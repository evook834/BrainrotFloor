local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassService = require(script.Parent.ClassService)
local EnemyVfxService = require(script.Parent.EnemyVfxService)
local ModelRootResolver = require(script.Parent.ModelRootResolver)
local CatalogAndPricing = require(script.Parent:WaitForChild("Shop"):WaitForChild("CatalogAndPricing"))
local InventoryIndex = require(script.Parent:WaitForChild("Shop"):WaitForChild("InventoryIndex"))
local PurchaseFlow = require(script.Parent:WaitForChild("Shop"):WaitForChild("PurchaseFlow"))
local SentryRuntime = require(script.Parent:WaitForChild("Shop"):WaitForChild("SentryRuntime"))
local WeaponAmmoRuntime = require(script.Parent:WaitForChild("Shop"):WaitForChild("WeaponAmmoRuntime"))

local ShopService = {}

local started = false
local remotesFolder = nil
local shopOpenRemote = nil
local shopGetCatalogFunction = nil
local shopBuyWeaponFunction = nil
local shopBuyAmmoFunction = nil
local weaponAimRemote = nil
local weaponFireRemote = nil
local weaponReloadRemote = nil
local damageIndicatorRemote = nil
local weaponById = {}
local weaponEffectsFolder = nil
local enemyDamageBlinkState = setmetatable({}, { __mode = "k" })
local enemyBurnState = setmetatable({}, { __mode = "k" })
local playerAimState = {}
local playerGroundFireState = {}
local ammoRuntime = WeaponAmmoRuntime.new({
	classService = ClassService,
	inventoryIndex = InventoryIndex,
})
local toolRuntimeState = ammoRuntime.getStateMap()
local randomGenerator = Random.new()
local FIRE_CONE_HALF_ANGLE_DEGREES = 40
local FIRE_CONE_MIN_DOT = math.cos(math.rad(FIRE_CONE_HALF_ANGLE_DEGREES))
local BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS = 0.5
local SENTRY_TURRET_FOLDER_NAME = "SentryTurrets"
local MAX_SENTRY_COUNT_PER_PLAYER = 3
local SENTRY_REPAIR_INTERRUPT_SECONDS = 0.45
local DEFAULT_SENTRY_MAX_AMMO = 300
local applyDamageToEnemy
local sentryRuntime = nil
local classChangedCleanupDisconnect = nil

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

local function getSentryTurretFolder()
	return sentryRuntime.getSentryTurretFolder()
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

local function getHorizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end
	return horizontal.Unit
end

