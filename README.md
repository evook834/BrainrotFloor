# Brainrot Floor (Rojo Setup)

## Tooling
- `aftman` manages the local toolchain
- `rojo` syncs source files with Roblox Studio
- `wally` manages external package dependencies

## Quick start
1. Open this folder in a terminal.
2. Run one of:
   - `rojo serve game/places/lobby/default.project.json` for the lobby place
   - `rojo serve game/places/match/default.project.json` for match/map places
   - `rojo serve default.project.json` for the legacy combined project
3. In Roblox Studio, install and open the Rojo plugin.
4. Connect to `localhost:34872` and sync the project.
5. If you use lobby matchmaking, set `LOBBY_PLACE_ID` and `MATCH_PLACE_IDS` in `game/shared/server/src/Shared/MatchmakingConfig.luau`.

## Per-place Wally manifests
- Lobby manifest: `game/places/lobby/wally.toml`
- Match manifest: `game/places/match/wally.toml`
- Install dependencies per place:
  - `cd game/places/lobby && wally install`
  - `cd game/places/match && wally install`

## CI and publish pipeline

Validation/build workflow:
- File: `.github/workflows/ci-places.yml`
- Triggers:
  - `pull_request` (all branches)
  - `push` to `main`
  - `workflow_dispatch` (manual)
- Behavior:
  - Installs toolchain using `scripts/ci/install_toolchain.sh` (`aftman` + tools from `aftman.toml`)
  - Runs optional per-place `wally install` when network is reachable
  - Auto-selects project files:
    - prefers `game/places/<place>/default.project.json`
    - falls back to `<place>.project.json` when place project files are not yet in the branch
  - Validates place mappings with `rojo sourcemap`
  - Builds:
    - `game/places/lobby/default.project.json` -> `artifacts/lobby-place.rbxlx`
    - `game/places/match/default.project.json` -> `artifacts/match-place.rbxlx`
  - Uploads `artifacts/` as `place-build-artifacts`

Publish skeleton workflow:
- File: `.github/workflows/publish-opencloud.yml`
- Trigger:
  - `workflow_dispatch` only (manual gate), with inputs:
    - `environment`: `staging` or `production`
    - `publish_lobby`: boolean
    - `publish_match`: boolean
- Strategy:
  1. Let CI (`ci-places.yml`) pass on the commit you want to ship.
  2. Run `publish-opencloud.yml` manually against that commit.
  3. Select the target environment (`staging` or `production`) so environment-scoped secrets are used.
  4. Choose whether to publish lobby, match, or both.
- Current state:
  - The workflow builds fresh artifacts and validates required secrets.
  - Final Open Cloud publish API call is intentionally left as a skeleton step for your credential/policy wiring.

Required GitHub environment secrets (`staging` and/or `production`):
- `ROBLOX_OPEN_CLOUD_API_KEY`
- `ROBLOX_UNIVERSE_ID`
- `ROBLOX_LOBBY_PLACE_ID`
- `ROBLOX_MATCH_PLACE_ID`

## Local CI-equivalent commands

```bash
scripts/ci/install_toolchain.sh
scripts/ci/build_and_validate_places.sh
```

Optional:
- `SKIP_WALLY_INSTALL=1 scripts/ci/build_and_validate_places.sh` to skip network-dependent Wally install.
- `ROJO_TIMEOUT_SECONDS=300 scripts/ci/build_and_validate_places.sh` to raise the per-command Rojo timeout.

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
Rojo sync can use the new place projects in `game/places/*/default.project.json` or legacy root project files.

## Multi-place runtime routing
Role selection is centralized in `game/shared/server/src/Shared/MatchmakingConfig.luau`:
- `LOBBY_PLACE_ID`: public lobby place id
- `MATCH_PLACE_IDS`: map/match place id list used for teleport + reserved servers
- `FORCE_PLACE_ROLE`: optional override (`"Lobby"` or `"Match"`) for testing only

Runtime behavior:
- `GameBootstrap` runs only in match places
- `LobbyMatchmaker` runs only in lobby places
- `MatchServerRegistry` runs only in match places (and only with `PrivateServerId`)

## Ownership layout
- Shared replicated config: `game/shared/replicated/src/*`
- Shared server modules: `game/shared/server/src/*`
- Shared client scripts: `game/shared/client/src/*`
- Lobby-only code: `game/places/lobby/src/*`
- Match-only code: `game/places/match/src/*`

Place-specific Rojo mappings:
- `game/places/lobby/default.project.json` mounts `Shared` + `Lobby` content.
- `game/places/match/default.project.json` mounts `Shared` + `Match` content.

## Difficulty tuning
Gameplay difficulty modifiers live in `game/shared/replicated/src/Shared/GameConfig.luau` under `Difficulty.Settings`.

Current server systems use:
- `EnemyHealthMultiplier` for spawned enemy max health
- `EnemyDamageMultiplier` for enemy melee attack damage

## Server script placement
Use these exact paths when syncing with Rojo:

1. `game/shared/server/src/Shared/MatchmakingConfig.luau`
   - Studio location: `ServerScriptService > Shared > MatchmakingConfig` (`ModuleScript`)
2. `game/shared/server/src/Shared/PlaceRole.luau`
   - Studio location: `ServerScriptService > Shared > PlaceRole` (`ModuleScript`)
   - Central place-role resolver used by startup scripts.
3. `game/places/lobby/src/ServerScriptService/Lobby/LobbyMatchmaker.server.luau`
   - Studio location: `ServerScriptService > Lobby > LobbyMatchmaker` (`Script`)
   - Runs in the lobby place (public server). Handles difficulty button prompts and teleports.
4. `game/places/match/src/ServerScriptService/Match/GameBootstrap.server.luau`
   - Studio location: `ServerScriptService > Match > GameBootstrap` (`Script`)
   - Runs core wave/combat systems for match places.
5. `game/places/match/src/ServerScriptService/Match/MatchServerRegistry.server.luau`
   - Studio location: `ServerScriptService > Match > MatchServerRegistry` (`Script`)
   - Runs in reserved match servers. Publishes heartbeat/player slot state to MemoryStore.
6. `game/places/match/src/ServerScriptService/Match/Services/*`
   - Studio location: `ServerScriptService > Match > Services > ...` (`ModuleScript`s)
   - Shared by match runtime systems only.

Required lobby workspace setup:
- `Workspace > DifficultyButtons` folder with button `BasePart` instances.
- Each button maps to a difficulty (`Easy`, `Normal`, `Hard`) by part name, or by a `Difficulty` attribute.
- Set `MATCH_PLACE_IDS` in `game/shared/server/src/Shared/MatchmakingConfig.luau` to the shared map pool used for all difficulties.
- Matchmaking reuses existing servers first; if none exist for that difficulty, it reserves a server on a random place from `MATCH_PLACE_IDS`.

## Automatic local backups
- Backup script: `scripts/auto_backup_place.ps1`
- Task registration: `scripts/register_auto_backup_task.ps1`
- Scheduled task name: `BrainrotFloorAutoBackup`

Commands:
- Register auto-backup task:
  `powershell -ExecutionPolicy Bypass -File .\\scripts\\register_auto_backup_task.ps1`
- Run one backup immediately:
  `powershell -ExecutionPolicy Bypass -File .\\scripts\\auto_backup_place.ps1`
- Remove task later if needed:
  `Unregister-ScheduledTask -TaskName BrainrotFloorAutoBackup -Confirm:$false`
