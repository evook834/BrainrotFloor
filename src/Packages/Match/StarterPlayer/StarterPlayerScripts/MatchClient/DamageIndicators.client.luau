local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local damageIndicatorRemote = remotesFolder:WaitForChild(Config.Remotes.DamageIndicator)

local indicatorFolder = nil
local randomGenerator = Random.new()

local function getIndicatorFolder()
	if indicatorFolder and indicatorFolder.Parent == Workspace then
		return indicatorFolder
	end

	indicatorFolder = Workspace:FindFirstChild("DamageIndicators")
	if indicatorFolder and indicatorFolder:IsA("Folder") then
		return indicatorFolder
	end

	if indicatorFolder then
		indicatorFolder:Destroy()
	end

	indicatorFolder = Instance.new("Folder")
	indicatorFolder.Name = "DamageIndicators"
	indicatorFolder.Parent = Workspace
	return indicatorFolder
end

local function resolveEnemyRoot(enemyModel)
	if enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") then
		return enemyModel.PrimaryPart
	end

	local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local anyPart = enemyModel:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
	end

	return nil
end

local function getEnemyHeightOffset(enemyModel)
	local height = 4
	local ok, size = pcall(function()
		return enemyModel:GetExtentsSize()
	end)
	if ok and size then
		height = size.Y
	end

	return math.clamp((height * 0.45) + 0.8, 1.6, 7.5)
end

local function resolveColorForDamage(damage)
	if damage >= 120 then
		return Color3.fromRGB(255, 95, 95)
	end
	if damage >= 60 then
		return Color3.fromRGB(255, 190, 95)
	end
	return Color3.fromRGB(245, 245, 245)
end

local function normalizeStyleTag(styleTag)
	if type(styleTag) ~= "string" then
		return ""
	end

	local trimmed = string.gsub(styleTag, "%s+", "")
	return string.lower(trimmed)
end

local function isCritStyle(styleTag)
	return normalizeStyleTag(styleTag) == "crit"
end

local function createDamageIndicator(worldPosition, damageAmount, styleTag)
	local roundedDamage = math.max(1, math.floor(damageAmount + 0.5))
	local critStyle = isCritStyle(styleTag)

	local startPosition = worldPosition
	startPosition += Vector3.new(
		randomGenerator:NextNumber(-0.5, 0.5),
		randomGenerator:NextNumber(0.2, 0.8),
		randomGenerator:NextNumber(-0.5, 0.5)
	)
	local rise = if critStyle then randomGenerator:NextNumber(2.8, 3.8) else randomGenerator:NextNumber(2.2, 3.2)
	local horizontalDriftRange = if critStyle then 0.8 else 0.6
	local drift = Vector3.new(
		randomGenerator:NextNumber(-horizontalDriftRange, horizontalDriftRange),
		rise,
		randomGenerator:NextNumber(-horizontalDriftRange, horizontalDriftRange)
	)
	local lifetime = if critStyle then randomGenerator:NextNumber(0.58, 0.78) else randomGenerator:NextNumber(0.45, 0.62)

	local anchor = Instance.new("Part")
	anchor.Name = "DamageIndicatorAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(startPosition)
	anchor.Parent = getIndicatorFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageIndicator"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Size = if critStyle then UDim2.fromOffset(130, 56) else UDim2.fromOffset(96, 42)
	billboard.Parent = anchor

	local scale = Instance.new("UIScale")
	scale.Scale = if critStyle then 0.74 else 0.82
	scale.Parent = billboard

	local critGlow = nil
	if critStyle then
		critGlow = Instance.new("TextLabel")
		critGlow.Name = "CritGlow"
		critGlow.BackgroundTransparency = 1
		critGlow.Position = UDim2.fromScale(-0.08, -0.08)
		critGlow.Size = UDim2.fromScale(1.16, 1.16)
		critGlow.Font = Enum.Font.GothamBlack
		critGlow.Text = string.format("CRIT %d", roundedDamage)
		critGlow.TextColor3 = Color3.fromRGB(255, 82, 55)
		critGlow.TextScaled = true
		critGlow.TextTransparency = 0.28
		critGlow.TextStrokeTransparency = 1
		critGlow.ZIndex = 1
		critGlow.Parent = billboard
	end

	local label = Instance.new("TextLabel")
	label.Name = "DamageText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = if critStyle then string.format("CRIT %d", roundedDamage) else tostring(roundedDamage)
	label.TextColor3 = if critStyle then Color3.fromRGB(255, 235, 120) else resolveColorForDamage(damageAmount)
	label.TextScaled = true
	label.TextStrokeColor3 = if critStyle then Color3.fromRGB(85, 20, 12) else Color3.new(0, 0, 0)
	label.TextStrokeTransparency = if critStyle then 0.08 else 0.25
	label.Rotation = if critStyle then randomGenerator:NextNumber(-4, 4) else 0
	label.ZIndex = 2
	label.Parent = billboard

	if critStyle then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 150)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 82)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 95, 70)),
		})
		gradient.Rotation = 90
		gradient.Parent = label
	end

	local popDuration = if critStyle then 0.16 else 0.14
	local popScaleTarget = if critStyle then 1.26 else 1.08
	local settleScaleTarget = if critStyle then 1.04 else 0.98
	local moveTween = TweenService:Create(
		anchor,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(startPosition + drift) }
	)
	local popTween = TweenService:Create(
		scale,
		TweenInfo.new(popDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = popScaleTarget }
	)
	local settleTween = TweenService:Create(
		scale,
		TweenInfo.new(math.max(0.16, lifetime - popDuration), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = settleScaleTarget }
	)
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	local glowFadeTween = nil
	if critGlow then
		glowFadeTween = TweenService:Create(
			critGlow,
			TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				TextTransparency = 1,
			}
		)
	end

	popTween.Completed:Connect(function()
		settleTween:Play()
	end)

	moveTween:Play()
	popTween:Play()
	fadeTween:Play()
	if glowFadeTween then
		glowFadeTween:Play()
	end

	Debris:AddItem(anchor, lifetime + 0.08)
end

damageIndicatorRemote.OnClientEvent:Connect(function(enemyModel, damageAmount, worldPosition, styleTag)
	if type(damageAmount) ~= "number" or damageAmount <= 0 then
		return
	end

	local spawnPosition = nil
	if typeof(worldPosition) == "Vector3" then
		spawnPosition = worldPosition
	end

	if enemyModel and enemyModel:IsA("Model") then
		local enemyRoot = resolveEnemyRoot(enemyModel)
		if enemyRoot then
			spawnPosition = enemyRoot.Position
		end

		if spawnPosition then
			spawnPosition += Vector3.new(0, getEnemyHeightOffset(enemyModel), 0)
		end
	end

	if not spawnPosition then
		return
	end

	createDamageIndicator(spawnPosition, damageAmount, styleTag)
end)
