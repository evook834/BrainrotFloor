local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local ClassService = {}

local started = false
local remotesFolder = nil
local classGetDataFunction = nil
local classSelectFunction = nil
local classStateRemote = nil
local classById = {}
local classOrder = {}
local weaponById = {}
local playerStateByPlayer = {}
local pushThrottleByPlayer = {}
local characterConnectionByPlayer = {}

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

local function normalizeToken(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function getClassSystemConfig()
	return Config.ClassSystem or {}
end

local function getMaxLevel()
	local maxLevel = math.floor(tonumber(getClassSystemConfig().MaxLevel) or 200)
	if maxLevel < 1 then
		maxLevel = 1
	end
	return maxLevel
end

local function getClassDefinition(classId)
	return classById[normalizeToken(classId)]
end

local function getDefaultClassId()
	local configured = normalizeToken(getClassSystemConfig().DefaultClassId)
	if configured ~= "" and classById[configured] then
		return configured
	end

	local firstClass = classOrder[1]
	if firstClass then
		return firstClass.Id
	end

	return ""
end

local function getXpRequiredForNextLevel(classDef, level)
	if not classDef then
		return nil
	end
	if level >= getMaxLevel() then
		return nil
	end

	local progression = classDef.Progression
	local baseXp = math.max(10, tonumber(progression.BaseXpToLevel) or 100)
	local growth = math.clamp(tonumber(progression.XpGrowthPerLevel) or 0.05, 0, 1)
	local requirement = baseXp * ((1 + growth) ^ math.max(0, level - 1))

	local progressionCurve = getClassSystemConfig().ProgressionCurve or {}
	local levelBandSize = math.max(1, math.floor(tonumber(progressionCurve.LevelBandSize) or 10))
	local decadeStepMultiplier = math.max(1, tonumber(progressionCurve.DecadeStepMultiplier) or 1)
	if decadeStepMultiplier > 1 then
		local levelBandIndex = math.floor(math.max(0, level - 1) / levelBandSize)
		requirement *= decadeStepMultiplier ^ levelBandIndex
	end

	local earlyLevelsFastUntil = math.max(1, math.floor(tonumber(progressionCurve.EarlyLevelsFastUntil) or 1))
	local earlyLevelsMultiplier = math.clamp(tonumber(progressionCurve.EarlyLevelsMultiplier) or 1, 0.1, 1)
	if earlyLevelsMultiplier < 1 and level <= earlyLevelsFastUntil then
		local blendAlpha = 1
		if earlyLevelsFastUntil > 1 then
			blendAlpha = (level - 1) / (earlyLevelsFastUntil - 1)
		end
		local earlyScale = earlyLevelsMultiplier + ((1 - earlyLevelsMultiplier) * blendAlpha)
		requirement *= earlyScale
	end

	local classXpRequirementMultiplier = math.max(0.001, tonumber(progression.XpRequirementMultiplier) or 1)
	requirement *= classXpRequirementMultiplier

	local earlyLevelXpRequirementMultiplier = math.max(0.001, tonumber(progression.EarlyLevelXpRequirementMultiplier) or 1)
	if earlyLevelXpRequirementMultiplier ~= 1 then
		local earlyLevelXpUntilLevel = math.max(
			1,
			math.floor(tonumber(progression.EarlyLevelXpUntilLevel) or earlyLevelsFastUntil)
		)
		if level <= earlyLevelXpUntilLevel then
			requirement *= earlyLevelXpRequirementMultiplier
		end
	end

	local xpRequirementMultiplier = math.max(0.001, tonumber(getClassSystemConfig().XpRequirementMultiplier) or 1)
	requirement *= xpRequirementMultiplier

	return math.max(1, math.floor(requirement + 0.5))
end

local function getBonusesAtLevel(classDef, level)
	local levelIndex = math.max(1, math.floor(tonumber(level) or 1))
	local bonusLevels = levelIndex - 1
	local bonuses = classDef and classDef.Bonuses or {}

	local damagePerLevel = math.max(
		0,
		tonumber(bonuses.DamagePerLevel)
			or tonumber(bonuses.WeaponDamagePerLevel)
			or 0
	)
	local damageMultiplier = 1 + (damagePerLevel * bonusLevels)
	local maxHealthMultiplier = 1 + (math.max(0, tonumber(bonuses.MaxHealthPerLevel) or 0) * bonusLevels)
	local moveSpeedMultiplier = 1 + (math.max(0, tonumber(bonuses.MoveSpeedPerLevel) or 0) * bonusLevels)
	local meleeRangeMultiplier = 1 + (math.max(0, tonumber(bonuses.MeleeRangePerLevel) or 0) * bonusLevels)
	local totalDamageReduction = math.clamp(
		math.max(0, tonumber(bonuses.DamageReductionPerLevel) or 0) * bonusLevels,
		0,
		0.85
	)
	local incomingDamageMultiplier = 1 - totalDamageReduction
	local shopDiscount = math.clamp(
		math.max(0, tonumber(bonuses.ShopDiscountPerLevel) or tonumber(bonuses.ShopCostReductionPerLevel) or 0) * bonusLevels,
		0,
		0.9
	)
	local magazineSizeMultiplier = 1
		+ (
			math.max(0, tonumber(bonuses.MagazineSizePerLevel) or tonumber(bonuses.MagSizePerLevel) or 0) * bonusLevels
		)
	local reloadSpeedBonus = math.max(0, tonumber(bonuses.ReloadSpeedPerLevel) or tonumber(bonuses.ReloadPerLevel) or 0)
		* bonusLevels
	local reloadTimeMultiplier = 1 / (1 + reloadSpeedBonus)
	local spreadReduction = math.clamp(
		math.max(
			0,
			tonumber(bonuses.BulletSpreadReductionPerLevel)
				or tonumber(bonuses.SpreadReductionPerLevel)
				or tonumber(bonuses.AccuracyPerLevel)
				or 0
		) * bonusLevels,
		0,
		0.8
	)
	local bulletSpreadMultiplier = 1 - spreadReduction

	return {
		damageMultiplier = math.max(0, damageMultiplier),
		maxHealthMultiplier = math.max(0.1, maxHealthMultiplier),
		moveSpeedMultiplier = math.max(0.1, moveSpeedMultiplier),
		meleeRangeMultiplier = math.max(0.1, meleeRangeMultiplier),
		incomingDamageMultiplier = math.max(0.05, incomingDamageMultiplier),
		shopCostMultiplier = math.max(0.1, 1 - shopDiscount),
		shopDiscount = shopDiscount,
		magazineSizeMultiplier = math.max(0.1, magazineSizeMultiplier),
		reloadTimeMultiplier = math.max(0.1, reloadTimeMultiplier),
		bulletSpreadMultiplier = math.max(0.2, bulletSpreadMultiplier),
	}
end

local function summarizeBonuses(bonuses)
	local reloadSpeedMultiplier = 1 / math.max(0.1, bonuses.reloadTimeMultiplier or 1)
	return {
		damageMultiplier = bonuses.damageMultiplier,
		maxHealthMultiplier = bonuses.maxHealthMultiplier,
		moveSpeedMultiplier = bonuses.moveSpeedMultiplier,
		meleeRangeMultiplier = bonuses.meleeRangeMultiplier,
		incomingDamageMultiplier = bonuses.incomingDamageMultiplier,
		shopCostMultiplier = bonuses.shopCostMultiplier,
		shopDiscount = bonuses.shopDiscount,
		magazineSizeMultiplier = bonuses.magazineSizeMultiplier,
		reloadTimeMultiplier = bonuses.reloadTimeMultiplier,
		bulletSpreadMultiplier = bonuses.bulletSpreadMultiplier,
		damagePct = (bonuses.damageMultiplier - 1) * 100,
		maxHealthPct = (bonuses.maxHealthMultiplier - 1) * 100,
		moveSpeedPct = (bonuses.moveSpeedMultiplier - 1) * 100,
		meleeRangePct = (bonuses.meleeRangeMultiplier - 1) * 100,
		damageReductionPct = (1 - bonuses.incomingDamageMultiplier) * 100,
		shopDiscountPct = bonuses.shopDiscount * 100,
		magazineSizePct = (bonuses.magazineSizeMultiplier - 1) * 100,
		reloadSpeedPct = (reloadSpeedMultiplier - 1) * 100,
		bulletSpreadReductionPct = (1 - bonuses.bulletSpreadMultiplier) * 100,
	}
end

local function buildClassRegistry()
	table.clear(classById)
	table.clear(classOrder)

	for _, rawClass in ipairs(getClassSystemConfig().Classes or {}) do
		if type(rawClass) == "table" then
			local id = normalizeToken(rawClass.Id)
			if id ~= "" then
				local classDef = {
					Id = id,
					DisplayName = tostring(rawClass.DisplayName or rawClass.Id),
					Description = tostring(rawClass.Description or ""),
					WeaponTag = tostring(rawClass.WeaponTag or rawClass.Id),
					Progression = rawClass.Progression or {},
					Bonuses = rawClass.Bonuses or {},
				}
				classById[id] = classDef
				table.insert(classOrder, classDef)
			end
		end
	end
end

local function buildWeaponRegistry()
	table.clear(weaponById)
	for _, weaponDef in ipairs((Config.Shop and Config.Shop.Weapons) or {}) do
		if type(weaponDef.Id) == "string" and weaponDef.Id ~= "" then
			weaponById[weaponDef.Id] = weaponDef
		end
	end
end

local function getOrCreatePlayerState(player)
	local state = playerStateByPlayer[player]
	if state then
		return state
	end

	local selectedClassId = getDefaultClassId()
	state = {
		selectedClassId = selectedClassId,
		progressByClassId = {},
	}
	playerStateByPlayer[player] = state
	return state
end

local function getOrCreateClassProgress(state, classId)
	local progress = state.progressByClassId[classId]
	if progress then
		return progress
	end

	progress = {
		level = 1,
		xp = 0,
	}
	state.progressByClassId[classId] = progress
	return progress
end

local function resolveWaveState()
	if not remotesFolder then
		return "Unknown"
	end

	local waveState = remotesFolder:GetAttribute("CurrentWaveState")
	if type(waveState) ~= "string" then
		return "Unknown"
	end
	return waveState
end

local function canSwitchClassNow()
	local waveState = resolveWaveState()
	local allowedStates = getClassSystemConfig().SwitchAllowedStates or {}
	if type(allowedStates[waveState]) == "boolean" then
		return allowedStates[waveState], waveState
	end

	return waveState ~= "InProgress", waveState
end

local function isWeaponAllowedForClass(classDef, weaponDef)
	if not classDef or type(weaponDef) ~= "table" then
		return false
	end

	local classIdToken = normalizeToken(classDef.Id)
	local classWeaponTagToken = normalizeToken(classDef.WeaponTag)

	local requiredClassIdToken = normalizeToken(weaponDef.ClassId)
	if requiredClassIdToken ~= "" then
		return requiredClassIdToken == classIdToken
	end

	local weaponTagToken = normalizeToken(weaponDef.ClassTag)
	if weaponTagToken ~= "" then
		if classWeaponTagToken ~= "" and weaponTagToken == classWeaponTagToken then
			return true
		end
		return weaponTagToken == classIdToken
	end

	return false
end

local function getPlayerClassDefinition(player)
	local state = getOrCreatePlayerState(player)
	local classDef = getClassDefinition(state.selectedClassId)
	if classDef then
		return classDef
	end

	local fallbackId = getDefaultClassId()
	state.selectedClassId = fallbackId
	return getClassDefinition(fallbackId)
end

local function getPlayerSelectedClassProgress(player)
	local classDef = getPlayerClassDefinition(player)
	if not classDef then
		return nil, nil
	end

	local state = getOrCreatePlayerState(player)
	local progress = getOrCreateClassProgress(state, classDef.Id)
	return classDef, progress
end

local function getPlayerSelectedClassBonuses(player)
	local classDef, progress = getPlayerSelectedClassProgress(player)
	if not classDef or not progress then
		return nil, nil
	end

	return classDef, getBonusesAtLevel(classDef, progress.level)
end

local function applyHumanoidClassBonus(humanoid, maxHealthMultiplier)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local baseMaxHealth = humanoid:GetAttribute("ClassBaseMaxHealth")
	if type(baseMaxHealth) ~= "number" or baseMaxHealth <= 0 then
		baseMaxHealth = humanoid.MaxHealth
		humanoid:SetAttribute("ClassBaseMaxHealth", baseMaxHealth)
	end

	local previousMaxHealth = humanoid.MaxHealth
	local previousHealth = humanoid.Health
	local desiredMaxHealth = math.max(1, math.floor((baseMaxHealth * maxHealthMultiplier) + 0.5))
	if math.abs(desiredMaxHealth - previousMaxHealth) < 0.01 then
		return
	end

	local healthRatio = 1
	if previousMaxHealth > 0 then
		healthRatio = math.clamp(previousHealth / previousMaxHealth, 0, 1)
	end

	humanoid.MaxHealth = desiredMaxHealth
	humanoid.Health = math.clamp(desiredMaxHealth * healthRatio, 0, desiredMaxHealth)
end

local function applyHumanoidMoveSpeedBonus(humanoid, moveSpeedMultiplier)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local baseWalkSpeed = humanoid:GetAttribute("ClassBaseWalkSpeed")
	if type(baseWalkSpeed) ~= "number" or baseWalkSpeed <= 0 then
		baseWalkSpeed = humanoid.WalkSpeed
		humanoid:SetAttribute("ClassBaseWalkSpeed", baseWalkSpeed)
	end

	local desiredWalkSpeed = math.max(1, baseWalkSpeed * moveSpeedMultiplier)
	if math.abs(desiredWalkSpeed - humanoid.WalkSpeed) < 0.01 then
		return
	end

	humanoid.WalkSpeed = desiredWalkSpeed
end

local function applyCharacterClassBonuses(player, character)
	local _, bonuses = getPlayerSelectedClassBonuses(player)
	if not bonuses then
		return
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		applyHumanoidClassBonus(humanoid, bonuses.maxHealthMultiplier)
		applyHumanoidMoveSpeedBonus(humanoid, bonuses.moveSpeedMultiplier)
	end
end

local function enforceContainerLoadout(player, container)
	if not container then
		return
	end

	local classDef = getPlayerClassDefinition(player)
	if not classDef then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			local weaponId = child:GetAttribute("WeaponId")
			if type(weaponId) ~= "string" or weaponId == "" then
				continue
			end

			local weaponDef = weaponById[weaponId]
			if weaponDef and not isWeaponAllowedForClass(classDef, weaponDef) then
				child:Destroy()
			end
		end
	end
end

local function enforcePlayerLoadout(player)
	enforceContainerLoadout(player, player:FindFirstChildOfClass("Backpack"))
	enforceContainerLoadout(player, player:FindFirstChild("StarterGear"))
	enforceContainerLoadout(player, player.Character)
end

local function buildPayloadForPlayer(player)
	local state = getOrCreatePlayerState(player)
	local classDef = getPlayerClassDefinition(player)
	if not classDef then
		return {
			success = false,
			message = "No classes configured.",
		}
	end

	local canSwitch, waveState = canSwitchClassNow()
	local currentProgress = getOrCreateClassProgress(state, classDef.Id)
	local currentBonuses = summarizeBonuses(getBonusesAtLevel(classDef, currentProgress.level))

	local classes = {}
	for _, listedClass in ipairs(classOrder) do
		local progress = getOrCreateClassProgress(state, listedClass.Id)
		local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, getMaxLevel())
		local xp = math.max(0, tonumber(progress.xp) or 0)
		local xpToNext = getXpRequiredForNextLevel(listedClass, level)
		local classBonuses = getBonusesAtLevel(listedClass, level)

		table.insert(classes, {
			id = listedClass.Id,
			name = listedClass.DisplayName,
			description = listedClass.Description,
			weaponTag = listedClass.WeaponTag,
			level = level,
			xp = xp,
			xpToNext = xpToNext,
			isCurrent = listedClass.Id == state.selectedClassId,
			currentBonuses = summarizeBonuses(classBonuses),
			perLevelBonuses = {
				damagePct = math.max(
					0,
					tonumber(listedClass.Bonuses.DamagePerLevel)
						or tonumber(listedClass.Bonuses.WeaponDamagePerLevel)
						or 0
				) * 100,
				maxHealthPct = math.max(0, tonumber(listedClass.Bonuses.MaxHealthPerLevel) or 0) * 100,
				moveSpeedPct = math.max(0, tonumber(listedClass.Bonuses.MoveSpeedPerLevel) or 0) * 100,
				meleeRangePct = math.max(0, tonumber(listedClass.Bonuses.MeleeRangePerLevel) or 0) * 100,
				damageReductionPct = math.max(0, tonumber(listedClass.Bonuses.DamageReductionPerLevel) or 0) * 100,
				shopDiscountPct = math.max(
					0,
					tonumber(listedClass.Bonuses.ShopDiscountPerLevel)
						or tonumber(listedClass.Bonuses.ShopCostReductionPerLevel)
						or 0
				) * 100,
				magazineSizePct = math.max(
					0,
					tonumber(listedClass.Bonuses.MagazineSizePerLevel)
						or tonumber(listedClass.Bonuses.MagSizePerLevel)
						or 0
				) * 100,
				reloadSpeedPct = math.max(
					0,
					tonumber(listedClass.Bonuses.ReloadSpeedPerLevel)
						or tonumber(listedClass.Bonuses.ReloadPerLevel)
						or 0
				) * 100,
				bulletSpreadReductionPct = math.max(
					0,
					tonumber(listedClass.Bonuses.BulletSpreadReductionPerLevel)
						or tonumber(listedClass.Bonuses.SpreadReductionPerLevel)
						or tonumber(listedClass.Bonuses.AccuracyPerLevel)
						or 0
				) * 100,
			},
		})
	end

	return {
		success = true,
		canSwitch = canSwitch,
		waveState = waveState,
		maxLevel = getMaxLevel(),
		currentClassId = classDef.Id,
		currentClassName = classDef.DisplayName,
		currentBonuses = currentBonuses,
		classes = classes,
	}
