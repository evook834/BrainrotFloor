--[[
	SentryTurretController — Deploy/place turrets, combat loop, healthbar UI.
	Placement: resolveSentryPlacementCFrame, resolveSentryPlacementPivotCFrame,
	resolveUprightSentryReferencePlacementCFrame, applySentryPlacementRotationOffset,
	alignPivotYawToDirection, resolveSentryPlacementReferencePart.
	Deploy + repair: deploySentryTurret, repairOwnedSentries.
	Targeting/combat: findTurretTarget, pickTurretTargetCandidate, startTurretCombatLoop,
	fireTurretRocketBurst, getTurretBurstRocketDirection.
	Healthbar: attachTurretHealthBar, getTurretFillColor.
	Helpers: isEnemyModelAlive, getEnemyModelHealth.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local AimResolver = require(Match.Combat.AimResolver)
local WeaponVfx = require(script.Parent.WeaponVfx)
local WeaponToolSetup = require(script.Parent.WeaponToolSetup)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local ShopConstants = require(Match.Shop.ShopConstants)

local MAX_SENTRY_COUNT_PER_PLAYER = ShopConstants.MAX_SENTRY_COUNT_PER_PLAYER
local SENTRY_REPAIR_INTERRUPT_SECONDS = ShopConstants.SENTRY_REPAIR_INTERRUPT_SECONDS
local DEFAULT_TURRET_ROCKET_SPREAD_DEGREES = ShopConstants.DEFAULT_TURRET_ROCKET_SPREAD_DEGREES
local TURRET_ROCKET_BURST_MODE_TOKEN = ShopConstants.TURRET_ROCKET_BURST_MODE_TOKEN

local sentryRuntime = nil
local fireRocket = nil

function init(options)
	if type(options) == "table" then
		if options.sentryRuntime ~= nil then
			sentryRuntime = options.sentryRuntime
		end
		if options.fireRocket ~= nil then
			fireRocket = options.fireRocket
		end
	end
end

local function getEnemyContainer()
	return Workspace:FindFirstChild(Config.Enemy.ContainerName)
end

local function getSentryTurretFolder()
	if sentryRuntime then
		return sentryRuntime.getSentryTurretFolder()
	end
	return nil
end

local function getEffectsFolder()
	return WeaponVfx.getEffectsFolder()
end

local function normalizeWeaponToken(token)
	return WeaponToolSetup.normalizeWeaponToken(token)
end

-- Health helpers
local function isEnemyModelAlive(enemyModel)
	if not enemyModel or not enemyModel.Parent then
		return false
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid.Health > 0
	end

	local health = enemyModel:GetAttribute("EnemyHealth")
	if type(health) ~= "number" then
		return true
	end

	return health > 0
end

local function getEnemyModelHealth(enemyModel)
	if not enemyModel or not enemyModel.Parent then
		return nil, nil
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local currentHealth = tonumber(humanoid.Health)
		local maxHealth = tonumber(humanoid.MaxHealth)
		if type(maxHealth) ~= "number" or maxHealth <= 0 then
			maxHealth = 1
		end
		return currentHealth, maxHealth
	end

	local currentHealth = enemyModel:GetAttribute("EnemyHealth")
	if type(currentHealth) ~= "number" then
		return nil, nil
	end

	local maxHealth = enemyModel:GetAttribute("EnemyMaxHealth")
	if type(maxHealth) ~= "number" or maxHealth <= 0 then
		maxHealth = math.max(1, currentHealth)
	end

	return currentHealth, maxHealth
end

-- Healthbar UI
local function getTurretFillColor(healthRatio)
	if healthRatio <= 0.2 then
		return Color3.fromRGB(220, 65, 60)
	end
	if healthRatio <= 0.5 then
		return Color3.fromRGB(230, 165, 60)
	end
	return Color3.fromRGB(70, 220, 105)
end

local function attachTurretHealthBar(model, rootPart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TurretHealthBar"
	billboard.Adornee = rootPart
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Size = UDim2.fromOffset(96, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	billboard.Parent = model

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 0, 8)
	background.Position = UDim2.fromOffset(0, 0)
	background.BackgroundColor3 = Color3.fromRGB(28, 32, 36)
	background.BackgroundTransparency = 0.2
	background.BorderSizePixel = 0
	background.Parent = billboard

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, 6)
	backgroundCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 220, 105)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local ammoText = Instance.new("TextLabel")
	ammoText.Name = "AmmoText"
	ammoText.BackgroundTransparency = 1
	ammoText.Size = UDim2.new(1, 0, 0, 14)
	ammoText.Position = UDim2.fromOffset(0, 10)
	ammoText.Font = Enum.Font.GothamSemibold
	ammoText.TextSize = 11
	ammoText.TextXAlignment = Enum.TextXAlignment.Center
	ammoText.TextYAlignment = Enum.TextYAlignment.Center
	ammoText.TextColor3 = Color3.fromRGB(195, 220, 255)
	ammoText.TextStrokeTransparency = 0.35
	ammoText.Text = "Ammo 0/0"
	ammoText.Parent = billboard

	return fill, ammoText
end

-- Targeting
local function pickTurretTargetCandidate(bestCandidate, candidate, preferredModel)
	if not bestCandidate then
		return candidate
	end

	if candidate.health < bestCandidate.health then
		return candidate
	end
	if candidate.health > bestCandidate.health then
		return bestCandidate
	end

	if candidate.distance < bestCandidate.distance then
		return candidate
	end
	if candidate.distance > bestCandidate.distance then
		return bestCandidate
	end

	if preferredModel then
		if candidate.model == preferredModel and bestCandidate.model ~= preferredModel then
			return candidate
		end
		if bestCandidate.model == preferredModel and candidate.model ~= preferredModel then
			return bestCandidate
		end
	end

	return bestCandidate
end

local function findTurretTarget(record, muzzleOrigin)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		record.currentTarget = nil
		return nil, nil
	end

	local maxRange = math.max(100, tonumber(record.acquireRange) or 100000)
	local preferredModel = record.currentTarget
	local bestCandidate = nil

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { record.model, getEffectsFolder() }
	raycastParams.IgnoreWater = true

	local function buildCandidate(enemyModel)
		if not enemyModel:IsA("Model") or not isEnemyModelAlive(enemyModel) then
			return nil
		end

		local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
		if not enemyRoot then
			return nil
		end

		local delta = enemyRoot.Position - muzzleOrigin
		local distance = delta.Magnitude
		if distance <= 0.01 or distance > maxRange then
			return nil
		end

		local hitResult = Workspace:Raycast(muzzleOrigin, delta, raycastParams)
		local isVisible = false
		if not hitResult then
			isVisible = true
		else
			isVisible = hitResult.Instance and hitResult.Instance:IsDescendantOf(enemyModel)
		end
		if not isVisible then
			return nil
		end

		local currentHealth = getEnemyModelHealth(enemyModel)
		local resolvedHealth = math.huge
		if type(currentHealth) == "number" then
			resolvedHealth = math.max(0, currentHealth)
		end

		return {
			model = enemyModel,
			root = enemyRoot,
			distance = distance,
			health = resolvedHealth,
		}
	end

	-- Hard target lock: keep current target until dead or out of range.
	if preferredModel and preferredModel.Parent then
		local preferredRoot = ModelRootResolver.resolveRootPart(preferredModel)
		if preferredRoot and isEnemyModelAlive(preferredModel) then
			local preferredDelta = preferredRoot.Position - muzzleOrigin
			local preferredDistance = preferredDelta.Magnitude
			if preferredDistance > 0.01 and preferredDistance <= maxRange then
				record.currentTarget = preferredModel
				return preferredModel, preferredRoot
			end
		end
	end

	for _, enemyModel in ipairs(enemyContainer:GetChildren()) do
		local candidate = buildCandidate(enemyModel)
		if candidate then
			bestCandidate = pickTurretTargetCandidate(bestCandidate, candidate, preferredModel)
		end
	end

	if bestCandidate then
		record.currentTarget = bestCandidate.model
		return bestCandidate.model, bestCandidate.root
	end

	record.currentTarget = nil
	return nil, nil
end

local function getTurretBurstRocketDirection(baseDirection, rocketIndex, rocketCount, spreadDegrees)
	local normalizedDirection = baseDirection
	if typeof(normalizedDirection) ~= "Vector3" or normalizedDirection.Magnitude <= 0.001 then
		normalizedDirection = Vector3.new(0, 0, -1)
	else
		normalizedDirection = normalizedDirection.Unit
	end

	if rocketCount <= 1 or spreadDegrees <= 0 then
		return normalizedDirection
	end

	local spacingRadians = math.rad(spreadDegrees)
	local offsetRadians = (rocketIndex - ((rocketCount + 1) * 0.5)) * spacingRadians
	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, offsetRadians)
	local rotated = rotation:VectorToWorldSpace(normalizedDirection)
	if rotated.Magnitude <= 0.001 then
		return normalizedDirection
	end

	return rotated.Unit
