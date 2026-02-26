--[[ Lobby settings UI — thin launcher for shared SettingsUi. ]]
local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local SettingsUi = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsUi"))
SettingsUi.run({ hudMoveModeAttribute = "LobbyHudMoveModeEnabled" })

--[[ Lobby settings UI — thin launcher for shared SettingsUi. ]]
local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local SettingsUi = require(SharedClient:WaitForChild("Settings"):WaitForChild("SettingsUi"))

SettingsUi.run({
	hudMoveModeAttribute = "LobbyHudMoveModeEnabled",
	canReturnToLobby = false,
})