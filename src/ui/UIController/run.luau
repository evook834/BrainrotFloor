--[[
	UIController Entry Point

	Wires together the State System and UI management.
	Run this on the client to start the UI system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import UI system
local UI = require(ReplicatedStorage.Shared.ui)
local GameState = UI.UIController.GameStateMachine
local UIManager = UI.UIController.UIManager

-- Import client feature modules
local PlayerScriptService = ReplicatedStorage.Shared.PlayerScriptService
local Features = PlayerScriptService.Features

-- Import shared client modules
local SharedClient = PlayerScriptService.SharedClient

type RunOptions = {
	hudMoveModeAttribute: string?,
	canReturnToLobby: boolean?,
}

local function run(options: RunOptions?)
	local player = Players.LocalPlayer
	if not player or not player:IsA("Player") then
		warn("UIController.run: LocalPlayer not found")
		return
	end

	-- Create state machine
	local gameState = GameState.new()

	-- Create UI manager
	local uiManager = UIManager.new(gameState)

	-- Register UI components with their state associations
	-- States: Menu, Lobby, Matchmaking, InGame, Wave, Intermission, Shop, GameOver, Settings, Classes

	-- Shop UI - available when in game or in shop state
	uiManager:register("Shop", {
		ui = UI.Shop.ShopView,
		controller = Features.Shop.ShopUiController,
		states = { "InGame", "Shop" },
		options = options,
	})

	-- Class UI - only in Lobby
	uiManager:register("Classes", {
		ui = SharedClient.Classes.ClassUiView,
		controller = SharedClient.Classes.ClassUi,
		states = { "Lobby" },
	})

	-- Crosshair - only in InGame state
	uiManager:register("Crosshair", {
		ui = Features.Combat.Crosshair.CrosshairView,
		controller = Features.Combat.Crosshair.CrosshairController,
		states = { "InGame" },
	})

	-- Ammo HUD - only in InGame state
	uiManager:register("AmmoHud", {
		ui = Features.Combat.AmmoHud.AmmoHudView,
		controller = Features.Combat.AmmoHud.AmmoHudController,
		states = { "InGame" },
	})

	-- Wave HUD - shows during waves and intermission
	uiManager:register("WaveHud", {
		ui = Features.Waves.WaveHudView,
		controller = Features.Waves.WaveHudController,
		states = { "Wave", "Intermission", "GameOver" },
	})

	-- XpBar HUD - shows in Lobby and InGame
	uiManager:register("XpBarHud", {
		ui = Features.Classes.XpBarHud.XpBarHudView,
		controller = Features.Classes.XpBarHud.XpBarHudController,
		states = { "Lobby", "InGame" },
	})

	-- Settings UI - available from Menu, Lobby, InGame
	uiManager:register("Settings", {
		ui = SharedClient.Settings.SettingsMenuUi,
		controller = SharedClient.Settings.SettingsMenuController,
		states = { "Menu", "Lobby", "InGame" },
		options = options,
	})

	-- Start managing UI
	uiManager:start()

	-- Set initial state
	gameState:setState("Menu")

	return {
		gameState = gameState,
		uiManager = uiManager,
	}
end

return {
	run = run,
}
