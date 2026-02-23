local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sprintKey = Enum.KeyCode.LeftShift
local playerConfig = Config.Player or {}

local sprintMultiplier = math.max(1, tonumber(playerConfig.SprintSpeedMultiplier) or 2.2)
local staminaMax = math.max(1, tonumber(playerConfig.SprintStaminaMax) or 100)
local staminaDrainPerSecond = math.max(0, tonumber(playerConfig.SprintStaminaDrainPerSecond) or 35)
local staminaRegenPerSecond = math.max(0, tonumber(playerConfig.SprintStaminaRegenPerSecond) or 10)
local staminaRegenDelaySeconds = math.max(0, tonumber(playerConfig.SprintStaminaRegenDelaySeconds) or 0.45)
local staminaMinToSprint = math.clamp(tonumber(playerConfig.SprintStaminaMinToSprint) or 15, 0, staminaMax)

local existingGui = playerGui:FindFirstChild("SprintStaminaHud")
if existingGui then
	existingGui:Destroy()
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "SprintStaminaHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 26
gui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "VitalsContainer"
container.Size = UDim2.new(0.36, 0, 0, 78)
container.Position = UDim2.new(0.5, 0, 1, -168)
container.AnchorPoint = Vector2.new(0.5, 1)
container.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
container.BackgroundTransparency = 0.1
container.BorderSizePixel = 0
container.Parent = gui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 10)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(78, 95, 118)
containerStroke.Transparency = 0.15
containerStroke.Thickness = 1
containerStroke.Parent = container

local containerSizeConstraint = Instance.new("UISizeConstraint")
containerSizeConstraint.MinSize = Vector2.new(250, 78)
containerSizeConstraint.MaxSize = Vector2.new(500, 92)
containerSizeConstraint.Parent = container

local containerPadding = Instance.new("UIPadding")
containerPadding.PaddingTop = UDim.new(0, 8)
containerPadding.PaddingBottom = UDim.new(0, 8)
containerPadding.PaddingLeft = UDim.new(0, 10)
containerPadding.PaddingRight = UDim.new(0, 10)
containerPadding.Parent = container

local containerLayout = Instance.new("UIListLayout")
containerLayout.FillDirection = Enum.FillDirection.Vertical
containerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
containerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
containerLayout.Padding = UDim.new(0, 8)
containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
containerLayout.Parent = container

local function createVitalsRow(name, labelText, initialFillColor)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 27)
	row.BackgroundTransparency = 1
	row.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(70, 27)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Color3.fromRGB(214, 232, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.Parent = row

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(1, -78, 0, 14)
	barBackground.Position = UDim2.new(0, 78, 0.5, -7)
	barBackground.BackgroundColor3 = Color3.fromRGB(33, 40, 52)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = row

	local barBackgroundCorner = Instance.new("UICorner")
	barBackgroundCorner.CornerRadius = UDim.new(0, 5)
	barBackgroundCorner.Parent = barBackground

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = initialFillColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 5)
	barFillCorner.Parent = barFill

	local barLabel = Instance.new("TextLabel")
	barLabel.Name = "BarLabel"
	barLabel.Size = UDim2.fromScale(1, 1)
	barLabel.BackgroundTransparency = 1
	barLabel.Text = "100 / 100"
	barLabel.TextColor3 = Color3.fromRGB(17, 24, 34)
	barLabel.Font = Enum.Font.GothamBold
	barLabel.TextSize = 11
	barLabel.Parent = barBackground

	return {
		label = label,
		fill = barFill,
		value = barLabel,
	}
end

local healthRow = createVitalsRow("HealthRow", "HEALTH", Color3.fromRGB(84, 206, 160))
local staminaRow = createVitalsRow("StaminaRow", "STAMINA", Color3.fromRGB(84, 206, 160))

local isSprintHeld = false
local isSprintActive = false
local isExhausted = false
local humanoid = nil
local normalWalkSpeed = 16
local currentStamina = staminaMax
local isApplyingSprintSpeed = false
local lastDrainAt = -math.huge
local walkSpeedConnection = nil
local humanoidDiedConnection = nil

local function getStaminaRatio()
	return math.clamp(currentStamina / staminaMax, 0, 1)
end

local function getHealthRatio()
	if not humanoid then
		return 1
	end

	local maxHealth = math.max(1, humanoid.MaxHealth)
	return math.clamp(humanoid.Health / maxHealth, 0, 1)
end

