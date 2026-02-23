local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

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

local frame = Instance.new("Frame")
frame.Name = "StatsPanel"
frame.Size = UDim2.fromOffset(300, 148)
frame.Position = UDim2.fromOffset(16, 16)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(65, 85, 95)
stroke.Transparency = 0.2
stroke.Thickness = 1
stroke.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = frame

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
header.Parent = frame

local function createLine(name, order)
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
	line.Parent = frame
	return line
end

local hpLine = createLine("HpLine", 2)
local moneyLine = createLine("MoneyLine", 3)
local waveLine = createLine("WaveLine", 4)
local enemiesLine = createLine("EnemiesLine", 5)

local uiState = {
	hp = 100,
	maxHp = 100,
	money = 0,
	wave = 0,
	waveState = "Waiting",
	livingEnemies = 0,
}
local intermissionCountdownState = {
	token = 0,
}
local respawnCountdownState = {
	token = 0,
}
local mapVoteCountdownState = {
	token = 0,
}

local gameOverActive = false
local returnToLobbyRequested = false
local returnToLobbyRequestToken = 0
local gameOverMouseUnlockConnection = nil
local savedCameraMode = nil

local returnToLobbyRemote = nil
local mapVoteRemote = nil

local mapVoteOpen = false
local mapVoteOptions = {}
local mapVoteButtonsByPlaceId = {}
local mapVoteSelectedPlaceId = nil

local function render()
	hpLine.Text = string.format("HP: %d / %d", math.max(0, math.floor(uiState.hp + 0.5)), math.max(1, math.floor(uiState.maxHp + 0.5)))
	moneyLine.Text = string.format("Money: $%d", math.floor(uiState.money + 0.5))
	waveLine.Text = string.format("Wave: %d (%s)", uiState.wave, uiState.waveState)
	enemiesLine.Text = string.format("Living Enemies: %d", uiState.livingEnemies)
end

render()

local function beginCountdown(countdownState)
	countdownState.token += 1
	return countdownState.token
end

local function isCountdownActive(countdownState, token)
	return token == countdownState.token
end

local function cancelCountdown(countdownState, label)
	beginCountdown(countdownState)
	label.Visible = false
	label.Text = ""
end

local function cancelMapVoteCountdown()
	beginCountdown(mapVoteCountdownState)
end

local function normalizePlaceId(value)
	local placeId = tonumber(value)
	if placeId == nil then
		return nil
	end

	if placeId ~= math.floor(placeId) then
		return nil
	end

	if placeId <= 0 then
		return nil
	end

	return placeId
end

