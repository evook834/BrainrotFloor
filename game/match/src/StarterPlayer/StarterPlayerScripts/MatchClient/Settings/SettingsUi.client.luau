local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local SettingsMenuController = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsMenuController"))

SettingsMenuController.run({
	hudMoveModeAttribute = "LobbyHudMoveModeEnabled",
	canReturnToLobby = true,
})