local function renderHealthBar()
	local maxHealth = 100
	local health = 100
	if humanoid then
		maxHealth = math.max(1, humanoid.MaxHealth)
		health = math.clamp(humanoid.Health, 0, maxHealth)
	end

	local ratio = getHealthRatio()
	healthRow.fill.Size = UDim2.fromScale(ratio, 1)
	healthRow.value.Text = string.format("%d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))

	if ratio <= 0.2 then
		healthRow.fill.BackgroundColor3 = Color3.fromRGB(230, 87, 87)
		healthRow.value.TextColor3 = Color3.fromRGB(44, 14, 14)
		healthRow.label.TextColor3 = Color3.fromRGB(255, 170, 170)
	elseif ratio <= 0.5 then
		healthRow.fill.BackgroundColor3 = Color3.fromRGB(235, 168, 88)
		healthRow.value.TextColor3 = Color3.fromRGB(52, 32, 10)
		healthRow.label.TextColor3 = Color3.fromRGB(255, 214, 168)
	else
		healthRow.fill.BackgroundColor3 = Color3.fromRGB(84, 206, 160)
		healthRow.value.TextColor3 = Color3.fromRGB(17, 24, 34)
		healthRow.label.TextColor3 = Color3.fromRGB(214, 232, 255)
	end
end

local function renderStaminaBar()
	local ratio = getStaminaRatio()
	staminaRow.fill.Size = UDim2.fromScale(ratio, 1)
	staminaRow.value.Text = string.format("%d / %d", math.floor(currentStamina + 0.5), math.floor(staminaMax + 0.5))

	if ratio <= 0.2 then
		staminaRow.fill.BackgroundColor3 = Color3.fromRGB(230, 87, 87)
		staminaRow.value.TextColor3 = Color3.fromRGB(44, 14, 14)
		staminaRow.label.TextColor3 = Color3.fromRGB(255, 170, 170)
	elseif ratio <= 0.5 then
		staminaRow.fill.BackgroundColor3 = Color3.fromRGB(235, 168, 88)
		staminaRow.value.TextColor3 = Color3.fromRGB(52, 32, 10)
		staminaRow.label.TextColor3 = Color3.fromRGB(255, 214, 168)
	else
		staminaRow.fill.BackgroundColor3 = Color3.fromRGB(84, 206, 160)
		staminaRow.value.TextColor3 = Color3.fromRGB(17, 24, 34)
		staminaRow.label.TextColor3 = Color3.fromRGB(214, 232, 255)
	end
end

local function applySpeed()
	if not humanoid then
		return
	end

	local targetSpeed = normalWalkSpeed
	if isSprintActive then
		targetSpeed *= sprintMultiplier
	end

	if math.abs(humanoid.WalkSpeed - targetSpeed) < 0.01 then
		return
	end

	isApplyingSprintSpeed = true
	humanoid.WalkSpeed = targetSpeed
	isApplyingSprintSpeed = false
end

local function onWalkSpeedChanged()
	if not humanoid then
		return
	end
	if isApplyingSprintSpeed then
		return
	end

	local currentWalkSpeed = humanoid.WalkSpeed
	if isSprintActive then
		local expectedSprintSpeed = normalWalkSpeed * sprintMultiplier
		if math.abs(currentWalkSpeed - expectedSprintSpeed) < 0.01 then
			return
		end
	end

	normalWalkSpeed = currentWalkSpeed
	applySpeed()
end

local function bindCharacter(character)
	if walkSpeedConnection then
		walkSpeedConnection:Disconnect()
		walkSpeedConnection = nil
	end
	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	normalWalkSpeed = humanoid.WalkSpeed
	currentStamina = staminaMax
	isSprintActive = false
	isExhausted = false
	lastDrainAt = -math.huge
	renderHealthBar()
	renderStaminaBar()

	walkSpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(onWalkSpeedChanged)
	humanoidDiedConnection = humanoid.Died:Connect(function()
		isSprintHeld = false
		isSprintActive = false
		applySpeed()
	end)

	applySpeed()
end

local function setSprintHeld(held)
	if isSprintHeld == held then
		return
	end

	isSprintHeld = held
	if not held then
		isSprintActive = false
	end
	applySpeed()
end

UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	if inputObject.KeyCode ~= sprintKey then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end

	setSprintHeld(true)
end)

UserInputService.InputEnded:Connect(function(inputObject)
	if inputObject.KeyCode ~= sprintKey then
		return
	end

	setSprintHeld(false)
end)

UserInputService.WindowFocusReleased:Connect(function()
	setSprintHeld(false)
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not humanoid then
		renderHealthBar()
		return
	end

	local dt = math.min(math.max(deltaTime, 0), 0.25)
	local canUseSprint = isSprintHeld
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.05
		and currentStamina > 0
		and (not isExhausted or currentStamina >= staminaMinToSprint)

	if canUseSprint then
		isSprintActive = true
		if staminaDrainPerSecond > 0 and dt > 0 then
			currentStamina = math.max(0, currentStamina - (staminaDrainPerSecond * dt))
			lastDrainAt = os.clock()
			if currentStamina <= 0 then
				currentStamina = 0
				isSprintActive = false
				isExhausted = true
			end
		end
	else
		isSprintActive = false
		local elapsedSinceDrain = os.clock() - lastDrainAt
		if elapsedSinceDrain >= staminaRegenDelaySeconds and staminaRegenPerSecond > 0 and dt > 0 then
			currentStamina = math.min(staminaMax, currentStamina + (staminaRegenPerSecond * dt))
		end
	end

	if isExhausted and currentStamina >= staminaMinToSprint then
		isExhausted = false
	end

	applySpeed()
	renderHealthBar()
	renderStaminaBar()
end)

renderHealthBar()
renderStaminaBar()

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(bindCharacter)
