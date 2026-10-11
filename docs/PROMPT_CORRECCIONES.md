# Prompt: pasada de coherencia (jugabilidad, visual e inconsistencias)

Copia todo lo que hay debajo de la línea en una sesión nueva de Claude Code
abierta sobre este repositorio.

---

Eres el desarrollador de **DON'T LOOK AWAY**, un juego de terror cooperativo
para Roblox (1-4 jugadores) hecho con Rojo y Luau. Lee primero `README.md` y
`docs/FALLOS_PENDIENTES.md`. Después haz una **pasada de coherencia**: corrige
los errores de jugabilidad, las incoherencias visuales y las contradicciones
entre el código, los textos del juego y la documentación que se listan abajo.
Todos los hallazgos están comprobados leyendo el código. Antes de tocar cada
uno, vuelve a confirmarlo en el código: las líneas pueden haberse movido.

## Reglas de trabajo

1. Trabaja en una rama nueva. Haz un commit por cada punto, con mensajes en
   inglés al estilo del repo (`Area: what is now true`, por ejemplo
   `Round: the shutter closing is not an Observer catch`).
2. Respeta el estilo del código: Luau con tipos, tabulaciones, comentarios en
   inglés que explican el porqué y servicios conectados mediante `Registry`.
   Todo número que se pueda ajustar va en `src/shared/Config/GameConfig.luau`.
   Los colores de la interfaz van en `src/shared/Theme.luau` y las superficies
   y luces en `src/shared/VisualStandards.luau`.
3. El servidor manda en todo. No muevas ninguna decisión de juego al cliente.
4. **No inventes IDs de assets** ni cambies los que hay en
   `src/shared/Config/AssetIds.luau`. Lo que dependa de subir archivos a Roblox
   apúntalo como pendiente.
5. No toques `src/marketing/`, ni el diseño del Observer (forma, mallas,
   piel) ni la economía o los precios. Esto es una pasada de coherencia, no un
   rediseño.
6. Si un punto pide una decisión de diseño que no se puede sacar del código
   (está marcado con **DECIDIR**), aplica la opción recomendada, déjala
   documentada en el comentario de cabecera del servicio y menciónala en el
   resumen final.
7. Verifica con lo que haya instalado: `tools/check.sh` (luau-analyze),
   `rojo build default.project.json -o build/test.rbxlx` y las pruebas de Lune
   (`tools/runtime_test.luau`, `tools/client_test.luau`,
   `tools/validate_map.luau`). Si falta alguna herramienta, dilo y explica cómo
   comprobar el cambio en Studio. Añade casos a `tools/runtime_test.luau` para
   los arreglos de la sección A.

## A. Jugabilidad (por prioridad)

### A1. Los objetos clave desaparecen al morir o desconectarse (la ronda queda bloqueada)
- `src/shared/Catalog/Items.luau` marca `FUSE`, `MAINT_KEY`, `OFFICE_KEY`,
  `TAPE`… con `important = true`, pero nada lee esa marca.
- `RoundService:KillPlayer` (`src/server/Services/RoundService.luau`) no suelta
  el inventario. `InventoryService` (`PlayerRemoving`, `Reset`) lo borra al
  salir o al volver a entrar.
- Resultado: si muere quien lleva la única llave de Mantenimiento o los
  fusibles, nadie puede terminar la ronda hasta el límite de 22 minutos.
- **Arreglo:** al morir, al salir de la partida y antes de `Reset` en
  `TryRejoin`, todo objeto `important` cae como pickup en el suelo. Usa la
  posición del jugador, ajustada a un punto alcanzable dentro del edificio
  (reutiliza `dropSlot` o los puntos de `room.itemSpots`), y avisa al equipo
  con un `Notify`. Si el jugador muere fuera del mapa jugable, el objeto
  vuelve a su sitio original.
- **Hecho cuando:** una prueba en `runtime_test` mata al portador de
  `MAINT_KEY` y comprueba que existe un pickup `MAINT_KEY` alcanzable.