end

local function pushPlayerState(player, reason, force)
	if not classStateRemote or player.Parent ~= Players then
		return
	end

	local now = os.clock()
	if not force then
		local nextPushAt = pushThrottleByPlayer[player] or 0
		if now < nextPushAt then
			return
		end
	end
	pushThrottleByPlayer[player] = now + 0.2

	local payload = buildPayloadForPlayer(player)
	payload.reason = reason
	classStateRemote:FireClient(player, payload)
end

local function selectClass(player, classId)
	local classDef = getClassDefinition(classId)
	if not classDef then
		return {
			success = false,
			message = "Unknown class.",
		}
	end

	local canSwitch, waveState = canSwitchClassNow()
	if not canSwitch then
		return {
			success = false,
			message = string.format("Class switch is blocked while wave is active (%s).", waveState),
			waveState = waveState,
		}
	end

	local state = getOrCreatePlayerState(player)
	if state.selectedClassId == classDef.Id then
		return {
			success = true,
			message = string.format("%s is already selected.", classDef.DisplayName),
			state = buildPayloadForPlayer(player),
		}
	end

	state.selectedClassId = classDef.Id
	getOrCreateClassProgress(state, classDef.Id)

	if player.Character then
		applyCharacterClassBonuses(player, player.Character)
	end
	enforcePlayerLoadout(player)
	pushPlayerState(player, "ClassChanged", true)

	return {
		success = true,
		message = string.format("Selected class: %s", classDef.DisplayName),
		state = buildPayloadForPlayer(player),
	}
