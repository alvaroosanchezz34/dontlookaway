# Prompt: luz, sombras, blackouts macabros y grano de cámara antigua (referencia: MONOCHROME)

Copia todo lo que hay debajo de la línea en una sesión nueva de Claude Code
abierta sobre este repositorio, en la rama `claude/epic-cannon-fcf3p3` (la
de la pasada de coherencia). Si tienes capturas o vídeos de MONOCHROME,
guárdalos antes en `docs/img/reference/monochrome/`: el prompt le pide al
agente que los mire.

---

Eres el desarrollador de **DON'T LOOK AWAY**, un juego de terror cooperativo
para Roblox hecho con Rojo y Luau. Antes de nada lee `README.md`,
`docs/FALLOS_PENDIENTES.md` (sobre todo el apartado 9, la pasada de
coherencia que acaba de entrar en esta rama) y `docs/VISUAL_OVERHAUL_V2.md`.
Si existe `docs/img/reference/monochrome/`, mira todas las imágenes: son la
referencia visual y mandan sobre lo que digo abajo.

El objetivo de esta pasada es **visual**: que la luz y las sombras sean
coherentes, que el menú principal tenga algo de luz tenue, que cada nivel de
blackout sea **más macabro sin ser más oscuro** y que la imagen tenga el
grano de una cámara antigua. La referencia de estilo es **MONOCHROME**, el
juego de terror de Roblox de @paramodal.

## La referencia: qué tomar de MONOCHROME

Lo que se sabe de su imagen (guías y miniaturas, no vídeo; si hay capturas en
la carpeta de referencia, contrasta todo esto con ellas):

- **Casi sin color.** Escenarios en escala de grises. El color, cuando
  aparece, significa algo.
- **Contraste duro pero legible.** La caída de la linterna es brusca, con un
  borde marcado entre la zona que buscas y la sombra profunda. Pero la
  oscuridad es un gris muy profundo con siluetas, no un negro de pantalla
  apagada: se intuye el espacio.
- **Grano analógico** sobre toda la imagen, como película o una cámara vieja.
- **La luz es del monstruo.** Las luces se atenúan y fallan cuando se acerca;
  un pasillo que se apaga es una señal, no un fondo. La visibilidad nunca está
  garantizada, pero siempre es *coherente*: si algo está oscuro, hay una razón
  que se ve (una lámpara muerta, una puerta, una pared).
- **El monstruo:** una silueta negra y alta con dos ojos blancos que se ven en
  la penumbra. Lo que da miedo es lo que casi se ve.

No copies nada de MONOCHROME (ni modelos, ni texturas, ni sonidos, ni su
monstruo). Toma el lenguaje visual: paleta, contraste, grano, el uso de la luz
como amenaza.

## Reglas de trabajo

1. Trabaja en la rama `claude/epic-cannon-fcf3p3`. Haz un commit por cada
   punto, con mensajes en inglés al estilo del repo (`Area: what is now true`).
2. Respeta el estilo del código: Luau con tipos, tabulaciones, comentarios en
   inglés que explican el porqué, servicios conectados mediante `Registry`.
   Los números ajustables van en `GameConfig` (añade un bloque
   `GameConfig.Visual` si hace falta), los colores en `Theme`, y las
   superficies y perfiles de luz en `VisualStandards`.
3. Todo lo visual es **local al cliente**, salvo los atributos que el servidor
   ya replica (`Power`, `Blackout`, `BlackoutSeed`, `Escape`…). No añadas
   tráfico de red por frame.
4. **No inventes IDs de assets.** Las texturas nuevas (grano, polvo,
   arañazos) se generan con un script en `tools/` y se dejan a `0` en
   `AssetIds` hasta que se suban. Con el ID a `0` el efecto tiene que fallar
   con elegancia: o se desactiva o usa una alternativa que no dependa de
   assets.
5. Accesibilidad: con `reducedEffects`, nada parpadea a más de 3 Hz, no hay
   estrobos y los pulsos son más lentos y suaves. El brillo del usuario
   (`AccessibilityController`) sigue funcionando. El grano tiene su propio
   ajuste (activado/desactivado e intensidad).
