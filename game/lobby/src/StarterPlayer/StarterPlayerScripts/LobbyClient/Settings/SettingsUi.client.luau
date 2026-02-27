local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local SettingsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("SettingsConfig"))
local SettingsMenuController = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsMenuController"))

SettingsMenuController.run({
	hudMoveModeAttribute = SettingsConfig.HudMoveMode.Attribute,
	canReturnToLobby = false,
})