end

local function fireTurretRocketBurst(record, muzzleOrigin, lookDirection, turretShotDamage)
	if not fireRocket then
		return 0
	end

	local ammo = math.max(0, math.floor((tonumber(record.ammo) or 0) + 0.5))
	if ammo <= 0 then
		return 0
	end

	local rocketCount = math.max(1, math.floor((tonumber(record.turretRocketCount) or 1) + 0.5))
	local rocketsToFire = math.min(rocketCount, ammo)
	if rocketsToFire <= 0 then
		return 0
	end

	local rocketRange = math.max(20, tonumber(record.turretRocketRange) or tonumber(record.acquireRange) or 120)
	local rocketBlastRadius = math.max(4, tonumber(record.turretRocketBlastRadius) or 8)
	local rocketProjectileSpeed = math.max(30, tonumber(record.turretRocketProjectileSpeed) or 140)
	local rocketSpreadDegrees = math.max(0, tonumber(record.turretRocketSpreadDegrees) or DEFAULT_TURRET_ROCKET_SPREAD_DEGREES)

	local rocketWeaponDef = {
		Damage = turretShotDamage,
		Range = rocketRange,
		BlastRadius = rocketBlastRadius,
		ProjectileSpeed = rocketProjectileSpeed,
	}
	local damageContext = {
		applyClassMultiplier = false,
		allowBurnOnHit = false,
		allowCriticalHits = false,
	}

	for rocketIndex = 1, rocketsToFire do
		local rocketDirection = getTurretBurstRocketDirection(lookDirection, rocketIndex, rocketsToFire, rocketSpreadDegrees)
		fireRocket(record.owner, record.model, muzzleOrigin, rocketDirection, rocketWeaponDef, muzzleOrigin, rocketDirection, damageContext)
	end

	return rocketsToFire
