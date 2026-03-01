local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsRemotesUtil = require(script.Parent:WaitForChild("SettingsRemotesUtil"))
local SettingsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("SettingsConfig"))
local HudLayoutConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("HudLayoutConfig"))
local HudLayoutService = require(script.Parent:WaitForChild("SettingsHudLayoutService"))
local HudMoveModeInput = require(script.Parent:WaitForChild("HudMoveModeInput"))
local SettingsPayloadBuilder = require(script.Parent:WaitForChild("SettingsPayloadBuilder"))
local SettingsTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("SettingsTypes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD_MOVABLE_ATTRIBUTE = "HudMovable"

type SettingsState = SettingsTypes.SettingsState
type RunOptions = SettingsTypes.RunOptions

type View = {
	gui: ScreenGui,
	panel: Frame,
	moveModeButton: TextButton,
	moveStatusLabel: TextLabel,
	selectedHudLabel: TextLabel,
	resetPositionButton: TextButton,
	hudScaleLabel: TextLabel,
	hudScaleDownButton: TextButton,
	hudScaleUpButton: TextButton,
	resetScaleButton: TextButton,
}

type RootState = {
	rawPosition: UDim2,
	defaultPosition: UDim2,
	scaleObject: UIScale?,
	useAttributeScale: boolean,
	applying: boolean,
	screenGuiName: string,
	persistKey: string,
	canDrag: boolean,
	connections: { RBXScriptConnection },
}

type ScreenGuiState = {
	connections: { RBXScriptConnection },
}

type DragState = {
	root: GuiObject,
	startMouse: Vector2,
	startRawPosition: UDim2,
}

type PendingTouch = {
	input: InputObject,
}

type InitOptions = {
	view: View,
	options: RunOptions?,
	settingsState: SettingsState,
}

type Controller = {
	view: View,
	settingsState: SettingsState,
	connections: { RBXScriptConnection },
	trackedScreenGuis: { [ScreenGui]: ScreenGuiState },
	trackedHudRoots: { [GuiObject]: RootState },
	settingsSaveRemote: RemoteEvent?,
	settingsSaveToken: number,
	moveModeEnabled: boolean,
	selectedHudRoot: GuiObject?,
	activeDrag: DragState?,
	hudMoveModeAttribute: string?,
	highlightStroke: UIStroke?,
	pendingTouch: PendingTouch?,
	statusOverrideText: string?,
}

local SettingsHudLayoutController = {}
SettingsHudLayoutController.__index = SettingsHudLayoutController

local HIGHLIGHT_STROKE_NAME = "HudMoveHighlightStroke"

function SettingsHudLayoutController:serializePosition(position: UDim2)
	return HudLayoutService.serializePosition(position)
end

function SettingsHudLayoutController:deserializePosition(rawPosition: any): UDim2?
	return HudLayoutService.deserializePosition(rawPosition)
end

function SettingsHudLayoutController:queueSettingsSave()
	if not self.settingsSaveRemote then
		return
	end

	self.settingsSaveToken += 1
	local activeToken = self.settingsSaveToken
	task.delay(SettingsConfig.SaveDebounceDelay, function()
		if activeToken ~= self.settingsSaveToken then
			return
		end

		for root, rootState in pairs(self.trackedHudRoots) do
			local currentPosition = self.settingsState.hudPositions[rootState.persistKey]
			if typeof(currentPosition) == "UDim2" then
				self.settingsState.hudPositions[rootState.persistKey] =
					HudLayoutService.clampRootPosition(currentPosition, root)
			end
		end

		local serializedPositions: { [string]: SettingsPayloadBuilder.SerializedPosition } = {}
		for key, position in pairs(self.settingsState.hudPositions) do
			if typeof(position) == "UDim2" then
				serializedPositions[key] = self:serializePosition(position)
			end
		end
		self.settingsSaveRemote:FireServer(SettingsPayloadBuilder.buildSavePayload(self.settingsState, serializedPositions))
	end)
end

function SettingsHudLayoutController:setHighlightedRoot(root: GuiObject?)
	if not root then
		if self.highlightStroke then
			self.highlightStroke:Destroy()
			self.highlightStroke = nil
		end
		return
	end

	local stroke = self.highlightStroke
	if stroke and stroke.Parent ~= root then
		stroke.Parent = root
		return
	end

	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = HIGHLIGHT_STROKE_NAME
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		self.highlightStroke = stroke
	end

	local isSelected = root == self.selectedHudRoot
	if isSelected then
		stroke.Color = Color3.fromRGB(255, 255, 127)
		stroke.Thickness = 3
		stroke.Transparency = 0
	else
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Transparency = 0.2
	end

	stroke.Parent = root
end

function SettingsHudLayoutController:applyHudRootTransform(root: GuiObject, rootState: RootState)
	HudLayoutService.applyHudRootTransform(root, rootState, self.settingsState)
end

function SettingsHudLayoutController:applyHudTransforms()
	HudLayoutService.applyHudTransforms(self.trackedHudRoots, self.settingsState)
end

function SettingsHudLayoutController:setRootPosition(root: GuiObject, rootState: RootState, rawPosition: UDim2, shouldPersist: boolean?)
	local clamped = HudLayoutService.clampRootPosition(rawPosition, root)
	rootState.rawPosition = clamped
	if shouldPersist ~= false then
		self.settingsState.hudPositions[rootState.persistKey] = clamped
	end
	self:applyHudRootTransform(root, rootState)
end

function SettingsHudLayoutController:resetRootToDefault(root: GuiObject, rootState: RootState)
	rootState.rawPosition = rootState.defaultPosition
	self.settingsState.hudPositions[rootState.persistKey] = nil
	self:applyHudRootTransform(root, rootState)
end

function SettingsHudLayoutController:destroyHudRoot(root: GuiObject, rootState: RootState)
	if self.selectedHudRoot == root then
		self.selectedHudRoot = nil
	end
	if self.activeDrag and self.activeDrag.root == root then
		self.activeDrag = nil
	end
	if self.highlightStroke and self.highlightStroke.Parent == root then
		self.highlightStroke.Parent = nil
	end

	for _, connection in ipairs(rootState.connections) do
		connection:Disconnect()
	end
	self.trackedHudRoots[root] = nil
	self:updateGameplayLabels()
end

function SettingsHudLayoutController:destroyScreenGui(screenGui: ScreenGui, screenState: ScreenGuiState)
	for _, connection in ipairs(screenState.connections) do
		connection:Disconnect()
	end
	self.trackedScreenGuis[screenGui] = nil
end

function SettingsHudLayoutController:trackHudRoot(root: GuiObject)
	if self.trackedHudRoots[root] then
		return
	end

	local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
	local rootKey = string.format("%s/%s", screenGui and screenGui.Name or "", root.Name)
	local specialConfig = SettingsConfig.SpecialHudRoots[rootKey]
	local useAttributeScale = specialConfig and specialConfig.UseAttributeScale == true

	local existingScale = root:FindFirstChild("GlobalHudScale")
	local scaleObject = nil
	if not useAttributeScale then
		if existingScale and existingScale:IsA("UIScale") then
			scaleObject = existingScale
		else
			scaleObject = Instance.new("UIScale")
			scaleObject.Name = "GlobalHudScale"
			scaleObject.Scale = 1
			scaleObject.Parent = root
		end
	end

	local rootState: RootState = {
		rawPosition = root.Position,
		defaultPosition = root.Position,
		scaleObject = scaleObject,
		useAttributeScale = useAttributeScale,
		applying = false,
		screenGuiName = "",
		persistKey = "",
		canDrag = true,
		connections = {},
	}

	if screenGui then
		rootState.screenGuiName = screenGui.Name
	end
	rootState.persistKey = string.format("%s/%s", rootState.screenGuiName, root.Name)
	if SettingsConfig.NonDraggableHudRoots[rootState.persistKey] or root:GetAttribute(HUD_MOVABLE_ATTRIBUTE) == false then
		rootState.canDrag = false
	end

	local savedPosition = self.settingsState.hudPositions[rootState.persistKey]
	if typeof(savedPosition) == "UDim2" then
		self:setRootPosition(root, rootState, savedPosition)
	end

	self.trackedHudRoots[root] = rootState

	table.insert(rootState.connections, root:GetPropertyChangedSignal("Position"):Connect(function()
		if rootState.applying then
			return
		end
		self:setRootPosition(root, rootState, root.Position)
	end))

	table.insert(rootState.connections, root.AncestryChanged:Connect(function(_, parent)
		if parent and root:IsDescendantOf(playerGui) then
			return
		end
		self:destroyHudRoot(root, rootState)
	end))

	self:applyHudRootTransform(root, rootState)
end

function SettingsHudLayoutController:trackScreenGui(screenGui: ScreenGui)
	if self.trackedScreenGuis[screenGui] then
		return
	end

	local screenState: ScreenGuiState = {
		connections = {},
	}
	self.trackedScreenGuis[screenGui] = screenState

	for _, child in ipairs(screenGui:GetChildren()) do
		if HudLayoutConfig.isHudRoot(self.view.gui, child) then
			self:trackHudRoot(child)
		end
	end

	table.insert(screenState.connections, screenGui.ChildAdded:Connect(function(child)
		if HudLayoutConfig.isHudRoot(self.view.gui, child) then
			self:trackHudRoot(child)
		end
	end))

	table.insert(screenState.connections, screenGui.AncestryChanged:Connect(function(_, parent)
		if parent and screenGui:IsDescendantOf(playerGui) then
			return
		end

		self:destroyScreenGui(screenGui, screenState)
	end))
end

function SettingsHudLayoutController:getTopHudRootAtPosition(screenPos: Vector2): GuiObject?
	return HudLayoutService.getTopHudRootAtPosition(self.trackedHudRoots, screenPos)
end

function SettingsHudLayoutController:updateDrag(screenPos: Vector2)
	if not self.activeDrag then
		return
	end

	local root = self.activeDrag.root
	local rootState = self.trackedHudRoots[root]
	if not rootState then
		self.activeDrag = nil
		return
	end

	local startRawPosition = self.activeDrag.startRawPosition
	local delta = screenPos - self.activeDrag.startMouse
	local newRawPosition = UDim2.new(
		startRawPosition.X.Scale,
		startRawPosition.X.Offset + math.floor(delta.X + 0.5),
		startRawPosition.Y.Scale,
		startRawPosition.Y.Offset + math.floor(delta.Y + 0.5)
	)
	self:setRootPosition(root, rootState, newRawPosition)
	self:updateGameplayLabels()
end

function SettingsHudLayoutController:startDragAtPosition(screenPos: Vector2)
	local root = self:getTopHudRootAtPosition(screenPos)
	if not root then
		self.selectedHudRoot = nil
		self:setHighlightedRoot(nil)
		self:setStatusOverride("No HUD element at this position.", 1)
		return
	end

	local rootState = self.trackedHudRoots[root]
	if not rootState or not rootState.canDrag then
		return
	end

	self.activeDrag = {
		root = root,
		startMouse = Vector2.new(screenPos.X, screenPos.Y),
		startRawPosition = rootState.rawPosition,
	}
	self.selectedHudRoot = root
	self:updateGameplayLabels()
	self:setHighlightedRoot(root)
end

local function getRootLabel(controller: Controller, root: GuiObject?): string
	if not root then
		return "None"
	end

	local rootState = controller.trackedHudRoots[root]
	if not rootState then
		return "None"
	end
	if rootState.screenGuiName ~= "" then
		return string.format("%s / %s", rootState.screenGuiName, root.Name)
	end
	return root.Name
end

function SettingsHudLayoutController:updateGameplayLabels()
	local scalePercent = math.floor((self.settingsState.hudScale * 100) + 0.5)
	if self.statusOverrideText then
		self.view.moveStatusLabel.Text = self.statusOverrideText
	else
		if self.moveModeEnabled then
			self.view.moveStatusLabel.Text = "Move Mode ON: drag HUD elements to reposition."
		else
			self.view.moveStatusLabel.Text = "Move Mode OFF"
		end
	end

	self.view.selectedHudLabel.Text = "Selected: " .. getRootLabel(self, self.selectedHudRoot)
	self.view.hudScaleLabel.Text = string.format("HUD Size: %d%%", scalePercent)
	self.view.moveModeButton.Text = if self.moveModeEnabled then "HUD Move Mode: ON" else "HUD Move Mode: OFF"
	self.view.resetPositionButton.Active = self.moveModeEnabled and self.selectedHudRoot ~= nil
	self.view.resetPositionButton.AutoButtonColor = self.view.resetPositionButton.Active
	self.view.resetPositionButton.BackgroundTransparency = if self.view.resetPositionButton.Active then 0 else 0.35

	if self.moveModeEnabled then
		self.view.moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 108, 86)
	else
		self.view.moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 86, 120)
	end
