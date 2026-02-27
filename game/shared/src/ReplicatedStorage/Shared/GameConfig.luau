local ClassSystemConfig = require(script.Parent:WaitForChild("Classes"):WaitForChild("ClassSystemConfig"))
local AmmoPickupConfig = require(script.Parent:WaitForChild("Pickups"):WaitForChild("AmmoPickupConfig"))
local EnemyConfig = require(script.Parent:WaitForChild("Enemy"):WaitForChild("EnemyConfig"))
local PlayerConfig = require(script.Parent:WaitForChild("Player"):WaitForChild("PlayerConfig"))
local RemoteNames = require(script.Parent:WaitForChild("Remotes"):WaitForChild("RemoteNames"))
local ShopConfig = require(script.Parent:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local WaveConfig = require(script.Parent:WaitForChild("Waves"):WaitForChild("WaveConfig"))
local SpectatorConfig = {
	CameraOffset = Vector3.new(0, 2, 8),
	Smoothness = 0.15,
	MinDistance = 5,
	MaxDistance = 15,
}

local Config = {
	Wave = WaveConfig,
	Enemy = EnemyConfig,
	Difficulty = {
		Default = "Normal",
		Settings = {
			Easy = {
				EnemyHealthMultiplier = 0.8,
				EnemyDamageMultiplier = 0.9,
				EnemyCountMultiplier = 0.9,
				DiffTotal = 0.85,
				DiffAlive = 0.90,
			},
			Normal = {
				EnemyHealthMultiplier = 1.0,
				EnemyDamageMultiplier = 1.0,
				EnemyCountMultiplier = 1.0,
				DiffTotal = 1.0,
				DiffAlive = 1.0,
			},
			Hard = {
				EnemyHealthMultiplier = 1.35,
				EnemyDamageMultiplier = 1.2,
				EnemyCountMultiplier = 1.15,
				DiffTotal = 1.25,
				DiffAlive = 1.15,
			},
			-- Nightmare (future): DiffTotal = 1.5, DiffAlive = 1.25
		},
	},
	Remotes = RemoteNames,
	Player = PlayerConfig,
	ClassSystem = ClassSystemConfig,
	Shop = ShopConfig,
	AmmoPickup = AmmoPickupConfig,
	Spectator = SpectatorConfig,
}

return Config
