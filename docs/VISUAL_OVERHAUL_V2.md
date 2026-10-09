# Visual Overhaul V2 — auditoría, cambios y pruebas

Este documento recoge la pasada visual V2 sobre el juego real: el edificio, sus
puertas, techos, muebles y lámparas, más el Marketing Studio.

No se ha podido abrir Roblox Studio ni hacer capturas desde este entorno. Todo lo
que aquí se mide sale de construir el mapa en Lune (`tools/visual_audit.luau`,
`tools/validate_map.luau`, `tools/zfight.luau`) y de los tests. **El aspecto final
hay que comprobarlo en Studio** con la lista del final.

## 1. Auditoría (antes de tocar nada)

Cifras medidas con la semilla 8919:

| | Antes | Después |
|---|---|---|
| Piezas totales | 6.527 | 9.432 |
| Piezas de detalle arquitectónico | 0 | 1.699 (carpeta `Detail`, con LOD) |
| Luces | 231 (Point 168 · Spot 62 · Surface 1) | 314 (Point 168 · Spot 81 · Surface 65) |
| Luces con sombra | 48 | 48 (ahora las proyectan las luces dirigidas) |
| Parejas con z-fighting (2 semillas) | 82 | 11 |
| Incidencias del validador de geometría | 0 | 0 |

Problemas encontrados, por prioridad:

1. **Las lámparas iluminaban el techo y no el suelo.** Cada lámpara (fluorescente,
   colgante, jaula o bombilla) era un único `PointLight` omnidireccional que nacía
   pegado al techo. El techo quedaba quemado y el charco de luz en el suelo no
   tenía forma. → **corregido**
2. **No había instalaciones ni herrajes.** Faltaban interruptores, enchufes,
   rejillas, aspersores, detectores, canalizaciones, bisagras, manillas,
   escudos, placas de patada y plintos. Es lo que hace que un edificio parezca
   real. → **corregido en todo el mapa**
3. **Un solo metal y la madera por defecto de Roblox.** Toda la madera
   (1.412 piezas) usaba la textura de Roblox. Todo el metal, manillas incluidas,
   usaba la textura de metal pintado y desconchado. → **6 texturas PBR nuevas
   generadas, subidas y conectadas**
4. **Muebles hechos de bloques.** Escritorios con laterales macizos, sillas con
   respaldo de una sola pieza, mesas sin faldón, archivadores y taquillas sin
   herrajes. → **rehechas las 7 piezas más repetidas**
5. **Z-fighting.** Había 82 parejas de caras coplanarias que parpadean:
   papeles sueltos apilados a 0,007 studs y laterales de los cubículos de los
   aseos que se solapaban. → **quedan 11**, todas preexistentes y menores:
   archivos de estantería, una barandilla, papeles bajo un monitor.
6. **El sótano y la escalera se veían igual que las oficinas.** Mismo yeso y
   suelo de hormigón seco. → **pintura que se levanta y hormigón húmedo**
   (necesitan la subida de texturas)
7. **Ninguna escala de calidad para las luces.** La distancia de LOD de luces
   era fija y no había LOD de detalle. → **niveles de calidad bajo / medio / alto**
8. **El Marketing Studio no tenía looks reutilizables.** Cada escena montaba su
   luz a mano. → **8 presets de luz y composición**

Lo que se descartó, y por qué:

- **No se tocó la iluminación global** (Ambient, Exposure, Atmosphere, grade). Ya
  estaba calibrada para que la oscuridad se lea sin cegar, y oscurecer o subir la
  niebla no es una mejora real.
- **No hay mallas nuevas.** Desde aquí solo se pueden generar mallas como
  archivos `.obj` que habría que importar en Studio. Para muebles y herrajes se
  ha trabajado con piezas, siluetas y uniones.
- **El Observer no cambia.** Ya usa mallas esculpidas con piel PBR. Su
  integración con la luz (parpadeo cercano, tintes) ya funcionaba con las luces
  nuevas: está probado en los tests.

## 2. Qué se ha cambiado

### Estándares (`src/shared/VisualStandards.luau`)

Un único sitio para:

- **19 superficies:** material, color, variante y reflectancia.
- **Perfiles de luz por tipo de lámpara.**
- **Niveles de calidad:** distancia de LOD de luces, luces secundarias y
  distancia de detalle.

### Texturas (`tools/gen_textures.py`)

Seis generadores nuevos, todos originales: ruido y geometría, sin imágenes
externas.

| Textura | Variante | Uso |
|---|---|---|
| `wood_aged` | `DLA_Wood` (sustituye a Wood) | madera de carpintería |
| `fabric_worn` | `DLA_Fabric` (sustituye a Fabric) | tapicería |
| `metal_rusted` | `DLA_Rust` (sustituye a CorrodedMetal) | tuberías y válvulas |
| `paint_peeling` | `DLA_PeelingPaint` | pintura que se levanta: sótano y escaleras |
| `concrete_wet` | `DLA_WetConcrete` | suelo húmedo: sótano y zonas industriales |
| `metal_bare` | `DLA_Hardware` | herrajes de acero o latón |

