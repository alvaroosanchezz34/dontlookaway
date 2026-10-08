# MARKETING STUDIO

Herramienta **solo para desarrollo**. Sirve para grabar teasers, trailers y clips verticales (TikTok, Shorts, Reels) de DON'T LOOK AWAY dentro de Roblox Studio.

- No cambia gameplay, economía, progresión, datos ni la UI del juego.
- Todo lo que hace es **local a tu pantalla**: nada se replica y no existe ningún RemoteEvent.
- Al terminar una escena, `CleanupMarketingScene()` devuelve el juego exactamente a su estado anterior.

## Estructura

```
src/marketing/
├── shared/   → ReplicatedStorage.Marketing
│   ├── MarketingConfig.luau     interruptor, usuarios autorizados, textos
│   └── MarketingAccess.luau     reglas de acceso (dónde y quién)
├── server/   → ServerScriptService.Marketing
│   └── MarketingGate.server.luau  concede el acceso (atributo del jugador)
└── client/   → StarterPlayerScripts.Marketing
    ├── MarketingStudio.client.luau  arranque (comprueba las 3 puertas)
    ├── MarketingController.luau     Play/Stop/Pause/Resume/Restart/List + cleanup
    ├── Timeline.luau                reloj de la escena (eventos y spans)
    ├── Actions.luau                 vocabulario de eventos
    ├── Runtime.luau                 MarketingRuntime + restauración garantizada
    ├── Cameras/  CameraRig, Presets
    ├── Effects/  Screen (formato, fundidos, glitch, CCTV, grade), LightFX,
    │             Doors, Eye, Figures
    ├── Audio/    MarketingAudio
    ├── Text/     Titles
    ├── Utilities/ Locations, Ease, Format
    ├── Scenes/   Scene01_Door … Scene08_Launch
    └── UI/       Panel
```

### Qué reutiliza del juego (sin modificarlo)

| Recurso del juego | Para qué se usa |
|---|---|
| `SoundFactory` y los 99 sonidos propios (`AudioLibrary`) | Todo el audio de las escenas |
| `ObserverRig.build(..., { localCopy = true })` | La silueta de la entidad, con las mallas esculpidas si están cargadas |
| `LightController:FlickerNear` | Parpadeo de las lámparas reales del edificio |
| Atributos `ClosedCFrame` / `OpenCFrame` de las puertas | Abrir puertas solo en tu pantalla |
| Etiquetas `Door` y `Mirror`, y suelos con atributo `Room` | Encontrar planos en el mapa procedural |
| `Util/Signal` | Eventos internos del controlador |

## 1. Activar Marketing Studio

Tienen que cumplirse **las tres** condiciones:

1. `MarketingConfig.Enabled = true` (viene así).
2. El entorno lo permite:
   - Roblox Studio: sí, con `AllowInStudio = true`.
   - Servidor privado (VIP): solo si pones `AllowInPrivateServers = true`.
   - Servidores públicos: **nunca**, sea cual sea la configuración.
3. El servidor te ha autorizado (ver el punto 2).

En producción no hace falta tocar nada: en servidores públicos el script del servidor sale sin hacer nada y el del cliente también.

## 2. Añadir un usuario autorizado

En `shared/MarketingConfig.luau`:

```lua
MarketingConfig.AdminUserIds = { 123456789 }
```

Ya están autorizados sin añadir nada:

- el propietario de la experiencia (si es de un usuario);
- los jugadores de prueba de Studio (Test → Clients and Servers).

## 3. Ejecutar Scene01 en Studio

1. `rojo serve` + conectar, o `rojo build` y abrir el `.rbxlx`.
2. **Play** en Studio. En la salida verás `[Marketing] Marketing Studio ready: 8 scenes · F7 to open`.
3. Para usar los lugares reales de Ashgrove:
   - Empieza una ronda: F8 → *Start round*.
   - Graba en **ARRIVAL**: luces encendidas y sin Observer.
   - Sin ronda (lobby o baseplate), las escenas usan un decorado virtual delante de la cámara. Las escenas en negro (04 y 07) no necesitan mapa.
4. Pulsa **F7** (o **F6**, o el botón **🎬** abajo a la derecha), elige **Scene01_Door** y pulsa **▶ PLAY**.
   - El panel se oculta mientras graba y vuelve al terminar.
   - **■ STOP** limpia la escena en cualquier momento.

También desde la consola de comandos de Studio, en el cliente:

