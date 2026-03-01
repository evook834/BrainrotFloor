# Brainrot Floor

Co-op wave-based shooter on Roblox: players choose a difficulty in the **lobby**, get matched into a **match** server, then survive waves of enemies, buy weapons and ammo, level classes, and optionally return to lobby or vote for the next map after game over.

This README is an **architecture overview**. For folder-by-folder layout see [PROJECT_MAP.md](PROJECT_MAP.md). For dependency rules see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes see [REMOTES.md](REMOTES.md). For the UI system see [UI_SYSTEM.md](UI_SYSTEM.md).

---

## Project structure

Single unified source tree with a **state-based UI system**:

```
BrainrotFloor/
├── src/                    # Source tree
│   ├── PlayerScriptService/   # Client scripts (StarterPlayerScripts)
│   ├── ReplicatedStorage/    # Shared client+server (config, remotes, catalogs)
│   ├── ServerScriptService/   # Server (Shared + Features)
│   ├── ui/                    # State-based UI
│   │   ├── UI/                # React Luau components
│   │   └── UIController/      # State machine + UI manager
│   └── Workspace/             # Place content (e.g. DifficultyButtons)
├── default.project.json   # Rojo project (single place)
└── Packages/               # Wally packages (DataService, etc.)
```

See [PROJECT_MAP.md](PROJECT_MAP.md) for folder-by-folder details.

---

## Architecture overview

### Two logical places, one codebase

Runtime behavior is determined by **PlaceRole** (place ID): the same codebase runs as either **Lobby** or **Match**.

- **Lobby** — Players pick difficulty (Easy / Normal / Hard). Server uses **MemoryStore** to find or create a match server and teleports the party there.
- **Match** — Wave loop, enemies, shop, classes, difficulty scaling, settings, ammo pickups, spectator. When all players die, game over triggers; players can return to lobby or vote for the next map.

### Client / server boundary

- **Clients** run under `StarterPlayer.StarterPlayerScripts` (SharedClient + LobbyClient or MatchClient). They **cannot** `require` anything under `ServerScriptService`; it does not exist on the client.
- **Servers** run under `ServerScriptService` (Shared + Features). They may `require` ReplicatedStorage.Shared and ServerScriptService (Shared + Features).
- **All cross-boundary communication** is via **Remotes** only (RemoteEvent / RemoteFunction). Names and payloads are in [REMOTES.md](REMOTES.md) and `ReplicatedStorage.Shared.Remotes.RemoteNames.luau`.

### Key systems (match)

| System | Server | Client | Remotes (examples) |
|--------|--------|--------|--------------------|
| **Waves** | WaveService: state machine (Preparing → InProgress → Cleared / Blocked / GameOver) plus KF-style director (WaveTotalTarget + AliveCap, composition, 1500 cap), intermission | WaveHud: wave number, state, intermission countdown, game-over overlay, map vote UI | WaveState (S→All) |
| **Classes** | ClassService: selection, XP, levels, combat bonuses; persistence via DataService (PlayerDataService) | ClassUi, XpBarHud | ClassGetData, ClassSelect, ClassState (C→S / S→C) |
| **Shop** | ShopService: catalog per player, buy weapon/ammo, trader prompt | ShopUi | ShopOpen (S→C), ShopGetCatalog, ShopBuyWeapon, ShopBuyAmmo (C→S) |
| **Friends** | Shared FriendService: requests, presence, 10-minute rejection cooldowns, and in-game direct messages | FriendSystem UI (settings menu) plus lobby nameplates | FriendGetState, FriendAction, FriendState (C→S / S→C) |
| **Combat** | Weapon fire/reload/aim handlers, damage, ammo | Crosshair, AmmoHud, DamageIndicators, DualWieldPose | WeaponAim, WeaponFire, WeaponReload (C→S), DamageIndicator (S→C) |
| **Enemies** | EnemyService, EnemyAIService, EnemyVfxService, difficulty-scaled HP/damage | EnemyHealthBars, EnemyDeathCloud | — |
| **Settings** | Shared SettingsService: get/save via DataService (audio, HUD) | SettingsUi (lobby + match) | SettingsGet (C→S), SettingsSave (C→S) |
| **Spectator** | SpectatorService: spectator state, respawn timing, living players | SpectatorController, SpectatorView | SpectatorState (S→C), SpectatorRequest (C→S) |
| **Ammo pickups** | AmmoPickupService: zones, spawn/respawn, pickup | — | — |
| **Game over / map vote** | GameBootstrap: all-dead → GameOver, return-to-lobby teleport, map vote winner → reserve + teleport party | WaveHud: game-over overlay, return button, map vote panel | ReturnToLobby, MapVote (reserved) |

