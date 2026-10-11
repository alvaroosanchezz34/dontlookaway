# Fallos pendientes

> **Pasada de coherencia** (rama `claude/epic-cannon-fcf3p3`, guion en
> `PROMPT_CORRECCIONES.md`): al final de este documento está lo que se
> arregló y lo que queda por comprobar en Studio.

Apuntados en la rama `fixes/vega`, sin arreglar todavía. En cada uno: dónde
creo que está, qué creo que lo causa y cómo comprobarlo en Studio. Son
hipótesis sacadas de leer el código y de medir los archivos, no de verlo en
Studio.

## 0. Recursos subidos por otra cuenta (probable causa de varios fallos)

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