```lua
local MC = require(game.Players.LocalPlayer.PlayerScripts.Marketing.MarketingController)
MC.PlayScene("Scene01_Door")   -- MC.StopScene()  MC.PauseScene()  MC.ResumeScene()
print(MC.ListScenes())         -- MC.RestartScene()  MC.CleanupMarketingScene()
```

## 4. Grabar el vídeo (9:16)

- **Format: 9:16** (por defecto) enmarca la escena en un rectángulo vertical centrado con bandas negras.
- En OBS:
  1. Captura la ventana de Studio.
  2. Recorta al rectángulo central, o pon un lienzo de 1080×1920 y escala.
  3. Usa F11 / pantalla completa en Studio para más resolución.
- También hay **16:9** (YouTube) y **1:1**.
- La cámara mantiene el campo de visión vertical, así que el recorte 9:16 encuadra exactamente lo diseñado.
- Opciones del panel:

  | Opción | Qué hace |
  |---|---|
  | *Hide HUD* | Oculta la interfaz del juego |
  | *Hide me* | Oculta tu personaje |
  | *Freeze me* | Deja tu personaje quieto |
  | *Mute game* | Solo suenan los sonidos de la escena |
  | *Slow-mo* | 0,5× (escenas y sonido) |
  | *Loop* | Repite la escena |
  | *Camera* | Fuerza un preset en todos los planos (`AUTO` = el de cada plano) |

- No se renderiza MP4 desde Roblox: la escena se prepara para grabarla con OBS o con la captura de Roblox.

## 5. Crear una escena nueva

Crea `client/Scenes/Scene09_MiEscena.luau`. Aparece sola en el panel, ordenada por nombre.

```lua
return {
	Name = "Scene09_MiEscena",
	Description = "Una luz al fondo del pasillo",
	Duration = 10,
	Build = function(L, Config)
		-- L = Utilities/Locations: corridor, doorShot, roomShot, cctvShot, mirror, reference...
		local from, _, length = L.corridor("U")
		return {
			{ at = 0,   action = "SetCamera", cframe = from, preset = "HALLWAY" },
			{ at = 0,   action = "Grade", grade = "dread" },
			{ at = 0,   action = "FadeFromBlack", from = 1, duration = 1 },
			{ at = 0,   action = "PlayAmbience", sound = "AmbientDrone" },
			{ at = 0,   action = "MoveCamera", to = from * CFrame.new(0, 0, -10), duration = 6, ease = "creep" },
			{ at = 4,   action = "FlickerLights", position = L.corridorPoint("U", 0.5, 12), duration = 1.2 },
			{ at = 7,   action = "ShowEye", mode = "world", position = L.corridorPoint("U", 0.9, 6), fade = 0.2 },
			{ at = 7.3, action = "HideEye" },
			{ at = 9,   action = "CutToBlack" },
		}
	end,
}
```

Reglas de un timeline:

- `at` es el segundo en el que ocurre el evento; el orden en la lista da igual.
- Todo lo que dura algo (movimientos, fundidos, puertas) sigue el reloj de la escena: la pausa y la cámara lenta funcionan solas.
- `Duration` es cuándo termina. Después se mantiene `HoldAtEnd` y se limpia.

## 6. Eventos disponibles (Actions.luau)

| Grupo | Eventos |
|---|---|
| Cámara | `SetCamera` / `Cut` / `TeleportCamera`, `MoveCamera`, `SetFOV`, `ShakeCamera`, `Jolt`, `TrackTarget`, `StopTracking` |
| Luz | `SetLighting`, `FadeLights`, `RestoreLights`, `Blackout`, `FlickerLights`, `KeyLight`, `KeyLightOff`, `Fog`, `Grade`, `Vignette`, `Blur`, `LookPreset` (sección 13) |
| Sonido | `PlaySound`, `PlayAmbience`, `StopSound`, `Silence`, `Unsilence`, `MuteGame` |
| Objetos | `UseDoor`, `OpenDoor`, `CloseDoor`, `SpawnEffect` (`person` / `entity`), `DestroyEffect`, `MoveObject`, `FadeObject` |
| Ojo | `ShowEye`, `HideEye`, `BlinkEye`, `EyeLook`, `SetEye` |
| Pantalla | `Glitch`, `CCTV`, `ShowText`, `HideText`, `SurfaceText`, `WriteText`, `Backdrop`, `FadeToBlack`, `FadeFromBlack`, `CutToBlack` |
| Otros | `Wait`, `RunCallback` |

### Crear un evento nuevo