end

function SettingsHudLayoutController:setMoveModeEnabled(enabled: boolean)
	self.moveModeEnabled = enabled
	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, self.moveModeEnabled)
	end
	if not self.moveModeEnabled then
		self.activeDrag = nil
		self.pendingTouch = nil
		self:setHighlightedRoot(nil)
	end
	self:updateGameplayLabels()
end

function SettingsHudLayoutController:applyLoadedHudSettings(loadedHud: any)
	if type(loadedHud) ~= "table" then
		return
	end

	local scaleMin = SettingsConfig.Hud.Scale.Min
	local scaleMax = SettingsConfig.Hud.Scale.Max
	self.settingsState.hudScale = math.clamp(tonumber(loadedHud.scale) or self.settingsState.hudScale, scaleMin, scaleMax)
	self.settingsState.hudPositions = {}

	if type(loadedHud.positions) == "table" then
		for key, rawPosition in pairs(loadedHud.positions) do
			if type(key) == "string" then
				local parsedPosition = self:deserializePosition(rawPosition)
				if parsedPosition then
					self.settingsState.hudPositions[key] = parsedPosition
				end
			end
		end
	end

	for root, rootState in pairs(self.trackedHudRoots) do
		local savedPosition = self.settingsState.hudPositions[rootState.persistKey]
		if typeof(savedPosition) == "UDim2" then
			self:setRootPosition(root, rootState, savedPosition)
		end
	end

	self:applyHudTransforms()
	self:updateGameplayLabels()