end

-- Placement helpers
local function getHorizontalUnitDirection(vector)
	if typeof(vector) ~= "Vector3" then
		return nil
	end

	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end

	return horizontal.Unit
end

local function alignPivotYawToDirection(pivotCFrame, desiredLookDirection, desiredPosition)
	local pivotPosition = desiredPosition
	if typeof(pivotPosition) ~= "Vector3" then
		pivotPosition = pivotCFrame.Position
	end

	local targetForward = getHorizontalUnitDirection(desiredLookDirection)
	local currentForward = getHorizontalUnitDirection(pivotCFrame.LookVector)
	if not currentForward then
		currentForward = getHorizontalUnitDirection(pivotCFrame.RightVector)
	end

	if not targetForward then
		targetForward = currentForward or Vector3.new(0, 0, -1)
	end

	if not currentForward then
		return CFrame.lookAt(pivotPosition, pivotPosition + targetForward)
	end

	local yawDot = math.clamp(currentForward:Dot(targetForward), -1, 1)
	local yawRadians = math.acos(yawDot)
	if currentForward:Cross(targetForward).Y < 0 then
		yawRadians = -yawRadians
	end

	local baseRotation = pivotCFrame - pivotCFrame.Position
	local yawRotation = CFrame.fromAxisAngle(Vector3.yAxis, yawRadians)
	return CFrame.new(pivotPosition) * yawRotation * baseRotation
end

local function resolveSentryPlacementReferencePart(sentryModel)
	if not sentryModel or not sentryModel:IsA("Model") then
		return nil
	end

	local handle = sentryModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return ModelRootResolver.resolveRootPart(sentryModel)
