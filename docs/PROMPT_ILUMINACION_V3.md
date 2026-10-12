# Pasada de iluminación v3: menos luz, contraste más suave, blackouts más oscuros, sin pop-in y menos grano

Proyecto: Don't Look Away (Roblox, Luau, Rojo). Antes de tocar nada lee
docs/LIGHTING_MONOCHROME.md y docs/PROMPT_ILUMINACION_MONOCHROME.md para
entender cómo está montada la luz ahora y cómo se mide. Esta pasada cambia
parte de esa filosofía (los blackouts ya no deben mantener la misma luz), así
que actualiza los comentarios de cabecera y la documentación donde digan lo
contrario.

Archivos implicados:

- src/server/Services/LightingService.luau (presets, BLACK_FLOOR, lifted(), Base, IsDark)
- src/shared/LightingRules.luau (LEVEL_MEAN, ALARM_LIT_GAIN, evaluate)
- src/client/Controllers/LightController.luau (LOD de luces, sombras, buckets)
- src/shared/VisualStandards.luau (Fixtures: ratio/range de main y fill; Quality: lightLod, shadowLights)
- src/client/Controllers/FilmController.luau (grano)
- src/client/Controllers/AccessibilityController.luau y donde se guarde el valor por defecto de grainIntensity (DataService / SettingsService)

Mide antes de cambiar nada con tools/light_probe.luau + tools/light_probe.py
(semilla 42, mismos puntos y vistas que en LIGHTING_MONOCHROME.md) y guarda la
tabla como línea base. Al terminar vuelve a medir y añade una sección nueva al
doc con el antes y el después.

## 1. Bajar la iluminación general

Ahora mismo en NORMAL un suelo gris debajo de una lámpara sale a ~0,33 en
pantalla. Quiero el juego en general más oscuro, en torno a 0,20-0,24 debajo
de una lámpara del pasillo, sin que las zonas sin lámpara se queden en negro
puro.

- Baja ExposureCompensation en los presets de interior (NORMAL, CINEMATIC,
  BREATH, HEARTBEAT, BLACKOUT, ESCAPE, EMERGENCY), que ahora están todos a 0,8.
  Prueba en el rango 0,4-0,55.
- Revisa Lighting.Brightness (0,6 en LightingService.Base) y el Ambient de
  cada preset. LOBBY, OUTSIDE y RESULTS se quedan como están.
- No toques el ajuste de brillo del jugador (AccessibilityController), sigue
  siendo el único margen que tiene el usuario.

## 2. Contraste luz/sombra más homogéneo

Ahora el charco de luz tiene un centro muy fuerte y cae deprisa. Quiero menos
diferencia entre el centro del charco y la zona entre dos lámparas: más
penumbra, menos pico.

- En VisualStandards.Fixtures reparte mejor la luz entre main y fill: baja el
  ratio de main (sobre todo pendant, que está a 1,8) y sube algo el fill y su
  range, para que la luz llegue más uniforme al suelo y a las paredes.
- Revisa ShadowSoftness (0,5) por si conviene subirlo un poco para bordes de
  sombra más suaves.
- Revisa el Contrast de los presets y el levantamiento de negros (lifted() y
  BLACK_FLOOR). La idea es comprimir el rango: el centro del charco baja y la
  zona intermedia no cae a 0.
- Objetivo de medida en NORMAL: la relación entre "corridor: under a lamp" y
  "corridor: halfway between two lamps" en pantalla no debería pasar de 3:1, y
  el porcentaje de píxeles casi negros en la vista del pasillo no debe subir
  respecto a la línea base aunque la media baje.

## 3. Blackouts con menos luz

Ahora LightingRules.LEVEL_MEAN deja todos los niveles al 0,9 y los presets de
blackout tienen la misma exposición que NORMAL, así que un blackout no se ve
más oscuro. Quiero que cada nivel quite luz de verdad, manteniendo los
comportamientos de cada uno (tartamudeo, respiración, latido, apagado de lejos
a cerca).

- LEVEL_MEAN escalonado, como punto de partida: 1 → 0,75, 2 → 0,6, 3 → 0,45,
  4 → 0,35. Ajusta después de ver cómo queda.
- Exposición de BREATH, HEARTBEAT y BLACKOUT por debajo de la de NORMAL, cada
  una un poco menos que la anterior.
- En LightController, en el nivel 4 hay un `brightness *= 1.1` para las
  lámparas que siguen encendidas: quítalo.
- ALARM_LIT_GAIN (3) hace que las luces de emergencia rojas en niveles 3-4
  alumbren tanto como las blancas. Bájalo para que el rojo sea un acento, no
  la fuente principal.
