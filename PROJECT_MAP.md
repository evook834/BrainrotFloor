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
| **`DifficultyConfig.luau`** | Difficulty config (default, ordered names, settings per difficulty). Single source for matchmaking list and match tuning. |
| **`Enemy/`** | Enemy config, definitions, profiles, presentation data. |
| **`Player/`** | Player config (money, respawn, movement). Includes `PlayerDataTemplate` for default player data. |
| **`Remotes/`** | Remote names and Remotes folder name. |
| **`SentryConstants.luau`** | Shared sentry constants (e.g. workspace folder name); used by client and server. |
| **`Shop/`** | Shop config and weapon catalog. |
| **`Waves/`** | Wave config (intermission, scaling, spawn). |
| **`Pickups/`** | Ammo pickup config. |
| **`MapVote/`** | Placeholder for map-vote shared data. |
| **`Settings/`** | Settings config and types (`SettingsConfig`, `HudLayoutConfig`, `SettingsTypes`, `SettingsDefaults`). |

### `game/shared/src/ServerScriptService/Shared/`

Server-only shared (e.g. matchmaking, place role). Used by both lobby and match.

| Folder / file | Purpose |
|---------------|--------|
| **`Classes/`** | Shared class system helpers: progression (XP, bonuses), state helpers, payload builder + lobby payload, optional persistence. |
| **`Matchmaking/`** | Matchmaking config and place-role detection. |
| **`PlayerData/`** | PlayerDataService: wraps DataService (leifstout/dataService) for persistent, replicated player data (settings, classes, money). |
| **`Settings/`** | Shared SettingsService: binds SettingsGet/SettingsSave remotes, reads/writes via PlayerDataService. Also config (`SettingsConfig`, `HudLayoutConfig`). |

### `game/shared/src/StarterPlayerScripts/SharedClient/`

Client-only shared. Runs in both lobby and match.

| Folder / file | Purpose |
|---------------|--------|
| **`Movement/`** | Sprint, stamina, movement behavior. |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby client. |
| **`Settings/`** | Settings client UI and controllers. |

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
| **`Core/`** | Match startup, remotes setup, service wiring. **`Core/Registry/`** — Match server registry: MatchServerRegistry (orchestration), MatchStore (MemoryStore wrapper), RegistryEntry (entry shape + hasAccessCode), RegistryJoinData (JoinData/TeleportData parsing); heartbeat, difficulty from JoinData, unregister on close. |
| **`Waves/`** | Wave state, KF-style director (WaveTotalTarget, AliveCap, role caps), spawning, intermission. |
| **`Enemies/`** | Enemy spawn, lifecycle, AI, VFX, model/hitbox resolution, targeting. |
| **`Combat/`** | Aim validation, damage application, feedback/DOT. |
| **`Shop/`** | Commerce: catalog, pricing, purchase, inventory. |
| **`Weapons/`** | Weapon and sentry runtime. Subsystems: **`Weapons/Tools/`** (tool creation, template lookup, ammo, shot origin; WeaponToolSetup, WeaponAmmoRuntime, WeaponShotResolver, WeaponToolFactory), **`Weapons/Combat/`** (fire facade/remotes/VFX; WeaponVfx, WeaponFireHandlers, WeaponRemoteBindings; per-mode handlers in `Weapons/Combat/Handlers/`), **`Weapons/Sentry/`** (orchestrator SentryTurretController; **`Sentry/Registry/`** SentryRuntime; **`Sentry/Placement/`** SentryPlacement; **`Sentry/Targeting/`** SentryTargeting; **`Sentry/Stats/`** SentryStatResolver; **`Sentry/UI/`** SentryHealthBar). |
| **`Classes/`** | Class selection, XP, levels, persistence, combat rules. |
| **`Pickups/`** | Ammo zones, pickups, player pickup. |
| **`Difficulty/`** | Difficulty settings (multipliers, etc.). |
| **`Settings/`** | Match settings (get/save). |
| **`Spectator/`** | Spectator mode: SpectatorService server API and client Spectator (entry), SpectatorController (logic), SpectatorView (UI). |
| **`Tools/`** | Ad-hoc or editor tools (e.g. layout generators). |
| **`MapVote/`** | Placeholder for map-vote server logic. |
| **`ReturnToLobby/`** | Placeholder for return-to-lobby server logic. |
| **`Admin/`** | OfflinePlayerDataEditor: binds EditOfflinePlayerData remote; edits saved player data by userId when the player is offline (Studio only by default). |

### `game/match/src/StarterPlayer/StarterPlayerScripts/MatchClient/`

Match client UI and HUD. Match folder names to responsibility.

| Folder / file | Purpose |
|---------------|--------|
| **`Waves/`** | Wave HUD: WaveHud (entry), WaveHudController (logic), WaveHudView (UI). |
| **`Enemies/`** | Enemy health bars, death VFX. |
| **`Shop/`** | Shop UI (catalog, buy). |
| **`Classes/`** | Class UI, XP bar. |
| **`Combat/`** | Crosshair, ammo HUD, dual-wield pose, damage numbers. |
| **`Settings/`** | Match settings UI. |
| **`Spectator/`** | Spectator mode client: Spectator (entry), SpectatorController (logic), SpectatorView (UI). |
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

---

## Settings System Files

| File | Location | Purpose |
|------|----------|---------|
| SettingsService | `ServerScriptService/Shared/Settings/` | Server-side; binds remotes, sanitizes data, persists via PlayerDataService |
| SettingsConfig | `ReplicatedStorage/Shared/Settings/` | Shared config (ranges, limits, HUD definitions) |
| HudLayoutConfig | `ReplicatedStorage/Shared/Settings/` | HUD layout config (draggable roots, ScreenGui names) |
| SettingsTypes | `ReplicatedStorage/Shared/Settings/` | Shared types (SettingsState, RunOptions) |
| SettingsDefaults | `ReplicatedStorage/Shared/Settings/` | Default settings state from config |
| SettingsMenuController | `StarterPlayerScripts/SharedClient/Settings/` | Main client controller |
| SettingsPayloadBuilder | `StarterPlayerScripts/SharedClient/Settings/` | Builds save payload for SettingsSave remote |
| SettingsMenuUi | `StarterPlayerScripts/SharedClient/Settings/` | UI builder |
| SettingsAudioController | `StarterPlayerScripts/SharedClient/Settings/` | Audio controls |
| SettingsHudLayoutController | `StarterPlayerScripts/SharedClient/Settings/` | HUD layout controls |
| SettingsHudLayoutService | `StarterPlayerScripts/SharedClient/Settings/` | Position helpers |
| SettingsVisibilityController | `StarterPlayerScripts/SharedClient/Settings/` | F10 UI toggle |
| SettingsReturnToLobbyController | `StarterPlayerScripts/SharedClient/Settings/` | Return to lobby (match only) |
| SettingsRemotesUtil | `StarterPlayerScripts/SharedClient/Settings/` | Remote resolution utilities |
| SettingsUi | `StarterPlayerScripts/SharedClient/Settings/` | Entry point |
| HudMoveModeInput | `StarterPlayerScripts/SharedClient/Settings/` | HUD move mode input binding (mouse + touch) |
