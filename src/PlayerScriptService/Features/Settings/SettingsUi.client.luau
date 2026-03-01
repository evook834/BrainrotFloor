local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local SettingsConfig = require(ReplicatedStorage.Shared.Settings.SettingsConfig)
local SettingsMenuController = require(StarterPlayer.StarterPlayerScripts.SharedClient.Settings.SettingsMenuController)

SettingsMenuController.run({
	hudMoveModeAttribute = SettingsConfig.HudMoveMode.Attribute,
	canReturnToLobby = true,
})