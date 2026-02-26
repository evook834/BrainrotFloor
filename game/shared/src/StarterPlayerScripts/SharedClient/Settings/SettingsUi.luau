local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SETTINGS_GUI_NAME = "MatchSettingsUi"
local MUSIC_CHANNEL = "Music"
local SFX_CHANNEL = "Sfx"
local GEAR_ICON = utf8.char(0x2699)
local REMOTE_WAIT_TIMEOUT_SECONDS = 15
local UI_HIDDEN_NOTICE_DELAY_SECONDS = 3
local hudMoveModeAttribute = nil

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

local settingsState = {
	musicVolume = 1,
	musicMuted = false,
	sfxVolume = 1,
	sfxMuted = false,
	hudScale = 1,
	hudPositions = {},
}

local trackedSounds = {}
local trackedScreenGuis = {}
local trackedHudRoots = {}
local moveModeEnabled = false
local activeDrag = nil
local selectedHudRoot = nil
local settingsSaveToken = 0
local hiddenScreenGuiEnabledStates = {}
local uiHidden = false
local uiHiddenNoticeToken = 0

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT_TIMEOUT_SECONDS)
local settingsGetFunction = nil
local settingsSaveRemote = nil
local returnToLobbyRemote = nil
local canReturnToLobby = false
local returnToLobbyRequestInFlight = false

local function resolveRemote(remoteName, className)
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

local function resolveOptionalRemote(remoteName, className)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

local function resolveReturnToLobbyRemoteAsync(onResolved)
	if not canReturnToLobby then
		returnToLobbyRemote = nil
		if onResolved then
			onResolved()
		end
		return
	end

	returnToLobbyRemote = resolveOptionalRemote(Config.Remotes.ReturnToLobby, "RemoteEvent")
	if returnToLobbyRemote then
		if onResolved then
			onResolved()
		end
		return
	end

	task.spawn(function()
		local remote = resolveRemote(Config.Remotes.ReturnToLobby, "RemoteEvent")
		if not canReturnToLobby then
			return
		end

		returnToLobbyRemote = remote
		if onResolved then
			onResolved()
		end
	end)
end

if remotesFolder then
	settingsGetFunction = resolveRemote(Config.Remotes.SettingsGet, "RemoteFunction")
	settingsSaveRemote = resolveRemote(Config.Remotes.SettingsSave, "RemoteEvent")
end

local existingGui = playerGui:FindFirstChild(SETTINGS_GUI_NAME)
if existingGui then
	existingGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = SETTINGS_GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = playerGui

local function styleRounded(container, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = container
	return corner
end

local function styleStroke(container, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = container
	return stroke
end

local function classifySound(sound)
	local channel = sound:GetAttribute("AudioChannel")
	if type(channel) == "string" then
		local normalized = string.lower(channel)
		if normalized == "music" then
			return MUSIC_CHANNEL
		end
		if normalized == "sfx" or normalized == "effect" or normalized == "effects" then
			return SFX_CHANNEL
		end
	end

	local group = sound.SoundGroup
	if group then
		local groupName = string.lower(group.Name)
		if string.find(groupName, "music", 1, true) then
			return MUSIC_CHANNEL
		end
		if string.find(groupName, "sfx", 1, true) or string.find(groupName, "effect", 1, true) then
			return SFX_CHANNEL
		end
	end

	local soundName = string.lower(sound.Name)
	if
		string.find(soundName, "music", 1, true)
		or string.find(soundName, "bgm", 1, true)
		or string.find(soundName, "theme", 1, true)
		or string.find(soundName, "song", 1, true)
		or string.find(soundName, "ambient", 1, true)
	then
		return MUSIC_CHANNEL
	end

	return SFX_CHANNEL
end

local function getChannelMultiplier(channel)
	if channel == MUSIC_CHANNEL then
		if settingsState.musicMuted then
			return 0
		end
		return settingsState.musicVolume
	end

	if settingsState.sfxMuted then
		return 0
	end
	return settingsState.sfxVolume
end

local function applySoundState(sound, state)
	if not sound.Parent then
		return
	end

	local multiplier = getChannelMultiplier(state.channel)
	local targetVolume = math.clamp(state.baseVolume * multiplier, 0, 10)
	state.isApplying = true
	sound.Volume = targetVolume
	state.isApplying = false
end

local function refreshAllSounds()
	for sound, state in pairs(trackedSounds) do
		if sound.Parent then
			applySoundState(sound, state)
		else
			trackedSounds[sound] = nil
		end
	end
end

local function trackSound(sound)
	if trackedSounds[sound] then
		return
	end

	local state = {
		channel = classifySound(sound),
		baseVolume = math.clamp(sound.Volume, 0, 10),
		isApplying = false,
		connections = {},
	}
	trackedSounds[sound] = state

	table.insert(state.connections, sound:GetPropertyChangedSignal("SoundGroup"):Connect(function()
		state.channel = classifySound(sound)
		applySoundState(sound, state)
	end))

	table.insert(state.connections, sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if state.isApplying then
			return
		end

		local multiplier = getChannelMultiplier(state.channel)
		if multiplier > 0 then
			state.baseVolume = math.clamp(sound.Volume / multiplier, 0, 10)
		else
			state.baseVolume = math.clamp(sound.Volume, 0, 10)
		end
		applySoundState(sound, state)
	end))

	table.insert(state.connections, sound.AttributeChanged:Connect(function(attributeName)
		if attributeName ~= "AudioChannel" then
			return
		end
		state.channel = classifySound(sound)
		applySoundState(sound, state)
	end))

	table.insert(state.connections, sound.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		for _, connection in ipairs(state.connections) do
			connection:Disconnect()
		end
		trackedSounds[sound] = nil
	end))

	applySoundState(sound, state)
end

