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
   - **normales** (OpenGL), con poros, arrugas, venas en relieve y las
     grietas;
   - **color**: piel muerta de carbón (piel B), con bastante más rango de
     valor que antes, venas oscuras bajo la piel, cavidades hundidas, crestas
     algo más claras, grietas secas en hombros y espalda, y piel fina (dedos,
     cuello y alrededor de los ojos) con un tono frío algo rojizo que imita
     la dispersión;
   - **rugosidad por zonas**: seca y mate casi todo (0,74–0,90), húmeda en la
     hendidura, las cuencas, el cuello y las palmas (0,22), y del todo seca
     en las grietas.

   Cabeza, cuello, torso y manos van a 4.096 px, el máximo que admite Roblox.
   La cabeza es el más pequeño de los cuatro, así que es lo que más densidad
   de textura lleva. El resto va a 512 px.

   Las islas UV son pocas y grandes, con margen entre ellas. El horneado
   extiende los bordes de cada isla y rellena los huecos con un valor neutro
   (nunca rugosidad 0, que en los mips se convierte en un espejo).

   Solo se rehace la malla de los segmentos que se piden con `--remesh` (por
   defecto, `Head`). Los demás se hornean sobre su `.obj` actual, así que
   las mallas ya subidas siguen valiendo.

   `--skin=A` hornea la otra propuesta, «ceniza»; las dos se compararon con
   renders antes de elegir.

Cada malla vive en el espacio local de su pieza del rig, así que
`ObserverRig.dress` la suelda encima sin tocar las articulaciones. Los
segmentos vecinos se solapan: el extremo de cada uno se hunde dentro del
siguiente y no aparecen bolas en codos y rodillas.

## 3. Capas y su función

| Capa | Qué es | Para qué sirve |
|---|---|---|
| Anatomía base | Cuerpo alto, estrecho y algo encorvado. Masa en caja torácica, pecho, cintura, muslos y antebrazos. | La silueta y la sensación de cuerpo sólido. |
| Volúmenes secundarios | Masa dorsal encorvada; un manto de tejido que sube por la nuca, de modo que la cabeza se asienta en los hombros; trapecios caídos; masas de hombro; omóplatos bajo la piel; tres pliegues de tejido oscuro en cada costado; un pliegue blando bajo el hombro; tendones y nuca gruesa en el cuello; membranas del cuello a los hombros. | Rompen el aspecto de esqueleto sin parecer armadura ni ropa. |
| Superficie | Bultos y arrugas en la geometría. En los mapas, piel muerta de carbón con venas, poros, arrugas, grietas secas y piel fina rojiza fría; rugosidad seca con zonas húmedas. | Que no parezca plástico: la luz la descubre a trozos, oscura pero legible. |
| Detalle focal | La cabeza: alargada y estrecha (0,80 × 1,68 studs), sin alas; un bulto pesado sobre cada cuenca (el derecho más alto); una hendidura por el centro de una cara larga y sin rasgos; dos cuencas hondas (la izquierda más alta) con los dos ojos pequeños; una punta corta que baja hacia el cuello. | Identidad propia, reconocible de lejos y de cerca. |

**Ojos:** son piezas del rig con articulación (`EyeTurnL` y `EyeTurnR`) y
siguen al jugador.

- Brillan como los de un animal en la oscuridad: el globo es oscuro (20, 18,
  16) y no tiene luz propia; el iris es Neon ámbar apagado (92, 76, 46) y la
  pupila, una ranura vertical. Se eligió entre dos propuestas renderizadas.
  Los anteriores eran un aro claro alrededor de un disco negro y, de cerca,
  parecían botones pegados.
- El izquierdo mide 0,105 studs, es algo menor y está más alto; el derecho
  mide 0,115.
- Dejan un brillo leve en la oscuridad sin parecer focos.
- Sus posiciones están compartidas entre `ObserverRig.EyeOffsets` y el
  script de Blender, para que caigan dentro de las cuencas.

