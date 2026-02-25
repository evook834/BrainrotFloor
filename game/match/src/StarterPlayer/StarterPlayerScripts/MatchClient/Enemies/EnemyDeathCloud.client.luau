local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local randomGenerator = Random.new()
local trackedState = setmetatable({}, { __mode = "k" })
local playedCloud = setmetatable({}, { __mode = "k" })

local function resolveEnemyPosition(enemyModel)
	local rootPart = enemyModel.PrimaryPart
	if not rootPart or not rootPart:IsA("BasePart") then
		rootPart = enemyModel:FindFirstChild("HumanoidRootPart", true)
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		rootPart = enemyModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position + Vector3.new(0, math.max(0.4, rootPart.Size.Y * 0.35), 0), rootPart.Size
	end

	local okPivot, pivot = pcall(function()
		return enemyModel:GetPivot()
	end)
	local okSize, extents = pcall(function()
		return enemyModel:GetExtentsSize()
	end)
	if okPivot and pivot then
		local size = okSize and extents or Vector3.new(3, 3, 3)
		return pivot.Position + Vector3.new(0, math.max(0.6, size.Y * 0.35), 0), size
	end

	return nil, nil
end

local function createPuff(position, scale, colorMin, colorMax)
	local puff = Instance.new("Part")
	puff.Name = "EnemyDeathPuffLocal"
	puff.Shape = Enum.PartType.Ball
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanTouch = false
	puff.CanQuery = false
	puff.Material = Enum.Material.SmoothPlastic
	local minValue = colorMin or 145
	local maxValue = colorMax or 200
	local gray = randomGenerator:NextInteger(minValue, maxValue)
	puff.Color = Color3.fromRGB(gray, gray, gray)
	puff.Transparency = randomGenerator:NextNumber(0.14, 0.26)

	local startSize = randomGenerator:NextNumber(0.8, 1.35) * scale
	local startVector = Vector3.new(startSize, startSize, startSize)
	puff.Size = startVector
	puff.CFrame = CFrame.new(position + Vector3.new(
		randomGenerator:NextNumber(-1.1, 1.1) * scale,
		randomGenerator:NextNumber(-0.1, 0.2) * scale,
		randomGenerator:NextNumber(-1.1, 1.1) * scale
	))
	puff.Parent = Workspace

	local rise = Vector3.new(
		randomGenerator:NextNumber(-0.35, 0.35) * scale,
		randomGenerator:NextNumber(0.9, 1.7) * scale,
		randomGenerator:NextNumber(-0.35, 0.35) * scale
	)
	local lifetime = randomGenerator:NextNumber(0.45, 0.9)
	local tween = TweenService:Create(
		puff,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = startVector * randomGenerator:NextNumber(1.7, 2.9),
			Transparency = 1,
			CFrame = puff.CFrame + rise,
		}
	)
	tween:Play()
	Debris:AddItem(puff, lifetime + 0.08)
end

local function createBurstBall(position, scale, color, transparencyMin, transparencyMax)
	local burst = Instance.new("Part")
	burst.Name = "EnemyDeathBurstLocal"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.SmoothPlastic
	burst.Color = color or Color3.fromRGB(190, 190, 190)
	burst.Transparency = randomGenerator:NextNumber(transparencyMin or 0.08, transparencyMax or 0.18)
	local burstStartSize = randomGenerator:NextNumber(0.95, 1.35) * scale
	local burstStartVector = Vector3.new(burstStartSize, burstStartSize, burstStartSize)
	burst.Size = burstStartVector
	burst.CFrame = CFrame.new(position)
	burst.Parent = Workspace

	local burstTween = TweenService:Create(
		burst,
		TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = burstStartVector * randomGenerator:NextNumber(2.5, 3.5),
			Transparency = 1,
		}
	)
	burstTween:Play()
	Debris:AddItem(burst, 0.42)
end

local function createShockwaveRing(position, scale, color)
	local ring = Instance.new("Part")
	ring.Name = "EnemyDeathShockwaveLocal"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color or Color3.fromRGB(255, 186, 112)
	ring.Transparency = randomGenerator:NextNumber(0.14, 0.26)
	local startDiameter = randomGenerator:NextNumber(1.2, 1.8) * scale
	ring.Size = Vector3.new(0.12 * scale, startDiameter, startDiameter)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), randomGenerator:NextNumber(0, math.pi * 2), 0)
	ring.Parent = Workspace

	local expandScale = randomGenerator:NextNumber(2.4, 3.8)
	local lifetime = randomGenerator:NextNumber(0.26, 0.42)
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.02 * scale, ring.Size.Y * expandScale, ring.Size.Z * expandScale),
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(ring, lifetime + 0.06)
end

