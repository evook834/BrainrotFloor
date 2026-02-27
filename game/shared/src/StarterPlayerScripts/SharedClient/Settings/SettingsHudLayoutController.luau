local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local REMOTE_WAIT_TIMEOUT_SECONDS = 15
local REMOTES_FOLDER_NAME = "Remotes"
local SETTINGS_SAVE_REMOTE_NAME = "SettingsSave"

local HUD_SCREEN_GUI_NAMES = {
	BrainrotHud = true,
	ClassXpBarHud = true,
	SprintStaminaHud = true,
	CombatCrosshairUi = true,
	AmmoHud = true,
}

local NON_DRAGGABLE_HUD_ROOTS = {
	["CombatCrosshairUi/CrosshairRoot"] = true,
	["BrainrotHud/RespawnTimer"] = true,
	["BrainrotHud/GameOverOverlay"] = true,
}

type SettingsState = {
	musicVolume: number,
	musicMuted: boolean,
	sfxVolume: number,
	sfxMuted: boolean,
	hudScale: number,
	hudPositions: { [string]: any },
}

type RunOptions = {
	hudMoveModeAttribute: string?,
}

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
	[string]: any,
}

local function resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	candidate = remotesFolder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT_SECONDS)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

local SettingsHudLayoutController = {}
SettingsHudLayoutController.__index = SettingsHudLayoutController

function SettingsHudLayoutController:serializePosition(position: UDim2)
	if typeof(position) ~= "UDim2" then
		return nil
	end

	return {
		xScale = position.X.Scale,
		xOffset = math.floor(position.X.Offset + 0.5),
		yScale = position.Y.Scale,
		yOffset = math.floor(position.Y.Offset + 0.5),
	}
end

function SettingsHudLayoutController:deserializePosition(rawPosition: any): UDim2?
	if type(rawPosition) ~= "table" then
		return nil
	end

	local xScale = tonumber(rawPosition.xScale)
	local xOffset = tonumber(rawPosition.xOffset)
	local yScale = tonumber(rawPosition.yScale)
	local yOffset = tonumber(rawPosition.yOffset)
	if xScale == nil or xOffset == nil or yScale == nil or yOffset == nil then
		return nil
	end

	return UDim2.new(xScale, math.floor(xOffset + 0.5), yScale, math.floor(yOffset + 0.5))
end

function SettingsHudLayoutController:queueSettingsSave()
	if not self.settingsSaveRemote then
		return
	end

	self.settingsSaveToken += 1
	local activeToken = self.settingsSaveToken
	task.delay(0.8, function()
		if activeToken ~= self.settingsSaveToken then
			return
		end

		self.settingsSaveRemote:FireServer({
			audio = {
				musicVolume = self.settingsState.musicVolume,
				musicMuted = self.settingsState.musicMuted,
				sfxVolume = self.settingsState.sfxVolume,
				sfxMuted = self.settingsState.sfxMuted,
			},
			hud = {
				scale = self.settingsState.hudScale,
				positions = self.settingsState.hudPositions,
			},
		})
	end)
end

function SettingsHudLayoutController:applyHudRootTransform(root: GuiObject, rootState: RootState)
	local rawPosition = rootState.rawPosition
	if typeof(rawPosition) ~= "UDim2" then
		rawPosition = root.Position
	end

	rootState.applying = true
	root.Position = rawPosition
	if rootState.useAttributeScale then
		root:SetAttribute("HudScaleMultiplier", self.settingsState.hudScale)
	elseif rootState.scaleObject then
		rootState.scaleObject.Scale = self.settingsState.hudScale
	end
	rootState.applying = false
end

function SettingsHudLayoutController:applyHudTransforms()
	for root, rootState in pairs(self.trackedHudRoots) do
		if root.Parent then
			self:applyHudRootTransform(root, rootState)
		else
			self.trackedHudRoots[root] = nil
		end
	end
end

