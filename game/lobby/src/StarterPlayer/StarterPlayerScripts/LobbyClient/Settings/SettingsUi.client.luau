local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local SettingsHudLayoutConfig = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsHudLayoutConfig"))
local SettingsMenuController = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsMenuController"))

SettingsMenuController.run({
	hudMoveModeAttribute = SettingsHudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE,
	canReturnToLobby = false,
})