local function isDirectionWithinForwardFireArc(rootPart, direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return true
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		return true
	end

	local forwardHorizontal = getHorizontalUnit(rootPart.CFrame.LookVector)
	local directionHorizontal = getHorizontalUnit(direction)
	if not forwardHorizontal or not directionHorizontal then
		return true
	end

	-- Allow only a narrow horizontal cone around where the character is facing.
	return forwardHorizontal:Dot(directionHorizontal) >= FIRE_CONE_MIN_DOT
end

local function clampDirectionToForwardFireArc(rootPart, direction, fallbackDirection)
	local fallback = fallbackDirection
	if typeof(fallback) ~= "Vector3" or fallback.Magnitude <= 0.001 then
		if rootPart and rootPart:IsA("BasePart") then
			fallback = rootPart.CFrame.LookVector
		else
			fallback = Vector3.new(0, 0, -1)
		end
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return fallback.Unit
	end

	local directionUnit = direction.Unit
	if isDirectionWithinForwardFireArc(rootPart, directionUnit) then
		return directionUnit
	end

	return fallback.Unit
end

local function canPlayerFireTowardRequestedDirection(player, rootPart, explicitShotDirection)
	local requestedDirection = explicitShotDirection
	if typeof(requestedDirection) ~= "Vector3" or requestedDirection.Magnitude <= 0.001 then
		local aimState = getFreshAimState(player)
		if aimState and typeof(aimState.lookDirection) == "Vector3" and aimState.lookDirection.Magnitude > 0.001 then
			requestedDirection = aimState.lookDirection
		else
			requestedDirection = rootPart.CFrame.LookVector
		end
	end

	return isDirectionWithinForwardFireArc(rootPart, requestedDirection)
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

	return clampDirectionToForwardFireArc(rootPart, aimDirection, baseDirection)
end

local function getPlayerShotRay(player, rootPart, fallbackOrigin, fallbackDirection)
	local aimState = getFreshAimState(player)
	if aimState and typeof(aimState.cameraOrigin) == "Vector3" then
		local lookDirection = aimState.lookDirection
		if typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
			return aimState.cameraOrigin, clampDirectionToForwardFireArc(rootPart, lookDirection, fallbackDirection)
		end
	end

	if typeof(fallbackOrigin) == "Vector3" and typeof(fallbackDirection) == "Vector3" and fallbackDirection.Magnitude > 0.001 then
		return fallbackOrigin, clampDirectionToForwardFireArc(rootPart, fallbackDirection, rootPart.CFrame.LookVector)
	end

	return rootPart.Position + Vector3.new(0, 1.5, 0), clampDirectionToForwardFireArc(rootPart, rootPart.CFrame.LookVector, rootPart.CFrame.LookVector)
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

	moneyValue.Value += math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
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

local function getOrCreateEnemyBlinkHighlight(enemyModel)
	local highlight = enemyModel:FindFirstChild("DamageBlinkHighlight")
	if highlight and not highlight:IsA("Highlight") then
		highlight:Destroy()
		highlight = nil
	end

	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "DamageBlinkHighlight"
		highlight.Adornee = enemyModel
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = Color3.fromRGB(255, 35, 35)
		highlight.FillTransparency = 0.22
		highlight.OutlineColor = Color3.fromRGB(255, 35, 35)
		highlight.OutlineTransparency = 0.65
		highlight.Enabled = false
		highlight.Parent = enemyModel
	end

	return highlight
end

local function blinkEnemyDamage(enemyModel)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local state = enemyDamageBlinkState[enemyModel]
	if not state then
		state = {
			token = 0,
		}
		enemyDamageBlinkState[enemyModel] = state
	end

	local highlight = getOrCreateEnemyBlinkHighlight(enemyModel)
	if not highlight then
		return
	end

	state.token += 1
	local currentToken = state.token
	highlight.Adornee = enemyModel
	highlight.Enabled = true

	task.delay(0.12, function()
		if not enemyModel.Parent then
			return
		end

		local liveState = enemyDamageBlinkState[enemyModel]
		if liveState ~= state or liveState.token ~= currentToken then
			return
		end

		if highlight.Parent == enemyModel then
			highlight.Enabled = false
		end
	end)
end

local function getDamageIndicatorStyleTag(weaponDef)
	if type(weaponDef) ~= "table" then
		return nil
	end

	-- Set this to "crit" to force the crit damage indicator style.
	local explicitStyle = weaponDef.DamageIndicatorStyle or weaponDef.DamageTextStyle
	if type(explicitStyle) == "string" and explicitStyle ~= "" then
		return string.lower(explicitStyle)
	end

	if weaponDef.Crit == true or weaponDef.IsCrit == true then
		return "crit"
	end

	return nil
end

local function resolveCriticalHitOutcome(player, weaponDef, damageContext)
	if damageContext and damageContext.allowCriticalHits == false then
		return 1, nil
	end
	if not player or not player:IsA("Player") then
		return 1, nil
	end
	if type(weaponDef) ~= "table" then
		return 1, nil
	end

	local critConfig = ClassService.getCriticalHitConfig(player, weaponDef)
	if type(critConfig) ~= "table" then
		return 1, nil
	end

	local superCriticalChance = math.clamp(tonumber(critConfig.superCriticalChance) or 0, 0, 1)
	local criticalChance = math.clamp(tonumber(critConfig.criticalChance) or 0, 0, 1)
	local totalChance = math.clamp(superCriticalChance + criticalChance, 0, 1)
	if totalChance <= 0 then
		return 1, nil
	end

	local roll = randomGenerator:NextNumber()
	if roll <= superCriticalChance then
		return math.max(1, tonumber(critConfig.superCriticalMultiplier) or 3), "supercrit"
	end
	if roll <= totalChance then
		return math.max(1, tonumber(critConfig.criticalMultiplier) or 2), "crit"
	end

	return 1, nil
end

local function emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
	if not damageIndicatorRemote then
		return
	end
	if not player or not player:IsA("Player") then
		return
	end
	if not enemyModel or not enemyModel.Parent then
		return
	end
	if type(dealtDamage) ~= "number" or dealtDamage <= 0 then
		return
	end
	local normalizedStyleTag = nil
	if type(indicatorStyleTag) == "string" and indicatorStyleTag ~= "" then
		normalizedStyleTag = string.lower(indicatorStyleTag)
	end

	local worldPosition = nil
	local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
	if enemyRoot then
		worldPosition = enemyRoot.Position
	else
		local ok, pivot = pcall(function()
			return enemyModel:GetPivot()
		end)
		if ok then
			worldPosition = pivot.Position
		end
	end

	damageIndicatorRemote:FireClient(player, enemyModel, dealtDamage, worldPosition, normalizedStyleTag)
end

local function isEnemyAliveForBurn(enemyModel)
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

local function tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
	if not player or not player:IsA("Player") then
		return
	end
	if not enemyModel or not enemyModel.Parent then
		return
	end
	if type(weaponDef) ~= "table" then
		return
	end

	local burnConfig = ClassService.getBurnOnHitConfig(player, weaponDef)
	if type(burnConfig) ~= "table" then
		return
	end

	local chance = math.clamp(tonumber(burnConfig.chance) or 0, 0, 1)
	if chance <= 0 or randomGenerator:NextNumber() > chance then
		return
	end

	local durationSeconds = math.max(0.1, tonumber(burnConfig.durationSeconds) or 3)
	local tickIntervalSeconds = math.max(
		0.1,
		tonumber(burnConfig.tickIntervalSeconds) or BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS
	)
	local damageFractionPerSecond = math.max(0, tonumber(burnConfig.damageFractionPerSecond) or 0)
	if damageFractionPerSecond <= 0 then
		return
	end

	local baseWeaponDamage = math.max(0, tonumber(weaponDef.Damage) or 0)
	if baseWeaponDamage <= 0 then
		return
	end

	local effectiveWeaponDamage = baseWeaponDamage * math.max(0, tonumber(classMultiplier) or 1)
	local damagePerTick = effectiveWeaponDamage * damageFractionPerSecond * tickIntervalSeconds
	if damagePerTick <= 0 then
		return
	end

	local ticksRemaining = math.max(1, math.floor((durationSeconds / tickIntervalSeconds) + 0.5))
	local state = enemyBurnState[enemyModel]
	if not state then
		state = {
			token = 0,
		}
		enemyBurnState[enemyModel] = state
	end

	state.token += 1
	local currentToken = state.token
	state.ownerPlayer = player
	state.damagePerTick = damagePerTick
	state.tickIntervalSeconds = tickIntervalSeconds
	state.ticksRemaining = ticksRemaining

	task.spawn(function()
		while true do
			local liveState = enemyBurnState[enemyModel]
			if liveState ~= state or state.token ~= currentToken then
				return
			end
			if state.ticksRemaining <= 0 then
				break
			end

			task.wait(state.tickIntervalSeconds)

			liveState = enemyBurnState[enemyModel]
			if liveState ~= state or state.token ~= currentToken then
				return
			end
			if not isEnemyAliveForBurn(enemyModel) then
				enemyBurnState[enemyModel] = nil
				return
			end

			local ownerPlayer = state.ownerPlayer
			if not ownerPlayer or not ownerPlayer:IsA("Player") or ownerPlayer.Parent ~= Players then
				enemyBurnState[enemyModel] = nil
				return
			end

			applyDamageToEnemy(ownerPlayer, enemyModel, state.damagePerTick, nil, {
				applyClassMultiplier = false,
				allowBurnOnHit = false,
				allowCriticalHits = false,
			})
			state.ticksRemaining -= 1
		end

		local liveState = enemyBurnState[enemyModel]
		if liveState == state and state.token == currentToken then
			enemyBurnState[enemyModel] = nil
		end
	end)
end

applyDamageToEnemy = function(player, enemyModel, damage, weaponDef, damageContext)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local context = damageContext or {}
	local applyClassMultiplier = context.applyClassMultiplier ~= false
	local allowBurnOnHit = context.allowBurnOnHit ~= false
	local explicitIndicatorStyleTag = nil
	if type(context.indicatorStyleTag) == "string" and context.indicatorStyleTag ~= "" then
		explicitIndicatorStyleTag = string.lower(context.indicatorStyleTag)
	end

	local appliedDamage = math.max(0, tonumber(damage) or 0)
	if appliedDamage <= 0 then
		return
	end

	local classMultiplier = 1
	if player and player:IsA("Player") and weaponDef then
		local computedMultiplier = ClassService.getWeaponDamageMultiplier(player, weaponDef)
		if computedMultiplier <= 0 then
			if applyClassMultiplier then
				return
			end
		else
			classMultiplier = computedMultiplier
			if applyClassMultiplier then
				appliedDamage *= classMultiplier
			end
		end
	end

	local criticalDamageMultiplier, criticalIndicatorStyleTag = resolveCriticalHitOutcome(player, weaponDef, context)
	appliedDamage *= math.max(1, tonumber(criticalDamageMultiplier) or 1)

	local indicatorStyleTag = criticalIndicatorStyleTag or explicitIndicatorStyleTag or getDamageIndicatorStyleTag(weaponDef)

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local previousHealth = humanoid.Health
		if previousHealth <= 0 then
			return
		end

		humanoid:TakeDamage(appliedDamage)
		local currentHealth = humanoid.Health
		local dealtDamage = math.max(0, previousHealth - currentHealth)
		if dealtDamage > 0 then
			blinkEnemyDamage(enemyModel)
			if player and player:IsA("Player") then
				ClassService.recordDamage(player, dealtDamage, weaponDef)
				emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
			end
			if allowBurnOnHit and currentHealth > 0 then
				tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
			end
		end
		if previousHealth > 0 and currentHealth <= 0 then
			EnemyVfxService.playDeathCloud(enemyModel)
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

	local previousHealth = health
	health -= appliedDamage
	enemyModel:SetAttribute("EnemyMaxHealth", maxHealth)
	enemyModel:SetAttribute("EnemyHealth", health)
	local dealtDamage = math.max(0, previousHealth - health)
	if dealtDamage > 0 then
		blinkEnemyDamage(enemyModel)
		if player and player:IsA("Player") then
			ClassService.recordDamage(player, dealtDamage, weaponDef)
			emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
		end
		if allowBurnOnHit and health > 0 then
			tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
		end
	end

	if health <= 0 then
		rewardEnemyKill(player, enemyModel)
		EnemyVfxService.playDeathCloud(enemyModel)
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

local function normalizeWeaponToken(value)
	if type(value) ~= "string" then
		return ""
	end

	local token = string.lower(value)
	token = string.gsub(token, "%s+", "")
	return token
end

local function isSniperWeaponDefinition(weaponDef)
	if type(weaponDef) ~= "table" then
		return false
	end

	local classIdToken = normalizeWeaponToken(weaponDef.ClassId)
	local classTagToken = normalizeWeaponToken(weaponDef.ClassTag)
	local weaponClassToken = normalizeWeaponToken(resolveWeaponClass(weaponDef))

	return classIdToken == "sniper" or classTagToken == "sniper" or weaponClassToken == "sniper"
end

local function getMagazineSize(weaponDef, player)
	return ammoRuntime.getMagazineSize(weaponDef, player)
end

local function getReloadSeconds(weaponDef, player)
	return ammoRuntime.getReloadSeconds(weaponDef, player)
end

local function getReserveAmmoCapacity(weaponDef, magazineSize)
	return ammoRuntime.getReserveAmmoCapacity(weaponDef, magazineSize)
end

local function syncToolCombatStats(tool, weaponDef, state, owner)
	ammoRuntime.syncToolCombatStats(tool, weaponDef, state, owner)
end

local function getToolState(tool, weaponDef, owner)
	return ammoRuntime.getToolState(tool, weaponDef, owner)
end

local function updateAmmoAttributes(tool, weaponDef, state, owner, skipMirror)
	ammoRuntime.updateAmmoAttributes(tool, weaponDef, state, owner, skipMirror)
end

local function startReload(tool, weaponDef, state, owner)
	ammoRuntime.startReload(tool, weaponDef, state, owner)
end

local function tryConsumeAmmo(tool, weaponDef, state, owner)
	return ammoRuntime.tryConsumeAmmo(tool, weaponDef, state, owner)
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

local function createFlamePuff(position, size, lifetimeSeconds)
	local puff = Instance.new("Part")
	puff.Name = "FlamePuff"
	puff.Shape = Enum.PartType.Ball
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanTouch = false
	puff.CanQuery = false
	puff.Material = Enum.Material.Neon
	puff.Color = Color3.fromRGB(255, 168, 85)
	puff.Transparency = 0.15
	puff.Size = Vector3.new(size, size, size)
	puff.CFrame = CFrame.new(position)
	puff.Parent = getEffectsFolder()

	local puffLifetime = math.max(0.08, lifetimeSeconds or 0.14)
	local expandScale = randomGenerator:NextNumber(1.5, 2.2)
	local tween = TweenService:Create(
		puff,
		TweenInfo.new(puffLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = puff.Size * expandScale,
			Transparency = 1,
			Color = Color3.fromRGB(130, 58, 30),
		}
	)
	tween:Play()
	Debris:AddItem(puff, puffLifetime + 0.05)
end

local function createFlameEmitterBurst(origin, direction, travelDistance)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "FlameEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanTouch = false
	emitterPart.CanQuery = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterPart.CFrame = CFrame.lookAt(origin, origin + direction)
	emitterPart.Parent = getEffectsFolder()

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitterPart

	local flameEmitter = Instance.new("ParticleEmitter")
	flameEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	flameEmitter.Rate = 0
	flameEmitter.LightEmission = 1
	flameEmitter.Lifetime = NumberRange.new(0.14, 0.28)
	flameEmitter.Speed = NumberRange.new(
		math.max(12, travelDistance * 0.85),
		math.max(20, travelDistance * 1.25)
	)
	flameEmitter.SpreadAngle = Vector2.new(24, 24)
	flameEmitter.Drag = 4
	flameEmitter.Acceleration = Vector3.new(0, 16, 0)
	flameEmitter.RotSpeed = NumberRange.new(-150, 150)
	flameEmitter.EmissionDirection = Enum.NormalId.Front
	flameEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.4, 1.25),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	flameEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 1),
	})
	flameEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 140)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 165, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 45, 28)),
	})
	flameEmitter.Parent = attachment
	flameEmitter:Emit(24)

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.Rate = 0
	smokeEmitter.Lifetime = NumberRange.new(0.3, 0.55)
	smokeEmitter.Speed = NumberRange.new(7, 13)
	smokeEmitter.SpreadAngle = Vector2.new(30, 30)
	smokeEmitter.Drag = 6
	smokeEmitter.Acceleration = Vector3.new(0, 9, 0)
	smokeEmitter.EmissionDirection = Enum.NormalId.Front
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(45, 45, 45))
	smokeEmitter.Parent = attachment
	smokeEmitter:Emit(10)

	Debris:AddItem(emitterPart, 0.5)
