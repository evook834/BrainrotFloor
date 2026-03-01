# Project map — folder-by-folder summary

High-level map of the repo for humans and AI. This map describes **where code should live by logical concern**. Use each folder's description to **decide** where to put new or moved code: match the script's responsibility to the folder that fits. Not a strict checklist — place by logical fit.

For dependency rules (who may `require` what), see [DEPENDENCIES.md](DEPENDENCIES.md). For remotes, see [REMOTES.md](REMOTES.md). For UI system, see [UI_SYSTEM.md](UI_SYSTEM.md). When you add, remove, or move scripts/folders, update this file as needed.

---

## Repository root

| Path | Purpose |
|------|--------|
| **`AGENTS.md`** | Agent instructions (placement, file organization). |
| **`CLAUDE.md`** | Claude-specific guidance (toolchain, architecture). |
| **`DEPENDENCIES.md`** | Dependency rules and runtime layout. |
| **`PROJECT_MAP.md`** | This file — folder-by-folder map. |
| **`README.md`** | Architecture overview, quick start. |
| **`REMOTES.md`** | Remote names and payloads. |
| **`UI_SYSTEM.md`** | State-based UI system (GameStateMachine, UIManager). |
| **`default.project.json`** | Rojo project (single place; ReplicatedStorage.Shared + ui, ServerScriptService.Shared + Features, StarterPlayerScripts, Workspace.DifficultyButtons). |
| **`Packages/`** | Wally packages (DataService, etc.). |
| **`src/`** | Source tree. |

---

## `src/` — Source tree

Single Rojo project; runtime mapping in [DEPENDENCIES.md](DEPENDENCIES.md).

### `src/PlayerScriptService/`

Client scripts; run under `StarterPlayer.StarterPlayerScripts`. Rojo mounts: **ClientEntry**, **ClientMain**, **SharedClient**, **LobbyClient**, **Features**.

| Item | Purpose |
|------|--------|
| **`ClientEntry.luau`** | Entry API; called by ClientMain, invokes `ReplicatedStorage.ui.UIController.run()`. |
| **`ClientMain.client.luau`** | Script that runs first; requires ClientEntry and calls `run(options)` (PlaceConfig, etc.). |
| **`SharedClient/`** | Shared client: Settings (menu, audio, HUD, return-to-lobby), Friends (FriendSystem, nameplates), Classes (ClassUi controller/view), Hud (placeholders), Movement (Sprint), TeleportLoading. |
| **`Features/`** | Feature client scripts (match + lobby). |
| **`Features/LobbyClient/`** | Lobby-only: Settings UI, Social (LobbyFriendNameplates), Classes UI. |
| **`Features/Classes/`** | Class UI, XpBarHud (view, controller, remotes). |
| **`Features/Combat/`** | Crosshair, AmmoHud, DamageIndicators, DualWieldPose, SentryPlacementPreview. |
| **`Features/Enemies/`** | EnemyHealthBars, EnemyDeathCloud, EnemyModelUtils. |
| **`Features/Settings/`** | Match settings UI. |
| **`Features/Shop/`** | Shop UI (controller, view, remotes, catalog display, messages). |
| **`Features/Social/`** | MatchFriendNameplates. |
| **`Features/Spectator/`** | Spectator controller and view. |
| **`Features/Waves/`** | WaveHud (view, controller, remotes), MapVotePayloadUtil, CountdownToken. |

### `src/ReplicatedStorage/`

Replicated to client and server. Rojo mounts **Shared** and **ui** (ui from `src/ui/`).

#### `src/ReplicatedStorage/Shared/`

Config and catalogs; may only `require` within this tree.

| Folder / file | Purpose |
|---------------|--------|
| **`GameConfig.luau`** | Top-level config; wires subsystems and remotes. |
| **`PlaceConfig.luau`** | Place IDs (lobby/match); used by client for place detection. |
| **`DifficultyConfig.luau`** | Difficulty settings. |
| **`SentryConstants.luau`** | Shared sentry constants. |
| **`Classes/`** | ClassSystemConfig, ClassCatalog, ClassIconAssets. |
| **`Enemy/`** | EnemyConfig, EnemyCatalog, EnemyDefinitions, EnemyProfiles, EnemyPresentation, EnemyModelGeometry. |
| **`Player/`** | PlayerConfig, PlayerDataTemplate. |
| **`Remotes/`** | RemoteNames (and Remotes folder name). |
| **`Settings/`** | SettingsConfig, SettingsDefaults, SettingsTypes, HudLayoutConfig. |
| **`Shop/`** | ShopConfig, WeaponCatalog, ShopUiConstants, ShopUiMessages. |
| **`Waves/`** | WaveConfig. |
| **`Pickups/`** | AmmoPickupConfig. |

### `src/ServerScriptService/`

Server-only. Rojo mounts **Shared** and **Features**.

#### `src/ServerScriptService/Shared/`

Server-only shared (no place-specific logic).

