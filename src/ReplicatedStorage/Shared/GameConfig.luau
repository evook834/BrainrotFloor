local Config = {
	Wave = {
		IntermissionSeconds = 10,
		BaseEnemyCount = 6,
		EnemiesPerWave = 2,
		SpawnBatchDelay = 0.5,
	},
	Enemy = {
		SpawnFolderName = "SpawnPoints",
		ContainerName = "EnemyContainer",
		TemplateFolderName = "EnemyTemplates",
	},
	Remotes = {
		Folder = "Remotes",
		WaveState = "WaveState",
	},
}

return Config