function SettingsHudLayoutController:trackHudRoot(root: GuiObject)
	if self.trackedHudRoots[root] then
		return
	end

	local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
	local useAttributeScale = screenGui ~= nil and screenGui.Name == "ClassXpBarHud" and root.Name == "XpContainer"

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
	if NON_DRAGGABLE_HUD_ROOTS[rootState.persistKey] then
		rootState.canDrag = false
	end

	local savedPosition = self:deserializePosition(self.settingsState.hudPositions[rootState.persistKey])
	if savedPosition then
		rootState.rawPosition = savedPosition
	end

	self.trackedHudRoots[root] = rootState

	table.insert(rootState.connections, root:GetPropertyChangedSignal("Position"):Connect(function()
		if rootState.applying then
			return
		end

		rootState.rawPosition = root.Position
		self.settingsState.hudPositions[rootState.persistKey] = self:serializePosition(rootState.rawPosition)
		self:applyHudRootTransform(root, rootState)
	end))

	table.insert(rootState.connections, root.AncestryChanged:Connect(function(_, parent)
		if parent and root:IsDescendantOf(playerGui) then
			return
		end

		if self.selectedHudRoot == root then
			self.selectedHudRoot = nil
		end
		if self.activeDrag and self.activeDrag.root == root then
			self.activeDrag = nil
		end

		for _, connection in ipairs(rootState.connections) do
			connection:Disconnect()
		end
		self.trackedHudRoots[root] = nil
		self:updateGameplayLabels()
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
		if child:IsA("GuiObject") then
			self:trackHudRoot(child)
		end
	end

	table.insert(screenState.connections, screenGui.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			self:trackHudRoot(child)
		end
	end))

	table.insert(screenState.connections, screenGui.AncestryChanged:Connect(function(_, parent)
		if parent and screenGui:IsDescendantOf(playerGui) then
			return
		end

		for _, connection in ipairs(screenState.connections) do
			connection:Disconnect()
		end
		self.trackedScreenGuis[screenGui] = nil
	end))
end

local function getRootHitBox(root: GuiObject): (number, number, number, number)
	local size = root.AbsoluteSize
	local position = root.AbsolutePosition
	if size.X >= 20 and size.Y >= 20 then
		return position.X, position.Y, size.X, size.Y
	end

	local fallbackSize = Vector2.new(28, 28)
	return position.X - (fallbackSize.X * 0.5), position.Y - (fallbackSize.Y * 0.5), fallbackSize.X, fallbackSize.Y
end

local function isPointInPanel(view: View, screenPos: Vector2): boolean
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

function SettingsHudLayoutController:getTopHudRootAtPosition(screenPos: Vector2): GuiObject?
	local bestRoot = nil
	local bestScore = -math.huge

	for root, rootState in pairs(self.trackedHudRoots) do
		if not rootState.canDrag then
			continue
		end
		if not root.Parent or not root.Visible then
			continue
		end

		local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
		if not screenGui or not screenGui.Enabled then
			continue
		end

		local x, y, width, height = getRootHitBox(root)
		local isInside = screenPos.X >= x and screenPos.X <= (x + width) and screenPos.Y >= y and screenPos.Y <= (y + height)
		if not isInside then
			continue
		end

		local score = (screenGui.DisplayOrder * 1000) + root.ZIndex
		if score > bestScore then
			bestScore = score
			bestRoot = root
		end
	end

	if bestRoot then
		self.selectedHudRoot = bestRoot
		self:updateGameplayLabels()
	end

	return bestRoot
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
	if typeof(startRawPosition) ~= "UDim2" then
		startRawPosition = rootState.rawPosition
	end

	local delta = screenPos - self.activeDrag.startMouse
	rootState.rawPosition = UDim2.new(
		startRawPosition.X.Scale,
		startRawPosition.X.Offset + math.floor(delta.X + 0.5),
		startRawPosition.Y.Scale,
		startRawPosition.Y.Offset + math.floor(delta.Y + 0.5)
	)
	self.settingsState.hudPositions[rootState.persistKey] = self:serializePosition(rootState.rawPosition)
	self:applyHudRootTransform(root, rootState)
	self:updateGameplayLabels()
	self:queueSettingsSave()
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
	if self.moveModeEnabled then
		self.view.moveStatusLabel.Text = "Move Mode ON: left-click and drag one HUD element."
	else
		self.view.moveStatusLabel.Text = "Move Mode OFF"
	end

	self.view.selectedHudLabel.Text = "Selected: " .. getRootLabel(self, self.selectedHudRoot)
	self.view.hudScaleLabel.Text = string.format("HUD Size: %d%%", scalePercent)
	self.view.moveModeButton.Text = if self.moveModeEnabled then "HUD Move Mode: ON" else "HUD Move Mode: OFF"
	self.view.resetPositionButton.Active = self.moveModeEnabled and self.selectedHudRoot ~= nil
	self.view.resetPositionButton.AutoButtonColor = self.view.resetPositionButton.Active
	self.view.resetPositionButton.BackgroundTransparency = if self.view.resetPositionButton.Active then 0 else 0.35
end

function SettingsHudLayoutController:setMoveModeEnabled(enabled: boolean)
	self.moveModeEnabled = enabled
	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, self.moveModeEnabled)
	end
	if not self.moveModeEnabled then
		self.activeDrag = nil
	end

	if self.moveModeEnabled then
		self.view.moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 108, 86)
	else
		self.view.moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 86, 120)
	end

	self:updateGameplayLabels()