end

local function resolveSentryPlacementPivotCFrame(sentryModel, referencePlacementCFrame)
	local referencePart = resolveSentryPlacementReferencePart(sentryModel)
	if not referencePart then
		return referencePlacementCFrame
	end

	local currentPivot = sentryModel:GetPivot()
	local referenceToPivot = referencePart.CFrame:ToObjectSpace(currentPivot)
	return referencePlacementCFrame * referenceToPivot
end

local function resolveSentryPlacementRotationOffsetCFrame(weaponDef)
	if type(weaponDef) ~= "table" then
		return CFrame.new()
	end

	local rotationDeg = weaponDef.TurretPlacementRotationDeg
	if typeof(rotationDeg) ~= "Vector3" then
		return CFrame.new()
	end

	return CFrame.Angles(
		math.rad(rotationDeg.X),
		math.rad(rotationDeg.Y),
		math.rad(rotationDeg.Z)
	)
end

local function applySentryPlacementRotationOffset(referencePlacementCFrame, weaponDef)
	return referencePlacementCFrame * resolveSentryPlacementRotationOffsetCFrame(weaponDef)
end

local function resolveUprightSentryReferencePlacementCFrame(sentryModel, referencePlacementCFrame, desiredLookDirection)
	local desiredFlatLook = getHorizontalUnitDirection(desiredLookDirection)
	local forwardAxis = referencePlacementCFrame.LookVector
	local rightAxis = referencePlacementCFrame.RightVector

	local candidateRotations = {
		CFrame.new(),
		CFrame.fromAxisAngle(forwardAxis, math.pi),
		CFrame.fromAxisAngle(forwardAxis, math.pi * 0.5),
		CFrame.fromAxisAngle(forwardAxis, -math.pi * 0.5),
		CFrame.fromAxisAngle(rightAxis, math.pi * 0.5),
		CFrame.fromAxisAngle(rightAxis, -math.pi * 0.5),
		CFrame.fromAxisAngle(rightAxis, math.pi),
	}

	local bestReferencePlacementCFrame = referencePlacementCFrame
	local bestScore = -math.huge

	for _, rotation in ipairs(candidateRotations) do
		local candidateReferencePlacementCFrame = referencePlacementCFrame * rotation
		local candidatePivotCFrame = resolveSentryPlacementPivotCFrame(sentryModel, candidateReferencePlacementCFrame)
		local upScore = candidatePivotCFrame.UpVector.Y
		local facingScore = 0
		if desiredFlatLook then
			local candidateFlatLook = getHorizontalUnitDirection(candidatePivotCFrame.LookVector)
			if candidateFlatLook then
				facingScore = desiredFlatLook:Dot(candidateFlatLook)
			end
		end

		local totalScore = upScore * 10 + facingScore
		if totalScore > bestScore then
			bestScore = totalScore
			bestReferencePlacementCFrame = candidateReferencePlacementCFrame
		end
	end

	return bestReferencePlacementCFrame
end

