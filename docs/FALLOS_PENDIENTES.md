# Fallos pendientes

> **Pasada de coherencia** (rama `claude/epic-cannon-fcf3p3`, guion en
> `PROMPT_CORRECCIONES.md`): al final de este documento está lo que se
> arregló y lo que queda por comprobar en Studio.

Apuntados en la rama `fixes/vega`, sin arreglar todavía. En cada uno: dónde
creo que está, qué creo que lo causa y cómo comprobarlo en Studio. Son
hipótesis sacadas de leer el código y de medir los archivos, no de verlo en
Studio.

## 0. Recursos subidos por otra cuenta (probable causa de varios fallos)

> **Comprobado el 18-10-2026 en Studio: no hace falta subir nada.** Los 195 IDs
> de `AssetIds.luau` (materiales, calcomanías, grano, audio, Observer, pieles y
> las 17 mallas de props con sus mapas) son del grupo Unreality Works, y en Play
> carga todo: "10 meshes loaded" y "prop meshes: 17 of 17 in use". El aviso de
> `rbxassetid://203785492` no es del juego (no está en ningún script ni
> propiedad del place): lo carga Studio. Lo de abajo queda como historial.

**Visto en Studio:** con los modelos del Observer que subió la otra cuenta,
en tu place solo cargó la cabeza que subiste tú. El cuerpo salió con el rig
de piezas de emergencia. Ya está corregido: `AssetIds.Observer.models` apunta
a los 10 modelos que has subido tú.

**Dónde más pasa:** `src/shared/Config/AssetIds.luau`. Todos los grupos de
IDs (`Materials`, `Decals`, `Audio`, `PropMeshes`, `PropMeshPool`) los subió
la otra cuenta.

**Causa probable:** un juego solo puede cargar con `InsertService` y
`CreateMeshPartAsync` los modelos y mallas de su propio dueño, y el audio es
privado por defecto. En tu place:

- las mallas de los props no cargan, y cada prop se queda con sus piezas de
  `SmoothPlastic`. Eso encaja con los «gráficos de plástico en casi todas las
  habitaciones» (puntos 3 y 6);
- el audio puede quedarse mudo.

Las imágenes (texturas) suelen cargar desde cualquier cuenta, pero conviene
comprobarlo igual.

**Cómo comprobarlo:** dale a Play y busca en la Output `could not load mesh`,
`not authorized`, `Failed to load` o `Asset is not approved`. Mira también si
los muebles se ven como cajas. Si es así, la solución es la misma que con el
Observer: subir desde tu cuenta (o la del grupo dueño del juego)
`assets/props/*.obj` y los `.ogg` de `assets/audio/`, y pasarme los IDs.

## 1. Tirones de pantalla — ARREGLADO EN CÓDIGO (`e53a5b6`), falta verlo en Studio

**Arreglo:** el cuerpo gira con un `AlignOrientation` (en el paso de física)
en vez de escribir `root.CFrame` en cada frame; `DetailLOD` tiene un margen
de ±10 % y cambia como mucho 4 grupos por pasada, los más cercanos primero;
`LightController` recoge las luces `PoweredLight` una vez por mapa y evalúa
los fixtures lejanos en 8 tandas, una por frame. La cámara sigue usando
`head.Position`: con la física a 240 Hz y sin la pelea del `CFrame` no
debería dar saltos; si a 144 Hz todavía se nota, el siguiente paso es
interpolarla. **Comprobar:** el paso 2 de abajo (60 Hz frente a 144 Hz).

**Dónde (antes)**

- `src/client/Controllers/CameraController.luau:173`: en cada frame de render
  se escribe `root.CFrame` del personaje para que siga el giro de la cámara.
- `src/client/Controllers/CameraController.luau:197`: la cámara se coloca en
  `head.Position`, que es la posición del último paso de física, sin
  interpolar.
- `src/client/Controllers/LightController.luau:346` (`applyPowered`):
  recorre `Workspace:GetDescendants()` entero cada vez que cambia `Power`.
- `src/client/Controllers/LightController.luau:429`: cada 0,35 s se evalúan
  todos los fixtures lejanos en el mismo frame.