- Se revisaron en una hoja de contacto y se corrigió una costura al hacer
  mosaico, en `paint_peeling`.
- Subidas a Roblox y conectadas: IDs en `AssetIds.Materials`, variantes escritas por
  `tools/sync_assets.py` en `src/materials/` (16 en total, 11 sustituyen a un material base).

### Arquitectura (`src/server/Map/Architecture.luau`)

Recorre las 34 salas, los pasillos y las 35 puertas con hoja, después de
amueblar. Por semilla coloca:

- **Puertas:**
  - tres bisagras en el eje de giro;
  - manilla de palanca con roseta y cuello;
  - escudo con bocallave;
  - placa de patada en las dos caras;
  - plintos bajo los marcos.

  Las piezas que van en la hoja se mueven con ella (atributo `Offset`), igual
  que las manillas que ya había.
- **Paredes:**
  - interruptor en el lado del pestillo de cada sala;
  - enchufes repartidos por la pared libre;
  - canalización con abrazaderas y cajas de registro en el sótano y las salas
    técnicas.
- **Techos:**
  - rejillas de ventilación con lamas;
  - aspersores;
  - detector de humo con LED;
  - placas con mancha de agua;
  - alguna placa que falta y alguna que cuelga de un borde.

Reglas que cumple, todas comprobadas en los tests:

- **No interfiere con el juego:** no colisiona, no recibe rayos ni toques y no
  da sombra. Por eso no afecta a la interacción, a la percepción del Observer,
  a la navegación ni a las anomalías.
- **No se mete en ningún mueble:** prueba de cajas orientadas contra cada pieza
  de mobiliario.
- **Respeta los huecos de pared de las anomalías.** Cada detalle de pared retira
  el hueco que tapa de `room.wallSpots`, que usan la puerta falsa, la sombra, la
  puerta B-13 y los símbolos de los objetivos. Ninguna sala baja de 3 huecos
  disponibles.
- **Es determinista:** misma semilla, mismas piezas en la misma posición
  (probado).
- **No genera z-fighting nuevo:** todo queda a 0,03 o más de su superficie.

### Iluminación motivada

- **Fluorescentes y colgantes** (`MapBuilder.addFixture`):
  - los fluorescentes llevan un `SurfaceLight` hacia abajo desde el difusor;
  - los colgantes llevan un `SpotLight` hacia abajo desde la pantalla;
  - en ambos esa luz dirigida es la que proyecta la sombra, y el `PointLight`
    "Light" queda como relleno o rebote;
  - las jaulas y las bombillas desnudas siguen siendo puntuales, porque así es
    como emiten luz de verdad.
- **Cliente** (`LightController`):
  - gobierna todas las luces de cada lámpara con su parte del brillo (`Ratio`);
  - tintes, overrides, parpadeos y apagones afectan a todas;
  - en calidad baja solo queda el relleno, con su brillo `Solo`, para gastar la
    mitad de luces;
  - la distancia de LOD sale del nivel de calidad.

### Muebles (`src/server/Map/Props.luau`)

Mismas huellas y mismo orden de aleatoriedad. El validador sigue en 0
incidencias.

| Mueble | Cambios |
|---|---|
| Escritorio | pedestal elevado sobre zócalo oscuro, pies, tiradores con placa, cerradura, pasacables |
| Mesa | patas que se estrechan, faldones, contera de goma |
| Silla de madera | respaldo de dos postes, travesaño y tres listones; faldones; chambranas |
| Silla de oficina | carcasa, columna de gas, buje, brazos y estructura del respaldo |
| Archivador | portaetiquetas con etiqueta, zócalo, bombín; los cajones abiertos enseñan laterales y carpetas |
| Taquilla | bisagras, placa de número, zócalo |
| Estantería metálica | pestaña delantera en cada balda, cruces traseras, placas en los pies |
| Cubículo de aseo | pie de acero, pestillo con la puerta cerrada, sin solapes coplanarios con el vecino |

### LOD de detalle (`src/client/Controllers/DetailLOD.luau`)

Cada sala tiene su grupo de detalle, con centro y radio. Más allá de la
distancia de su nivel de calidad (40 / 70 / 110 studs) se oculta en local con
`LocalTransparencyModifier`. No se destruye ni se cambia de sitio nada del
servidor.

### Marketing Studio

- `Utilities/Looks.luau`: 8 looks.
- La acción `LookPreset`.
- Dos escenas nuevas, `Scene_LookBook` y `Scene_DoorAjarToEye`, en la categoría
  H · LOOKS.
- Ver la sección 13 de `src/marketing/README.md`.

## 3. Pruebas ejecutadas de verdad

- **`tools/runtime_test.luau`: 97.980 comprobaciones, 0 fallos.** Cubre 5
  semillas, con el validador de geometría a 0 en todas.
  - detalle colocado (más de 800 piezas) y agrupado por sala;
  - ninguna pieza de detalle sólida o consultable;
  - ninguna pieza de detalle dentro de un mueble;
  - huecos de anomalía conservados;
  - placas de patada presentes y piezas de puerta con `Offset`;
  - reparto de brillo en todas las luces y más de 60 luces dirigidas;
  - determinismo;
  - las 6 texturas V2 generadas (color, normal y rugosidad).