end

function SettingsHudLayoutController:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	for screenGui, screenState in pairs(self.trackedScreenGuis) do
		self:destroyScreenGui(screenGui, screenState)
	end

	for root, rootState in pairs(self.trackedHudRoots) do
		self:destroyHudRoot(root, rootState)
	end

	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, false)
	end

	if self.highlightStroke then
		self.highlightStroke:Destroy()
		self.highlightStroke = nil
	end
end

function SettingsHudLayoutController:setStatusOverride(text: string?, durationSeconds: number?)
	self.statusOverrideText = text
	self:updateGameplayLabels()

	if text and durationSeconds and durationSeconds > 0 then
		local expectedText = text
		task.delay(durationSeconds, function()
			if self.statusOverrideText ~= expectedText then
				return
			end
			self.statusOverrideText = nil
			self:updateGameplayLabels()
		end)
	end
end

local function isHudScreenGui(viewGui: ScreenGui, instance: Instance): boolean
	return HudLayoutConfig.isHudScreenGui(viewGui, instance)
end

local function ensureDefaults(settingsState: SettingsState)
	HudLayoutService.ensureDefaults(settingsState, SettingsConfig.Hud.Scale.Min, SettingsConfig.Hud.Scale.Max)
end

function SettingsHudLayoutController.new(init: InitOptions): Controller
	local options = init.options or {}

	local self = (setmetatable({
		view = init.view,
		settingsState = init.settingsState,
		connections = {},
		trackedScreenGuis = {},
		trackedHudRoots = {},
		settingsSaveRemote = SettingsRemotesUtil.resolveSettingsSaveRemote(),
		settingsSaveToken = 0,
		moveModeEnabled = false,
		selectedHudRoot = nil,
		activeDrag = nil,
		hudMoveModeAttribute = options.hudMoveModeAttribute,
		highlightStroke = nil,
		pendingTouch = nil,
	}, SettingsHudLayoutController) :: any) :: Controller

	ensureDefaults(self.settingsState)

	for _, child in ipairs(playerGui:GetChildren()) do
		if isHudScreenGui(self.view.gui, child) then
			self:trackScreenGui(child)
		end
	end

	table.insert(self.connections, playerGui.ChildAdded:Connect(function(child)
		if isHudScreenGui(self.view.gui, child) then
			self:trackScreenGui(child)
		end
	end))

	table.insert(self.connections, self.view.moveModeButton.Activated:Connect(function()
		self:setMoveModeEnabled(not self.moveModeEnabled)
	end))

	table.insert(self.connections, self.view.resetPositionButton.Activated:Connect(function()
		if not self.moveModeEnabled then
			return
		end
		if not self.selectedHudRoot then
			return
		end

		local rootState = self.trackedHudRoots[self.selectedHudRoot]
		if not rootState then
			self.selectedHudRoot = nil
			self:updateGameplayLabels()
			return
		end

		self:resetRootToDefault(self.selectedHudRoot, rootState)
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.hudScaleDownButton.Activated:Connect(function()
		self.settingsState.hudScale = math.clamp(self.settingsState.hudScale - SettingsConfig.Hud.Scale.Step, SettingsConfig.Hud.Scale.Min, SettingsConfig.Hud.Scale.Max)
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.hudScaleUpButton.Activated:Connect(function()
		self.settingsState.hudScale = math.clamp(self.settingsState.hudScale + SettingsConfig.Hud.Scale.Step, SettingsConfig.Hud.Scale.Min, SettingsConfig.Hud.Scale.Max)
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.resetScaleButton.Activated:Connect(function()
		self.settingsState.hudScale = SettingsConfig.Hud.Scale.Default
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	HudMoveModeInput.bindMoveModeInput(self, self.connections)

	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, false)
	end
	self:setMoveModeEnabled(false)
	self:applyHudTransforms()
	self:updateGameplayLabels()

	return self
end

return SettingsHudLayoutController