- EMERGENCY (sin corriente) también un poco más oscuro, pero que con la
  linterna se siga pudiendo jugar.
- LightingService:IsDark usa evaluate con steady y LitFraction para decidir
  dónde está oscuro (la velocidad del Observer y otras mecánicas dependen de
  eso). Comprueba que con la luz más baja lo que el servidor considera "con
  luz" sigue coincidiendo con lo que se ve. Si una lámpara a 0,35 de su brillo
  ya no ilumina de forma visible, IsDark tiene que tenerlo en cuenta (por
  ejemplo reduciendo el alcance efectivo según el brillo).

## 4. Que las zonas de luz estén renderizadas antes de que llegue el jugador

Al avanzar por un pasillo se ve cómo las luces y sus sombras aparecen de
golpe delante del jugador. Causas probables en LightController:

- LOD de luces: más allá de LOD_DISTANCE (70/95/120 según calidad) la luz se
  apaga, y solo se desvanece en el último 20 %.
- Sombras: pickShadowed solo da sombras a las N lámparas más cercanas y se
  recalcula cada 0,35 s. Las que no tienen sombras tienen el range recortado a
  wallDist, así que cuando una lámpara pasa a tener sombras cambia de golpe el
  range y el sombreado.
- Las lámparas lejanas se evalúan por buckets (una de cada 8 por frame).

Cambios que quiero:

- Que el LOD tenga en cuenta hacia dónde mira y se mueve la cámara: las
  lámparas delante del jugador se activan antes (más distancia en la dirección
  de la vista y del movimiento) y las de detrás pueden apagarse antes para
  compensar el coste.
- Banda de fundido más ancha (30-40 % en vez de 20 %), para que no se note el
  encendido.
- Elegir las lámparas con sombra por cercanía a una posición adelantada
  (cámara + dirección de movimiento × unos studs), no solo por la posición
  actual, y con más histéresis para que no salten.
- Cuando una lámpara cambie entre con sombra y sin sombra, interpola el range
  y el brillo en unos frames en vez de cambiarlo en uno.
- Future lighting tarda algún frame en resolver la sombra de una luz recién
  activada: activa las luces con suficiente antelación para que cuando el
  jugador llegue ya estén asentadas.
- No subas el número de luces activas a lo loco: comprueba el rendimiento en
  calidad 1 (móvil) y mantén los presupuestos de VisualStandards.Quality o
  ajústalos con cabeza.
- El apagado de lejos a cerca del nivel 4 es intencionado, no lo trates como
  pop-in.

## 5. Grano de pantalla más suave

El grano tiene demasiado ruido. En FilmController:

- amount() parte de 0,55, suma 0,6 sin corriente y level × 0,12 en blackouts,
  y el alpha final se limita a 0,6. Baja la base (≈0,3), reduce mucho el
  extra por oscuridad (con la escena más oscura, el grano extra se nota el
  doble) y baja el tope a ≈0,3.
- Baja el valor por defecto de grainIntensity de 0,5 a ≈0,3, y comprueba si
  hay jugadores con el 0,5 ya guardado en sus datos. Si el 0,5 viene del
  default y no de una elección del jugador, migra al nuevo valor.
- Comprueba qué modo de grano se está usando (FilmController:Mode()). Si es
  "specks", el multiplicador `alpha * 3` y los specks de 2 px hacen que se vea
  mucho más ruidoso que con textura: bájalo y deja solo specks de 1 px. Si los
  assets de AssetIds.Film no están subidos, avísame.
- Mantén el pico de grano en los sustos (Spike), pero algo más corto.
- Las motas y rayas de polvo (dirt) pueden quedarse, pero reduce un poco su
  frecuencia.

## Comprobación

- Pasa tools/runtime_test.luau y tools/client_test.luau y arregla lo que
  rompa (hay tests que pueden comprobar valores de LEVEL_MEAN o del grano).
- Medida final con light_probe en NORMAL, B1-B4 y EMERGENCY. Cada nivel de
  blackout tiene que salir más oscuro que el anterior, sin que la vista del
  pasillo llegue al 100 % de negro en B4.
- Capturas en Studio del pasillo principal y de G-02 en NORMAL, B2, B4 y
  EMERGENCY, antes y después.
- Recorre un pasillo largo en calidad 1 y 3 y confirma que las luces de
  delante ya están encendidas y con su sombra cuando entras en ellas.
- Resume al final qué valores cambiaste y en qué archivo, con el valor
  anterior y el nuevo.