local function startTurretCombatLoop(record)
	if not sentryRuntime then
		return
	end

	task.spawn(function()
		while record.model.Parent and record.humanoid.Parent and record.humanoid.Health > 0 do
			task.wait(math.max(0.05, tonumber(record.thinkInterval) or 0.08))

			local rootPart = ModelRootResolver.resolveRootPart(record.model)
			if not rootPart then
				continue
			end

			local maxAmmo = tonumber(record.maxAmmo)
			if type(maxAmmo) ~= "number" or maxAmmo <= 0 then
				local modelMaxAmmo = if record.model and record.model:IsA("Model") then record.model:GetAttribute("TurretMaxAmmo") else nil
				maxAmmo = tonumber(modelMaxAmmo)
			end
			if type(maxAmmo) ~= "number" or maxAmmo <= 0 then
				maxAmmo = sentryRuntime.resolveTurretMaxAmmo(record.weaponDef)
			end
			maxAmmo = math.max(1, math.floor(maxAmmo + 0.5))
			record.maxAmmo = maxAmmo
			record.ammo = math.clamp(math.floor((tonumber(record.ammo) or maxAmmo) + 0.5), 0, maxAmmo)
			if record.ammo <= 0 then
				sentryRuntime.syncSentryAmmoAttributes(record)
				continue
			end

			local now = os.clock()
			if now - (record.lastFireAt or -math.huge) < math.max(0.05, tonumber(record.fireCooldown) or 0.2) then
				continue
			end

			local muzzleOrigin = rootPart.Position + Vector3.new(0, rootPart.Size.Y * 0.35, 0)
			local enemyModel, enemyRoot = findTurretTarget(record, muzzleOrigin)
			if not enemyModel or not enemyRoot then
				continue
			end

			record.lastFireAt = now
			local toEnemy = enemyRoot.Position - muzzleOrigin
			local lookDirection = if toEnemy.Magnitude > 0.01 then toEnemy.Unit else rootPart.CFrame.LookVector
			local turretDamageMultiplier = 1
			if record.owner and record.owner:IsA("Player") then
				turretDamageMultiplier = math.max(0, ClassService.getTurretDamageMultiplier(record.owner))
			end
			local turretShotDamage = math.max(0, record.damage * turretDamageMultiplier)
			if turretShotDamage <= 0 then
				continue
			end

			local shotsConsumed = 1
			if normalizeWeaponToken(record.turretAttackMode) == TURRET_ROCKET_BURST_MODE_TOKEN then
				WeaponVfx.createMuzzleFlash(muzzleOrigin, Color3.fromRGB(255, 190, 120), 0.26, 0.06)
				shotsConsumed = fireTurretRocketBurst(record, muzzleOrigin, lookDirection, turretShotDamage)
				if shotsConsumed <= 0 then
					continue
				end
			else
				WeaponVfx.createMuzzleFlash(muzzleOrigin, Color3.fromRGB(120, 225, 255), 0.22, 0.05)
				WeaponVfx.createTracerSegment(muzzleOrigin, enemyRoot.Position, Color3.fromRGB(120, 225, 255), 0.1, 0.05)
				EnemyDamageService.applyDamageToEnemy(record.owner, enemyModel, turretShotDamage, nil, {
					applyClassMultiplier = false,
					allowBurnOnHit = false,
					allowCriticalHits = false,
				})
			end

			record.ammo = math.max(0, record.ammo - shotsConsumed)
			sentryRuntime.syncSentryAmmoAttributes(record)

			local flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
			if flatLook.Magnitude > 0.01 then
				local referencePart = resolveSentryPlacementReferencePart(record.model)
				if referencePart then
					local desiredReferencePlacementCFrame = CFrame.lookAt(referencePart.Position, referencePart.Position + flatLook.Unit)
					desiredReferencePlacementCFrame = resolveUprightSentryReferencePlacementCFrame(record.model, desiredReferencePlacementCFrame, flatLook)
					desiredReferencePlacementCFrame = applySentryPlacementRotationOffset(desiredReferencePlacementCFrame, record.weaponDef)
					record.model:PivotTo(resolveSentryPlacementPivotCFrame(record.model, desiredReferencePlacementCFrame))
				else
					local currentPivot = record.model:GetPivot()
					record.model:PivotTo(alignPivotYawToDirection(currentPivot, flatLook, rootPart.Position))
				end
			end
		end

		if record.model and record.model.Parent then
			record.model:Destroy()
		end
		sentryRuntime.removeRecord(record.model)
	end)
end

