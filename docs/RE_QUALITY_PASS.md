# Pase de calidad "Resident Evil": iluminación, materiales y recepción

No he podido abrir Roblox Studio ni hacer capturas del juego desde este entorno.
Todo lo comprobado aquí sale de:

- construir el mapa real en Lune;
- los tests y los validadores;
- un **estudio de luz aproximado** propio (`tools/light_study.*`).

**El aspecto final hay que verlo en Studio** con la lista de la sección 6.

## 1. Por qué la recepción se veía tan oscura

Medido, no supuesto. Roblox multiplica el color de la pieza por el mapa de color
de su textura. Calculando el albedo efectivo (color en lineal × media del mapa):

| Superficie de la recepción | Antes | Ahora |
|---|---|---|
| Suelo (mármol) | 4 % | 24 % (damero de mármol) |
| Zócalo de madera | 1,4 % | 8,5 % (madera oscura barnizada) |
| Papel pintado | 10 % | 36 % |
| Techo | 7 % | 48 % |

La sala devolvía entre el 1 % y el 10 % de la luz que recibía: daba igual cuánta
luz pusieras. Se sumaban otras causas:

- **El relleno de los colgantes no llegaba a las paredes.** En el pase V2 lo
  dejé en 11 studs de alcance.
- **Había demasiadas lámparas fundidas:** el 16 % de todas por diseño.
- **El grade aplastaba las sombras:** su contraste (0,13) llevaba a negro los
  tonos bajos.
- **Había valores de Lighting duplicados y en conflicto** entre
  `default.project.json` (Brightness 0,4, ClockTime 0,5, Ambient casi negro) y
  `LightingService.Init` (0,6 / 0,4).

Revisé todo lo que toca la iluminación:

- Lighting, Atmosphere, ColorCorrection, Bloom y DOF del servidor;
- los grades locales: miedo, accesibilidad, adaptación a la oscuridad y térmica;
- `LightController`, apagones, linterna y emergencia.

No hay ningún script que aplique el apagón durante el estado normal. La ronda
aplica el perfil normal al entrar y el `HorrorDirector` corta la luz más tarde,
como estaba diseñado.

## 2. Perfiles de iluminación (`LightingService`)

| Perfil | Cuándo |
|---|---|
| `NORMAL` | Edificio con electricidad y sin evento: la referencia de juego. Ambient (44,42,40), exposición +0,1, contraste 0,05 |
| `EMERGENCY` | Sin electricidad: luna, emergencia y linterna (antes `DARK`) |
| `BLACKOUT` | Apagón total |
| `CINEMATIC` | Momentos guionizados: más duro y frío |

- `POWERED` y `DARK` siguen funcionando como alias.
- Los valores globales salen de una única tabla (`LightingService.Base`), y
  `default.project.json` usa los mismos valores, así que Studio en edición se ve
  igual que en juego.

## 3. Materiales, texturas y calcomanías

### Creadas en esta sesión

**Recalibración de color** de los 14 estilos, de molduras, puertas, la paleta de
muebles, alfombra, sillas y puerta de entrada. Cada color sale de un albedo
objetivo y de la media real de su textura; se conserva el tono original.

**Texturas nuevas** (originales, generadas por código; revisadas en hoja de
contacto y en mosaico):

- `marble_tiles` (`DLA_MarbleTiles`): mármol en damero con juntas biseladas y
  vetas finas direccionales. Sin grietas dibujadas.
- `wallpaper_aged` (`DLA_WallpaperAged`): rapport grande, juntas de rollo,
  lotes de tono distintos y motivo de bajo contraste, para que no se note la
  repetición.

**Calcomanías RGBA** (`tools/gen_decals.py`, en `assets/decals/`):

| Calcomanía | Dónde se coloca |
|---|---|
| `damp_rising` | humedad en las paredes del sótano, escaleras, aseos y cámara fría |
| `water_streak` | churretes bajo cada ventana |
| `grime_smudge` | mugre alrededor de interruptores y de la manilla de las puertas |
| `ceiling_stain` | mancha en anillo en el techo; sustituye a los discos translúcidos |
| `floor_dirt` | suciedad al pie de los muros de pasillos y zonas de servicio |

### Subidas y conectadas

Las 6 imágenes de `marble_tiles` y `wallpaper_aged` y las 5 calcomanías ya están
en `AssetIds` (18 materiales personalizados en total).

Por semilla se colocan unas 290 calcomanías: suelo, techo, mugre, churretes y
humedad. Cada una comprueba espacio libre contra los muebles: no se pinta
encima de patas ni detrás de armarios.

Si un ID vuelve a 0, esa clase deja de colocarse y el juego sigue igual. Los
tests lo comprueban en los dos sentidos.

## 4. Modelos y geometría (integrados en la generación procedural)

### Recepción

- **Mostrador nuevo:**
  - zócalo rehundido y frente de bastidor con cuatro plafones;
  - encimera de piedra con canto redondeado, moldura y ménsulas;
  - placa de latón con el rótulo «RECEPTION»;
  - laterales con plafón;
  - estante con archivadores;
  - libro de visitas abierto con su bolígrafo y timbre;
  - lámpara de banquero con pantalla verde que se enciende con la red eléctrica.
- **Lámparas colgantes nuevas** (en todo el mapa): florón de techo, cable
  textil, campana esmaltada con reflector interior y bombilla visible.
  - La luz principal es un `SpotLight` hacia abajo desde la campana.
  - Lleva un relleno que alcanza el techo y las paredes.
- **Apliques de pared** de latón con tulipa de cristal (también en galería,
  archivo y sala silenciosa).
  - Son lámparas completas: obedecen apagones, tintes y LOD.