end

local function createFlamethrowerVisuals(origin, direction, range)
	local visualDistance = math.min(range, 15)
	createMuzzleFlash(origin, Color3.fromRGB(255, 165, 90), 1.15, 0.12)
	createMuzzleFlash(origin + direction * 1.1, Color3.fromRGB(255, 210, 120), 0.62, 0.1)
	createTracerSegment(origin, origin + direction * visualDistance, Color3.fromRGB(255, 130, 70), 0.56, 0.08)
	createTracerSegment(origin, origin + direction * (visualDistance * 0.72), Color3.fromRGB(255, 205, 120), 0.32, 0.07)
	createFlameEmitterBurst(origin, direction, visualDistance)

	local upReference = math.abs(direction:Dot(Vector3.yAxis)) > 0.92 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(upReference)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(direction).Unit

	for i = 1, 9 do
		local progress = i / 9
		local travel = visualDistance * progress
		local spread = (1 - progress) * 0.32
		local jitter = right * randomGenerator:NextNumber(-spread, spread) + up * randomGenerator:NextNumber(-spread, spread)
		local puffPosition = origin + direction * travel + jitter
		local puffSize = randomGenerator:NextNumber(0.48, 0.95) * (1 - progress * 0.2)
		createFlamePuff(puffPosition, puffSize, randomGenerator:NextNumber(0.12, 0.22))
	end
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

local function getEnemyTemplateProfile(enemyModel)
	if not enemyModel or not enemyModel:IsA("Model") then
		return nil
	end

	local enemyType = enemyModel:GetAttribute("EnemyType")
	if type(enemyType) ~= "string" or enemyType == "" then
		return nil
	end

	local templateProfiles = Config.Enemy.TemplateProfiles or {}
	local templateProfile = templateProfiles[enemyType]
	if type(templateProfile) == "table" then
		return templateProfile
	end

	return nil
end

local function getEffectiveEnemyHitRadius(enemyModel, enemyRoot)
	local radius = getEnemyHitRadius(enemyRoot)
	local profile = getEnemyTemplateProfile(enemyModel)
	if not profile then
		return radius
	end

	local hitboxScale = tonumber(profile.HitboxScale) or 1
	local hitboxPadding = tonumber(profile.HitboxPadding) or 0
	radius = radius * math.max(0.1, hitboxScale) + math.max(0, hitboxPadding)

	return math.clamp(radius, 1.2, 10)
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
			local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
			if enemyRoot then
				local nearestPoint = projectPointOnSegment(enemyRoot.Position, segmentStart, segmentEnd)
				local distanceFromPath = (enemyRoot.Position - nearestPoint).Magnitude
				local allowedRadius = getEffectiveEnemyHitRadius(enemyModel, enemyRoot) + radiusPadding
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
	local halfArcRadians = math.rad(math.clamp((arcDegrees or 90) * 0.5, 1, 179))

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
			if enemyRoot then
				local offset = enemyRoot.Position - origin
				local distance = offset.Magnitude
				local targetRadius = getEffectiveEnemyHitRadius(enemyModel, enemyRoot)
				if distance <= (range + targetRadius) and distance > 0.05 then
					local direction = offset.Unit
					local facingDot = normalizedLook:Dot(direction)
					local angularSlackRadians = math.atan(targetRadius / math.max(distance, 0.01))
					local enemyMinDot = math.cos(math.min(math.rad(179), halfArcRadians + angularSlackRadians))
					if facingDot >= enemyMinDot and hasClearPathToEnemy(character, origin, enemyModel, enemyRoot) then
						table.insert(enemies, enemyModel)
					end
				end
			end
		end
	end

	return enemies
end

local function applyBlastDamage(player, centerPosition, radius, maxDamage, weaponDef)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return
	end

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
			if enemyRoot then
				local distance = (enemyRoot.Position - centerPosition).Magnitude
				if distance <= radius then
					local falloff = 1 - (distance / math.max(radius, 0.01))
					local damageScale = math.clamp(0.3 + falloff * 0.7, 0.3, 1)
					applyDamageToEnemy(player, enemyModel, maxDamage * damageScale, weaponDef)
				end
			end
		end
	end
end

local function spawnFlamethrowerGroundFire(player, weaponDef, hitResult)
	if not player or not player:IsA("Player") then
		return
	end
	if not hitResult then
		return
	end

	local hitEnemy = resolveEnemyFromRaycastResult(hitResult)
	if hitEnemy then
		return
	end

	local hitNormal = hitResult.Normal
	if typeof(hitNormal) ~= "Vector3" or hitNormal.Magnitude <= 0.001 then
		hitNormal = Vector3.yAxis
	end
	if hitNormal.Y < 0.45 then
		return
	end

	local chance = math.clamp(tonumber(weaponDef.GroundFireChance) or 0.2, 0, 1)
	if chance <= 0 then
		return
	end
	if randomGenerator:NextNumber() > chance then
		return
	end

	local now = os.clock()
	local state = playerGroundFireState[player]
	if not state then
		state = {
			lastSpawnAt = -math.huge,
		}
		playerGroundFireState[player] = state
	end

	local spawnCooldown = math.max(0.05, tonumber(weaponDef.GroundFireSpawnCooldownSeconds) or 0.45)
	if now - (state.lastSpawnAt or -math.huge) < spawnCooldown then
		return
	end
	state.lastSpawnAt = now

	local radius = math.max(2, tonumber(weaponDef.GroundFireRadius) or 4.5)
	local duration = math.max(0.5, tonumber(weaponDef.GroundFireDurationSeconds) or 2.6)
	local tickInterval = math.max(0.08, tonumber(weaponDef.GroundFireTickIntervalSeconds) or 0.35)
	local damageScale = math.max(0, tonumber(weaponDef.GroundFireDamageScale) or 0.1)
	local damagePerTick = math.max(0, (tonumber(weaponDef.Damage) or 10) * damageScale)
	if damagePerTick <= 0 then
		return
	end

	local centerPosition = hitResult.Position + Vector3.new(0, 0.1, 0)
	local patch = Instance.new("Part")
	patch.Name = "GroundFirePatch"
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanTouch = false
	patch.CanQuery = false
	patch.Material = Enum.Material.Neon
	patch.Color = Color3.fromRGB(255, 120, 55)
	patch.Transparency = 0.35
	patch.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	patch.CFrame = CFrame.new(centerPosition)
	patch.Parent = getEffectsFolder()
	Debris:AddItem(patch, duration + 0.35)

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, patch.Size.Y * 0.5, 0)
	attachment.Parent = patch

	local fireEmitter = Instance.new("ParticleEmitter")
	fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	fireEmitter.LightEmission = 1
	fireEmitter.Rate = 28
	fireEmitter.Lifetime = NumberRange.new(0.2, 0.4)
	fireEmitter.Speed = NumberRange.new(2, 6)
	fireEmitter.SpreadAngle = Vector2.new(20, 20)
	fireEmitter.Acceleration = Vector3.new(0, 10, 0)
	fireEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	fireEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	fireEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 120)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 45, 30)),
	})
	fireEmitter.Parent = attachment

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.Rate = 8
	smokeEmitter.Lifetime = NumberRange.new(0.45, 0.8)
	smokeEmitter.Speed = NumberRange.new(1, 3)
	smokeEmitter.SpreadAngle = Vector2.new(30, 30)
	smokeEmitter.Acceleration = Vector3.new(0, 6, 0)
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(45, 45, 45))
	smokeEmitter.Parent = attachment

	task.delay(duration, function()
		if fireEmitter then
			fireEmitter.Enabled = false
		end
		if smokeEmitter then
			smokeEmitter.Enabled = false
		end
	end)

	task.spawn(function()
		local elapsed = 0
		local queryHeight = math.max(4, radius * 1.35)
		local querySize = Vector3.new(radius * 2, queryHeight, radius * 2)
		local queryCenter = centerPosition + Vector3.new(0, queryHeight * 0.5, 0)

		while patch.Parent and elapsed < duration do
			local enemyContainer = getEnemyContainer()
			if enemyContainer then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { enemyContainer }
				overlapParams.MaxParts = 256

				local touchedParts = Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), querySize, overlapParams)
				local damagedThisTick = {}
				for _, touchedPart in ipairs(touchedParts) do
					local enemyModel = findEnemyModelFromDescendant(touchedPart, enemyContainer)
					if enemyModel and not damagedThisTick[enemyModel] then
						damagedThisTick[enemyModel] = true
						applyDamageToEnemy(player, enemyModel, damagePerTick, weaponDef)
					end
				end
			end

			task.wait(tickInterval)
			elapsed += tickInterval
		end
	end)
