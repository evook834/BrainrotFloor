local ClassCatalog = require(script.Parent:WaitForChild("ClassCatalog"))
local EnemyProfiles = require(script.Parent:WaitForChild("EnemyProfiles"))
local RemoteNames = require(script.Parent:WaitForChild("RemoteNames"))
local ShopConfig = require(script.Parent:WaitForChild("ShopConfig"))

local Config = {
	Wave = {
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
	},
	Enemy = {
		SpawnFolderName = "SpawnPoints",
		ContainerName = "EnemyContainer",
		TemplateFolderName = "EnemyTemplates",
		NonHumanoidLifetimeSeconds = 25,
		NonHumanoidMaxHealth = 120,
		BaseBounty = 25,
		BountyPerWave = 4,
		SpawnPaddingY = 0.1,
		DefaultProfile = EnemyProfiles.DefaultProfile,
		TemplateProfiles = EnemyProfiles.TemplateProfiles,
	},
	Difficulty = {
		Default = "Normal",
		Settings = {
			Easy = {
				EnemyHealthMultiplier = 0.8,
				EnemyDamageMultiplier = 0.9,
			},
			Normal = {
				EnemyHealthMultiplier = 1.0,
				EnemyDamageMultiplier = 1.0,
			},
			Hard = {
				EnemyHealthMultiplier = 1.35,
				EnemyDamageMultiplier = 1.2,
			},
		},
	},
	Remotes = RemoteNames,
	Player = {
		StartingMoney = 5000,
		DisableHealthRegen = true,
		RespawnDelaySeconds = 60,
		OutOfWaveMoveSpeedMultiplier = 2.0,
		SprintSpeedMultiplier = 2.2,
		SprintStaminaMax = 100,
		SprintStaminaDrainPerSecond = 35,
		SprintStaminaRegenPerSecond = 10,
		SprintStaminaRegenDelaySeconds = 0.45,
		SprintStaminaMinToSprint = 15,
	},
	ClassSystem = {
		MaxLevel = 200,
		DefaultClassId = "berserker",
		DamageToXpScale = 1,
		XpRequirementMultiplier = 30,
		ProgressionCurve = {
			LevelBandSize = 10,
			DecadeStepMultiplier = 1.2,
			EarlyLevelsFastUntil = 20,
			EarlyLevelsMultiplier = 0.7,
			-- With DamageToXpScale = 1 and ~550k damage XP/hour, this lands near level 200 in ~100 hours.
		},
		SwitchAllowedStates = {
			Preparing = true,
			Cleared = true,
			Blocked = true,
		},
		Classes = ClassCatalog,
	},
	Shop = ShopConfig,
}

return Config
