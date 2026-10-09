# Assets propios: texturas y Observer esculpido

Todo lo de esta carpeta es **original**: lo generan `tools/gen_textures.py` y
`tools/gen_observer.py` a partir de ruido y geometría, sin imágenes externas.
Roblox solo permite usar texturas y mallas que estén **subidas a tu cuenta**,
así que hay que subirlas una vez. Mientras no lo hagas, el juego funciona igual
con los materiales de Roblox y el Observer de piezas.

## Qué hay

| Carpeta | Contenido | Dónde se usa |
|---|---|---|
| `textures/plaster_aged` | yeso viejo con humedad y desconchones | todas las paredes y techos de yeso |
| `textures/wallpaper_damask` | papel pintado de damasco descolorido | recepción, archivo, galería, sala silenciosa |
| `textures/carpet_worn` | moqueta con desgaste y manchas | oficinas |
| `textures/tiles_worn` | baldosa cerámica con juntas sucias | pasillos, baños, cocina, enfermería |
| `textures/ceiling_tile` | placa de techo acústica | techos suspendidos |
| `textures/concrete_grimy` | hormigón con poros y aceite | sótano, zonas industriales |
| `textures/wood_planks_worn` | tarima vieja | archivo, galería, sala silenciosa |
| `textures/brick_grimy` | ladrillo con hollín | fachada y zonas industriales |
| `textures/marble_stained` | mármol con vetas y manchas | recepción |
| `textures/metal_worn` | metal pintado con óxido | metal en general |
| `textures/wood_aged` *(V2)* | madera de carpintería con veta, barniz gastado, golpes | **sustituye a Wood**: puertas, marcos, zócalos, muebles |
| `textures/fabric_worn` *(V2)* | tapicería de sarga con bolitas y manchas | **sustituye a Fabric**: sillas, sofás, tablones |
| `textures/metal_rusted` *(V2)* | hierro con óxido en escamas, picaduras | **sustituye a CorrodedMetal**: tuberías, válvulas |
| `textures/paint_peeling` *(V2)* | pintura que se levanta sobre yeso húmedo, moho | paredes del sótano y escaleras (`DLA_PeelingPaint`) |
| `textures/concrete_wet` *(V2)* | losa húmeda con charcos y salitre | suelos del sótano y zonas industriales (`DLA_WetConcrete`) |
| `textures/metal_bare` *(V2)* | acero cepillado / latón gastado | bisagras, manillas, placas, aspersores (`DLA_Hardware`) |
| `textures/marble_tiles` *(pendiente de subir)* | baldosa de mármol en damero, juntas biseladas, vetas finas | suelo de recepción y vestíbulo (`DLA_MarbleTiles`) |
| `textures/wallpaper_aged` *(pendiente de subir)* | papel pintado envejecido de rapport grande, juntas de rollo | paredes de recepción y archivo (`DLA_WallpaperAged`) |
| `decals/*.png` *(pendientes de subir)* | 5 calcomanías RGBA: humedad, churretes, mugre, mancha de techo, suciedad de suelo | colocadas con lógica por `Map/Architecture` |
| `observer/*.obj` | 12 mallas del Observer | el Observer y sus cinemáticas |
| `observer/observer_skin_*` | piel PBR (color, relieve, rugosidad) | el Observer |
| `audio/dla_ambience.ogg` | 23 ambientes en bucle (zumbidos, lluvia, viento, ventilación, alarma, respiración del Observer, música de tensión) | todo el edificio |
| `audio/dla_horror.ogg` | 45 sonidos de terror (Observer, sustos, crujidos, golpes, susurros, caja de música, apagones) | el Observer, anomalías, el director |
| `audio/dla_world.ogg` | 31 sonidos del mundo (pasos por material, puertas, interruptores, teclado, cintas, persiana) | interacción |

Cada textura tiene `_color`, `_normal` y `_roughness` (y `metal_worn`, `metal_rusted` y `metal_bare` además `_metalness`).

