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
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)
local Match = script.Parent.Parent.Parent
local Weapons = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local AimResolver = require(Match.Combat.AimResolver)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local ShopConstants = require(Match.Shop.ShopConstants)
local WeaponVfx = require(Weapons.Combat.WeaponVfx)
local WeaponToolSetup = require(Weapons.Tools.WeaponToolSetup)
local SentryStatResolver = require(script.Parent.Stats.SentryStatResolver)
local SentryPlacement = require(script.Parent.Placement.SentryPlacement)
local SentryHealthBar = require(script.Parent.UI.SentryHealthBar)
local SentryTargeting = require(script.Parent.Targeting.SentryTargeting)

local MAX_SENTRY_COUNT_PER_PLAYER = ShopConstants.MAX_SENTRY_COUNT_PER_PLAYER
local SENTRY_REPAIR_INTERRUPT_SECONDS = ShopConstants.SENTRY_REPAIR_INTERRUPT_SECONDS
local DEFAULT_TURRET_ROCKET_SPREAD_DEGREES = ShopConstants.DEFAULT_TURRET_ROCKET_SPREAD_DEGREES
local TURRET_ROCKET_BURST_MODE_TOKEN = ShopConstants.TURRET_ROCKET_BURST_MODE_TOKEN

-- Placement and combat tuning (named for scalability)
local PLACEMENT_ORIGIN_OFFSET_Y = 1.5
local MIN_FLOOR_NORMAL_Y = 0.55
local PLACEMENT_BOUNDS_OFFSET_Y = 0.05
local OVERLAP_PADDING = 0.25
local MUZZLE_HEIGHT_RATIO = 0.35

local sentryRuntime = nil
local fireRocket = nil

-- Singleton-style init; call once with sentryRuntime and fireRocket from bootstrap (e.g. ShopService).
function init(options)
	local opts = options or {}
	sentryRuntime = opts.sentryRuntime
	fireRocket = opts.fireRocket
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
local sentryTargeting = SentryTargeting.new({
	modelRootResolver = ModelRootResolver,
	getEnemyContainer = getEnemyContainer,
	getEffectsFolder = getEffectsFolder,
	enemyContainerName = Config.Enemy.ContainerName,
})
local isEnemyModelAlive = sentryTargeting.isEnemyModelAlive
local getEnemyModelHealth = sentryTargeting.getEnemyModelHealth

-- Healthbar UI
local getTurretFillColor = SentryHealthBar.getTurretFillColor
local attachTurretHealthBar = SentryHealthBar.attachTurretHealthBar

-- Targeting
local pickTurretTargetCandidate = sentryTargeting.pickTurretTargetCandidate
local findTurretTarget = sentryTargeting.findTurretTarget

local function resolveTurretMuzzleOrigin(rootPart, weaponDef)
	local muzzleLocalOffset = Vector3.new(0, rootPart.Size.Y * MUZZLE_HEIGHT_RATIO, 0)
	local configuredOffset = weaponDef and weaponDef.TurretMuzzleOffset
	if typeof(configuredOffset) == "Vector3" then
		muzzleLocalOffset += configuredOffset
	end

	return rootPart.CFrame:PointToWorldSpace(muzzleLocalOffset)
end

local function aimTurretModel(record, rootPart, lookDirection)
	local flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	if flatLook.Magnitude <= 0.01 then
		return
	end

	local referencePart = SentryPlacement.resolveSentryPlacementReferencePart(record.model)
	if referencePart then
		local desiredReferencePlacementCFrame = CFrame.lookAt(referencePart.Position, referencePart.Position + flatLook.Unit)
		desiredReferencePlacementCFrame =
			SentryPlacement.resolveUprightSentryReferencePlacementCFrame(record.model, desiredReferencePlacementCFrame, flatLook)
		desiredReferencePlacementCFrame =
			SentryPlacement.applySentryPlacementRotationOffset(desiredReferencePlacementCFrame, record.weaponDef)
		record.model:PivotTo(SentryPlacement.resolveSentryPlacementPivotCFrame(record.model, desiredReferencePlacementCFrame))
	else
		local currentPivot = record.model:GetPivot()
		record.model:PivotTo(SentryPlacement.alignPivotYawToDirection(currentPivot, flatLook, rootPart.Position))
	end
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
		ignorePlayerCharacters = true,
	}

	for rocketIndex = 1, rocketsToFire do
		local rocketDirection = getTurretBurstRocketDirection(lookDirection, rocketIndex, rocketsToFire, rocketSpreadDegrees)
		fireRocket(record.owner, record.model, muzzleOrigin, rocketDirection, rocketWeaponDef, muzzleOrigin, rocketDirection, damageContext)
	end

	return rocketsToFire
end