end

local function bindPlayer(player)
	getOrCreatePlayerState(player)

	if characterConnectionByPlayer[player] then
		characterConnectionByPlayer[player]:Disconnect()
		characterConnectionByPlayer[player] = nil
	end

	characterConnectionByPlayer[player] = player.CharacterAdded:Connect(function(character)
		task.defer(function()
			applyCharacterClassBonuses(player, character)
			enforcePlayerLoadout(player)
		end)
	end)

	if player.Character then
		task.defer(function()
			applyCharacterClassBonuses(player, player.Character)
			enforcePlayerLoadout(player)
		end)
	end

	pushPlayerState(player, "Init", true)
end

function ClassService.getPlayerClassId(player)
	local classDef = getPlayerClassDefinition(player)
	return classDef and classDef.Id or ""
end

function ClassService.getPlayerClassName(player)
	local classDef = getPlayerClassDefinition(player)
	return classDef and classDef.DisplayName or "Unknown"
end

function ClassService.canPlayerUseWeapon(player, weaponDef)
	if not player or not player:IsA("Player") then
		return false
	end
	if type(weaponDef) ~= "table" then
		return false
	end

	local classDef = getPlayerClassDefinition(player)
	return isWeaponAllowedForClass(classDef, weaponDef)
end

function ClassService.getWeaponDamageMultiplier(player, weaponDef)
	if not ClassService.canPlayerUseWeapon(player, weaponDef) then
		return 0
	end

	local _, bonuses = getPlayerSelectedClassBonuses(player)
	if not bonuses then
		return 0
	end

	return math.max(0, bonuses.damageMultiplier)
