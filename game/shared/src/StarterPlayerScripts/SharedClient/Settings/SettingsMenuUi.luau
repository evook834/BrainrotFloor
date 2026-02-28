local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

export type View = {
	gui: ScreenGui,
	launcher: Frame,
	launcherGear: TextButton,
	launcherLabel: TextLabel,
	friendLauncherButton: TextButton,

	panel: Frame,
	panelTitle: TextLabel,
	panelClose: TextButton,

	audioTabButton: TextButton,
	gameplayTabButton: TextButton,

	content: Frame,
	audioPage: Frame,
	gameplayPage: Frame,

	-- Audio page
	musicRow: Frame,
	musicSliderBackground: Frame,
	musicSliderFill: Frame,
	musicSliderKnob: Frame,
	musicValueLabel: TextLabel,
	musicMinusButton: TextButton,
	musicPlusButton: TextButton,
	musicMuteButton: TextButton,

	sfxRow: Frame,
	sfxSliderBackground: Frame,
	sfxSliderFill: Frame,
	sfxSliderKnob: Frame,
	sfxValueLabel: TextLabel,
	sfxMinusButton: TextButton,
	sfxPlusButton: TextButton,
	sfxMuteButton: TextButton,

	audioHint: TextLabel,

	-- Gameplay page
	moveModeButton: TextButton,
	moveStatusLabel: TextLabel,
	selectedHudLabel: TextLabel,

	returnToLobbyButton: TextButton,
	returnToLobbyStatusLabel: TextLabel,

	resetPositionButton: TextButton,

	hudScaleLabel: TextLabel,
	hudScaleDownButton: TextButton,
	hudScaleUpButton: TextButton,
	resetScaleButton: TextButton,

	fullHideButton: TextButton,
	fullHideStatusLabel: TextLabel,

	gameplayHint: TextLabel,
}

local SETTINGS_GUI_NAME = "MatchSettingsUi"
local GEAR_ICON = utf8.char(0x2699)

local existingGui = playerGui:FindFirstChild(SETTINGS_GUI_NAME)
if existingGui then
	existingGui:Destroy()
end

local function styleRounded(container: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = container
	return corner
end

local function styleStroke(container: GuiObject, color: Color3, transparency: number, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = container
	return stroke
end

local function createSlider(
	parent: Instance,
	name: string,
	labelText: string,
	offsetY: number
): (
	Frame,
	Frame,
	Frame,
	Frame,
	TextLabel,
	TextButton,
	TextButton
)
	local row = Instance.new("Frame")
	row.Name = name
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
	label.Font = Enum.Font.Gotham
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

	return row, sliderBackground, sliderFill, sliderKnob, valueLabel, minusButton, plusButton
end

local function build(): View
	local gui = Instance.new("ScreenGui")
	gui.Name = SETTINGS_GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = playerGui

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
	launcherLabel.Font = Enum.Font.Gotham
	launcherLabel.TextSize = 18
	launcherLabel.Parent = launcher

	local friendLauncherButton = Instance.new("TextButton")
	friendLauncherButton.Name = "FriendLauncherButton"
	friendLauncherButton.Size = UDim2.fromOffset(146, 32)
	friendLauncherButton.Position = UDim2.new(0, 12, 0.5, 124)
	friendLauncherButton.BackgroundColor3 = Color3.fromRGB(45, 101, 98)
	friendLauncherButton.BorderSizePixel = 0
	friendLauncherButton.Text = "Friend List"
	friendLauncherButton.TextColor3 = Color3.fromRGB(238, 249, 246)
	friendLauncherButton.Font = Enum.Font.GothamBold
	friendLauncherButton.TextSize = 13
	friendLauncherButton.Parent = gui
	styleRounded(friendLauncherButton, 8)
	styleStroke(friendLauncherButton, Color3.fromRGB(88, 130, 126), 0.28, 1)

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.Size = UDim2.fromOffset(400, 400)
	panel.Position = UDim2.new(0, 66, 0.5, -200)
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

	local musicRow, musicSliderBackground, musicSliderFill, musicSliderKnob, musicValueLabel, musicMinusButton, musicPlusButton =
		createSlider(audioPage, "MusicRow", "Music Volume", 10)

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

	local sfxRow, sfxSliderBackground, sfxSliderFill, sfxSliderKnob, sfxValueLabel, sfxMinusButton, sfxPlusButton =
		createSlider(audioPage, "SfxRow", "SFX / Effects Volume", 130)

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
	moveStatusLabel.Font = Enum.Font.Gotham
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
	hudScaleLabel.Font = Enum.Font.Gotham
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
	gameplayHint.Text = "Move mode: left-click one HUD element and drag it (or long-press on touch). Only that UI moves."
	gameplayHint.TextWrapped = true
	gameplayHint.TextXAlignment = Enum.TextXAlignment.Left
	gameplayHint.TextYAlignment = Enum.TextYAlignment.Top
	gameplayHint.TextColor3 = Color3.fromRGB(178, 192, 210)
	gameplayHint.Font = Enum.Font.Gotham
	gameplayHint.TextSize = 12
	gameplayHint.Parent = gameplayPage

	return {
		gui = gui,
		launcher = launcher,
		launcherGear = launcherGear,
		launcherLabel = launcherLabel,
		friendLauncherButton = friendLauncherButton,

		panel = panel,
		panelTitle = panelTitle,
		panelClose = panelClose,

		audioTabButton = audioTabButton,
		gameplayTabButton = gameplayTabButton,

		content = content,
		audioPage = audioPage,
		gameplayPage = gameplayPage,

		musicRow = musicRow,
		musicSliderBackground = musicSliderBackground,
		musicSliderFill = musicSliderFill,
		musicSliderKnob = musicSliderKnob,
		musicValueLabel = musicValueLabel,
		musicMinusButton = musicMinusButton,
		musicPlusButton = musicPlusButton,
		musicMuteButton = musicMuteButton,

		sfxRow = sfxRow,
		sfxSliderBackground = sfxSliderBackground,
		sfxSliderFill = sfxSliderFill,
		sfxSliderKnob = sfxSliderKnob,
		sfxValueLabel = sfxValueLabel,
		sfxMinusButton = sfxMinusButton,
		sfxPlusButton = sfxPlusButton,
		sfxMuteButton = sfxMuteButton,

		audioHint = audioHint,

		moveModeButton = moveModeButton,
		moveStatusLabel = moveStatusLabel,
		selectedHudLabel = selectedHudLabel,

		returnToLobbyButton = returnToLobbyButton,
		returnToLobbyStatusLabel = returnToLobbyStatusLabel,

		resetPositionButton = resetPositionButton,

		hudScaleLabel = hudScaleLabel,
		hudScaleDownButton = hudScaleDownButton,
		hudScaleUpButton = hudScaleUpButton,
		resetScaleButton = resetScaleButton,

		fullHideButton = fullHideButton,
		fullHideStatusLabel = fullHideStatusLabel,

		gameplayHint = gameplayHint,
	}
end

return {
	build = build,
}