local function resolveSentryPlacementCFrame(player, character, rootPart, sentryModel, weaponDef, explicitShotOrigin, explicitShotDirection)
	local fallbackOrigin = rootPart.Position + Vector3.new(0, 1.5, 0)
	local fallbackDirection = rootPart.CFrame.LookVector
	local rayDirection = nil

	local aimState = AimResolver.getFreshAimState(player)
	if aimState and typeof(aimState.hitPosition) == "Vector3" then
		local toAimHit = aimState.hitPosition - fallbackOrigin
		if toAimHit.Magnitude > 0.01 then
			rayDirection = toAimHit.Unit
		end
	end

	if typeof(rayDirection) ~= "Vector3" or rayDirection.Magnitude <= 0.001 then
		local fallbackRayDirection = explicitShotDirection
		if typeof(fallbackRayDirection) ~= "Vector3" or fallbackRayDirection.Magnitude <= 0.001 then
			_, fallbackRayDirection = AimResolver.getPlayerShotRay(player, rootPart, fallbackOrigin, fallbackDirection)
		end

		rayDirection = if typeof(fallbackRayDirection) == "Vector3" then fallbackRayDirection.Unit else fallbackDirection
	end

	local maxDistance = math.max(15, tonumber(weaponDef.TurretPlacementDistance) or tonumber(weaponDef.Range) or 180)
	local raycastExclusions = {}
	local enemyContainer = getEnemyContainer()
	if enemyContainer then
		table.insert(raycastExclusions, enemyContainer)
	end
	local sentryFolder = getSentryTurretFolder()
	if sentryFolder then
		table.insert(raycastExclusions, sentryFolder)
	end
	local raycastParams = AimResolver.buildWeaponRaycastParams(character, raycastExclusions)
	local hitResult = Workspace:Raycast(fallbackOrigin, rayDirection.Unit * maxDistance, raycastParams)
	if not hitResult then
		return nil
	end

	if hitResult.Normal.Y < 0.55 then
		return nil
	end

	local ok, _, boundsSize = pcall(function()
		return sentryModel:GetBoundingBox()
	end)
	if not ok or not boundsSize then
		return nil
	end

	local lookDirection = Vector3.new(rayDirection.X, 0, rayDirection.Z)
	if lookDirection.Magnitude <= 0.01 then
		lookDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	if lookDirection.Magnitude <= 0.01 then
		lookDirection = Vector3.new(0, 0, -1)
	end

	local placementPosition = hitResult.Position + Vector3.new(0, (boundsSize.Y * 0.5) + 0.05, 0)
	local referencePlacementCFrame = CFrame.lookAt(placementPosition, placementPosition + lookDirection.Unit)
	referencePlacementCFrame = resolveUprightSentryReferencePlacementCFrame(sentryModel, referencePlacementCFrame, lookDirection)
	referencePlacementCFrame = applySentryPlacementRotationOffset(referencePlacementCFrame, weaponDef)
	local placementCFrame = resolveSentryPlacementPivotCFrame(sentryModel, referencePlacementCFrame)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapExclusions = { character, getEffectsFolder() }
	if enemyContainer then
		table.insert(overlapExclusions, enemyContainer)
	end
	overlapParams.FilterDescendantsInstances = overlapExclusions

	local padding = Vector3.new(0.25, 0.25, 0.25)
	local overlaps = Workspace:GetPartBoundsInBox(referencePlacementCFrame, boundsSize + padding, overlapParams)
	for _, part in ipairs(overlaps) do
		if part and part.Parent and part.CanCollide then
			return nil
		end
	end

	return placementCFrame
end

