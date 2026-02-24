local WaveConfig = {
	IntermissionSeconds = 10,
	BaseEnemyCount = 6,
	EnemiesPerWave = 2,
	SpawnCadence = {
		InitialDelaySeconds = 2,
		BaseIntervalSeconds = 3,
		MinIntervalSeconds = 1.2,
		WaveAccelerationPerWave = 0.12,
		IntraWaveAcceleration = 0.6,
		GroupSize = 4,
		GroupPauseSeconds = 1.0,
		IntraBurstDelaySeconds = 0.08,
		PlayerScaling = {
			Enabled = true,
			BasePlayers = 1,
			BurstSizeBase = 1,
			BurstSizePerExtraPlayer = 1,
			MaxBurstSize = 4,
			IntervalMultiplierPerExtraPlayer = 0.12,
			MinIntervalMultiplier = 0.45,
			GroupPauseMultiplierPerExtraPlayer = 0.08,
			MinGroupPauseMultiplier = 0.5,
		},
	},
}

return WaveConfig