end

local function isRightShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	local motorName = motor.Name
	if motorName == "RightShoulder" or motorName == "Right Shoulder" then
		return true
	end

	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	local part0Name = part0.Name
	local part1Name = part1.Name
	if part1Name ~= "Right Arm" and part1Name ~= "RightUpperArm" then
		return false
	end

	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findRightShoulderMotor(character)
	if not character or not character:IsA("Model") then
		return nil
	end

	local directR15 = character:FindFirstChild("RightShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then
		return directR15
	end

	local directR6 = character:FindFirstChild("Right Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then
		return directR6
	end

	for _, descendant in character:GetDescendants() do
		if isRightShoulderMotor(descendant) then
			return descendant
		end
	end

	return nil
end

local function isLeftShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	local motorName = motor.Name
	if motorName == "LeftShoulder" or motorName == "Left Shoulder" then
		return true
	end

	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	local part0Name = part0.Name
	local part1Name = part1.Name
	if part1Name ~= "Left Arm" and part1Name ~= "LeftUpperArm" then
		return false
	end

	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findLeftShoulderMotor(character)
	if not character or not character:IsA("Model") then
		return nil
	end

	local directR15 = character:FindFirstChild("LeftShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then
		return directR15
	end

	local directR6 = character:FindFirstChild("Left Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then
		return directR6
	end

	for _, descendant in character:GetDescendants() do
		if isLeftShoulderMotor(descendant) then
			return descendant
		end
	end

	return nil
end

local function playMeleeSwing(character, weaponDef, state)
	state.swingToken += 1
	local swingToken = state.swingToken

	local swingForwardDegrees = tonumber(weaponDef.SwingForwardDegrees) or 70
	local swingDuration = math.max(0.08, tonumber(weaponDef.SwingDuration) or 0.18)
	local swingSideDegrees = tonumber(weaponDef.SwingSideDegrees)
	if type(swingSideDegrees) ~= "number" then
		swingSideDegrees = math.max(8, math.min(22, math.abs(swingForwardDegrees) * 0.24))
	end
	local swingRollDegrees = tonumber(weaponDef.SwingRollDegrees) or (-0.5 * swingSideDegrees)
	local windupDegrees = tonumber(weaponDef.SwingWindupDegrees)
	if type(windupDegrees) ~= "number" then
		windupDegrees = math.max(8, math.min(24, math.abs(swingForwardDegrees) * 0.32))
	end
	local windupSideDegrees = tonumber(weaponDef.SwingWindupSideDegrees)
	if type(windupSideDegrees) ~= "number" then
		windupSideDegrees = -swingSideDegrees * 0.55
	end
	local windupRollDegrees = tonumber(weaponDef.SwingWindupRollDegrees)
	if type(windupRollDegrees) ~= "number" then
		windupRollDegrees = -swingRollDegrees * 0.35
	end
	local shoulderMotor = findRightShoulderMotor(character)
	if not shoulderMotor then
		return
	end

	local baseC0 = shoulderMotor.C0
	local windupC0 = baseC0 * CFrame.Angles(
		math.rad(windupDegrees),
		math.rad(windupSideDegrees),
		math.rad(windupRollDegrees)
	)
	local strikeC0 = baseC0 * CFrame.Angles(
		math.rad(-swingForwardDegrees),
		math.rad(swingSideDegrees),
		math.rad(swingRollDegrees)
	)

	local function animateMotorC0(fromC0, toC0, durationSeconds)
		local duration = math.max(0.01, durationSeconds)
		local start = os.clock()
		while shoulderMotor.Parent do
			if state.swingToken ~= swingToken then
				return false
			end

			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			local easedAlpha = 1 - ((1 - alpha) * (1 - alpha))
			shoulderMotor.C0 = fromC0:Lerp(toC0, easedAlpha)
			if alpha >= 1 then
				return true
			end

			RunService.Heartbeat:Wait()
		end
		return false
	end

	task.spawn(function()
		local windupTime = swingDuration * 0.24
		local strikeTime = swingDuration * 0.38
		local recoverTime = swingDuration * 0.38

		if not animateMotorC0(baseC0, windupC0, windupTime) then
			return
		end
		if not animateMotorC0(windupC0, strikeC0, strikeTime) then
			return
		end
		animateMotorC0(strikeC0, baseC0, recoverTime)
	end)
end

local function applyBulletSpread(direction, spreadDegrees)
	local maxDegrees = math.max(0, tonumber(spreadDegrees) or 0)
	if maxDegrees <= 0 then
		return direction
	end

	local coneRadius = math.tan(math.rad(maxDegrees))
	local theta = randomGenerator:NextNumber(0, math.pi * 2)
	local radius = coneRadius * math.sqrt(randomGenerator:NextNumber())
	local referenceUp = math.abs(direction:Dot(Vector3.yAxis)) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(referenceUp)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(direction).Unit
	local offset = right * (math.cos(theta) * radius) + up * (math.sin(theta) * radius)
	local spreadDirection = direction + offset
	if spreadDirection.Magnitude <= 0.001 then
		return direction
	end

	return spreadDirection.Unit
end

local function fireBulletShot(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local isSniperWeapon = isSniperWeaponDefinition(weaponDef)
	local baseRange = math.max(1, tonumber(weaponDef.Range) or 40)
	local range = baseRange * math.max(0.1, ClassService.getWeaponBulletRangeMultiplier(player, weaponDef))
	local rayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local rayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local spreadDegrees = 0
	if not isSniperWeapon then
		spreadDegrees = ClassService.getWeaponSpreadDegrees(player, weaponDef)
		if type(spreadDegrees) ~= "number" then
			spreadDegrees = weaponDef.SpreadDegrees
		end
	end
	rayDirection = applyBulletSpread(rayDirection, spreadDegrees)
	local raycastParams = buildWeaponRaycastParams(character, {})
	local result = Workspace:Raycast(rayOrigin, rayDirection * range, raycastParams)
	local hitPosition = rayOrigin + rayDirection * range
	local enemyTarget = nil

	if result then
		hitPosition = result.Position
		enemyTarget = resolveEnemyFromRaycastResult(result)
	end

	if not enemyTarget then
		local fallbackRadius = 0.75
		local fallbackEnd = hitPosition
		if isSniperWeapon then
			fallbackRadius = math.max(2.5, tonumber(weaponDef.SniperHitAssistRadius) or 2.5)
			fallbackEnd = rayOrigin + (rayDirection * range)
		end

		local fallbackEnemy, fallbackImpact = findEnemyAlongSegment(character, rayOrigin, fallbackEnd, fallbackRadius)
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
		applyDamageToEnemy(player, enemyTarget, weaponDef.Damage or 20, weaponDef)
	end
end

local function fireMeleeAttack(player, character, origin, direction, weaponDef, state, tool)
	playMeleeSwing(character, weaponDef, state)

	local meleeRangeMultiplier = math.max(0.1, ClassService.getMeleeRangeMultiplier(player, weaponDef))
	local range = math.max(1, tonumber(weaponDef.Range) or 8) * meleeRangeMultiplier
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 90
	local downwardBias = math.clamp(tonumber(weaponDef.MeleeDownwardBias) or 0.34, 0, 0.85)
	local originDrop = math.max(0, tonumber(weaponDef.MeleeOriginDrop) or 1.15)
	local groundRangeBonus = math.max(0, tonumber(weaponDef.MeleeGroundRangeBonus) or 1.2) * meleeRangeMultiplier
	local groundArcBonus = math.max(0, tonumber(weaponDef.MeleeGroundArcBonus) or 14)
	local groundExtraRadius = math.max(0, tonumber(weaponDef.MeleeGroundExtraRadius) or 1.8) * meleeRangeMultiplier
	local damage = weaponDef.Damage or 15

	local targetsByModel = {}
	local function collectTargets(hitOrigin, hitDirection, hitRange, hitArcDegrees)
		local hits = getEnemiesInCone(character, hitOrigin, hitDirection, hitRange, hitArcDegrees)
		for _, enemyModel in ipairs(hits) do
			targetsByModel[enemyModel] = true
		end
	end

	collectTargets(origin, direction, range, arcDegrees)

	local loweredOrigin = origin - Vector3.new(0, originDrop, 0)
	local downwardDirection = direction + Vector3.new(0, -downwardBias, 0)
	if downwardDirection.Magnitude > 0.001 then
		downwardDirection = downwardDirection.Unit
	else
		downwardDirection = direction
	end

	collectTargets(loweredOrigin, downwardDirection, range + groundRangeBonus, arcDegrees + groundArcBonus)

	if next(targetsByModel) == nil then
		local fallbackEnd = loweredOrigin + downwardDirection * (range + groundRangeBonus)
		local fallbackEnemy = findEnemyAlongSegment(character, loweredOrigin, fallbackEnd, groundExtraRadius)
		if fallbackEnemy then
			targetsByModel[fallbackEnemy] = true
		end
	end

	for enemyModel in pairs(targetsByModel) do
		applyDamageToEnemy(player, enemyModel, damage, weaponDef)
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
			createFlamethrowerVisuals(origin, direction, range)
			local raycastParams = buildWeaponRaycastParams(character, {})
			local impactResult = Workspace:Raycast(origin, direction * range, raycastParams)
			if impactResult then
				spawnFlamethrowerGroundFire(player, weaponDef, impactResult)
			end

			local targets = getEnemiesInCone(character, origin, direction, range, arcDegrees)
			for _, enemyModel in ipairs(targets) do
				applyDamageToEnemy(player, enemyModel, tickDamage, weaponDef)
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
					applyDamageToEnemy(player, directTarget, blastDamage, weaponDef)
				end

				break
			end
		end

		if rocket.Parent then
			createExplosionEffect(currentPosition, blastRadius)
			applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef)
			rocket:Destroy()
		end
	end)
end

local function fireGrenadeLauncher(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local speed = math.max(35, tonumber(weaponDef.ProjectileSpeed) or 110)
	local range = math.max(25, tonumber(weaponDef.Range) or 110)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 12)
	local blastDamage = tonumber(weaponDef.Damage) or 90
	local fuseSeconds = math.max(0.35, tonumber(weaponDef.FuseSeconds) or 2.5)
	local lobFactor = math.clamp(tonumber(weaponDef.LobFactor) or 0.15, -0.2, 0.55)
	local gravity = math.max(20, Workspace.Gravity)

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
	direction = (direction + Vector3.new(0, lobFactor, 0)).Unit

	local grenade = Instance.new("Part")
	grenade.Name = "GrenadeProjectile"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(0.9, 0.9, 0.9)
	grenade.Material = Enum.Material.Metal
	grenade.Color = Color3.fromRGB(112, 132, 86)
	grenade.Anchored = true
	grenade.CanCollide = false
	grenade.CanTouch = false
	grenade.CanQuery = false
	grenade.CFrame = CFrame.new(origin)
	grenade.Parent = getEffectsFolder()
	Debris:AddItem(grenade, 8)

	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Position = Vector3.new(0, 0, -grenade.Size.Z * 0.45)
	frontAttachment.Parent = grenade

	local backAttachment = Instance.new("Attachment")
	backAttachment.Position = Vector3.new(0, 0, grenade.Size.Z * 0.45)
	backAttachment.Parent = grenade

	local trail = Instance.new("Trail")
	trail.Attachment0 = frontAttachment
	trail.Attachment1 = backAttachment
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 218, 145), Color3.fromRGB(158, 136, 94))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.08
	trail.MinLength = 0.05
	trail.Parent = grenade

	task.spawn(function()
		local currentPosition = origin
		local velocity = direction * speed
		local elapsed = 0
		local traveled = 0
		local raycastParams = buildWeaponRaycastParams(character, { grenade })
		local directTarget = nil

		while grenade.Parent and elapsed < fuseSeconds and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepTime = math.min(deltaTime, 0.06)
			local nextVelocity = velocity + Vector3.new(0, -gravity, 0) * stepTime
			local displacement = (velocity + nextVelocity) * 0.5 * stepTime

			if displacement.Magnitude <= 0.0001 then
				velocity = nextVelocity
				elapsed += stepTime
				continue
			end

			local raycastResult = Workspace:Raycast(currentPosition, displacement, raycastParams)
			local stepEndPosition = currentPosition + displacement
			local nextPosition = stepEndPosition

			if raycastResult then
				nextPosition = raycastResult.Position
				directTarget = resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.35)
				if fallbackEnemy then
					directTarget = fallbackEnemy
					if fallbackImpact then
						nextPosition = fallbackImpact
					end
				end
			end

			local facing = displacement.Unit
			grenade.CFrame = CFrame.lookAt(nextPosition, nextPosition + facing)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(225, 190, 120), 0.18, 0.08)

			currentPosition = nextPosition
			velocity = nextVelocity
			elapsed += stepTime
			traveled += displacement.Magnitude

			if raycastResult or directTarget then
				if directTarget then
					applyDamageToEnemy(player, directTarget, blastDamage, weaponDef)
				end
				break
			end
		end

		if grenade.Parent then
			createExplosionEffect(currentPosition, blastRadius)
			applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef)
			grenade:Destroy()
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
	elseif weaponClass == "GrenadeLauncher" then
		handle.Size = Vector3.new(1.2, 1.2, 3.8)
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

