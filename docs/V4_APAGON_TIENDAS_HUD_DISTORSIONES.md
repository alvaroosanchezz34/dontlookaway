# V4: Blackout 4, tiendas, menú, carga, HUD y distorsiones de la realidad

Rama: `dev/alvaro-trabajo` (sale de `claude/epic-cannon-fcf3p3`, `d166144`).
Commits: `a1dea5a` (apagón), `44be22f` (tiendas), `2b0561c` (menú y carga),
`8f9f301` (distorsiones y HUD).

**Importante:** nada de esto se ha probado todavía en Roblox Studio. Todo lo
marcado como "probado" lo está con las pruebas automáticas (Lune) y el
analizador. La lista de comprobaciones de Studio está en el apartado 5.

## 1. Qué se ha implementado

| Funcionalidad | Estado |
|---|---|
| Blackout 4: caída en 4 estilos, mantenimiento, restauración progresiva | Implementado, probado automáticamente, **pendiente de Studio** |
| Blackout 4: vida en la oscuridad, sin parpadeo negro, el zumbido vuelve con las lámparas | Implementado, probado automáticamente (lógica), **pendiente de Studio** |
| Tienda normal: confirmación, estados, respuestas del servidor, compra atómica | Implementado, probado automáticamente, **pendiente de Studio** |
| Tienda de Robux (`MarketplaceService`, `ProcessReceipt` idempotente) | Implementado, probado automáticamente, **pendiente de configuración** (IDs a 0) |
| Menú inicial nuevo; PLAY espera al servidor | Implementado, probado automáticamente, **pendiente de Studio** |
| Pantalla de carga con fases reales (`ReplicatedFirst`) | Implementado, probado automáticamente (estado y reglas), **pendiente de Studio** |
| HUD: carriles sin solapes, avisos sin duplicados, progreso de anomalías, modo silencioso | Implementado, probado automáticamente (construcción), **pendiente de Studio** |
| Director de distorsiones | Implementado, probado automáticamente, **pendiente de Studio** |
| Evento `ImpossibleHallway` completo | Implementado, probado automáticamente (flujo, ritmo, cancelaciones), **pendiente de Studio y multijugador** |
| El intruso, El bucle, La habitación equivocada | Diseñados en el catálogo, **no construidos** (el director nunca los elige) |

### Blackout 4 (apagón)

- **Las fases.** Cada apagón tiene ahora tres fases:
  - **ONSET**, la caída, en uno de cuatro estilos que nunca se repiten seguidos: BROWNOUT (todas las lámparas se hunden juntas), CASCADE (una a una, cada una con su tartamudeo), SURGE (un pequeño repunte, nunca un destello, y luego la caída) y STUTTER (tartamudeos sueltos que se apagan).
  - **HOLD**, el nivel en sí.
  - **RESTORE**, la vuelta: cada lámpara regresa en su momento y "prende" como un tubo.
- **Servidor y cliente sincronizados.** Las fases van selladas con el reloj del servidor, así que todos los clientes ven lo mismo. La lógica del juego (dónde está oscuro, el Observer, el director) sigue leyendo solo el nivel.
- **Sin destellos.** Ya no hay fundido a negro al empezar un apagón. La imagen se oscurece un poco con la luz (una corrección de color local que nunca llega a negro) y ninguna lámpara supera 1,25 veces su luz. Con efectos reducidos no hay parpadeos, solo cambios suaves.
- **Audio.** Las lámparas cercanas zumban al fallar. En la oscuridad suenan cosas en otro sitio: tuberías, golpes, pasos en otra planta, una puerta lejana, polvo que cae. Al volver la luz suenan relés y el zumbido y la ventilación regresan poco a poco.
- **Respeto al Observer.** Si el Observer real está cerca, no aparecen figuras falsas ni ojos falsos.
- **Sin luces atascadas.** Los reinicios de ronda terminan el apagón al instante, sin restauración, para que no quede ninguna lámpara a medias.

### Tienda normal

- **El servidor responde a todo.** Cada petición (comprar, mejorar, equipar, guardar el equipamiento, cosméticos) recibe una respuesta (`ShopResult`) con el motivo si falla.
- **Compra atómica.** La compra de cosméticos comprueba y cobra en una sola actualización, así que dos peticiones seguidas no compran dos veces.
- **Solo en el lobby.** No se vende nada durante una noche.
- **Interfaz.**
  - Monedero siempre visible.
  - Estados claros: EQUIPPED, OWNED, LOCKED (nivel o cómo se gana), precio pagable o "NEED ◈ X MORE".
  - Panel de detalle también para los cosméticos.
  - Confirmación con el saldo que queda.
  - El botón queda en espera ("…") hasta la respuesta; sin respuesta en 6 s, lo dice.
  - Navegación con mando, teclado, ratón y táctil.