```lua
-- en Actions.luau (o en un módulo tuyo que lo registre)
Actions.register("Pulse", function(tl, e)
	tl:span(e.duration or 1, "inOutSine", function(a)
		-- a va de 0 a 1 con el reloj de la escena
	end, e.at)
end)
```

Si cambias algo que ya existía en el mundo, hazlo con `Runtime.setProp(inst, "Prop", valor)` o registra la restauración con `Runtime.onCleanup(fn)`. Lo que crees, ponlo en `Runtime.folder()` (Workspace.MarketingRuntime) o pásalo por `Runtime.track(inst)`.

## 7. Cámaras

Presets en `Cameras/Presets.luau`:

`CCTV`, `STATIC`, `HANDHELD`, `FIRST_PERSON`, `CINEMATIC`, `CLOSE_UP`, `EYE_CLOSEUP`, `DOOR_SHOT`, `HALLWAY`

Cada preset define el campo de visión, el balanceo de mano, la deriva y, en el caso de CCTV, el overlay y la imagen a 12 fps. Para crear uno nuevo, añade una entrada a la tabla y aparece en el panel.

La cámara de marketing va en su propio render step, **después** de la del juego. El servidor sigue viendo tu vista real, así que la percepción del juego no se altera, y al parar vuelve la cámara normal.

## 8. Audio

```lua
{ at = 2, action = "PlaySound", sound = "DoorOpen", position = Vector3.new(...),
  volume = 0.7, speed = 0.8, startTime = 0, duration = 3, fadeIn = 0.2, fadeOut = 0.5, name = "puerta" }
```

- `sound` puede ser:
  - cualquier clave de `AudioLibrary` (por ejemplo `"Whisper"`, `"ObserverSting"`, `"MusicPad"`);
  - un `"rbxassetid://..."` tuyo (solo audio con derechos).
- Sin `position` el sonido es 2D.
- `Silence` / `Unsilence` bajan y suben solo los sonidos de la escena.
- *Mute game* silencia el juego durante la escena.

## 9. El ojo

- **Modo `world`:** un billboard en la escena (detrás de una puerta, al fondo de un pasillo).
- **Modo `screen`:** primer plano a pantalla completa.
- Está dibujado con formas, sin texturas ni assets externos, en el mismo lenguaje que el ojo de los cuadros alterados del juego.

| Evento | Qué hace |
|---|---|
| `ShowEye` | `mode`, `position`, `scale`, `intensity`, `fade`, `open`, `look` |
| `SetEye` | Anima `intensity`, `scale`, `pupil`, `open`, `opacity` y `position` |
| `BlinkEye` | Parpadeo |
| `EyeLook` | Mira a la cámara (`"camera"`), a un punto `Vector3` o a una dirección `Vector2` |
| `HideEye` | Lo hace desaparecer |

## 10. Limpieza

`MarketingController.CleanupMarketingScene()` (se llama sola al parar o terminar):

- quita el render step y devuelve la cámara y el FOV;
- restaura iluminación, exposición y niebla, pero solo si el juego no las cambió entretanto;
- borra grade y blur;
- devuelve las puertas al estado que marca el juego;
- borra figuras, ojo, textos y luces de la escena;
- para los sonidos y devuelve el volumen de los grupos de audio del juego;
- vuelve a mostrar el HUD y la UI de Roblox;
- vacía Workspace.MarketingRuntime y PlayerGui.MarketingRuntimeGui.

Se puede llamar las veces que haga falta. Si el personaje se reinicia a mitad de escena, también se limpia sola.

## Tests

`tools/client_test.luau`, sección "marketing studio":

- ejecuta las 8 escenas sin mapa y dentro de un edificio de prueba;
- comprueba que cada una termina sola y que no queda nada en MarketingRuntime;
- comprueba que iluminación, cámara, GUI y audio vuelven a su estado;
- comprueba que la puerta real vuelve a su sitio;
- prueba pausa, reanudar, cámara lenta, reiniciar, parar y limpieza repetida.

`tools/runtime_test.luau`, sección "marketing studio access", comprueba las reglas de acceso:

- nunca en servidores públicos;
- solo usuarios autorizados;
- los servidores privados solo si se activan.

## 11. Imágenes de la campaña (ojo realista y título rayado)

Están en `assets/marketing/`. Son originales: las generan `tools/gen_eye.py` y `tools/gen_title.py`, sin imágenes externas.

