# Remotes reference

All remotes live under `ReplicatedStorage.Remotes` (folder name from `RemoteNames.Folder`). Names are defined in `game/shared/src/ReplicatedStorage/Shared/Remotes/RemoteNames.luau`. **When you add or change a remote, update this file and `RemoteNames.luau`** (and PROJECT_MAP/README/DEPENDENCIES as needed; see [README § Maintaining the docs](README.md#maintaining-the-docs-dependencies-project_map-readme-remotes)).

**Direction**: **C→S** = Client → Server (client fires/invokes, server handles). **S→C** = Server → Client (server fires, client listens). **S→All** = Server → All clients.

---

| Remote name       | Type           | Direction | Payload / schema |
|-------------------|----------------|-----------|------------------|
| **WaveState**     | RemoteEvent    | S→All     | **Server** fires to all clients. Payload (table): `state` (string), `wave` (number); plus optional fields depending on `state`: `enemies`, `enemiesRemaining`, `players`, `intermission`, `intermissionEndsAt`, `nextWavePlayers`, `reason`. States: `"Preparing"`, `"InProgress"`, `"Cleared"`, `"Blocked"`, `"GameOver"`, `"Won"`. For `"InProgress"`, `enemiesRemaining` = number of enemies left to kill for the wave to complete (derived from the wave director’s planned total minus kills). For `"Won"`, optional `reason` (e.g. `"BossDefeated"`). `intermissionEndsAt` = server time when intermission ends. |
| **ReturnToLobby** | RemoteEvent    | —         | *Not yet implemented.* Reserved for client request to return to lobby or server notification. |
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
| **SettingsGet**   | RemoteFunction | C→S       | **Client** invokes (no args). **Server** returns: `{ success: boolean, settings?: table }`. `settings`: `{ schemaVersion, audio: { musicVolume, musicMuted, sfxVolume, sfxMuted }, hud: { scale, positions } }`. |
| **SettingsSave**  | RemoteEvent    | C→S       | **Client** fires `(rawSettings: table)`. Server sanitizes and persists. Same shape as **SettingsGet** `settings` (audio/hud). |
| **EditOfflinePlayerData** | RemoteFunction | C→S | **Client** invokes `(userId: number, edits: { { path: string, value: any } })`. Server edits saved player data only when that player is offline. Paths are dot-separated (e.g. `classes.progressByClassId.scentry.level`). Returns `{ success: boolean, message?: string }`. Allowed only in Studio by default. |
| **SpectatorState** | RemoteEvent | S→C | **Server** fires to **one** client when spectator state changes. Payload: `{ isSpectating: boolean, livingPlayerUserIds: { number }?, respawnsAt: number? }`. When `isSpectating` is true, client enters spectator mode and can cycle camera among players in `livingPlayerUserIds`. `respawnsAt` is server time (seconds, from `workspace:GetServerTimeNow()`) when the spectator will spawn; client can compute countdown as `respawnsAt - workspace:GetServerTimeNow()`. When false or `respawnsAt` is 0/nill, client exits spectator mode (e.g. after respawn). Server updates `livingPlayerUserIds` when the set of living players in the match changes. |
| **SpectatorRequest** | RemoteFunction | C→S | **Client** invokes `(request: string)`. **Server** returns: `{ success: boolean, message?: string, isSpectating?: boolean }`. Requests: `"toggleSpectate"` (toggle spectator mode when dead), `"spawnNow"` (attempt immediate spawn), `"exitSpectate"` (exit spectator mode without spawning). Used for late joiners or players who want to control their spectator state. |

---

## Summary table (quick reference)

| Name            | Type           | Direction |
|-----------------|----------------|-----------|
| WaveState       | RemoteEvent    | S→All     |
| ReturnToLobby   | RemoteEvent    | —         |
| MapVote         | RemoteEvent    | —         |
| ShopOpen        | RemoteEvent    | S→C       |
| ShopGetCatalog  | RemoteFunction | C→S       |
| ShopBuyWeapon   | RemoteFunction | C→S       |
| ShopBuyAmmo     | RemoteFunction | C→S       |
| WeaponAim       | RemoteEvent    | C→S       |
| WeaponFire      | RemoteEvent    | C→S       |
| WeaponReload    | RemoteEvent    | C→S       |
| DamageIndicator | RemoteEvent    | S→C       |
| ClassGetData    | RemoteFunction | C→S       |
| ClassSelect     | RemoteFunction | C→S       |
| ClassState      | RemoteEvent    | S→C       |
| SettingsGet     | RemoteFunction | C→S       |
| SettingsSave    | RemoteEvent    | C→S       |
| EditOfflinePlayerData | RemoteFunction | C→S       |
| SpectatorState        | RemoteEvent    | S→C       |
| SpectatorRequest      | RemoteFunction | C→S       |

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
