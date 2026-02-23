# Brainrot Floor (Rojo Setup)

## Tooling
- `aftman` manages the local toolchain
- `rojo` syncs source files with Roblox Studio

## Quick start
1. Open this folder in a terminal.
2. Run one of:
   - `rojo serve lobby.project.json` for the lobby place
   - `rojo serve match.project.json` for match/map places
   - `rojo serve default.project.json` for the legacy single-project setup
3. In Roblox Studio, install and open the Rojo plugin.
4. Connect to `localhost:34872` and sync the project.
5. If you use lobby matchmaking, set `LOBBY_PLACE_ID` and `MATCH_PLACE_IDS` in `src/ServerScriptService/Shared/MatchmakingConfig.luau`.

## Game scaffold included
- Wave loop with intermission and scaling enemy count.
- Enemy spawner that clones models from `ServerStorage/EnemyTemplates`.
- Client HUD that shows wave state.
- Difficulty modifiers for enemy stats (configured in `GameConfig`).

## What to add in Studio
1. Add enemy models (with `Humanoid` and `HumanoidRootPart`) under `ServerStorage > EnemyTemplates`.
2. Add spawn parts under `Workspace > SpawnPoints`.
3. Hit Play to test wave spawning.

## Existing place file
Your existing place file (`Brainrot  Floor.rbxlx`) is untouched.
Rojo sync can use `default.project.json`, `lobby.project.json`, or `match.project.json`.

## Multi-place runtime routing
Role selection is centralized in `src/ServerScriptService/Shared/MatchmakingConfig.luau`:
- `LOBBY_PLACE_ID`: public lobby place id
- `MATCH_PLACE_IDS`: map/match place id list used for teleport + reserved servers
- `FORCE_PLACE_ROLE`: optional override (`"Lobby"` or `"Match"`) for testing only

Runtime behavior:
- `GameBootstrap` runs only in match places
- `LobbyMatchmaker` runs only in lobby places
- `MatchServerRegistry` runs only in match places (and only with `PrivateServerId`)

## Ownership layout
- Shared code: `src/ServerScriptService/Shared/*`
- Lobby-only code: `src/ServerScriptService/Lobby/*`
- Match-only code: `src/ServerScriptService/Match/*`
- Lobby workspace sync source: `src/Workspace/Lobby/*`
- Match workspace sync source: `src/Workspace/Match/*`

Place-specific Rojo mappings:
- `lobby.project.json` mounts only `ServerScriptService/Shared` and `ServerScriptService/Lobby`.
- `match.project.json` mounts only `ServerScriptService/Shared` and `ServerScriptService/Match`.

## Difficulty tuning
Gameplay difficulty modifiers live in `src/ReplicatedStorage/Shared/GameConfig.luau` under `Difficulty.Settings`.

Current server systems use:
- `EnemyHealthMultiplier` for spawned enemy max health
- `EnemyDamageMultiplier` for enemy melee attack damage

## Server script placement
Use these exact paths when syncing with Rojo:

1. `src/ServerScriptService/Shared/MatchmakingConfig.luau`
   - Studio location: `ServerScriptService > Shared > MatchmakingConfig` (`ModuleScript`)
2. `src/ServerScriptService/Shared/PlaceRole.luau`
   - Studio location: `ServerScriptService > Shared > PlaceRole` (`ModuleScript`)
   - Central place-role resolver used by startup scripts.
3. `src/ServerScriptService/Lobby/LobbyMatchmaker.server.luau`
   - Studio location: `ServerScriptService > Lobby > LobbyMatchmaker` (`Script`)
   - Runs in the lobby place (public server). Handles difficulty button prompts and teleports.
4. `src/ServerScriptService/Match/GameBootstrap.server.luau`
   - Studio location: `ServerScriptService > Match > GameBootstrap` (`Script`)
   - Runs core wave/combat systems for match places.
5. `src/ServerScriptService/Match/MatchServerRegistry.server.luau`
   - Studio location: `ServerScriptService > Match > MatchServerRegistry` (`Script`)
   - Runs in reserved match servers. Publishes heartbeat/player slot state to MemoryStore.
6. `src/ServerScriptService/Match/Services/*`
   - Studio location: `ServerScriptService > Match > Services > ...` (`ModuleScript`s)
   - Shared by match runtime systems only.

Required lobby workspace setup:
- `Workspace > DifficultyButtons` folder with button `BasePart` instances.
- Each button maps to a difficulty (`Easy`, `Normal`, `Hard`) by part name, or by a `Difficulty` attribute.
- Set `MATCH_PLACE_IDS` in `src/ServerScriptService/Shared/MatchmakingConfig.luau` to the shared map pool used for all difficulties.
- Matchmaking reuses existing servers first; if none exist for that difficulty, it reserves a server on a random place from `MATCH_PLACE_IDS`.

## Automatic local backups
- Backup script: `scripts/auto_backup_place.ps1`
- Task registration: `scripts/register_auto_backup_task.ps1`
- Scheduled task name: `BrainrotFloorAutoBackup`

Commands:
- Register auto-backup task:
  `powershell -ExecutionPolicy Bypass -File .\scripts\register_auto_backup_task.ps1`
- Run one backup immediately:
  `powershell -ExecutionPolicy Bypass -File .\scripts\auto_backup_place.ps1`
- Remove task later if needed:
  `Unregister-ScheduledTask -TaskName BrainrotFloorAutoBackup -Confirm:$false`
