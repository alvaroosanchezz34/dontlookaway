# The Observer V2: criatura orgánica, anatomía por capas y jumpscare imprevisible

Sustituye el aspecto de `OBSERVER_REDESIGN.md`. La IA, la navegación, los
estados y las herramientas de administración no cambian.

## 1. Por qué el modelo anterior parecía un esqueleto geométrico

- **Formas tubulares:** cada segmento era un *loft* de secciones circulares,
  es decir, tubos y husos.
- **Sin anatomía:** no había masa en el pecho, la espalda ni los muslos, y
  tampoco capas.
- **Juntas de muñeco:** en las articulaciones, los dos segmentos acababan en
  punta o en bola.
- **Superficie perfecta:** era negra, sin variación ni relieve.
- **Copia literal:** la silueta reproducía la imagen de referencia tal cual.

## 2. Cómo está hecha ahora

`tools/blender/build_observer.py` **esculpe** cada segmento de forma
procedimental en Blender:

1. **Volúmenes fusionados:** se combinan metaballs. Los elipsoides y las
   cápsulas se funden en una superficie continua, y los volúmenes negativos
   tallan cuencas, hendiduras y huecos.
2. **Relieve orgánico:** bultos suaves y arrugas finas en la dirección del
   cuerpo, más un suavizado.
3. **Malla de juego:** la de alta resolución se reduce a un presupuesto de
   juego, de 1.400 a 6.000 triángulos por segmento y unos 30.000 en total.
4. **Horneado:** de la alta a la de juego, en tres mapas:
   - normales (OpenGL);
   - color, con las cavidades oscurecidas y los relieves un punto más claros;
   - rugosidad mate (0,68–0,94).

   Son 1.024 px para la cabeza y el torso y 512 px para el resto.

Cada malla vive en el espacio local de su pieza del rig, así que
`ObserverRig.dress` la suelda encima sin tocar las articulaciones. Los
segmentos vecinos se solapan: el extremo de cada uno se hunde dentro del
siguiente y no aparecen bolas en codos y rodillas.

## 3. Capas y su función

| Capa | Qué es | Para qué sirve |
|---|---|---|
| Anatomía base | Cuerpo alto, estrecho y algo encorvado. Masa en caja torácica, pecho, cintura, muslos y antebrazos. | La silueta y la sensación de cuerpo sólido. |
| Volúmenes secundarios | Masa dorsal encorvada; un manto de tejido que sube por la nuca, de modo que la cabeza se asienta en los hombros; trapecios caídos; masas de hombro; omóplatos bajo la piel; tres pliegues de tejido oscuro en cada costado; un pliegue blando bajo el hombro; tendones y nuca gruesa en el cuello; membranas del cuello a los hombros. | Rompen el aspecto de esqueleto sin parecer armadura ni ropa. |
| Superficie | Bultos y arrugas en la geometría; piel casi negra moteada, más oscura en las cavidades; rugosidad alta. | Que no parezca plástico liso, sin dejar de ser oscura y legible. |
| Detalle focal | La cabeza: una media luna ancha y caída, asimétrica (izquierda más larga, derecha más baja); un pliegue sobre cada ala; membranas bajo las alas; arco superciliar pesado y más alto a la derecha; una hendidura por el centro de una cara larga y sin rasgos; dos cuencas hondas (la izquierda más alta) con los dos ojos pequeños. | Identidad propia, reconocible de lejos y de cerca. Ya no es una copia de la referencia. |

**Ojos:** son piezas del rig con articulación (`EyeTurnL` y `EyeTurnR`) y
siguen al jugador.

- Gris apagado autoiluminado, de color (104, 102, 96), con una pupila grande.
- El izquierdo mide 0,105 studs, es algo menor y está más alto; el derecho
  mide 0,115.
- Leen en la oscuridad sin parecer focos.
- Sus posiciones están compartidas entre `ObserverRig.EyeOffsets` y el
  script de Blender, para que caigan dentro de las cuencas.

**Sin boca:** la ausencia de rasgos inquieta más que unos dientes.

## 4. El jumpscare

### Por qué era previsible

- Siempre tenía la misma gramática y el mismo ritmo:
  1. el sonido se cortaba en el primer fotograma, y eso era el aviso;
  2. la cámara se giraba de golpe;
  3. se abalanzaba en 0,2 s y golpeaba.
- Además, antes de cada captura sonaba siempre la inhalación de aviso.

### Cómo funciona ahora

El servidor elige una **secuencia** según la situación y la envía con un
**ritmo** (`beat`, de 0 a 1). Nunca repite la misma secuencia dos veces
seguidas al mismo jugador.