### Tienda de Robux

- **Configuración.** `Config/Monetization.luau` es el catálogo y la única fuente de IDs. Lo que se vende es solo cosmético: 3 pases y 3 productos.
- **`MonetizationService`.**
  - Hay un solo `ProcessReceipt` en todo el juego, y una prueba lo comprueba.
  - Es idempotente: cada `PurchaseId` concedido se guarda en el perfil.
  - Solo confirma la compra tras un guardado real (`DataService:SaveNow`); si el guardado falla, deshace la concesión.
  - Los pases se vuelven a comprobar con `UserOwnsGamePassAsync`.
  - Solo se compra desde el menú o el lobby.
- **Interfaz.** La tienda premium es un panel aparte, con color propio y precios en R$ leídos de Roblox. Muestra PENDING SETUP mientras falte el ID.
- **Pasos de Creator Dashboard:** `docs/TIENDA_PREMIUM.md`.

### Menú y pantalla de carga

- **`ReplicatedFirst/Boot`.** `BootState` registra lo que el cliente ha terminado de verdad:
  - el contenido de la experiencia;
  - los sistemas iniciados;
  - el registro del jugador;
  - los sonidos del menú y las texturas del edificio, precargados con `PreloadAsync`;
  - el edificio de esta noche.
  
  Además impide que los controladores arranquen dos veces.
- **`Loading.client`.**
  - Sustituye la pantalla por defecto.
  - Muestra un barrido indeterminado, sin porcentaje inventado, y una línea por fase.
  - Los consejos van aparte (marcados como NOTE) y en orden aleatorio.
  - Cada fase tiene un límite de tiempo, así que un recurso que falla nunca bloquea la pantalla.
  - Si el servidor no responde, ofrece RETRY, que vuelve a unirse a la experiencia.
  - Se va cuando todo está listo de verdad, no por temporizador.
- **Menú.**
  - Nuevo bloque de título; entradas SUPPLY ROOM y PREMIUM STORE.
  - Barra indicadora al pasar por encima o seleccionar; foco en PLAY con mando.
  - Aviso de "edificio en preparación".
  - PLAY espera a que el servidor te ponga en el Field Office; si no responde, el menú vuelve con un mensaje.
  - Una presencia apenas perceptible al fondo del plano, de vez en cuando (nunca con efectos reducidos).

### HUD

- **Carriles.** Un carril por tipo de mensaje: el "coaching" ya no pisa los subtítulos. Como mucho 3 avisos, y un aviso repetido en 3 s se descarta.
- **Anomalías.** El recuento es una línea con barra de progreso dentro de los objetivos (la lista del equipo sube a su sitio). Un objetivo nuevo entra deslizándose una vez.
- **Batería baja.** "Respira" a menos de 1 Hz; nunca parpadea.
- **`SetQuiet`.** Objetivos y equipo se desvanecen durante una distorsión; las barras se quedan.

### Distorsiones y el pasillo imposible

- **`Catalog/Distortions`.** Para cada evento define: id, categoría, peso, enfriamiento, límites por jugador y por ronda, fase de historia mínima, duración máxima, intensidad, variante (individual) y el diseño de inicio, desarrollo, salida y restauración.
- **`DistortionService`.** Hace de director.
  - **Una distorsión a la vez.**
  - **Cuándo:** con ronda en exploración, desde su fase de historia, con el director en CALM o TENSION, pagado del presupuesto de tensión, sin apagón mayor que 2, con el Observer libre y respetando enfriamientos y límites.
  - **Sin ritmo fijo:** una probabilidad pequeña en cada comprobación que crece cuanto más tiempo lleva siendo posible. No hay ritmo que aprender.
  - **A quién:** un jugador vivo, en el edificio, con el Observer lejos, sin estar sujetando una interacción, sin menú, puzle o nota abiertos, con el tutorial superado y que no sea el de la última vez.
