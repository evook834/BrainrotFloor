--[[
	Client entry script. Runs on startup and starts the UI system (UIController).
	Uses PlaceConfig to set canReturnToLobby based on current place (lobby vs match).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local ClientEntry = require(script.Parent.ClientEntry)

ClientEntry.run({
	hudMoveModeAttribute = "HudMoveMode",
	canReturnToLobby = (game.PlaceId ~= PlaceConfig.LOBBY_PLACE_ID),
})
