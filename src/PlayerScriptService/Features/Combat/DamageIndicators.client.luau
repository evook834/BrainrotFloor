local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyModelUtils = require(script.Parent.Parent.Enemies.EnemyModelUtils)

local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
local damageIndicatorRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.DamageIndicator) or nil

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

local function resolveDamageStyle(styleTag)
	local normalized = normalizeStyleTag(styleTag)
	if normalized == "supercrit" or normalized == "supercritical" then
		return "supercrit"
	end
	if normalized == "crit" then
		return "crit"
	end
	return "normal"
end

local function createDamageIndicator(worldPosition, damageAmount, styleTag)
	local roundedDamage = math.max(1, math.floor(damageAmount + 0.5))
	local damageStyle = resolveDamageStyle(styleTag)
	local critStyle = damageStyle ~= "normal"
	local superCritStyle = damageStyle == "supercrit"

	local startPosition = worldPosition
	startPosition += Vector3.new(
		randomGenerator:NextNumber(-0.5, 0.5),
		randomGenerator:NextNumber(0.2, 0.8),
		randomGenerator:NextNumber(-0.5, 0.5)
	)
	local rise = if superCritStyle
		then randomGenerator:NextNumber(3.4, 4.4)
		elseif critStyle then randomGenerator:NextNumber(2.8, 3.8) else randomGenerator:NextNumber(2.2, 3.2)
	local horizontalDriftRange = if superCritStyle then 0.95 elseif critStyle then 0.8 else 0.6
	local drift = Vector3.new(
		randomGenerator:NextNumber(-horizontalDriftRange, horizontalDriftRange),
		rise,
		randomGenerator:NextNumber(-horizontalDriftRange, horizontalDriftRange)
	)
	local lifetime = if superCritStyle
		then randomGenerator:NextNumber(0.72, 0.92)
		elseif critStyle then randomGenerator:NextNumber(0.58, 0.78) else randomGenerator:NextNumber(0.45, 0.62)

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
	billboard.Size = if superCritStyle
		then UDim2.fromOffset(182, 78)
		elseif critStyle then UDim2.fromOffset(152, 68) else UDim2.fromOffset(96, 42)
	billboard.Parent = anchor

	local scale = Instance.new("UIScale")
	scale.Scale = if superCritStyle then 0.62 elseif critStyle then 0.68 else 0.82
	scale.Parent = billboard

	local critGlow = nil
	if critStyle then
		critGlow = Instance.new("TextLabel")
		critGlow.Name = "CritGlow"
		critGlow.BackgroundTransparency = 1
		critGlow.Position = UDim2.fromScale(-0.08, -0.08)
		critGlow.Size = UDim2.fromScale(1.16, 1.16)
		critGlow.Font = Enum.Font.GothamBlack
		critGlow.Text = tostring(roundedDamage)
		critGlow.TextColor3 = if superCritStyle then Color3.fromRGB(255, 214, 64) else Color3.fromRGB(255, 50, 50)
		critGlow.TextScaled = true
		critGlow.TextTransparency = 0.2
		critGlow.TextStrokeTransparency = 1
		critGlow.ZIndex = 1
		critGlow.Parent = billboard
	end

	local label = Instance.new("TextLabel")
	label.Name = "DamageText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(roundedDamage)
	label.TextColor3 = if superCritStyle
		then Color3.fromRGB(255, 226, 90)
		elseif critStyle then Color3.fromRGB(255, 58, 58) else resolveColorForDamage(damageAmount)
	label.TextScaled = true
	label.TextStrokeColor3 = if superCritStyle
		then Color3.fromRGB(95, 66, 6)
		elseif critStyle then Color3.fromRGB(92, 14, 14) else Color3.new(0, 0, 0)
	label.TextStrokeTransparency = if critStyle then 0.08 else 0.25
	local initialRotation = if superCritStyle
		then randomGenerator:NextNumber(-8, 8)
		elseif critStyle then randomGenerator:NextNumber(-6, 6) else 0
	label.Rotation = initialRotation
	label.ZIndex = 2
	label.Parent = billboard

	if critStyle then
		local gradient = Instance.new("UIGradient")
		if superCritStyle then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 246, 165)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 214, 76)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 176, 34)),
			})
		else
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 66, 66)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 28, 28)),
			})
		end
		gradient.Rotation = 90
		gradient.Parent = label
	end

	local popDuration = if superCritStyle then 0.18 elseif critStyle then 0.16 else 0.14
	local popScaleTarget = if superCritStyle then 1.45 elseif critStyle then 1.34 else 1.08
	local settleScaleTarget = if superCritStyle then 1.12 elseif critStyle then 1.08 else 0.98
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
	local secondPulseTween = nil
	if critStyle then
		secondPulseTween = TweenService:Create(
			scale,
			TweenInfo.new(if superCritStyle then 0.1 else 0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = if superCritStyle then 1.2 else 1.14 }
		)
	end
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
		if secondPulseTween then
			secondPulseTween.Completed:Connect(function()
				settleTween:Play()
			end)
			secondPulseTween:Play()
			return
		end
		settleTween:Play()
	end)

	moveTween:Play()
	popTween:Play()
	fadeTween:Play()
	if glowFadeTween then
		glowFadeTween:Play()
	end
	if critStyle then
		local tiltTween = TweenService:Create(
			label,
			TweenInfo.new(0.11, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Rotation = -initialRotation * 0.45 }
		)
		local settleTiltTween = TweenService:Create(
			label,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Rotation = 0 }
		)
		tiltTween.Completed:Connect(function()
			settleTiltTween:Play()
		end)
		tiltTween:Play()
	end

	Debris:AddItem(anchor, lifetime + 0.08)
end

if damageIndicatorRemote then
	damageIndicatorRemote.OnClientEvent:Connect(function(enemyModel, damageAmount, worldPosition, styleTag)
	if type(damageAmount) ~= "number" or damageAmount <= 0 then
		return
	end

	local spawnPosition = nil
	if typeof(worldPosition) == "Vector3" then
		spawnPosition = worldPosition
	end

	if enemyModel and enemyModel:IsA("Model") then
		local enemyRoot = EnemyModelUtils.resolveRootPart(enemyModel)
		if enemyRoot then
			spawnPosition = enemyRoot.Position
		end

		if spawnPosition then
			local size = EnemyModelUtils.getExtentsSize(enemyModel, Vector3.new(4, 4, 4))
			local height = size.Y
			local heightOffset = math.clamp((height * 0.45) + 0.8, 1.6, 7.5)
			spawnPosition += Vector3.new(0, heightOffset, 0)
		end
	end

	if not spawnPosition then
		return
	end

		createDamageIndicator(spawnPosition, damageAmount, styleTag)
	end)
end