- **`ImpossibleHallway`.** Lo que vive el jugador:
  1. **Ruptura:** parpadeo, el sonido se corta y corte a negro.
  2. **Llegada:** aparece en un pasillo de 480 studs, mirando hacia el fondo.
  3. **Aviso:** el Observer espera al fondo, a 125 studs, sin moverse, entre 5 y 8 s (menos si el jugador se acerca).
  4. **Despertar:** las lámparas a su alrededor mueren de golpe.
  5. **Persecución:** la oscuridad avanza con él. Mantiene sus reglas:
     - mirarlo lo detiene solo donde se le ve (una lámpara viva, la linterna sobre él o a un palmo);
     - nadie aguanta la mirada para siempre: se fuerza el parpadeo;
     - antes de alcanzarte respira, con tiempo para reaccionar.
  6. **Salida o captura:** la salida está detrás del jugador, en la otra punta.
- **Desenlaces.**
  - **escaped:** el jugador llega a la puerta.
  - **taken:** el Observer lo alcanza o se agota el tiempo. No hay muerte: hay una sacudida y +15 de *dread*.
  - **cancelled:** cualquier interrupción.
- **Regreso.** Siempre igual:
  1. corte a negro;
  2. vuelta al sitio exacto (comprobado; si está ocupado, el punto libre más cercano de la misma habitación);
  3. limpieza;
  4. fundido de vuelta.

  No se muestra ningún mensaje.
- **Huella.** Al volver hay una sola diferencia en la habitación: una lámpara muerta (solo para él), una puerta abierta o un cuadro torcido (solo para él). Reportarla no cuenta ni como acierto ni como error.
- **Integraciones.**
  - El Observer se presta en exclusiva (`Borrow` y `Release`): ni su bucle, ni las cazas, ni las apariciones, ni los mímicos actúan mientras tanto, ni sobre el jugador ausente.
  - El director no coloca eventos ni sonidos alrededor del jugador ausente.
  - El espectador ve SIGNAL LOST, y la radio y los pings ignoran al ausente.

## 2. Archivos

**Nuevos**
- `src/first/BootState.luau`, `src/first/Loading.client.luau` (y `ReplicatedFirst` en `default.project.json`)
- `src/shared/Config/Monetization.luau`, `src/shared/Catalog/Distortions.luau`
- `src/server/Services/MonetizationService.luau`, `src/server/Services/DistortionService.luau`
- `src/server/Distortions/HallwayBuilder.luau`, `src/server/Distortions/ImpossibleHallway.luau`
- `src/client/UI/PremiumPanel.luau`, `src/client/Controllers/DistortionController.luau`
- `docs/TIENDA_PREMIUM.md` y este documento

**Modificados**
- Compartido: `LightingRules`, `Net`, `Theme`, `GameConfig`, `Cosmetics`.
- Servidor:
  - Servicios: `LightingService`, `EconomyService`, `EquipmentService`, `DataService` (esquema v5), `ObserverService`, `HorrorDirector`, `RoundService`, `AnomalyService`, `AdminService`, `PingService`, `InteractionService`.
  - `Main`.
- Cliente:
  - `BlackoutFX`, `EffectsController`, `AudioController`, `LightController`, `MenuController`, `MenuLook`, `HUDController`, `NetController`, `SpectatorController`, `ToolController`, `AdminController`.
  - `ShopPanel`, `State`, `Main`.
- Pruebas: `tools/runtime_test.luau`, `tools/client_test.luau`.

## 3. Sistemas reutilizados (no se ha duplicado ninguno)

- **Luz:**
  - `LightingRules`, la única regla de luz, ahora con fases.
  - `LightingService`, `BlackoutFX`, `LightController`.
  - `VisualStandards` y `MenuLook`.
- **Economía y datos:** `EconomyService` y `EquipmentService` siguen siendo los dueños; `DataService` (con `Update` atómico y el nuevo `SaveNow`).
- **Interfaz:** `Kit`, `Theme`, `MenuController` y sus paneles, `HUDController`.
- **Entidades y director:** el Observer real (modelo, `ObserverFX`, sonidos), prestado. `HorrorDirector` (presupuesto y *dread*).
- **Realidad:** `RealityService` y `RealityOps` (huella de alcance PLAYER, revertida al acabar la ronda), `DoorService`, `MaterialLibrary` (texturas del pasillo).
- **Herramientas:** `AdminService` y el panel F8.

## 4. Pruebas ejecutadas (resultados reales)

