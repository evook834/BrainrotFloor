local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

local started = false
local remotesFolder = nil
local shopOpenRemote = nil
local shopGetCatalogFunction = nil
local shopBuyWeaponFunction = nil
local weaponAimRemote = nil
local weaponFireRemote = nil
local weaponById = {}
local weaponEffectsFolder = nil
local toolRuntimeState = setmetatable({}, { __mode = "k" })
local playerAimState = {}

local function ensureRemote(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if instance and instance.ClassName == className then
		return instance
	end

	if instance then
		instance:Destroy()
	end

	instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function getEffectsFolder()
	if weaponEffectsFolder and weaponEffectsFolder.Parent == Workspace then
		return weaponEffectsFolder
	end

	weaponEffectsFolder = Workspace:FindFirstChild("WeaponEffects")
	if weaponEffectsFolder and weaponEffectsFolder:IsA("Folder") then
		return weaponEffectsFolder
	end

	if weaponEffectsFolder then
		weaponEffectsFolder:Destroy()
	end

	weaponEffectsFolder = Instance.new("Folder")
	weaponEffectsFolder.Name = "WeaponEffects"
	weaponEffectsFolder.Parent = Workspace
	return weaponEffectsFolder
end

local function getEnemyContainer()
	return Workspace:FindFirstChild(Config.Enemy.ContainerName)
end

local function resolveEnemyRoot(enemyModel)
	if enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") then
		return enemyModel.PrimaryPart
	end

	local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		enemyModel.PrimaryPart = humanoidRootPart
		return humanoidRootPart
	end

	local anyPart = enemyModel:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		enemyModel.PrimaryPart = anyPart
	end
	return anyPart
end

local function findEnemyModelFromDescendant(descendant, enemyContainer)
	local current = descendant
	while current and current ~= enemyContainer do
		if current:IsA("Model") and current.Parent == enemyContainer then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function buildWeaponRaycastParams(character, additionalExclusions)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local exclusions = { character, getEffectsFolder() }
	for _, item in ipairs(additionalExclusions or {}) do
		table.insert(exclusions, item)
	end

	raycastParams.FilterDescendantsInstances = exclusions
	return raycastParams
end

local function updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
	if typeof(hitPosition) ~= "Vector3" then
		return
	end
	if typeof(lookDirection) ~= "Vector3" or lookDirection.Magnitude <= 0.001 then
		return
	end
	if cameraOrigin ~= nil and typeof(cameraOrigin) ~= "Vector3" then
		return
	end

	playerAimState[player] = {
		hitPosition = hitPosition,
		lookDirection = lookDirection.Unit,
		cameraOrigin = cameraOrigin,
		updatedAt = os.clock(),
	}
end

local function getFreshAimState(player)
	local aimState = playerAimState[player]
	if not aimState then
		return nil
	end

	if os.clock() - (aimState.updatedAt or 0) > 0.8 then
		return nil
	end

	return aimState
end

local function getPlayerAimDirection(player, character, rootPart, origin)
	local baseDirection = rootPart.CFrame.LookVector
	local aimState = getFreshAimState(player)
	if not aimState then
		return baseDirection
	end

	local cameraOrigin = aimState.cameraOrigin
	local lookDirection = aimState.lookDirection
	if typeof(cameraOrigin) == "Vector3" then
		local range = 1800
		local raycastParams = buildWeaponRaycastParams(character, {})
		local raycastResult = Workspace:Raycast(cameraOrigin, lookDirection * range, raycastParams)
		local targetPosition = cameraOrigin + lookDirection * range
		if raycastResult then
			targetPosition = raycastResult.Position
		end

		local toTarget = targetPosition - origin
		if toTarget.Magnitude > 0.01 then
			return toTarget.Unit
		end
	end

	local aimDirection = nil
	local toHit = aimState.hitPosition - origin
	if toHit.Magnitude > 0.01 then
		aimDirection = toHit.Unit
	else
		aimDirection = aimState.lookDirection
	end

	if typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude <= 0.001 then
		return baseDirection
	end

	return aimDirection.Unit
end

local function getPlayerShotRay(player, rootPart, fallbackOrigin, fallbackDirection)
	local aimState = getFreshAimState(player)
	if aimState and typeof(aimState.cameraOrigin) == "Vector3" then
		local lookDirection = aimState.lookDirection
		if typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
			return aimState.cameraOrigin, lookDirection.Unit
		end
	end

	if typeof(fallbackOrigin) == "Vector3" and typeof(fallbackDirection) == "Vector3" and fallbackDirection.Magnitude > 0.001 then
		return fallbackOrigin, fallbackDirection.Unit
	end

	return rootPart.Position + Vector3.new(0, 1.5, 0), rootPart.CFrame.LookVector
end

local function getMoneyValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local moneyValue = leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("IntValue") then
		return moneyValue
	end

	return nil
end

local function addMoney(player, amount)
	local moneyValue = getMoneyValue(player)
	if not moneyValue then
		return
	end

	moneyValue.Value += math.max(0, math.floor(amount + 0.5))
end

local function rewardEnemyKill(player, enemyModel)
	if enemyModel:GetAttribute("KillRewardPaid") then
		return
	end

	enemyModel:SetAttribute("KillRewardPaid", true)
	local bounty = enemyModel:GetAttribute("Bounty")
	if type(bounty) ~= "number" then
		bounty = Config.Enemy.BaseBounty or 25
	end

	addMoney(player, bounty)
end

local function applyDamageToEnemy(player, enemyModel, damage)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local appliedDamage = math.max(0, tonumber(damage) or 0)
	if appliedDamage <= 0 then
		return
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local previousHealth = humanoid.Health
		if previousHealth <= 0 then
			return
		end

		humanoid:TakeDamage(appliedDamage)
		if previousHealth > 0 and humanoid.Health <= 0 then
			rewardEnemyKill(player, enemyModel)
		end
		return
	end

	local maxHealth = enemyModel:GetAttribute("EnemyMaxHealth")
	if type(maxHealth) ~= "number" then
		maxHealth = Config.Enemy.NonHumanoidMaxHealth or 120
	end

	local health = enemyModel:GetAttribute("EnemyHealth")
	if type(health) ~= "number" then
		health = maxHealth
	end

	health -= appliedDamage
	enemyModel:SetAttribute("EnemyMaxHealth", maxHealth)
	enemyModel:SetAttribute("EnemyHealth", health)

	if health <= 0 then
		rewardEnemyKill(player, enemyModel)
		enemyModel:Destroy()
	end
end

local function resolveWeaponClass(weaponDef)
	if type(weaponDef.WeaponClass) == "string" and weaponDef.WeaponClass ~= "" then
		return weaponDef.WeaponClass
	end

	if (weaponDef.Range or 0) <= 12 then
		return "Melee"
	end

	return "Ranged"
end

local function getMagazineSize(weaponDef)
	local magazineSize = tonumber(weaponDef.MagazineSize)
	if not magazineSize then
		return nil
	end

	magazineSize = math.floor(magazineSize + 0.5)
	if magazineSize <= 0 then
		return nil
	end

	return magazineSize
end

local function getToolState(tool, weaponDef)
	local state = toolRuntimeState[tool]
	if state then
		return state
	end

	state = {
		lastActivatedAt = -math.huge,
		ammo = getMagazineSize(weaponDef),
		isReloading = false,
		isBursting = false,
		baseGrip = tool.Grip,
		swingToken = 0,
	}
	toolRuntimeState[tool] = state
	return state
end

local function updateAmmoAttributes(tool, weaponDef, state)
	local magazineSize = getMagazineSize(weaponDef)
	if not magazineSize then
		tool:SetAttribute("MaxAmmo", nil)
		tool:SetAttribute("CurrentAmmo", nil)
		tool:SetAttribute("IsReloading", false)
		tool.ToolTip = tostring(weaponDef.DisplayName or tool.Name)
		return
	end

	if type(state.ammo) ~= "number" then
		state.ammo = magazineSize
	end

	tool:SetAttribute("MaxAmmo", magazineSize)
	tool:SetAttribute("CurrentAmmo", state.ammo)
	tool:SetAttribute("IsReloading", state.isReloading == true)

	if state.isReloading then
		tool.ToolTip = string.format("%s | Reloading...", tostring(weaponDef.DisplayName or tool.Name))
	else
		tool.ToolTip = string.format("%s | Ammo %d/%d", tostring(weaponDef.DisplayName or tool.Name), state.ammo, magazineSize)
	end
end

local function startReload(tool, weaponDef, state)
	local magazineSize = getMagazineSize(weaponDef)
	if not magazineSize or state.isReloading then
		return
	end

	state.isReloading = true
	updateAmmoAttributes(tool, weaponDef, state)

	local reloadSeconds = math.max(0.2, tonumber(weaponDef.ReloadSeconds) or 2)
	task.delay(reloadSeconds, function()
		state.isReloading = false
		state.ammo = magazineSize
		if tool.Parent then
			updateAmmoAttributes(tool, weaponDef, state)
		end
	end)
end

local function tryConsumeAmmo(tool, weaponDef, state)
	local magazineSize = getMagazineSize(weaponDef)
	if not magazineSize then
		return true
	end

	if state.isReloading then
		return false
	end

	if type(state.ammo) ~= "number" then
		state.ammo = magazineSize
	end

	if state.ammo <= 0 then
		startReload(tool, weaponDef, state)
		return false
	end

	state.ammo -= 1
	updateAmmoAttributes(tool, weaponDef, state)

	if state.ammo <= 0 then
		startReload(tool, weaponDef, state)
	end

	return true
end

local function createTracerSegment(startPos, endPos, color, thickness, lifetimeSeconds)
	local delta = endPos - startPos
	local length = delta.Magnitude
	if length <= 0.05 then
		return
	end

	local segment = Instance.new("Part")
	segment.Name = "WeaponTracer"
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false
	segment.CanQuery = false
	segment.Material = Enum.Material.Neon
	segment.Color = color or Color3.fromRGB(255, 230, 140)
	segment.Size = Vector3.new(thickness or 0.18, thickness or 0.18, length)
	segment.CFrame = CFrame.lookAt((startPos + endPos) * 0.5, endPos)
	segment.Parent = getEffectsFolder()

	Debris:AddItem(segment, lifetimeSeconds or 0.1)
end

local function createMuzzleFlash(position, color, size, lifetimeSeconds)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = color or Color3.fromRGB(255, 190, 95)
	flash.Size = Vector3.new(size or 0.5, size or 0.5, size or 0.5)
	flash.CFrame = CFrame.new(position)
	flash.Parent = getEffectsFolder()
	Debris:AddItem(flash, lifetimeSeconds or 0.08)
end

local function createExplosionEffect(position, radius)
	local blast = Instance.new("Part")
	blast.Name = "RocketExplosion"
	blast.Shape = Enum.PartType.Ball
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanTouch = false
	blast.CanQuery = false
	blast.Material = Enum.Material.Neon
	blast.Color = Color3.fromRGB(255, 145, 70)
	blast.Transparency = 0.2
	blast.Size = Vector3.new(2, 2, 2)
	blast.CFrame = CFrame.new(position)
	blast.Parent = getEffectsFolder()

	local tween = TweenService:Create(
		blast,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(radius * 2, radius * 2, radius * 2),
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(blast, 0.25)
end

local function getWeaponOriginAndDirection(player, character, rootPart, handle)
	local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
	if handle and handle:IsA("BasePart") then
		origin = handle.Position
	end

	local direction = getPlayerAimDirection(player, character, rootPart, origin)
	if direction.Magnitude <= 0.001 then
		direction = rootPart.CFrame.LookVector
	end
	direction = direction.Unit

	if handle and handle:IsA("BasePart") then
		origin += direction * math.max(0.8, handle.Size.Z * 0.45)
		direction = getPlayerAimDirection(player, character, rootPart, origin)
		if direction.Magnitude <= 0.001 then
			direction = rootPart.CFrame.LookVector
		end
		direction = direction.Unit
	end

	return origin, direction
end

local function resolveEnemyFromRaycastResult(result)
	if not result then
		return nil
	end

	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return nil
	end

	return findEnemyModelFromDescendant(result.Instance, enemyContainer)
end

local function projectPointOnSegment(point, segmentStart, segmentEnd)
	local segment = segmentEnd - segmentStart
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= 0.0001 then
		return segmentStart, 0
	end

	local t = math.clamp((point - segmentStart):Dot(segment) / lengthSquared, 0, 1)
	return segmentStart + segment * t, t
end

local function hasClearPathToEnemy(character, startPos, enemyModel, enemyRoot)
	local params = buildWeaponRaycastParams(character, {})
	local direction = enemyRoot.Position - startPos
	if direction.Magnitude <= 0.01 then
		return true
	end

	local result = Workspace:Raycast(startPos, direction, params)
	if not result then
		return true
	end

	local hitEnemy = resolveEnemyFromRaycastResult(result)
	return hitEnemy == enemyModel
end

local function getEnemyHitRadius(enemyRoot)
	local rootSize = enemyRoot.Size
	local rootRadius = math.max(rootSize.X, rootSize.Z) * 0.55
	return math.clamp(rootRadius, 1.2, 5.5)
end

local function findEnemyAlongSegment(character, segmentStart, segmentEnd, extraRadius)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return nil, nil
	end

	local closestEnemy = nil
	local closestDistance = math.huge
	local impactPoint = nil
	local radiusPadding = math.max(0, extraRadius or 0)

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = resolveEnemyRoot(enemyModel)
			if enemyRoot then
				local nearestPoint = projectPointOnSegment(enemyRoot.Position, segmentStart, segmentEnd)
				local distanceFromPath = (enemyRoot.Position - nearestPoint).Magnitude
				local allowedRadius = getEnemyHitRadius(enemyRoot) + radiusPadding
				if distanceFromPath <= allowedRadius and hasClearPathToEnemy(character, segmentStart, enemyModel, enemyRoot) then
					local alongDistance = (nearestPoint - segmentStart).Magnitude
					if alongDistance < closestDistance then
						closestDistance = alongDistance
						closestEnemy = enemyModel
						impactPoint = nearestPoint
					end
				end
			end
		end
	end

	return closestEnemy, impactPoint
end

local function getEnemiesInCone(character, origin, lookDirection, range, arcDegrees)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return {}
	end

	local enemies = {}
	local normalizedLook = lookDirection.Magnitude > 0.001 and lookDirection.Unit or Vector3.new(0, 0, -1)
	local minDot = math.cos(math.rad(math.clamp((arcDegrees or 90) * 0.5, 1, 179)))

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = resolveEnemyRoot(enemyModel)
			if enemyRoot then
				local offset = enemyRoot.Position - origin
				local distance = offset.Magnitude
				if distance <= range and distance > 0.05 then
					local direction = offset.Unit
					local facingDot = normalizedLook:Dot(direction)
					if facingDot >= minDot and hasClearPathToEnemy(character, origin, enemyModel, enemyRoot) then
						table.insert(enemies, enemyModel)
					end
				end
			end
		end
	end

	return enemies
end

local function applyBlastDamage(player, centerPosition, radius, maxDamage)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return
	end

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = resolveEnemyRoot(enemyModel)
			if enemyRoot then
				local distance = (enemyRoot.Position - centerPosition).Magnitude
				if distance <= radius then
					local falloff = 1 - (distance / math.max(radius, 0.01))
					local damageScale = math.clamp(0.3 + falloff * 0.7, 0.3, 1)
					applyDamageToEnemy(player, enemyModel, maxDamage * damageScale)
				end
			end
		end
	end
end

local function playMeleeSwing(tool, weaponDef, state)
	local baseGrip = state.baseGrip or tool.Grip
	state.baseGrip = baseGrip
	state.swingToken += 1
	local swingToken = state.swingToken

	local swingForwardDegrees = tonumber(weaponDef.SwingForwardDegrees) or 70
	local swingDuration = math.max(0.05, tonumber(weaponDef.SwingDuration) or 0.14)
	local swingGrip = baseGrip * CFrame.Angles(math.rad(-swingForwardDegrees), 0, 0)

	tool.Grip = swingGrip
	task.delay(swingDuration, function()
		if state.swingToken ~= swingToken then
			return
		end
		if tool.Parent then
			tool.Grip = baseGrip
		end
	end)
end

local function fireBulletShot(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local range = math.max(1, tonumber(weaponDef.Range) or 40)
	local rayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local rayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local raycastParams = buildWeaponRaycastParams(character, {})
	local result = Workspace:Raycast(rayOrigin, rayDirection * range, raycastParams)
	local hitPosition = rayOrigin + rayDirection * range
	local enemyTarget = nil

	if result then
		hitPosition = result.Position
		enemyTarget = resolveEnemyFromRaycastResult(result)
	end

	if not enemyTarget then
		local fallbackEnemy, fallbackImpact = findEnemyAlongSegment(character, rayOrigin, hitPosition, 0.75)
		if fallbackEnemy then
			enemyTarget = fallbackEnemy
			if fallbackImpact then
				hitPosition = fallbackImpact
			end
		end
	end

	createMuzzleFlash(origin, Color3.fromRGB(255, 210, 120), 0.35, 0.06)
	createTracerSegment(origin, hitPosition, Color3.fromRGB(255, 235, 140), 0.13, 0.08)

	if enemyTarget then
		applyDamageToEnemy(player, enemyTarget, weaponDef.Damage or 20)
	end
end

local function fireMeleeAttack(player, character, origin, direction, weaponDef, state, tool)
	playMeleeSwing(tool, weaponDef, state)

	local range = math.max(1, tonumber(weaponDef.Range) or 8)
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 90
	local targets = getEnemiesInCone(character, origin, direction, range, arcDegrees)

	for _, enemyModel in ipairs(targets) do
		applyDamageToEnemy(player, enemyModel, weaponDef.Damage or 15)
	end
end

local function fireFlamethrower(player, character, weaponDef, state, handle)
	if state.isBursting then
		return
	end
	state.isBursting = true

	local burstTicks = math.max(1, math.floor((tonumber(weaponDef.BurstTicks) or 5) + 0.5))
	local burstInterval = math.max(0.03, tonumber(weaponDef.BurstIntervalSeconds) or 0.07)
	local range = math.max(4, tonumber(weaponDef.Range) or 25)
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 60
	local tickDamage = math.max(1, (tonumber(weaponDef.Damage) or 10) / burstTicks)

	task.spawn(function()
		for _ = 1, burstTicks do
			if not character.Parent then
				break
			end

			local liveRootPart = character:FindFirstChild("HumanoidRootPart")
			if not liveRootPart then
				break
			end

			local origin, direction = getWeaponOriginAndDirection(player, character, liveRootPart, handle)
			local flameEnd = origin + direction * math.min(range, 9)
			createMuzzleFlash(origin, Color3.fromRGB(255, 145, 70), 0.8, 0.08)
			createTracerSegment(origin, flameEnd, Color3.fromRGB(255, 120, 65), 0.65, 0.09)

			local targets = getEnemiesInCone(character, origin, direction, range, arcDegrees)
			for _, enemyModel in ipairs(targets) do
				applyDamageToEnemy(player, enemyModel, tickDamage)
			end

			task.wait(burstInterval)
		end

		state.isBursting = false
	end)
end

local function fireRocket(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local speed = math.max(30, tonumber(weaponDef.ProjectileSpeed) or 140)
	local range = math.max(30, tonumber(weaponDef.Range) or 120)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 16)
	local blastDamage = tonumber(weaponDef.Damage) or 100
	local aimRayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local aimRayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local aimRaycastParams = buildWeaponRaycastParams(character, {})
	local aimRaycastResult = Workspace:Raycast(aimRayOrigin, aimRayDirection * range, aimRaycastParams)
	local aimTargetPosition = aimRayOrigin + aimRayDirection * range
	if aimRaycastResult then
		aimTargetPosition = aimRaycastResult.Position
	end

	local toAimTarget = aimTargetPosition - origin
	if toAimTarget.Magnitude > 0.01 then
		direction = toAimTarget.Unit
	end

	local rocket = Instance.new("Part")
	rocket.Name = "RocketProjectile"
	rocket.Size = Vector3.new(0.45, 0.45, 2.2)
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(120, 125, 130)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanTouch = false
	rocket.CanQuery = false
	rocket.CFrame = CFrame.lookAt(origin, origin + direction)
	rocket.Parent = getEffectsFolder()
	Debris:AddItem(rocket, 8)

	local tailAttachment = Instance.new("Attachment")
	tailAttachment.Position = Vector3.new(0, 0, rocket.Size.Z * 0.5)
	tailAttachment.Parent = rocket

	local tailFire = Instance.new("Fire")
	tailFire.Size = 2.5
	tailFire.Heat = 8
	tailFire.Color = Color3.fromRGB(255, 185, 90)
	tailFire.SecondaryColor = Color3.fromRGB(255, 95, 45)
	tailFire.Parent = rocket

	task.spawn(function()
		local currentPosition = origin
		local traveled = 0
		local raycastParams = buildWeaponRaycastParams(character, { rocket })

		while rocket.Parent and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepDistance = math.min(speed * deltaTime, range - traveled)
			local raycastResult = Workspace:Raycast(currentPosition, direction * stepDistance, raycastParams)
			local stepEndPosition = currentPosition + direction * stepDistance

			local nextPosition = stepEndPosition
			local directTarget = nil
			if raycastResult then
				nextPosition = raycastResult.Position
				directTarget = resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.15)
				if fallbackEnemy then
					directTarget = fallbackEnemy
					if fallbackImpact then
						nextPosition = fallbackImpact
					end
				end
			end

			rocket.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(255, 170, 95), 0.22, 0.08)

			currentPosition = nextPosition
			traveled += stepDistance

			if raycastResult or directTarget then
				if directTarget then
					applyDamageToEnemy(player, directTarget, blastDamage)
				end

				break
			end
		end

		if rocket.Parent then
			createExplosionEffect(currentPosition, blastRadius)
			applyBlastDamage(player, currentPosition, blastRadius, blastDamage)
			rocket:Destroy()
		end
	end)
end

local function createFallbackWeaponTool(weaponDef)
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 2.2)
	handle.Color = weaponDef.Color or Color3.fromRGB(180, 180, 180)
	handle.Material = Enum.Material.Metal
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Parent = tool

	local weaponClass = resolveWeaponClass(weaponDef)
	if weaponClass == "Melee" then
		handle.Size = Vector3.new(0.7, 0.7, 2.8)
	elseif weaponClass == "Flamethrower" then
		handle.Size = Vector3.new(1.2, 1, 3.4)
	elseif weaponClass == "RPG" then
		handle.Size = Vector3.new(1.3, 1.3, 4.2)
	elseif (weaponDef.Range or 0) >= 50 then
		handle.Size = Vector3.new(1, 1, 3.2)
	end

	return tool
