local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.Settings.SettingsConfig)
local SettingsMenuController = require(script.Parent.Parent.Parent:WaitForChild("SharedClient"):WaitForChild("Settings"):WaitForChild("SettingsMenuController"))

SettingsMenuController.run({
	hudMoveModeAttribute = SettingsConfig.HudMoveMode.Attribute,
	canReturnToLobby = true,
})