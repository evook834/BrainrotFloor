--[[
	XpBarHud entry: builds UI (XpBarHudView) and runs logic (XpBarHudController).
	Controller.run(playerGui): ClassGetData/ClassState, spectator visibility, HUD move mode, scale.
]]
local Players = game:GetService("Players")
local XpBarHudController = require(script.Parent.XpBarHudController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
XpBarHudController.run(playerGui)
