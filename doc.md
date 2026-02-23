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