-- Placement helpers
local alignPivotYawToDirection = SentryPlacement.alignPivotYawToDirection
local resolveSentryPlacementReferencePart = SentryPlacement.resolveSentryPlacementReferencePart
local resolveSentryPlacementPivotCFrame = SentryPlacement.resolveSentryPlacementPivotCFrame
local applySentryPlacementRotationOffset = SentryPlacement.applySentryPlacementRotationOffset
local resolveUprightSentryReferencePlacementCFrame = SentryPlacement.resolveUprightSentryReferencePlacementCFrame

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

			local modelMaxAmmo = if record.model and record.model:IsA("Model") then record.model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO) else nil
			local modelAmmo = if record.model and record.model:IsA("Model") then record.model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO) else nil
			local fallbackMaxAmmo = sentryRuntime.resolveTurretMaxAmmo(record.weaponDef)
			local ammo, maxAmmo
			if type(sentryRuntime.resolveRecordAmmoState) == "function" then
				ammo, maxAmmo = sentryRuntime.resolveRecordAmmoState(record, fallbackMaxAmmo)
			else
				ammo, maxAmmo = SentryStatResolver.resolveAmmoStateFromCandidates(
					{ modelMaxAmmo, record.maxAmmo, fallbackMaxAmmo },
					{ modelAmmo, record.ammo },
					fallbackMaxAmmo
				)
			end
			record.maxAmmo = maxAmmo
			record.ammo = ammo
			if record.ammo <= 0 then
				sentryRuntime.syncSentryAmmoAttributes(record)
				continue
			end

			local now = os.clock()
			if now - (record.lastFireAt or -math.huge) < math.max(0.05, tonumber(record.fireCooldown) or 0.2) then
				continue
			end

			local targetingOrigin = resolveTurretMuzzleOrigin(rootPart, record.weaponDef)
			local enemyModel, enemyRoot = findTurretTarget(record, targetingOrigin)
			if not enemyModel or not enemyRoot then
				continue
			end

			local toEnemy = enemyRoot.Position - targetingOrigin
			local lookDirection = if toEnemy.Magnitude > 0.01 then toEnemy.Unit else rootPart.CFrame.LookVector
			local turretDamageMultiplier = 1
			if record.owner and record.owner:IsA("Player") then
				turretDamageMultiplier = math.max(0, ClassService.getTurretDamageMultiplier(record.owner))
			end
			local turretShotDamage = math.max(0, record.damage * turretDamageMultiplier)
			if turretShotDamage <= 0 then
				continue
			end

			aimTurretModel(record, rootPart, lookDirection)
			rootPart = ModelRootResolver.resolveRootPart(record.model) or rootPart
			local muzzleOrigin = resolveTurretMuzzleOrigin(rootPart, record.weaponDef)
			toEnemy = enemyRoot.Position - muzzleOrigin
			lookDirection = if toEnemy.Magnitude > 0.01 then toEnemy.Unit else rootPart.CFrame.LookVector

			record.lastFireAt = now
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
		end

		if record.model and record.model.Parent then
			record.model:Destroy()
		end
		sentryRuntime.removeRecord(record.model)
	end)
end

local function resolveSentryPlacementCFrame(player, character, rootPart, sentryModel, weaponDef, explicitShotOrigin, explicitShotDirection)
	local fallbackOrigin = rootPart.Position + Vector3.new(0, PLACEMENT_ORIGIN_OFFSET_Y, 0)
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

	if hitResult.Normal.Y < MIN_FLOOR_NORMAL_Y then
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

	local placementPosition = hitResult.Position + Vector3.new(0, (boundsSize.Y * 0.5) + PLACEMENT_BOUNDS_OFFSET_Y, 0)
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

	local padding = Vector3.new(OVERLAP_PADDING, OVERLAP_PADDING, OVERLAP_PADDING)
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

	local combatStats = SentryStatResolver.resolveCombatStats(weaponDef, {
		normalizeWeaponToken = normalizeWeaponToken,
		defaultRocketSpreadDegrees = DEFAULT_TURRET_ROCKET_SPREAD_DEGREES,
	})
	local turretMaxHealth = combatStats.turretMaxHealth
	local turretDamage = combatStats.turretDamage
	local turretFireCooldown = combatStats.turretFireCooldown
	local turretAcquireRange = combatStats.turretAcquireRange
	local turretThinkInterval = combatStats.turretThinkInterval
	local turretAttackMode = combatStats.turretAttackMode
	local turretRocketCount = combatStats.turretRocketCount
	local turretRocketBlastRadius = combatStats.turretRocketBlastRadius
	local turretRocketProjectileSpeed = combatStats.turretRocketProjectileSpeed
	local turretRocketRange = combatStats.turretRocketRange
	local turretRocketSpreadDegrees = combatStats.turretRocketSpreadDegrees
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
	sentryModel:SetAttribute(SentryConstants.ATTR_IS_SENTRY_TURRET, true)
	sentryModel:SetAttribute(SentryConstants.ATTR_SENTRY_OWNER_USER_ID, player.UserId)
	sentryModel:SetAttribute(SentryConstants.ATTR_SENTRY_OWNER_NAME, player.Name)
	sentryModel:SetAttribute(SentryConstants.ATTR_SENTRY_WEAPON_ID, tostring(weaponDef.Id or ""))
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_MAX_HEALTH, turretMaxHealth)
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_HEALTH, turretMaxHealth)
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_LAST_DAMAGED_AT, -1)
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO, turretMaxAmmo)
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_AMMO, turretInitialAmmo)
	sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_OUT_OF_AMMO, turretInitialAmmo <= 0)

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
			sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_LAST_DAMAGED_AT, record.lastDamagedAt)
		end

		sentryModel:SetAttribute(SentryConstants.ATTR_TURRET_HEALTH, resolvedHealth)
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
