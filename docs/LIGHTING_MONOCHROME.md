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