end

function ClassService.getIncomingDamageMultiplier(player)
	if not player or not player:IsA("Player") then
		return 1
	end

	local _, bonuses = getPlayerSelectedClassBonuses(player)
	if not bonuses then
		return 1
	end

	return math.max(0.05, bonuses.incomingDamageMultiplier)
end

function ClassService.getMeleeRangeMultiplier(player, weaponDef)
	if not player or not player:IsA("Player") then
		return 1
	end
	if weaponDef and type(weaponDef) == "table" and not ClassService.canPlayerUseWeapon(player, weaponDef) then
		return 1
	end

	local _, bonuses = getPlayerSelectedClassBonuses(player)
	if not bonuses then
		return 1
	end

	return math.max(0.1, bonuses.meleeRangeMultiplier)
end

local function getPlayerWeaponBonuses(player, weaponDef)
	if not player or not player:IsA("Player") then
		return nil
	end
	if type(weaponDef) ~= "table" then
		return nil
	end

	local classDef, bonuses = getPlayerSelectedClassBonuses(player)
	if not classDef or not isWeaponAllowedForClass(classDef, weaponDef) then
		return nil
	end

	return bonuses
end

function ClassService.getWeaponShopCost(player, weaponDef)
	local baseCost = math.max(0, math.floor((tonumber(weaponDef and weaponDef.Cost) or 0) + 0.5))
	if baseCost <= 0 then
		return 0
	end

	local bonuses = getPlayerWeaponBonuses(player, weaponDef)
	if not bonuses then
		return baseCost
	end

	local adjustedCost = math.floor((baseCost * math.max(0.1, bonuses.shopCostMultiplier or 1)) + 0.5)
	return math.max(1, adjustedCost)