Las 6 texturas V2 (Visual Overhaul V2) están subidas y conectadas (`AssetIds.Materials`).

**Pendientes de subir (pase de calidad Resident Evil):** 6 imágenes de textura
(`marble_tiles` y `wallpaper_aged`: color, normal, roughness) y 5 calcomanías
(`assets/decals/`: `damp_rising`, `water_streak`, `grime_smudge`, `ceiling_stain`,
`floor_dirt`). Mientras su ID sea `0`:
- el suelo de recepción y su papel pintado usan el material base de Roblox;
- no se coloca ninguna calcomanía (el mapa funciona igual).
Las calcomanías se suben igual que las imágenes (Bulk Import) y su ID va en
`AssetIds.Decals`. No hace falta `sync_assets.py` para ellas; para las 2 texturas, sí.

## Cómo subirlo (una vez)

1. Abre el juego en Roblox Studio (tiene que estar **publicado**).
2. **View → Asset Manager → Bulk Import** (icono de subir).
3. Selecciona **todas las imágenes .png** de `assets/textures/*/` y `assets/observer/`.
   Se suben como *Images*. Roblox las revisa (moderación), puede tardar unos minutos.
4. Para las mallas: **Bulk Import** de los 12 archivos `.obj` de `assets/observer/`.
   En el diálogo de importación deja las opciones por defecto.
5. En el Asset Manager, en **Images** y **Meshes**, haz clic derecho en cada
   recurso → **Copy Asset ID**.

### Audio (solo 3 archivos)
Los 99 sonidos van empaquetados en **3 archivos** para no gastar el cupo mensual
de subidas de audio de Roblox; el juego reproduce cada uno recortando su trozo
(`PlaybackRegion`, ver `src/shared/Config/AudioSheets.luau`).
**Gestor de recursos → Importar** → los 3 `.ogg` de `assets/audio/`. Aparecen en
**Audio**; copia sus IDs a `AssetIds.Audio` (o pásamelos).
Puedes escucharlos antes de subirlos: se abren con cualquier reproductor.

## Cómo conectarlo

Pega cada número en `src/shared/Config/AssetIds.luau`:

```lua
plaster_aged = { color = 1234567890, normal = 1234567891, roughness = 1234567892 },
...
AssetIds.Observer.meshes.Head = 1234567893
```

O, más fácil: **pásame la lista de nombres e IDs** y lo relleno yo.

Después de cambiar IDs ejecuta `python3 tools/sync_assets.py`: Roblox no deja que
los scripts del juego creen materiales ni asignen la piel, así que ese script
escribe los MaterialVariant (`src/materials/`), la piel (`src/shared/ObserverSkin.model.json`)
y la sustitución de materiales base en `default.project.json`, y Rojo los mete en el lugar.

Con los IDs puestos:
- las texturas sustituyen automáticamente a los materiales de Roblox
  (`src/shared/MaterialLibrary.luau`);
- el servidor carga las mallas al arrancar y viste al Observer con ellas y con la
  piel PBR (`ObserverRig.loadMeshes` / `ObserverRig.dress`). Las animaciones
  siguen funcionando igual porque cada malla va soldada a su articulación.

Si solo subes una parte, se usa esa parte y el resto sigue como antes.

## Regenerar

```bash
python3 tools/gen_textures.py 1024   # texturas (numpy + Pillow)
python3 tools/gen_textures.py 1024 wood_aged metal_bare   # solo algunas
python3 tools/gen_decals.py          # calcomanías (assets/decals)
python3 tools/gen_observer.py        # mallas, piel y src/shared/Config/ObserverMeshMeta.luau
python3 tools/gen_audio.py           # audio (numpy + ffmpeg) y src/shared/Config/AudioSheets.luau
```

Vista previa del Observer sin Studio:

```bash
rojo build default.project.json -o build/test.rbxlx
lune run tools/dump_rig.luau build/test.rbxlx > build/rig.txt
python3 tools/preview_observer.py build
```
