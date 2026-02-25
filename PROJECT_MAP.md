# Project map — folder-by-folder summary

High-level map of the repo for humans and AI. For dependency rules (who may `require` what), see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes, see [REMOTES.md](REMOTES.md). **When you add, remove, or move scripts/folders, update this file** (and README/DEPENDENCIES/REMOTES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

---

## Repository root

| Path | Purpose |
|------|--------|
| **`AGENTS.md`** | Agent instructions: command preference, placement (use DEPENDENCIES/PROJECT_MAP/README/REMOTES), file organization, when to add/edit/split. |
| **`DEPENDENCIES.md`** | Dependency rules and runtime layout (client vs server, shared vs place). |
| **`REMOTES.md`** | Remote names, direction (C→S / S→C), and payload schemas. |
| **`README.md`** | Tooling (aftman, rojo, wally), quick start, CI, per-place projects. |
| **`doc.md`** | Project documentation (if present). |
| **`wally.toml`** | Root Wally manifest (if used). |
| **`aftman.toml`** | Toolchain (rojo, etc.). |
| **`game/`** | All game source: shared, lobby, match. |

---

## `game/shared/`

Shared code used by **lobby** and **match** places. Rojo mounts it into each place’s DataModel.

### `game/shared/src/ReplicatedStorage/Shared/`

Replicated to **client and server**. Config, catalogs, remote names only. May only `require` other modules under this tree.

| Folder / file | Purpose |
|---------------|--------|
| **`GameConfig.luau`** | Top-level config: wires Wave, Enemy, Difficulty, Player, ClassSystem, Shop, AmmoPickup, Remotes. |
| **`Classes/`** | **ClassCatalog.luau** — class definitions (id, display name, weapon tag, progression, bonuses). **ClassSystemConfig.luau** — system config (wires catalog). |
| **`Enemy/`** | **EnemyConfig.luau** — enemy config (wires profiles). **EnemyProfiles.luau** — per-enemy profile data. |
| **`Player/`** | **PlayerConfig.luau** — starting money, respawn, sprint/stamina, move speed. |
| **`Remotes/`** | **RemoteNames.luau** — single source of remote names and Remotes folder name. |
| **`Shop/`** | **ShopConfig.luau** — shop config (wires weapon catalog). **WeaponCatalog.luau** — weapon definitions (cost, damage, class tag, etc.). |
| **`Waves/`** | **WaveConfig.luau** — intermission, enemy counts, wave scaling, spawn cadence. |
| **`Pickups/`** | **AmmoPickupConfig.luau** — ammo zone/pickup folder names, defaults, refill mode. |
| **`MapVote/`** | Placeholder (e.g. `.gitkeep`) for future map-vote shared data. |

### `game/shared/src/ServerScriptService/Shared/`

Server-only shared code. Used by both lobby and match server scripts.

| Folder / file | Purpose |
|---------------|--------|
| **`Matchmaking/`** | **MatchmakingConfig.luau** — place IDs, MemoryStore name, difficulties, TTLs, heartbeat, button folder/attribute names. **PlaceRole.luau** — detects place role (Lobby vs Match) for conditional system startup. |
| **`Settings/`** | Placeholder for shared server-side settings logic (if any). |

### `game/shared/src/StarterPlayerScripts/SharedClient/`

Client-only shared scripts. Run in both lobby and match.

| Folder / file | Purpose |
|---------------|--------|
| **`Movement/`** | **Sprint.client.luau** — sprint input and stamina (client-side behavior). |
| **`ReturnToLobby/`** | Placeholder for shared “return to lobby” client handling. |

---

## `game/lobby/`

**Lobby place**: difficulty selection, matchmaking, teleport to match. Uses **`default.project.json`**; pulls in **`../shared`**.

### `game/lobby/src/ServerScriptService/Lobby/`

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | **LobbyMatchmaker.server.luau** — MemoryStore matchmaking, difficulty buttons, teleport to match. **LobbySettings.server.luau** — lobby-specific settings bootstrap. |
| **`Settings/`** | **SettingsService.luau** — server-side settings (get/save) for lobby; remotes **SettingsGet** / **SettingsSave**. |

### `game/lobby/src/StarterPlayer/StarterPlayerScripts/LobbyClient/`

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | **LobbyHudPlaceholders.client.luau** — HUD setup/placeholders in lobby. |
| **`Settings/`** | **SettingsUi.client.luau** — settings UI (audio, HUD) in lobby. |

### `game/lobby/src/Workspace/`

| Folder | Purpose |
|--------|--------|
| **`DifficultyButtons/`** | Workspace folder for difficulty buttons (names/attributes per MatchmakingConfig). `init.meta.json` for Rojo. |

### Other

| Path | Purpose |
|------|--------|
| **`game/lobby/Packages/`** | Wally packages (e.g. `.gitkeep`). |
| **`game/lobby/default.project.json`** | Rojo project: ReplicatedStorage.Shared, ServerScriptService.Shared + Lobby, StarterPlayerScripts SharedClient + LobbyClient. |
| **`game/lobby/wally.toml`**, **`wally.lock`** | Lobby place dependencies. |

---

## `game/match/`

**Match place**: waves, enemies, shop, classes, difficulty, settings, ammo pickups. Uses **`default.project.json`**; pulls in **`../shared`**.

### `game/match/src/ServerScriptService/Match/`

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | **GameBootstrap.server.luau** — match startup: remotes setup, wave/shop/class/difficulty/settings/ammo services, map vote wiring, server registry. **MatchServerRegistry.server.luau** — match server registration for lobby matchmaking. |
| **`Waves/`** | **WaveService.luau** — wave state, spawning, intermission, WaveState remote. |
| **`Enemies/`** | **EnemyService.luau** — enemy spawning/lifecycle. **EnemyAIService.luau** — AI behavior. **EnemyVfxService.luau** — enemy VFX. **ModelRootResolver.luau** — resolve model root for damage/hitboxes. |
| **`Shop/`** | **ShopService.luau** — shop remotes (catalog, buy weapon/ammo), trader prompt. **CatalogAndPricing.luau** — build catalog for player. **InventoryIndex.luau** — index owned tools/sentries. **PurchaseFlow.luau** — purchase validation. **WeaponAmmoRuntime.luau** — weapon ammo state. **SentryRuntime.luau** — sentry state. |
| **`Classes/`** | **ClassService.luau** — class selection, XP, levels, ClassGetData/ClassSelect/ClassState remotes. **ClassStateSync.luau** — build class state payload for client. **ClassPersistence.luau** — persist class progress. **ClassProgression.luau** — XP/level math. **ClassRuntimeEffects.luau** — apply class bonuses. **ClassCombatRules.luau** — combat rules per class. |
| **`Pickups/`** | **AmmoPickupService.luau** — ammo zones, spawn/respawn pickups, player pickup. |
| **`Difficulty/`** | **DifficultyService.luau** — difficulty settings (health/damage multipliers from GameConfig). |
| **`Settings/`** | **SettingsService.luau** — server-side settings (get/save) for match. |
| **`Tools/`** | **AmmoZoneLayoutGenerator.luau** — tool to generate ammo zone layout (run ad-hoc). |
| **`MapVote/`** | Placeholder for map-vote server logic. |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby server logic. |

### `game/match/src/StarterPlayer/StarterPlayerScripts/MatchClient/`

| Folder / file | Purpose |
|---------------|--------|
| **`Waves/`** | **WaveHud.client.luau** — wave state HUD (from WaveState remote / Remotes attributes). |
| **`Enemies/`** | **EnemyHealthBars.client.luau** — enemy health bars. **EnemyDeathCloud.client.luau** — death VFX. |
| **`Shop/`** | **ShopUi.client.luau** — shop UI (catalog, buy weapon/ammo). |
| **`Classes/`** | **ClassUi.client.luau** — class selection UI. **XpBarHud.client.luau** — XP/level bar. |
| **`Combat/`** | **Crosshair.client.luau** — crosshair. **AmmoHud.client.luau** — ammo display. **DualWieldPose.client.luau** — dual-wield pose. **DamageIndicators.client.luau** — damage numbers (DamageIndicator remote). |
| **`Settings/`** | **SettingsUi.client.luau** — settings UI in match. |
| **`ReturnToLobby/`** | Placeholder for “return to lobby” client handling. |

### `game/match/src/Workspace/`

| Folder | Purpose |
|--------|--------|
| **`EnemyContainer/`** | Container for spawned enemies. `init.meta.json` for Rojo. |
| **`SpawnPoints/`** | Player spawn points. `init.meta.json` for Rojo. |

### `game/match/src/ServerStorage/`

| Folder | Purpose |
|--------|--------|
| **`EnemyTemplates/`** | Templates for spawning enemies. `init.meta.json` for Rojo. |
| **`ShopItems/`** | Shop item templates (e.g. tools). `init.meta.json` for Rojo. |

### Other

| Path | Purpose |
|------|--------|
| **`game/match/Packages/`** | Wally packages. |
| **`game/match/default.project.json`** | Rojo project: ReplicatedStorage.Shared, ServerScriptService.Shared + Match, StarterPlayerScripts SharedClient + MatchClient. |
| **`game/match/wally.toml`**, **`wally.lock`** | Match place dependencies. |

---

## `game/places/`

Legacy or alternate copy of place-specific code. **Current** lobby and match source live under **`game/lobby/`** and **`game/match/`**; some workflows or CI may still reference `game/places/lobby` or `game/places/match`. Prefer **`game/lobby`** and **`game/match`** for new work and for project paths in README/CI.

---

## Quick reference: where to put what

| Kind of code | Prefer location |
|--------------|-----------------|
| Config/catalog used by client and server | **`game/shared/src/ReplicatedStorage/Shared/`** (and subfolders) |
| Server-only shared (e.g. matchmaking, place role) | **`game/shared/src/ServerScriptService/Shared/`** |
| Client-only shared (e.g. sprint) | **`game/shared/src/StarterPlayerScripts/SharedClient/`** |
| Lobby server logic | **`game/lobby/src/ServerScriptService/Lobby/`** |
| Lobby client UI/scripts | **`game/lobby/src/StarterPlayer/StarterPlayerScripts/LobbyClient/`** |
| Match server logic (waves, shop, classes, etc.) | **`game/match/src/ServerScriptService/Match/`** |
| Match client UI/HUD | **`game/match/src/StarterPlayer/StarterPlayerScripts/MatchClient/`** |