| Archivo | Campo en `MarketingConfig` |
|---|---|
| `eye/eye_sclera.png` | `EyeImages.sclera` |
| `eye/eye_iris.png` | `EyeImages.iris` |
| `eye/eye_pupil.png` | `EyeImages.pupil` |
| `eye/eye_glint.png` | `EyeImages.glint` |
| `eye/eye_lid_top.png` | `EyeImages.lidTop` |
| `eye/eye_lid_bot.png` | `EyeImages.lidBottom` |
| `eye/eye_socket.png` | `EyeImages.socket` |
| `title_dla.png` | `TitleImage` |

Súbelas como **imágenes** (Gestor de recursos → Importar, o Creator Hub) y pega los IDs en `shared/MarketingConfig.luau` (o pásamelos).

- Mientras falten, se usan el ojo dibujado y el título de texto.
- `eye_preview.png` y `title_preview.png` son solo vistas previas: no hace falta subirlas.

Para regenerarlas:

```bash
python3 tools/gen_eye.py
python3 tools/gen_title.py
```

## 12. Catálogo de escenas (56)

En el panel (F7, F6 o 🎬) las escenas salen **agrupadas por categoría**, con su duración. Al elegir una se muestra su descripción, y el buscador filtra por nombre, categoría o palabras de la descripción.

| Categoría | Archivo | Escenas | Dónde ocurre |
|---|---|---|---|
| 0 · ORIGINALS | `Scenes/Scene01…08` | Door, DidYouSeeIt, CAM04, TheEye, TheMessage, TheHallway, FinalWarning, Launch | mapa o decorados |
| A · THE EYE | `Scenes/A_TheEye.luau` | EyeInTheDark, EyeBehindDoor, EyeTracksCamera, TheWrongBlink, EyeInTheReflection, EyeAppearsForOneFrame | decorado puerta / habitación |
| B · CCTV | `Scenes/B_CCTV.luau` | CAM04_Anomaly, CAM07_ImpossibleMovement, CCTV_LookBehindYou, CCTV_TheExtraPerson, CCTV_TheCameraTurns, CCTV_TimeLoop | pasillo del mapa / habitación |
| C · DOORS & HALLWAYS | `Scenes/C_DoorsHallways.luau` | DoorOpensByItself, SomethingAtTheEnd, TheDoorWasOpen, TheHallwayChanges, TheDoorBehindYou, TheEndlessHallway | decorado puerta / pasillos del mapa |
| D · FIGURES | `Scenes/D_Figures.luau` | TheFigureAtTheWindow, TheFigureDoesNotMove, TheEmptyRoom, TheObserverIsWatching, TheFigureBehindTheCamera, TheWrongShadow, TheRoomIsWatching | habitación / pasillo |
| E · MESSAGES | `Scenes/E_Messages.luau` | DontLookAway, TheMessageChanges, ThisVideoIsWrong, TheCameraNoticesYou, YouMissedSomething, TheFinalWarning | negro / habitación / pasillo |
| F · SOUND | `Scenes/F_Sound.luau` | TheBreathingRoom, FootstepsApproaching, TheSilence, WhisperFromTheWall, TheSoundFollows | habitación / pasillo |
| G · MICRO (4–6 s) | `Scenes/G_Micro.luau` | MicroEyeReveal, MicroDoorMovement, MicroCAM04, MicroShadow, MicroFigureBehindCamera, MicroOneFrameAnomaly, MicroFinalWarning, MicroDidYouSeeIt, MicroTheWrongReflection, MicroTheDoorWasOpen | todas |
| H · LOOKS | `Scenes/H_Looks.luau` | LookBook (los 8 looks rotulados), DoorAjarToEye | habitación + pasillo / decorado puerta |

**Dónde graban:**

- **Decorados** (`Effects/Sets.luau`): no necesitan ronda y siempre se ven igual.
  - `doorway`: la puerta del póster con la lámpara colgante.
  - `room`: una habitación con ventana a la noche, espejo, puerta a negro, silla, mesa y lámpara.
- **Pasillos del mapa:** con una ronda en marcha usan el pasillo real de Ashgrove (F8 → Start round, mejor en ARRIVAL). Sin ronda, un decorado virtual.

**Qué reutiliza cada categoría:**