local function createFragmentBurst(position, scale, count, color)
	local fragmentCount = count or randomGenerator:NextInteger(6, 10)
	for _ = 1, fragmentCount do
		local fragment = Instance.new("Part")
		fragment.Name = "EnemyDeathFragmentLocal"
		fragment.Anchored = true
		fragment.CanCollide = false
		fragment.CanTouch = false
		fragment.CanQuery = false
		fragment.Material = Enum.Material.Neon
		fragment.Color = color or Color3.fromRGB(255, 170, 95)
		fragment.Transparency = randomGenerator:NextNumber(0.08, 0.22)
		local size = randomGenerator:NextNumber(0.08, 0.2) * scale
		fragment.Size = Vector3.new(size, size, size)
		fragment.CFrame = CFrame.new(position)
		fragment.Parent = Workspace

		local horizontalRange = randomGenerator:NextNumber(1.3, 2.3) * scale
		local travel = Vector3.new(
			randomGenerator:NextNumber(-horizontalRange, horizontalRange),
			randomGenerator:NextNumber(0.65, 1.75) * scale,
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

local function createSparkEmitter(position, scale)
	local source = Instance.new("Part")
	source.Name = "EnemyDeathSparkSourceLocal"
	source.Anchored = true
	source.CanCollide = false
	source.CanTouch = false
	source.CanQuery = false
	source.Transparency = 1
	source.Size = Vector3.new(0.2, 0.2, 0.2)
	source.CFrame = CFrame.new(position)
	source.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = source

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Speed = NumberRange.new(8 * scale, 14 * scale)
	emitter.SpreadAngle = Vector2.new(90, 90)
	emitter.Drag = 5
	emitter.Acceleration = Vector3.new(0, -22, 0)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.24 * scale),
		NumberSequenceKeypoint.new(1, 0.1 * scale),
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

local function playSmokeStyle(position, scale)
	createBurstBall(position, scale, Color3.fromRGB(192, 192, 192), 0.08, 0.18)
	local puffCount = randomGenerator:NextInteger(6, 10)
	for _ = 1, puffCount do
		createPuff(position, scale, 145, 200)
	end
end

local function playExplosionStyle(position, scale)
	createBurstBall(position, scale, Color3.fromRGB(255, 168, 96), 0.06, 0.14)
	createShockwaveRing(position, scale, Color3.fromRGB(255, 170, 98))
	createFragmentBurst(position, scale, randomGenerator:NextInteger(8, 13), Color3.fromRGB(255, 170, 96))
	createSparkEmitter(position, scale)
	local puffCount = randomGenerator:NextInteger(4, 7)
	for _ = 1, puffCount do
		createPuff(position, scale * 0.9, 105, 165)
	end
end

local function playShockwaveStyle(position, scale)
	createBurstBall(position, scale, Color3.fromRGB(220, 228, 236), 0.05, 0.12)
	createShockwaveRing(position, scale * randomGenerator:NextNumber(1.15, 1.45), Color3.fromRGB(220, 228, 236))
	createShockwaveRing(position, scale * randomGenerator:NextNumber(0.95, 1.2), Color3.fromRGB(170, 180, 194))
	createFragmentBurst(position, scale, randomGenerator:NextInteger(6, 11), Color3.fromRGB(218, 228, 235))
end

local function playAshBurstStyle(position, scale)
	createBurstBall(position, scale, Color3.fromRGB(150, 150, 150), 0.1, 0.22)
	createFragmentBurst(position, scale, randomGenerator:NextInteger(9, 14), Color3.fromRGB(182, 182, 182))
	local puffCount = randomGenerator:NextInteger(8, 12)
	for _ = 1, puffCount do
		createPuff(position, scale * randomGenerator:NextNumber(0.9, 1.2), 120, 185)
	end
end

local function playDeathCloud(enemyModel)
	if playedCloud[enemyModel] then
		return
	end
	playedCloud[enemyModel] = true

	local position, size = resolveEnemyPosition(enemyModel)
	if not position then
		return
	end

	local scale = 1
	if size then
		scale = math.max(0.9, math.min(1.9, size.Magnitude / 6))
	end

	local styleRoll = randomGenerator:NextInteger(1, 100)
	if styleRoll <= 38 then
		playSmokeStyle(position, scale)
	elseif styleRoll <= 66 then
		playExplosionStyle(position, scale)
	elseif styleRoll <= 84 then
		playShockwaveStyle(position, scale)
	else
		playAshBurstStyle(position, scale)
	end
end

local function stopTrackingEnemy(enemyModel)
	local state = trackedState[enemyModel]
	if not state then
		return
	end

	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	trackedState[enemyModel] = nil
end

local function trackEnemy(enemyModel)
	if trackedState[enemyModel] or not enemyModel:IsA("Model") then
		return
	end

	local state = {
		connections = {},
	}
	trackedState[enemyModel] = state

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(state.connections, humanoid.Died:Once(function()
			playDeathCloud(enemyModel)
		end))
	end

	local function checkHealth()
		local health = enemyModel:GetAttribute("EnemyHealth")
		if type(health) == "number" and health <= 0 then
			playDeathCloud(enemyModel)
		end
	end

	table.insert(state.connections, enemyModel:GetAttributeChangedSignal("EnemyHealth"):Connect(checkHealth))
	table.insert(state.connections, enemyModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			stopTrackingEnemy(enemyModel)
		end
	end))

	checkHealth()
end

local function bindEnemyContainer()
	local container = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if not container then
		Workspace.ChildAdded:Connect(function(child)
			if child.Name == Config.Enemy.ContainerName then
				for _, enemyModel in ipairs(child:GetChildren()) do
					trackEnemy(enemyModel)
				end
				child.ChildAdded:Connect(trackEnemy)
				child.ChildRemoved:Connect(stopTrackingEnemy)
			end
		end)
		return
	end

	for _, enemyModel in ipairs(container:GetChildren()) do
		trackEnemy(enemyModel)
	end
	container.ChildAdded:Connect(trackEnemy)
	container.ChildRemoved:Connect(stopTrackingEnemy)
end

bindEnemyContainer()
