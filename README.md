# Brainrot Floor

Co-op wave-based shooter on Roblox: players choose a difficulty in the **lobby**, get matched into a **match** server, then survive waves of enemies, buy weapons and ammo, level classes, and optionally return to lobby or vote for the next map after game over. Single Rojo project (Luau); one codebase for both lobby and match places.

This README is an **architecture overview**. Folder-by-folder layout: [PROJECT_MAP.md](PROJECT_MAP.md). Dependency rules: [DEPENDENCIES.md](DEPENDENCIES.md). Remotes: [REMOTES.md](REMOTES.md). UI system: [UI_SYSTEM.md](UI_SYSTEM.md).

---

## Source layout

Single source tree; Rojo mounts it from **`default.project.json`** at repo root.

```
src/
├── PlayerScriptService/     # → StarterPlayerScripts (ClientEntry, ClientMain, SharedClient, LobbyClient, Features)
│   ├── ClientEntry.luau, ClientMain.client.luau
│   ├── SharedClient/        # Settings, Friends, Classes, Hud, Movement, TeleportLoading
│   └── Features/            # Match + Lobby client (Classes, Combat, Waves, Shop, LobbyClient, …)
├── ReplicatedStorage/
│   └── Shared/              # Config, Remotes, catalogs (client + server)
├── ServerScriptService/
│   ├── Shared/              # Matchmaking, PlaceRole, PlayerData, Settings, Friends
│   └── Features/            # Lobby, Core (GameBootstrap), Waves, Shop, Enemies, …
├── ui/                      # → ReplicatedStorage.ui (GameStateMachine, UIManager, React Luau views)
└── Workspace/               # e.g. DifficultyButtons
```