### A2. La ronda se puede perder en plena huida por anomalías «no vistas»
- `AnomalyService:Expire` suma `missed` y llama a `FailRound` al llegar a
  `MaxMissed`, también en estado `ESCAPE` y también cuando la cuota ya está
  cumplida.
- Al empezar la huida, `startEscape` (`RoundService.luau`, ~línea 314) fuerza 4
  anomalías GLOBAL, y el director sigue generando más. En NIGHTMARE
  `AnomalyLifetime` es 115 s y `EscapeWindow` 150 s: caducan antes de que se
  cierre la persiana y pueden hacer perder a todos en la puerta.
- La anomalía del tutorial (`SpawnTutorial`, `spec.lifetime = 240`) también
  cuenta como fallo para un jugador nuevo.
- **Arreglo:** una anomalía que caduca solo cuenta como fallo si la cuota
  (`locks.ANOMALIES`) sigue pendiente y la ronda no está en `ESCAPE`. Las
  anomalías de la huida y la del tutorial llevan `noMiss = true`. No se
  generan anomalías nuevas en `ESCAPE` aparte de las de `startEscape`.

### A3. Morir porque se cierra la persiana se presenta como «te atrapó»
- `RoundService.luau:571` llama a `KillPlayer(p, nil)`. El cliente
  (`DeathController.deathSequence`) muestra «YOU WERE TAKEN — It was right
  there when you looked away» y `computeEndings` lo cuenta como
  `ObserverCaughtYou`.
- **Arreglo:** crea un final propio (por ejemplo `Enums.Ending.LockedIn`) con
  su título y su texto en el cliente, sin el tirón de cámara hacia un atacante
  que no existe. Muestra el final correcto en `ResultsController`, en los
  logros y en la analítica. Lo mismo para `FailRound` (colapso por anomalías):
  revisa que título, subtítulo y final digan lo mismo.

### A4. «Mirar» al Observer no significa lo mismo en cada sitio
- Los semiángulos son distintos en cada lugar: 64° para congelarlo
  (`watchers`, `GameConfig.Observer.WatchFOV`), 62° para que una anomalía
  cuente como no vista (`AnomalyService.isUnseen`), 40° y 70° en el
  avistamiento (`ObserverService.luau:1029` y `:1039`) y 18°, 25° y 30° en
  otros puntos.
- Con FOV vertical 74 en 16:9 el semiángulo horizontal real es de ~53°: con
  64° el Observer se queda congelado estando fuera de la pantalla. Además, el
  servidor no conoce el FOV que el jugador eligió (60-95).
- La percepción no tiene en cuenta la luz. En un apagón total, a 140 studs y
  sin linterna, «miras» algo que no puedes ver y lo congelas igual.
- **Arreglo:**
  - Centraliza en `GameConfig.Perception` tres valores con nombre: en pantalla
    (congelar), periferia (que una anomalía no cambie a la vista) y foco
    (reportar o reconocer).
  - El cliente manda su FOV horizontal efectivo junto con el rayo de visión, y
    el servidor lo limita a un rango válido.
  - **DECIDIR** (recomendado): en oscuridad (`dark`, ver A5) el Observer solo
    queda congelado si está dentro del haz de la linterna del que mira, en el
    radio de una fuente de luz encendida o a menos de ~12 studs.

### A5. Tres definiciones distintas de «está oscuro»
- `HorrorDirector.luau:577`: `GetBlackout() >= 3`.
- `ObserverService.luau:1119`: `>= 3 or not IsPowered()`.
- `ObserverService.luau:538`: lo mismo, más «y la víctima no lleva la luz».
- **Arreglo:** un único `LightingService:IsDark(position?)` que usen todos.

### A6. El aviso de la respiración no deja reaccionar
- Respira a 14 studs (`ObserverService.luau:1103`) y ataca 0,3-0,8 s después,
  desde `CatchDistance + 1.5` (5,7 studs). A 13,5-17,5 studs/s recorre esa
  distancia en ~0,5-0,6 s. El comentario dice «you always hear it before it
  can reach you», pero no hay tiempo de girarse.
