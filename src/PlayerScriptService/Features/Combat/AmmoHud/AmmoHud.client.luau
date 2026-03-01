--[[
	AmmoHud — Entry for the combat ammo HUD (weapon name, ammo count, details, status).
	Builds UI via AmmoHudView and runs logic via AmmoHudController.
]]

local Players = game:GetService("Players")
local AmmoHudController = require(script.Parent.AmmoHudController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
AmmoHudController.run(playerGui)
