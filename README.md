# DON'T LOOK AWAY

**THE WORLD CHANGES WHEN YOU STOP LOOKING.**

A cooperative first-person psychological horror experience for Roblox (1-4 players,
10-15 minute rounds). Explore the abandoned Ashgrove Building, notice what changed,
report the anomalies, restore the power, solve the puzzles the building gives you
tonight and escape — while THE OBSERVER moves every time nobody is looking at it.

Everything in this repository is original: the building, props, creature, interface,
sound design (built from the Roblox client's own sounds) and a generative score.

---

## Opening the project

The project is a [Rojo](https://rojo.space) project.

```bash
# build a place file and open it in Roblox Studio
rojo build default.project.json -o DontLookAway.rbxlx

# or live-sync into Studio
rojo serve
```

Then in Studio:

1. **Game Settings → Security → Enable Studio Access to API Services** (for saving
   data while testing; without it the game uses an in-memory store and warns once).
2. **Game Settings → Places → Max players = 4** (the game is built for 1-4).
3. Press **Play** (or **Start → 2-4 players** in the Test tab for co-op testing).

When published, set the experience settings listed in [`docs/GAME_PAGE.md`](docs/GAME_PAGE.md).

## How to test a full round

1. Press **PLAY** in the main menu → you arrive in *The Waiting Room*.
2. Press **READY** (alone is fine). A countdown starts; it shortens when everyone is ready.
3. You spawn outside in the rain. Walk in; the doors slam behind you.
4. Objectives (top-left) tell you what is needed. Typical round:
   - find anomalies and **hold Right Mouse / LT / LOOK** on them,
   - find the **Maintenance Key**, the **Office Key**, three **Fuses**,
   - read the **Maintenance Log** in Office G-02 for the breaker pattern,
   - insert the fuses and set the breakers in **Maintenance (B-04)** → power,
   - complete the two puzzles of the night (keypad + override, symbol cabinet,
     closet doors + cassette, or the Quiet Room offerings),
   - reach the anomaly quota → all four exit locks release → **ESCAPE** through the
     loading dock shutter before it closes.
5. Results, rewards and the return to the lobby are automatic.

### Admin / debug panel (F8)

In Studio every player is an admin; in live servers only the place owner (or the
group owner, or ids in `GameConfig.AdminUserIds`). The panel can start / end / reset
rounds, force any of the 50 anomalies, spawn The Observer (hunt, sighting, mimic),
release locks, teleport to rooms or players, and inspect the round seed, director
phase, dread, active anomalies, players, analytics aggregates and server logs.
Every command is validated on the server.

## Controls

| Action | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| Move / look | WASD / mouse | Left / right stick | Thumbstick / drag right side |
| Sprint | Shift (hold) | L3 (toggle) | RUN (toggle) |
| Interact | E | X | USE |
| Flashlight | F | Y | LIGHT |
| Report anomaly | Right mouse / Q (hold) | LT (hold) | LOOK (hold) |
| Ping | G (tap = ANOMALY, hold = wheel) / middle mouse | RB | PING |
| Inventory | 1-4, mouse wheel, R use, X drop | D-pad | tap slot (tap again to use) |
| Notes | Tab | View | NOTES |
| Menu | P / M | Menu | MENU |
| Journal (lobby) | J | — | kiosk |
| Emotes | B | R3 | EMOTE |

## Architecture

```
src/shared            ReplicatedStorage.Shared   (config, catalogs, net, reality ops, utils)
src/server            ServerScriptService.Server (services, map builder, anomalies, observer)
src/client            StarterPlayerScripts.Client (controllers, UI kit)
src/playerscripts     RbxCharacterSounds override (material footsteps)
docs/                 store page, thumbnails, design notes
tools/check.sh        static analysis
```

Server services (all server-authoritative, wired through a late-bound registry):

| Service | Responsibility |
|---|---|
| `DataService` | DataStore with session locking, retries/backoff, validation & repair, autosave, BindToClose, Studio mock |
| `PlayerService` | status, spawning, and **perception** (validated view rays, line of sight queries) |
| `AntiExploitService` | speed / wall-clip / flight checks, rate-limit violations |
| `MapService` + `Map/*` | builds the lobby once and the building every round from the round seed |
| `DoorService` | doors, locks, keys, slams; clients animate |
| `RealityService` | applies/reverts reality ops GLOBAL (replicated) or PLAYER/TEAM (client-local) |
| `AnomalyService` + `Anomalies/*` | 50 anomalies: selection, unseen activation, scopes, reports, interact/endure rules, expiry, stats |
| `ObserverService` | THE OBSERVER: sightings, perception-gated hunts, forced blinks, mimicry, attacks, escape chase |
| `HorrorDirector` | CALM → TENSION → FEAR → RELIEF pacing, dread, ambience, silence, capped jumpscares |
| `ObjectiveService` | seeded item/key/clue placement (always solvable), exit locks, objective text |
| `PuzzleService` | fuses+breakers, keypad+override, symbol dials, closet doors+cassette, offerings, secret passage |
| `InventoryService` | 4-slot inventory, pickups, batteries, flashlight battery |
| `InteractionService` | validated interactions (distance, LOS, hold time, state) |
| `RoundService` | LOBBY → STARTING → EXPLORING → OBJECTIVE → ESCAPE → RESULTS → RETURNING, deaths, escapes, endings, rejoin |
| `LobbyService` | menu → lobby, ready/countdown, host difficulty, invites, kiosks |
| `ProgressionService` | XP/levels, Anomaly Journal, 24 achievements, stats, round rewards |
| `EconomyService` | Echoes, cosmetic shop, equipping, emotes, game passes (cosmetic only) |
| `PingService`, `AudioService`, `LightingService`, `SettingsService`, `AnalyticsService`, `AdminService` | as named |

Key design decisions:

- **The server never trusts the client** for anomalies, rewards, inventory, items,
  interactions or currency. Clients send intents (a view ray, "interact with this",
  "buy this id"); the server validates and decides. Every remote is rate limited.
- **Perception**: clients stream their view ray at 10 Hz; the server clamps it to the
  head and the body's yaw, and answers "can anyone see this?" with raycasts. That is
  what makes "it moves only when nobody looks" and "anomalies only change unseen"
  server-authoritative.
- **Reality ops** are a tiny reversible vocabulary (Hide/Show/Pivot/Prop/Attr/Clone/Tag).
  An anomaly is just data + a few functions; new anomalies are one table entry.
- **Seeds**: every round has a seed. The map variations, item placement, puzzle
  choice, anomaly and director streams derive from it (shown in results and admin).
- **Performance**: no per-frame server loops beyond throttled heartbeats; fixtures
  are LOD-culled on the client; StreamingEnabled is off because the compact map is
  rebuilt per round and many local systems need the whole building present.

## Adding an anomaly

1. Add an entry to `src/shared/Catalog/JournalCatalog.luau` (number, id, name, …).
2. Add the behaviour to one of `src/server/Anomalies/*.luau`:

```lua
{
	id = "MY_ANOMALY",
	difficulty = 2,
	scopes = { "GLOBAL", "PLAYER" },
	detection = "FOCUS",
	candidates = function(ctx) return ctx:tagged("Clock") end,
	create = function(ctx, clock)
		return {
			claim = clock,
			ops = { { t = "Attr", target = clock, name = "ClockMode", value = "stopped" } },
			anchors = { ctx:anchor(clock) },
		}
	end,
},
```

The service handles unseen activation, scopes, reporting, expiry, journal and rewards.

## Configuration

`src/shared/Config/GameConfig.luau` holds every tunable (difficulties, timings,
movement, flashlight, rewards, data store name, admin ids, game pass ids).

- **Game passes**: create them on the Creator Dashboard and put the ids in
  `GameConfig.GamePasses` (`VIP`, `FlashlightCollection`, `EmotePack`,
  `ExtraLoadouts`). While an id is `0` the matching shop items are hidden and no
  purchase prompt can appear. Passes only unlock cosmetics.
- **No randomized purchases** exist. If you ever add any, Roblox requires
  disclosing odds and respecting `PolicyService:GetPolicyInfoForPlayerAsync`
  (`ArePaidRandomItemsRestricted`); gate the UI on that policy.
- **Audio**: `src/shared/Config/AudioLibrary.luau` maps every sound key to an asset
  id plus effects. All defaults are Roblox built-in client sounds shaped with
  pitch/reverb/EQ/distortion. To use licensed Creator Store audio, change only the
  `id` of an entry.

## Static checks

```bash
LUAU_DEFS=/path/to/globalTypes.d.luau tools/check.sh   # luau-analyze over every file
rojo build default.project.json -o DontLookAway.rbxlx  # project builds
```