local function isHudScreenGui(instance)
	if not instance:IsA("ScreenGui") then
		return false
	end
	if instance == gui then
		return false
	end
	return HUD_SCREEN_GUI_NAMES[instance.Name] == true
end

local function serializePosition(position)
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

local function deserializePosition(rawPosition)
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

local function buildSettingsPayload()
	return {
		audio = {
			musicVolume = settingsState.musicVolume,
			musicMuted = settingsState.musicMuted,
			sfxVolume = settingsState.sfxVolume,
			sfxMuted = settingsState.sfxMuted,
		},
		hud = {
			scale = settingsState.hudScale,
			positions = settingsState.hudPositions,
		},
	}
end

local function queueSettingsSave()
	if not settingsSaveRemote then
		return
	end

	settingsSaveToken += 1
	local activeToken = settingsSaveToken
	task.delay(0.8, function()
		if activeToken ~= settingsSaveToken then
			return
		end
		settingsSaveRemote:FireServer(buildSettingsPayload())
	end)
end

local function applyHudRootTransform(root, rootState)
	local rawPosition = rootState.rawPosition
	if typeof(rawPosition) ~= "UDim2" then
		rawPosition = root.Position
	end

	rootState.applying = true
	root.Position = rawPosition
	if rootState.useAttributeScale then
		root:SetAttribute("HudScaleMultiplier", settingsState.hudScale)
	elseif rootState.scaleObject then
		rootState.scaleObject.Scale = settingsState.hudScale
	end
	rootState.applying = false
end

local function trackHudRoot(root)
	if trackedHudRoots[root] then
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

	local rootState = {
		rawPosition = root.Position,
		defaultPosition = root.Position,
		scaleObject = scaleObject,
		useAttributeScale = useAttributeScale,
		applying = false,
		screenGuiName = "",
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
	local savedPosition = deserializePosition(settingsState.hudPositions[rootState.persistKey])
	if savedPosition then
		rootState.rawPosition = savedPosition
	end
	trackedHudRoots[root] = rootState

	table.insert(rootState.connections, root:GetPropertyChangedSignal("Position"):Connect(function()
		if rootState.applying then
			return
		end

		rootState.rawPosition = root.Position
		settingsState.hudPositions[rootState.persistKey] = serializePosition(rootState.rawPosition)
		applyHudRootTransform(root, rootState)
	end))

	table.insert(rootState.connections, root.AncestryChanged:Connect(function(_, parent)
		if parent and root:IsDescendantOf(playerGui) then
			return
		end

		if selectedHudRoot == root then
			selectedHudRoot = nil
		end
		if activeDrag and activeDrag.root == root then
			activeDrag = nil
		end

		for _, connection in ipairs(rootState.connections) do
			connection:Disconnect()
		end
		trackedHudRoots[root] = nil
	end))

	applyHudRootTransform(root, rootState)
end

local function applyHudTransforms()
	for root, rootState in pairs(trackedHudRoots) do
		if root.Parent then
			applyHudRootTransform(root, rootState)
		else
			trackedHudRoots[root] = nil
		end
	end
end

local function trackScreenGui(screenGui)
	if trackedScreenGuis[screenGui] then
		return
	end

	local screenState = {
		connections = {},
	}
	trackedScreenGuis[screenGui] = screenState

	for _, child in ipairs(screenGui:GetChildren()) do
		if child:IsA("GuiObject") then
			trackHudRoot(child)
		end
	end

	table.insert(screenState.connections, screenGui.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			trackHudRoot(child)
		end
	end))

	table.insert(screenState.connections, screenGui.AncestryChanged:Connect(function(_, parent)
		if parent and screenGui:IsDescendantOf(playerGui) then
			return
		end

		for _, connection in ipairs(screenState.connections) do
			connection:Disconnect()
		end
		trackedScreenGuis[screenGui] = nil
	end))
end

for _, descendant in ipairs(game:GetDescendants()) do
	if descendant:IsA("Sound") then
		trackSound(descendant)
	end
end

game.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Sound") then
		trackSound(descendant)
	end
end)

for _, child in ipairs(playerGui:GetChildren()) do
	if isHudScreenGui(child) then
		trackScreenGui(child)
	end
end

playerGui.ChildAdded:Connect(function(child)
	if uiHidden and child:IsA("ScreenGui") and hiddenScreenGuiEnabledStates[child] == nil then
		hiddenScreenGuiEnabledStates[child] = child.Enabled
		child.Enabled = false
	end

	if isHudScreenGui(child) then
		trackScreenGui(child)
	end
end)

local launcher = Instance.new("Frame")
launcher.Name = "SettingsLauncher"
launcher.Size = UDim2.fromOffset(146, 46)
launcher.Position = UDim2.new(0, 12, 0.5, 72)
launcher.BackgroundTransparency = 1
launcher.Parent = gui

local launcherGear = Instance.new("TextButton")
launcherGear.Name = "GearButton"
launcherGear.Size = UDim2.fromOffset(46, 46)
launcherGear.Position = UDim2.fromOffset(0, 0)
launcherGear.BackgroundColor3 = Color3.fromRGB(32, 37, 47)
launcherGear.BorderSizePixel = 0
launcherGear.Text = GEAR_ICON
launcherGear.TextColor3 = Color3.fromRGB(242, 246, 255)
launcherGear.Font = Enum.Font.GothamBold
launcherGear.TextSize = 25
launcherGear.Parent = launcher
styleRounded(launcherGear, 8)
styleStroke(launcherGear, Color3.fromRGB(88, 104, 128), 0.2, 1)

local launcherLabel = Instance.new("TextLabel")
launcherLabel.Name = "Label"
launcherLabel.Size = UDim2.fromOffset(92, 46)
launcherLabel.Position = UDim2.fromOffset(54, 0)
launcherLabel.BackgroundTransparency = 1
launcherLabel.Text = "Settings"
launcherLabel.TextXAlignment = Enum.TextXAlignment.Left
launcherLabel.TextColor3 = Color3.fromRGB(232, 238, 248)
launcherLabel.Font = Enum.Font.GothamSemibold
launcherLabel.TextSize = 18
launcherLabel.Parent = launcher

