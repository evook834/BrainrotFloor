local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EnemyVfxService = {}

local randomGenerator = Random.new()
local enemyEffectsFolder = nil

local function getEffectsFolder()
	if enemyEffectsFolder and enemyEffectsFolder.Parent == Workspace then
		return enemyEffectsFolder
	end

	enemyEffectsFolder = Workspace:FindFirstChild("EnemyEffects")
	if enemyEffectsFolder and enemyEffectsFolder:IsA("Folder") then
		return enemyEffectsFolder
	end

	if enemyEffectsFolder then
		enemyEffectsFolder:Destroy()
	end

	enemyEffectsFolder = Instance.new("Folder")
	enemyEffectsFolder.Name = "EnemyEffects"
	enemyEffectsFolder.Parent = Workspace
	return enemyEffectsFolder
end

local function getEmitterPosition(enemyModel)
	local modelPivot = CFrame.new()
	local hasPivot = pcall(function()
		modelPivot = enemyModel:GetPivot()
	end)
	if not hasPivot then
		local rootPart = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart", true)
		if rootPart and rootPart:IsA("BasePart") then
			modelPivot = rootPart.CFrame
		end
	end

	local size = Vector3.new(4, 4, 4)
	local ok, extents = pcall(function()
		return enemyModel:GetExtentsSize()
	end)
	if ok and extents then
		size = extents
	end

	local horizontalJitter = Vector3.new(
		randomGenerator:NextNumber(-0.2, 0.2) * size.X,
		0,
		randomGenerator:NextNumber(-0.2, 0.2) * size.Z
	)
	local verticalOffset = math.max(0.4, size.Y * randomGenerator:NextNumber(0.25, 0.45))
	return modelPivot.Position + horizontalJitter + Vector3.new(0, verticalOffset, 0), size
end

local function createPuff(position, effectScale, colorMin, colorMax)
	local puff = Instance.new("Part")
	puff.Name = "EnemyDeathPuff"
	puff.Shape = Enum.PartType.Ball
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanTouch = false
	puff.CanQuery = false
	puff.Material = Enum.Material.SmoothPlastic
	local minValue = colorMin or 130
	local maxValue = colorMax or 168
	local gray = randomGenerator:NextInteger(minValue, maxValue)
	puff.Color = Color3.fromRGB(gray, gray, gray)
	puff.Transparency = randomGenerator:NextNumber(0.1, 0.28)

	local startSize = randomGenerator:NextNumber(0.95, 1.55) * effectScale
	local sizeVector = Vector3.new(startSize, startSize, startSize)
	puff.Size = sizeVector

	local horizontalSpread = randomGenerator:NextNumber(0.5, 1.35) * effectScale
	local offset = Vector3.new(
		randomGenerator:NextNumber(-horizontalSpread, horizontalSpread),
		randomGenerator:NextNumber(-0.05, 0.25) * effectScale,
		randomGenerator:NextNumber(-horizontalSpread, horizontalSpread)
	)
	puff.CFrame = CFrame.new(position + offset)
	puff.Parent = getEffectsFolder()

	local riseOffset = Vector3.new(
		randomGenerator:NextNumber(-0.4, 0.4) * effectScale,
		randomGenerator:NextNumber(0.8, 1.6) * effectScale,
		randomGenerator:NextNumber(-0.4, 0.4) * effectScale
	)
	local expandScale = randomGenerator:NextNumber(1.45, 2.2)
	local lifetime = randomGenerator:NextNumber(0.55, 0.95)
	local tween = TweenService:Create(
		puff,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = sizeVector * expandScale,
			Transparency = 1,
			CFrame = puff.CFrame + riseOffset,
		}
	)
	tween:Play()
	Debris:AddItem(puff, lifetime + 0.08)
end

local function createBurstBall(position, effectScale, color, transparencyMin, transparencyMax)
	local burst = Instance.new("Part")
	burst.Name = "EnemyDeathBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.SmoothPlastic
	burst.Color = color or Color3.fromRGB(185, 185, 185)
	burst.Transparency = randomGenerator:NextNumber(transparencyMin or 0.08, transparencyMax or 0.2)
	local startSize = randomGenerator:NextNumber(0.9, 1.35) * effectScale
	local startSizeVector = Vector3.new(startSize, startSize, startSize)
	burst.Size = startSizeVector
	burst.CFrame = CFrame.new(position)
	burst.Parent = getEffectsFolder()

	local endScale = randomGenerator:NextNumber(2.6, 3.7)
	local tween = TweenService:Create(
		burst,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = startSizeVector * endScale,
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(burst, 0.45)
end

local function createShockwaveRing(position, effectScale, color)
	local ring = Instance.new("Part")
	ring.Name = "EnemyDeathShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color or Color3.fromRGB(255, 186, 112)
	ring.Transparency = randomGenerator:NextNumber(0.14, 0.26)
	local startDiameter = randomGenerator:NextNumber(1.2, 1.8) * effectScale
	ring.Size = Vector3.new(0.12 * effectScale, startDiameter, startDiameter)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), randomGenerator:NextNumber(0, math.pi * 2), 0)
	ring.Parent = getEffectsFolder()

	local expandScale = randomGenerator:NextNumber(2.4, 3.8)
	local lifetime = randomGenerator:NextNumber(0.26, 0.42)
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.02 * effectScale, ring.Size.Y * expandScale, ring.Size.Z * expandScale),
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(ring, lifetime + 0.06)
end