end

function ClassService.getWeaponMagazineSize(player, weaponDef)
	local baseMagazineSize = tonumber(weaponDef and weaponDef.MagazineSize)
	if not baseMagazineSize then
		return nil
	end

	baseMagazineSize = math.floor(baseMagazineSize + 0.5)
	if baseMagazineSize <= 0 then
		return nil
	end

	local bonuses = getPlayerWeaponBonuses(player, weaponDef)
	if not bonuses then
		return baseMagazineSize
	end

	local adjustedMagazineSize = math.floor((baseMagazineSize * math.max(0.1, bonuses.magazineSizeMultiplier or 1)) + 0.5)
	return math.max(1, adjustedMagazineSize)
end

function ClassService.getWeaponReloadSeconds(player, weaponDef)
	local configuredReload = tonumber(weaponDef and weaponDef.ReloadSeconds)
	if not configuredReload then
		return nil
	end

	local reloadSeconds = math.max(0.2, configuredReload)
	local bonuses = getPlayerWeaponBonuses(player, weaponDef)
	if not bonuses then
		return reloadSeconds
	end

	return math.max(0.2, reloadSeconds * math.max(0.1, bonuses.reloadTimeMultiplier or 1))
end

function ClassService.getWeaponSpreadDegrees(player, weaponDef)
	local baseSpreadDegrees = tonumber(weaponDef and weaponDef.SpreadDegrees)
	if type(baseSpreadDegrees) ~= "number" then
		return nil
	end
	if baseSpreadDegrees <= 0 then
		return 0
	end

	local bonuses = getPlayerWeaponBonuses(player, weaponDef)
	if not bonuses then
		return baseSpreadDegrees
	end

	return math.max(0, baseSpreadDegrees * math.max(0.2, bonuses.bulletSpreadMultiplier or 1))
