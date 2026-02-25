local ClassSystemConfig = require(script.Parent:WaitForChild("Classes"):WaitForChild("ClassSystemConfig"))
local AmmoPickupConfig = require(script.Parent:WaitForChild("Pickups"):WaitForChild("AmmoPickupConfig"))
local EnemyConfig = require(script.Parent:WaitForChild("Enemy"):WaitForChild("EnemyConfig"))
local PlayerConfig = require(script.Parent:WaitForChild("Player"):WaitForChild("PlayerConfig"))
local RemoteNames = require(script.Parent:WaitForChild("Remotes"):WaitForChild("RemoteNames"))
local ShopConfig = require(script.Parent:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local WaveConfig = require(script.Parent:WaitForChild("Waves"):WaitForChild("WaveConfig"))

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
	AmmoPickup = AmmoPickupConfig,
}

return Config
