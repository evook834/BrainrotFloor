--[[
	UIManager — Manages UI component lifecycle and visibility based on GameState.

	This module works with GameStateMachine to show/hide UI components
	based on the current game state. Each UI component has:
	- A state tag (which state(s) it belongs to)
	- Show/Hide methods
	- Optional initialization options

	Usage:
		local UIManager = require(ReplicatedStorage.ui.UIController.UIManager)
		local gameState = require(ReplicatedStorage.ui.UIController.GameStateMachine).new()

		local uiManager = UIManager.new(gameState)

		-- Register UI components
		uiManager:register("Shop", {
			ui = ShopUiView.build(),
			controller = ShopUiController,
			states = { "InGame", "Shop" },
		})

		uiManager:register("Crosshair", {
			ui = CrosshairView.build(),
			controller = CrosshairController,
			states = { "InGame" },
		})

		-- Start managing UI
		uiManager:start()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type UIComponent = {
	ui: any,
	controller: {
		run: (options: any) -> (),
		destroy: (() -> ())?,
	},
	states: { string },
	options: any?,
}

type UIManager = {
	new: (gameState: any) -> UIManager,
	register: (self: UIManager, name: string, component: UIComponent) -> (),
	unregister: (self: UIManager, name: string) -> (),
	start: (self: UIManager) -> (),
	destroy: (self: UIManager) -> (),
	getActiveUI: (self: UIManager) -> { string },
}

type UIManagerInternal = {
	_gameState: any,
	_components: { [string]: UIComponent & { active: boolean, connections: { RBXScriptConnection } } },
	_activeUI: { string },
	_player: Player?,
	_playerGui: PlayerGui?,
}

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new(gameState: any): UIManager
	local self = setmetatable({
		_gameState = gameState,
		_components = {},
		_activeUI = {},
		_player = Players.LocalPlayer,
		_playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"),
	}, UIManager)

	-- Listen for state changes
	local connection = gameState:onStateChange():Connect(function(newStateName, _oldStateName)
		self:_handleStateChange(newStateName)
	end)
	table.insert(self._components, {
		-- Internal "connection tracker" component
		name = "__stateListener__",
		connections = { connection },
	})

	return self
end

function UIManager:register(name: string, component: UIComponent)
	if self._components[name] then
		warn(("UIManager: Component '%s' already registered"):format(name))
		return false
	end

	-- Verify required fields
	if not component.ui then
		warn(("UIManager: Component '%s' missing 'ui' field"):format(name))
		return false
	end

	if not component.controller or not component.controller.run then
		warn(("UIManager: Component '%s' missing valid 'controller.run'"):format(name))
		return false
	end

	-- Verify states is a table
	if type(component.states) ~= "table" then
		warn(("UIManager: Component '%s' states must be a table"):format(name))
		return false
	end

	self._components[name] = {
		ui = component.ui,
		controller = component.controller,
		states = component.states,
		options = component.options or {},
		active = false,
		connections = {},
	}

	return true
end

function UIManager:unregister(name: string)
	local component = self._components[name]
	if not component then
		return false
	end

	-- Destroy active component
	if component.active then
		self:_destroyComponent(name, component)
	end

	-- Remove connections
	for _, conn in ipairs(component.connections) do
		conn:Disconnect()
	end

	self._components[name] = nil
	return true
end

function UIManager:start()
	-- Initial state sync
	local initialState = self._gameState:getState()
	if initialState ~= "nil" then
		self:_handleStateChange(initialState)
	end
end

function UIManager:destroy()
	for name, component in pairs(self._components) do
		if name ~= "__stateListener__" and type(name) == "string" then
			if component.active then
				self:_destroyComponent(name, component)
			end
			for _, conn in ipairs(component.connections) do
				conn:Disconnect()
			end
		end
	end
	self._components = {}
	self._activeUI = {}
end

function UIManager:_handleStateChange(newState: string)
	local componentsToActivate = {}
	local componentsToDeactivate = {}

	-- Find components that need state changes
	for name, component in pairs(self._components) do
		if name == "__stateListener__" or type(name) == "number" or not component.states then
			continue
		end

		local shouldBeActive = self:_stateMatches(component.states, newState)

		if shouldBeActive and not component.active then
			table.insert(componentsToActivate, { name = name, component = component })
		elseif not shouldBeActive and component.active then
			table.insert(componentsToDeactivate, { name = name, component = component })
		end
	end

	-- Deactivate first (in reverse order for proper cleanup)
	for _, item in ipairs(componentsToDeactivate) do
		self:_destroyComponent(item.name, item.component)
	end

	-- Activate new components
	for _, item in ipairs(componentsToActivate) do
		self:_activateComponent(item.name, item.component)
	end
end

function UIManager:_stateMatches(states: { string }, stateName: string): boolean
	for _, state in ipairs(states) do
		if state == stateName then
			return true
		end
	end
	return false
end

function UIManager:_activateComponent(name: string, component: UIComponent)
	if component.active then
		return
	end

	-- Build UI tree if not already done
	if component.ui.build and component._uiRoot == nil then
		if self._playerGui then
			component._uiRoot = component.ui.build(self._playerGui)
		else
			warn(("UIManager: Cannot build '%s' - PlayerGui not found"):format(name))
			return
		end
	end

	-- Run controller
	local success, err = pcall(function()
		component.controller.run(component.options)
	end)

	if not success then
		warn(("UIManager: Failed to run controller for '%s': %s"):format(name, err))
		return
	end

	component.active = true
	table.insert(self._activeUI, name)
end

function UIManager:_destroyComponent(name: string, component: UIComponent)
	if not component.active then
		return
	end

	-- Call destroy on controller
	if type(component.controller.destroy) == "function" then
		pcall(function()
			component.controller.destroy()
		end)
	end

	-- Clean up UI root
	if component._uiRoot then
		pcall(function()
			component._uiRoot:Destroy()
		end)
		component._uiRoot = nil
	end

	component.active = false

	-- Remove from active list
	for i, uiName in ipairs(self._activeUI) do
		if uiName == name then
			table.remove(self._activeUI, i)
			break
		end
	end
end

function UIManager:getActiveUI(): { string }
	return self._activeUI
end

return UIManager