**Packages/** — Wally deps (DataService, etc.). Full folder breakdown: [PROJECT_MAP.md](PROJECT_MAP.md).

---

## Architecture overview

### Two logical places, one codebase

Runtime behavior is determined by **PlaceRole** (place ID at runtime): the same codebase runs as either **Lobby** or **Match**; no separate game folders.

- **Lobby** — Players pick difficulty (Easy / Normal / Hard). Server uses **MemoryStore** to find or create a match server and teleports the party there.
- **Match** — Wave loop, enemies, shop, classes, difficulty scaling, settings, ammo pickups, spectator. When all players die, game over triggers; players can return to lobby or vote for the next map.

### Client / server boundary

- **Clients** run under `StarterPlayer.StarterPlayerScripts` (SharedClient + LobbyClient or MatchClient). They **cannot** `require` anything under `ServerScriptService`; it does not exist on the client.
- **Servers** run under `ServerScriptService` (Shared + Features). They may `require` ReplicatedStorage.Shared and ServerScriptService (Shared + Features).
- **All cross-boundary communication** is via **Remotes** only (RemoteEvent / RemoteFunction). Names and payloads are in [REMOTES.md](REMOTES.md) and `ReplicatedStorage.Shared.Remotes.RemoteNames.luau`.

### Key systems (match)

Server/client modules: [PROJECT_MAP.md](PROJECT_MAP.md). Remote payloads: [REMOTES.md](REMOTES.md).

| System | Server | Client | Remotes (examples) |
|--------|--------|--------|--------------------|
| **Waves** | WaveService: state machine, KF-style director, intermission | WaveHud: state, countdown, game-over, map vote | WaveState (S→All) |
| **Classes** | ClassService: selection, XP, levels, persistence (DataService) | ClassUi, XpBarHud | ClassGetData, ClassSelect, ClassState |
| **Shop** | ShopService: catalog, buy weapon/ammo, trader prompt | ShopUi | ShopOpen (S→C), ShopGetCatalog, ShopBuyWeapon, ShopBuyAmmo |
| **Friends** | FriendService: requests, presence, cooldowns, DMs | FriendSystem UI, lobby nameplates | FriendGetState, FriendAction, FriendState |
| **Combat** | Weapon fire/reload/aim, damage, ammo | Crosshair, AmmoHud, DamageIndicators, DualWieldPose | WeaponAim, WeaponFire, WeaponReload, DamageIndicator |
| **Enemies** | EnemyService, AI, VFX, difficulty-scaled HP/damage | EnemyHealthBars, EnemyDeathCloud | — |
| **Settings** | SettingsService: get/save via DataService (audio, HUD) | SettingsUi (lobby + match) | SettingsGet, SettingsSave |
| **Spectator** | SpectatorService: state, respawn timing, living players | SpectatorController, SpectatorView | SpectatorState, SpectatorRequest |
| **Ammo pickups** | AmmoPickupService: zones, spawn/respawn, pickup | — | — |
| **Game over / map vote** | GameBootstrap: all-dead → GameOver, return-to-lobby, map vote | WaveHud: overlay, return button, map vote | ReturnToLobby, MapVote (reserved) |

Config (wave timing, enemy counts, wave director tables, class catalog, weapon catalog, difficulty multipliers, etc.) lives in **ReplicatedStorage.Shared** (e.g. `GameConfig`, `WaveConfig`, `WeaponCatalog`, `PlaceConfig`). Server-only shared config (place IDs, MemoryStore name, difficulties) is in **ServerScriptService.Shared.Matchmaking**.

### Lobby

- **LobbyMatchmaker**: Listens for difficulty buttons, finds/creates match server via MemoryStore, teleports party with difficulty in teleport data.
- **LobbySettings**: Wires SettingsGet/SettingsSave in lobby so settings persist across lobby and match.
- **PlaceRole**: Detects Lobby vs Match by place ID so lobby-only systems (matchmaker) and match-only systems (waves, shop, classes, etc.) run in the correct place.

---

## Quick start

**Prerequisites:** [Aftman](https://github.com/rojo-rbx/aftman), [Wally](https://github.com/UpliftGames/wally), Roblox Studio with Rojo plugin. Install toolchain via `aftman install` (see `aftman.toml`).

1. **Packages** — From repo root: `wally install` (DataService, etc.).
2. **Serve** — From repo root: `rojo serve default.project.json` (serve port e.g. 34872).
3. **Studio** — Connect to the served port and sync.
4. **Matchmaking** — Set `LOBBY_PLACE_ID` and `MATCH_PLACE_IDS` in `src/ServerScriptService/Shared/Matchmaking/MatchmakingConfig.luau` for real place IDs.

**Client entry:** `ClientMain.client.luau` runs first and calls `ClientEntry.run(options)`, which uses `ReplicatedStorage.ui.UIController.run()`. See [UI_SYSTEM.md](UI_SYSTEM.md).

---

## Docs index

| Doc | Purpose |
|-----|--------|
| **[README.md](README.md)** | Architecture overview (this file). |
| **[PROJECT_MAP.md](PROJECT_MAP.md)** | Folder-by-folder layout. |
| **[DEPENDENCIES.md](DEPENDENCIES.md)** | Who may `require` what; client vs server; shared vs place. |
| **[REMOTES.md](REMOTES.md)** | Remote names, direction, payloads. |
| **[UI_SYSTEM.md](UI_SYSTEM.md)** | State-based UI (GameStateMachine, UIManager). |
| **[CLAUDE.md](CLAUDE.md)** | Claude-specific guidance: toolchain, architecture, dependency rules. |
| **[AGENTS.md](AGENTS.md)** | Agent instructions: placement rules, file organization, when to add/edit/split. |

---

## Maintaining the docs

**README**, **PROJECT_MAP**, **DEPENDENCIES**, and **REMOTES** describe where code lives and how it connects. Keep them accurate when the codebase changes.

**When to update**

- **Prefer updating as part of the same change.** When you add, remove, or move a module, script, folder, or remote, update the affected doc(s) in that same task:
  - New or moved **script/folder** → [PROJECT_MAP.md](PROJECT_MAP.md) (and README key systems table if it’s a new system or major move).
  - New or changed **remote** → [REMOTES.md](REMOTES.md) and `src/ReplicatedStorage/Shared/Remotes/RemoteNames.luau`.
  - New **runtime surface** or dependency rule → [DEPENDENCIES.md](DEPENDENCIES.md) if the “who can require what” table or repo layout changes.
  - New **system** or major flow change → [README.md](README.md) architecture / key systems section.
- **Optional:** A periodic pass over these docs can catch drift. Primary rule: update whenever you add/remove/move modules, remotes, or layout so the docs stay in sync.
