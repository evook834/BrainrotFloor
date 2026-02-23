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