local panel = Instance.new("Frame")
panel.Name = "SettingsPanel"
panel.Size = UDim2.fromOffset(400, 360)
panel.Position = UDim2.new(0, 66, 0.5, -180)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
styleRounded(panel, 12)
styleStroke(panel, Color3.fromRGB(78, 95, 120), 0.14, 1)

local panelTitle = Instance.new("TextLabel")
panelTitle.Name = "Title"
panelTitle.Size = UDim2.new(1, -64, 0, 34)
panelTitle.Position = UDim2.fromOffset(14, 8)
panelTitle.BackgroundTransparency = 1
panelTitle.Text = "Settings"
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
panelTitle.Font = Enum.Font.GothamBold
panelTitle.TextSize = 24
panelTitle.Parent = panel

local panelClose = Instance.new("TextButton")
panelClose.Name = "CloseButton"
panelClose.Size = UDim2.fromOffset(34, 34)
panelClose.Position = UDim2.new(1, -42, 0, 8)
panelClose.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
panelClose.BorderSizePixel = 0
panelClose.Text = "X"
panelClose.TextColor3 = Color3.fromRGB(240, 240, 245)
panelClose.Font = Enum.Font.GothamBold
panelClose.TextSize = 18
panelClose.Parent = panel
styleRounded(panelClose, 8)

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -24, 0, 42)
tabBar.Position = UDim2.fromOffset(12, 50)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local audioTabButton = Instance.new("TextButton")
audioTabButton.Name = "AudioTab"
audioTabButton.Size = UDim2.new(0.5, -5, 1, 0)
audioTabButton.Position = UDim2.fromOffset(0, 0)
audioTabButton.BackgroundColor3 = Color3.fromRGB(52, 70, 96)
audioTabButton.BorderSizePixel = 0
audioTabButton.Text = "Audio"
audioTabButton.TextColor3 = Color3.fromRGB(240, 246, 255)
audioTabButton.Font = Enum.Font.GothamBold
audioTabButton.TextSize = 15
audioTabButton.Parent = tabBar
styleRounded(audioTabButton, 8)

local gameplayTabButton = Instance.new("TextButton")
gameplayTabButton.Name = "GameplayTab"
gameplayTabButton.Size = UDim2.new(0.5, -5, 1, 0)
gameplayTabButton.Position = UDim2.new(0.5, 5, 0, 0)
gameplayTabButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
gameplayTabButton.BorderSizePixel = 0
gameplayTabButton.Text = "Gameplay"
gameplayTabButton.TextColor3 = Color3.fromRGB(225, 233, 245)
gameplayTabButton.Font = Enum.Font.GothamBold
gameplayTabButton.TextSize = 15
gameplayTabButton.Parent = tabBar
styleRounded(gameplayTabButton, 8)

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -24, 1, -108)
content.Position = UDim2.fromOffset(12, 98)
content.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
content.BackgroundTransparency = 0.15
content.BorderSizePixel = 0
content.Parent = panel
styleRounded(content, 8)

local audioPage = Instance.new("Frame")
audioPage.Name = "AudioPage"
audioPage.Size = UDim2.fromScale(1, 1)
audioPage.BackgroundTransparency = 1
audioPage.Visible = true
audioPage.Parent = content

local gameplayPage = Instance.new("Frame")
gameplayPage.Name = "GameplayPage"
gameplayPage.Size = UDim2.fromScale(1, 1)
gameplayPage.BackgroundTransparency = 1
gameplayPage.Visible = false
gameplayPage.Parent = content

