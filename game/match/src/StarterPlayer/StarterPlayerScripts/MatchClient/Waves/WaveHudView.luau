--[[
	WaveHudView — Builds the Brainrot HUD UI tree (wave timer, respawn, game over, map vote, stats, wave status).
	No remotes or game logic; returns refs for the controller to update and wire.
]]

local function createLine(parent: Frame, name: string, order: number): TextLabel
	local line = Instance.new("TextLabel")
	line.Name = name
	line.LayoutOrder = order
	line.Size = UDim2.new(1, 0, 0, 22)
	line.BackgroundTransparency = 1
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = Color3.fromRGB(220, 225, 230)
	line.Font = Enum.Font.GothamSemibold
	line.TextSize = 15
	line.Text = ""
	line.Parent = parent
	return line
end

export type MapVoteOption = {
	placeId: number,
	label: string,
	votes: number,
}

function getMapVoteButtonWidth(optionCount: number): number
	if optionCount <= 1 then return 280 end
	if optionCount == 2 then return 230 end
	if optionCount == 3 then return 200 end
	return 160
end

function clearMapVoteOptionButtons(frame: Frame): ()
	for _, child in frame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

function buildMapVoteOptionButton(
	parent: Frame,
	option: MapVoteOption,
	layoutOrder: number,
	optionCount: number,
	onActivated: () -> ()
): TextButton
	local buttonWidth = getMapVoteButtonWidth(optionCount)
	local button = Instance.new("TextButton")
	button.Name = ("Option_%d"):format(option.placeId)
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.fromOffset(buttonWidth, 112)
	button.BackgroundColor3 = Color3.fromRGB(34, 41, 52)
	button.BorderSizePixel = 0
	button.Text = ""
	button.TextWrapped = true
	button.TextYAlignment = Enum.TextYAlignment.Center
	button.TextColor3 = Color3.fromRGB(224, 232, 244)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.ZIndex = 22
	button.Parent = parent
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = button
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(98, 124, 156)
	buttonStroke.Transparency = 0.18
	buttonStroke.Thickness = 1
	buttonStroke.Parent = button
	button.Activated:Connect(onActivated)
	return button
end

function updateMapVoteButtonVisual(
	button: TextButton,
	option: MapVoteOption,
	isSelected: boolean,
	mapVoteOpen: boolean
): ()
	if mapVoteOpen then
		button.Active = true
		button.AutoButtonColor = true
	else
		button.Active = false
		button.AutoButtonColor = false
	end
	button.BackgroundColor3 = if isSelected then Color3.fromRGB(64, 108, 166) else Color3.fromRGB(34, 41, 52)
	button.TextColor3 = if isSelected then Color3.fromRGB(245, 250, 255) else Color3.fromRGB(224, 232, 244)
	local markerText = if isSelected then "\nYOUR VOTE" else ""
	button.Text = string.format("%s\nVotes: %d%s", option.label, option.votes, markerText)
end

export type ViewRefs = {
	gui: ScreenGui,
	topTimer: TextLabel,
	respawnTimer: TextLabel,
	gameOverOverlay: Frame,
	gameOverTitle: TextLabel,
	gameOverMessage: TextLabel,
	mapVotePanel: Frame,
	mapVoteHeader: TextLabel,
	mapVoteTimerLabel: TextLabel,
	mapVoteOptionsFrame: Frame,
	mapVoteStatusLabel: TextLabel,
	returnToLobbyButton: TextButton,
	returnToLobbyStatus: TextLabel,
	statsPanel: Frame,
	hpLine: TextLabel,
	moneyLine: TextLabel,
	waveLine: TextLabel,
	enemiesLine: TextLabel,
	waveStatusRoot: Frame,
	waveStatusWaveLabel: TextLabel,
	waveStatusMonstersLabel: TextLabel,
}

