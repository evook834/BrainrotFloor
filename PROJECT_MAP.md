# Project map — folder-by-folder summary

High-level map of the repo for humans and AI. This map describes **where code should live by logical concern**. Use each folder's description to **decide** where to put new or moved code: match the script's responsibility to the folder that fits. Not a strict checklist — place by logical fit.

For dependency rules (who may `require` what), see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes, see [REMOTES.md](REMOTES.md). For UI system, see [UI_SYSTEM.md](UI_SYSTEM.md). When you add, remove, or move scripts/folders, update this file as needed.

---

## Repository root

| Path | Purpose |
|------|--------|
| **`AGENTS.md`** | Agent instructions. |
| **`DEPENDENCIES.md`** | Dependency rules and runtime layout. |
| **`REMOTES.md`** | Remote names and payloads. |
| **`README.md`** | Tooling, quick start, CI. |
| **`UI_SYSTEM.md`** | New state-based UI system documentation. |
| **`game/`** | Legacy game source (lobby/match). Kept for backwards compatibility. |
| **`src/`** | New source tree with unified structure (currently active). |
| **`default.project.json`** | Rojo config for new structure. |
| **`Packages/`** | Centralized Wally packages. |

---

## `src/` — New unified source tree

The new source structure that consolidates all game code.

### `src/PlayerScriptService/`

Client-only scripts that run under `StarterPlayer.StarterPlayerScripts` at runtime.

| Folder / file | Purpose |
|---------------|--------|
| **`Core/`** | Core client systems (bootstrapping, base services). |
| **`Features/`** | Feature-specific client scripts (classes, combat, waves, lobby). |
| **`SharedClient/`** | Shared client code (settings, friends, movement). |
| **`ClientEntry.luau`** | New entry point using UI State System. |

**Subfolders:**
- `LobbyClient/` — Lobby-specific client scripts

### `src/ReplicatedStorage/`

Replicated to client and server at runtime.

#### `src/ReplicatedStorage/Shared/`

Config and catalogs; may only `require` within this tree.

| Folder / file | Purpose |
|---------------|--------|
| **`GameConfig.luau`** | Top-level config; wires subsystems (waves, enemies, classes, shop, player, remotes). |
| **`Classes/`** | Class definitions and system config. |
| **`DifficultyConfig.luau`** | Difficulty config (settings per difficulty). |
| **`Enemy/`** | Enemy config, definitions, profiles. |
| **`Player/`** | Player config (money, respawn, movement). |
| **`Remotes/`** | Remote names and Remotes folder name. |
| **`SentryConstants.luau`** | Shared sentry constants. |
| **`Shop/`** | Shop config and weapon catalog. |
| **`Waves/`** | Wave config (intermission, scaling, spawn). |
| **`Pickups/`** | Ammo pickup config. |
| **`Settings/`** | Settings config and types. |

#### `src/ReplicatedStorage/Core/`

Core shared modules.

#### `src/ReplicatedStorage/Features/`

Feature modules for ReplicatedStorage.

### `src/ServerScriptService/`

Server-only scripts.

#### `src/ServerScriptService/Shared/`

Server-only shared (e.g. matchmaking, place role).

| Folder / file | Purpose |
|---------------|--------|
| **`Classes/`** | Shared class system helpers: progression, state helpers, payload builder. |
| **`Friends/`** | FriendService: shared social backend. |
| **`Matchmaking/`** | Matchmaking config and place-role detection. |
| **`PlayerData/`** | PlayerDataService: wraps DataService for persistent data. |
| **`Settings/`** | Shared SettingsService: binds remotes, persists data. |

#### `src/ServerScriptService/Lobby/`

Lobby place server scripts.

| File | Purpose |
|------|--------|
| **`init.luau`** | Entry point for lobby systems (PlaceRole check, services startup) |

**Subfolders:**
- `Core/` — Lobby-specific server scripts (matchmaking, class remotes, settings)

### `src/ServerScriptService/Features/`

Feature modules for ServerScriptService.

#### `src/ServerScriptService/Features/Lobby/Core/`

Lobby-specific server scripts.

| File | Purpose |
|------|--------|
| **`LobbyMatchmaker.server.luau`** | Matchmaking: difficulty selection, server creation/joining |
| **`LobbySettings.server.luau`** | Settings management in lobby |
| **`LobbyClassRemotes.server.luau`** | Class selection remotes (ClassGetData, ClassSelect) |

