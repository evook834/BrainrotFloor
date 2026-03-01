local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local SharedClient = StarterPlayer.StarterPlayerScripts.SharedClient
local SettingsConfig = require(ReplicatedStorage.Shared.Settings.SettingsConfig)
local SettingsMenuController = require(SharedClient.Settings.SettingsMenuController)

SettingsMenuController.run({
	hudMoveModeAttribute = SettingsConfig.HudMoveMode.Attribute,
	canReturnToLobby = false,
})