| Herramienta | Antes | Ahora |
|---|---|---|
| `tools/runtime_test.luau` | 118.004 comprobaciones, 0 fallos | 118.338 comprobaciones, 0 fallos |
| `tools/client_test.luau` | 114.565 comprobaciones, 0 fallos, 36 controladores | 126.439 comprobaciones, 0 fallos, 37 controladores |
| `tools/check.sh` (luau-analyze) | 100 líneas de línea base | sin líneas nuevas; una menos que la línea base |

Qué cubren las nuevas comprobaciones:

- **Apagón.**
  - Ninguna caída supera el tope de brillo; con efectos reducidos nunca se apaga del todo.
  - Los 4 estilos son curvas distintas y nunca se repite el mismo dos veces seguidas.
  - La restauración empieza en el nivel del que viene y todas las lámparas vuelven antes de acabar.
  - El servidor lee el nivel durante la caída.
  - Las lámparas de emergencia no participan.
  - Sin corriente no hay restauración; un reinicio de ronda limpia una restauración a medias.
  - Ya no hay fundido a negro.
- **Tiendas.**
  - Compra válida; saldo insuficiente (no se gasta nada); dos peticiones seguidas (una compra, un cobro).
  - Equipar lo comprado; no equipar lo que no se tiene; los artículos de pase no se compran con Echoes.
  - Bloqueo por nivel; nada se vende en ronda.
  - Premium:
    - sin IDs todo sale PENDING y no se abre ninguna compra;
    - un recibo de un producto desconocido no se concede, ni tampoco con un perfil que no se puede guardar;
    - si el guardado falla, la concesión se deshace;
    - un recibo repetido se confirma sin conceder otra vez;
    - un acabado ya comprado no se puede volver a comprar;
    - el agradecimiento es repetible y da título e insignia una sola vez;
    - no se compra en ronda;
    - hay un único `ProcessReceipt`.
  - Cliente: estados, confirmación, botón en espera, motivo del rechazo, precio R$, OWNED, compra cancelada.
- **Carga y menú.** Fases y límites de tiempo; arranque único (`claim`); fases que no retroceden; sin porcentaje; RETRY; salida por condición real; PLAY espera al servidor.
- **Pasillo.**
  - Geometría: ninguna pieza estructural se solapa (comprobado par a par), la decoración no colisiona y hay una lámpara por segmento. El pasillo está lejos del mapa y la salida queda detrás del jugador.
  - Ritmo (simulado con la resistencia real): corriendo se sale en 24,2 s y lo más cerca que llega son 16,3 studs; andando, 32,6 s; quieto, te alcanza en 7,8 s.
  - Rechazos con su motivo: sin ronda, estado de ronda, fase de historia, director en FEAR, apagón mayor, Observer ocupado, Observer cerca, interacción, tutorial y evento no construido.
  - Una prueba forzada se salta el tiempo pero no la seguridad. Nunca hay dos a la vez; un jugador dentro y el otro no.
  - Flujo completo: break → arrive → NOTICE → WAKE → CHASE → salida. El Observer se presta y se devuelve exactamente una vez, y el jugador vuelve exactamente donde estaba.
  - La huella es solo suya y reportarla no penaliza.
  - Una tarea retrasada de una ejecución terminada nunca corre.
  - Morir dentro cancela; acabar la ronda cancela; "taken" no mata y suma *dread*; un error dentro también lo deshace todo.
  - Cliente: señales, lámparas, oscuridad, señales de otra ejecución ignoradas, la vista vuelve donde miraba y la red de seguridad cuando no llega el "return".

## 5. Pruebas pendientes en Roblox Studio

**Ninguna se ha hecho.** Por orden:

1. **Pasillo imposible** (pasos exactos en el apartado 7).
2. **Apagón.** Panel F8 → Blackout L1…L4, repetidos:
   - la caída se ve distinta cada vez y sin destellos;
   - las lámparas vuelven una a una;
   - el zumbido regresa;
   - sin luces atascadas tras "End blackout" y tras acabar la ronda;
   - con *Reduced flashes* activado, sin parpadeos.
3. **Carga.** Entrar a la experiencia:
   - la pantalla muestra las fases y se va sola;
   - con Network Simulator (latencia alta) sigue funcionando;
   - con un asset roto, la fase de recursos termina con aviso, no se cuelga.
4. **Menú.**
   - PLAY con y sin respuesta;
   - mando (foco en PLAY);
   - móvil (Device Emulator: iPhone, iPad, 720p y 4K).
