--[[
	UIController Entry Point

	Wires together the State System and UI management.
	Run this on the client to start the UI system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

-- Import UI system (require submodules directly to avoid circular require with ui init)
local GameState = require(ReplicatedStorage.ui.UIController.GameStateMachine)
local UIManager = require(ReplicatedStorage.ui.UIController.UIManager)
local UI = require(ReplicatedStorage.ui.UI)

-- Import client feature modules
local Features = StarterPlayer.StarterPlayerScripts.Features
local ShopUiController = require(Features.Shop.ShopUiController)
local CrosshairController = require(Features.Combat.Crosshair.CrosshairController)
local AmmoHudController = require(Features.Combat.AmmoHud.AmmoHudController)
local WaveHudController = require(Features.Waves.WaveHudController)
local XpBarHudController = require(Features.Classes.XpBarHud.XpBarHudController)

-- Import shared client modules
local SharedClient = StarterPlayer.StarterPlayerScripts.SharedClient
local ClassUi = require(SharedClient.Classes.ClassUi)
local SettingsMenuController = require(SharedClient.Settings.SettingsMenuController)

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
		controller = ShopUiController,
		states = { "InGame", "Shop" },
		options = options,
	})

	-- Class UI - only in Lobby
	uiManager:register("Classes", {
		ui = require(SharedClient.Classes.ClassUiView),
		controller = ClassUi,
		states = { "Lobby" },
	})

	-- Crosshair - only in InGame state
	uiManager:register("Crosshair", {
		ui = require(Features.Combat.Crosshair.CrosshairView),
		controller = CrosshairController,
		states = { "InGame" },
	})

	-- Ammo HUD - only in InGame state
	uiManager:register("AmmoHud", {
		ui = require(Features.Combat.AmmoHud.AmmoHudView),
		controller = AmmoHudController,
		states = { "InGame" },
	})

	-- Wave HUD - shows during waves and intermission
	uiManager:register("WaveHud", {
		ui = require(Features.Waves.WaveHudView),
		controller = WaveHudController,
		states = { "Wave", "Intermission", "GameOver" },
	})

	-- XpBar HUD - shows in Lobby and InGame
	uiManager:register("XpBarHud", {
		ui = require(Features.Classes.XpBarHud.XpBarHudView),
		controller = XpBarHudController,
		states = { "Lobby", "InGame" },
	})

	-- Settings UI - available from Menu, Lobby, InGame
	uiManager:register("Settings", {
		ui = require(SharedClient.Settings.SettingsMenuUi),
		controller = SettingsMenuController,
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
