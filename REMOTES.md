# Remotes reference

All remotes live under `ReplicatedStorage.Remotes` (folder name from `RemoteNames.Folder`). Names are defined in `game/shared/src/ReplicatedStorage/Shared/Remotes/RemoteNames.luau`. **When you add or change a remote, update this file and `RemoteNames.luau`** (and PROJECT_MAP/README/DEPENDENCIES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

**Direction**: **C→S** = Client → Server (client fires/invokes, server handles). **S→C** = Server → Client (server fires, client listens). **S→All** = Server → All clients.

---

| Remote name       | Type           | Direction | Payload / schema |
|-------------------|----------------|-----------|------------------|
| **WaveState**     | RemoteEvent    | S→All     | **Server** fires to all clients. Payload (table): `state` (string), `wave` (number); plus optional fields depending on `state`: `enemies`, `enemiesRemaining`, `players`, `intermission`, `intermissionEndsAt`, `nextWavePlayers`, `reason`. States: `"Preparing"`, `"InProgress"`, `"Cleared"`, `"Blocked"`, `"GameOver"`, `"Won"`. For `"InProgress"`, `enemiesRemaining` = number of enemies left to kill for the wave to complete (derived from the wave director's planned total minus kills). For `"Won"`, optional `reason` (e.g. `"BossDefeated"`). `intermissionEndsAt` = server time when intermission ends. |
| **ReturnToLobby** | RemoteEvent    | C→S       | **Client** fires (no args). Server initiates teleport back to lobby. Used by Settings UI "Return to Lobby" button. |
| **MapVote**       | RemoteEvent    | —         | *Not yet implemented.* Reserved for map vote (e.g. client sends vote, server broadcasts result). |
| **ShopOpen**      | RemoteEvent    | S→C       | **Server** fires to **one** client (trader prompt triggered). No payload. |
| **ShopGetCatalog**| RemoteFunction | C→S       | **Client** invokes (no args). **Server** returns: catalog for that player (weapons, ammo refill quotes, money, owned tools/sentries, etc.). Structure is built by `CatalogAndPricing.getCatalogForPlayer`. |
| **ShopBuyWeapon**  | RemoteFunction | C→S       | **Client** invokes `(weaponId: string)`. **Server** returns: `{ success: boolean, message?: string }`. |
| **ShopBuyAmmo**    | RemoteFunction | C→S       | **Client** invokes with either (1) `weaponId: string` for one weapon, or (2) table `{ allOwned = true }` for all owned, or (3) table `{ weaponId: string }`. **Server** returns: `{ success: boolean, message?: string }`. |
| **WeaponAim**     | RemoteEvent    | C→S       | **Client** fires `(hitPosition: Vector3, lookDirection: Vector3, cameraOrigin: Vector3)`. Server updates aim state for hit detection. |
| **WeaponFire**    | RemoteEvent    | C→S       | **Client** fires `(weaponId: string, hitPosition: Vector3, lookDirection: Vector3, cameraOrigin: Vector3)`. Server runs weapon fire handler (damage, ammo). |
| **WeaponReload**  | RemoteEvent    | C→S       | **Client** fires `(weaponId: string)`. Server starts reload for that weapon tool. |
| **DamageIndicator** | RemoteEvent  | S→C       | **Server** fires to **one** client: `(player, enemyModel: Model, dealtDamage: number, worldPosition: Vector3, normalizedStyleTag: string?)`. Client shows damage number at position; `normalizedStyleTag` optional (e.g. `"critical"`). |
| **ClassGetData**  | RemoteFunction | C→S       | **Client** invokes (no args). **Server** returns: same shape as **ClassState** payload (see below). |
| **ClassSelect**   | RemoteFunction | C→S       | **Client** invokes `(classId: string)`. **Server** returns: `{ success: boolean, message?: string }`. |
| **ClassState**    | RemoteEvent    | S→C       | **Server** fires to **one** client when class state changes. Payload: `ClassStateSync.buildPayloadForPlayer(player)` plus `reason`. Schema: `{ success, canSwitch, waveState, maxLevel, currentClassId, currentClassName, currentBonuses, classes[], reason? }`. Each `classes[]`: `{ id, name, description, weaponTag, level, xp, xpToNext, isCurrent, currentBonuses, perLevelBonuses }`. |
| **SettingsGet**   | RemoteFunction | C→S       | **Client** invokes (no args). **Server** returns: `{ success: boolean, settings?: table }`. `settings`: `{ schemaVersion, audio: { musicVolume, musicMuted, sfxVolume, sfxMuted }, hud: { scale, positions } }`. Audio values are in [0,1], hud.scale is in [0.6, 1.45]. |
| **SettingsSave**  | RemoteEvent    | C→S       | **Client** fires `(rawSettings: table)`. Server sanitizes and persists. Same shape as **SettingsGet** `settings` (audio/hud). |
| **EditOfflinePlayerData** | RemoteFunction | C→S | **Client** invokes `(userId: number, edits: { { path: string, value: any } })`. Server edits saved player data only when that player is offline. Paths are dot-separated (e.g. `classes.progressByClassId.scentry.level`). Returns `{ success: boolean, message?: string }`. Allowed only in Studio by default. |
| **SpectatorState** | RemoteEvent | S→C | **Server** fires to **one** client when spectator state changes. Payload: `{ isSpectating: boolean, livingPlayerUserIds: { number }?, respawnsAt: number? }`. When `isSpectating` is true, client enters spectator mode and can cycle camera among players in `livingPlayerUserIds`. `respawnsAt` is server time (seconds, from `workspace:GetServerTimeNow()`) when the spectator will spawn; client can compute countdown as `respawnsAt - workspace:GetServerTimeNow()`. When false or `respawnsAt` is 0/nill, client exits spectator mode (e.g. after respawn). Server updates `livingPlayerUserIds` when the set of living players in the match changes. |
| **SpectatorRequest** | RemoteFunction | C→S | **Client** invokes `(request: string)`. **Server** returns: `{ success: boolean, message?: string, isSpectating?: boolean }`. Requests: `"toggleSpectate"` (toggle spectator mode when dead), `"spawnNow"` (attempt immediate spawn), `"exitSpectate"` (exit spectator mode without spawning). Used for late joiners or players who want to control their spectator state. |

---

## Summary table (quick reference)

| Name                | Type           | Direction |
|---------------------|----------------|-----------|
| WaveState           | RemoteEvent    | S→All     |
| ReturnToLobby       | RemoteEvent    | C→S       |
| MapVote             | RemoteEvent    | —         |
| ShopOpen            | RemoteEvent    | S→C       |
| ShopGetCatalog      | RemoteFunction | C→S       |
| ShopBuyWeapon       | RemoteFunction | C→S       |
| ShopBuyAmmo         | RemoteFunction | C→S       |
| WeaponAim           | RemoteEvent    | C→S       |
| WeaponFire          | RemoteEvent    | C→S       |
| WeaponReload        | RemoteEvent    | C→S       |
| DamageIndicator     | RemoteEvent    | S→C       |
| ClassGetData        | RemoteFunction | C→S       |
| ClassSelect         | RemoteFunction | C→S       |
| ClassState          | RemoteEvent    | S→C       |
| SettingsGet         | RemoteFunction | C→S       |
| SettingsSave        | RemoteEvent    | C→S       |
| EditOfflinePlayerData | RemoteFunction | C→S       |
| SpectatorState      | RemoteEvent    | S→C       |
| SpectatorRequest    | RemoteFunction | C→S       |

---

## Remotes folder attributes (server-set)

The `Remotes` folder has attributes updated by the server for clients that read them instead of (or in addition to) events:

- `CurrentWaveState` (string): same as latest **WaveState** payload `state`.
- `CurrentWaveNumber` (number): current wave index.
- `IntermissionEndTime` (number): server time when intermission ends (for **WaveState** `"Preparing"`).
- `SpectatingPlayers` (IntValue): count of players currently in spectator mode. Updated when players enter/exit spectator state.
- `CurrentSpectatorTarget` (string): name of the player currently being spectated. Updated when cycling targets.

The **Remotes** folder also contains:

- `WaveEnemiesRemaining` (IntValue): number of enemies left to kill for the current wave to complete. Updated by the server when a wave starts and when each enemy dies. Clients can read `.Value` and listen to `.Changed` for the HUD.

---

## Settings System

The Settings system allows players to customize audio levels and HUD layout. It uses a client-server architecture with server-side persistence via `PlayerDataService`.

### Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                    Settings Flow                                    │
└────────────────────────────────────────────────────────────────────┘

Client UI (SettingsMenuController)
         |
         | (1) User opens settings (F10 or gear icon)
         V
┌────────────────────────────────────────────────────────────────────┐
│ SettingsMenuController.run()                                       │
│ - Builds SettingsMenuUi (View)                                     │
│ - Creates subcontrollers: Audio, HUD Layout, Visibility, Return  │
│ - Loads settings from server via SettingsGet                       │
└────────────────────────────────────────────────────────────────────┘
         |
         | (2) User modifies settings (sliders, drag HUD)
         V
┌────────────────────────────────────────────────────────────────────┐
│ Subcontrollers dispatch changes                                    │
│ - AudioController: queues save after 0.8s debounce                 │
│ - HudLayoutController: queues save when drag ends                  │
└────────────────────────────────────────────────────────────────────┘
         |
         | (3) SettingsSave RemoteEvent.FireServer()
         V
┌────────────────────────────────────────────────────────────────────┐
│ SettingsService (Server)                                           │
│ - OnServerEvent handler receives rawSettings                       │
│ - sanitizeSettings() validates/clamps all values                   │
│ - PlayerDataService.set(player, {"settings"}, sanitized)          │
└────────────────────────────────────────────────────────────────────┘
         |
         | (4) DataPersistence (PlayerDataService)
         |    saves via ProfileStore on session end
         V
┌────────────────────────────────────────────────────────────────────┐
│ DataStore (persistent)                                             │
└────────────────────────────────────────────────────────────────────┘
```

### Files

| File | Purpose |
|------|---------|
| **`SettingsService`** | Server-side service; binds SettingsGet/SettingsSave remotes, sanitizes data, persists via PlayerDataService. |
| **`SettingsMenuController`** | Main client controller; orchestrates subcontrollers, loads settings from server on startup. |
| **`SettingsMenuUi`** | UI builder; constructs the settings panel UI tree. |
| **`SettingsAudioController`** | Audio controls; tracks all Sounds in game, applies volume/mute settings. |
| **`SettingsHudLayoutController`** | HUD layout controls; drag-to-reposition, scale controls, position persistence. |
| **`SettingsHudLayoutService`** | Position serialization/deserialization, screen clamping, transform logic. |
| **`SettingsVisibilityController`** | F10 toggle for hiding all UI/HUD. |
| **`SettingsReturnToLobbyController`** | Return-to-lobby button handler (match only). |
| **`HudMoveModeInput`** | Input bindings for HUD move mode (drag-to-reposition). |
| **`SettingsRemotesUtil`** | Remote resolution utilities to avoid code duplication. |
| **`SettingsConfig`** | Shared configuration (audio ranges, HUD scale limits, HUD root definitions). |
| **`HudLayoutConfig`** | HUD layout config (draggable/non-draggable roots, ScreenGui names). |

### Settings Schema

```lua
{
	schemaVersion = 1,
	audio = {
		musicVolume = 0..1,     -- music volume level
		musicMuted = boolean,   -- music mute state
		sfxVolume = 0..1,       -- SFX volume level
		sfxMuted = boolean,     -- SFX mute state
	},
	hud = {
		scale = 0.6..1.45,      -- HUD scale multiplier
		positions = {           -- dynamic table of UDim2 positions
			["ScreenGuiName/RootName"] = {
				xScale = number,   -- UDim2 X.Scale
				xOffset = number,  -- UDim2 X.Offset (rounded to integer)
				yScale = number,   -- UDim2 Y.Scale
				yOffset = number,  -- UDim2 Y.Offset (rounded to integer)
			},
			-- ... up to SettingsConfig.Hud.MaxPositionEntries (default: 120)
		}
	}
}
```

### Subcontrollers

| Subcontroller | Responsibility |
|---------------|----------------|
| **Audio** | Volume sliders, mute buttons, sound tracking. Debounced save after 0.8s. |
| **HUD Layout** | Drag-to-reposition, scale controls, position persistence. Debounced save on drag end. |
| **Visibility** | F10 toggle to hide/show all UI/HUD. Preserves original ScreenGui.Enabled states. |
| **ReturnToLobby** | Match-only button to teleport back to lobby. Validates remote availability. |

### Configuration

See `SettingsConfig` in `game/shared/src/ReplicatedStorage/Shared/Settings/SettingsConfig.luau`:

- Audio volume ranges: [0, 1] for both music and SFX
- HUD scale range: [0.6, 1.45] (configurable)
- HUD move mode attribute: `"LobbyHudMoveModeEnabled"`
- Max position entries: 120
- Save debounce delay: 0.8 seconds

### Remote Flow

```
Client opens settings UI
    ↓
SettingsGet RemoteFunction → Server → Load from PlayerDataService
    ↓
Server returns sanitized settings
    ↓
Client applies settings to UI + game objects
    ↓
User modifies settings via UI
    ↓
SettingsSave RemoteEvent → Server → Sanitize → Save to PlayerDataService
    ↓
Server updates PlayerDataService (persisted to DataStore)
```

---

## SpectatorService

The **SpectatorService** module (`game/match/src/ServerScriptService/Match/Spectator/SpectatorService.luau`) provides a clean API for spectator mode management:

### Functions

| Function | Description |
|----------|-------------|
| `SpectatorService.start()` | Initialize the spectator service (called during match bootstrap). Sets up remotes and request handler. |
| `SpectatorService.stop()` | Stop the spectator service and cleanup state. |
| `SpectatorService.handleRequest(player, request)` | Handle spectator requests from clients. Returns `{ success, message?, isSpectating? }`. |
| `SpectatorService.isSpectating(player)` | Check if a player is currently spectating. |
| `SpectatorService.getSpectatingPlayers()` | Get table of all spectating players. |
| `SpectatorService.getSpectatingPlayerCount()` | Get count of spectating players. |
| `SpectatorService.getLivingPlayerUserIds()` | Get array of living player UserIds. |
| `SpectatorService.onPlayerDeath(player)` | Call when a player dies. Returns `true` if player entered spectating. |
| `SpectatorService.onPlayerRespawn(player, character)` | Call when a player respawns. Cleans up spectator state. |
| `SpectatorService.onPlayerJoinDuringMatch(player)` | Call for late joiners during an active match. Forces spectator mode until respawn. |
| `SpectatorService.onPlayerRemove(player)` | Call when a player leaves the game. Cleanup. |
| `SpectatorService.enterSpectator(player)` | Explicit API to enter spectator mode. Returns `{ success, message?, isSpectating? }`. |
| `SpectatorService.exitSpectator(player)` | Explicit API to exit spectator mode. Returns `{ success, message?, isSpectating? }`. |
| `SpectatorService.spawnNow(player)` | Explicit API to force immediate spawn. Returns `{ success, message?, isSpectating? }`. |

### Server Attributes

The **Remotes** folder has these server-set attributes for client visibility:
- `SpectatingPlayers` (IntValue): count of players currently in spectator mode. Updated when players enter/exit spectator state.
- `CurrentSpectatorTarget` (StringValue): name of the player currently being spectated (first target). Updated when cycling or when new spectators join.

### Client-Side API

The client-side **Spectator** system is split into:
- `game/match/src/StarterPlayer/StarterPlayerScripts/MatchClient/Spectator/Spectator.luau` - Entry module
- `SpectatorController` - Handles camera control, target cycling, and remote communication
- `SpectatorView` - Handles UI building and rendering

The client handles:
- Camera switching to `Scriptable` type and following target player
- Q/E key handling for target cycling
- T key for toggling/exit
- UI display showing target name and respawn countdown
- Wave state handling (exits spectator on GameOver/Won)

### Deprecated Client Module

The old `game/shared/src/StarterPlayerScripts/SharedClient/Spectator/SpectatorMode.client.luau` module is deprecated and replaced by the MatchClient structure above.
