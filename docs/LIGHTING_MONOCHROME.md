# Luz y sombras (referencia MONOCHROME): medidas

Medido con `tools/light_probe.luau` + `tools/light_probe.py` (semilla 42,
planta baja: despachos G-01 / G-02, pasillo principal, recepción, aseos). Es
una **aproximación** con el modelo de luz de `tools/light_study.py` (caída
de Roblox, conos, sombras solo de las luces que las proyectan, ambiente
plano, exposición, ACES y el grado del preset aplicado sobre la imagen
final). Sirve para comparar estados y versiones, no para valores absolutos.

- **En pantalla:** lo que muestra un suelo gris medio (0 = negro, 1 = blanco).
- **Luz que llega ×1000:** la que mandan las lámparas al punto, sin ambiente
  ni grado. Separa «no llega luz» de «llega, pero el grado la aplasta».
- **Vistas:** media de la imagen y porcentaje de píxeles casi negros de una
  vista del pasillo y otra de G-02.

Estados: NORMAL, B1-B4 (blackout 1-4 con corriente) y EMERGENCY (sin
corriente).

Reproducir:

```bash
lune run tools/light_probe.luau build/test.rbxl 42 build/probe.json
python3 tools/light_probe.py build/probe.json --markdown --views
```

## Antes (línea base, commit `cfc70d5`)

**on screen (0-1)**

| Punto | NORMAL | B1 | B2 | B3 | B4 | EMERGENCY |
|---|---|---|---|---|---|---|
| corridor: under a lamp | 0.119 | 0.067 | 0.000 | 0.000 | 0.000 | 0.000 |
| corridor: 5 studs from it | 0.046 | 0.011 | 0.000 | 0.000 | 0.000 | 0.000 |
| corridor: halfway between two lamps | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| reception: under a lamp | 0.046 | 0.028 | 0.000 | 0.000 | 0.000 | 0.000 |
| office G-02: centre | 0.013 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| office G-02 without its lamps: centre | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| G_u, lamps off, behind the wall of lit G_r | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| the same spot with no lamp anywhere near (ambient only) | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |

**light arriving x1000**

| Punto | NORMAL | B1 | B2 | B3 | B4 | EMERGENCY |
|---|---|---|---|---|---|---|
| corridor: under a lamp | 172.5 | 120.8 | 0.0 | 0.0 | 0.0 | 0.0 |
| corridor: 5 studs from it | 102.0 | 71.4 | 0.8 | 0.3 | 0.0 | 0.8 |
| corridor: halfway between two lamps | 59.6 | 41.7 | 10.7 | 3.2 | 0.0 | 10.7 |
| reception: under a lamp | 101.9 | 86.5 | 50.7 | 50.7 | 0.0 | 0.0 |
| office G-02: centre | 73.1 | 51.2 | 0.0 | 0.0 | 0.0 | 0.0 |
| office G-02 without its lamps: centre | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| G_u, lamps off, behind the wall of lit G_r | 0.3 | 0.2 | 0.0 | 0.0 | 0.0 | 0.0 |
| the same spot with no lamp anywhere near (ambient only) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
view corridor: NORMAL mean 0.105 black 56%; B1 mean 0.072 black 59%; B2 mean 0.013 black 85%; B3 mean 0.029 black 76%; B4 mean 0.002 black 100%; EMERGENCY mean 0.010 black 87%
view G-02: NORMAL mean 0.049 black 81%; B1 mean 0.033 black 86%; B2 mean 0.004 black 100%; B3 mean 0.004 black 100%; B4 mean 0.004 black 100%; EMERGENCY mean 0.004 black 100%

**Lectura:**

- A medio camino entre dos lámparas del pasillo llega el 35 % de la luz
  que hay debajo de una (59,6 frente a 172,5), pero en pantalla sale **0**.
  El negro entre charcos no es falta de luz: es el grado (exposición 0,
  contraste 0,16 alrededor del gris medio) aplastando todo lo que queda por
  debajo de un umbral. Por eso hay negro absoluto justo al lado de un charco.
- En NORMAL, debajo de una lámpara un suelo gris solo llega a 0,12 en
  pantalla: incluso lo «bien iluminado» es muy oscuro.
