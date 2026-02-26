local EnemyProfiles = require(script.Parent:WaitForChild("EnemyProfiles"))
local EnemyCatalog = require(script.Parent:WaitForChild("EnemyCatalog"))

local EnemyConfig = {
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
	Catalog = EnemyCatalog,
}

return EnemyConfig