- NORMAL se describe como «slower and more readable Observer», pero
  `ObserverSpeed = 13.5` va por encima de la marcha (10). Correr (17) solo
  dura ~6 s.
- **Arreglo:** el radio del aviso y la espera antes del ataque pasan a
  `GameConfig.Difficulty` y garantizan al menos ~1,2 s (NORMAL), ~0,9 s
  (HARD) y ~0,6 s (NIGHTMARE) entre oír la respiración y poder ser atrapado,
  contando también los saltos de `blinkStep`. Revisa que la velocidad de
  NORMAL cuadre con lo que dice su descripción, o cambia la descripción.

### A7. El apagón total del COLLAPSE depende de que haya luz
- `maybeBlackout` sale si no hay corriente. Si el equipo nunca la restaura,
  no llegan ni el «total blackout» que promete la cabecera de
  `HorrorDirector` ni la anomalía `darkOnly`.
- **Arreglo:** sin corriente, el COLLAPSE apaga también las balizas y los
  rótulos de salida durante el mismo tiempo (nivel 4 sobre `EMERGENCY`).
  Documenta la regla.

### A8. Sustos que rompen la regla de «solo cambia cuando no miras»
- `SCARES.falling_box` hace `PivotTo` de golpe a 80° sin comprobar si alguien
  lo ve. Si lo ven, parece un fallo gráfico. Además puede dejar la caja
  atravesando paredes o tapando el paso.
- `startEscape` y el apagón de nivel 4 fuerzan anomalías con
  `ignoreVisibility = true`.
- **Arreglo:** la caja cae con física (sin anclar, con un pequeño impulso) o
  con un tween corto, solo fuera de la vista o justo en el borde del campo de
  visión, y la posición final se valida con las reglas de
  `GeometryValidator`. **DECIDIR** (recomendado): las anomalías visibles en la
  huida se quedan como excepción consciente («the building fights back»),
  escrita en la cabecera de `AnomalyService` y del README.

## B. Coherencia visual

### B1. Los presets de luz contradicen la dirección de arte
- `LightingService.Presets`: `ESCAPE` (ambiente 28,20,20, exposición +0,3,
  bruma 2,3) y `CINEMATIC` (ambiente 26, bruma 1,6) son 3-4 veces más claros
  y brumosos que `NORMAL` (7,7,8, bruma 0,2). El clímax queda más iluminado y
  gris que el resto de la partida, y el comentario de `CINEMATIC` dice «the
  same building, harder and colder».
- La exposición no baja en orden: `BLACKOUT` tiene +0,1, `EMERGENCY` +0,05 y
  `NORMAL` 0. El commit `0ac0bcb` dice «every blackout level is a visible step
  down».
- `LightingService.luau:48` («Ambient values are the never blind floor»)
  contradice la cabecera del mismo archivo («Darkness is dark»).
- **Arreglo:** `ESCAPE` y `CINEMATIC` derivan de `NORMAL` o `EMERGENCY` con un
  tinte (rojo para la huida) y sin subir ambiente, exposición ni bruma. La
  exposición baja con cada nivel: NORMAL ≥ EMERGENCY ≥ BLACKOUT. Corrige el
  comentario. `RESULTS` y `LOBBY` pueden ser más claros: no son el edificio.

### B2. Tirones de cámara y LOD que salta de golpe (ver FALLOS_PENDIENTES §1)
- `CameraController.fpsCFrame` escribe `root.CFrame` en cada frame de render
  y coloca la cámara en `head.Position` sin interpolar.
  **Arreglo:** el giro del cuerpo con `AlignOrientation` o
  `Humanoid.AutoRotate` en el paso de física, y la cámara sobre la posición
  interpolada.
- `DetailLOD:Update` oculta y muestra sin histéresis.
  **Arreglo:** margen de ±10 % y escalonar los cambios entre varios frames.
- `LightController` recorre `Workspace:GetDescendants()` en cada cambio de
  `Power` y evalúa todos los fixtures en el mismo frame cada 0,35 s.
  **Arreglo:** cachear la lista de fixtures por ronda y repartir la
  evaluación entre varios frames.