**Sin boca:** la ausencia de rasgos inquieta más que unos dientes.

## 4. El jumpscare

> Sustituye al jumpscare por secuencias (falsa calma, giros, impacto a
> 3 studs). Aquel parecía de comedia: la cámara se movía sola, que es el
> aviso de que algo viene; el fondo seguía iluminado; la cara se veía
> pequeña; y el ritmo (0,55 s ladeando la cabeza y luego un empujón) daba
> risa.

### Las reglas

- **Instantáneo.** El frame en que llega la muerte ya es el golpe: sin falsa
  calma, sin giros y sin aviso. `ScareController:Death` lo monta todo en la
  misma llamada, antes del siguiente render. La inhalación de aviso que manda
  el servidor cuando está cerca se queda: es una regla de juego justa.
- **La cámara no se mueve.** Conserva la posición, la orientación (también
  mirando al suelo o al techo) y el FOV de ese frame. No hay temblor ni zoom,
  y el ratón no hace nada (`State.scareDark` congela la entrada y oculta el
  cursor en `CameraController`). El que se mueve es él:
  `ObserverRig.placeFace` pone su cara delante de donde apunta la cámara, con
  el pitch incluido, derecha en pantalla y mirando al objetivo.
- **Todo lo demás, a negro en ese mismo frame,** y todo en local:
  - todas las luces del Workspace y la linterna apagadas;
  - en Lighting, a cero `Ambient`, `OutdoorAmbient`, `Brightness`,
    `EnvironmentDiffuseScale` y `EnvironmentSpecularScale`, y la
    `Atmosphere` sin densidad;
  - sin cielo, sin grades que levanten el negro, sin blur;
  - sin HUD (todo `PlayerGui` menos `Overlay`) y sin los demás jugadores;
  - una caja de seis placas Neon negras alrededor de la cámara. Neon negro
    se ve negro le dé la luz que le dé, y tapa lo emisivo del edificio
    (rótulos de salida, pantallas, balizas), que si no seguiría brillando.

  Cada propiedad se fija con `hold` y se devuelve al terminar. Si otro sistema
  la cambia mientras tanto (por ejemplo, un tween del servidor), se devuelve
  ese último valor. Lo mismo pasa si el susto se corta (una muerte durante un
  `Flash`) o falla al montarse.
- **La cara llena la pantalla.** La cabeza ocupa dos tercios del alto con el
  FOV del jugador. `ObserverRig.scareDistance(fov)` lo calcula con la cabeza
  medida (`ObserverMeshMeta.Head`). Con el FOV por defecto (74) la cara queda
  a 1,03 studs.
- **Una luz tenue en su cabeza y nada más.** Es un `PointLight` frío y débil
  (alcance 2,2 y brillo 1,1), pegado abajo y a un lado de la cabeza
  (`ScareController.Light`): saca el relieve y los ojos y deja media cara en
  negro. Respira despacio, como una bombilla que no acaba de morir; nunca
  estrobo, y fija con `reducedEffects`.
- **El movimiento es suyo.** Poses clave que saltan sin interpolar
  (`ScareController.DeathKeys`): un tirón seco de cabeza, otro desde el cuello
  hacia el lado contrario, la cabeza tumbada sobre el hombro a 98° y
  congelada un instante, tics, y al final se echa hacia el objetivo. Los ojos
  se recalculan cada frame sobre la cabeza resuelta, así que no te sueltan. El
  rig local va todo anclado y con las articulaciones apagadas: cada frame se
  colocan las piezas con `ObserverRig.solve`, y cada salto se ve justo en el
  frame en que ocurre.
- **Sonido.** Silencio total salvo el golpe: `ObserverImpact`,
  `ObserverScreech` y `JumpSting` juntos y fuertes, por un grupo propio
  (`ScareHit`, solo con el volumen general). Los demás grupos quedan a cero
  hasta el corte. `reducedEffects` no baja el golpe.
- **Duración.** Entre 1,25 y 1,45 s de cara, según el `beat` del servidor.
  Después, corte seco a negro, pitido y la frase de la variante.