local function deploySentryTurret(player, character, rootPart, weaponDef, explicitShotOrigin, explicitShotDirection)
	if not sentryRuntime then
		return false
	end

	local activeCount = sentryRuntime.prunePlayerSentries(player)
	if activeCount >= MAX_SENTRY_COUNT_PER_PLAYER then
		return false
	end
	if sentryRuntime.countPlayerSentriesByKind(player, weaponDef.Id) >= 1 then
		return false
	end

	local sentryModel = WeaponToolSetup.buildSentryModelFromTemplate(weaponDef)
	if not sentryModel then
		return false
	end

	local placementCFrame = resolveSentryPlacementCFrame(
		player,
		character,
		rootPart,
		sentryModel,
		weaponDef,
		explicitShotOrigin,
		explicitShotDirection
	)
	if not placementCFrame then
		sentryModel:Destroy()
		return false
	end

	local root = ModelRootResolver.resolveRootPart(sentryModel)
	if not root then
		sentryModel:Destroy()
		return false
	end

	local turretMaxHealth = math.max(50, tonumber(weaponDef.TurretMaxHealth) or 420)
	local turretDamage = math.max(1, tonumber(weaponDef.TurretDamage) or 26)
	local turretFireCooldown = math.max(0.05, tonumber(weaponDef.TurretFireCooldown) or 0.2)
	local turretAcquireRange = math.max(100, tonumber(weaponDef.TurretAcquireRange) or 100000)
	local turretThinkInterval = math.max(0.05, tonumber(weaponDef.TurretThinkInterval) or 0.08)
	local turretAttackMode = normalizeWeaponToken(weaponDef.TurretAttackMode or "Bullet")
	local turretRocketCount = math.max(1, math.floor((tonumber(weaponDef.TurretRocketCount) or 1) + 0.5))
	local turretRocketBlastRadius = math.max(4, tonumber(weaponDef.TurretRocketBlastRadius) or 8)
	local turretRocketProjectileSpeed = math.max(30, tonumber(weaponDef.TurretRocketProjectileSpeed) or 140)
	local turretRocketRange = math.max(20, tonumber(weaponDef.TurretRocketRange) or tonumber(weaponDef.Range) or 180)
	local turretRocketSpreadDegrees = math.max(0, tonumber(weaponDef.TurretRocketSpreadDegrees) or DEFAULT_TURRET_ROCKET_SPREAD_DEGREES)
	local turretMaxAmmo = sentryRuntime.resolveTurretMaxAmmo(weaponDef)
	local turretInitialAmmo = sentryRuntime.resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)

	for _, descendant in ipairs(sentryModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = true
			descendant.CanQuery = true
		end
	end

	local humanoid = sentryModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = sentryModel
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = turretMaxHealth
	humanoid.Health = turretMaxHealth

	sentryModel.Name = string.format("Sentry_%d_%d", player.UserId, math.floor(os.clock() * 1000))
	sentryModel:SetAttribute("IsSentryTurret", true)
	sentryModel:SetAttribute("SentryOwnerUserId", player.UserId)
	sentryModel:SetAttribute("SentryOwnerName", player.Name)
	sentryModel:SetAttribute("TurretMaxHealth", turretMaxHealth)
	sentryModel:SetAttribute("TurretHealth", turretMaxHealth)
	sentryModel:SetAttribute("TurretLastDamagedAt", -1)
	sentryModel:SetAttribute("TurretMaxAmmo", turretMaxAmmo)
	sentryModel:SetAttribute("TurretAmmo", turretInitialAmmo)
	sentryModel:SetAttribute("TurretOutOfAmmo", turretInitialAmmo <= 0)

	local turretFolder = getSentryTurretFolder()
	sentryModel.Parent = turretFolder
	sentryModel:PivotTo(placementCFrame)

	local healthFill, ammoLabel = attachTurretHealthBar(sentryModel, root)
	local record = {
		owner = player,
		kindId = tostring(weaponDef.Id or ""),
		model = sentryModel,
		humanoid = humanoid,
		damage = turretDamage,
		fireCooldown = turretFireCooldown,
		acquireRange = turretAcquireRange,
		thinkInterval = turretThinkInterval,
		turretAttackMode = turretAttackMode,
		turretRocketCount = turretRocketCount,
		turretRocketBlastRadius = turretRocketBlastRadius,
		turretRocketProjectileSpeed = turretRocketProjectileSpeed,
		turretRocketRange = turretRocketRange,
		turretRocketSpreadDegrees = turretRocketSpreadDegrees,
		maxAmmo = turretMaxAmmo,
		ammo = turretInitialAmmo,
		lastFireAt = -math.huge,
		lastDamagedAt = -1,
		currentTarget = nil,
		healthFill = healthFill,
		ammoLabel = ammoLabel,
		connections = {},
		weaponDef = weaponDef,
	}
	sentryRuntime.registerRecord(player, sentryModel, record)
	sentryRuntime.syncSentryAmmoAttributes(record)

	local function refreshHealthVisuals(newHealth, previousHealth)
		local resolvedHealth = math.clamp(tonumber(newHealth) or 0, 0, turretMaxHealth)
		if previousHealth ~= nil and resolvedHealth < previousHealth then
			record.lastDamagedAt = os.clock()
			sentryModel:SetAttribute("TurretLastDamagedAt", record.lastDamagedAt)
		end

		sentryModel:SetAttribute("TurretHealth", resolvedHealth)
		if record.healthFill then
			local healthRatio = math.clamp(resolvedHealth / turretMaxHealth, 0, 1)
			record.healthFill.Size = UDim2.fromScale(healthRatio, 1)
			record.healthFill.BackgroundColor3 = getTurretFillColor(healthRatio)
		end
	end

	local previousHealth = humanoid.Health
	table.insert(record.connections, humanoid.HealthChanged:Connect(function(newHealth)
		refreshHealthVisuals(newHealth, previousHealth)
		previousHealth = math.clamp(tonumber(newHealth) or 0, 0, turretMaxHealth)
	end))

	table.insert(record.connections, humanoid.Died:Connect(function()
		if sentryModel and sentryModel.Parent then
			sentryModel:Destroy()
		end
	end))

	table.insert(record.connections, sentryModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			sentryRuntime.removeRecord(sentryModel)
		end
	end))

	refreshHealthVisuals(humanoid.Health)
	startTurretCombatLoop(record)
	return true
