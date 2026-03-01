--[[
	GameStateMachine — Central state system for Brainrot Floor UI management.

	This module defines a state machine that manages:
	- Game states (Menu, Lobby, InGame, Wave, Shop, GameOver, etc.)
	- UI visibility based on state transitions
	- Script activation/deactivation per state
	- State change events for cross-system communication

	Usage:
		local GameState = require(ReplicatedStorage.ui.UIController.GameStateMachine)
		local state = GameState.new()

		state:setState("Lobby")
		state:onStateChange():Connect(function(newState, oldState)
			print("Changed from", oldState, "to", newState)
		end)
]]

-- State definitions
type GameState = {
	name: string,
	enter: (state: GameState) -> (),
	exit: (state: GameState) -> (),
	allowedTransitions: { string },
}

type StateMachine = {
	new: () -> StateMachine,
	setState: (self: StateMachine, newStateName: string) -> boolean,
	getState: (self: StateMachine) -> string,
	getStateObject: (self: StateMachine) -> GameState?,
	onStateChange: (self: StateMachine) -> RBXScriptSignal,
	allowTransition: (self: StateMachine, fromState: string, toState: string) -> (),
}

-- Define valid states and their behavior
local STATE_DEFINITIONS = {
	Menu = {
		name = "Menu",
		allowedTransitions = { "Lobby", "Settings" },
	},
	Lobby = {
		name = "Lobby",
		allowedTransitions = { "Menu", "Matchmaking", "Settings", "Classes" },
	},
	Matchmaking = {
		name = "Matchmaking",
		allowedTransitions = { "Lobby", "InGame" },
	},
	InGame = {
		name = "InGame",
		allowedTransitions = { "Matchmaking", "Shop", "Settings", "GameOver" },
	},
	Wave = {
		name = "Wave",
		allowedTransitions = { "InGame", "Intermission" },
	},
	Intermission = {
		name = "Intermission",
		allowedTransitions = { "Wave", "Shop" },
	},
	Shop = {
		name = "Shop",
		allowedTransitions = { "InGame", "Wave" },
	},
	GameOver = {
		name = "GameOver",
		allowedTransitions = { "InGame", "Lobby" },
	},
	Settings = {
		name = "Settings",
		allowedTransitions = { "Menu", "Lobby", "InGame" },
	},
	Classes = {
		name = "Classes",
		allowedTransitions = { "Lobby", "Settings" },
	},
}

local GameState = {}
GameState.__index = GameState

function GameState.new(): StateMachine
	local self = setmetatable({
		_currentState = nil,
		_stateObject = nil,
		_stateChangeSignal = Instance.new("BindableEvent"),
		_allowList = {},
	}, GameState)

	-- Initialize allow list from definitions
	for stateName, def in pairs(STATE_DEFINITIONS) do
		self._allowList[stateName] = {}
		for _, allowed in ipairs(def.allowedTransitions) do
			self._allowList[stateName][allowed] = true
		end
	end

	return self
end

function GameState:setState(newStateName: string): boolean
	local currentStateName = self._currentState

	-- Check if state exists
	local newState = STATE_DEFINITIONS[newStateName]
	if not newState then
		warn(("GameState: Unknown state '%s'"):format(newStateName))
		return false
	end

	-- Check if transition is allowed
	local allowedFrom = currentStateName and self._allowList[currentStateName]
	if currentStateName and not (allowedFrom and allowedFrom[newStateName]) then
		warn((
			"GameState: Transition '%s' -> '%s' not allowed. Allowed: %s"
		):format(
			currentStateName or "nil",
			newStateName,
			table.concat(self._allowList[currentStateName] and table.keys(self._allowList[currentStateName]) or {}, ", ")
		))
		return false
	end

	-- Exit old state
	if self._stateObject and type(self._stateObject.exit) == "function" then
		self._stateObject.exit(self._stateObject)
	end

	-- Update state
	self._currentState = newStateName
	self._stateObject = newState

	-- Enter new state
	if type(newState.enter) == "function" then
		newState.enter(newState)
	end

	-- Fire state change event
	self._stateChangeSignal:Fire(newStateName, currentStateName)

	return true
end

function GameState:getState(): string
	return self._currentState or "nil"
end

function GameState:getStateObject(): GameState?
	return self._stateObject
end

function GameState:onStateChange(): RBXScriptSignal
	return self._stateChangeSignal.Event
end

function GameState:allowTransition(fromState: string, toState: string)
	if not self._allowList[fromState] then
		self._allowList[fromState] = {}
	end
	self._allowList[fromState][toState] = true
end

-- Export
return GameState