- **Fuera** el glitch, el destello rojo, el blur y el temblor.
- **`Flash`** sigue las mismas reglas durante medio segundo. `MimicLunge` no
  cambia: es la cara del mimic, no la del Observer.

El servidor sigue mandando `variant`, `sequence` y `beat`: `variant` elige la
frase, `beat` la duración y `sequence` solo aparece en el informe de admin.
`ObserverService` no cambia.

## 5. Pruebas ejecutadas de verdad

**`tools/runtime_test.luau`: 117.846 comprobaciones, 0 fallos.**

- Mallas y mapas horneados de los 10 segmentos, todos por debajo del límite
  de triángulos.
- Montadas sobre el rig: 16 mallas mates y ninguna pieza con aristas visible
  encima.
- Proporciones, cuerpo negro y mate, y ojos pequeños y apagados.
- Encuadre del jumpscare: 12 posiciones, 5 pitch (de −80° a 80°) y 3 poses.
  - Error de colocación 0,00000.
  - De frente al objetivo y derecha en pantalla: 1,0000.
  - Ojos a 10,8° del centro como mucho.
- La cabeza ocupa entre el 60 % y el 74 % del alto de pantalla con FOV 60, 74
  y 90. Se mide proyectando los vértices reales de `Head.obj`.
- Nada se interpone entre la cámara y la cabeza.

**`tools/client_test.luau`: 100.792 comprobaciones, 0 fallos.**

- 7 variantes, y además mirando al suelo (−75°) y al techo (60°), en los dos
  extremos del `beat`.
- Antes de que corra ningún frame, la cara ya está delante de la cámara, a
  la distancia de su FOV, centrada y de frente.
- Durante toda la cinemática:
  - el CFrame y el FOV de la cámara son idénticos a los de antes del golpe;
  - no hay ninguna luz del edificio, ni de la linterna, ni estática
    encendida;
  - la del susto es la única luz que toca la cabeza, y tiene poco alcance;
  - Lighting está a cero, sin cielo, sin HUD y con los grupos de sonido a
    cero.
- Al terminar vuelve todo como estaba: luces, Lighting (incluido un tween
  que cae a mitad del susto), cielo, grade, HUD y volúmenes. No quedan ni
  rig ni caja.
- Además se prueban el `Flash`, una muerte que corta un `Flash` y la prueba
  de admin.

**Renders Cycles del rig real con las mallas y sus mapas**
(`tools/observer_shot.luau` y `render_room.py`). **No son el render de
Roblox.** La toma `scare` reproduce el frame del golpe con la luz en la
cabeza.

## 6. Lo que falta

**Subir a Studio:**

- `assets/observer/Head.obj`: la cabeza nueva, sin alas;
- los 30 mapas de `assets/observer/<Segmento>/`, horneados con la piel
  nueva.

Las otras 9 mallas no cambian. Con los IDs nuevos relleno
`AssetIds.Observer.models.Head` y `AssetIds.ObserverSkins`, y ejecuto
`sync_assets.py`.

Hasta entonces:

- el cuerpo usa las mallas y la piel ya subidas;
- la cabeza vieja con alas ya no encaja con este build. `loadMeshes`
  compara su tamaño nativo con `ObserverMeshMeta`, la descarta con un aviso
  y la cabeza se ve hecha con piezas (también sin alas).

**No comprobado en Roblox:**

- el aspecto con la iluminación del juego;
- la animación de las mallas en movimiento;
- el jumpscare en primera persona real (lista de comprobación en el resumen de la rama `fixes/vega`).

**Técnica:** son segmentos rígidos sobre un rig de Motor6D, no una malla con
huesos. Solapar los extremos esconde las juntas, pero en flexiones extremas
puede verse algo. Una malla con skinning exigiría FBX y otro sistema de
animación.

**Puertas:** la cabeza ya no tiene alas (0,8 studs de ancho), así que no
atraviesa los marcos.