function build(parent: PlayerGui): ViewRefs
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrainrotHud"
	gui.ResetOnSpawn = false
	gui.Parent = parent

	local topTimer = Instance.new("TextLabel")
	topTimer.Name = "NextWaveTimer"
	topTimer.Size = UDim2.fromOffset(360, 46)
	topTimer.Position = UDim2.fromScale(0.5, 0.03)
	topTimer.AnchorPoint = Vector2.new(0.5, 0)
	topTimer.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	topTimer.BackgroundTransparency = 0.18
	topTimer.BorderSizePixel = 0
	topTimer.TextColor3 = Color3.fromRGB(245, 248, 255)
	topTimer.Font = Enum.Font.GothamBold
	topTimer.TextSize = 20
	topTimer.Text = ""
	topTimer.Visible = false
	topTimer.Parent = gui

	local topTimerCorner = Instance.new("UICorner")
	topTimerCorner.CornerRadius = UDim.new(0, 10)
	topTimerCorner.Parent = topTimer

	local topTimerStroke = Instance.new("UIStroke")
	topTimerStroke.Color = Color3.fromRGB(92, 112, 128)
	topTimerStroke.Transparency = 0.15
	topTimerStroke.Thickness = 1
	topTimerStroke.Parent = topTimer

	local respawnTimer = Instance.new("TextLabel")
	respawnTimer.Name = "RespawnTimer"
	respawnTimer.Size = UDim2.fromOffset(420, 64)
	respawnTimer.Position = UDim2.new(0.5, 0, 0, 84)
	respawnTimer.AnchorPoint = Vector2.new(0.5, 0)
	respawnTimer.BackgroundColor3 = Color3.fromRGB(25, 14, 14)
	respawnTimer.BackgroundTransparency = 0.15
	respawnTimer.BorderSizePixel = 0
	respawnTimer.TextColor3 = Color3.fromRGB(255, 230, 230)
	respawnTimer.Font = Enum.Font.GothamBold
	respawnTimer.TextSize = 24
	respawnTimer.Text = ""
	respawnTimer.Visible = false
	respawnTimer.Parent = gui

	local respawnTimerCorner = Instance.new("UICorner")
	respawnTimerCorner.CornerRadius = UDim.new(0, 12)
	respawnTimerCorner.Parent = respawnTimer

	local respawnTimerStroke = Instance.new("UIStroke")
	respawnTimerStroke.Color = Color3.fromRGB(145, 80, 80)
	respawnTimerStroke.Transparency = 0.1
	respawnTimerStroke.Thickness = 1
	respawnTimerStroke.Parent = respawnTimer

	local gameOverOverlay = Instance.new("Frame")
	gameOverOverlay.Name = "GameOverOverlay"
	gameOverOverlay.Size = UDim2.fromScale(1, 1)
	gameOverOverlay.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	gameOverOverlay.BackgroundTransparency = 0.28
	gameOverOverlay.BorderSizePixel = 0
	gameOverOverlay.Visible = false
	gameOverOverlay.ZIndex = 20
	gameOverOverlay.Parent = gui

	local gameOverTitle = Instance.new("TextLabel")
	gameOverTitle.Name = "GameOverTitle"
	gameOverTitle.Size = UDim2.fromOffset(680, 90)
	gameOverTitle.Position = UDim2.fromScale(0.5, 0.38)
	gameOverTitle.AnchorPoint = Vector2.new(0.5, 1)
	gameOverTitle.BackgroundTransparency = 1
	gameOverTitle.Text = "GAME OVER"
	gameOverTitle.TextColor3 = Color3.fromRGB(255, 112, 112)
	gameOverTitle.Font = Enum.Font.GothamBlack
	gameOverTitle.TextSize = 72
	gameOverTitle.ZIndex = 21
	gameOverTitle.Parent = gameOverOverlay

	local gameOverMessage = Instance.new("TextLabel")
	gameOverMessage.Name = "GameOverMessage"
	gameOverMessage.Size = UDim2.fromOffset(760, 80)
	gameOverMessage.Position = UDim2.fromScale(0.5, 0.4)
	gameOverMessage.AnchorPoint = Vector2.new(0.5, 0)
	gameOverMessage.BackgroundTransparency = 1
	gameOverMessage.Text = ""
	gameOverMessage.TextWrapped = true
	gameOverMessage.TextColor3 = Color3.fromRGB(245, 230, 230)
	gameOverMessage.Font = Enum.Font.GothamSemibold
	gameOverMessage.TextSize = 28
	gameOverMessage.ZIndex = 21
	gameOverMessage.Parent = gameOverOverlay

	local mapVotePanel = Instance.new("Frame")
	mapVotePanel.Name = "MapVotePanel"
	mapVotePanel.Size = UDim2.new(0.9, 0, 0, 250)
	mapVotePanel.Position = UDim2.fromScale(0.5, 0.52)
	mapVotePanel.AnchorPoint = Vector2.new(0.5, 0)
	mapVotePanel.BackgroundColor3 = Color3.fromRGB(16, 19, 25)
	mapVotePanel.BackgroundTransparency = 0.1
	mapVotePanel.BorderSizePixel = 0
	mapVotePanel.Visible = false
	mapVotePanel.ZIndex = 21
	mapVotePanel.Parent = gameOverOverlay

	local mapVotePanelSizeConstraint = Instance.new("UISizeConstraint")
	mapVotePanelSizeConstraint.MaxSize = Vector2.new(920, 260)
	mapVotePanelSizeConstraint.MinSize = Vector2.new(320, 220)
	mapVotePanelSizeConstraint.Parent = mapVotePanel

	local mapVotePanelCorner = Instance.new("UICorner")
	mapVotePanelCorner.CornerRadius = UDim.new(0, 12)
	mapVotePanelCorner.Parent = mapVotePanel

	local mapVotePanelStroke = Instance.new("UIStroke")
	mapVotePanelStroke.Color = Color3.fromRGB(100, 130, 170)
	mapVotePanelStroke.Transparency = 0.2
	mapVotePanelStroke.Thickness = 1
	mapVotePanelStroke.Parent = mapVotePanel

	local mapVoteHeader = Instance.new("TextLabel")
	mapVoteHeader.Name = "Header"
	mapVoteHeader.Size = UDim2.new(1, -32, 0, 34)
	mapVoteHeader.Position = UDim2.fromOffset(16, 12)
	mapVoteHeader.BackgroundTransparency = 1
	mapVoteHeader.Text = "MAP VOTE"
	mapVoteHeader.TextXAlignment = Enum.TextXAlignment.Left
	mapVoteHeader.TextColor3 = Color3.fromRGB(240, 245, 255)
	mapVoteHeader.Font = Enum.Font.GothamBold
	mapVoteHeader.TextSize = 24
	mapVoteHeader.ZIndex = 22
	mapVoteHeader.Parent = mapVotePanel

	local mapVoteTimerLabel = Instance.new("TextLabel")
	mapVoteTimerLabel.Name = "Timer"
	mapVoteTimerLabel.Size = UDim2.new(1, -32, 0, 26)
	mapVoteTimerLabel.Position = UDim2.fromOffset(16, 44)
	mapVoteTimerLabel.BackgroundTransparency = 1
	mapVoteTimerLabel.Text = ""
	mapVoteTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
	mapVoteTimerLabel.TextColor3 = Color3.fromRGB(180, 210, 245)
	mapVoteTimerLabel.Font = Enum.Font.GothamSemibold
	mapVoteTimerLabel.TextSize = 18
	mapVoteTimerLabel.ZIndex = 22
	mapVoteTimerLabel.Parent = mapVotePanel

	local mapVoteOptionsFrame = Instance.new("Frame")
	mapVoteOptionsFrame.Name = "Options"
	mapVoteOptionsFrame.Size = UDim2.new(1, -32, 0, 122)
	mapVoteOptionsFrame.Position = UDim2.fromOffset(16, 76)
	mapVoteOptionsFrame.BackgroundTransparency = 1
	mapVoteOptionsFrame.ZIndex = 22
	mapVoteOptionsFrame.Parent = mapVotePanel

	local mapVoteOptionsLayout = Instance.new("UIListLayout")
	mapVoteOptionsLayout.FillDirection = Enum.FillDirection.Horizontal
	mapVoteOptionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	mapVoteOptionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	mapVoteOptionsLayout.Padding = UDim.new(0, 10)
	mapVoteOptionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mapVoteOptionsLayout.Parent = mapVoteOptionsFrame

	local mapVoteStatusLabel = Instance.new("TextLabel")
	mapVoteStatusLabel.Name = "Status"
	mapVoteStatusLabel.Size = UDim2.new(1, -32, 0, 42)
	mapVoteStatusLabel.Position = UDim2.fromOffset(16, 204)
	mapVoteStatusLabel.BackgroundTransparency = 1
	mapVoteStatusLabel.Text = ""
	mapVoteStatusLabel.TextWrapped = true
	mapVoteStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	mapVoteStatusLabel.TextColor3 = Color3.fromRGB(225, 232, 244)
	mapVoteStatusLabel.Font = Enum.Font.GothamSemibold
	mapVoteStatusLabel.TextSize = 17
	mapVoteStatusLabel.ZIndex = 22
	mapVoteStatusLabel.Parent = mapVotePanel

	local returnToLobbyButton = Instance.new("TextButton")
	returnToLobbyButton.Name = "ReturnToLobbyButton"
	returnToLobbyButton.Size = UDim2.fromOffset(280, 54)
	returnToLobbyButton.Position = UDim2.fromScale(0.5, 0.83)
	returnToLobbyButton.AnchorPoint = Vector2.new(0.5, 0)
	returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(55, 90, 130)
	returnToLobbyButton.BorderSizePixel = 0
	returnToLobbyButton.Text = "Return to Lobby"
	returnToLobbyButton.TextColor3 = Color3.fromRGB(245, 250, 255)
	returnToLobbyButton.Font = Enum.Font.GothamBold
	returnToLobbyButton.TextSize = 22
	returnToLobbyButton.AutoButtonColor = true
	returnToLobbyButton.Visible = false
	returnToLobbyButton.ZIndex = 21
	returnToLobbyButton.Parent = gameOverOverlay

	local returnToLobbyButtonCorner = Instance.new("UICorner")
	returnToLobbyButtonCorner.CornerRadius = UDim.new(0, 10)
	returnToLobbyButtonCorner.Parent = returnToLobbyButton

	local returnToLobbyButtonStroke = Instance.new("UIStroke")
	returnToLobbyButtonStroke.Color = Color3.fromRGB(140, 185, 235)
	returnToLobbyButtonStroke.Transparency = 0.1
	returnToLobbyButtonStroke.Thickness = 1
	returnToLobbyButtonStroke.Parent = returnToLobbyButton

	local returnToLobbyStatus = Instance.new("TextLabel")
	returnToLobbyStatus.Name = "ReturnToLobbyStatus"
	returnToLobbyStatus.Size = UDim2.fromOffset(760, 42)
	returnToLobbyStatus.Position = UDim2.fromScale(0.5, 0.91)
	returnToLobbyStatus.AnchorPoint = Vector2.new(0.5, 0)
	returnToLobbyStatus.BackgroundTransparency = 1
	returnToLobbyStatus.Text = ""
	returnToLobbyStatus.TextWrapped = true
	returnToLobbyStatus.TextColor3 = Color3.fromRGB(220, 230, 245)
	returnToLobbyStatus.Font = Enum.Font.GothamSemibold
	returnToLobbyStatus.TextSize = 17
	returnToLobbyStatus.Visible = false
	returnToLobbyStatus.ZIndex = 21
	returnToLobbyStatus.Parent = gameOverOverlay

	local statsPanel = Instance.new("Frame")
	statsPanel.Name = "StatsPanel"
	statsPanel.Size = UDim2.fromOffset(300, 148)
	statsPanel.Position = UDim2.fromOffset(16, 16)
	statsPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	statsPanel.BackgroundTransparency = 0.2
	statsPanel.BorderSizePixel = 0
	statsPanel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = statsPanel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(65, 85, 95)
	stroke.Transparency = 0.2
	stroke.Thickness = 1
	stroke.Parent = statsPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = statsPanel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = statsPanel

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = "BRAINROT FLOOR"
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(240, 245, 250)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 16
	header.Parent = statsPanel

	local hpLine = createLine(statsPanel, "HpLine", 2)
	local moneyLine = createLine(statsPanel, "MoneyLine", 3)
	local waveLine = createLine(statsPanel, "WaveLine", 4)
	local enemiesLine = createLine(statsPanel, "EnemiesLine", 5)

	local waveStatusRoot = Instance.new("Frame")
	waveStatusRoot.Name = "WaveStatusPanel"
	waveStatusRoot.Size = UDim2.fromOffset(180, 56)
	waveStatusRoot.Position = UDim2.new(1, -196, 0, 16)
	waveStatusRoot.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	waveStatusRoot.BackgroundTransparency = 0.15
	waveStatusRoot.BorderSizePixel = 0
	waveStatusRoot.ClipsDescendants = false
	waveStatusRoot.Parent = gui

	local waveStatusCorner = Instance.new("UICorner")
	waveStatusCorner.CornerRadius = UDim.new(0, 8)
	waveStatusCorner.Parent = waveStatusRoot

	local waveStatusStroke = Instance.new("UIStroke")
	waveStatusStroke.Color = Color3.fromRGB(70, 88, 100)
	waveStatusStroke.Transparency = 0.25
	waveStatusStroke.Thickness = 1
	waveStatusStroke.Parent = waveStatusRoot

	local waveStatusPadding = Instance.new("UIPadding")
	waveStatusPadding.PaddingTop = UDim.new(0, 8)
	waveStatusPadding.PaddingBottom = UDim.new(0, 8)
	waveStatusPadding.PaddingLeft = UDim.new(0, 12)
	waveStatusPadding.PaddingRight = UDim.new(0, 12)
	waveStatusPadding.Parent = waveStatusRoot

	local waveStatusWaveLabel = Instance.new("TextLabel")
	waveStatusWaveLabel.Name = "WaveLabel"
	waveStatusWaveLabel.Size = UDim2.new(1, -24, 0, 20)
	waveStatusWaveLabel.Position = UDim2.fromOffset(0, 0)
	waveStatusWaveLabel.BackgroundTransparency = 1
	waveStatusWaveLabel.TextXAlignment = Enum.TextXAlignment.Left
	waveStatusWaveLabel.TextColor3 = Color3.fromRGB(240, 248, 255)
	waveStatusWaveLabel.Font = Enum.Font.GothamBold
	waveStatusWaveLabel.TextSize = 16
	waveStatusWaveLabel.Text = "Wave —/10"
	waveStatusWaveLabel.Parent = waveStatusRoot

	local waveStatusMonstersLabel = Instance.new("TextLabel")
	waveStatusMonstersLabel.Name = "MonstersLabel"
	waveStatusMonstersLabel.Size = UDim2.new(1, -24, 0, 20)
	waveStatusMonstersLabel.Position = UDim2.fromOffset(0, 24)
	waveStatusMonstersLabel.BackgroundTransparency = 1
	waveStatusMonstersLabel.TextXAlignment = Enum.TextXAlignment.Left
	waveStatusMonstersLabel.TextColor3 = Color3.fromRGB(200, 218, 235)
	waveStatusMonstersLabel.Font = Enum.Font.GothamSemibold
	waveStatusMonstersLabel.TextSize = 14
	waveStatusMonstersLabel.Text = "Monsters: 0"
	waveStatusMonstersLabel.Parent = waveStatusRoot

	return {
		gui = gui,
		topTimer = topTimer,
		respawnTimer = respawnTimer,
		gameOverOverlay = gameOverOverlay,
		gameOverTitle = gameOverTitle,
		gameOverMessage = gameOverMessage,
		mapVotePanel = mapVotePanel,
		mapVoteHeader = mapVoteHeader,
		mapVoteTimerLabel = mapVoteTimerLabel,
		mapVoteOptionsFrame = mapVoteOptionsFrame,
		mapVoteStatusLabel = mapVoteStatusLabel,
		returnToLobbyButton = returnToLobbyButton,
		returnToLobbyStatus = returnToLobbyStatus,
		statsPanel = statsPanel,
		hpLine = hpLine,
		moneyLine = moneyLine,
		waveLine = waveLine,
		enemiesLine = enemiesLine,
		waveStatusRoot = waveStatusRoot,
		waveStatusWaveLabel = waveStatusWaveLabel,
		waveStatusMonstersLabel = waveStatusMonstersLabel,
	}
end

return {
	build = build,
	getMapVoteButtonWidth = getMapVoteButtonWidth,
	clearMapVoteOptionButtons = clearMapVoteOptionButtons,
	buildMapVoteOptionButton = buildMapVoteOptionButton,
	updateMapVoteButtonVisual = updateMapVoteButtonVisual,
}