Config (wave timing, enemy counts, wave director tables, class catalog, weapon catalog, difficulty multipliers, etc.) lives in **ReplicatedStorage.Shared** (e.g. `GameConfig`, `WaveConfig`, `WeaponCatalog`, `PlaceConfig`). Server-only shared config (place IDs, MemoryStore name, difficulties) is in **ServerScriptService.Shared.Matchmaking**.

### Lobby

- **LobbyMatchmaker**: Listens for difficulty buttons, finds/creates match server via MemoryStore, teleports party with difficulty in teleport data.
- **LobbySettings** / **SettingsService**: Expose SettingsGet / SettingsSave so settings persist across lobby and match.
- **PlaceRole**: Detects Lobby vs Match so lobby-only systems (matchmaker) and match-only systems (waves, shop, classes, etc.) run in the correct place.

---

## Repo layout (summary)

```
src/
├── PlayerScriptService/
│   ├── ClientEntry.luau, ClientMain.client.luau   # Client entry
│   ├── Features/       # Match + Lobby client (Classes, Waves, Shop, LobbyClient, …)
│   └── SharedClient/   # Shared client (Settings, Friends, Hud, …)
├── ReplicatedStorage/
│   └── Shared/         # Config, Remotes, catalogs
├── ServerScriptService/
│   ├── Shared/         # Matchmaking, PlaceRole, PlayerData, Settings, Friends
│   └── Features/        # Lobby, Core (GameBootstrap), Waves, Shop, Enemies, …
└── ui/
    ├── UI/             # React Luau views
    └── UIController/   # GameStateMachine, UIManager, run
```

Detailed folder-by-folder breakdown: **[PROJECT_MAP.md](PROJECT_MAP.md)**.

---

## Quick start

1. **Toolchain** — `aftman` (see `aftman.toml`) for `rojo` and `wally`.
2. **Packages** — `wally install` in the repo root (installs DataService, etc.).
3. **Serve** — `rojo serve default.project.json` (single Rojo project; serve port e.g. 34872).
4. **Studio** — Connect to the served port and sync.
5. **Matchmaking** — Configure `LOBBY_PLACE_ID` and `MATCH_PLACE_IDS` in `src/ServerScriptService/Shared/Matchmaking/MatchmakingConfig.luau` for real place IDs.

**Client entry:** `ClientMain.client.luau` runs first and calls `ClientEntry.run(options)`, which uses `ReplicatedStorage.ui.UIController.run()` (state machine + UI manager). See [UI_SYSTEM.md](UI_SYSTEM.md).

---

## Docs index

| Doc | Purpose |
|-----|--------|
| **[README.md](README.md)** | Architecture overview (this file). |
| **[PROJECT_MAP.md](PROJECT_MAP.md)** | Folder-by-folder summary. |
| **[DEPENDENCIES.md](DEPENDENCIES.md)** | Who may `require` what; client vs server; shared vs place. |
| **[REMOTES.md](REMOTES.md)** | Remote names, direction, payloads. |
| **[UI_SYSTEM.md](UI_SYSTEM.md)** | State-based UI system (GameStateMachine, UIManager). |
| **[AGENTS.md](AGENTS.md)** | Agent instructions: command preference, placement rules, file organization, when to add/edit/split. |

---

## Maintaining the docs (DEPENDENCIES, PROJECT_MAP, README, REMOTES)

These four files describe where code lives and how it connects. Keep them accurate when the codebase changes.

**When to update**

- **Prefer updating as part of the same change.** When you add, remove, or move a module, script, folder, or remote, update the affected doc(s) in that same task:
  - New or moved **script/folder** → [PROJECT_MAP.md](PROJECT_MAP.md) (and README key systems table if it’s a new system or major move).
  - New or changed **remote** → [REMOTES.md](REMOTES.md) and `src/ReplicatedStorage/Shared/Remotes/RemoteNames.luau`.
  - New **runtime surface** or dependency rule → [DEPENDENCIES.md](DEPENDENCIES.md) if the “who can require what” table or repo layout changes.
  - New **system** or major flow change → [README.md](README.md) architecture / key systems section.
- **Optional:** A periodic or end-of-session pass (e.g. once a day) over the four docs can catch drift if something was missed during a change. The primary rule is still: update whenever you add/remove/move modules, remotes, or layout so the docs stay in sync.