- `src/client/Controllers/DetailLOD.luau:70`: el detalle de cada sala se
  oculta y se muestra de golpe al cruzar la distancia de LOD.

**Causa probable**

- La principal: escribir el CFrame de un cuerpo con física desde
  `RenderStepped` pelea con la simulación (60 Hz). Con monitores de más de
  60 Hz, la cámara pegada a la cabeza da saltitos de un frame.
- Los recorridos de todo el mapa causan picos de un frame al cambiar la luz.
- El LOD del detalle hace que aparezca y desaparezca de golpe.

**Cómo comprobarlo**

1. Abre el MicroProfiler (Ctrl+F6) y anda en línea recta por un pasillo.
   Si hay picos periódicos cada ~0,35 s, es el bucle de fixtures. Si el pico
   llega al cambiar `Power` o al empezar un apagón, es `applyPowered`.
2. Pon el monitor a 60 Hz y luego a 120/144 Hz. Si el temblor solo se ve a
   más de 60 Hz, es la cámara pegada a la física.
3. Para descartarlo: comenta la línea 173 de `CameraController` y gira
   andando. Si el temblor desaparece (aunque el cuerpo ya no gire), es eso.

## 2. La luz de los blackouts — ARREGLADO (`54096d0`)

**Visto en Studio (antes):** en un apagón de nivel 4, sin linterna, el pasillo
entero se leía con claridad, todo teñido de rojo. La linterna apenas cambiaba
nada.

**Causa:**

- la luz de adaptación: una `PointLight` sin sombras de hasta 22 studs que
  seguía a la cámara;
- el preset `BLACKOUT`, con ambiente (19, 20, 27) y exposición +0,45;
- los focos de las balizas a 2,2.

**Arreglo:**

- `LightController.luau`: fuera la luz de adaptación y su grade. Las balizas
  bajan a 0,8 / 0,5 (`:241`, `:245`).
- `LightingService.luau:66` y `:96`: `EMERGENCY` y `BLACKOUT` sin ambiente de
  relleno, sin subida de exposición y sin bruma gris.
- `AccessibilityController.luau:86`: el ajuste de brillo sigue funcionando,
  en ±0,04.

**Ahora:** sin linterna solo se ven los tubos que quedan encendidos, los
rótulos de salida, las cúpulas de las balizas y las siluetas más cercanas.
Hace falta la linterna. La batería no cambia; en NIGHTMARE queda justa
(unos 11 min de luz continua con todas las pilas encontradas).

## 3. Gráficos de plástico en casi todas las habitaciones — ARREGLADO EN PARTE (`b00ede2`)

**Arreglo:** ninguna pieza visible es `SmoothPlastic` (63 en `Props.luau`,
las superficies `porcelain`, `grime`, `paper` y `plastic` de
`VisualStandards` y detalles del mapa, el lobby y los pickups). Cada una usa
el material del que está hecha. `EnvironmentSpecularScale` ya estaba a 0,5.
**Sigue pendiente:** el punto 0 (mallas de props subidas por otra cuenta) y
el punto 6 (rugosidad).

**Dónde (antes)**

- `src/server/Map/Props.luau`: 63 piezas con `Material.SmoothPlastic`.
- `default.project.json:98-115`: `MaterialService` solo sustituye Plaster,
  Carpet, CeramicTiles, Concrete, WoodPlanks, Brick, Marble, Metal, Wood,
  Fabric y CorrodedMetal. `Plastic` y `SmoothPlastic` se quedan con el
  material de Roblox.
- `src/server/Services/LightingService.luau:124`: `EnvironmentSpecularScale
  = 1`, con brillo especular del cielo al máximo.

**Causa probable**

- Todo lo que está construido con `SmoothPlastic` (muebles y props sin
  malla, detalles) se ve como plástico liso con brillo.
- Con especular al máximo, cualquier superficie oscura y poco rugosa tiene
  ese brillo. Es lo que le pasaba a la piel vieja del Observer.

**Cómo comprobarlo**