- **Zócalo de bastidor y plafones en relieve** sobre la madera (también en
  archivo, sala silenciosa y galería).
- **Perchero y paragüero** junto a la entrada.
- **Sin lámparas fundidas** en recepción ni vestíbulo.

### Resto del mapa

- **Puertas de madera:** molduras alrededor de los dos plafones en ambas caras.
  Los plafones se estrechan para dejar libre el larguero de la cerradura. Las
  placas de patada se acortan para no tocar la moldura.
- **Ventanas:**
  - tapajuntas interior;
  - vierteaguas bajo el alféizar;
  - hoja pintada con peinazo y junquillos;
  - cierre metálico;
  - marco más claro.
- **Fluorescentes:** difusor prismático de cristal y pestañas de chapa.
- **Escalera de la planta alta:** segunda lámpara sobre el hueco (antes tenía
  una sola).
- **Lámparas fundidas:** 8 % (antes 16 %) y 12 % con parpadeo (antes 14 %).
- **Enchufes:** sobre la madera en las salas con zócalo de bastidor y plafones.
- **LOD de detalle:** también oculta las calcomanías lejanas.

Todo sigue estas reglas:

- se genera con la semilla, así que funciona con cualquier distribución del mapa;
- comprueba espacio libre contra los muebles;
- respeta los huecos de pared de las anomalías;
- no colisiona ni bloquea pasillos.

## 5. Pruebas ejecutadas de verdad

| Prueba | Resultado |
|---|---|
| `tools/runtime_test.luau` | **112.839 comprobaciones, 0 fallos** |
| `tools/client_test.luau` | **71.289 comprobaciones, 0 fallos** |
| `tools/validate_map.luau` (4 semillas) | **0 incidencias** |
| `tools/zfight.luau` | **11 parejas**, las mismas que antes de este pase; ninguna nueva |
| Analizador de tipos | sin líneas nuevas respecto a la línea base |

`runtime_test` cubre, entre otras cosas, las 5 semillas con el validador, los
perfiles, el albedo de los techos, las calcomanías, el mostrador, el zócalo, los
apliques y que no haya lámparas fundidas en recepción.

**Estudio de luz** (`docs/img/reception_light_study.png`): es un trazado de
rayos aproximado del mapa real.

- En la recepción en NORMAL pasa de 99 % de píxeles casi negros a 7 %.
- El apagón sigue siendo casi negro (99,8 %): la recepción no tiene ventanas ni
  emergencia; ahí cuentan la linterna y la adaptación a la oscuridad del juego,
  que el estudio no simula.

**No es el render de Roblox:**

- no usa texturas;
- no tiene rebote de luz;
- su Ambient seguramente es más débil que el de Roblox.

Las cifras absolutas no valen para Studio; las comparaciones entre versiones sí.

## 6. Pruebas manuales en Studio

1. **Sincroniza y entra en la recepción.**
   - `git pull`, `rojo serve` y Play.
   - F8 → Start round y entra.
   - Con luz y sin evento, la recepción debe verse clara: paredes, suelo,
     mostrador y puertas reconocibles sin linterna.
   - Las esquinas en penumbra, no en negro.
2. **Compara apagón y normal.** F8 → Blackout L4 y luego End blackout. El apagón
   debe ser muy distinto y la vuelta debe restaurar la imagen.
3. **Lámparas.** Bajo cada colgante debe haber un charco cálido, y la campana y
   la bombilla deben verse.
   - Los apliques iluminan la pared a su alrededor.
   - La lámpara verde del mostrador se apaga cuando se va la luz.
4. **Mostrador.** Revisa el frente con plafones, el canto redondeado de la
   encimera, la placa «RECEPTION», el libro de visitas y el timbre.
5. **Zócalo y puertas.**
   - El bastidor y los plafones no deben parpadear.
   - Las molduras de las puertas deben moverse con la hoja al abrir.
6. **Ventanas** de las oficinas: tapajuntas y hoja pintada.
7. **Resto del mapa en estado normal.** Pasillos, oficinas, archivo, galería,
   escaleras, aseos y sótano: legibles. El sótano puede quedar en penumbra.
8. **Calidad.** En Ajustes → Quality LOW, la iluminación normal debe seguir
   siendo legible.
9. **Cuando subas las texturas y calcomanías:**
   - suelo en damero en la recepción;
   - papel pintado nuevo;
   - humedad en sótano y escaleras;
   - churretes bajo las ventanas;
   - mugre en interruptores y manillas;
   - manchas de techo.

Si algo se ve demasiado claro u oscuro, dime en qué sala. Los valores están
centralizados en `LightingService.Presets.NORMAL`,
`VisualStandards.Fixtures` y `Layout.Styles`.

## 7. Limitaciones

- **No es Resident Evil.** Es un mapa de piezas de Roblox con texturas PBR,
  iluminación calibrada y más detalle arquitectónico. Los principios son los
  mismos, la fidelidad no.
- **Nada está verificado a la vista en Studio.**
- **Faltan subidas:** las 2 texturas y las 5 calcomanías nuevas.
- **No hay mallas nuevas.** Las curvas reales (molduras, campanas, tiradores)
  necesitarían mallas `.obj` importadas en Studio.
- **El estudio de luz es una aproximación.** Los valores finos pueden necesitar
  un ajuste en Studio.
- **Coste:** el mapa tiene ~10.900 piezas (antes ~9.400) y 330 luces (antes
  314). Lo nuevo no colisiona ni da sombra y está bajo LOD, pero conviene mirar
  los FPS en móvil.