local function createSlider(parent, labelText, offsetY, initialValue, onChanged)
	local row = Instance.new("Frame")
	row.Name = labelText:gsub("%s+", "") .. "Row"
	row.Size = UDim2.new(1, -12, 0, 74)
	row.Position = UDim2.fromOffset(6, offsetY)
	row.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Parent = parent
	styleRounded(row, 8)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -16, 0, 20)
	label.Position = UDim2.fromOffset(8, 6)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(226, 234, 245)
	label.Font = Enum.Font.GothamSemibold
	label.TextSize = 14
	label.Parent = row

	local sliderBackground = Instance.new("Frame")
	sliderBackground.Name = "SliderBackground"
	sliderBackground.Size = UDim2.fromOffset(230, 12)
	sliderBackground.Position = UDim2.fromOffset(8, 40)
	sliderBackground.BackgroundColor3 = Color3.fromRGB(44, 52, 66)
	sliderBackground.BorderSizePixel = 0
	sliderBackground.Parent = row
	styleRounded(sliderBackground, 6)

	local sliderFill = Instance.new("Frame")
	sliderFill.Name = "SliderFill"
	sliderFill.Size = UDim2.fromScale(0, 1)
	sliderFill.BackgroundColor3 = Color3.fromRGB(100, 168, 242)
	sliderFill.BorderSizePixel = 0
	sliderFill.Parent = sliderBackground
	styleRounded(sliderFill, 6)

	local sliderKnob = Instance.new("Frame")
	sliderKnob.Name = "SliderKnob"
	sliderKnob.Size = UDim2.fromOffset(12, 12)
	sliderKnob.Position = UDim2.fromOffset(-6, 0)
	sliderKnob.BackgroundColor3 = Color3.fromRGB(238, 245, 255)
	sliderKnob.BorderSizePixel = 0
	sliderKnob.Parent = sliderBackground
	styleRounded(sliderKnob, 6)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ValueLabel"
	valueLabel.Size = UDim2.fromOffset(52, 22)
	valueLabel.Position = UDim2.fromOffset(248, 35)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "100%"
	valueLabel.TextColor3 = Color3.fromRGB(230, 238, 248)
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 14
	valueLabel.Parent = row

	local minusButton = Instance.new("TextButton")
	minusButton.Name = "MinusButton"
	minusButton.Size = UDim2.fromOffset(24, 24)
	minusButton.Position = UDim2.fromOffset(308, 34)
	minusButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
	minusButton.BorderSizePixel = 0
	minusButton.Text = "-"
	minusButton.TextColor3 = Color3.fromRGB(236, 242, 252)
	minusButton.Font = Enum.Font.GothamBold
	minusButton.TextSize = 16
	minusButton.Parent = row
	styleRounded(minusButton, 6)

	local plusButton = Instance.new("TextButton")
	plusButton.Name = "PlusButton"
	plusButton.Size = UDim2.fromOffset(24, 24)
	plusButton.Position = UDim2.fromOffset(336, 34)
	plusButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
	plusButton.BorderSizePixel = 0
	plusButton.Text = "+"
	plusButton.TextColor3 = Color3.fromRGB(236, 242, 252)
	plusButton.Font = Enum.Font.GothamBold
	plusButton.TextSize = 16
	plusButton.Parent = row
	styleRounded(plusButton, 6)

	local currentValue = math.clamp(initialValue, 0, 1)
	local isDragging = false

	local function setValue(newValue, fireChanged)
		currentValue = math.clamp(newValue, 0, 1)
		sliderFill.Size = UDim2.fromScale(currentValue, 1)
		sliderKnob.Position = UDim2.new(currentValue, -6, 0, 0)
		valueLabel.Text = string.format("%d%%", math.floor((currentValue * 100) + 0.5))
		if fireChanged and onChanged then
			onChanged(currentValue)
		end
	end

	local function setFromInputPosition(positionX)
		local width = math.max(1, sliderBackground.AbsoluteSize.X)
		local relative = (positionX - sliderBackground.AbsolutePosition.X) / width
		setValue(relative, true)
	end

	sliderBackground.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		isDragging = true
		setFromInputPosition(input.Position.X)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not isDragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setFromInputPosition(input.Position.X)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		isDragging = false
	end)

	minusButton.Activated:Connect(function()
		setValue(currentValue - 0.05, true)
	end)

	plusButton.Activated:Connect(function()
		setValue(currentValue + 0.05, true)
	end)

	setValue(currentValue, false)

	return {
		setValue = function(newValue, fireChanged)
			setValue(newValue, fireChanged == true)
		end,
		getValue = function()
			return currentValue
		end,
	}
end

local musicSlider = createSlider(audioPage, "Music Volume", 10, settingsState.musicVolume, function(value)
	settingsState.musicVolume = value
	refreshAllSounds()
	queueSettingsSave()
end)

local musicMuteButton = Instance.new("TextButton")
musicMuteButton.Name = "MusicMuteButton"
musicMuteButton.Size = UDim2.fromOffset(164, 32)
musicMuteButton.Position = UDim2.fromOffset(10, 90)
musicMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
musicMuteButton.BorderSizePixel = 0
musicMuteButton.TextColor3 = Color3.fromRGB(236, 242, 252)
musicMuteButton.Font = Enum.Font.GothamBold
musicMuteButton.TextSize = 14
musicMuteButton.Parent = audioPage
styleRounded(musicMuteButton, 8)

local sfxSlider = createSlider(audioPage, "SFX / Effects Volume", 130, settingsState.sfxVolume, function(value)
	settingsState.sfxVolume = value
	refreshAllSounds()
	queueSettingsSave()
end)

local sfxMuteButton = Instance.new("TextButton")
sfxMuteButton.Name = "SfxMuteButton"
sfxMuteButton.Size = UDim2.fromOffset(164, 32)
sfxMuteButton.Position = UDim2.fromOffset(10, 210)
sfxMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
sfxMuteButton.BorderSizePixel = 0
sfxMuteButton.TextColor3 = Color3.fromRGB(236, 242, 252)
sfxMuteButton.Font = Enum.Font.GothamBold
sfxMuteButton.TextSize = 14
sfxMuteButton.Parent = audioPage
styleRounded(sfxMuteButton, 8)

local audioHint = Instance.new("TextLabel")
audioHint.Name = "Hint"
audioHint.Size = UDim2.new(1, -20, 0, 34)
audioHint.Position = UDim2.fromOffset(10, 248)
audioHint.BackgroundTransparency = 1
audioHint.Text = "Tip: set Sound attribute AudioChannel to Music or Sfx for exact routing."
audioHint.TextWrapped = true
audioHint.TextXAlignment = Enum.TextXAlignment.Left
audioHint.TextYAlignment = Enum.TextYAlignment.Top
audioHint.TextColor3 = Color3.fromRGB(178, 192, 210)
audioHint.Font = Enum.Font.Gotham
audioHint.TextSize = 12
audioHint.Parent = audioPage

local moveModeButton = Instance.new("TextButton")
moveModeButton.Name = "MoveModeButton"
moveModeButton.Size = UDim2.fromOffset(182, 34)
moveModeButton.Position = UDim2.fromOffset(10, 10)
moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 86, 120)
moveModeButton.BorderSizePixel = 0
moveModeButton.TextColor3 = Color3.fromRGB(242, 248, 255)
moveModeButton.Font = Enum.Font.GothamBold
moveModeButton.TextSize = 14
moveModeButton.Parent = gameplayPage
styleRounded(moveModeButton, 8)

local moveStatusLabel = Instance.new("TextLabel")
moveStatusLabel.Name = "MoveStatus"
moveStatusLabel.Size = UDim2.new(1, -20, 0, 20)
moveStatusLabel.Position = UDim2.fromOffset(10, 48)
moveStatusLabel.BackgroundTransparency = 1
moveStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
moveStatusLabel.TextColor3 = Color3.fromRGB(205, 220, 236)
moveStatusLabel.Font = Enum.Font.GothamSemibold
moveStatusLabel.TextSize = 13
moveStatusLabel.Parent = gameplayPage

