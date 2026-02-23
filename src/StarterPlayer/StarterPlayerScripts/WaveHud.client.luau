local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
gameOverTitle.Position = UDim2.fromScale(0.5, 0.44)
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
gameOverMessage.Position = UDim2.fromScale(0.5, 0.46)
gameOverMessage.AnchorPoint = Vector2.new(0.5, 0)
gameOverMessage.BackgroundTransparency = 1
gameOverMessage.Text = ""
gameOverMessage.TextWrapped = true
gameOverMessage.TextColor3 = Color3.fromRGB(245, 230, 230)
gameOverMessage.Font = Enum.Font.GothamSemibold
gameOverMessage.TextSize = 28
gameOverMessage.ZIndex = 21
gameOverMessage.Parent = gameOverOverlay

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
local gameOverActive = false

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

local function setGameOverActive(active, reason)
	gameOverActive = active
	gameOverOverlay.Visible = active

	if active then
		hideCountdown()
		hideRespawnCountdown()
		gameOverMessage.Text = getGameOverMessage(reason)
		return
	end

	gameOverMessage.Text = ""
end

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
if not remotesFolder then
	warn("WaveHud could not find ReplicatedStorage/Remotes")
end

local waveStateRemote = remotesFolder and remotesFolder:WaitForChild(Config.Remotes.WaveState, 15) or nil
if not waveStateRemote then
	warn("WaveHud could not find ReplicatedStorage/Remotes/WaveState")
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