end

local function repairOwnedSentries(player, weaponDef)
	if not sentryRuntime then
		return
	end

	local records = sentryRuntime.getPlayerSentryModels(player)
	if not records or #records == 0 then
		return
	end

	sentryRuntime.prunePlayerSentries(player)
	records = sentryRuntime.getPlayerSentryModels(player)
	if not records or #records == 0 then
		return
	end

	local repairPerSecond = math.max(0, tonumber(weaponDef.RepairPerSecond) or 24)
	if repairPerSecond <= 0 then
		return
	end

	local character = player.Character
	local playerRootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not playerRootPart then
		return
	end

	local repairDistance = math.max(2, tonumber(weaponDef.RepairDistance) or 12)
	local repairDistanceSquared = repairDistance * repairDistance
	local repairSpeedMultiplier = math.max(0.1, ClassService.getRepairSpeedMultiplier(player))
	local tickSeconds = math.max(0.05, tonumber(weaponDef.Cooldown) or 0.2)
	local repairAmount = repairPerSecond * repairSpeedMultiplier * tickSeconds
	if repairAmount <= 0 then
		return
	end

	local now = os.clock()
	for _, model in ipairs(records) do
		local record = sentryRuntime.getRecord(model)
		local humanoid = record and record.humanoid
		if record and humanoid and humanoid.Parent and humanoid.Health > 0 then
			local turretRoot = ModelRootResolver.resolveRootPart(model)
			if not turretRoot then
				continue
			end

			local delta = turretRoot.Position - playerRootPart.Position
			if delta:Dot(delta) > repairDistanceSquared then
				continue
			end

			if now - (record.lastDamagedAt or -math.huge) > SENTRY_REPAIR_INTERRUPT_SECONDS then
				local maxHealth = math.max(1, humanoid.MaxHealth)
				if humanoid.Health < maxHealth then
					humanoid.Health = math.clamp(humanoid.Health + repairAmount, 0, maxHealth)
				end
			end
		end
	end
end

return {
	init = init,
	resolveSentryPlacementCFrame = resolveSentryPlacementCFrame,
	resolveSentryPlacementPivotCFrame = resolveSentryPlacementPivotCFrame,
	resolveUprightSentryReferencePlacementCFrame = resolveUprightSentryReferencePlacementCFrame,
	applySentryPlacementRotationOffset = applySentryPlacementRotationOffset,
	alignPivotYawToDirection = alignPivotYawToDirection,
	resolveSentryPlacementReferencePart = resolveSentryPlacementReferencePart,
	deploySentryTurret = deploySentryTurret,
	repairOwnedSentries = repairOwnedSentries,
	findTurretTarget = findTurretTarget,
	pickTurretTargetCandidate = pickTurretTargetCandidate,
	startTurretCombatLoop = startTurretCombatLoop,
	fireTurretRocketBurst = fireTurretRocketBurst,
	getTurretBurstRocketDirection = getTurretBurstRocketDirection,
	attachTurretHealthBar = attachTurretHealthBar,
	getTurretFillColor = getTurretFillColor,
	isEnemyModelAlive = isEnemyModelAlive,
	getEnemyModelHealth = getEnemyModelHealth,
}
