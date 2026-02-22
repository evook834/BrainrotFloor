# Brainrot Floor (Rojo Setup)

## Tooling
- `aftman` manages the local toolchain
- `rojo` syncs source files with Roblox Studio

## Quick start
1. Open this folder in a terminal.
2. Run `rojo serve`.
3. In Roblox Studio, install and open the Rojo plugin.
4. Connect to `localhost:34872` and sync the project.

## Game scaffold included
- Wave loop with intermission and scaling enemy count.
- Enemy spawner that clones models from `ServerStorage/EnemyTemplates`.
- Client HUD that shows wave state.

## What to add in Studio
1. Add enemy models (with `Humanoid` and `HumanoidRootPart`) under `ServerStorage > EnemyTemplates`.
2. Add spawn parts under `Workspace > SpawnPoints`.
3. Hit Play to test wave spawning.

## Existing place file
Your existing place file (`Brainrot  Floor.rbxlx`) is untouched.
Rojo sync uses `default.project.json` and `src/` going forward.

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
