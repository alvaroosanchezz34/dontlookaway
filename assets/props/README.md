# Mallas propias (Blender) para DON'T LOOK AWAY

Todo lo de esta carpeta es **original**: geometría y materiales los crea
`tools/blender/build_assets.py` con Blender (módulo `bpy`), sin modelos ni
texturas externas.

| Archivo | Qué es |
|---|---|
| `<Asset>.obj` | malla en studs, ejes de Roblox (Y arriba, el frente del objeto en -Z) |
| `<Asset>/<Asset>_color.png` | albedo horneado (incluye la suciedad de cavidades y el desgaste de aristas) |
| `<Asset>/<Asset>_normal.png` | mapa de normales tangente, convención OpenGL (Y+), la que usa SurfaceAppearance |
| `<Asset>/<Asset>_roughness.png` | rugosidad |
| `<Asset>/<Asset>_metalness.png` | metalicidad (negro en lo que no es metal) |
| `previews/<Asset>.png` | render de revisión en Cycles |
| `previews/_sheet.png` | hoja con todos |

`src/shared/Config/PropMeshMeta.luau` (generado) guarda el tamaño y el centro de
cada malla para que el juego la coloque exactamente.

## Mallas

| Asset | Sustituye a | Notas |
|---|---|---|
| ReceptionDesk | el mostrador de recepción | frente de bastidor con 4 plafones, encimera de piedra con canto redondeado, moldura en S, ménsulas, laterales con plafón |
| DoorLeaf | la hoja de las puertas de madera | 4 plafones en relieve con moldura, en las dos caras; se mueve con la puerta |
| DoorCasing | el marco de cada cara de cada puerta | piernas molduradas, tacos de esquina con roseta |
| PendantLamp | la lámpara colgante | florón, cable, campana esmaltada torneada con reflector (la bombilla sigue siendo la pieza que brilla) |
| WallSconce | el aplique de pared | placa, brazo curvo y copa de latón (la tulipa de cristal y la bombilla siguen siendo piezas) |
| Radiator | los radiadores | 8 columnas de fundición, pies, válvula |
| WoodChair | la silla de madera | patas torneadas, respaldo de husillos, travesaño curvo |
| Table | la mesa 5 × 3 | patas torneadas, faldones, canto redondeado |
| Sofa | el sofá | chesterfield con brazos enrollados y capitoné |
| FilingCabinet | el archivador (con los cajones cerrados) | frentes embutidos, portaetiquetas, tiradores, zócalo |
| OfficeDesk | el escritorio de oficina | cajonera con tiradores, faldón, tablero con canto |
| Locker | la taquilla | puerta con rejillas de ventilación, maneta, zócalo |
| MetalShelf | la estantería metálica de 6 de ancho | montantes perforados, baldas con pestaña |
| PictureFrame | el marco de los cuadros | moldura dorada; el juego la escala a cada cuadro |
| Baseboard / DadoRail / Cornice | rodapiés, molduras de zócalo y cornisas de todo el mapa | perfil constante: el juego lo estira a cada tramo |

## Cómo meterlas en el juego (Studio, una vez)

1. **Mallas.** Asset Manager → **Import 3D** → elige cada `assets/props/<Asset>.obj`.
   Deja las opciones por defecto. Studio crea un **Model** por archivo; clic
   derecho → **Copy Asset ID**.
2. **Mapas.** Asset Manager → **Bulk Import** de las PNG de
   `assets/props/<Asset>/`. Se suben como imágenes; copia sus IDs. Los
   `_metalness` solo hacen falta en: PendantLamp, WallSconce, Radiator,
   FilingCabinet, Locker y OfficeDesk; el resto puede ir con 0.
3. Pon los números en `src/shared/Config/AssetIds.luau` → `AssetIds.PropMeshes`
   (o pásamelos con una captura) y ejecuta `python3 tools/sync_assets.py`. Ese
   script crea `src/shared/PropSkins/<Asset>.model.json` (la SurfaceAppearance
   con los mapas), que Rojo mete en el juego.

Con un `model` y su `color` puestos, el servidor carga la malla al arrancar
(`PropMeshes.load`, igual que el Observer) y viste el mapa
(`PropMeshes.dress`). Si una malla no está subida, ese objeto se queda como
está (piezas). Las piezas sustituidas siguen existiendo, invisibles: la
colisión, la interacción, las anomalías y el validador de geometría no cambian.

## Regenerar

```bash
uv venv --python /usr/bin/python3.13 ~/.venv-blender
uv pip install --python ~/.venv-blender/bin/python bpy==5.2.2 numpy pillow
~/.venv-blender/bin/python tools/blender/build_assets.py            # todas
~/.venv-blender/bin/python tools/blender/build_assets.py DoorLeaf   # una
~/.venv-blender/bin/python tools/blender/preview_assets.py          # renders de revisión
```

Regenerar una malla cambia su archivo: hay que volver a importarla y a subir sus mapas.

## Revisión en contexto (no es el render de Roblox)

```bash
lune run tools/light_study.luau build/test.rbxlx G_r 8919 build/light_G_r.json
~/.venv-blender/bin/python tools/blender/render_room.py build/light_G_r.json out.png meshes NORMAL
```

Reconstruye una sala del mapa real con las texturas del juego y las mallas, y
la renderiza en Cycles. Para parecerse a Roblox usa solo luz directa y el
Ambient del perfil, sin rebote de luz.