1. En una sala cualquiera, selecciona varias cosas que parezcan plástico y
   mira su `Material` en Properties. Si son `SmoothPlastic` sin
   `MaterialVariant`, es esto.
2. Baja `Lighting.EnvironmentSpecularScale` a 0,3 en Studio y compara.

## 4. El bicho es un plagio de otro juego

**Dónde:** `docs/OBSERVER_REDESIGN.md` se titula «rediseño según la imagen
de referencia». `docs/OBSERVER_V2.md` reconoce que la silueta anterior
«reproducía la imagen de referencia tal cual». La imagen no está en el
repositorio.

**Lo que ya cambió en esta rama:** la cabeza ha perdido las alas, que eran
el rasgo más llamativo de esa silueta. Ahora es un cráneo alargado. Los ojos
son otros y la piel también.

**Necesito que me digas:**

- de qué juego es la criatura;
- qué rasgos crees que siguen siendo copiados (proporciones, brazos largos
  hasta la espinilla, ojos pequeños, postura, forma de moverse…).

No he rediseñado nada más.

## 5. Sombras raras en el suelo durante los blackouts — ARREGLADO (`a0e2354`)

**Causa demostrada:** tu propio cuerpo oculto. Medido en Studio durante un
apagón de nivel 4:

- las únicas luces con sombras encendidas eran las dos de tu linterna
  (`Core` y `Spill`). Las de emergencia, las balizas, la luna y la luz de
  adaptación tienen `Shadows = false`, así que no pueden crear sombras;
- quieto, ninguna luz entró ni salió del LOD (0 cambios en 4 s);
- `LocalTransparencyModifier` oculta el cuerpo pero no quita su sombra. Las
  17 piezas del personaje tenían `CastShadow = true`. Al mirar al suelo
  (-65°), la cabeza invisible tapaba el 33 % del haz de la linterna y dejaba
  una mancha oscura en el suelo que se movía contigo.

**Arreglo:** `CameraController.luau:131`: las piezas ocultas tienen
`CastShadow = false`. La propiedad no se replica, así que tus compañeros
siguen viendo tu sombra.

**Comprobado en Studio:** 0 piezas del cuerpo con sombra, y 0 % del haz
tapado a -65°.

## 6. Texturas de plástico en las salas — PENDIENTE (hay que volver a hornear y subir)

**Dónde:** los mapas de rugosidad de los props horneados en Blender
(`tools/blender/dla_blender.py:444-471`, margen de 8 px e islas con margen
0,004). Medido en `assets/props/*/*_roughness.png`, el porcentaje de píxeles
a 0 (negro) es:

| Mapa | Píxeles a 0 |
|---|---|
| Baseboard | 57 % |
| Cornice | 73 % |
| DadoRail | 75 % |
| DoorCasing | 60 % |
| MetalShelf | 24 % |

**Causa probable:** rugosidad 0 es un espejo. Fuera de las islas UV el mapa
está a 0, y con los mips (en cuanto el objeto se aleja) ese 0 se mezcla en
los bordes de las islas. Salen bordes brillantes y un brillo general de
plástico en zócalos, cornisas, molduras y marcos.

**Arreglo probable (no hecho):** lo mismo que he hecho con el Observer:
rellenar el fondo con un valor de rugosidad neutro, margen `EXTEND` más
ancho e islas con más separación. Después, volver a subir esos mapas.

**Cómo comprobarlo:** mira un zócalo o una cornisa desde 10–15 studs con la
linterna. Si los bordes y las aristas brillan como plástico mojado y de
cerca no, es esto.

## 7. Inconsistencias e incoherencias — ARREGLADO (`145c3ee`, `8423b1b`, `b1a588c`)

- `OBSERVER_REDESIGN.md` ahora dice claramente que es histórico y remite al
  código (`145c3ee`).
- El aviso de mallas del Observer nombra la causa real: subida antigua, id
  sin segmento o error de carga; solo culpa a la propiedad si el error es de
  permisos (`8423b1b`).
- La regla queda escrita (README y cabecera de `LightingService`,
  `b1a588c`): la oscuridad es oscura; el único negro total es el del susto,
  a propósito y solo en tu pantalla.