6. Rendimiento: el juego se juega en móvil. El grano son una o dos
   `ImageLabel`, no cientos de frames. Ningún bucle recorre el workspace
   entero por frame.
7. No toques `src/marketing/` ni el diseño del Observer (forma, mallas,
   piel). Puedes usar sus ojos en efectos, pero no cambiar el rig.
8. Si algo necesita una decisión de diseño (**DECIDIR**), aplica la opción
   recomendada, escríbela en la cabecera del módulo y menciónala al final.

### Herramientas (ya probadas en esta rama)

- Lune **0.10.x** (0.8.x se cuelga). Rojo 7.6.1 no reconoce
  `SurfaceAppearance.AlphaMode = "Opaque"`: construye el place de prueba desde
  una copia de `src/` con `"Overlay"`, en formato binario `.rbxl`.
- Análisis estático: `luau-lsp analyze --platform=roblox
  --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src`.
- `tools/runtime_test.luau`, `tools/client_test.luau`,
  `tools/validate_map.luau`, `tools/zfight.luau` y **`tools/light_study.luau`
  + `tools/light_study.py`**, que exporta una sala y estima niveles de luz:
  úsalo para medir antes y después.
- Fallos que ya existían y no son tuyos: la sección «the observer: reference
  silhouette» de `runtime_test` y las cinemáticas de muerte de `client_test`.

## Antes de tocar nada: mide

Con `tools/light_study.luau` exporta como mínimo la recepción (`G_r`), un
pasillo y un despacho, con la semilla 42, en NORMAL, EMERGENCY y blackout
1-4. Guarda una tabla en `docs/LIGHTING_MONOCHROME.md` con la luminancia
estimada en el centro de un charco de luz, en el borde, a medio camino entre
dos lámparas, en una sala sin lámpara y junto a una pared que separa una sala
iluminada de otra a oscuras. Esa tabla es tu línea base. Al final repítela.

## A. Sombras y oscuridad coherentes

**El síntoma:** zonas en las que no se ve nada justo al lado de otras muy
iluminadas, sin una razón visible. Todo esto está en el código, compruébalo:

### A1. Qué lámparas proyectan sombra es aleatorio

- `src/server/Map/MapBuilder.luau` (`addFixture` y su llamada por tipo de
  sala): en los pasillos solo una de cada tres lámparas tiene sombras
  (`shadows = index % 3 == 1`); en las salas, solo la primera
  (`shadows = placed == 0`).
- Una luz sin sombras **atraviesa paredes, puertas y muebles**. Por eso una
  sala recibe luz de la de al lado a través del muro, mientras su vecina,
  iluminada por una lámpara con sombra, queda correctamente a oscuras. El
  resultado parece arbitrario.
- El relleno (`PointLight` «Light», 11-18 studs, sin sombras) de cada lámpara
  también traspasa paredes. La luna «wash» (`VisualStandards.Moonlight`, sin
  sombras) igual.

**Arreglo:**

- **Ninguna luz ilumina a través de una pared.** Toda luz que llegue a otra
  sala, o lleva sombras, o se recorta: su `Range` no pasa de la distancia a
  la pared más cercana más un margen. Calcula ese límite al construir la sala
  (tienes `room.cells` y el tamaño de la celda), no a ojo.
- Sustituye el reparto aleatorio por un **LOD de sombras en el cliente**: las
  N lámparas encendidas más cercanas a la cámara proyectan sombras (N según la
  calidad: por ejemplo 6 / 10 / 14, en `VisualStandards.Quality`) y el resto
  no, pero esas otras ya no traspasan paredes gracias al recorte. Con
  histéresis para que las sombras no salten.
- Con la calidad baja hoy se quitan todas las sombras de las lámparas
  (`AccessibilityController.applyShadows`). Deja al menos la lámpara más
  cercana y la linterna con sombra, y recorta los rangos.
- La luna «wash» también se recorta a la sala por la que entra.

### A2. Luces que se apagan de golpe por distancia y salas oscuras por azar