- Cada nivel de blackout es más oscuro que el anterior; desde B2 todo el
  pasillo y los despachos son 0 en pantalla (85-100 % de la vista casi negra).

## Después (esta pasada)

Mismos puntos y vistas. La medida ya reproduce lo que hace el cliente: las
lámparas cercanas proyectan sombras y las piezas con `CastShadow` apagado no
tapan nada (por eso la «luz que llega» en algunos puntos difiere un poco de
la línea base, que se exportó con las sombras repartidas al azar).

**on screen (0-1)**

| Punto | NORMAL | B1 | B2 | B3 | B4 | EMERGENCY |
|---|---|---|---|---|---|---|
| corridor: under a lamp | 0.331 | 0.309 | 0.307 | 0.314 | 0.321 | 0.040 |
| corridor: 5 studs from it | 0.233 | 0.217 | 0.216 | 0.220 | 0.225 | 0.041 |
| corridor: halfway between two lamps | 0.163 | 0.152 | 0.151 | 0.148 | 0.151 | 0.059 |
| reception: under a lamp | 0.246 | 0.237 | 0.238 | 0.241 | 0.246 | 0.040 |
| office G-02: centre | 0.186 | 0.174 | 0.170 | 0.176 | 0.180 | 0.040 |
| office G-02 without its lamps: centre | 0.043 | 0.043 | 0.043 | 0.042 | 0.042 | 0.040 |
| G_u, lamps off, behind the wall of lit G_r | 0.043 | 0.043 | 0.043 | 0.042 | 0.042 | 0.040 |
| the same spot with no lamp anywhere near (ambient only) | 0.043 | 0.043 | 0.043 | 0.042 | 0.042 | 0.040 |

**light arriving x1000**

| Punto | NORMAL | B1 | B2 | B3 | B4 | EMERGENCY |
|---|---|---|---|---|---|---|
| corridor: under a lamp | 172.5 | 155.3 | 151.8 | 155.3 | 155.3 | 0.0 |
| corridor: 5 studs from it | 102.0 | 91.8 | 89.8 | 91.7 | 91.7 | 0.8 |
| corridor: halfway between two lamps | 59.6 | 53.6 | 52.4 | 51.8 | 51.8 | 10.7 |
| reception: under a lamp | 111.4 | 105.3 | 104.2 | 105.3 | 105.3 | 0.0 |
| office G-02: centre | 73.1 | 65.8 | 63.2 | 65.8 | 65.8 | 0.0 |
| office G-02 without its lamps: centre | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| G_u, lamps off, behind the wall of lit G_r | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| the same spot with no lamp anywhere near (ambient only) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
view corridor: NORMAL mean 0.251 black 25%; B1 mean 0.237 black 26%; B2 mean 0.228 black 26%; B3 mean 0.226 black 22%; B4 mean 0.230 black 22%; EMERGENCY mean 0.098 black 59%
view G-02: NORMAL mean 0.141 black 41%; B1 mean 0.135 black 41%; B2 mean 0.130 black 44%; B3 mean 0.136 black 41%; B4 mean 0.139 black 43%; EMERGENCY mean 0.048 black 100%

## Objetivos y resultado

| Objetivo | Antes | Después |
|---|---|---|
| Entre dos lámparas del pasillo se ve (NORMAL, en pantalla) | 0,000 | 0,163 |
| Proporción debajo de una lámpara / entre dos (≤ 2,5) | infinita | 2,0 |
| Una sala sin lámpara es gris profundo, nunca 0 (0,03-0,06) | 0,000 | 0,043 |
| Detrás de la pared de una sala iluminada = sala sin lámpara (sin fugas) | 0,3 de luz que llega | 0,0 |
| Blackout 1→4: la vista media no baja más de 0,01 de un nivel al siguiente | 0,072 → 0,013 → 0,029 → 0,002 | 0,237 → 0,228 → 0,226 → 0,230 |
| Sin corriente sigue haciendo falta la linterna | 0,010 (vista) | 0,098 (vista), 0,04 en el suelo |

**Lectura:**