end

function SettingsHudLayoutController:applyLoadedHudSettings(loadedHud: any)
	if type(loadedHud) ~= "table" then
		return
	end

	self.settingsState.hudScale = math.clamp(tonumber(loadedHud.scale) or self.settingsState.hudScale, 0.6, 1.45)
	self.settingsState.hudPositions = {}

	if type(loadedHud.positions) == "table" then
		for key, rawPosition in pairs(loadedHud.positions) do
			if type(key) == "string" then
				local parsedPosition = self:deserializePosition(rawPosition)
				if parsedPosition then
					self.settingsState.hudPositions[key] = self:serializePosition(parsedPosition)
				end
			end
		end
	end

	for _, rootState in pairs(self.trackedHudRoots) do
		local savedPosition = self:deserializePosition(self.settingsState.hudPositions[rootState.persistKey])
		if savedPosition then
			rootState.rawPosition = savedPosition
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
		for _, screenConnection in ipairs(screenState.connections) do
			screenConnection:Disconnect()
		end
		self.trackedScreenGuis[screenGui] = nil
	end

	for root, rootState in pairs(self.trackedHudRoots) do
		for _, rootConnection in ipairs(rootState.connections) do
			rootConnection:Disconnect()
		end
		self.trackedHudRoots[root] = nil
	end

	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, false)
	end
end

local function isHudScreenGui(viewGui: ScreenGui, instance: Instance): boolean
	if not instance:IsA("ScreenGui") then
		return false
	end
	if instance == viewGui then
		return false
	end
	return HUD_SCREEN_GUI_NAMES[instance.Name] == true
end

local function ensureDefaults(settingsState: SettingsState)
	settingsState.hudScale = math.clamp(tonumber(settingsState.hudScale) or 1, 0.6, 1.45)
	if type(settingsState.hudPositions) ~= "table" then
		settingsState.hudPositions = {}
	end
end

function SettingsHudLayoutController.new(init: InitOptions): Controller
	local options = init.options or {}

	local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, REMOTE_WAIT_TIMEOUT_SECONDS)
	local settingsSaveRemote = nil
	if remotesFolder then
		settingsSaveRemote = resolveRemote(remotesFolder, SETTINGS_SAVE_REMOTE_NAME, "RemoteEvent")
	end

	local self = (setmetatable({
		view = init.view,
		settingsState = init.settingsState,
		connections = {},
		trackedScreenGuis = {},
		trackedHudRoots = {},
		settingsSaveRemote = settingsSaveRemote,
		settingsSaveToken = 0,
		moveModeEnabled = false,
		selectedHudRoot = nil,
		activeDrag = nil,
		hudMoveModeAttribute = options.hudMoveModeAttribute,
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

		rootState.rawPosition = rootState.defaultPosition
		self.settingsState.hudPositions[rootState.persistKey] = nil
		self:applyHudRootTransform(self.selectedHudRoot, rootState)
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.hudScaleDownButton.Activated:Connect(function()
		self.settingsState.hudScale = math.clamp(self.settingsState.hudScale - 0.05, 0.6, 1.45)
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.hudScaleUpButton.Activated:Connect(function()
		self.settingsState.hudScale = math.clamp(self.settingsState.hudScale + 0.05, 0.6, 1.45)
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.resetScaleButton.Activated:Connect(function()
		self.settingsState.hudScale = 1
		self:applyHudTransforms()
		self:updateGameplayLabels()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(inputObject, _gameProcessed)
		if not self.moveModeEnabled then
			return
		end
		if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local screenPos = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
		if isPointInPanel(self.view, screenPos) then
			return
		end

		local root = self:getTopHudRootAtPosition(screenPos)
		if not root then
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
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(inputObject)
		if not self.moveModeEnabled or not self.activeDrag then
			return
		end
		if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		self:updateDrag(Vector2.new(inputObject.Position.X, inputObject.Position.Y))
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		self.activeDrag = nil
	end))

	if self.hudMoveModeAttribute then
		playerGui:SetAttribute(self.hudMoveModeAttribute, false)
	end
	self:setMoveModeEnabled(false)
	self:applyHudTransforms()
	self:updateGameplayLabels()

	return self
end

return SettingsHudLayoutController