end

function ClassService.recordDamage(player, damage, weaponDef)
	if not player or not player:IsA("Player") then
		return
	end
	if weaponDef and not ClassService.canPlayerUseWeapon(player, weaponDef) then
		return
	end

	local xpGain = math.max(0, tonumber(damage) or 0)
	if xpGain <= 0 then
		return
	end

	xpGain *= math.max(0, tonumber(getClassSystemConfig().DamageToXpScale) or 1)
	if xpGain <= 0 then
		return
	end

	local classDef, progress = getPlayerSelectedClassProgress(player)
	if not classDef or not progress then
		return
	end

	local maxLevel = getMaxLevel()
	local leveledUp = false

	while xpGain > 0 and progress.level < maxLevel do
		local xpToNext = getXpRequiredForNextLevel(classDef, progress.level)
		if not xpToNext then
			break
		end

		local missingXp = math.max(0, xpToNext - progress.xp)
		if xpGain >= missingXp then
			xpGain -= missingXp
			progress.level += 1
			progress.xp = 0
			leveledUp = true
		else
			progress.xp += xpGain
			xpGain = 0
		end
	end

	if progress.level >= maxLevel then
		progress.level = maxLevel
		progress.xp = 0
	end

	if leveledUp and player.Character then
		applyCharacterClassBonuses(player, player.Character)
	end

	pushPlayerState(player, leveledUp and "LevelUp" or "XpGained", leveledUp)
end

function ClassService.enforcePlayerLoadout(player)
	if not player or not player:IsA("Player") then
		return
	end

	enforcePlayerLoadout(player)
end

function ClassService.start()
	if started then
		return
	end
	started = true

	buildClassRegistry()
	buildWeaponRegistry()

	if #classOrder == 0 then
		warn("ClassService could not start: no classes configured in Config.ClassSystem.Classes")
		return
	end

	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = Config.Remotes.Folder
		remotesFolder.Parent = ReplicatedStorage
	end

	classGetDataFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ClassGetData)
	classSelectFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ClassSelect)
	classStateRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.ClassState)

	classGetDataFunction.OnServerInvoke = function(player)
		return buildPayloadForPlayer(player)
	end

	classSelectFunction.OnServerInvoke = function(player, classId)
		if type(classId) ~= "string" then
			return {
				success = false,
				message = "Invalid class selection.",
			}
		end

		return selectClass(player, classId)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerStateByPlayer[player] = nil
		pushThrottleByPlayer[player] = nil

		if characterConnectionByPlayer[player] then
			characterConnectionByPlayer[player]:Disconnect()
			characterConnectionByPlayer[player] = nil
		end
	end)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return ClassService