Lo que había apuntado:

- `docs/OBSERVER_REDESIGN.md` todavía describe la cabeza como una hoja de
  4,6 studs y el susto a 3 studs. Está marcado como sustituido, pero
  confunde.
- `src/server/Services/ObserverService.luau:1258-1265`: si una malla del
  Observer no carga (por ejemplo, la cabeza vieja que ahora se descarta
  hasta que subas la nueva), avisa con «the place must be the published
  experience that owns them», que en ese caso no es la causa.
- `src/server/Services/LightingService.luau:8-12` dice que la oscuridad
  «nunca es negra». El susto ahora sí lo es, a propósito y en local. Hay que
  decidir si eso es la regla o la excepción y dejarlo escrito.

## 8. Errores de texturas

**Dónde**

- `src/shared/Config/AssetIds.luau`: todos los IDs de imagen.
- `tools/studio/check_image_ids.luau` y `tools/apply_image_fix.py`.

**Causa probable**

- Al subir una imagen, Roblox crea dos IDs: el del Decal y el de la Image que
  lleva dentro. `SurfaceAppearance`, `MaterialVariant` y `Decal.Texture`
  necesitan el de la Image. Con el del Decal fallan con «Asset type does not
  match requested type». Ya pasó con la piel del Observer (commit `36de6d8`).
- Si algún ID de `AssetIds.Materials` o de los props es de Decal, esa
  textura no carga y la pieza se queda con el material de Roblox: otra fuente
  de «plástico».
- También entra aquí el punto 6 (bordes de islas UV).

**Cómo comprobarlo:** abre la Output al darle a Play y busca «Asset type
does not match» o «Failed to load». Después pega
`tools/studio/check_image_ids.luau` en la Command Bar: lista cada ID que es
de Decal y su Image.

## 9. Pasada de coherencia: qué se arregló y qué falta ver en Studio

Hecho con pruebas de Lune (`tools/runtime_test.luau`, secciones «round
rules», «perception», «the observer: its breath», «the collapse», «scares»,
«lighting»), `luau-lsp analyze` sin errores nuevos, `validate_map` (0
problemas en 20 semillas) y `zfight` (los mismos 17 pares que antes).

| Punto | Commit | Qué cambia |
|---|---|---|
| A1 | `1e48c5b` | Llaves, fusibles, cassette y ofrendas caen donde muere o sale su portador (o vuelven a su sitio). |
| A2 | `ef25b42` | Las anomalías no cuentan como fallo con la cuota cumplida ni en la huida; las de la huida y la del tutorial nunca. |
| A3 | `d41cc92` | Finales propios: LOCKED IN (persiana) y THE NIGHT RAN OUT (tiempo). |
| A4 + A5 | `1dbaf01` | Ángulos con nombre (`GameConfig.Perception`), FOV real de cada cliente, un solo `IsDark`, y en la oscuridad el Observer solo se congela si se le ve. |
| A6 | `82667b5` | La respiración deja 1,2 / 0,9 / 0,6 s para girarse. |
| A7 | `1c5cadd` | El apagón total del COLLAPSE ocurre también sin corriente. |
| A8 | `4d4a684` | La caja cae fuera de la vista, en 0,4 s, tumbada en el suelo y nunca dentro de nada. |
| B1 | `732f90e` | ESCAPE y CINEMATIC no iluminan más que NORMAL; la exposición baja con cada nivel. |
| B2 | `e53a5b6` | Ver el punto 1. |
| B3 | `b00ede2` | Ver el punto 3. |
| B4 | `c24b8f2`, `1e3c38b` | Todos los colores de la interfaz salen de `Theme`. |
| C1-C6 | `b1a588c` … `145c3ee` | README, comentarios, tutorial, guía de controles, aviso de mallas, documentos del Observer. |

**Decisiones tomadas (DECIDIR del guion):**

- En la oscuridad mirar no basta: el Observer solo queda quieto si está a
  menos de 12 studs, en el haz de una linterna o junto a una barra de luz.
  Las anomalías siguen sin cambiar en la periferia aunque esté oscuro.