| Categoría | Recursos |
|---|---|
| A | El ojo (capas `EyeImages`, o el ojo dibujado si no cargan), la lámpara del decorado, sonidos `ObserverInhale` / `ObserverSting` |
| B | Overlay CCTV (12 fps, REC, reloj), el Observer (`ObserverRig`, copia local), la copia de tu avatar, la cámara de seguridad física (`Sets.cctvCamera`), estática de señal perdida |
| C | Puertas reales del mapa (se mueven solo en tu pantalla y vuelven a su sitio), `LightController` para el parpadeo real, `Doors.prop` para la puerta que aparece |
| D | Observer, sombras de pared (`Figures.shadow`), brillos de ojos (`Figures.shine`), maniquíes |
| E | Títulos, texto en pared, título rayado (`TitleImage`), ojo |
| F | Audio 3D de la librería del juego: `Breath`, `StepConcrete`, `Whisper`, `KnockDoor`, `FootstepsBehind`… |
| G | Todo lo anterior, en versión corta |

**Acciones nuevas:**

| Acción | Qué hace |
|---|---|
| `PlaceObject` | Mueve una figura u objeto al instante |
| `AdoptObject` | Hace movible una pieza del decorado |
| `Static` | Nieve de señal perdida |
| `FreezeFrame` | Congela la imagen |
| `EyeLook` `target = "follow"` | El ojo sigue a la cámara, con retardo |
| `SpawnEffect` | Nuevos `kind`: `shadow`, `shine` y `actor` |

**Añadir más escenas:** crea un módulo en `Scenes/` (una escena, o un paquete `{ Category = "...", Scenes = { ... } }`) y aparece solo en el panel. Los atajos comunes están en `Utilities/Shots.luau`: `open`, `room`, `doorway`, `cctv`, `black`, `cut`, `steps`, `knocks`, `behind` y `turn`.

**Pruebas realizadas** (`tools/client_test.luau`, Lune, sin Roblox):

- las 54 escenas se registran con nombre único, categoría, descripción y duración;
- cada una se ejecuta entera sin mapa y otra vez con un edificio de prueba, sin eventos fallidos;
- después de cada escena se comprueba que iluminación, cámara, GUI, sonido y `MarketingRuntime` vuelven a su estado;
- se prueba pausa, reanudar, cámara lenta, reiniciar, parar a mitad, cambiar de escena a mitad y la limpieza repetida.

**Hay que comprobar a mano en Roblox Studio** (los tests no ven píxeles ni oyen):

- encuadre y luz de cada escena;
- que el ojo de imágenes cargue: mira la línea `[Marketing] images: X/8 loaded` del Output;
- volumen y dirección de los sonidos;
- que la copia de tu avatar camine bien con tu tipo de rig.

**Limitaciones conocidas:**

- Roblox no refleja la escena en espejos ni ventanas. Los "reflejos" se simulan con el ojo anclado y con siluetas sobre el cristal.
- Las sombras de pared son siluetas dibujadas, no sombras proyectadas.
- No se han inventado assets. Lo que no existía (cámara de seguridad, sombras, brillos, decorados) se construye con piezas.

## 13. Looks: presets de luz y composición (Visual Overhaul V2)

`Utilities/Looks.luau` define 8 looks. Cada uno aplica de una vez: grade, exposición
(relativa a la de la escena, no se acumula), niebla, objetivo (FOV), viñeta y hasta dos
luces clave/contra colocadas respecto a la cámara y al sujeto. Todo pasa por
`LightFX` / `Screen` / `CameraRig`, así que la limpieza lo deja todo como estaba.

| Look | Para qué | Luces |
|---|---|---|
| `EyeCloseUp` | primer plano del ojo | clave cálida baja lateral + contra fría detrás |
| `LongCorridor` | pasillo en punto de fuga | un charco de luz fría a mitad, niebla densa |
| `DoorAjar` | puerta entreabierta | luz de sodio que se cuela por la rendija hacia la cámara |
| `CCTV` | cámara de seguridad | ninguna (plano, gran angular, sin viñeta) |
| `FigureAtBack` | figura al fondo | contraluz: se lee como silueta |
| `NormalRoom` | la calma antes | relleno suave cálido |
| `AnomalyReveal` | la revelación | cenital dura sobre el sujeto, negros aplastados |
| `CutToBlack` | corte | todo a negro |

```lua
{ at = 3.0, action = "LookPreset", preset = "FigureAtBack", subject = figurePos, camera = shotCf, duration = 0.4 },
```

`subject` (Vector3) es el punto al que miran/rodean las luces; `camera` (CFrame) es el
plano para el que se colocan (si no se da, el plano actual). `fov = false` no toca el objetivo.
`Scene_LookBook` enseña los 8 seguidos y rotulados para comparar.

