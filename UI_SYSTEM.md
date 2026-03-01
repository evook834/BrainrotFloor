# UI System — State-based UI management

This document describes the new UI system for Brainrot Floor, using a centralized state machine to manage UI component visibility and activation.

---

## Overview

The UI System uses a **State System** approach where:

1. **GameStateMachine** tracks the current game state (Menu, Lobby, InGame, Shop, etc.)
2. **UIManager** manages UI components, showing/hiding them based on the current state
3. **React Luau** components provide declarative UI building

This replaces the previous pattern of manually showing/hiding UI in each controller.

---

## Architecture

```
src/ui/
├── UI/                # React Luau UI components
│   ├── init.luau      # UI exports
│   └── uitypes.luau   # Shared type definitions
└── UIController/      # State management and UI orchestration
    ├── init.luau
    ├── GameStateMachine.luau   # State machine definition
    ├── UIManager.luau          # UI component manager
    └── run.luau                # Entry point
```

---

## GameStateMachine

The core state machine that:

- Defines valid game states and allowed transitions
- Fires events when state changes
- Tracks the current state

### States

| State | Description | Allowed Transitions |
|-------|-------------|---------------------|
| Menu | Main menu screen | Lobby, Settings |
| Lobby | Player lobby, difficulty selection | Menu, Matchmaking, Settings, Classes |
| Matchmaking | Finding/creating a match | Lobby, InGame |
| InGame | Active gameplay | Matchmaking, Shop, Settings, GameOver |
| Wave | Active wave | InGame, Intermission |
| Intermission | Between waves | Wave, Shop |
| Shop | Weapon/ammo shop | InGame, Wave |
| GameOver | Player died | InGame, Lobby |
| Settings | Settings menu | Menu, Lobby, InGame |
| Classes | Class selection | Lobby, Settings |

### Usage

```lua
local GameState = require(ReplicatedStorage.Shared.ui.UIController.GameStateMachine)

local gameState = GameState.new()

-- Listen for state changes
gameState:onStateChange():Connect(function(newState, oldState)
	print("Changed from", oldState, "to", newState)
end)

-- Set state (returns false if transition not allowed)
gameState:setState("Lobby")
```

---

## UIManager

Manages UI components by:

- Registering components with their associated states
- Automatically showing/hiding based on current state
- Running controller `run()` on show, `destroy()` on hide

### Usage

```lua
local UIManager = require(ReplicatedStorage.Shared.ui.UIController.UIManager)
local GameState = require(ReplicatedStorage.Shared.ui.UIController.GameStateMachine)

local gameState = GameState.new()
local uiManager = UIManager.new(gameState)

-- Register a UI component
uiManager:register("Shop", {
	ui = require(ReplicatedStorage.Shared.ui.Shop.ShopUiView),
	controller = require(ReplicatedStorage.Shared.ui.Shop.ShopUiController),
	states = { "InGame", "Shop" },  -- Show in these states
})

-- Start the manager
uiManager:start()

-- Change state - UIManager will auto-show/hide components
gameState:setState("Shop")  -- Shop UI appears
gameState:setState("InGame")  -- Shop UI hides
```

---

## UI Component Structure

Each registered component should have:

```lua
{
	ui = {
		build = function(parent: PlayerGui): ViewRefs
			-- Build UI tree, return refs
		end,
	},
	controller = {
		run = function(options: RunOptions?)
			-- Start controller logic
		end,
		destroy = function()
			-- Cleanup logic
		end,
	},
	states = { "State1", "State2" },  -- States where UI is shown
	options = { ... },  -- Optional config passed to controller
}
```

---

## React Luau Components

React Luau provides declarative UI building. Components are defined in `src/ui/UI/`.

### Component Example

```lua
local Roact = require("Roact")

local function Button(props)
	return Roact.createElement("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = props.color or Color3.fromRGB(50, 50, 50),
		Text = props.text or "Button",
	}, {
		Label = Roact.createElement("TextLabel", {
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Text = props.text,
		}),
	})
end

return Button
```

---

## Migration from Old UI Pattern

### Before (Manual Show/Hide)

```lua
-- In ShopUiController
local function openShop()
	panel.Visible = true
	refreshCatalog()
end

local function closeShop()
	panel.Visible = false
end

shopOpenRemote.OnClientEvent:Connect(openShop)
```

### After (State-based)

```lua
-- Register with UIManager
uiManager:register("Shop", {
	ui = ShopUiView,
	controller = ShopUiController,
	states = { "InGame", "Shop" },
})

-- No manual show/hide needed - UIManager handles it
```

---

## Entry Points

### New Client Entry (with UI System)

```lua
local ClientEntry = require(ReplicatedStorage.Shared.PlayerScriptService.ClientEntry)
ClientEntry.run()
```

### Old Client Entry (legacy)

```lua
-- Keep for backwards compatibility
local SettingsUi = require(ReplicatedStorage.Shared.PlayerScriptService.SharedClient.Settings.SettingsUi)
SettingsUi.run()
```

---

## Benefits of State-based UI

1. **Centralized Control**: All UI state decisions in one place
2. **Automatic Cleanup**: UIManager handles destroy on state change
3. **Easier Debugging**: Can inspect current state and active UIs
4. **Type Safety**: Type definitions for states and transitions
5. **Flexible**: Easy to add new states or modify transitions

---

## Future Enhancements

- Animation support for state transitions
- UI component pooling for performance
- State persistence across game sessions
- Declarative UI definitions (JSON/YAML)
- Hot-reload support for UI development