| Folder / file | Purpose |
|---------------|--------|
| **`Matchmaking/`** | MatchmakingConfig, PlaceRole (lobby vs match detection). |
| **`PlayerData/`** | PlayerDataService (wraps DataService). |
| **`Settings/`** | SettingsService (remotes, persistence). |
| **`Friends/`** | FriendService (requests, presence, messages). |
| **`Classes/`** | ClassProgression, ClassStateHelpers, ClassPayloadBuilder, ClassDataPayload, ClassPersistence. |

#### `src/ServerScriptService/Features/`

Place-specific server; PlaceRole controls which systems run (Lobby vs Match).

| Folder / file | Purpose |
|---------------|--------|
| **`Lobby/`** | Lobby entry (init.luau); Core: LobbyMatchmaker, LobbySettings, LobbyClassRemotes. |
| **`Core/`** | GameBootstrap (match entry), Bootstrap (RemotesSetup, ReturnToLobbyFlow, MapVoteFlow, PlayerLifecycleBootstrap, MatchSetup, TempContentSetup), Registry (MatchStore, MatchServerRegistry, etc.). |
| **`Waves/`** | WaveService, WaveSpawnLogic, WaveSpawnRunner, WaveSpawnSchedule. |
| **`Enemies/`** | EnemyService, EnemyAIService, EnemyVfxService, EnemyRegistry, EnemyFactory, EnemyScaling, EnemyTargeting, EnemySpawnResolver, etc. |
| **`Classes/`** | ClassService, ClassStateSync, ClassRuntimeEffects, ClassCombatRules. |
| **`Shop/`** | ShopService, Catalog (CatalogBuilder, PricingEngine, AmmoInventory), PurchaseFlow, CurrencyService, TraderAccess, Inventory. |
| **`Weapons/`** | Tools (WeaponToolFactory, WeaponTemplateResolver, ammo, fire handlers), Combat (AimResolver, EnemyDamageService, WeaponFireHandlers, handlers: Bullet, Melee, Projectile, Flamethrower, WeaponVfx, WeaponRemoteBindings), Sentry (Registry, Placement, Targeting, Stats, UI, SentryTurretController). |
| **`Combat/`** | AimResolver, EnemyDamageService (weapon damage lives under Weapons). |
| **`Difficulty/`** | DifficultyService. |
| **`Pickups/`** | AmmoPickupService. |
| **`Spectator/`** | SpectatorService. |
| **`Tools/`** | AmmoZoneLayoutGenerator. |
| **`Admin/`** | OfflinePlayerDataEditor. |

### `src/ui/` — UI system (mounted at ReplicatedStorage.ui)

#### `src/ui/UI/`

React Luau views (declarative UI).

| Item | Purpose |
|------|--------|
| **`init.luau`** | UI exports. |
| **`uitypes.luau`** | Shared UI types. |
| **`Shop/`** | ShopView. |

#### `src/ui/UIController/`

State and UI orchestration.

| Item | Purpose |
|------|--------|
| **`init.luau`** | UIController exports. |
| **`GameStateMachine.luau`** | State machine (Menu, Lobby, InGame, Shop, etc.). |
| **`UIManager.luau`** | Show/hide UI by state. |
| **`run.luau`** | Entry; wires state machine and UI manager. |

### `src/Workspace/`

Place content.

| Folder | Purpose |
|--------|--------|
| **`DifficultyButtons/`** | Difficulty buttons (e.g. for lobby); used by LobbyMatchmaker. |

---

## Quick reference: where to put what

| Kind of code | Prefer location |
|--------------|-----------------|
| **Config/catalog (client + server)** | **`src/ReplicatedStorage/Shared/`** |
| **Server-only shared** | **`src/ServerScriptService/Shared/`** |
| **Client-only shared** | **`src/PlayerScriptService/SharedClient/`** |
| **Match/Lobby server features** | **`src/ServerScriptService/Features/`** (Lobby, Core, Waves, Shop, …) |
| **Match/Lobby client features** | **`src/PlayerScriptService/Features/`** |
| **New UI views (React Luau)** | **`src/ui/UI/`** |
| **UI state / orchestration** | **`src/ui/UIController/`** |
| **Client entry** | **`src/PlayerScriptService/ClientEntry.luau`** (invoked by ClientMain.client.luau) |

---

## Settings system

| Component | Location | Purpose |
|-----------|----------|--------|
| SettingsService | `src/ServerScriptService/Shared/Settings/` | Server; remotes, persistence via PlayerDataService. |
| Settings config | `src/ReplicatedStorage/Shared/Settings/` | Ranges, limits, HUD definitions. |
| Settings client | `src/PlayerScriptService/SharedClient/Settings/` | Menu controller, audio, HUD layout, visibility, return-to-lobby. |

---

## UI state system

| Component | Location | Purpose |
|-----------|----------|--------|
| GameStateMachine | `src/ui/UIController/GameStateMachine.luau` | States and transitions. |
| UIManager | `src/ui/UIController/UIManager.luau` | Show/hide by state. |
| Views | `src/ui/UI/` | React Luau components (e.g. ShopView). |
| Entry | `src/ui/UIController/run.luau` | Wires state machine and UIManager. |
| Client bootstrap | `ClientMain.client.luau` → `ClientEntry.run()` → `UIController.run()`. |

See [UI_SYSTEM.md](UI_SYSTEM.md) for full documentation.
