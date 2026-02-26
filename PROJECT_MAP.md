# Project map — folder-by-folder summary

High-level map of the repo for humans and AI. This map describes **where code should live by logical concern**. Use each folder’s description to **decide** where to put new or moved code: match the script’s responsibility to the folder that fits. Not a strict checklist — place by logical fit.

For dependency rules (who may `require` what), see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes, see [REMOTES.md](REMOTES.md). When you add, remove, or move scripts/folders, update this file as needed.

---

## Repository root

| Path | Purpose |
|------|--------|
| **`AGENTS.md`** | Agent instructions. |
| **`DEPENDENCIES.md`** | Dependency rules and runtime layout. |
| **`REMOTES.md`** | Remote names and payloads. |
| **`README.md`** | Tooling, quick start, CI. |
| **`game/`** | Game source: shared, lobby, match. |

---

## `game/shared/`

Shared code used by **lobby** and **match**. Mounted into each place’s DataModel.

### `game/shared/src/ReplicatedStorage/Shared/`

Replicated to client and server. Config and catalogs only; may only `require` within this tree.

| Folder / file | Purpose |
|---------------|--------|
| **`GameConfig.luau`** | Top-level config; wires subsystems (waves director, enemies, classes, shop, player, remotes). |
| **`Classes/`** | Class definitions and system config. |
| **`Enemy/`** | Enemy config and profiles. |
| **`Player/`** | Player config (money, respawn, movement). |
| **`Remotes/`** | Remote names and Remotes folder name. |
| **`Shop/`** | Shop config and weapon catalog. |
| **`Waves/`** | Wave config (intermission, scaling, spawn). |
| **`Pickups/`** | Ammo pickup config. |
| **`MapVote/`** | Placeholder for map-vote shared data. |

### `game/shared/src/ServerScriptService/Shared/`

Server-only shared (e.g. matchmaking, place role). Used by both lobby and match.

| Folder / file | Purpose |
|---------------|--------|
| **`Classes/`** | ClassProgression (XP, bonuses), ClassDataPayload (build class list + selection from PlayerData; used by Lobby). |
| **`Matchmaking/`** | Matchmaking config and place-role detection. |
| **`PlayerData/`** | PlayerDataService: wraps DataService (leifstout/dataService) for persistent, replicated player data (settings, classes, money). |
| **`Settings/`** | Shared SettingsService: binds SettingsGet/SettingsSave remotes, reads/writes via PlayerDataService. |

### `game/shared/src/StarterPlayerScripts/SharedClient/`

Client-only shared. Runs in both lobby and match.

| Folder / file | Purpose |
|---------------|--------|
| **`Movement/`** | Sprint, stamina, movement behavior. |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby client. |

---

## `game/lobby/`

Lobby place: difficulty selection, matchmaking, teleport to match.

### `game/lobby/src/ServerScriptService/Lobby/`

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | Matchmaking, difficulty buttons, teleport, lobby bootstrap, class remotes (ClassGetData/ClassSelect). |
| **`Settings/`** | Empty; settings use Shared SettingsService (PlayerDataService). |

### `game/lobby/src/StarterPlayer/StarterPlayerScripts/LobbyClient/`

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | Lobby HUD and placeholders. |
| **`Classes/`** | Class selection UI (same as Match; selection persists to Match). |
| **`Settings/`** | Lobby settings UI. |

### `game/lobby/src/Workspace/`

| Folder | Purpose |
|--------|--------|
| **`DifficultyButtons/`** | Workspace folder for difficulty buttons. |

---

## `game/match/`

Match place: waves, enemies, shop, classes, difficulty, settings, ammo.

### `game/match/src/ServerScriptService/Match/`

Match server logic. Put each script in the folder whose description matches its responsibility.

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | Match startup, remotes setup, service wiring, server registry. |
| **`Waves/`** | Wave state, KF-style director (WaveTotalTarget, AliveCap, role caps), spawning, intermission. |
| **`Enemies/`** | Enemy spawn, lifecycle, AI, VFX, model/hitbox resolution, targeting. |
| **`Combat/`** | Aim validation, damage application, feedback/DOT. |
| **`Shop/`** | Commerce: catalog, pricing, purchase, inventory. |
| **`Weapons/`** | Weapon and sentry runtime: tools, ammo, fire, VFX, remotes. |
| **`Classes/`** | Class selection, XP, levels, persistence, combat rules. |
| **`Pickups/`** | Ammo zones, pickups, player pickup. |
| **`Difficulty/`** | Difficulty settings (multipliers, etc.). |
| **`Settings/`** | Match settings (get/save). |
| **`Tools/`** | Ad-hoc or editor tools (e.g. layout generators). |
| **`MapVote/`** | Placeholder for map-vote server logic. |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby server logic. |
| **`Admin/`** | OfflinePlayerDataEditor: binds EditOfflinePlayerData remote; edits saved player data by userId when the player is offline (Studio only by default). |

### `game/match/src/StarterPlayer/StarterPlayerScripts/MatchClient/`

Match client UI and HUD. Match folder names to responsibility.

| Folder / file | Purpose |
|---------------|--------|
| **`Waves/`** | Wave state HUD. |
| **`Enemies/`** | Enemy health bars, death VFX. |
| **`Shop/`** | Shop UI (catalog, buy). |
| **`Classes/`** | Class UI, XP bar. |
| **`Combat/`** | Crosshair, ammo HUD, dual-wield pose, damage numbers. |
| **`Settings/`** | Match settings UI. |
| **`Spectator/`** | Spectator mode: when dead, spectate living players (camera follow, Q/E cycle). |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby client. |

### `game/match/src/Workspace/`

| Folder | Purpose |
|--------|--------|
| **`EnemyContainer/`** | Container for spawned enemies. |
| **`SpawnPoints/`** | Player spawn points. |

### `game/match/src/ServerStorage/`

| Folder | Purpose |
|--------|--------|
| **`EnemyTemplates/`** | Templates for spawning enemies. |
| **`ShopItems/`** | Shop item templates (e.g. tools). |

---

## `game/places/`

Legacy or alternate copy of place-specific code. Prefer **`game/lobby`** and **`game/match`** for new work.

---

## Quick reference: where to put what

| Kind of code | Prefer location |
|--------------|-----------------|
| Config/catalog (client + server) | **`game/shared/src/ReplicatedStorage/Shared/`** |
| Server-only shared | **`game/shared/src/ServerScriptService/Shared/`** |
| Client-only shared | **`game/shared/src/StarterPlayerScripts/SharedClient/`** |
| Lobby server | **`game/lobby/src/ServerScriptService/Lobby/`** |
| Lobby client | **`game/lobby/.../LobbyClient/`** |
| Match server | **`game/match/src/ServerScriptService/Match/`** — use subfolder by concern (Core, Waves, Enemies, Combat, Shop, Weapons, Classes, etc.). |
| Match client UI/HUD | **`game/match/.../MatchClient/`** — use subfolder by concern. |