local selectedHudLabel = Instance.new("TextLabel")
selectedHudLabel.Name = "SelectedHud"
selectedHudLabel.Size = UDim2.new(1, -20, 0, 18)
selectedHudLabel.Position = UDim2.fromOffset(10, 66)
selectedHudLabel.BackgroundTransparency = 1
selectedHudLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedHudLabel.TextColor3 = Color3.fromRGB(182, 198, 216)
selectedHudLabel.Font = Enum.Font.Gotham
selectedHudLabel.TextSize = 12
selectedHudLabel.Parent = gameplayPage

local returnToLobbyButton = Instance.new("TextButton")
returnToLobbyButton.Name = "ReturnToLobbyButton"
returnToLobbyButton.Size = UDim2.fromOffset(140, 34)
returnToLobbyButton.Position = UDim2.fromOffset(226, 10)
returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(98, 64, 64)
returnToLobbyButton.BorderSizePixel = 0
returnToLobbyButton.Text = "Return to Lobby"
returnToLobbyButton.TextColor3 = Color3.fromRGB(246, 238, 238)
returnToLobbyButton.Font = Enum.Font.GothamBold
returnToLobbyButton.TextSize = 13
returnToLobbyButton.Parent = gameplayPage
styleRounded(returnToLobbyButton, 8)

local returnToLobbyStatusLabel = Instance.new("TextLabel")
returnToLobbyStatusLabel.Name = "ReturnToLobbyStatus"
returnToLobbyStatusLabel.Size = UDim2.fromOffset(140, 42)
returnToLobbyStatusLabel.Position = UDim2.fromOffset(226, 48)
returnToLobbyStatusLabel.BackgroundTransparency = 1
returnToLobbyStatusLabel.TextWrapped = true
returnToLobbyStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
returnToLobbyStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
returnToLobbyStatusLabel.TextColor3 = Color3.fromRGB(182, 198, 216)
returnToLobbyStatusLabel.Font = Enum.Font.Gotham
returnToLobbyStatusLabel.TextSize = 12
returnToLobbyStatusLabel.Parent = gameplayPage

local resetPositionButton = Instance.new("TextButton")
resetPositionButton.Name = "ResetPositionButton"
resetPositionButton.Size = UDim2.fromOffset(184, 34)
resetPositionButton.Position = UDim2.fromOffset(10, 90)
resetPositionButton.BackgroundColor3 = Color3.fromRGB(76, 60, 60)
resetPositionButton.BorderSizePixel = 0
resetPositionButton.Text = "Reset Selected UI Position"
resetPositionButton.TextColor3 = Color3.fromRGB(245, 236, 236)
resetPositionButton.Font = Enum.Font.GothamBold
resetPositionButton.TextSize = 12
resetPositionButton.Parent = gameplayPage
styleRounded(resetPositionButton, 8)

local hudScaleLabel = Instance.new("TextLabel")
hudScaleLabel.Name = "HudScaleLabel"
hudScaleLabel.Size = UDim2.new(1, -20, 0, 20)
hudScaleLabel.Position = UDim2.fromOffset(10, 124)
hudScaleLabel.BackgroundTransparency = 1
hudScaleLabel.TextXAlignment = Enum.TextXAlignment.Left
hudScaleLabel.TextColor3 = Color3.fromRGB(205, 220, 236)
hudScaleLabel.Font = Enum.Font.GothamSemibold
hudScaleLabel.TextSize = 13
hudScaleLabel.Parent = gameplayPage

local hudScaleDownButton = Instance.new("TextButton")
hudScaleDownButton.Name = "HudScaleDown"
hudScaleDownButton.Size = UDim2.fromOffset(42, 32)
hudScaleDownButton.Position = UDim2.fromOffset(10, 150)
hudScaleDownButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
hudScaleDownButton.BorderSizePixel = 0
hudScaleDownButton.Text = "-"
hudScaleDownButton.TextColor3 = Color3.fromRGB(236, 242, 252)
hudScaleDownButton.Font = Enum.Font.GothamBold
hudScaleDownButton.TextSize = 22
hudScaleDownButton.Parent = gameplayPage
styleRounded(hudScaleDownButton, 6)

local hudScaleUpButton = Instance.new("TextButton")
hudScaleUpButton.Name = "HudScaleUp"
hudScaleUpButton.Size = UDim2.fromOffset(42, 32)
hudScaleUpButton.Position = UDim2.fromOffset(58, 150)
hudScaleUpButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
hudScaleUpButton.BorderSizePixel = 0
hudScaleUpButton.Text = "+"
hudScaleUpButton.TextColor3 = Color3.fromRGB(236, 242, 252)
hudScaleUpButton.Font = Enum.Font.GothamBold
hudScaleUpButton.TextSize = 20
hudScaleUpButton.Parent = gameplayPage
styleRounded(hudScaleUpButton, 6)

local resetScaleButton = Instance.new("TextButton")
resetScaleButton.Name = "ResetScaleButton"
resetScaleButton.Size = UDim2.fromOffset(110, 32)
resetScaleButton.Position = UDim2.fromOffset(108, 150)
resetScaleButton.BackgroundColor3 = Color3.fromRGB(76, 60, 60)
resetScaleButton.BorderSizePixel = 0
resetScaleButton.Text = "Reset Size"
resetScaleButton.TextColor3 = Color3.fromRGB(245, 236, 236)
resetScaleButton.Font = Enum.Font.GothamBold
resetScaleButton.TextSize = 13
resetScaleButton.Parent = gameplayPage
styleRounded(resetScaleButton, 6)