local function isDualWieldWeapon(weaponDef)
	if type(weaponDef.DualWield) == "boolean" then
		return weaponDef.DualWield
	end
	return false
end

local function findHandPart(character, isLeft)
	local preferredNames = if isLeft then { "LeftHand", "Left Arm" } else { "RightHand", "Right Arm" }
	for _, name in ipairs(preferredNames) do
		local part = character:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function buildOffhandGrip(weaponDef)
	local gripOffset = Vector3.new(-0.3, -0.8, 0)
	local gripRotationDeg = Vector3.new(0, 0, 0)

	if typeof(weaponDef.OffhandGripPositionOffset) == "Vector3" then
		gripOffset += weaponDef.OffhandGripPositionOffset
	elseif typeof(weaponDef.GripPositionOffset) == "Vector3" then
		gripOffset += Vector3.new(-weaponDef.GripPositionOffset.X, weaponDef.GripPositionOffset.Y, weaponDef.GripPositionOffset.Z)
	end

	if typeof(weaponDef.OffhandGripRotationDeg) == "Vector3" then
		gripRotationDeg = weaponDef.OffhandGripRotationDeg
	elseif typeof(weaponDef.GripRotationDeg) == "Vector3" then
		gripRotationDeg = Vector3.new(weaponDef.GripRotationDeg.X, -weaponDef.GripRotationDeg.Y, -weaponDef.GripRotationDeg.Z)
	end

	return CFrame.new(gripOffset)
		* CFrame.Angles(math.rad(gripRotationDeg.X), math.rad(gripRotationDeg.Y), math.rad(gripRotationDeg.Z))
end

local function stopDualWieldArmPose(state)
	if state.offhandPoseConn then
		state.offhandPoseConn:Disconnect()
		state.offhandPoseConn = nil
	end

	if state.offhandLeftShoulder and state.offhandLeftShoulder.Parent then
		state.offhandLeftShoulder.Transform = CFrame.new()
		local leftState = state.offhandLeftShoulderState
		if leftState then
			if typeof(leftState.c0) == "CFrame" then
				state.offhandLeftShoulder.C0 = leftState.c0
			end
			pcall(function()
				if type(leftState.maxVelocity) == "number" then
					state.offhandLeftShoulder.MaxVelocity = leftState.maxVelocity
				end
				if type(leftState.desiredAngle) == "number" then
					state.offhandLeftShoulder.DesiredAngle = leftState.desiredAngle
				end
			end)
		end
	end

	if state.offhandRightShoulder and state.offhandRightShoulder.Parent then
		state.offhandRightShoulder.Transform = CFrame.new()
		local rightState = state.offhandRightShoulderState
		if rightState then
			if typeof(rightState.c0) == "CFrame" then
				state.offhandRightShoulder.C0 = rightState.c0
			end
			pcall(function()
				if type(rightState.maxVelocity) == "number" then
					state.offhandRightShoulder.MaxVelocity = rightState.maxVelocity
				end
				if type(rightState.desiredAngle) == "number" then
					state.offhandRightShoulder.DesiredAngle = rightState.desiredAngle
				end
			end)
		end
	end

	state.offhandLeftShoulder = nil
	state.offhandRightShoulder = nil
	state.offhandLeftShoulderState = nil
	state.offhandRightShoulderState = nil
end

local function isR6ShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end
	if motor.Name == "Left Shoulder" or motor.Name == "Right Shoulder" then
		return true
	end

	local part1 = motor.Part1
	if not part1 then
		return false
	end

	local part1Name = string.lower(part1.Name)
	return part1Name == "left arm" or part1Name == "right arm"
end

local function startDualWieldArmPose(character, state)
	stopDualWieldArmPose(state)
	-- Client handles the dual-wield arm pose locally to avoid server/client joint conflicts.
	return
end

local function clearDualWieldOffhand(state)
	stopDualWieldArmPose(state)

	if state.offhandModel and state.offhandModel.Parent then
		state.offhandModel:Destroy()
	end
	state.offhandModel = nil
	state.offhandRoot = nil
