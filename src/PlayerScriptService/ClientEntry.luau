--[[
	Client Entry Point - New structure using UI State System

	This is the new client entry point that uses the centralized
	State System and UIManager instead of manual script management.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import UI system entry point
local UIController = require(ReplicatedStorage.Shared.ui.UIController)

type RunOptions = {
	hudMoveModeAttribute: string?,
	canReturnToLobby: boolean?,
}

local function run(options: RunOptions?)
	-- Use the centralized UI controller
	return UIController.run(options)
end

return {
	run = run,
}
