--[[
	Binds input (mouse + touch) for HUD Move mode: drag HUD roots when move mode is on.
	Call bindMoveModeInput(controller, connections) during controller init; it appends
	RBXScriptConnections to the given table.
]]

local UserInputService = game:GetService("UserInputService")

local TOUCH_LONG_PRESS_DELAY = 0.4

export type MoveModeController = {
	view: { panel: Frame },
	moveModeEnabled: boolean,
	pendingTouch: { input: InputObject }?,
	activeDrag: any?,
	selectedHudRoot: GuiObject?,
	startDragAtPosition: (self: any, screenPos: Vector2) -> (),
	updateDrag: (self: any, screenPos: Vector2) -> (),
	setHighlightedRoot: (self: any, root: GuiObject?) -> (),
	getTopHudRootAtPosition: (self: any, screenPos: Vector2) -> GuiObject?,
	queueSettingsSave: (self: any) -> (),
}

local function isPointInPanel(view: { panel: Frame }, screenPos: Vector2): boolean
	if not view.panel.Visible then
		return false
	end
	local panelPos = view.panel.AbsolutePosition
	local panelSize = view.panel.AbsoluteSize
	return screenPos.X >= panelPos.X
		and screenPos.X <= panelPos.X + panelSize.X
		and screenPos.Y >= panelPos.Y
		and screenPos.Y <= panelPos.Y + panelSize.Y
end

local function isMoveModePointer(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function isMoveModePointerOrMovement(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

function bindMoveModeInput(controller: MoveModeController, connections: { RBXScriptConnection })
	table.insert(connections, UserInputService.InputBegan:Connect(function(inputObject, _gameProcessed)
		if not controller.moveModeEnabled then
			return
		end
		if not isMoveModePointer(inputObject.UserInputType) then
			return
		end

		local screenPos = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		if isPointInPanel(controller.view, screenPos) then
			return
		end

		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			controller:startDragAtPosition(screenPos)
			return
		end

		-- Touch: start drag only after long-press to avoid conflicting with tap
		controller.pendingTouch = { input = inputObject }
		local pendingTouch = controller.pendingTouch
		task.delay(TOUCH_LONG_PRESS_DELAY, function()
			if controller.pendingTouch ~= pendingTouch then
				return
			end
			if not controller.moveModeEnabled then
				return
			end
			local currentInput = pendingTouch.input
			local currentPos = Vector2.new(currentInput.Position.X, currentInput.Position.Y)
			if isPointInPanel(controller.view, currentPos) then
				return
			end
			controller.pendingTouch = nil
			controller:startDragAtPosition(currentPos)
		end)
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(inputObject)
		if not controller.moveModeEnabled then
			return
		end
		if not isMoveModePointerOrMovement(inputObject.UserInputType) then
			return
		end

		local screenPos = Vector2.new(inputObject.Position.X, inputObject.Position.Y)

		if controller.activeDrag then
			controller:updateDrag(screenPos)
			return
		end

		if isPointInPanel(controller.view, screenPos) then
			controller:setHighlightedRoot(controller.selectedHudRoot)
			return
		end

		local hoverRoot = controller:getTopHudRootAtPosition(screenPos)
		controller:setHighlightedRoot(hoverRoot or controller.selectedHudRoot)
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(inputObject)
		if not isMoveModePointer(inputObject.UserInputType) then
			return
		end
		if controller.pendingTouch and controller.pendingTouch.input == inputObject then
			controller.pendingTouch = nil
		end
		if controller.activeDrag then
			controller:queueSettingsSave()
		end
		controller.activeDrag = nil
	end))
end

return {
	bindMoveModeInput = bindMoveModeInput,
}