end

local function createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
	clearDualWieldOffhand(state)

	if not (tool and tool.Parent == character and character and character:IsA("Model")) then
		return
	end
	if not (handle and handle:IsA("BasePart")) then
		return
	end

	local leftHand = findHandPart(character, true)
	if not leftHand then
		return
	end
	startDualWieldArmPose(character, state)

	local sourceParts = {}
	local seen = {}
	local function addSourcePart(part)
		if part and part:IsA("BasePart") and not seen[part] then
			seen[part] = true
			table.insert(sourceParts, part)
		end
	end

	addSourcePart(handle)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= handle then
			if descendant.Transparency < 0.995 then
				addSourcePart(descendant)
			end
		end
	end

	if #sourceParts == 0 then
		return
	end

	local sourceRoot = handle
	local sourceRootCFrame = sourceRoot.CFrame
	local relativeCFrames = {}
	for _, sourcePart in ipairs(sourceParts) do
		relativeCFrames[sourcePart] = sourceRootCFrame:ToObjectSpace(sourcePart.CFrame)
	end

	local offhandModel = Instance.new("Model")
	offhandModel.Name = "DualWieldOffhand"
	offhandModel.Parent = character

	local sourceToClone = {}
	local offhandRoot = nil
	for _, sourcePart in ipairs(sourceParts) do
		local clonePart = sourcePart:Clone()
		for _, cloneDescendant in clonePart:GetDescendants() do
			if cloneDescendant:IsA("JointInstance") or cloneDescendant:IsA("WeldConstraint") then
				cloneDescendant:Destroy()
			end
		end
		clonePart.Anchored = false
		clonePart.CanCollide = false
		clonePart.CanTouch = false
		clonePart.CanQuery = false
		clonePart.Massless = true
		clonePart.Parent = offhandModel

		sourceToClone[sourcePart] = clonePart
		if sourcePart == sourceRoot then
			offhandRoot = clonePart
		end
	end

	if not offhandRoot then
		offhandModel:Destroy()
		return
	end

	local offhandGrip = buildOffhandGrip(weaponDef)
	offhandRoot.CFrame = leftHand.CFrame * offhandGrip

	for _, sourcePart in ipairs(sourceParts) do
		if sourcePart ~= sourceRoot then
			local clonePart = sourceToClone[sourcePart]
			clonePart.CFrame = offhandRoot.CFrame * relativeCFrames[sourcePart]

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = offhandRoot
			weld.Part1 = clonePart
			weld.Parent = offhandRoot
		end
	end

	local handWeld = Instance.new("WeldConstraint")
	handWeld.Name = "DualWieldHandWeld"
	handWeld.Part0 = leftHand
	handWeld.Part1 = offhandRoot
	handWeld.Parent = offhandRoot

	state.offhandModel = offhandModel
	state.offhandRoot = offhandRoot
end

local function normalizeTemplateKey(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function keyMatches(candidateKey, queryKey)
	if queryKey == "" then
		return false
	end
	if candidateKey == queryKey then
		return true
	end
	if not string.find(candidateKey, queryKey, 1, true) then
		return false
	end

	-- Avoid false positives like matching "ak" inside "makarov".
	if #queryKey <= 2 then
		return string.sub(candidateKey, 1, #queryKey) == queryKey
	end

	return true
end

local function isTemplateCandidate(instance)
	return instance:IsA("Tool") or instance:IsA("Model") or instance:IsA("BasePart")
end

local function collectTemplateCandidates(container, out)
	for _, child in container:GetChildren() do
		if isTemplateCandidate(child) then
			table.insert(out, child)
		elseif child:IsA("Folder") then
			collectTemplateCandidates(child, out)
		end
	end
end

local function matchesTemplateCandidate(candidate, templateNameLower, templateNameKey, idLower, nameLower, idKey, nameKey)
	local candidateNameLower = string.lower(candidate.Name)
	local candidateKey = normalizeTemplateKey(candidate.Name)

	if templateNameLower ~= "" and candidateNameLower == templateNameLower then
		return true
	end
	if keyMatches(candidateKey, templateNameKey) then
		return true
	end

	if candidateNameLower == idLower or candidateNameLower == nameLower then
		return true
	end
	if keyMatches(candidateKey, idKey) then
		return true
	end
	if keyMatches(candidateKey, nameKey) then
		return true
	end

	local attributeKey = normalizeTemplateKey(
		candidate:GetAttribute("WeaponId")
			or candidate:GetAttribute("ShopWeaponId")
			or candidate:GetAttribute("TemplateId")
	)
	if attributeKey ~= "" and (attributeKey == idKey or attributeKey == nameKey or attributeKey == templateNameKey) then
		return true
	end

	return false
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

	local templateCandidates = {}
	collectTemplateCandidates(shopItemsFolder, templateCandidates)

	for _, candidate in templateCandidates do
		if matchesTemplateCandidate(candidate, templateNameLower, templateNameKey, idLower, nameLower, idKey, nameKey) then
			return candidate
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

sentryRuntime = SentryRuntime.new({
	modelRootResolver = ModelRootResolver,
	createExplosionEffect = createExplosionEffect,
	createMuzzleFlash = createMuzzleFlash,
	createTracerSegment = createTracerSegment,
	createFlamePuff = createFlamePuff,
	randomGenerator = randomGenerator,
	sentryTurretFolderName = SENTRY_TURRET_FOLDER_NAME,
	defaultSentryMaxAmmo = DEFAULT_SENTRY_MAX_AMMO,
})

local function removeSentryRecord(model)
	sentryRuntime.removeRecord(model)
end

local function clearPlayerSentries(player, options)
	sentryRuntime.clearPlayerSentries(player, options)
end

local function disconnectPlayerSentryDeathBindings(player)
	sentryRuntime.disconnectPlayerSentryDeathBindings(player)
end

local function bindPlayerSentryDeathCleanup(player)
	sentryRuntime.bindPlayerSentryDeathCleanup(player)
end

local function prunePlayerSentries(player)
	return sentryRuntime.prunePlayerSentries(player)
end

local function countPlayerSentriesByKind(player, kindId)
	return sentryRuntime.countPlayerSentriesByKind(player, kindId)
end

local function resolveTurretMaxAmmo(weaponDef)
	return sentryRuntime.resolveTurretMaxAmmo(weaponDef)
end

local function resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)
	return sentryRuntime.resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)
end

local function syncSentryAmmoAttributes(record)
	sentryRuntime.syncSentryAmmoAttributes(record)
end

local function collectOwnedSentryRecordsByWeaponId(player)
	return sentryRuntime.collectOwnedSentryRecordsByWeaponId(player)
end

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

local function startTurretCombatLoop(record)
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
				maxAmmo = resolveTurretMaxAmmo(record.weaponDef)
			end
			maxAmmo = math.max(1, math.floor(maxAmmo + 0.5))
			record.maxAmmo = maxAmmo
			record.ammo = math.clamp(math.floor((tonumber(record.ammo) or maxAmmo) + 0.5), 0, maxAmmo)
			if record.ammo <= 0 then
				syncSentryAmmoAttributes(record)
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
			createMuzzleFlash(muzzleOrigin, Color3.fromRGB(120, 225, 255), 0.22, 0.05)
			createTracerSegment(muzzleOrigin, enemyRoot.Position, Color3.fromRGB(120, 225, 255), 0.1, 0.05)
			applyDamageToEnemy(record.owner, enemyModel, turretShotDamage, nil, {
				applyClassMultiplier = false,
				allowBurnOnHit = false,
				allowCriticalHits = false,
			})
			record.ammo = math.max(0, record.ammo - 1)
			syncSentryAmmoAttributes(record)

			local flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
			if flatLook.Magnitude > 0.01 then
				record.model:PivotTo(CFrame.lookAt(rootPart.Position, rootPart.Position + flatLook.Unit))
			end
		end

		if record.model and record.model.Parent then
			record.model:Destroy()
		end
		removeSentryRecord(record.model)
	end)
end

local function buildSentryModelFromTemplate(weaponDef)
	local template = findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Model") then
		return template:Clone()
	end

	if template:IsA("Tool") then
		local clonedTool = template:Clone()
		local model = Instance.new("Model")
		model.Name = clonedTool.Name
		for _, child in ipairs(clonedTool:GetChildren()) do
			child.Parent = model
		end
		clonedTool:Destroy()
		if not model:FindFirstChildWhichIsA("BasePart", true) then
			model:Destroy()
			return nil
		end
		return model
	end

	if template:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = template.Name
		local part = template:Clone()
		part.Parent = model
		return model
	end

	return nil
end