- `LightController`: más allá de `lightLod` (70 / 95 / 120 studs) la luz se
  desactiva de golpe aunque el tubo siga brillando. Un tramo lejano de pasillo
  se vuelve negro de repente. **Arreglo:** atenúa el brillo en el último 20 %
  de la distancia y añade histéresis.
- Las lámparas `dead` (8 %) y `flicker` (20 %) se reparten al azar, y en los
  pasillos una de cada tres va al circuito `EMERGENCY`. Puede quedar una sala
  o un tramo entero sin luz que funcione, sin intención. **Arreglo:** cada
  sala y cada tramo de 2-3 lámparas de pasillo tiene al menos una lámpara
  `on`, salvo las salas diseñadas para estar a oscuras (márcalas con un
  atributo y documéntalas). Una lámpara muerta tiene que **verse muerta**
  (tubo apagado y sucio) para que la oscuridad tenga una razón.

### A3. El suelo de la oscuridad: gris profundo, no negro

- Ahora `NORMAL` tiene un ambiente de (7, 7, 8) y `EnvironmentDiffuseScale`
  0,08. Entre dos charcos de luz el resultado es negro puro, justo al lado del
  centro del charco: es el contraste que se lee como «roto».
- **Objetivo MONOCHROME:** contraste fuerte y oscuridad profunda, pero con
  siluetas legibles a pocos studs. Sube el suelo un poco y de forma uniforme
  (ambiente gris neutro y algo de `EnvironmentDiffuseScale`), y alarga la
  caída de cada charco (`VisualStandards.Fixtures`) para que el paso de luz a
  oscuridad sea un degradado, no un corte.
- Fíjalo con números en `docs/LIGHTING_MONOCHROME.md`: proporciones máximas
  entre el centro de un charco, el punto medio entre charcos y una sala sin
  lámpara. Comprueba que se cumplen con `light_study`.
- La oscuridad sigue siendo un problema que resuelve la linterna: sin ella, a
  más de unos studs, no se distingue nada.

### A4. La linterna: un haz duro, una sola sombra

- `FlashlightController`: la linterna local lleva dos `SpotLight` con sombras
  (`Core` y `Spill`) más un relleno; cada linterna de un compañero lleva otra
  con sombras. Varias sombras superpuestas, desplazadas unas de otras.
- **Arreglo:** una sola fuente con sombra por linterna (el haz principal). El
  halo exterior sin sombras y con rango corto. Borde del haz marcado, caída
  rápida: el «harsh falloff» de MONOCHROME. De los compañeros, solo las 1-2
  linternas más cercanas proyectan sombra.

### A5. Lo que se ve y lo que el juego cree que se ve tienen que coincidir

- En la pasada anterior, `LightingService:IsDark` / `IsLit` deciden si el
  Observer queda congelado (hay que verlo para pararlo en la oscuridad).
  Pero qué lámparas siguen encendidas en un blackout lo decide **solo el
  cliente** (`LightController`, `hashFrac(seed, BlackoutSeed)`).
- **Arreglo:** pasa a un módulo compartido (por ejemplo
  `src/shared/LightingRules.luau`) la regla de si una lámpara está encendida
  con un `Power`, un `Blackout`, un `BlackoutZone` y un `BlackoutSeed` dados.
  El cliente la usa para pintar y el servidor para `IsDark(position)` (¿hay
  una lámpara encendida que llegue aquí?). Así, si el jugador ve luz, el
  juego también la ve.
- Esto es imprescindible para el punto C: si los blackouts dejan de ser más
  oscuros, «oscuro» ya no puede significar «nivel ≥ 3».

## B. El menú principal: un poco más de luz, tenue

- La cámara del menú (`MenuController.menuCamera`) recorre el edificio con
  planos lentos (`SHOTS`). Entre rondas el edificio se queda **sin
  corriente** (`RoundService.returnToLobby` llama a `SetPower(false)`), la
  luz es la del preset `LOBBY` y encima hay una franja negra al 85 % sobre la
  mitad izquierda (`buildMain`, `shade`). Resultado: el menú se ve casi negro.
