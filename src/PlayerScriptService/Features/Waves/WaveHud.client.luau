--[[
	Wave HUD entry: builds UI (WaveHudView) and runs logic (WaveHudController).
	Controller.run(playerGui): WaveState remote, attributes, HP/money/enemies, game over, map vote, return to lobby.
]]
local Players = game:GetService("Players")
local WaveHudController = require(script.Parent.WaveHudController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
WaveHudController.run(playerGui)
