--[[
	Lobby Client Entry Point

	This is the entry point for the lobby place that uses the new UI State System.
	It bootstraps the centralized GameStateMachine and UIManager.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import UI controller entry point
local UIController = require(ReplicatedStorage.Shared.ui.UIController)

-- Run the UI controller
UIController.run({
	hudMoveModeAttribute = "HudMoveMode",
	canReturnToLobby = false,
})