5. **Tiendas.**
   - Comprar, equipar, saldo insuficiente.
   - Doble clic rápido: una sola compra.
   - Persistencia: salir, volver y seguir teniéndolo, con API Services activado.
6. **Tienda premium**, cuando tenga IDs (`docs/TIENDA_PREMIUM.md`, apartado "Comprobar en Studio").
7. **HUD.** Resoluciones distintas; textos legibles en una sala oscura; sin solapes entre subtítulos, coaching y slots.
8. **Multijugador** (Studio → Test → 2-4 jugadores):
   - pasillo con un compañero cerca: él sigue en el edificio y no ve nada raro salvo que el otro "no está";
   - si el compañero espectea, ve SIGNAL LOST;
   - repetir el pasillo en otra ronda.

## 6. IDs y configuración manual

- **Robux.** Rellenar los `id = 0` de `src/shared/Config/Monetization.luau`: 3 Game Passes y 3 Developer Products. Pasos en `docs/TIENDA_PREMIUM.md`.
- **Nada más.** No hacen falta IDs nuevos de imágenes ni de sonido: todo usa los assets que ya existen.

## 7. Cómo probar el pasillo imposible (pasos exactos)

1. Sincroniza la rama `dev/alvaro-trabajo` con Rojo y dale a **Play** en Studio.
2. En el menú, PLAY. En el Field Office, prepárate e inicia una ronda.
3. Entra en el edificio. No hace falta esperar a la fase DISTORTION: la prueba forzada se salta el tiempo.
4. Pulsa **F8**:
   - **Distortion: list** debe decir `ImpossibleHallway [SPACE] ready`.
   - **Distortion: status** debe decir `idle` y si la ronda lo permite ahora.
5. Selecciona tu jugador en la lista de objetivos (o ninguno: serás tú) y pulsa **Distortion: hallway (target)**.
   - Si lo rechaza, el panel dice el motivo. Por ejemplo, "The Observer is near them": aléjate o pulsa *Despawn entities*.
6. Comprueba:
   - **la ruptura:** parpadeo, el sonido se corta, corte a negro;
   - **el pasillo:** largo, puertas B-13, tubos fluorescentes;
   - **la presencia:** al fondo, lejos, el Observer quieto mirándote durante unos segundos;
   - **el despertar:** se apagan las luces a su alrededor y empieza a venir;
   - **la persecución:**
     - la salida (EXIT) está a tu espalda;
     - mirarlo con la linterna lo detiene un momento, pero parpadeas;
     - si te paras, te alcanza;
     - corriendo y andando se llega.
7. Al cruzar la puerta: corte a negro y estás donde estabas, mirando a donde mirabas. Busca la diferencia en la habitación.
8. **Distortion: report** muestra la duración, el resultado, la línea de fases, si se restauró y la huella.
9. **Cancelaciones:**
   - **Distortion: cancel** a mitad;
   - *Kill me* dentro;
   - *End round* dentro;
   - salir del juego dentro (con 2 jugadores).

   En todos los casos el jugador debe quedar fuera del pasillo y el Observer libre: **Observer status** debe decir `mode nil`.

## 8. Problemas conocidos y límites

- **Sin pruebas visuales todavía.**
  - El aspecto del pasillo (colores, niebla, lo largo que parece), la silueta del Observer a 125 studs y la sensación de la persecución solo se pueden juzgar en Studio.
  - Los valores de ritmo están en `ImpossibleHallway.Pace`, por si hay que ajustarlos.
- **Animación del Observer en el pasillo.** Usa la de siempre (`ObserverFX` según `Behavior` y su movimiento). Hay que verificar en Studio que camina bien por el suelo del pasillo (Humanoid, sin pathfinding).
- **El pasillo se replica.** Se envía a los clientes cada vez que se usa (unas 500 piezas), detrás del corte a negro. Si se nota un tirón, se puede dejar construido permanentemente.
- **Huella de puerta.** Es global: los compañeros también ven la puerta abierta. Las otras dos huellas son solo del jugador.
- **Pagos.** Ninguno funciona hasta poner los IDs.
- **Distorsiones solo diseñadas.** El intruso, El bucle y La habitación equivocada están en el catálogo pero sin construir, a propósito.
- **Pruebas de pagos.** Las pruebas automáticas de recibos usan dobles del DataStore y de `MarketplaceService`. La prueba real de pagos es la de Studio, con API Services activado.