- **Arreglo, solo en el cliente y solo mientras `State.status == "MENU"`:**
  - Un preset `MENU` en `LightingService.Presets` que el cliente aplica en
    local: ambiente gris tenue, exposición apenas por encima de `NORMAL`, el
    grado frío y casi sin color de MONOCHROME. Al salir del menú se restaura
    el preset que mande el servidor.
  - Para cada plano de `SHOTS`, una o dos luces prácticas **locales** que
    justifiquen la luz: una bombilla desnuda que oscila un poco, un haz de luna
    por una ventana, una lámpara de emergencia. Tenues, cálidas o neutras, con
    sombras y con un parpadeo lento. Se crean al entrar en el menú y se
    destruyen al salir. Nada se replica.
  - Menos negra la franja del título (que el texto siga leyéndose).
  - El grano del punto D también en el menú: es la identidad del juego.
- Comprueba que el lobby (Field Office) no cambia y que al pulsar PLAY no
  queda ninguna luz del menú encendida.

## C. Blackouts 1-4: cada nivel más macabro, no más oscuro

**La regla:** la luminancia media de la escena **no baja** de un nivel al
siguiente (mídelo con `light_study`; tolerancia pequeña). Lo que sube es lo
inquietante: el ritmo, el color, lo que aparece en la luz y el sonido. El
negro total sigue siendo solo el del jumpscare.

Hoy cada nivel es básicamente más oscuro (`BLACKOUT_SAG` en
`LightController`, `BLACKOUT` en `LightingService.Presets`, los blackouts en
`HorrorDirector.maybeBlackout`). Rehazlo así (ajusta los detalles, pero
respeta la escalada):

| Nivel | Nombre | Qué pasa |
|---|---|---|
| 1 | Falla | Las lámparas zumban, tartamudean y vuelven. El grano sube un poco. Sonido eléctrico. Nada más: es el aviso. |
| 2 | Respira | Las lámparas que siguen encendidas laten despacio y a la vez, como una respiración (~0,25 Hz). El color se va hacia un blanco enfermizo. Las puertas cercanas crujen solas. En los charcos de luz, durante un instante, la sombra de alguien que no está. |
| 3 | Late | Las lámparas laten con un doble golpe, como un corazón, y la emergencia se vuelve roja (el único color de la pantalla). Las lámparas de un pasillo se encienden en secuencia **hacia el jugador**. Entre latido y latido, una silueta en el borde del charco durante un fotograma. Susurros. |
| 4 | Mira | Las lámparas de la sala se apagan una a una, de lejos a cerca, y vuelven. En la penumbra del borde de la luz, dos ojos blancos (los del Observer, en local y sin colisión) que desaparecen al mirarlos. El grano tiembla, la viñeta se cierra, el latido se oye. Nunca negro total. |

- **El sentido de MONOCHROME:** la luz es del monstruo. Cuando el Observer
  está cerca (`ObserverProx`), las lámparas a su alrededor se atenúan y
  tartamudean aunque no haya blackout. Es un aviso que se lee, igual que su
  respiración.
- Las siluetas y los ojos son paranoia, no anomalías: no se pueden reportar y
  no cuentan (reutiliza `ParanoiaController` / `HorrorDirector.Paranoia`).
- Actualiza las cabeceras de `LightController` y `LightingService` (que
  describen cada nivel como más oscuro), y la prueba de la pasada anterior que
  exige que el nivel 4 sea más oscuro que la emergencia
  (`tools/runtime_test.luau`, sección «lighting»): ahora la regla es la
  contraria.
- Con A5 hecho, `IsDark` sale de las lámparas encendidas de verdad. Comprueba
  que el Observer sigue siendo justo en cada nivel (`DarkSightRange`,
  `ReactionTime`).
- Con `reducedEffects`: sin el encendido en secuencia rápido, los pulsos a
  menos de 1 Hz y sin siluetas de un fotograma.

## D. Grano y efecto de cámara antigua

Un controlador de cliente nuevo (por ejemplo
`src/client/Controllers/FilmController.luau`) con todo esto, siempre activo
salvo que el jugador lo desactive:

1. **Grano.** Una o dos `ImageLabel` a pantalla completa con una textura de
   ruido en mosaico (`ScaleType = Tile`), por encima del mundo y **por
   debajo** del HUD (el HUD no es parte de la película). A 24 fps cambia de
   fotograma (atlas de 4-8 ruidos) y de desplazamiento al azar. Dos capas, una
   clara y una oscura, para que el grano suba y baje la imagen. Más visible en
   la oscuridad, como en una película real: la intensidad depende del nivel
   de blackout y del miedo (`State.fear`).
2. **Viñeta y suciedad.** Integra la viñeta que ya tiene `EffectsController`
   (no dupliques) y añade de vez en cuando una mota de polvo o un arañazo
   vertical que dura un fotograma.
3. **Parpadeo de proyector.** Variaciones mínimas y aleatorias del brillo del
   grado (±0,01) a 24 Hz. Desactivado con `reducedEffects`.
4. **Gate weave.** Un temblor de encuadre casi imperceptible (fracciones de
   grado) en `CameraController`. Desactivado con `reduceMotion`.
5. **Color.** Lleva la saturación general hacia el gris de MONOCHROME
   (**DECIDIR**, recomendado: entre -0,85 y -0,9 en `NORMAL`, dejando que el
   rojo de emergencia y de peligro sea lo único con color). Comprueba que
   los modos de color de accesibilidad siguen distinguiendo el peligro.
6. **Halo.** Un poco de bloom en las fuentes de luz (tubos, bombillas), como
   la halación de la película. Sin lavar la imagen.

Assets:

- Escribe `tools/gen_film.py` (numpy y PIL, como `tools/gen_textures.py`):
  genera en `assets/film/` el atlas de grano (ruido gaussiano en mosaico sin
  costuras, gris medio, 256×256 por fotograma), una hoja de polvo y arañazos y,
  si hace falta, una viñeta. Añádelos a `tools/upload_assets.py` y deja sus
  IDs a `0` en `AssetIds.Film`.
- Mientras el ID sea `0`, intenta una alternativa sin assets: un ruido
  generado en tiempo de ejecución con `EditableImage`
  (`AssetService:CreateEditableImage`), dentro de un `pcall` porque puede no
  estar disponible. Si falla, el grano se desactiva y se avisa una vez en la
  Output.
- Ajustes nuevos en Settings → Graphics: «Film grain» (on/off) e intensidad.
  Guárdalos como el resto de ajustes (`SettingsService`, `State.settings`).
- Los sustos (`ScareController`) suben el grano durante el golpe. La pantalla
  de resultados y el menú lo mantienen.

## Verificación

- Repite la tabla de `docs/LIGHTING_MONOCHROME.md` con los mismos puntos y
  compárala con la línea base: tienen que cumplirse las proporciones de A3 y
  la regla de C (la luminancia no baja de un nivel al siguiente).
- Pruebas nuevas en Lune:
  - `LightingRules` da el mismo resultado en el cliente y en el servidor
    para varias semillas y niveles;
  - ninguna luz sin sombras alcanza más allá de la pared de su sala (con las
    salas de 20 semillas);
  - cada sala y cada tramo de pasillo tiene al menos una lámpara `on`;
  - el preset `MENU` se aplica en el menú y se restaura al salir, y no
    quedan luces del menú;
  - el grano crea como mucho dos `ImageLabel`, respeta el ajuste y se
    desactiva con el ID a `0` si no hay `EditableImage`.
- `validate_map`, `zfight`, `client_test` y `runtime_test`: sin fallos
  nuevos (compara contra los que ya existían).
- **En Studio** (deja la lista en `FALLOS_PENDIENTES.md`): recorrer un pasillo
  y dos salas contiguas en NORMAL y en cada blackout; el menú principal; el
  grano en PC y en móvil; los FPS con el MicroProfiler antes y después.

## Resumen final que debes entregar

Una tabla con cada punto (A1-A5, B, C, D) con: hecho / parcial / no, commit,
cómo se verificó y las decisiones **DECIDIR** que tomaste. Añade la tabla de
luminancias de antes y después.