### `src/ui/` — New UI System

#### `src/ui/UI/`

React Luau UI components (declarative UI definitions).

| File | Purpose |
|------|--------|
| **`init.luau`** | UI exports. |
| **`uitypes.luau`** | Shared type definitions. |

#### `src/ui/UIController/`

State management and UI orchestration.

| File | Purpose |
|------|--------|
| **`init.luau`** | UIController exports. |
| **`GameStateMachine.luau`** | State machine (Menu, Lobby, InGame, Shop, etc.). |
| **`UIManager.luau`** | UI component manager (show/hide based on state). |
| **`run.luau`** | Entry point that wires everything together. |

---

## `game/` — Legacy structure

Kept for backwards compatibility during migration. All code has been migrated to `src/`.

- **`game/shared/`** — Legacy shared code (migrated)
- **`game/lobby/`** — Legacy lobby place (migrated)
- **`game/match/`** — Legacy match place (migrated)

All files have been migrated to `src/`. The legacy folders remain only as reference.

---

## Quick reference: where to put what

| Kind of code | Prefer location |
|--------------|-----------------|
| **Config/catalog (client + server)** | **`src/ReplicatedStorage/Shared/`** |
| **Server-only shared** | **`src/ServerScriptService/Shared/`** |
| **Client-only shared** | **`src/PlayerScriptService/SharedClient/`** |
| **New UI components** | **`src/ui/UI/`** (React Luau) |
| **UI controllers** | **`src/ui/UIController/`** |
| **Client entry (new)** | **`src/PlayerScriptService/ClientEntry.luau`** |

---

## Settings System Files

| File | Location | Purpose |
|------|----------|---------|
| SettingsService | `src/ServerScriptService/Shared/Settings/` | Server-side; binds remotes, persists via PlayerDataService |
| SettingsConfig | `src/ReplicatedStorage/Shared/Settings/` | Shared config (ranges, limits, HUD definitions) |
| SettingsMenuController | `src/PlayerScriptService/SharedClient/Settings/` | Main client controller |

---

## UI State System

| Component | Location | Purpose |
|-----------|----------|---------|
| GameStateMachine | `src/ui/UIController/GameStateMachine.luau` | State machine, tracks current state, allows transitions |
| UIManager | `src/ui/UIController/UIManager.luau` | Manages UI components, shows/hides by state |
| React Luau UI | `src/ui/UI/` | Declarative UI components |
| Entry Point | `src/ui/UIController/run.luau` | Wires state machine and UI manager |
| ClientEntry | `src/PlayerScriptService/ClientEntry.luau` | Client entry point using UI State System |

See [UI_SYSTEM.md](UI_SYSTEM.md) for full documentation.

---

## Migration Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Core Structure** | Done | New `src/` folder structure created |
| **State System** | Done | GameStateMachine + UIManager implemented |
| **Shared Code** | Done | Migrated from `game/shared/` to `src/ReplicatedStorage/Shared/` |
| **Match Client** | Done | Migrated to `src/PlayerScriptService/Features/` |
| **Match Server** | Done | Migrated to `src/ServerScriptService/Features/` |
| **Lobby Client** | Done | Migrated to `src/PlayerScriptService/Features/LobbyClient/` |
| **Lobby Server** | Done | Entry point at `src/ServerScriptService/Lobby/init.luau` |
| **Lobby Matchmaking** | Done | `LobbyMatchmaker` creates ProximityPrompts on DifficultyButtons |
| **UI Components** | Done | ShopView and all components registered |
| **Entry Points** | Done | UIController.run, Lobby entry point created |
| **Wally Packages** | Done | DataService dependency installed in root `Packages/` |

**Migration completed.** The new `src/` structure is now active. Use `rojo serve default.project.json` to run the game.

---

---

## Quick reference: where to put what

| Kind of code | Prefer location |
|--------------|-----------------|
| **Config/catalog (client + server)** | **`src/ReplicatedStorage/Shared/`** |
| **Server-only shared** | **`src/ServerScriptService/Shared/`** |
| **Client-only shared** | **`src/PlayerScriptService/SharedClient/`** |
| **New UI components** | **`src/ui/UI/`** (React Luau) |
| **UI controllers** | **`src/ui/UIController/`** |
| **Client entry (new)** | **`src/PlayerScriptService/ClientEntry.luau`** |
