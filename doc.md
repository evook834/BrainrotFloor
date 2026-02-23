# Out-Of-Wave Player Speed Change

## What changed

Player movement speed now increases whenever a wave is **not** active:

- At match start (before a wave starts)
- Between waves (`Preparing`)
- After a wave is cleared (`Cleared`)

Speed stays normal (no boost) when:

- A wave is active (`InProgress`)
- Wave flow is blocked (`Blocked`)

## Current multiplier value

`2.0` is configured here:

- `src/ReplicatedStorage/Shared/GameConfig.luau`
- Field: `Config.Player.OutOfWaveMoveSpeedMultiplier`

```luau
Player = {
    StartingMoney = 5000,
    DisableHealthRegen = true,
    RespawnDelaySeconds = 60,
    OutOfWaveMoveSpeedMultiplier = 2.0,
},
```

## Implementation notes

- Speed calculation is applied in:
  - `src/ServerScriptService/Match/Services/ClassService.luau`
  - `applyHumanoidMoveSpeedBonus(...)`
- Wave state changes trigger an immediate refresh of all players’ movement speed through:
  - `remotesFolder:GetAttributeChangedSignal("CurrentWaveState")`

---

# Sprint System (Lobby + Match)

## What changed

A hold-to-sprint system was added for players in both Lobby and Match.

- Hold `LeftShift` to sprint.
- Release `LeftShift` to return to normal movement speed.
- Sprint currently uses a `2.5x` multiplier.

The sprint logic is client-side and shared because it lives in `StarterPlayerScripts`, which both place mappings include.

## Current sprint multiplier value

`2.5` is configured here:

- `src/ReplicatedStorage/Shared/GameConfig.luau`
- Field: `Config.Player.SprintSpeedMultiplier`

```luau
Player = {
    StartingMoney = 5000,
    DisableHealthRegen = true,
    RespawnDelaySeconds = 60,
    OutOfWaveMoveSpeedMultiplier = 2.0,
    SprintSpeedMultiplier = 2.5,
},
```

## Implementation notes

- Sprint script:
  - `src/StarterPlayer/StarterPlayerScripts/Sprint.client.luau`
- Key handling:
  - `UserInputService.InputBegan` + `InputEnded` for `Enum.KeyCode.LeftShift`
- Character handling:
  - Rebinds on `CharacterAdded` so sprint still works after respawn
- Compatibility:
  - Tracks external `Humanoid.WalkSpeed` updates and reapplies sprint multiplier on top of the latest normal speed

---

# Sprint Stamina System (Lobby + Match)

## What changed

Sprint now uses stamina and includes a stamina HUD bar.

- While sprinting, stamina drains over time.
- When not sprinting, stamina regenerates after a short delay.
- If stamina reaches `0`, sprint is exhausted and disabled until stamina recovers to a minimum threshold.
- A bottom-center stamina bar shows current stamina percent and changes color at low stamina.

Like sprint, this system is shared for both Lobby and Match because it is implemented in `StarterPlayerScripts`.

## Current stamina tuning values

Configured in:

- `src/ReplicatedStorage/Shared/GameConfig.luau`
- Fields under `Config.Player`:

```luau
Player = {
    StartingMoney = 5000,
    DisableHealthRegen = true,
    RespawnDelaySeconds = 60,
    OutOfWaveMoveSpeedMultiplier = 2.0,
    SprintSpeedMultiplier = 2.5,
    SprintStaminaMax = 100,
    SprintStaminaDrainPerSecond = 35,
    SprintStaminaRegenPerSecond = 22,
    SprintStaminaRegenDelaySeconds = 0.45,
    SprintStaminaMinToSprint = 15,
},
```

## Implementation notes

- Script location:
  - `src/StarterPlayer/StarterPlayerScripts/Sprint.client.luau`
- Update loop:
  - Uses `RunService.Heartbeat` to process stamina drain/regen each frame.
- Sprint condition:
  - Sprint only applies while `LeftShift` is held, the player is moving, alive, and stamina allows sprint.