- **`tools/client_test.luau`: 71.379 comprobaciones, 0 fallos.**
  - una lámpara con dos luces respeta su reparto de brillo, el tinte de
    anomalía y el override;
  - `DetailLOD` oculta y vuelve a mostrar;
  - los 8 looks colocan sus luces;
  - las 56 escenas del Marketing Studio se ejecutan sin eventos fallidos, en
    decorado virtual y en edificio.
- **`tools/zfight.luau`:** 82 → 11 parejas.
- **Analizador:** sin líneas nuevas respecto a la línea base.

## 4. Pruebas manuales en Studio

1. **Sincronizar.** `rojo serve` y conectar. En el Output debe salir
   `[MaterialLibrary] 16 custom textures active` (antes eran 10; incluye las 6
   nuevas).
2. **Iluminación de oficinas y pasillos.**
   - Empieza una ronda (F8 → Start round) y entra en una oficina con luz.
   - Bajo cada fluorescente tiene que haber un charco de luz en el suelo, con
     el techo más oscuro que antes.
   - La sombra de los muebles debe caer hacia abajo, no hacia los lados.
3. **Recepción y galería.** Los colgantes deben dar un cono cálido bajo la
   pantalla y un brillo tenue arriba.
4. **Apagones.**
   - Admin → Blackout 1, 2, 3 y 4.
   - Las luces dirigidas deben parpadear, apagarse y ponerse rojas a la vez que
     su relleno.
   - Las de emergencia deben seguir encendidas como antes.
5. **Anomalía de color de lámpara.** Fuérzala desde el panel admin (forceAnomaly `LAMP_CHANGE`); el tinte
   debe verse en el charco del suelo, no solo en el tubo.
6. **Puertas.**
   - Abre y cierra varias puertas: manillas, roseta, escudo y placas de patada
     deben moverse con la hoja sin despegarse.
   - Las bisagras quedan en el canto, en el eje de giro.
   - Revisa que una puerta abierta no atraviesa el interruptor (va en el lado
     del pestillo).
7. **Techos.**
   - En los pasillos busca rejillas, aspersores, el detector con LED rojo,
     manchas de agua y alguna placa que falta o cuelga.
   - Nada debe atravesar los fluorescentes ni las tuberías del techo.
8. **Sótano.**
   - Canalización con abrazaderas y cajas a unos 11,5 studs en las paredes
     largas de la sala de calderas, el pasillo B y las salas técnicas.
   - Paredes con pintura que se levanta y suelo húmedo, cuando estén subidas
     las texturas.
9. **Muebles.**
   - Mira de cerca un escritorio, una silla de madera, una de oficina, un
     archivador con un cajón abierto, una taquilla, una estantería metálica y
     los aseos.
   - No debe haber parpadeos en las caras.
10. **Calidad.** Ajustes → Calidad BAJA, MEDIA y ALTA.
    - En BAJA desaparecen las luces dirigidas (queda el relleno más fuerte).
    - El detalle de salas lejanas se oculta antes.
    - Mira los FPS con el Developer Console (F9 → Memory / Render) en BAJA y
      en ALTA.
11. **Rendimiento.** Con 2 o 3 jugadores en el servidor de prueba, compara
    FPS y Ping con la versión publicada.
    - El mapa tiene unas 2.900 piezas más (+44 %), casi todas sin colisión ni
      sombra.
    - Tiene 83 luces más, todas sujetas al LOD.
12. **Marketing Studio.**
    - F7 → H · LOOKS → `Scene_LookBook`: deben verse los 8 looks rotulados y
      volver todo a la normalidad al terminar.
    - `Scene_DoorAjarToEye`: la luz se cuela por la rendija y el plano se
      cierra sobre el ojo.
13. **Texturas V2** (ya subidas):
    - madera de puertas, marcos y muebles con veta;
    - herrajes metálicos brillantes;
    - tuberías oxidadas;
    - sótano con pintura que se levanta y suelo húmedo.

## 5. Límites honestos

- **No es fotorrealismo.** El juego sigue siendo un mapa de piezas de Roblox
  con texturas PBR. Esta pasada sube la credibilidad del espacio con detalle
  funcional, luz con forma y materiales, pero no lo convierte en una fotografía.
- **No se ha comprobado visualmente en Roblox.** Las cifras y pruebas de arriba
  son de geometría y de lógica, no de imagen.
- **No hay mallas nuevas.** Los muebles se han mejorado con piezas; mallas
  importadas como `.obj` darían curvas y biseles reales, pero requieren Studio.
- **Coste de luces.** Las nuevas luces dirigidas suben el número de luces
  dinámicas cerca de la cámara. Hay que mirar el rendimiento en móvil, donde
  la calidad baja las quita.