local fullHideButton = Instance.new("TextButton")
fullHideButton.Name = "FullHideButton"
fullHideButton.Size = UDim2.fromOffset(208, 34)
fullHideButton.Position = UDim2.fromOffset(10, 190)
fullHideButton.BackgroundColor3 = Color3.fromRGB(62, 94, 54)
fullHideButton.BorderSizePixel = 0
fullHideButton.Text = "Hide All UI + HUD"
fullHideButton.TextColor3 = Color3.fromRGB(242, 248, 255)
fullHideButton.Font = Enum.Font.GothamBold
fullHideButton.TextSize = 13
fullHideButton.Parent = gameplayPage
styleRounded(fullHideButton, 8)

local fullHideStatusLabel = Instance.new("TextLabel")
fullHideStatusLabel.Name = "FullHideStatus"
fullHideStatusLabel.Size = UDim2.new(1, -20, 0, 20)
fullHideStatusLabel.Position = UDim2.fromOffset(10, 228)
fullHideStatusLabel.BackgroundTransparency = 1
fullHideStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
fullHideStatusLabel.TextColor3 = Color3.fromRGB(182, 198, 216)
fullHideStatusLabel.Font = Enum.Font.Gotham
fullHideStatusLabel.TextSize = 12
fullHideStatusLabel.Parent = gameplayPage

local gameplayHint = Instance.new("TextLabel")
gameplayHint.Name = "Hint"
gameplayHint.Size = UDim2.new(1, -20, 0, 32)
gameplayHint.Position = UDim2.fromOffset(10, 252)
gameplayHint.BackgroundTransparency = 1
gameplayHint.Text = "Move mode: left-click one HUD element and drag it. Only that UI moves."
gameplayHint.TextWrapped = true
gameplayHint.TextXAlignment = Enum.TextXAlignment.Left
gameplayHint.TextYAlignment = Enum.TextYAlignment.Top
gameplayHint.TextColor3 = Color3.fromRGB(178, 192, 210)
gameplayHint.Font = Enum.Font.Gotham
gameplayHint.TextSize = 12
gameplayHint.Parent = gameplayPage

local function getRootLabel(root)
	local rootState = trackedHudRoots[root]
	if not rootState then
		return "None"
	end
	if rootState.screenGuiName ~= "" then
		return string.format("%s / %s", rootState.screenGuiName, root.Name)
	end
	return root.Name
end

local function updateAudioButtons()
	if settingsState.musicMuted then
		musicMuteButton.BackgroundColor3 = Color3.fromRGB(128, 66, 66)
		musicMuteButton.Text = "Unmute Music"
	else
		musicMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
		musicMuteButton.Text = "Mute Music"
	end

	if settingsState.sfxMuted then
		sfxMuteButton.BackgroundColor3 = Color3.fromRGB(128, 66, 66)
		sfxMuteButton.Text = "Unmute SFX"
	else
		sfxMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
		sfxMuteButton.Text = "Mute SFX"
	end
end

local function updateReturnToLobbyControls()
	local buttonEnabled = canReturnToLobby and returnToLobbyRemote ~= nil and not returnToLobbyRequestInFlight
	returnToLobbyButton.Active = buttonEnabled
	returnToLobbyButton.AutoButtonColor = buttonEnabled

	if returnToLobbyRequestInFlight then
		returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(86, 72, 56)
		returnToLobbyButton.BackgroundTransparency = 0.12
		returnToLobbyButton.TextColor3 = Color3.fromRGB(244, 236, 228)
		returnToLobbyButton.Text = "Returning..."
		returnToLobbyStatusLabel.Text = "Teleport request sent."
		return
	end

	if canReturnToLobby and returnToLobbyRemote then
		returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(98, 64, 64)
		returnToLobbyButton.BackgroundTransparency = 0
		returnToLobbyButton.TextColor3 = Color3.fromRGB(246, 238, 238)
		returnToLobbyButton.Text = "Return to Lobby"
		returnToLobbyStatusLabel.Text = "Leave the current match and teleport back to lobby."
		return
	end

	returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(68, 72, 80)
	returnToLobbyButton.BackgroundTransparency = 0.35
	returnToLobbyButton.TextColor3 = Color3.fromRGB(188, 194, 202)
	returnToLobbyButton.Text = "Return to Lobby"
	if canReturnToLobby then
		returnToLobbyStatusLabel.Text = "Return-to-lobby is unavailable right now."
	else
		returnToLobbyStatusLabel.Text = "You are already in the lobby."
	end
end

local function updateGameplayLabels()
	local scalePercent = math.floor((settingsState.hudScale * 100) + 0.5)
	if moveModeEnabled then
		moveStatusLabel.Text = "Move Mode ON: left-click and drag one HUD element."
	else
		moveStatusLabel.Text = "Move Mode OFF"
	end
	selectedHudLabel.Text = "Selected: " .. getRootLabel(selectedHudRoot)
	hudScaleLabel.Text = string.format("HUD Size: %d%%", scalePercent)
	moveModeButton.Text = if moveModeEnabled then "HUD Move Mode: ON" else "HUD Move Mode: OFF"
	resetPositionButton.Active = moveModeEnabled and selectedHudRoot ~= nil
	resetPositionButton.AutoButtonColor = resetPositionButton.Active
	resetPositionButton.BackgroundTransparency = if resetPositionButton.Active then 0 else 0.35
	if uiHidden then
		fullHideButton.BackgroundColor3 = Color3.fromRGB(120, 78, 52)
		fullHideButton.Text = "Show All UI + HUD"
		fullHideStatusLabel.Text = "UI hidden. Press F10 to restore."
	else
		fullHideButton.BackgroundColor3 = Color3.fromRGB(62, 94, 54)
		fullHideButton.Text = "Hide All UI + HUD"
		fullHideStatusLabel.Text = "Tip: Press F10 to toggle full UI visibility."
	end
	updateReturnToLobbyControls()
