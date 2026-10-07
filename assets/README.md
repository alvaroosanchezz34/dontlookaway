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
| `observer/*.obj` | 12 mallas del Observer | el Observer y sus cinemáticas |
| `observer/observer_skin_*` | piel PBR (color, relieve, rugosidad) | el Observer |

Cada textura tiene `_color`, `_normal` y `_roughness` (y `metal_worn` además `_metalness`).

## Cómo subirlo (una vez)

1. Abre el juego en Roblox Studio (tiene que estar **publicado**).
2. **View → Asset Manager → Bulk Import** (icono de subir).
3. Selecciona **todas las imágenes .png** de `assets/textures/*/` y `assets/observer/`.
   Se suben como *Images*. Roblox las revisa (moderación), puede tardar unos minutos.
4. Para las mallas: **Bulk Import** de los 12 archivos `.obj` de `assets/observer/`.
   En el diálogo de importación deja las opciones por defecto.
5. En el Asset Manager, en **Images** y **Meshes**, haz clic derecho en cada
   recurso → **Copy Asset ID**.

## Cómo conectarlo

Pega cada número en `src/shared/Config/AssetIds.luau`:

```lua
plaster_aged = { color = 1234567890, normal = 1234567891, roughness = 1234567892 },
...
AssetIds.Observer.meshes.Head = 1234567893
```

O, más fácil: **pásame la lista de nombres e IDs** y lo relleno yo.

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
python3 tools/gen_observer.py        # mallas, piel y src/shared/Config/ObserverMeshMeta.luau
```

Vista previa del Observer sin Studio:

```bash
rojo build default.project.json -o build/test.rbxlx
lune run tools/dump_rig.luau build/test.rbxlx > build/rig.txt
python3 tools/preview_observer.py build
```