local function resolveSentryPlacementCFrame(player, character, rootPart, sentryModel, weaponDef, explicitShotOrigin, explicitShotDirection)
	local fallbackOrigin = rootPart.Position + Vector3.new(0, 1.5, 0)
	local fallbackDirection = rootPart.CFrame.LookVector
	local rayDirection = nil

	local aimState = getFreshAimState(player)
	if aimState and typeof(aimState.hitPosition) == "Vector3" then
		local toAimHit = aimState.hitPosition - fallbackOrigin
		if toAimHit.Magnitude > 0.01 then
			rayDirection = toAimHit.Unit
		end
	end

	if typeof(rayDirection) ~= "Vector3" or rayDirection.Magnitude <= 0.001 then
		local fallbackRayDirection = explicitShotDirection
		if typeof(fallbackRayDirection) ~= "Vector3" or fallbackRayDirection.Magnitude <= 0.001 then
			_, fallbackRayDirection = getPlayerShotRay(player, rootPart, fallbackOrigin, fallbackDirection)
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
	local raycastParams = buildWeaponRaycastParams(character, raycastExclusions)
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
	local placementCFrame = CFrame.lookAt(placementPosition, placementPosition + lookDirection.Unit)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapExclusions = { character, getEffectsFolder() }
	if enemyContainer then
		table.insert(overlapExclusions, enemyContainer)
	end
	overlapParams.FilterDescendantsInstances = overlapExclusions

	local padding = Vector3.new(0.25, 0.25, 0.25)
	local overlaps = Workspace:GetPartBoundsInBox(placementCFrame, boundsSize + padding, overlapParams)
	for _, part in ipairs(overlaps) do
		if part and part.Parent and part.CanCollide then
			return nil
		end
	end

	return placementCFrame
end

local function deploySentryTurret(player, character, rootPart, weaponDef, explicitShotOrigin, explicitShotDirection)
	local activeCount = prunePlayerSentries(player)
	if activeCount >= MAX_SENTRY_COUNT_PER_PLAYER then
		return false
	end
	if countPlayerSentriesByKind(player, weaponDef.Id) >= 1 then
		return false
	end

	local sentryModel = buildSentryModelFromTemplate(weaponDef)
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
	local turretMaxAmmo = resolveTurretMaxAmmo(weaponDef)
	local turretInitialAmmo = resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)

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
	syncSentryAmmoAttributes(record)

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
			removeSentryRecord(sentryModel)
		end
	end))

	refreshHealthVisuals(humanoid.Health)
	startTurretCombatLoop(record)
	return true
end

local function repairOwnedSentries(player, weaponDef)
	local records = sentryRuntime.getPlayerSentryModels(player)
	if not records or #records == 0 then
		return
	end

	prunePlayerSentries(player)
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

local function consumeOwnedWeaponInstances(player, weaponId)
	return InventoryIndex.destroyWeaponToolsById(player, weaponId)
end

local function configureWeaponTool(tool, weaponDef, owner)
	local weaponClass = resolveWeaponClass(weaponDef)
	local dualWieldEnabled = isDualWieldWeapon(weaponDef)

	tool.Name = weaponDef.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponDef.Id)
	tool:SetAttribute("WeaponClass", weaponClass)
	tool:SetAttribute("ClassTag", weaponDef.ClassTag)
	tool:SetAttribute("RequiredClassId", weaponDef.ClassId)
	tool:SetAttribute("DualWield", dualWieldEnabled)
	tool:SetAttribute("AutoFire", weaponDef.AutoFire == true)
	tool:SetAttribute("Damage", weaponDef.Damage)
	tool:SetAttribute("Range", weaponDef.Range)
	tool:SetAttribute("Cooldown", weaponDef.Cooldown)
	tool:SetAttribute("TurretPlacementDistance", weaponDef.TurretPlacementDistance)
	tool:SetAttribute("MagazineSize", getMagazineSize(weaponDef, owner))
	tool:SetAttribute("ReloadSeconds", getReloadSeconds(weaponDef, owner))

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

	local state = getToolState(tool, weaponDef, owner)
	state.baseGrip = tool.Grip
	state.dualWieldEnabled = dualWieldEnabled
	state.nextDualWieldShotLeft = false
	updateAmmoAttributes(tool, weaponDef, state, owner)

	local function fireWeapon(owner, character, humanoid, rootPart, explicitShotOrigin, explicitShotDirection)
		if not ClassService.canPlayerUseWeapon(owner, weaponDef) then
			ClassService.enforcePlayerLoadout(owner)
			return
		end

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

		-- Keep anti-backshot for offensive weapons; sentry deploy/repair should follow placement/repair rules instead.
		if weaponClass ~= "SentryDeployer" and weaponClass ~= "RepairTool" and not canPlayerFireTowardRequestedDirection(owner, rootPart, explicitShotDirection) then
			return
		end

		if not tryConsumeAmmo(tool, weaponDef, state, owner) then
			return
		end

		state.lastActivatedAt = now

		if dualWieldEnabled then
			local hasOffhandVisual = state.offhandRoot and state.offhandRoot.Parent ~= nil
			if not hasOffhandVisual then
				createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
			end
		end

		local origin, direction = getWeaponOriginAndDirection(owner, character, rootPart, handle)
		local shotOrigin, shotDirection = nil, nil
		if typeof(explicitShotOrigin) == "Vector3" and typeof(explicitShotDirection) == "Vector3" and explicitShotDirection.Magnitude > 0.001 then
			shotOrigin = explicitShotOrigin
			shotDirection = clampDirectionToForwardFireArc(rootPart, explicitShotDirection, direction)
		else
			shotOrigin, shotDirection = getPlayerShotRay(owner, rootPart, origin, direction)
		end

		if weaponClass == "SentryDeployer" then
			local didDeploy = deploySentryTurret(owner, character, rootPart, weaponDef, shotOrigin, shotDirection)
			if didDeploy then
				consumeOwnedWeaponInstances(owner, weaponDef.Id)
			end
		elseif weaponClass == "RepairTool" then
			repairOwnedSentries(owner, weaponDef)
		elseif weaponClass == "Melee" then
			fireMeleeAttack(owner, character, origin, direction, weaponDef, state, tool)
		elseif weaponClass == "Flamethrower" then
			fireFlamethrower(owner, character, weaponDef, state, handle)
		elseif weaponClass == "RPG" then
			fireRocket(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
		elseif weaponClass == "GrenadeLauncher" then
			fireGrenadeLauncher(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
		else
			local muzzleOrigin = origin
			if dualWieldEnabled and state.nextDualWieldShotLeft and state.offhandRoot and state.offhandRoot.Parent then
				local offhandRoot = state.offhandRoot
				muzzleOrigin = offhandRoot.Position + (direction * math.max(0.8, offhandRoot.Size.Z * 0.45))
			end

			fireBulletShot(owner, character, muzzleOrigin, direction, weaponDef, shotOrigin, shotDirection)

			if dualWieldEnabled then
				state.nextDualWieldShotLeft = not state.nextDualWieldShotLeft
			end
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

	state.reloadHandler = function(owner)
		if not owner or not owner:IsA("Player") then
			return
		end

		if not ClassService.canPlayerUseWeapon(owner, weaponDef) then
			ClassService.enforcePlayerLoadout(owner)
			return
		end

		local character = owner.Character
		if not character or tool.Parent ~= character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		startReload(tool, weaponDef, state, owner)
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

	tool.Equipped:Connect(function()
		if not dualWieldEnabled then
			return
		end

		local character = tool.Parent
		if character and character:IsA("Model") then
			createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
		end
	end)

	tool.Unequipped:Connect(function()
		if dualWieldEnabled then
			clearDualWieldOffhand(state)
			state.nextDualWieldShotLeft = false
		end
	end)

	tool.Destroying:Connect(function()
		if state then
			clearDualWieldOffhand(state)
			state.fireHandler = nil
			state.reloadHandler = nil
		end
		ammoRuntime.clearToolState(tool)
	end)
end

local function createWeaponTool(weaponDef, owner)
	local tool = createToolFromTemplate(weaponDef)
	if not tool then
		tool = createFallbackWeaponTool(weaponDef)
	end

	configureWeaponTool(tool, weaponDef, owner)
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

local function normalizeAmmoRefillMode(value)
	return ammoRuntime.normalizeAmmoRefillMode(value)
end

local function refillAmmoForTool(tool, weaponDef, owner, refillMode, reserveAmount)
	return ammoRuntime.refillAmmoForTool(tool, weaponDef, owner, refillMode, reserveAmount)
end

local function refillAmmoForSentryRecords(sentryRecords, weaponDef)
	if type(sentryRecords) ~= "table" then
		return false
	end

	local didRefill = false
	local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)
	for _, record in ipairs(sentryRecords) do
		if record and record.model and record.model.Parent and record.humanoid and record.humanoid.Health > 0 then
			local turretMaxAmmo = math.max(
				1,
				math.floor(
					(tonumber(record.maxAmmo) or tonumber(record.model:GetAttribute("TurretMaxAmmo")) or fallbackMaxAmmo) + 0.5
				)
			)
			local ammoBefore = math.clamp(
				math.floor((tonumber(record.ammo) or tonumber(record.model:GetAttribute("TurretAmmo")) or turretMaxAmmo) + 0.5),
				0,
				turretMaxAmmo
			)

			record.maxAmmo = turretMaxAmmo
			record.ammo = turretMaxAmmo
			syncSentryAmmoAttributes(record)

			if ammoBefore < turretMaxAmmo then
				didRefill = true
			end
		end
	end

	return didRefill
end

local function playerOwnsWeapon(player, weaponId)
	local normalizedWeaponId = tostring(weaponId or "")
	if normalizedWeaponId == "" then
		return false
	end

	if InventoryIndex.hasWeaponTool(player, normalizedWeaponId) then
		return true
	end

	return sentryRuntime.playerOwnsWeaponId(player, normalizedWeaponId)
end

local function getRequiredOwnedWeaponId(weaponDef)
	return CatalogAndPricing.getRequiredOwnedWeaponId(weaponDef, weaponById)
end

local function getUpgradeRestrictionMessage(weaponDef)
	return CatalogAndPricing.getUpgradeRestrictionMessage(weaponDef, weaponById)
end

local function canPurchaseNow()
	return CatalogAndPricing.canPurchaseNow(remotesFolder, Config)
end

local function canPlayerUseWeapon(player, weaponDef)
	return ClassService.canPlayerUseWeapon(player, weaponDef)
end

local function getWeaponCostForPlayer(player, weaponDef)
	return CatalogAndPricing.getWeaponCostForPlayer(player, weaponDef, ClassService)
end

local function collectOwnedWeaponToolsById(player)
	return InventoryIndex.collectFirstWeaponToolById(player)
end

local function getToolAmmoSnapshot(tool, weaponDef, owner)
	return ammoRuntime.getToolAmmoSnapshot(tool, weaponDef, owner)
end

local function getSentryAmmoSnapshot(sentryRecords, weaponDef)
	if type(sentryRecords) ~= "table" or #sentryRecords == 0 then
		return nil
	end

	local totalCurrentAmmo = 0
	local totalMaxAmmo = 0
	local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)

	for _, record in ipairs(sentryRecords) do
		if type(record) == "table" and record.humanoid and record.humanoid.Health > 0 then
			local model = record.model
			local modelMaxAmmo = if model and model:IsA("Model") then model:GetAttribute("TurretMaxAmmo") else nil
			local modelAmmo = if model and model:IsA("Model") then model:GetAttribute("TurretAmmo") else nil
			local turretMaxAmmo = math.max(
				1,
				math.floor((tonumber(record.maxAmmo) or tonumber(modelMaxAmmo) or fallbackMaxAmmo) + 0.5)
			)
			local turretAmmo = math.clamp(
				math.floor((tonumber(record.ammo) or tonumber(modelAmmo) or turretMaxAmmo) + 0.5),
				0,
				turretMaxAmmo
			)

			record.maxAmmo = turretMaxAmmo
			record.ammo = turretAmmo
			syncSentryAmmoAttributes(record)

			totalCurrentAmmo += turretAmmo
			totalMaxAmmo += turretMaxAmmo
		end
	end

	local missingAmmo = math.max(0, totalMaxAmmo - totalCurrentAmmo)
	return {
		currentTotalAmmo = totalCurrentAmmo,
		maxTotalAmmo = totalMaxAmmo,
		missingAmmo = missingAmmo,
	}