end

local function setActiveTab(tabName)
	local audioActive = tabName == "Audio"
	audioPage.Visible = audioActive
	gameplayPage.Visible = not audioActive

	if audioActive then
		audioTabButton.BackgroundColor3 = Color3.fromRGB(52, 70, 96)
		audioTabButton.TextColor3 = Color3.fromRGB(240, 246, 255)
		gameplayTabButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
		gameplayTabButton.TextColor3 = Color3.fromRGB(225, 233, 245)
	else
		audioTabButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
		audioTabButton.TextColor3 = Color3.fromRGB(225, 233, 245)
		gameplayTabButton.BackgroundColor3 = Color3.fromRGB(52, 70, 96)
		gameplayTabButton.TextColor3 = Color3.fromRGB(240, 246, 255)
	end
end

local function getRootHitBox(root)
	local size = root.AbsoluteSize
	local position = root.AbsolutePosition
	if size.X >= 20 and size.Y >= 20 then
		return position.X, position.Y, size.X, size.Y
	end

	local fallbackSize = Vector2.new(28, 28)
	return position.X - (fallbackSize.X * 0.5), position.Y - (fallbackSize.Y * 0.5), fallbackSize.X, fallbackSize.Y
end

local function isPointInPanel(screenPos)
	if not panel.Visible then
		return false
	end

	local panelPos = panel.AbsolutePosition
	local panelSize = panel.AbsoluteSize
	return screenPos.X >= panelPos.X
		and screenPos.X <= panelPos.X + panelSize.X
		and screenPos.Y >= panelPos.Y
		and screenPos.Y <= panelPos.Y + panelSize.Y
end

local function getTopHudRootAtPosition(screenPos)
	local bestRoot = nil
	local bestScore = -math.huge

	for root, rootState in pairs(trackedHudRoots) do
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

		local x, y, w, h = getRootHitBox(root)
		local isInside = screenPos.X >= x and screenPos.X <= (x + w) and screenPos.Y >= y and screenPos.Y <= (y + h)
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
		selectedHudRoot = bestRoot
		updateGameplayLabels()
	end

	return bestRoot
end

local function adjustHudScale(delta)
	settingsState.hudScale = math.clamp(settingsState.hudScale + delta, 0.6, 1.45)
	applyHudTransforms()
	updateGameplayLabels()
	queueSettingsSave()
end

local function setMoveModeEnabled(enabled)
	moveModeEnabled = enabled
	if hudMoveModeAttribute then
		playerGui:SetAttribute(hudMoveModeAttribute, moveModeEnabled)
	end
	if not moveModeEnabled then
		activeDrag = nil
	end

	if moveModeEnabled then
		moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 108, 86)
	else
		moveModeButton.BackgroundColor3 = Color3.fromRGB(52, 86, 120)
	end

	updateGameplayLabels()
end

local function showUiHiddenHintNotification()
	local payload = {
		Title = "UI Hidden",
		Text = "Press F10 to show UI + HUD.",
		Duration = 5,
	}

	for _ = 1, 3 do
		local ok = pcall(function()
			StarterGui:SetCore("SendNotification", payload)
		end)
		if ok then
			return
		end
		task.wait(0.35)
	end
end

local function setUiHidden(enabled)
	if uiHidden == enabled then
		return
	end

	uiHiddenNoticeToken += 1
	local noticeToken = uiHiddenNoticeToken
	uiHidden = enabled
	if uiHidden then
		panel.Visible = false
		setMoveModeEnabled(false)
		selectedHudRoot = nil
		activeDrag = nil

		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and hiddenScreenGuiEnabledStates[child] == nil then
				hiddenScreenGuiEnabledStates[child] = child.Enabled
				child.Enabled = false
			end
		end
	else
		for screenGui, wasEnabled in pairs(hiddenScreenGuiEnabledStates) do
			if screenGui.Parent and screenGui:IsDescendantOf(playerGui) then
				screenGui.Enabled = wasEnabled == true
			end
			hiddenScreenGuiEnabledStates[screenGui] = nil
		end
	end

	if uiHidden then
		task.delay(UI_HIDDEN_NOTICE_DELAY_SECONDS, function()
			if noticeToken ~= uiHiddenNoticeToken then
				return
			end
			if not uiHidden then
				return
			end
			showUiHiddenHintNotification()
		end)
	end

	updateGameplayLabels()
end

local function beginDrag(root, screenPos)
	local rootState = trackedHudRoots[root]
	if not rootState or not rootState.canDrag then
		return
	end

	activeDrag = {
		root = root,
		startMouse = Vector2.new(screenPos.X, screenPos.Y),
		startRawPosition = rootState.rawPosition,
	}
	selectedHudRoot = root
	updateGameplayLabels()
end

local function updateDrag(screenPos)
	if not activeDrag then
		return
	end

	local root = activeDrag.root
	local rootState = trackedHudRoots[root]
	if not rootState then
		activeDrag = nil
		return
	end

	local startRawPosition = activeDrag.startRawPosition
	if typeof(startRawPosition) ~= "UDim2" then
		startRawPosition = rootState.rawPosition
	end

	local delta = Vector2.new(screenPos.X, screenPos.Y) - activeDrag.startMouse
	rootState.rawPosition = UDim2.new(
		startRawPosition.X.Scale,
		startRawPosition.X.Offset + math.floor(delta.X + 0.5),
		startRawPosition.Y.Scale,
		startRawPosition.Y.Offset + math.floor(delta.Y + 0.5)
	)
	settingsState.hudPositions[rootState.persistKey] = serializePosition(rootState.rawPosition)
	applyHudRootTransform(root, rootState)
	updateGameplayLabels()
	queueSettingsSave()
end

local function togglePanel()
	panel.Visible = not panel.Visible
	if panel.Visible then
		setActiveTab("Audio")
	end
