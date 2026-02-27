--[[
	WaveHudController — Wave/game-over HUD logic: WaveState remote, attributes, HP/money/enemies,
	map vote, return to lobby. Updates WaveHudView refs. No UI construction.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local TeleportLoading = require(SharedClient:WaitForChild("TeleportLoading"):WaitForChild("TeleportLoading"))
local WaveHudView = require(script.Parent.WaveHudView)

local Config = require(ReplicatedStorage.Shared.GameConfig)

type CountdownState = { token: number }

type MapVoteOption = {
	placeId: number,
	label: string,
	votes: number,
}

type UiState = {
	hp: number,
	maxHp: number,
	money: number,
	wave: number,
	waveState: string,
	livingEnemies: number,
	enemiesRemaining: number,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local existingGui = playerGui:FindFirstChild("BrainrotHud")
if existingGui then
	existingGui:Destroy()
end

local refs = WaveHudView.build(playerGui)

local uiState: UiState = {
	hp = 100,
	maxHp = 100,
	money = 0,
	wave = 0,
	waveState = "Waiting",
	livingEnemies = 0,
	enemiesRemaining = 0,
}

local intermissionCountdownState: CountdownState = { token = 0 }
local respawnCountdownState: CountdownState = { token = 0 }
local mapVoteCountdownState: CountdownState = { token = 0 }

local gameOverActive = false
local returnToLobbyRequested = false
local returnToLobbyRequestToken = 0
local gameOverMouseUnlockConnection: RBXScriptConnection? = nil
local savedCameraMode: Enum.CameraMode? = nil
local hiddenScreenGuiEnabledStates: { [ScreenGui]: boolean } = {}
local gameOverHudVisibilityConnection: RBXScriptConnection? = nil

local returnToLobbyRemote: RemoteEvent? = nil
local mapVoteRemote: RemoteEvent? = nil

local mapVoteOpen = false
local mapVoteOptions: { MapVoteOption } = {}
local mapVoteButtonsByPlaceId: { [number]: TextButton } = {}
local mapVoteSelectedPlaceId: number? = nil

local totalWaves = math.max(1, tonumber(Config.Wave and Config.Wave.TotalWaves) or 10)
local bossWaveNumber = math.max(2, tonumber(Config.Wave and Config.Wave.BossWaveNumber) or 11)

local function beginCountdown(countdownState: CountdownState): number
	countdownState.token += 1
	return countdownState.token
end

local function isCountdownActive(countdownState: CountdownState, token: number): boolean
	return token == countdownState.token
end

local function cancelCountdown(countdownState: CountdownState, label: TextLabel)
	beginCountdown(countdownState)
	label.Visible = false
	label.Text = ""
end

local function cancelMapVoteCountdown()
	beginCountdown(mapVoteCountdownState)
end

local function normalizePlaceId(value: any): number?
	local placeId = tonumber(value)
	if placeId == nil then return nil end
	if placeId ~= math.floor(placeId) then return nil end
	if placeId <= 0 then return nil end
	return placeId
end

local function normalizeMapVoteOptions(rawOptions: any): { MapVoteOption }
	local normalized: { MapVoteOption } = {}
	if type(rawOptions) ~= "table" then return normalized end
	for _, rawOption in ipairs(rawOptions) do
		if type(rawOption) == "table" then
			local placeId = normalizePlaceId(rawOption.placeId)
			if placeId ~= nil then
				local label = rawOption.label
				if type(label) ~= "string" or label == "" then
					label = ("Map %d"):format(#normalized + 1)
				end
				local votes = math.max(0, math.floor(tonumber(rawOption.votes) or 0))
				table.insert(normalized, { placeId = placeId, label = label, votes = votes })
			end
		end
	end
	return normalized
end

local function formatMapVoteTimerText(endsAt: number?): string
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return "Vote ends soon"
	end
	local remaining = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
	return string.format("Vote ends in %02ds", remaining)
end

local function computeVoteButtonWidth(optionCount: number): number
	if optionCount <= 1 then return 280 end
	if optionCount == 2 then return 230 end
	if optionCount == 3 then return 200 end
	return 160
end

local function clearMapVoteButtons()
	for _, child in refs.mapVoteOptionsFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	mapVoteButtonsByPlaceId = {}
end

local function refreshMapVoteButtonVisual(button: TextButton, option: MapVoteOption)
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
	if #mapVoteOptions <= 0 then
		refs.mapVoteStatusLabel.Text = "No map options available."
		return
	end
	local buttonWidth = computeVoteButtonWidth(#mapVoteOptions)
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
		button.Parent = refs.mapVoteOptionsFrame
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 10)
		buttonCorner.Parent = button
		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(98, 124, 156)
		buttonStroke.Transparency = 0.18
		buttonStroke.Thickness = 1
		buttonStroke.Parent = button
		button.Activated:Connect(function()
			if not mapVoteOpen or not mapVoteRemote or not gameOverActive then return end
			mapVoteSelectedPlaceId = placeId
			updateMapVoteButtons()
			refs.mapVoteStatusLabel.Text = string.format("You voted for %s.", label)
			mapVoteRemote:FireServer({ placeId = placeId })
		end)
		mapVoteButtonsByPlaceId[placeId] = button
		refreshMapVoteButtonVisual(button, option)
	end
end

local function resetMapVoteUi()
	mapVoteOpen = false
	mapVoteOptions = {}
	mapVoteSelectedPlaceId = nil
	cancelMapVoteCountdown()
	clearMapVoteButtons()
	refs.mapVotePanel.Visible = false
	refs.mapVoteTimerLabel.Text = ""
	refs.mapVoteStatusLabel.Text = ""
end

local function startMapVoteCountdown(endsAt: number?)
	local activeToken = beginCountdown(mapVoteCountdownState)
	refs.mapVoteTimerLabel.Text = formatMapVoteTimerText(endsAt)
	task.spawn(function()
		while isCountdownActive(mapVoteCountdownState, activeToken) do
			if not mapVoteOpen then break end
			refs.mapVoteTimerLabel.Text = formatMapVoteTimerText(endsAt)
			if type(endsAt) == "number" and endsAt > 0 then
				local remaining = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
				if remaining <= 0 then break end
			end
			task.wait(0.15)
		end
	end)
end

local function startIntermissionCountdown(seconds: number?, waveNumber: number, intermissionEndsAt: number?)
	local activeToken = beginCountdown(intermissionCountdownState)
	local fallbackRemaining = math.max(0, math.floor(seconds or 0))
	local useServerEndTime = type(intermissionEndsAt) == "number" and intermissionEndsAt > 0
	refs.topTimer.Visible = true
	task.spawn(function()
		while isCountdownActive(intermissionCountdownState, activeToken) do
			local remaining
			if useServerEndTime then
				remaining = math.max(0, math.ceil(intermissionEndsAt - Workspace:GetServerTimeNow()))
			else
				remaining = fallbackRemaining
			end
			refs.topTimer.Text = string.format("Wave %d starts in %02ds", waveNumber, remaining)
			if remaining <= 0 then break end
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
	cancelCountdown(intermissionCountdownState, refs.topTimer)
end

local function startRespawnCountdown(seconds: number)
	local activeToken = beginCountdown(respawnCountdownState)
	local remaining = math.max(0, math.floor(seconds or 0))
	refs.respawnTimer.Visible = true
	task.spawn(function()
		while isCountdownActive(respawnCountdownState, activeToken) and remaining >= 0 do
			refs.respawnTimer.Text = string.format("You died - respawning in %02ds", remaining)
			if remaining <= 0 then break end
			task.wait(1)
			remaining -= 1
		end
		if isCountdownActive(respawnCountdownState, activeToken) then
			refs.respawnTimer.Text = "Respawning..."
		end
	end)
end

local function hideRespawnCountdown()
	cancelCountdown(respawnCountdownState, refs.respawnTimer)
end

local function getGameOverMessage(reason: string?): string
	if reason == "AllPlayersDead" then
		return "All players were eliminated at the same time. Respawning is disabled."
	end
	return "The match has ended."
end

local function getWinMessage(reason: string?): string
	if reason == "BossDefeated" then
		return "Boss defeated. Choose the next map."
	end
	return "You won!"
end

local function setReturnToLobbyButtonEnabled(enabled: boolean, text: string)
	refs.returnToLobbyButton.Active = enabled
	refs.returnToLobbyButton.AutoButtonColor = enabled
	refs.returnToLobbyButton.BackgroundTransparency = enabled and 0 or 0.35
	refs.returnToLobbyButton.Text = text
end

local function hideScreenGuiForGameOver(screenGui: ScreenGui)
	if screenGui == refs.gui then return end
	if hiddenScreenGuiEnabledStates[screenGui] == nil then
		hiddenScreenGuiEnabledStates[screenGui] = screenGui.Enabled
	end
	screenGui.Enabled = false
end

local function restoreHiddenScreenGuis()
	for screenGui, wasEnabled in pairs(hiddenScreenGuiEnabledStates) do
		if screenGui.Parent == playerGui then
			screenGui.Enabled = wasEnabled
		end
		hiddenScreenGuiEnabledStates[screenGui] = nil
	end
end

local function stopGameOverHudVisibilityLoop(restoreGuis: boolean)
	if gameOverHudVisibilityConnection then
		gameOverHudVisibilityConnection:Disconnect()
		gameOverHudVisibilityConnection = nil
	end
	if restoreGuis then
		restoreHiddenScreenGuis()
	end
end

local function startGameOverHudVisibilityLoop()
	stopGameOverHudVisibilityLoop(false)
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") then
			hideScreenGuiForGameOver(child)
		end
	end
	gameOverHudVisibilityConnection = playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			hideScreenGuiForGameOver(child)
		end
	end)
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

local function setGameOverInputModeActive(active: boolean)
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

local function setGameOverActive(active: boolean, reason: string?, isWin: boolean)
	gameOverActive = active
	refs.gameOverOverlay.Visible = active
	setGameOverInputModeActive(active)
	if active then
		refs.gui.Enabled = true
		hideCountdown()
		hideRespawnCountdown()
		resetMapVoteUi()
		refs.statsPanel.Visible = false
		startGameOverHudVisibilityLoop()
		if isWin then
			refs.gameOverTitle.Text = "You won!"
			refs.gameOverTitle.TextColor3 = Color3.fromRGB(112, 255, 160)
			refs.gameOverMessage.Text = getWinMessage(reason)
		else
			refs.gameOverTitle.Text = "GAME OVER"
			refs.gameOverTitle.TextColor3 = Color3.fromRGB(255, 112, 112)
			refs.gameOverMessage.Text = getGameOverMessage(reason)
		end
		refs.returnToLobbyButton.Visible = true
		refs.returnToLobbyStatus.Visible = true
		refs.returnToLobbyStatus.Text = ""
		returnToLobbyRequested = false
		returnToLobbyRequestToken += 1
		if returnToLobbyRemote then
			setReturnToLobbyButtonEnabled(true, "Return to Lobby")
		else
			setReturnToLobbyButtonEnabled(false, "Lobby Unavailable")
			refs.returnToLobbyStatus.Text = "Lobby teleport remote is unavailable."
		end
		return
	end
	stopGameOverHudVisibilityLoop(true)
	refs.statsPanel.Visible = true
	refs.gameOverMessage.Text = ""
	refs.returnToLobbyButton.Visible = false
	refs.returnToLobbyStatus.Visible = false
	refs.returnToLobbyStatus.Text = ""
	returnToLobbyRequested = false
	returnToLobbyRequestToken += 1
	setReturnToLobbyButtonEnabled(false, "Return to Lobby")
	resetMapVoteUi()
end

local function render()
	refs.hpLine.Text = string.format("HP: %d / %d", math.max(0, math.floor(uiState.hp + 0.5)), math.max(1, math.floor(uiState.maxHp + 0.5)))
	refs.moneyLine.Text = string.format("Money: $%d", math.floor(uiState.money + 0.5))
	refs.waveLine.Text = string.format("Wave: %d (%s)", uiState.wave, uiState.waveState)
	refs.enemiesLine.Text = string.format("Living Enemies: %d", uiState.livingEnemies)
	if uiState.wave >= bossWaveNumber then
		refs.waveStatusWaveLabel.Text = "Wave: Boss"
	else
		refs.waveStatusWaveLabel.Text = string.format("Wave %d/%d", math.max(0, uiState.wave), totalWaves)
	end
	refs.waveStatusMonstersLabel.Text = string.format("Monsters: %d", math.max(0, uiState.enemiesRemaining))
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
	if not gameOverActive then return end
	if not returnToLobbyRemote then
		refs.returnToLobbyStatus.Text = "Lobby teleport is unavailable."
		setReturnToLobbyButtonEnabled(false, "Lobby Unavailable")
		return
	end
	if returnToLobbyRequested then return end
	returnToLobbyRequested = true
	returnToLobbyRequestToken += 1
	local activeRequestToken = returnToLobbyRequestToken
	refs.returnToLobbyStatus.Text = "Returning you to lobby..."
	setReturnToLobbyButtonEnabled(false, "Returning...")
	TeleportLoading.show({
		title = "Returning to lobby",
		subtitle = "Teleporting you back to the lobby...",
		timeoutSeconds = 12,
		timeoutMessage = "Could not return to the lobby. Please try again.",
	})
	returnToLobbyRemote:FireServer()
	task.delay(8, function()
		if not gameOverActive or not returnToLobbyRequested or returnToLobbyRequestToken ~= activeRequestToken then
			return
		end
		returnToLobbyRequested = false
		TeleportLoading.showFailure("Could not return to the lobby. Please try again.")
		refs.returnToLobbyStatus.Text = "Teleport did not complete. Press again to retry."
		setReturnToLobbyButtonEnabled(true, "Return to Lobby")
	end)
end

refs.returnToLobbyButton.Activated:Connect(requestReturnToLobby)

local function applyMapVotePayload(payload: any)
	if typeof(payload) ~= "table" then return end
	if not gameOverActive then return end
	local t = payload
	local action = t.action
	if type(action) ~= "string" then return end
	if action == "Start" then
		mapVoteOptions = normalizeMapVoteOptions(t.options)
		mapVoteOpen = true
		refs.mapVotePanel.Visible = true
		mapVoteSelectedPlaceId = nil
		refs.mapVoteHeader.Text = "MAP VOTE"
		refs.mapVoteStatusLabel.Text = "Choose the next map."
		renderMapVoteOptions()
		startMapVoteCountdown(t.endsAt)
		return
	end
	if action == "Update" then
		mapVoteOptions = normalizeMapVoteOptions(t.options)
		if refs.mapVotePanel.Visible then
			renderMapVoteOptions()
		end
		if mapVoteOpen then
			refs.mapVoteTimerLabel.Text = formatMapVoteTimerText(t.endsAt)
		end
		return
	end
	if action == "End" then
		mapVoteOptions = normalizeMapVoteOptions(t.options)
		mapVoteOpen = false
		cancelMapVoteCountdown()
		refs.mapVotePanel.Visible = true
		renderMapVoteOptions()
		refs.mapVoteTimerLabel.Text = "Voting closed"
		local selectedLabel = type(t.selectedLabel) == "string" and t.selectedLabel ~= "" and t.selectedLabel or "next map"
		if t.wasTie == true then
			refs.mapVoteStatusLabel.Text = string.format("Winner: %s (random tie-break).", selectedLabel)
		else
			refs.mapVoteStatusLabel.Text = string.format("Winner: %s.", selectedLabel)
		end
		return
	end
	if action == "Teleporting" then
		mapVoteOpen = false
		cancelMapVoteCountdown()
		refs.mapVotePanel.Visible = true
		refs.mapVoteTimerLabel.Text = "Teleporting..."
		TeleportLoading.show({
			title = "Loading next map",
			subtitle = refs.mapVoteStatusLabel.Text,
			timeoutSeconds = 12,
			timeoutMessage = "Could not load the next map. Please try again.",
		})
		local selectedLabel = type(t.selectedLabel) == "string" and t.selectedLabel ~= "" and t.selectedLabel or "selected map"
		local difficultyLabel = t.difficulty
		if type(difficultyLabel) == "string" and difficultyLabel ~= "" then
			refs.mapVoteStatusLabel.Text = string.format("Loading %s (%s difficulty)...", selectedLabel, difficultyLabel)
		else
			refs.mapVoteStatusLabel.Text = string.format("Loading %s...", selectedLabel)
		end
		updateMapVoteButtons()
	end
end

local function applyWaveState(payload: any)
	if typeof(payload) ~= "table" then return end
	local t = payload
	local stateName = t.state
	if gameOverActive and stateName ~= "GameOver" and stateName ~= "Won" then return end
	if type(t.wave) == "number" then
		uiState.wave = t.wave
	end
	uiState.waveState = stateName or uiState.waveState
	if type(t.enemiesRemaining) == "number" then
		uiState.enemiesRemaining = math.max(0, t.enemiesRemaining)
	end
	render()
	if stateName == "GameOver" then
		setGameOverActive(true, t.reason, false)
		return
	end
	if stateName == "Won" then
		setGameOverActive(true, t.reason, true)
		return
	end
	setGameOverActive(false)
	if stateName == "Preparing" then
		startIntermissionCountdown(t.intermission or Config.Wave.IntermissionSeconds, uiState.wave, t.intermissionEndsAt)
	else
		hideCountdown()
	end
end

local function bindCharacter(character: Model)
	hideRespawnCountdown()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local function updateHp()
		uiState.hp = humanoid.Health
		uiState.maxHp = humanoid.MaxHealth
		render()
	end
	updateHp()
	humanoid.HealthChanged:Connect(updateHp)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHp)
	humanoid.Died:Connect(function()
		if gameOverActive then return end
		startRespawnCountdown((Config.Player and Config.Player.RespawnDelaySeconds) or 60)
	end)
end

local function bindMoney()
	local leaderstats = player:WaitForChild("leaderstats", 15)
	if not leaderstats then return end
	local moneyValue = leaderstats:FindFirstChild("Money") or leaderstats:WaitForChild("Money", 15)
	if not moneyValue then return end
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
	local function syncWaveFromAttribute()
		local n = remotesFolder:GetAttribute("CurrentWaveNumber")
		if type(n) == "number" then
			uiState.wave = n
			render()
		end
	end
	local function syncEnemiesRemainingFromValue()
		local nv = remotesFolder:FindFirstChild("WaveEnemiesRemaining")
		if nv and nv:IsA("IntValue") then
			uiState.enemiesRemaining = math.max(0, nv.Value)
			render()
		end
	end
	remotesFolder:GetAttributeChangedSignal("CurrentWaveNumber"):Connect(syncWaveFromAttribute)
	syncWaveFromAttribute()
	local waveEnemiesRemainingValue = remotesFolder:FindFirstChild("WaveEnemiesRemaining")
	if waveEnemiesRemainingValue and waveEnemiesRemainingValue:IsA("IntValue") then
		waveEnemiesRemainingValue.Changed:Connect(syncEnemiesRemainingFromValue)
		syncEnemiesRemainingFromValue()
	end
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

render()

return {}