end

local function collectAmmoRefillQuotesForOwnedWeapons(player)
	return CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, {
		config = Config,
		weaponById = weaponById,
		canPlayerUseWeapon = canPlayerUseWeapon,
		collectOwnedWeaponToolsById = collectOwnedWeaponToolsById,
		prunePlayerSentries = prunePlayerSentries,
		collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = getToolAmmoSnapshot,
		getSentryAmmoSnapshot = getSentryAmmoSnapshot,
		getWeaponCostForPlayer = getWeaponCostForPlayer,
	})
end

local function getClassRestrictionMessage(player)
	return CatalogAndPricing.getClassRestrictionMessage(player, ClassService)
end

local function getCatalogForPlayer(player)
	return CatalogAndPricing.getCatalogForPlayer(player, {
		config = Config,
		classService = ClassService,
		weaponById = weaponById,
		remotesFolder = remotesFolder,
		canPlayerUseWeapon = canPlayerUseWeapon,
		playerOwnsWeapon = playerOwnsWeapon,
		resolveWeaponClass = resolveWeaponClass,
		getWeaponCostForPlayer = getWeaponCostForPlayer,
		getMagazineSize = getMagazineSize,
		getReloadSeconds = getReloadSeconds,
		collectOwnedWeaponToolsById = collectOwnedWeaponToolsById,
		prunePlayerSentries = prunePlayerSentries,
		collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = getToolAmmoSnapshot,
		getSentryAmmoSnapshot = getSentryAmmoSnapshot,
	})
end

local function buyWeapon(player, weaponId)
	return PurchaseFlow.buyWeapon(player, weaponId, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		canPlayerUseWeapon = canPlayerUseWeapon,
		getClassRestrictionMessage = getClassRestrictionMessage,
		getRequiredOwnedWeaponId = getRequiredOwnedWeaponId,
		playerOwnsWeapon = playerOwnsWeapon,
		getUpgradeRestrictionMessage = getUpgradeRestrictionMessage,
		getMoneyValue = getMoneyValue,
		getWeaponCostForPlayer = getWeaponCostForPlayer,
		createWeaponTool = createWeaponTool,
	})
end

local function buyAmmoForWeapon(player, weaponId)
	return PurchaseFlow.buyAmmoForWeapon(player, weaponId, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		canPlayerUseWeapon = canPlayerUseWeapon,
		getClassRestrictionMessage = getClassRestrictionMessage,
		collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyValue = getMoneyValue,
		refillAmmoForTool = refillAmmoForTool,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
	})
end

local function buyAmmoForAllOwnedWeapons(player)
	return PurchaseFlow.buyAmmoForAllOwnedWeapons(player, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyValue = getMoneyValue,
		refillAmmoForTool = refillAmmoForTool,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
	})
end

function ShopService.refillPlayerAmmo(player, options)
	if not player or not player:IsA("Player") then
		return false
	end

	local refillMode = "ReserveOnly"
	local reserveAmount = nil
	if type(options) == "table" then
		refillMode = normalizeAmmoRefillMode(options.mode)
		reserveAmount = options.reserveAmount
	end

	local anyRefilled = false
	for _, tool in ipairs(InventoryIndex.getAllTools(player)) do
		local weaponId = tool:GetAttribute("WeaponId")
		if type(weaponId) == "string" and weaponId ~= "" then
			local weaponDef = weaponById[weaponId]
			if weaponDef and refillAmmoForTool(tool, weaponDef, player, refillMode, reserveAmount) then
				anyRefilled = true
			end
		end
	end

	return anyRefilled
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

	local turretFolder = getSentryTurretFolder()
	for _, child in ipairs(turretFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

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
	shopBuyAmmoFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyAmmo)
	weaponAimRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponAim)
	weaponFireRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponFire)
	weaponReloadRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponReload)
	damageIndicatorRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.DamageIndicator)

	shopGetCatalogFunction.OnServerInvoke = function(player)
		return getCatalogForPlayer(player)
	end

	if not classChangedCleanupDisconnect and type(ClassService.registerClassChangedCallback) == "function" then
		classChangedCleanupDisconnect = ClassService.registerClassChangedCallback(function(player, previousClassId, selectedClassId)
			if not player or not player:IsA("Player") then
				return
			end
			if previousClassId == selectedClassId then
				return
			end

			clearPlayerSentries(player, {
				playDestroyEffect = true,
			})
		end)
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

	shopBuyAmmoFunction.OnServerInvoke = function(player, request)
		if type(request) == "string" then
			return buyAmmoForWeapon(player, request)
		end

		if type(request) ~= "table" then
			return {
				success = false,
				message = "Invalid ammo purchase request.",
			}
		end

		if request.allOwned == true then
			return buyAmmoForAllOwnedWeapons(player)
		end

		local weaponId = request.weaponId
		if type(weaponId) ~= "string" or weaponId == "" then
			return {
				success = false,
				message = "Invalid weapon ammo request.",
			}
		end

		return buyAmmoForWeapon(player, weaponId)
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

			local weaponDef = weaponById[weaponId]
			if not weaponDef then
				return
			end
			if not canPlayerUseWeapon(player, weaponDef) then
				ClassService.enforcePlayerLoadout(player)
				return
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

	if weaponReloadRemote then
		weaponReloadRemote.OnServerEvent:Connect(function(player, weaponId)
			if type(weaponId) ~= "string" or weaponId == "" then
				return
			end

			local weaponDef = weaponById[weaponId]
			if not weaponDef then
				return
			end
			if not canPlayerUseWeapon(player, weaponDef) then
				ClassService.enforcePlayerLoadout(player)
				return
			end

			local tool = getEquippedWeaponTool(player, weaponId)
			if not tool then
				return
			end

			local state = toolRuntimeState[tool]
			if not state then
				return
			end

			if type(state.reloadHandler) == "function" then
				state.reloadHandler(player)
				return
			end

			startReload(tool, weaponDef, state, player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		bindPlayerSentryDeathCleanup(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerAimState[player] = nil
		playerGroundFireState[player] = nil
		clearPlayerSentries(player)
		disconnectPlayerSentryDeathBindings(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayerSentryDeathCleanup(player)
	end

	ensureTraderPrompt()
end

return ShopService