Cada secuencia tiene fases:

- **A, falsa calma.**
- **B, ruptura.**
- **C, impacto:**
  1. la cara aparece iluminada a 3 studs, nivelada, con los dos ojos en el
     centro;
  2. se sostiene 0,55 s mientras la cabeza se ladea despacio;
  3. luego empuja una vez hasta 1,9 studs, con el grito.
- **D, cierre:** fundido a negro, pitido y una frase.

| Secuencia | Situación | Qué pasa |
|---|---|---|
| turn | detrás o de lado | Te giras hacia el ruido: no hay nada. Un respiro (0,45 a 1,05 s). Al volver la cabeza, ya está delante, antes de que termines de girarte. |
| stillness | delante | Está al fondo, quieto; solo se le ladea la cabeza (0,9 a 1,7 s). De repente, sin moverse, está en tu cara. |
| drop | delante o detrás | Nada delante (0,45 a 0,95 s)… y su cara baja al encuadre desde arriba. |
| lightsout | oscuridad | Se apaga la luz. Dos ojos pequeños al fondo un instante. Vuelve la luz y no hay nada. Sube a tu cara desde abajo. |
| peek | de lado o en una puerta | Media cabeza asoma por el borde del encuadre y se retira. Llega por el lado contrario. |
| mirror | espejo | Primero lo ves en el espejo y luego te giras. |
| mimic | compañero | Un compañero de espaldas gira la cabeza del todo: no es él. |

**Sonido:** el mundo sigue sonando durante la falsa calma y solo se corta en
el golpe. En «lightsout» se corta al apagarse la luz, porque ahí el silencio
es la propia ruptura.

**Efectos:** el temblor, el glitch y el destello rojo son leves y nunca tapan
la cara.

**Garantías técnicas:**

- La cara se coloca siempre con `ObserverRig.placeFace`.
- El rig local no tiene Humanoid ni Animator, así que la locomoción no puede
  pisar la pose.
- El servidor decide el ataque y la muerte, que ocurre una sola vez.
- El modo de prueba devuelve la cámara y el control.

## 5. Pruebas ejecutadas de verdad

**`tools/runtime_test.luau`: 117.837 comprobaciones, 0 fallos.**

- Mallas y mapas horneados de los 10 segmentos, todos por debajo del límite
  de triángulos.
- Montadas sobre el rig: 16 mallas mates y ninguna pieza con aristas visible
  encima.
- Proporciones, cuerpo negro y mate, y ojos pequeños y apagados.
- Encuadre del jumpscare desde 12 posiciones y 3 fases:
  - error de colocación 0,00000;
  - orientación hacia la cámara 0,999;
  - cara nivelada;
  - ojos a 3,9° del centro como mucho.

**`tools/client_test.luau`: 175.947 comprobaciones, 0 fallos.**

- Las 7 situaciones con su secuencia por defecto, más las 7 secuencias en los
  dos extremos de ritmo (27 casos).
- En todos, en el fotograma del impacto la cara queda delante de la cámara, a
  3 studs, centrada y de frente.
- El momento del impacto varía: al menos 8 instantes distintos.
- Cada caso termina, limpia y devuelve la cámara.

**Renders Cycles del rig real con las mallas y sus mapas**
(`tools/observer_shot.luau` y `render_room.py`). **No son el render de
Roblox.** La imagen `observer_v2_sheet.jpg` reúne 9 tomas:

- 3/4 con luz de estudio y primer plano de la cabeza;
- perfil, pasillo iluminado, pasillo oscuro y a 40 studs;
- zancada, fotograma del impacto y los ojos solos en la oscuridad.

## 6. Lo que falta

**Subir a Studio:**

- las 10 mallas de `assets/observer/*.obj`, que ahora llevan nombre propio;
- sus 30 mapas de `assets/observer/<Segmento>/`.

Con sus IDs relleno `AssetIds.Observer.models` (o `pool`) y
`AssetIds.ObserverSkins`, y ejecuto `sync_assets.py`. Hasta entonces se ve la
versión hecha con piezas.

**No comprobado en Roblox:**

- el aspecto con la iluminación del juego;
- la animación de las mallas en movimiento;
- el jumpscare en primera persona real.

**Técnica:** son segmentos rígidos sobre un rig de Motor6D, no una malla con
huesos. Solapar los extremos esconde las juntas, pero en flexiones extremas
puede verse algo. Una malla con skinning exigiría FBX y otro sistema de
animación.

**Cuidado con las puertas:** la cabeza mide unos 4,4 studs de ancho y puede
atravesar visualmente los marcos.