- La oscuridad ya no es un agujero negro al lado de cada charco: es un gris
  profundo (negros levantados como en la película) y el paso de la luz a la
  sombra es un degradado.
- Ninguna lámpara ilumina a través de una pared: las cercanas tienen
  sombra y las lejanas no pasan de su sala.
- Los blackouts con corriente mantienen la luz media; lo que cambia es el
  ritmo, el color y lo que aparece en ella (`LightingRules`, `BlackoutFX`).
- Sin corriente (EMERGENCY) sigue siendo el estado oscuro de verdad.
- Es una aproximación: en Studio el brillo absoluto cambiará (texturas,
  rebotes, el tonemapper de Roblox). Lo que vale es la comparación.


## v3: menos luz, contraste más suave, blackouts más oscuros (octubre 2026)

Esta pasada cambia la regla de arriba: los blackouts con corriente ya no
mantienen la luz media. Cada nivel quita luz (`LightingRules.LEVEL_MEAN`:
1 → 0,8, 2 → 0,55, 3 → 0,45, 4 → 0,35) y su preset baja también la
exposición. La tabla del modelo de arriba se quedó corta: en Studio el juego
se veía mucho más claro de lo que daba `light_probe` (un suelo gris bajo una
lámpara salía a 0,74 en pantalla, no a 0,33), así que esta vez se midió
directamente en Studio.

**Cómo se midió:** partida en Studio (modo Play), cámara fija en el pasillo
principal G_c (desde x 14 mirando a +X) y en el despacho G_b, captura de
pantalla y luminancia sRGB media con un desenfoque de 7 px para quitar el
grano. "Bajo lámpara" y "entre lámparas" son dos zonas fijas del suelo del
pasillo. "Negro" es el porcentaje de píxeles por debajo de 0,06. Capturas
en `docs/img/v3_*.jpg`. `light_probe` no se volvió a pasar en esta pasada.

| Vista | Media antes | Media después | Negro antes | Negro después |
|---|---|---|---|---|
| Pasillo, NORMAL | 0,446 | 0,189 | 6 % | 4 % |
| Pasillo, B1 | | 0,155 | | 8 % |
| Pasillo, B2 | 0,432 | 0,138 | 0 % | 12 % |
| Pasillo, B3 | | 0,088 | | 21 % |
| Pasillo, B4 | 0,482 | 0,081 | 0 % | 27 % |
| Pasillo, EMERGENCY | 0,124 | 0,092 | 0 % | 24 % |
| Despacho G-02, NORMAL | 0,622 | 0,195 | 0 % | 5 % |

| Suelo del pasillo (NORMAL) | Antes | Después |
|---|---|---|
| Bajo una lámpara | 0,73 | 0,27 |
| Entre dos lámparas | 0,74 | 0,22 |
| Proporción | 1,0 | 1,25 (objetivo ≤ 3) |

Antes el pasillo con un blackout 4 era más claro que en NORMAL. Ahora cada
nivel es más oscuro que el anterior y B4 sigue sin ser negro (27 % de la
vista).

**Luces que aparecían de golpe.** Las lámparas sin sombra tienen el alcance
recortado a la distancia a su pared (un tubo del pasillo se queda en 3,5
studs y no llega al suelo). Solo las N más cercanas a la cámara tenían
sombra, y al ganarla el alcance saltaba de 3,5 a 16 en un frame: ese era el
charco que aparecía delante. Ahora el LOD mira hacia delante
(`LightController`: más alcance en la dirección de la vista y de la marcha,
menos detrás, fundido en el 35 % exterior), las sombras van a las lámparas
más cercanas a un punto 20 studs por delante de la cámara, y el alcance
crece o encoge en unos 0,3 s. Recorriendo el pasillo a 10 studs/s, lámparas
del pasillo ya con sombra y alcance completo:

| Distancia por delante | Antes | Después |
|---|---|---|
| 6-20 studs | 87-93 % | 97-100 % |
| 20-36 studs | 17-20 % | 90-95 % |
| 36-56 studs | 0 % | 6-8 % |

Presupuesto de sombras por calidad: 3 / 12 / 16 lámparas (antes 2 / 10 / 14).