- Las anomalías que aparecen a la vista al empezar la huida y en el apagón
  total se quedan como excepción consciente, escrita en `AnomalyService` y
  el README.
- El apagón total sin corriente sigue la definición del nivel 4: apaga la
  mitad de las lámparas de emergencia y deja las balizas y los rótulos de
  salida (no los apaga, como sugería el guion).

**Comprobar en Studio:**

1. Girar andando a 60 y a 144 Hz: que el cuerpo siga a la cámara sin
   retraso visible y sin tirones (`AlignOrientation`).
2. En un apagón, mirar al Observer a 20 studs sin linterna: debe acercarse;
   con la linterna encima, debe quedarse quieto. Ajustar
   `GameConfig.Perception.DarkSightRange` si la partida se vuelve injusta.
3. Oír la respiración y girarse a tiempo en las tres dificultades.
4. Ver la caja tumbada (susto `falling_box`) y que no tape una puerta.
5. Mirar la huida y una escena cinemática: rojo y duro, no más claro.
6. Recorrer salas con props: papel, carteles, aseos y máquinas sin brillo de
   plástico.

**Pruebas que ya fallaban antes de esta pasada (no son de estos cambios):**
con Lune 0.10 la sección «the observer: reference silhouette» de
`runtime_test` y las cinemáticas de muerte de `client_test` fallan porque
las tablas indexadas por `Instance` no coinciden (Lune devuelve un objeto
nuevo en cada acceso). Lune 0.8.x se cuelga al cargar el place.


## 10. Pasada de luz, sombras y película (referencia MONOCHROME)

Guion en `PROMPT_ILUMINACION_MONOCHROME.md`; medidas de antes y después en
`LIGHTING_MONOCHROME.md`. Verificado con `runtime_test` (secciones «light»,
«blackouts», «film»), `client_test` (menú, película), `light_probe`,
`validate_map` y `zfight`, y sin errores nuevos de `luau-lsp`.

| Punto | Commit | Qué cambia |
|---|---|---|
| A5 | `cfc70d5` | `Shared/LightingRules`: una sola regla de qué lámpara luce; el `IsDark` del servidor lee las lámparas encendidas de verdad. |
| — | `fbb63d2` | `tools/light_probe` y la línea base; `light_study` gradúa la imagen final (antes aplastaba los oscuros a 0). |
| A1 + A2 | `5caba29` | Las lámparas más cercanas (2 / 10 / 14 según calidad) proyectan sombras; el resto se recorta a su sala (`WallDist`) y nunca ilumina a través de una pared; la luna sin sombras acaba en la sala; las lámparas lejanas se desvanecen; ninguna sala ni tramo de pasillo queda a oscuras por azar. |
| A3 | `d34f17d` | La oscuridad es gris profundo: exposición +0,8 y negros levantados. Entre dos lámparas: 0,16 (antes 0). |
| A4 | `a565246` | La linterna: un solo haz con sombra; halo corto sin sombra; solo las 2 linternas de compañeros más cercanas con sombra. |
| B | `5e5326b` | Menú: luz tenue local (`MenuLook`) con bombillas que se balancean. |
| C | `ac68fb7` | Blackouts 1-4 más macabros, no más oscuros (falla, respira, late, mira); lámparas que se apagan cerca del Observer. |
| D | `236ecf4`, `4126e8a` | Grano de película (`FilmController`), polvo y arañazos, parpadeo, gate weave, viñeta, casi monocromo, halo. |

**Decisiones tomadas (DECIDIR):**

- Saturación del interior entre -0,75 y -0,86 (NORMAL -0,82). El rojo de
  emergencia sigue leyéndose (probado).
- Las lámparas rojas de emergencia con corriente en los niveles 3-4 son un
  rojo algo menos saturado (255, 96, 80) y 3 veces más fuertes, para que el
  rojo no oscurezca la escena (el rojo lleva un cuarto de la luminancia del
  blanco).
- Con corriente, ningún blackout hace «oscuro» para el juego: el Observer
  solo tiene ventaja en la oscuridad sin corriente o donde no hay lámpara.
  El director sigue adelantando las cacerías en los blackouts 3-4 (ritmo, no
  visión).
