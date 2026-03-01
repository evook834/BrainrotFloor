local ClassSystemConfig = require(script.Parent:WaitForChild("Classes"):WaitForChild("ClassSystemConfig"))
local AmmoPickupConfig = require(script.Parent:WaitForChild("Pickups"):WaitForChild("AmmoPickupConfig"))
local DifficultyConfig = require(script.Parent:WaitForChild("DifficultyConfig"))
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
	Difficulty = DifficultyConfig,
	Remotes = RemoteNames,
	Player = PlayerConfig,
	ClassSystem = ClassSystemConfig,
	Shop = ShopConfig,
	AmmoPickup = AmmoPickupConfig,
	Spectator = SpectatorConfig,
}

return Config