local function createFragmentBurst(position, effectScale, count, color)
	local fragmentCount = count or randomGenerator:NextInteger(6, 10)
	for _ = 1, fragmentCount do
		local fragment = Instance.new("Part")
		fragment.Name = "EnemyDeathFragment"
		fragment.Anchored = true
		fragment.CanCollide = false
		fragment.CanTouch = false
		fragment.CanQuery = false
		fragment.Material = Enum.Material.Neon
		fragment.Color = color or Color3.fromRGB(255, 170, 95)
		fragment.Transparency = randomGenerator:NextNumber(0.08, 0.22)
		local size = randomGenerator:NextNumber(0.08, 0.2) * effectScale
		fragment.Size = Vector3.new(size, size, size)
		fragment.CFrame = CFrame.new(position)
		fragment.Parent = getEffectsFolder()

		local horizontalRange = randomGenerator:NextNumber(1.3, 2.3) * effectScale
		local travel = Vector3.new(
			randomGenerator:NextNumber(-horizontalRange, horizontalRange),
			randomGenerator:NextNumber(0.65, 1.75) * effectScale,
			randomGenerator:NextNumber(-horizontalRange, horizontalRange)
		)
		local rotation = CFrame.Angles(
			math.rad(randomGenerator:NextNumber(90, 340)),
			math.rad(randomGenerator:NextNumber(90, 340)),
			math.rad(randomGenerator:NextNumber(90, 340))
		)
		local lifetime = randomGenerator:NextNumber(0.24, 0.5)
		local tween = TweenService:Create(
			fragment,
			TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				CFrame = (fragment.CFrame * rotation) + (travel * 0.6),
				Size = fragment.Size * randomGenerator:NextNumber(0.25, 0.55),
				Transparency = 1,
			}
		)
		tween:Play()
		Debris:AddItem(fragment, lifetime + 0.08)
	end
end

local function createSparkEmitter(position, effectScale)
	local source = Instance.new("Part")
	source.Name = "EnemyDeathSparkSource"
	source.Anchored = true
	source.CanCollide = false
	source.CanTouch = false
	source.CanQuery = false
	source.Transparency = 1
	source.Size = Vector3.new(0.2, 0.2, 0.2)
	source.CFrame = CFrame.new(position)
	source.Parent = getEffectsFolder()

	local attachment = Instance.new("Attachment")
	attachment.Parent = source

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(8 * effectScale, 14 * effectScale)
	emitter.SpreadAngle = Vector2.new(90, 90)
	emitter.Drag = 5
	emitter.Acceleration = Vector3.new(0, -22, 0)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.24 * effectScale),
		NumberSequenceKeypoint.new(1, 0.1 * effectScale),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 150)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 165, 85)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 56, 32)),
	})
	emitter.Parent = attachment
	emitter:Emit(randomGenerator:NextInteger(10, 22))
	Debris:AddItem(source, 0.6)
end

local function playSmokeStyle(position, effectScale)
	createBurstBall(position, effectScale, Color3.fromRGB(192, 192, 192), 0.08, 0.18)
	local puffCount = randomGenerator:NextInteger(6, 10)
	for _ = 1, puffCount do
		createPuff(position, effectScale, 130, 170)
	end
end

local function playExplosionStyle(position, effectScale)
	createBurstBall(position, effectScale, Color3.fromRGB(255, 168, 96), 0.06, 0.14)
	createShockwaveRing(position, effectScale, Color3.fromRGB(255, 170, 98))
	createFragmentBurst(position, effectScale, randomGenerator:NextInteger(8, 13), Color3.fromRGB(255, 170, 96))
	createSparkEmitter(position, effectScale)
	local puffCount = randomGenerator:NextInteger(4, 7)
	for _ = 1, puffCount do
		createPuff(position, effectScale * 0.9, 105, 165)
	end
end

local function playShockwaveStyle(position, effectScale)
	createBurstBall(position, effectScale, Color3.fromRGB(220, 228, 236), 0.05, 0.12)
	createShockwaveRing(position, effectScale * randomGenerator:NextNumber(1.15, 1.45), Color3.fromRGB(220, 228, 236))
	createShockwaveRing(position, effectScale * randomGenerator:NextNumber(0.95, 1.2), Color3.fromRGB(170, 180, 194))
	createFragmentBurst(position, effectScale, randomGenerator:NextInteger(6, 11), Color3.fromRGB(218, 228, 235))
end

local function playAshBurstStyle(position, effectScale)
	createBurstBall(position, effectScale, Color3.fromRGB(150, 150, 150), 0.1, 0.22)
	createFragmentBurst(position, effectScale, randomGenerator:NextInteger(9, 14), Color3.fromRGB(182, 182, 182))
	local puffCount = randomGenerator:NextInteger(8, 12)
	for _ = 1, puffCount do
		createPuff(position, effectScale * randomGenerator:NextNumber(0.9, 1.2), 120, 185)
	end
end

function EnemyVfxService.playDeathCloud(enemyModel)
	if not enemyModel or not enemyModel:IsA("Model") then
		return
	end
	if enemyModel:GetAttribute("DeathCloudPlayed") then
		return
	end
	enemyModel:SetAttribute("DeathCloudPlayed", true)

	local position, modelSize = getEmitterPosition(enemyModel)
	local effectScale = math.max(1.05, math.min(1.9, (modelSize.Magnitude / 7.5) * randomGenerator:NextNumber(0.95, 1.3)))
	local styleRoll = randomGenerator:NextInteger(1, 100)
	if styleRoll <= 38 then
		playSmokeStyle(position, effectScale)
	elseif styleRoll <= 66 then
		playExplosionStyle(position, effectScale)
	elseif styleRoll <= 84 then
		playShockwaveStyle(position, effectScale)
	else
		playAshBurstStyle(position, effectScale)
	end
end

return EnemyVfxService