- El nivel 2 ya no oscurece una planta (`BlackoutZone` se guarda pero no
  apaga nada).

**Completado después** (lo que estaba simplificado):

- Nivel 2: una puerta cercana se entreabre sola y cruje (solo en tu
  pantalla; la del servidor sigue cerrada; nunca una puerta cerrada con llave).
- Nivel 4: los ojos son los del Observer (una copia local de su rig en la
  que solo se ven los ojos, en blanco).
- Nivel 1: además del chasquido, la lámpara zumba un momento.
- Menú: un haz de luna en la recepción y una lámpara de emergencia en el
  sótano, además de las bombillas.
- Lámparas muertas: suciedad sobre el cristal (la calcomanía de mugre ya
  subida).

**El grano.** Subido desde Studio el 12-10-2026: `grain_light`
75475187132085 y `grain_dark` 133619764838758, ya en `AssetIds.Film`. Si en la
Output aparece «Asset type does not match», son IDs de calcomanía y no de
imagen: `tools/studio/check_image_ids.luau` da los buenos. El juego elige
solo, de mejor a peor:

1. **Texturas subidas** (`AssetIds.Film`): el grano más fino. No hace falta
   API key: en Studio, *Asset Manager → Bulk Import* con
   `assets/film/grain_light.png` y `grain_dark.png` (o subirlas en el Creator
   Dashboard), y poner en `AssetIds.Film` el ID de **imagen**, no el de la
   calcomanía (`tools/studio/check_image_ids.luau` los distingue).
2. **Textura creada en el juego** (`EditableImage`): en un juego publicado
   Roblox solo la permite si el dueño tiene verificación de edad (13+) y de
   identidad y activa *Game Settings → Security → Allow Mesh / Image APIs*.
3. **Motas** (si faltan las dos anteriores): un campo de puntos de un píxel,
   blancos y negros, que cambian 24 veces por segundo (220 / 450 / 700 según
   la calidad gráfica). No necesita nada; es más grueso que la película.

**Pendiente:**

- Las proporciones de luz son de un modelo aproximado: ajustar en Studio.

**Comprobar en Studio:**

1. Recorrer un pasillo y dos salas contiguas (G-01 / G-02) en NORMAL y en
   cada blackout (panel F8 → Blackout 1-4): ninguna sala iluminada a través
   de la pared, nada negro absoluto junto a un charco de luz, y cada nivel
   igual de visible pero más inquietante.
2. Que las sombras de las lámparas no salten al andar (LOD de sombras).
3. El menú principal: luz tenue, bombillas que se mueven, y al pulsar PLAY
   no queda ninguna.
4. El grano en PC y en móvil, con y sin «Film grain»; que el HUD quede
   limpio por encima. Con las motas, mirar el coste en móvil (calidad baja:
   220 puntos).
7. Nivel 2: la puerta que se entreabre; nivel 4: los ojos del Observer en
   la penumbra (que se lean a 16-24 studs).
5. FPS con el MicroProfiler antes y después (sombras de 10 lámparas, grano
   a 24 fps).
6. Con «Reduced flashes & glitches»: sin parpadeo de proyector, sin
   siluetas de un fotograma, pulsos lentos.

## 11. Pasada de lógica y enganche (18-10-2026, rama `fixes/vega`)