### B3. Superficies de «plástico»
- `VisualStandards.Surfaces` usa `SmoothPlastic` para `porcelain`, `grime`,
  `paper` y `plastic`, y `src/server/Map/Props.luau` tiene 63 piezas con
  `SmoothPlastic`. `MaterialService` no sustituye `Plastic` ni
  `SmoothPlastic` (`default.project.json`).
- **Arreglo:** cambia cada pieza a la superficie de `VisualStandards` que le
  corresponde (papel → `Fabric` o `Plaster` mate, suciedad → `Concrete`,
  cerámica → `Marble` o `CeramicTiles`). Deja `SmoothPlastic` solo donde un
  `SurfaceAppearance` lo cubra entero. Ejecuta `tools/zfight.luau` y
  `tools/validate_map.luau` después.
- El repintado de los mapas de rugosidad (FALLOS §6) necesita volver a subir
  los archivos: apúntalo como pendiente, no lo hagas.

### B4. Colores de la interfaz fuera de `Theme`
- `HUDController` (tarjetas «NEW EQUIPMENT» 150,190,230 y «ARCHIVE»
  196,178,140; nota de papel 214,206,184), `PuzzleUI` (papel, teclado, verde
  de LCD, rojo de error) y `ToolController` repiten colores casi iguales a
  `Theme.Colors.Accent` o `Danger`, o inventan otros.
- **Arreglo:** añade a `Theme.Colors` los tonos que faltan (`Paper`, `Ink`,
  `Lcd`, `LcdError`, `Archive`) y úsalos. El rojo solo se usa para el peligro,
  como dice la cabecera de `Theme`. Revisa que el rojo del error del teclado
  sea `Theme.Colors.Danger` o un derivado.

## C. Inconsistencias entre código, textos y documentación

1. `README.md:176` dice «Darkness never goes fully black: the eye adapts».
   La luz de adaptación se quitó (`54096d0`). Reescríbelo según el diseño
   actual: la oscuridad es oscura y el ajuste de brillo da ±0,04. Así queda
   resuelto el punto §7 de FALLOS_PENDIENTES: escribe la regla (oscuro en
   juego; el susto final negro y local es una excepción deliberada).
2. `ObjectiveService.luau:10` dice «there are no waypoint markers», pero
   `GuidanceService` (nivel 5) muestra un marcador. Corrige el comentario.
3. `TutorialController.luau:129` dice «Hold [Ping] to point things out». En
   realidad, pulsar hace un ping inteligente y mantener abre la rueda. Cambia
   el texto.
4. El bloque CONTROLS de `MenuController.luau:128` no menciona el cinturón de
   herramientas (5-9 / V / T) ni los emotes (B), que sí están en el README.
   Añádelos con `IC:Label`.
5. `ObserverService.luau:1251` siempre culpa de que no carguen las mallas a
   «the place must be the published experience that owns them». Distingue el
   caso de los IDs a 0 o descartados (por ejemplo, la cabeza vieja) del error
   de permisos.
6. `docs/OBSERVER_REDESIGN.md` describe un diseño sustituido (cabeza de 4,6
   studs, susto a 3 studs). Pon un aviso al principio que remita a
   `OBSERVER_V2.md` y al código actual.
7. Al terminar, actualiza `docs/FALLOS_PENDIENTES.md`: marca como ARREGLADO
   (con el hash del commit) lo que corresponda y añade lo que quede pendiente
   de Studio o de subir assets.

## Fuera de alcance

- Subir assets, cambiar IDs o volver a hornear texturas.
- Rediseñar el Observer (FALLOS §4 espera una respuesta del autor).
- `src/marketing/`, la economía, los precios y los game passes.

## Resumen final que debes entregar

Una tabla con cada punto (A1…C7) con: arreglado / parcialmente / no, el
commit, cómo se verificó (prueba de Lune, luau-analyze o «solo en Studio:
pasos») y las decisiones **DECIDIR** que tomaste.