- Exhaustion handling:
  - Hitting `0` stamina disables sprint until stamina reaches `SprintStaminaMinToSprint`.
- UI:
  - Creates `ScreenGui` named `SprintStaminaHud` with a percentage fill bar above the XP bar.

---

# Enemy HP Scales With Difficulty

## What changed

Enemy HP is difficulty-scaled in match servers.

- `Easy` uses lower enemy HP.
- `Normal` uses baseline enemy HP.
- `Hard` uses higher enemy HP.

## Current HP multipliers

Configured in:

- `src/ReplicatedStorage/Shared/GameConfig.luau`
- `Config.Difficulty.Settings.<Difficulty>.EnemyHealthMultiplier`

Current values:

- `Easy`: `0.8`
- `Normal`: `1.0`
- `Hard`: `1.35`

## Implementation notes

- Difficulty is read from the active match difficulty via `DifficultyService`.
- Enemy HP multiplier is applied in:
  - `src/ServerScriptService/Match/Services/EnemyService.luau`
  - `getEnemyHealthMultiplierForDifficulty(...)`
- On enemy spawn:
  - Humanoid enemies have `Humanoid.MaxHealth` and `Humanoid.Health` scaled by difficulty.
  - Non-humanoid enemies set scaled `EnemyMaxHealth` based on `Config.Enemy.NonHumanoidMaxHealth`.

---

# Match Game Over When All Players Die

## What changed

A game-over flow was added for **match servers only** (not lobby).

- When all alive players die at the same time window, the match enters `GameOver`.
- Once `GameOver` is triggered, player respawns are cancelled/disabled.
- A full-screen game-over overlay is shown to clients.
- During game over, players can click a **Return to Lobby** button.

## Match-only guard

The game-over trigger is protected by the existing place-role check:

- `PlaceRole.shouldRunMatchSystems()`

This ensures the logic only runs where match systems are active.

## Implementation notes

- Server death/respawn + game-over detection:
  - `src/ServerScriptService/Match/GameBootstrap.server.luau`
  - Adds living-player check on death and triggers game over when none remain alive.
  - Cancels all pending respawn tokens so scheduled respawns no longer fire.
  - Sets `Workspace` attribute `GameOver = true`.

- Wave state terminal mode:
  - `src/ServerScriptService/Match/Services/WaveService.luau`
  - Adds `WaveService.gameOver(...)` to broadcast terminal state:
    - `CurrentWaveState = "GameOver"`
    - Remote payload `state = "GameOver"` with reason `AllPlayersDead`.
  - Stops wave loop progression after game over.

- Client HUD game-over screen:
  - `src/StarterPlayer/StarterPlayerScripts/WaveHud.client.luau`
  - Adds `GameOverOverlay` with `GAME OVER` title and reason text.
  - Listens for wave state `GameOver` and displays overlay.
  - Hides/suppresses intermission and respawn countdown UI once game over is active.

- Return-to-lobby remote + server teleport:
  - `src/ReplicatedStorage/Shared/GameConfig.luau`
  - Adds remote name `Config.Remotes.ReturnToLobby`.
  - `src/ServerScriptService/Match/GameBootstrap.server.luau`
  - Creates/binds `Remotes/ReturnToLobby` (`RemoteEvent`).
  - On request, validates that:
    - match systems are active
    - game over has already been triggered
  - Teleports the requesting player back to `MatchmakingConfig.LOBBY_PLACE_ID` using `TeleportService:TeleportAsync(...)`.
  - Includes retry logic and per-player cooldown/in-flight guards.

- Game-over mouse/camera input fix (button clickability):
  - `src/StarterPlayer/StarterPlayerScripts/WaveHud.client.luau`
  - While game over is active:
    - forces `UserInputService.MouseBehavior = Enum.MouseBehavior.Default`
    - forces `UserInputService.MouseIconEnabled = true`
    - temporarily sets `player.CameraMode = Enum.CameraMode.Classic`
  - Uses a render-step loop to keep mouse unlocked/visible while the overlay is up.
  - Restores previous camera mode when game-over UI is dismissed.