end

local function createCenterHandleForModel(model, tool)
	local ok, bboxCFrame, bboxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not bboxCFrame then
		return nil
	end

	local oldHandle = model:FindFirstChild("Handle", true)
	if oldHandle and oldHandle:IsA("BasePart") then
		oldHandle.Name = "VisualHandle"
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(
		math.clamp((bboxSize and bboxSize.X or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Y or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Z or 1) * 0.15, 0.2, 1)
	)
	handle.CFrame = bboxCFrame
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Anchored = false
	handle.Parent = tool
	return handle
end

local function hasWeldBetween(partA, partB)
	for _, child in partA:GetChildren() do
		if child:IsA("WeldConstraint") then
			if (child.Part0 == partA and child.Part1 == partB) or (child.Part0 == partB and child.Part1 == partA) then
				return true
			end
		end
	end
	return false
end

local function prepareToolParts(tool, handle)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= handle and not hasWeldBetween(handle, descendant) then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = handle
			end
		end
	end
end

local function normalizeTemplateKey(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function findShopItemTemplate(weaponDef)
	local shopItemsFolder = ServerStorage:FindFirstChild("ShopItems")
	if not shopItemsFolder then
		return nil
	end

	local templateName = weaponDef.TemplateName
	local templateNameLower = string.lower(templateName or "")
	local templateNameKey = normalizeTemplateKey(templateName)

	local idLower = string.lower(weaponDef.Id or "")
	local nameLower = string.lower(weaponDef.DisplayName or "")
	local idKey = normalizeTemplateKey(weaponDef.Id)
	local nameKey = normalizeTemplateKey(weaponDef.DisplayName)
	for _, child in shopItemsFolder:GetChildren() do
		local childNameLower = string.lower(child.Name)
		local childKey = normalizeTemplateKey(child.Name)

		if templateNameLower ~= "" and childNameLower == templateNameLower then
			return child
		end
		if templateNameKey ~= "" and (childKey == templateNameKey or string.find(childKey, templateNameKey, 1, true)) then
			return child
		end

		if childNameLower == idLower or childNameLower == nameLower then
			return child
		end
		if idKey ~= "" and (childKey == idKey or string.find(childKey, idKey, 1, true)) then
			return child
		end
		if nameKey ~= "" and (childKey == nameKey or string.find(childKey, nameKey, 1, true)) then
			return child
		end
	end

	return nil
end

local function createToolFromTemplate(weaponDef)
	local template = findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Tool") then
		return template:Clone()
	end

	local tool = Instance.new("Tool")
	local cloned = template:Clone()

	if template:IsA("Model") then
		cloned.Parent = tool
		local handle = createCenterHandleForModel(cloned, tool)

		if not (handle and handle:IsA("BasePart")) then
			tool:Destroy()
			warn(string.format("Shop item template '%s' could not create centered handle", template.Name))
			return nil
		end

		return tool
	end

	if template:IsA("BasePart") then
		cloned.Name = "Handle"
		cloned.Parent = tool
		return tool
	end

	tool:Destroy()
	warn(string.format("Shop item template '%s' is unsupported type %s", template.Name, template.ClassName))
	return nil
end

local function configureWeaponTool(tool, weaponDef)
	local weaponClass = resolveWeaponClass(weaponDef)

	tool.Name = weaponDef.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponDef.Id)
	tool:SetAttribute("WeaponClass", weaponClass)
	tool:SetAttribute("Damage", weaponDef.Damage)
	tool:SetAttribute("Range", weaponDef.Range)
	tool:SetAttribute("Cooldown", weaponDef.Cooldown)
	tool:SetAttribute("MagazineSize", getMagazineSize(weaponDef))
	tool:SetAttribute("ReloadSeconds", tonumber(weaponDef.ReloadSeconds))

	local handle = tool:FindFirstChild("Handle", true)
	tool.RequiresHandle = handle ~= nil
	if handle and handle:IsA("BasePart") then
		handle.CanCollide = false
		prepareToolParts(tool, handle)
	end

	local grip = CFrame.new(-0.3, -0.8, 0)
	if typeof(weaponDef.GripPositionOffset) == "Vector3" then
		grip *= CFrame.new(weaponDef.GripPositionOffset)
	end
	if typeof(weaponDef.GripRotationDeg) == "Vector3" then
		grip *= CFrame.Angles(
			math.rad(weaponDef.GripRotationDeg.X),
			math.rad(weaponDef.GripRotationDeg.Y),
			math.rad(weaponDef.GripRotationDeg.Z)
		)
	end
	tool.Grip = grip

	local state = getToolState(tool, weaponDef)
	state.baseGrip = tool.Grip
	updateAmmoAttributes(tool, weaponDef, state)

	local function fireWeapon(owner, character, humanoid, rootPart, explicitShotOrigin, explicitShotDirection)
		local now = os.clock()
		local cooldown = math.max(0.05, tonumber(weaponDef.Cooldown) or 0.25)
		if now - (state.lastActivatedAt or -math.huge) < cooldown then
			return
		end

		if state.isReloading then
			return
		end

		if weaponClass == "Flamethrower" and state.isBursting then
			return
		end

		if not tryConsumeAmmo(tool, weaponDef, state) then
			return
		end

		state.lastActivatedAt = now

		local origin, direction = getWeaponOriginAndDirection(owner, character, rootPart, handle)
		local shotOrigin, shotDirection = nil, nil
		if typeof(explicitShotOrigin) == "Vector3" and typeof(explicitShotDirection) == "Vector3" and explicitShotDirection.Magnitude > 0.001 then
			shotOrigin = explicitShotOrigin
			shotDirection = explicitShotDirection.Unit
		else
			shotOrigin, shotDirection = getPlayerShotRay(owner, rootPart, origin, direction)
		end

		if weaponClass == "Melee" then
			fireMeleeAttack(owner, character, origin, direction, weaponDef, state, tool)
		elseif weaponClass == "Flamethrower" then
			fireFlamethrower(owner, character, weaponDef, state, handle)
		elseif weaponClass == "RPG" then
			fireRocket(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
		else
			fireBulletShot(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
		end
	end

	state.fireHandler = function(owner, explicitShotOrigin, explicitShotDirection)
		if not owner or not owner:IsA("Player") then
			return
		end

		local character = owner.Character
		if not character or tool.Parent ~= character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			return
		end

		fireWeapon(owner, character, humanoid, rootPart, explicitShotOrigin, explicitShotDirection)
	end

	tool.Activated:Connect(function()
		-- Prefer explicit client fire remote for aim-accurate shots.
		if weaponFireRemote then
			return
		end

		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end

		local owner = Players:GetPlayerFromCharacter(character)
		if not owner then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			return
		end

		fireWeapon(owner, character, humanoid, rootPart, nil, nil)
	end)

	tool.Destroying:Connect(function()
		if state then
			state.fireHandler = nil
		end
		toolRuntimeState[tool] = nil
	end)
end

local function createWeaponTool(weaponDef)
	local tool = createToolFromTemplate(weaponDef)
	if not tool then
		tool = createFallbackWeaponTool(weaponDef)
	end

	configureWeaponTool(tool, weaponDef)
	return tool
end

local function getEquippedWeaponTool(player, weaponId)
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
			return child
		end
	end

	return nil
end

local function playerOwnsWeapon(player, weaponId)
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
					return true
				end
			end
		end
	end

	return false
end

local function canPurchaseNow()
	if not remotesFolder then
		return true, "Unknown"
	end

	local waveState = remotesFolder:GetAttribute("CurrentWaveState")
	if type(waveState) ~= "string" then
		return true, "Unknown"
	end

	local allowedStates = Config.Shop.PurchaseAllowedStates or {}
	if type(allowedStates[waveState]) == "boolean" then
		return allowedStates[waveState], waveState
	end

	return waveState ~= "InProgress", waveState
end

local function getCatalogForPlayer(player)
	local canPurchase, waveState = canPurchaseNow()
	local weapons = {}

	for _, weaponDef in ipairs(Config.Shop.Weapons or {}) do
		table.insert(weapons, {
			id = weaponDef.Id,
			name = weaponDef.DisplayName,
			weaponClass = resolveWeaponClass(weaponDef),
			cost = weaponDef.Cost,
			damage = weaponDef.Damage,
			range = weaponDef.Range,
			cooldown = weaponDef.Cooldown,
			magazineSize = getMagazineSize(weaponDef),
			reloadSeconds = tonumber(weaponDef.ReloadSeconds),
			owned = playerOwnsWeapon(player, weaponDef.Id),
		})
	end

	table.sort(weapons, function(a, b)
		return a.cost < b.cost
	end)

	return {
		success = true,
		canPurchase = canPurchase,
		waveState = waveState,
		weapons = weapons,
	}
end

local function grantWeapon(player, weaponDef)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	local toolForBackpack = createWeaponTool(weaponDef)
	if backpack then
		toolForBackpack.Parent = backpack
	else
		toolForBackpack:Destroy()
	end

	if starterGear then
		local toolForStarterGear = createWeaponTool(weaponDef)
		toolForStarterGear.Parent = starterGear
	end
end

local function buyWeapon(player, weaponId)
	local weaponDef = weaponById[weaponId]
	if not weaponDef then
		return {
			success = false,
			message = "Unknown weapon.",
		}
	end

	local canPurchase = canPurchaseNow()
	if not canPurchase then
		return {
			success = false,
			message = "You can only buy between waves.",
		}
	end

	if playerOwnsWeapon(player, weaponId) then
		return {
			success = false,
			message = "You already own this weapon.",
		}
	end

	local moneyValue = getMoneyValue(player)
	if not moneyValue then
		return {
			success = false,
			message = "Money data not available.",
		}
	end

	if moneyValue.Value < weaponDef.Cost then
		return {
			success = false,
			message = "Not enough money.",
		}
	end

	moneyValue.Value -= weaponDef.Cost
	grantWeapon(player, weaponDef)

	return {
		success = true,
		message = string.format("Bought %s for $%d", weaponDef.DisplayName, weaponDef.Cost),
	}
end

local function ensureTraderPrompt()
	local traderConfig = Config.Shop.Trader or {}
	local modelName = traderConfig.ModelName or "WeaponTrader"
	local partName = traderConfig.PartName or "TraderRoot"

	local traderModel = Workspace:FindFirstChild(modelName)
	if not (traderModel and traderModel:IsA("Model")) then
		traderModel = Instance.new("Model")
		traderModel.Name = modelName
		traderModel.Parent = Workspace
	end

	local rootPart = traderModel:FindFirstChild(partName)
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = traderModel:FindFirstChildWhichIsA("BasePart")
	end

	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = partName
		rootPart.Size = Vector3.new(3, 6, 2)
		rootPart.Color = Color3.fromRGB(120, 85, 70)
		rootPart.Material = Enum.Material.WoodPlanks
		rootPart.Anchored = true
		rootPart.CFrame = CFrame.new(traderConfig.Position or Vector3.new(0, 4, -25))
		rootPart.Parent = traderModel
	end

	traderModel.PrimaryPart = rootPart

	local prompt = rootPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = rootPart
	end

	prompt.ActionText = traderConfig.ActionText or "Open Store"
	prompt.ObjectText = traderConfig.ObjectText or "Weapon Trader"
	prompt.MaxActivationDistance = traderConfig.MaxActivationDistance or 12
	prompt.HoldDuration = traderConfig.HoldDuration or 0.15
	prompt.RequiresLineOfSight = false

	prompt.Triggered:Connect(function(player)
		if shopOpenRemote then
			shopOpenRemote:FireClient(player)
		end
	end)
end

function ShopService.start()
	if started then
		return
	end
	started = true

	for _, weaponDef in ipairs(Config.Shop.Weapons or {}) do
		weaponById[weaponDef.Id] = weaponDef
	end

	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		warn("ShopService could not find remotes folder")
		return
	end

	shopOpenRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.ShopOpen)
	shopGetCatalogFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopGetCatalog)
	shopBuyWeaponFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyWeapon)
	weaponAimRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponAim)
	weaponFireRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponFire)

	shopGetCatalogFunction.OnServerInvoke = function(player)
		return getCatalogForPlayer(player)
	end

	shopBuyWeaponFunction.OnServerInvoke = function(player, weaponId)
		if type(weaponId) ~= "string" then
			return {
				success = false,
				message = "Invalid purchase request.",
			}
		end

		return buyWeapon(player, weaponId)
	end

	if weaponAimRemote then
		weaponAimRemote.OnServerEvent:Connect(function(player, hitPosition, lookDirection, cameraOrigin)
			updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
		end)
	end

	if weaponFireRemote then
		weaponFireRemote.OnServerEvent:Connect(function(player, weaponId, hitPosition, lookDirection, cameraOrigin)
			if typeof(hitPosition) == "Vector3" and typeof(lookDirection) == "Vector3" then
				updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
			end

			local tool = getEquippedWeaponTool(player, weaponId)
			if not tool then
				return
			end

			local state = toolRuntimeState[tool]
			if not state or type(state.fireHandler) ~= "function" then
				return
			end

			local explicitShotOrigin = nil
			local explicitShotDirection = nil
			if typeof(cameraOrigin) == "Vector3" and typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
				explicitShotOrigin = cameraOrigin
				explicitShotDirection = lookDirection.Unit
			end

			state.fireHandler(player, explicitShotOrigin, explicitShotDirection)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		playerAimState[player] = nil
	end)

	ensureTraderPrompt()
end

return ShopService
