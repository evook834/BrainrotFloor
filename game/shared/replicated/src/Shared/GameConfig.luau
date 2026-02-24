local ClassSystemConfig = require(script.Parent:WaitForChild("ClassSystemConfig"))
local EnemyConfig = require(script.Parent:WaitForChild("EnemyConfig"))
local PlayerConfig = require(script.Parent:WaitForChild("PlayerConfig"))
local RemoteNames = require(script.Parent:WaitForChild("RemoteNames"))
local ShopConfig = require(script.Parent:WaitForChild("ShopConfig"))
local WaveConfig = require(script.Parent:WaitForChild("WaveConfig"))

local Config = {
	Wave = WaveConfig,
	Enemy = EnemyConfig,
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
	Player = PlayerConfig,
	ClassSystem = ClassSystemConfig,
	Shop = ShopConfig,
}

return Config
