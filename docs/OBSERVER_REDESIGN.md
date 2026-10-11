# The Observer: rediseño según la imagen de referencia

> **Documento histórico.** Lo sustituyó `OBSERVER_V2.md` (aspecto y
> jumpscare), y después cambiaron más cosas. Las medidas de aquí ya no valen:
> la cabeza no es una hoja de 4,6 studs (ahora es alargada, estrecha y sin
> alas) y el susto no se encuadra a 3 studs. La fuente de verdad es el código:
> `src/shared/ObserverRig.luau` (cuerpo, cabeza, encuadre),
> `src/shared/Config/ObserverMeshMeta.luau` (medidas de las mallas) y
> `src/client/Controllers/ScareController.luau` (jumpscare).

Este rediseño sustituye al aspecto descrito en `ENTITIES_OVERHAUL.md`, que tenía
una cara pálida, fauces y dientes. La IA, los estados, el jumpscare encuadrado
y las herramientas de administración de ese documento siguen igual.

## 1. Qué impedía el aspecto buscado

**Lo que tenía el modelo anterior:**

- una cabeza pequeña adelantada sobre un cuello largo;
- una cara pálida con fauces y dientes;
- costillas, columna y dedos hechos con piezas;
- encima, las mallas esculpidas antiguas (`tools/gen_observer.py`), con
  costillas y brillo húmedo.

Ninguna de esas cosas está en la referencia.

**Primer intento con piezas:** cuñas y bloques daban bien la silueta, pero las
facciones se veían **separadas y geométricas**. Con piezas no se consigue una
forma fluida.

## 2. La solución: un cuerpo continuo y suave

`tools/blender/build_observer.py` genera una malla suave por segmento del rig.
Cada una es un *loft* de secciones redondeadas con superficie de subdivisión:
sin aristas y sin piezas sueltas.

| Segmento | Forma |
|---|---|
| Head | Una hoja horizontal de 4,6 studs, en una sola pieza: el borde superior casi recto, el inferior subiendo hacia las puntas y una punta central que baja hasta el cuello. |
| Neck | Largo y fino, ensanchándose hacia el mentón y los hombros. |
| UpperTorso | Cintura estrecha que se abre en hombros caídos hasta los brazos. |
| Brazos y piernas | Largos y finos, con extremos redondeados. En cada articulación los dos segmentos tienen el mismo grosor y se solapan, así que no hay estrangulamientos al doblar. |
| Manos y pies | Sencillos, integrados en la silueta. |

**Ojos:** dos ojos pequeños, de gris claro, con pupila negra. Son piezas
aparte, con articulación propia (`EyeTurnL` y `EyeTurnR`), y miran al jugador.
Usan Neon con un gris tenue: brillan lo justo para leerse en la oscuridad,
como en la referencia, sin halo.

**Material:** negro mate uniforme (9, 9, 10), SmoothPlastic sin reflectancia y
sin textura.

**Proporciones medidas** (el test las comprueba):

| Medida | Valor |
|---|---|
| Altura | 9,31 studs |
| Anchura de la cabeza | 4,60 studs |
| Anchura de hombros | 2,50 studs |
| Altura a la que llegan las manos | 1,25 studs (a media espinilla) |

**Compatibilidad:** las mallas se montan sobre el mismo rig con
`ObserverRig.dress`. Las articulaciones conservan sus nombres (`RootJoint`,
`Waist`, `NeckJoint`, `HeadJoint`, hombros, codos, muñecas, caderas, rodillas
y tobillos), así que no cambian:

- la IA y la navegación;
- `ObserverFX`;
- el jumpscare;
- las figuras del Marketing Studio y las anomalías.

**Hasta que subas las mallas** se ve la versión hecha con piezas: la misma
silueta, pero con aristas.

## 3. Animación y jumpscare

**Animación:** son los estados deliberados de la pasada anterior:

- quieto mientras lo miran;
- la cabeza gira hacia ti a 55 °/s como mucho;
- ni temblores ni chasquidos.

**El jumpscare:**

- La cara queda a **3 studs** de la cámara con un campo de visión de **62°**,
  para que se vea **toda la hoja** de la cabeza.
- Los ojos quedan a menos de 4° del centro de la imagen, nivelados y mirando
  al objetivo.
- Los brazos se abren a los lados sin tapar la cabeza.
- La luz es más baja, para que el negro siga siendo negro.
- Ya no hay cara que se abra.

## 4. Pruebas ejecutadas de verdad

**Test de runtime (`runtime_test`): 117.807 comprobaciones, 0 fallos.**

- Las mallas existen y cada una tiene menos de 20.000 triángulos.
- Montadas sobre el rig: 16 mallas mates y ninguna pieza con aristas visible
  encima.
- No quedan costillas, dientes, fauces, dedos ni costura.
- Proporciones:
  - la cabeza es más de 1,8 veces más ancha que los hombros;
  - mide entre 9 y 10 studs;
  - las manos llegan a la media espinilla.
- El cuerpo es negro uniforme y mate, y los ojos son pequeños y claros.
- Encuadre del jumpscare, desde 12 posiciones y 3 fases:
  - error de colocación de la cara 0,00000;
  - orientación hacia la cámara 0,999;
  - cara nivelada;
  - ojos a 3,7° del centro como mucho;
  - nada entre la cámara y la cabeza.

**Test de cliente (`client_test`): 78.422 comprobaciones, 0 fallos.** Las 7
variantes de muerte, con la cara a 3 studs y centrada.

**Renders Cycles del rig real con su pose** (`tools/observer_shot.luau`). **No
son el render de Roblox.**

| Render | Imagen |
|---|---|
| (imágenes reemplazadas por las de `OBSERVER_V2.md`) | |

## 5. Lo que tienes que hacer en Studio

1. **Importar las mallas.** Asset Manager → Import 3D de las 10 mallas de
   `assets/observer/`:
   - Head, Neck, UpperTorso, LowerTorso;
   - UpperArm, LowerArm, Hand;
   - UpperLeg, LowerLeg, Foot.
2. **Pasarme los IDs.** Si salen como «Malla» y con el nombre `default`, el
   reconocimiento por tamaño se puede aplicar igual que con las props.
3. **Comprobarlo.** Con `Observer: inspect` y los `Scare test` del panel F8,
   en pasillos iluminados y oscuros, de frente y de lado.

**No comprobado en Roblox:** el aspecto final con la iluminación del juego y la
animación en movimiento de las mallas.