local function normalizeMapVoteOptions(rawOptions)
	local normalized = {}
	if type(rawOptions) ~= "table" then
		return normalized
	end

	for _, rawOption in ipairs(rawOptions) do
		if type(rawOption) == "table" then
			local placeId = normalizePlaceId(rawOption.placeId)
			if placeId ~= nil then
				local label = rawOption.label
				if type(label) ~= "string" or label == "" then
					label = ("Map %d"):format(#normalized + 1)
				end

				local votes = math.max(0, math.floor(tonumber(rawOption.votes) or 0))
				table.insert(normalized, {
					placeId = placeId,
					label = label,
					votes = votes,
				})
			end
		end
	end

	return normalized
end

local function formatMapVoteTimerText(endsAt)
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return "Vote ends soon"
	end

	local remaining = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
	return string.format("Vote ends in %02ds", remaining)
end

local function computeVoteButtonWidth(optionCount)
	if optionCount <= 1 then
		return 280
	end

	if optionCount == 2 then
		return 230
	end

	if optionCount == 3 then
		return 200
	end

	return 160
end

local function clearMapVoteButtons()
	for _, child in ipairs(mapVoteOptionsFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	mapVoteButtonsByPlaceId = {}
end

local function refreshMapVoteButtonVisual(button, option)
	if mapVoteOpen then
		button.Active = true
		button.AutoButtonColor = true
	else
		button.Active = false
		button.AutoButtonColor = false
	end

	local isSelected = mapVoteSelectedPlaceId == option.placeId
	button.BackgroundColor3 = if isSelected then Color3.fromRGB(64, 108, 166) else Color3.fromRGB(34, 41, 52)
	button.TextColor3 = if isSelected then Color3.fromRGB(245, 250, 255) else Color3.fromRGB(224, 232, 244)

	local markerText = if isSelected then "\nYOUR VOTE" else ""
	button.Text = string.format("%s\nVotes: %d%s", option.label, option.votes, markerText)
end

local function updateMapVoteButtons()
	for _, option in ipairs(mapVoteOptions) do
		local button = mapVoteButtonsByPlaceId[option.placeId]
		if button then
			refreshMapVoteButtonVisual(button, option)
		end
	end
end

local function renderMapVoteOptions()
	clearMapVoteButtons()

	local optionCount = #mapVoteOptions
	if optionCount <= 0 then
		mapVoteStatusLabel.Text = "No map options available."
		return
	end

	local buttonWidth = computeVoteButtonWidth(optionCount)
	for index, option in ipairs(mapVoteOptions) do
		local placeId = option.placeId
		local label = option.label

		local button = Instance.new("TextButton")
		button.Name = ("Option_%d"):format(placeId)
		button.LayoutOrder = index
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
		button.Parent = mapVoteOptionsFrame

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 10)
		buttonCorner.Parent = button

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(98, 124, 156)
		buttonStroke.Transparency = 0.18
		buttonStroke.Thickness = 1
		buttonStroke.Parent = button

		button.Activated:Connect(function()
			if not mapVoteOpen or not mapVoteRemote or not gameOverActive then
				return
			end

			mapVoteSelectedPlaceId = placeId
			updateMapVoteButtons()
			mapVoteStatusLabel.Text = string.format("You voted for %s.", label)
			mapVoteRemote:FireServer({
				placeId = placeId,
			})
		end)

		mapVoteButtonsByPlaceId[placeId] = button
		refreshMapVoteButtonVisual(button, option)
	end
end

local function startMapVoteCountdown(endsAt)
	local activeToken = beginCountdown(mapVoteCountdownState)
	mapVoteTimerLabel.Text = formatMapVoteTimerText(endsAt)

	task.spawn(function()
		while isCountdownActive(mapVoteCountdownState, activeToken) do
			if not mapVoteOpen then
				break
			end

			mapVoteTimerLabel.Text = formatMapVoteTimerText(endsAt)
			if type(endsAt) == "number" and endsAt > 0 then
				local remaining = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
				if remaining <= 0 then
					break
				end
			end

			task.wait(0.15)
		end
	end)
end

local function resetMapVoteUi()
	mapVoteOpen = false
	mapVoteOptions = {}
	mapVoteSelectedPlaceId = nil
	cancelMapVoteCountdown()
	clearMapVoteButtons()
	mapVotePanel.Visible = false
	mapVoteTimerLabel.Text = ""
	mapVoteStatusLabel.Text = ""
end

local function startIntermissionCountdown(seconds, waveNumber, intermissionEndsAt)
	local activeToken = beginCountdown(intermissionCountdownState)

	task.spawn(function()
		local fallbackRemaining = math.max(0, math.floor(seconds or 0))
		local useServerEndTime = type(intermissionEndsAt) == "number" and intermissionEndsAt > 0

		topTimer.Visible = true
		while isCountdownActive(intermissionCountdownState, activeToken) do
			local remaining
			if useServerEndTime then
				remaining = math.max(0, math.ceil(intermissionEndsAt - Workspace:GetServerTimeNow()))
			else
				remaining = fallbackRemaining
			end

			topTimer.Text = string.format("Wave %d starts in %02ds", waveNumber, remaining)
			if remaining <= 0 then
				break
			end

			if useServerEndTime then
				task.wait(0.15)
			else
				task.wait(1)
				fallbackRemaining -= 1
			end
		end
	end)
end

local function hideCountdown()
	cancelCountdown(intermissionCountdownState, topTimer)
end

local function startRespawnCountdown(seconds)
	local activeToken = beginCountdown(respawnCountdownState)
	local remaining = math.max(0, math.floor(seconds or 0))

	task.spawn(function()
		respawnTimer.Visible = true
		while isCountdownActive(respawnCountdownState, activeToken) and remaining >= 0 do
			respawnTimer.Text = string.format("You died - respawning in %02ds", remaining)
			if remaining <= 0 then
				break
			end

			task.wait(1)
			remaining -= 1
		end

		if isCountdownActive(respawnCountdownState, activeToken) then
			respawnTimer.Text = "Respawning..."
		end
	end)
end

local function hideRespawnCountdown()
	cancelCountdown(respawnCountdownState, respawnTimer)
end

local function getGameOverMessage(reason)
	if reason == "AllPlayersDead" then
		return "All players were eliminated at the same time. Respawning is disabled."
	end

	return "The match has ended."
end

local function setReturnToLobbyButtonEnabled(enabled, text)
	returnToLobbyButton.Active = enabled
	returnToLobbyButton.AutoButtonColor = enabled
	returnToLobbyButton.BackgroundTransparency = enabled and 0 or 0.35
	returnToLobbyButton.Text = text
end

local function stopGameOverMouseUnlockLoop()
	if gameOverMouseUnlockConnection then
		gameOverMouseUnlockConnection:Disconnect()
		gameOverMouseUnlockConnection = nil
	end
end

local function startGameOverMouseUnlockLoop()
	stopGameOverMouseUnlockLoop()
	gameOverMouseUnlockConnection = RunService.RenderStepped:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

local function setGameOverInputModeActive(active)
	if active then
		if savedCameraMode == nil then
			savedCameraMode = player.CameraMode
		end

		player.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		startGameOverMouseUnlockLoop()
		return
	end

	stopGameOverMouseUnlockLoop()
	if savedCameraMode ~= nil then
		player.CameraMode = savedCameraMode
		savedCameraMode = nil
	end
end

local function setGameOverActive(active, reason)
	gameOverActive = active
	gameOverOverlay.Visible = active
	setGameOverInputModeActive(active)

	if active then
		hideCountdown()
		hideRespawnCountdown()
		resetMapVoteUi()
		gameOverMessage.Text = getGameOverMessage(reason)
		returnToLobbyButton.Visible = true
		returnToLobbyStatus.Visible = true
		returnToLobbyStatus.Text = ""
		returnToLobbyRequested = false
		returnToLobbyRequestToken += 1

		if returnToLobbyRemote then
			setReturnToLobbyButtonEnabled(true, "Return to Lobby")
		else
			setReturnToLobbyButtonEnabled(false, "Lobby Unavailable")
			returnToLobbyStatus.Text = "Lobby teleport remote is unavailable."
		end

		return
	end

	gameOverMessage.Text = ""
	returnToLobbyButton.Visible = false
	returnToLobbyStatus.Visible = false
	returnToLobbyStatus.Text = ""
	returnToLobbyRequested = false
	returnToLobbyRequestToken += 1
	setReturnToLobbyButtonEnabled(false, "Return to Lobby")
	resetMapVoteUi()
end

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
if not remotesFolder then
	warn("WaveHud could not find ReplicatedStorage/Remotes")
end

local waveStateRemote = remotesFolder and remotesFolder:WaitForChild(Config.Remotes.WaveState, 15) or nil
if not waveStateRemote then
	warn("WaveHud could not find ReplicatedStorage/Remotes/WaveState")
end

local returnToLobbyRemoteCandidate = remotesFolder and remotesFolder:WaitForChild(Config.Remotes.ReturnToLobby, 15) or nil
if returnToLobbyRemoteCandidate and returnToLobbyRemoteCandidate:IsA("RemoteEvent") then
	returnToLobbyRemote = returnToLobbyRemoteCandidate
elseif returnToLobbyRemoteCandidate then
	warn("WaveHud found ReturnToLobby remote with unexpected class")
else
	warn("WaveHud could not find ReplicatedStorage/Remotes/ReturnToLobby")
end

local mapVoteRemoteCandidate = remotesFolder and remotesFolder:WaitForChild(Config.Remotes.MapVote, 15) or nil
if mapVoteRemoteCandidate and mapVoteRemoteCandidate:IsA("RemoteEvent") then
	mapVoteRemote = mapVoteRemoteCandidate
elseif mapVoteRemoteCandidate then
	warn("WaveHud found MapVote remote with unexpected class")
else
	warn("WaveHud could not find ReplicatedStorage/Remotes/MapVote")
end

local function requestReturnToLobby()
	if not gameOverActive then
		return
	end

	if not returnToLobbyRemote then
		returnToLobbyStatus.Text = "Lobby teleport is unavailable."
		setReturnToLobbyButtonEnabled(false, "Lobby Unavailable")
		return
	end

	if returnToLobbyRequested then
		return
	end

	returnToLobbyRequested = true
	returnToLobbyRequestToken += 1
	local activeRequestToken = returnToLobbyRequestToken
	returnToLobbyStatus.Text = "Returning you to lobby..."
	setReturnToLobbyButtonEnabled(false, "Returning...")
	returnToLobbyRemote:FireServer()

	task.delay(8, function()
		if not gameOverActive then
			return
		end

		if not returnToLobbyRequested then
			return
		end

		if returnToLobbyRequestToken ~= activeRequestToken then
			return
		end

		returnToLobbyRequested = false
		returnToLobbyStatus.Text = "Teleport did not complete. Press again to retry."
		setReturnToLobbyButtonEnabled(true, "Return to Lobby")
	end)
end

returnToLobbyButton.Activated:Connect(requestReturnToLobby)

local function applyMapVotePayload(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if not gameOverActive then
		return
	end

	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	if action == "Start" then
		mapVoteOptions = normalizeMapVoteOptions(payload.options)
		mapVoteOpen = true
		mapVotePanel.Visible = true
		mapVoteSelectedPlaceId = nil
		mapVoteHeader.Text = "MAP VOTE"
		mapVoteStatusLabel.Text = "Choose the next map."
		renderMapVoteOptions()
		startMapVoteCountdown(payload.endsAt)
		return
	end

	if action == "Update" then
		mapVoteOptions = normalizeMapVoteOptions(payload.options)
		if mapVotePanel.Visible then
			renderMapVoteOptions()
		end
		if mapVoteOpen then
			mapVoteTimerLabel.Text = formatMapVoteTimerText(payload.endsAt)
		end
		return
	end

	if action == "End" then
		mapVoteOptions = normalizeMapVoteOptions(payload.options)
		mapVoteOpen = false
		cancelMapVoteCountdown()
		mapVotePanel.Visible = true
		renderMapVoteOptions()
		mapVoteTimerLabel.Text = "Voting closed"

		local selectedLabel = payload.selectedLabel
		if type(selectedLabel) ~= "string" or selectedLabel == "" then
			selectedLabel = "next map"
		end

		if payload.wasTie == true then
			mapVoteStatusLabel.Text = string.format("Winner: %s (random tie-break).", selectedLabel)
		else
			mapVoteStatusLabel.Text = string.format("Winner: %s.", selectedLabel)
		end
		return
	end

	if action == "Teleporting" then
		mapVoteOpen = false
		cancelMapVoteCountdown()
		mapVotePanel.Visible = true
		mapVoteTimerLabel.Text = "Teleporting..."

		local selectedLabel = payload.selectedLabel
		if type(selectedLabel) ~= "string" or selectedLabel == "" then
			selectedLabel = "selected map"
		end

		local difficultyLabel = payload.difficulty
		if type(difficultyLabel) == "string" and difficultyLabel ~= "" then
			mapVoteStatusLabel.Text = string.format("Loading %s (%s difficulty)...", selectedLabel, difficultyLabel)
		else
			mapVoteStatusLabel.Text = string.format("Loading %s...", selectedLabel)
		end
		updateMapVoteButtons()
	end
end

local function applyWaveState(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local stateName = payload.state
	if gameOverActive and stateName ~= "GameOver" then
		return
	end

	uiState.wave = payload.wave or uiState.wave
	uiState.waveState = stateName or uiState.waveState
	render()

	if stateName == "GameOver" then
		setGameOverActive(true, payload.reason)
		return
	end

	setGameOverActive(false)

	if stateName == "Preparing" then
		startIntermissionCountdown(
			payload.intermission or Config.Wave.IntermissionSeconds,
			uiState.wave,
			payload.intermissionEndsAt
		)
	else
		hideCountdown()
	end
end

local function bindCharacter(character)
	hideRespawnCountdown()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local function updateHp()
		uiState.hp = humanoid.Health
		uiState.maxHp = humanoid.MaxHealth
		render()
	end

	updateHp()
	humanoid.HealthChanged:Connect(updateHp)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHp)
	humanoid.Died:Connect(function()
		if gameOverActive then
			return
		end

		startRespawnCountdown((Config.Player and Config.Player.RespawnDelaySeconds) or 60)
	end)
end

local function bindMoney()
	local leaderstats = player:WaitForChild("leaderstats", 15)
	if not leaderstats then
		return
	end

	local moneyValue = leaderstats:FindFirstChild("Money") or leaderstats:WaitForChild("Money", 15)
	if not moneyValue then
		return
	end

	local function updateMoney()
		uiState.money = moneyValue.Value
		render()
	end

	updateMoney()
	moneyValue:GetPropertyChangedSignal("Value"):Connect(updateMoney)
end

local function updateEnemyCount()
	local enemyContainer = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if not enemyContainer then
		uiState.livingEnemies = 0
		render()
		return
	end

	local count = 0
	for _, child in enemyContainer:GetChildren() do
		if child:IsA("Model") then
			count += 1
		end
	end

	uiState.livingEnemies = count
	render()
end

local function bindEnemyContainer()
	local enemyContainer = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if not enemyContainer then
		Workspace.ChildAdded:Connect(function(child)
			if child.Name == Config.Enemy.ContainerName then
				updateEnemyCount()
				child.ChildAdded:Connect(updateEnemyCount)
				child.ChildRemoved:Connect(updateEnemyCount)
			end
		end)
		return
	end

	updateEnemyCount()
	enemyContainer.ChildAdded:Connect(updateEnemyCount)
	enemyContainer.ChildRemoved:Connect(updateEnemyCount)
end

if waveStateRemote then
	waveStateRemote.OnClientEvent:Connect(applyWaveState)
end

if mapVoteRemote then
	mapVoteRemote.OnClientEvent:Connect(applyMapVotePayload)
end

if remotesFolder then
	local snapshotState = remotesFolder:GetAttribute("CurrentWaveState")
	local snapshotWave = remotesFolder:GetAttribute("CurrentWaveNumber")
	local intermissionEndTime = remotesFolder:GetAttribute("IntermissionEndTime")
	if type(snapshotState) == "string" then
		applyWaveState({
			state = snapshotState,
			wave = snapshotWave,
			intermission = Config.Wave.IntermissionSeconds,
			intermissionEndsAt = intermissionEndTime,
		})
	end
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

task.spawn(bindMoney)
bindEnemyContainer()