end

launcherGear.Activated:Connect(togglePanel)
panelClose.Activated:Connect(function()
	panel.Visible = false
end)

audioTabButton.Activated:Connect(function()
	setActiveTab("Audio")
end)

gameplayTabButton.Activated:Connect(function()
	setActiveTab("Gameplay")
end)

musicMuteButton.Activated:Connect(function()
	settingsState.musicMuted = not settingsState.musicMuted
	refreshAllSounds()
	updateAudioButtons()
	queueSettingsSave()
end)

sfxMuteButton.Activated:Connect(function()
	settingsState.sfxMuted = not settingsState.sfxMuted
	refreshAllSounds()
	updateAudioButtons()
	queueSettingsSave()
end)

fullHideButton.Activated:Connect(function()
	setUiHidden(not uiHidden)
end)

returnToLobbyButton.Activated:Connect(function()
	if not canReturnToLobby or not returnToLobbyRemote or returnToLobbyRequestInFlight then
		return
	end

	returnToLobbyRequestInFlight = true
	panel.Visible = false
	setMoveModeEnabled(false)
	selectedHudRoot = nil
	activeDrag = nil
	updateGameplayLabels()
	returnToLobbyRemote:FireServer()

	task.delay(2, function()
		if not player.Parent then
			return
		end

		returnToLobbyRequestInFlight = false
		updateGameplayLabels()
	end)
end)

moveModeButton.Activated:Connect(function()
	setMoveModeEnabled(not moveModeEnabled)
end)

resetPositionButton.Activated:Connect(function()
	if not moveModeEnabled then
		return
	end
	if not selectedHudRoot then
		return
	end

	local rootState = trackedHudRoots[selectedHudRoot]
	if not rootState then
		selectedHudRoot = nil
		updateGameplayLabels()
		return
	end

	rootState.rawPosition = rootState.defaultPosition
	settingsState.hudPositions[rootState.persistKey] = nil
	applyHudRootTransform(selectedHudRoot, rootState)
	updateGameplayLabels()
	queueSettingsSave()
end)

UserInputService.InputBegan:Connect(function(inputObject, _gameProcessed)
	if inputObject.UserInputType == Enum.UserInputType.Keyboard and inputObject.KeyCode == Enum.KeyCode.F10 then
		setUiHidden(not uiHidden)
		return
	end

	if not moveModeEnabled then
		return
	end
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local screenPos = inputObject.Position
	if isPointInPanel(screenPos) then
		return
	end

	local root = getTopHudRootAtPosition(screenPos)
	if root then
		beginDrag(root, screenPos)
	end
end)

UserInputService.InputChanged:Connect(function(inputObject)
	if not moveModeEnabled or not activeDrag then
		return
	end
	if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	updateDrag(inputObject.Position)
end)

UserInputService.InputEnded:Connect(function(inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	activeDrag = nil
end)

hudScaleDownButton.Activated:Connect(function()
	adjustHudScale(-0.05)
end)

hudScaleUpButton.Activated:Connect(function()
	adjustHudScale(0.05)
end)

resetScaleButton.Activated:Connect(function()
	settingsState.hudScale = 1
	applyHudTransforms()
	updateGameplayLabels()
	queueSettingsSave()
end)

setMoveModeEnabled(false)
local function loadSettingsFromServer()
	if not settingsGetFunction then
		return
	end

	local ok, response = pcall(function()
		return settingsGetFunction:InvokeServer()
	end)
	if not ok or type(response) ~= "table" or response.success ~= true then
		return
	end

	local loadedSettings = response.settings
	if type(loadedSettings) ~= "table" then
		return
	end

	local loadedAudio = loadedSettings.audio
	if type(loadedAudio) == "table" then
		settingsState.musicVolume = math.clamp(tonumber(loadedAudio.musicVolume) or settingsState.musicVolume, 0, 1)
		settingsState.musicMuted = loadedAudio.musicMuted == true
		settingsState.sfxVolume = math.clamp(tonumber(loadedAudio.sfxVolume) or settingsState.sfxVolume, 0, 1)
		settingsState.sfxMuted = loadedAudio.sfxMuted == true
	end

	settingsState.hudPositions = {}
	local loadedHud = loadedSettings.hud
	if type(loadedHud) == "table" then
		settingsState.hudScale = math.clamp(tonumber(loadedHud.scale) or settingsState.hudScale, 0.6, 1.45)
		if type(loadedHud.positions) == "table" then
			for key, rawPosition in pairs(loadedHud.positions) do
				if type(key) == "string" then
					local parsedPosition = deserializePosition(rawPosition)
					if parsedPosition then
						settingsState.hudPositions[key] = serializePosition(parsedPosition)
					end
				end
			end
		end
	end

	for _, rootState in pairs(trackedHudRoots) do
		local savedPosition = deserializePosition(settingsState.hudPositions[rootState.persistKey])
		if savedPosition then
			rootState.rawPosition = savedPosition
		end
	end
end

local function run(options)
	options = options or {}
	hudMoveModeAttribute = options.hudMoveModeAttribute
	canReturnToLobby = options.canReturnToLobby == true
	returnToLobbyRequestInFlight = false
	if canReturnToLobby then
		resolveReturnToLobbyRemoteAsync(function()
			if player.Parent then
				updateGameplayLabels()
			end
		end)
	else
		returnToLobbyRemote = nil
	end
	if hudMoveModeAttribute then
		playerGui:SetAttribute(hudMoveModeAttribute, false)
	end
	loadSettingsFromServer()
	updateGameplayLabels()
	updateAudioButtons()
	musicSlider.setValue(settingsState.musicVolume, false)
	sfxSlider.setValue(settingsState.sfxVolume, false)
	refreshAllSounds()
	applyHudTransforms()
end

return {
	run = run,
}