--[[
	WaveConfig — KF1-style wave director and spawn cadence.
	Director: WaveTotalTarget (planned spawns, capped 1500), AliveCap (concurrent alive), role caps, pack-based pressure.
]]

local WaveConfig = {
	TotalWaves = 10,
	BossWaveNumber = 11,
	MaxMonstersPerWave = 1500,
	WaveTotalPlannedMax = 1400, -- internal clamp so we rarely hit 1500 brake
	MaxPlayers = 20,
	IntermissionSeconds = 15,

	-- Director: Solo Normal baselines (waves 1–10). Scaled by player count and difficulty.
	Director = {
		BaseWaveTotal = { 20, 26, 32, 40, 50, 62, 76, 92, 112, 140 },
		BaseAliveCap = { 8, 9, 10, 12, 14, 16, 18, 20, 22, 24 },
		-- CountMult(p) = 1 + CountMultK * (p-1)^CountMultExp. Sub-linear for WaveTotalTarget.
		CountMultK = 0.50,
		CountMultExp = 0.60,
		-- AliveMult(p) = 1 + AliveMultK * (p-1)^AliveMultExp. Sub-linear for AliveCap.
		AliveMultK = 0.35,
		AliveMultExp = 0.70,
		AliveCapMin = 8,
		AliveCapMax = 120,
		-- Pressure-based spawn cooldown: lerp(CooldownMin, CooldownMax, Alive/AliveCap).
		CooldownMin = 0.15,
		CooldownMax = 1.0,
		DirectorTickSeconds = 0.25,
		-- Role concurrent caps as fraction of AliveCap (trash/medium). Heavies/specials use formulas.
		TrashCapFraction = 0.70,
		MediumCapFraction = 0.28,
		-- SpecialCap = 1 + floor(w/3) + floor((p-1)/6) [+1 on Hard/Nightmare].
		-- HeavyCap = max(0, floor((w-6)/2) + floor((p-1)/10)) [+1 on Hard/Nightmare].
	},

	-- Composition targets per wave (Solo Normal): % of spawns that are trash/medium/heavy/special.
	-- Index 1 = wave 1, index 10 = wave 10. Heavies/specials ramp in mid/late waves.
	CompositionPercentByWave = {
		{ trash = 100, medium = 0, heavy = 0, special = 0 },
		{ trash = 90, medium = 10, heavy = 0, special = 0 },
		{ trash = 85, medium = 12, heavy = 0, special = 3 },
		{ trash = 80, medium = 15, heavy = 0, special = 5 },
		{ trash = 75, medium = 17, heavy = 3, special = 5 },
		{ trash = 70, medium = 18, heavy = 5, special = 7 },
		{ trash = 68, medium = 19, heavy = 6, special = 7 },
		{ trash = 65, medium = 20, heavy = 8, special = 7 },
		{ trash = 62, medium = 22, heavy = 9, special = 7 },
		{ trash = 60, medium = 25, heavy = 10, special = 5 },
	},

	-- Legacy / fallback (used if Director is not used).
	BaseEnemyCount = 6,
	EnemiesPerWave = 2,
	BaseEnemiesPerWave = 10,
	Trajectory = {
		TargetAliveBase = 8,
		TargetAlivePerPlayer = 4,
		MaxTargetAlive = 60,
		AvgTrashTTKSeconds = 3,
	},
	WaveScaling = {
		Enabled = true,
		BasePlayers = 1,
		EnemiesPerExtraPlayer = 1,
		MaxEnemyCountMultiplier = 2,
		EnemyHealthMultiplierPerExtraPlayer = 0.15,
		MaxEnemyHealthMultiplier = 1.75,
	},
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