| Qué | Dónde |
|---|---|
| THE WITNESS pide haber leído todo el archivo de los capítulos 1-7 (29 entradas), como dice la historia, en vez de 10. El texto del archivo del lobby y el aviso de la foto en blanco cuentan con eso. | `Catalog/Lore`, `RoundService`, `MenuController` |
| `CL_WITNESS` y `AL_VALE_04` (capítulo 8) ya no pueden salir como papeles en el edificio: solo salen con la foto. | `Lore.pick` (`rewardOnly`) |
| Lore sin contradicciones: la nota del día 3 pasa al día 43 (Vale ve lo primero raro el día 40) y quien lleva once años es el que cuidaba el edificio antes del proyecto. | `Catalog/Lore` |
| El lore de la noche solo mira a los participantes de la ronda, no a quien está en el menú o el lobby. | `ObjectiveService:Plan` |
| La dificultad baja a la más alta que tengan desbloqueada todos los que están listos (con aviso). Un novato ya no entra en NIGHTMARE por el host. | `LobbyService` |
| Equipos veteranos (tutorial hecho y 3+ rondas cada uno): el apagón llega como mucho a los 75 s. | `HorrorDirector`, `GameConfig.VeteranRounds/VeteranArrival` |
| Quien se desconecta sale como LEFT en los resultados, no como LOST. | `RoundService`, `ResultsController` |
| El bonus de +10 % se llama "Played as a team": se da con cualquier compañero, no solo con amigos. | `ProgressionService` |
| Badges de Roblox para 10 logros, y los logros ya ganados reciben su badge al entrar. Faltan los IDs. | `GameConfig.Badges`, `ProgressionService` |

**Para que funcionen las badges:** crearlas en el Creator Dashboard (Engagement → Badges) y pegar cada ID en `GameConfig.Badges`. Con 0 no se hace nada.

**Comprobar en Studio:** entrar con un perfil que tenga todo el lore de 1-7 y salir con la foto (debe dar THE WITNESS); con 2 jugadores, uno sin HARD desbloqueado y el host con HARD elegido (la ronda debe ir en NORMAL con aviso); el panel F8 con un perfil veterano (el apagón a los 75 s en NORMAL).

## 12. Cámaras de seguridad para los que ya no están dentro (18-10-2026)

Quien ha muerto, se ha quedado encerrado o ya ha salido no se queda solo mirando: con **C** (o el botón SECURITY CAMERAS sobre la vista de espectador) ve el edificio por las cámaras de seguridad, y lo que ve una cámara en directo cuenta como mirado. El Observer se queda quieto en cámara igual que delante de un vivo.

Reglas, para que no rompa la partida:

- Las cámaras van con la corriente del edificio. Durante el apagón no hay señal: restaurar la luz también devuelve los ojos a los muertos.
- Una cámara solo ve lo iluminado, dentro de 70 studs y de su ángulo, con línea de visión.
- Cada cinta aguanta 8 s en directo y luego rebobina 6 s. Cambiar de cámara no la reinicia.
- El parpadeo forzado por mirar fijo también se aplica a quien mira por la cámara.
- Hay 8 cámaras por edificio: todos los pasillos y después salas grandes elegidas con la semilla. Tienen un piloto rojo que se enciende cuando alguien mira por ellas.

Todo se ajusta en `GameConfig.SecurityCams`. Código: `SecurityCamService` (servidor, decide), `SecurityCamController` (cliente, pinta) y tres puntos de `ObserverService` (`watchers`, `unseenAt` y el avistamiento).

**Comprobar en Studio** (Start con 2 jugadores): matar a uno desde el panel F8, pulsar C, buscar al Observer en una cámara con la corriente restaurada y ver que se queda quieto mientras el vivo le da la espalda; que durante el apagón salga NO SIGNAL; que al acabar los 8 s rebobine y el Observer vuelva a moverse; que ninguna cámara quede metida en una pared (si alguna mira a la nada, el problema está en `mountFor`).

**Probado en Studio (18-10-2026, un jugador con estado DEAD simulado en el servidor):** 7-8 cámaras, ninguna en una pared; LIVE 8 s y REWIND 6 s; cambiar de cámara no reinicia la cinta; con el apagón, STATIC y la cinta parada; piloto rojo solo en LIVE. Con el Observer delante de la CAM 01, WATCHED los 6 s de LIVE sin moverse un stud, y al rebobinar se mueve. Falta ver con 2 jugadores reales la interfaz del cliente (C, NO SIGNAL).

**Arreglado al probarlo:** el Observer y el Mimic buscaban camino con un radio de agente de 1.6 y 1.5, y con eso el navmesh no pasa por ninguna puerta. `pathOk` fallaba siempre, así que ninguna caza llegaba a empezar y el Observer no podía andar de una sala a otra (solo se recolocaba). Ahora el radio es 1 en los dos.
