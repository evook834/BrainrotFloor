local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local ClassService = {}

local CLASS_SELECTION_DATASTORE_NAME = "BrainrotFloor_ClassSelection_v1"
local CLASS_SELECTION_SCHEMA_VERSION = 1
local CLASS_PROGRESS_AUTOSAVE_SECONDS = 30

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
local classSelectionStore = nil
local classSelectionStoreUnavailable = false
local persistedStateSignatureByUserId = {}
local dirtyStateByUserId = {}

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

local getDefaultClassId

local function getClassSelectionStore()
	if classSelectionStore then
		return classSelectionStore
	end
	if classSelectionStoreUnavailable then
		return nil
	end

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(CLASS_SELECTION_DATASTORE_NAME)
	end)
	if not ok or not store then
		classSelectionStoreUnavailable = true
		warn(string.format("ClassService could not get class selection DataStore: %s", tostring(store)))
		return nil
	end

	classSelectionStore = store
	return classSelectionStore
end

local function getClassSelectionStoreKey(userId)
	return string.format("u:%d", math.max(0, math.floor(tonumber(userId) or 0)))
end

local function buildPersistableStateData(state)
	local maxLevel = getMaxLevel()
	local selectedClassId = normalizeToken(state and state.selectedClassId)
	if selectedClassId == "" or not classById[selectedClassId] then
		selectedClassId = getDefaultClassId()
	end

	local progressByClassId = {}
	if type(state) == "table" and type(state.progressByClassId) == "table" then
		for classId, rawProgress in pairs(state.progressByClassId) do
			local normalizedClassId = normalizeToken(classId)
			if normalizedClassId ~= "" and classById[normalizedClassId] and type(rawProgress) == "table" then
				local level = math.clamp(math.floor(tonumber(rawProgress.level) or 1), 1, maxLevel)
				local xp = math.max(0, tonumber(rawProgress.xp) or 0)
				if level >= maxLevel then
					xp = 0
				end
				progressByClassId[normalizedClassId] = {
					level = level,
					xp = xp,
				}
			end
		end
	end

	if selectedClassId ~= "" and not progressByClassId[selectedClassId] then
		progressByClassId[selectedClassId] = {
			level = 1,
			xp = 0,
		}
	end

	return {
		schemaVersion = CLASS_SELECTION_SCHEMA_VERSION,
		selectedClassId = selectedClassId,
		progressByClassId = progressByClassId,
	}
end

local function buildStateSignature(stateData)
	local parts = { tostring(stateData.selectedClassId or "") }
	local classIds = {}
	for classId in pairs(stateData.progressByClassId or {}) do
		table.insert(classIds, classId)
	end
	table.sort(classIds)

	for _, classId in ipairs(classIds) do
		local progress = stateData.progressByClassId[classId] or {}
		local level = math.floor(tonumber(progress.level) or 1)
		local xpMillis = math.max(0, math.floor(((tonumber(progress.xp) or 0) * 1000) + 0.5))
		table.insert(parts, string.format("%s:%d:%d", classId, level, xpMillis))
	end

	return table.concat(parts, "|")
end

local function loadPersistedState(userId)
	local store = getClassSelectionStore()
	if not store then
		return nil
	end

	local key = getClassSelectionStoreKey(userId)
	local ok, value = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn(string.format("ClassService failed to load class state for userId %s: %s", tostring(userId), tostring(value)))
		return nil
	end

	local loadedState = {
		selectedClassId = getDefaultClassId(),
		progressByClassId = {},
	}

	if type(value) == "string" then
		loadedState.selectedClassId = value
	elseif type(value) == "table" then
		loadedState.selectedClassId = value.selectedClassId or value.classId or loadedState.selectedClassId

		local progressByClassId = value.progressByClassId
		if type(progressByClassId) ~= "table" then
			progressByClassId = value.progress
		end

		if type(progressByClassId) == "table" then
			for classId, rawProgress in pairs(progressByClassId) do
				local normalizedClassId = normalizeToken(classId)
				if normalizedClassId ~= "" and classById[normalizedClassId] and type(rawProgress) == "table" then
					loadedState.progressByClassId[normalizedClassId] = {
						level = tonumber(rawProgress.level) or 1,
						xp = tonumber(rawProgress.xp) or 0,
					}
				end
			end
		end
	else
		return nil
	end

	local normalizedSelectedClassId = normalizeToken(loadedState.selectedClassId)
	if normalizedSelectedClassId == "" or not classById[normalizedSelectedClassId] then
		normalizedSelectedClassId = getDefaultClassId()
	end
	loadedState.selectedClassId = normalizedSelectedClassId
	if loadedState.selectedClassId == "" then
		return nil
	end

	return loadedState
end

local function markPersistedStateDirty(userId)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end

	dirtyStateByUserId[userId] = true
end

local function savePersistedState(userId, state, force)
	if type(userId) ~= "number" or userId <= 0 then
		return false
	end

	local stateData = buildPersistableStateData(state)
	if stateData.selectedClassId == "" then
		return false
	end

	local signature = buildStateSignature(stateData)
	if persistedStateSignatureByUserId[userId] == signature and (not force or dirtyStateByUserId[userId] ~= true) then
		dirtyStateByUserId[userId] = nil
		return true
	end

	local store = getClassSelectionStore()
	if not store then
		return false
	end

	local key = getClassSelectionStoreKey(userId)
	local ok, errOrResult = pcall(function()
		store:SetAsync(key, stateData)
	end)
	if not ok then
		warn(
			string.format(
				"ClassService failed to save class state for userId %s (class %s): %s",
				tostring(userId),
				stateData.selectedClassId,
				tostring(errOrResult)
			)
		)
		return false
	end

	persistedStateSignatureByUserId[userId] = signature
	dirtyStateByUserId[userId] = nil
	return true
end

getDefaultClassId = function()
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

local function sanitizeLoadedProgress(classId, rawProgress)
	if type(rawProgress) ~= "table" then
		return nil
	end

	local classDef = classById[classId]
	if not classDef then
		return nil
	end

	local maxLevel = getMaxLevel()
	local level = math.clamp(math.floor(tonumber(rawProgress.level) or 1), 1, maxLevel)
	local xp = math.max(0, tonumber(rawProgress.xp) or 0)
	local xpToNext = getXpRequiredForNextLevel(classDef, level)
	if xpToNext then
		xp = math.min(xp, math.max(0, xpToNext - 1))
	else
		level = maxLevel
		xp = 0
	end

	return {
		level = level,
		xp = xp,
	}
end

local function applyPersistedStateToPlayerState(state, persistedState)
	local selectedClassId = normalizeToken(persistedState and persistedState.selectedClassId)
	if selectedClassId == "" or not classById[selectedClassId] then
		selectedClassId = getDefaultClassId()
	end

	state.selectedClassId = selectedClassId
	table.clear(state.progressByClassId)

	if type(persistedState) == "table" and type(persistedState.progressByClassId) == "table" then
		for classId, rawProgress in pairs(persistedState.progressByClassId) do
			local normalizedClassId = normalizeToken(classId)
			local sanitizedProgress = sanitizeLoadedProgress(normalizedClassId, rawProgress)
			if sanitizedProgress then
				state.progressByClassId[normalizedClassId] = sanitizedProgress
			end
		end
	end

	if selectedClassId ~= "" and not state.progressByClassId[selectedClassId] then
		state.progressByClassId[selectedClassId] = {
			level = 1,
			xp = 0,
		}
	end
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
	local bulletRangeMultiplier = 1
		+ (
			math.max(
				0,
				tonumber(bonuses.BulletRangePerLevel)
					or tonumber(bonuses.WeaponRangePerLevel)
					or tonumber(bonuses.RangePerLevel)
					or 0
			) * bonusLevels
		)
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
		bulletRangeMultiplier = math.max(0.1, bulletRangeMultiplier),
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
		bulletRangeMultiplier = bonuses.bulletRangeMultiplier,
		bulletSpreadMultiplier = bonuses.bulletSpreadMultiplier,
		damagePct = (bonuses.damageMultiplier - 1) * 100,
		maxHealthPct = (bonuses.maxHealthMultiplier - 1) * 100,
		moveSpeedPct = (bonuses.moveSpeedMultiplier - 1) * 100,
		meleeRangePct = (bonuses.meleeRangeMultiplier - 1) * 100,
		damageReductionPct = (1 - bonuses.incomingDamageMultiplier) * 100,
		shopDiscountPct = bonuses.shopDiscount * 100,
		magazineSizePct = (bonuses.magazineSizeMultiplier - 1) * 100,
		reloadSpeedPct = (reloadSpeedMultiplier - 1) * 100,
		bulletRangePct = (bonuses.bulletRangeMultiplier - 1) * 100,
		bulletSpreadReductionPct = (1 - bonuses.bulletSpreadMultiplier) * 100,
	}
end

local bonusPctKeyAliases = {
	Damage = "damagePct",
	WeaponDamage = "damagePct",
	MaxHealth = "maxHealthPct",
	MoveSpeed = "moveSpeedPct",
	MeleeRange = "meleeRangePct",
	DamageReduction = "damageReductionPct",
	ShopDiscount = "shopDiscountPct",
	ShopCostReduction = "shopDiscountPct",
	MagazineSize = "magazineSizePct",
	MagSize = "magazineSizePct",
	ReloadSpeed = "reloadSpeedPct",
	Reload = "reloadSpeedPct",
	BulletRange = "bulletRangePct",
	WeaponRange = "bulletRangePct",
	Range = "bulletRangePct",
	BulletSpreadReduction = "bulletSpreadReductionPct",
	SpreadReduction = "bulletSpreadReductionPct",
	Accuracy = "bulletSpreadReductionPct",
}

local function resolveBonusPctKeyFromPerLevel(rawBonusKey)
	if type(rawBonusKey) ~= "string" then
		return nil
	end

	local stem = string.match(rawBonusKey, "^(.+)PerLevel$")
	if not stem or stem == "" then
		return nil
	end

	local alias = bonusPctKeyAliases[stem]
	if alias then
		return alias
	end

	return string.lower(string.sub(stem, 1, 1)) .. string.sub(stem, 2) .. "Pct"
end

local function buildPerLevelBonusesFromConfig(rawBonusConfig)
	local perLevelBonuses = {}
	if type(rawBonusConfig) ~= "table" then
		return perLevelBonuses
	end

	for rawBonusKey, rawPerLevelValue in pairs(rawBonusConfig) do
		local pctKey = resolveBonusPctKeyFromPerLevel(rawBonusKey)
		local perLevelValue = tonumber(rawPerLevelValue)
		if pctKey and perLevelValue then
			local pctValue = perLevelValue * 100
			local existing = perLevelBonuses[pctKey]
			if type(existing) ~= "number" or math.abs(pctValue) > math.abs(existing) then
				perLevelBonuses[pctKey] = pctValue
			end
		end
	end

	return perLevelBonuses
end

local function buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)
	local currentBonuses = summarizeBonuses(classBonuses)
	local bonusLevels = math.max(0, math.floor(tonumber(level) or 1) - 1)

	for pctKey, perLevelValue in pairs(perLevelBonuses) do
		if currentBonuses[pctKey] == nil then
			currentBonuses[pctKey] = (tonumber(perLevelValue) or 0) * bonusLevels
		end
	end

	return currentBonuses
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

local function getOutOfWaveMoveSpeedMultiplier()
	local configuredMultiplier = tonumber((Config.Player and Config.Player.OutOfWaveMoveSpeedMultiplier) or 1)
	if not configuredMultiplier then
		return 1
	end

	return math.max(0, configuredMultiplier)
end

local function getWaveMoveSpeedMultiplier()
	local waveState = resolveWaveState()
	if waveState == "InProgress" or waveState == "Blocked" then
		return 1
	end

	return getOutOfWaveMoveSpeedMultiplier()
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

	local desiredWalkSpeed = math.max(1, baseWalkSpeed * moveSpeedMultiplier * getWaveMoveSpeedMultiplier())
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

local function refreshAllCharacterClassBonuses()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			applyCharacterClassBonuses(player, character)
		end
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
	local selectedClassBonuses = getBonusesAtLevel(classDef, currentProgress.level)
	local selectedPerLevelBonuses = buildPerLevelBonusesFromConfig(classDef.Bonuses)
	local currentBonuses = buildCurrentBonusesWithFallback(
		selectedClassBonuses,
		selectedPerLevelBonuses,
		currentProgress.level
	)

	local classes = {}
	for _, listedClass in ipairs(classOrder) do
		local progress = getOrCreateClassProgress(state, listedClass.Id)
		local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, getMaxLevel())
		local xp = math.max(0, tonumber(progress.xp) or 0)
		local xpToNext = getXpRequiredForNextLevel(listedClass, level)
		local classBonuses = getBonusesAtLevel(listedClass, level)
		local perLevelBonuses = buildPerLevelBonusesFromConfig(listedClass.Bonuses)
		local classCurrentBonuses = buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)

		table.insert(classes, {
			id = listedClass.Id,
			name = listedClass.DisplayName,
			description = listedClass.Description,
			weaponTag = listedClass.WeaponTag,
			level = level,
			xp = xp,
			xpToNext = xpToNext,
			isCurrent = listedClass.Id == state.selectedClassId,
			currentBonuses = classCurrentBonuses,
			perLevelBonuses = perLevelBonuses,
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
	markPersistedStateDirty(player.UserId)
	savePersistedState(player.UserId, state, true)

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
	local state = getOrCreatePlayerState(player)
	local userId = player.UserId

	local persistedState = loadPersistedState(userId)
	if persistedState then
		applyPersistedStateToPlayerState(state, persistedState)
	else
		state.selectedClassId = getDefaultClassId()
		getOrCreateClassProgress(state, state.selectedClassId)
	end
	persistedStateSignatureByUserId[userId] = buildStateSignature(buildPersistableStateData(state))
	dirtyStateByUserId[userId] = nil

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

local function savePlayerStateForPlayer(player, force)
	if not player or not player:IsA("Player") then
		return false
	end

	local state = playerStateByPlayer[player]
	if not state then
		return false
	end

	local userId = player.UserId
	if not force and dirtyStateByUserId[userId] ~= true then
		return true
	end

	return savePersistedState(userId, state, force)
end

local function autosaveDirtyPlayerStates()
	for _, player in Players:GetPlayers() do
		savePlayerStateForPlayer(player, false)
	end
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

function ClassService.getWeaponBulletRangeMultiplier(player, weaponDef)
	local bonuses = getPlayerWeaponBonuses(player, weaponDef)
	if not bonuses then
		return 1
	end

	return math.max(0.1, bonuses.bulletRangeMultiplier or 1)
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

	local previousLevel = progress.level
	local previousXp = progress.xp
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
	if progress.level ~= previousLevel or progress.xp ~= previousXp then
		markPersistedStateDirty(player.UserId)
	end
	if leveledUp then
		local state = playerStateByPlayer[player]
		if state then
			savePersistedState(player.UserId, state, true)
		end
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

	remotesFolder:GetAttributeChangedSignal("CurrentWaveState"):Connect(function()
		refreshAllCharacterClassBonuses()
	end)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayerStateForPlayer(player, true)

		playerStateByPlayer[player] = nil
		pushThrottleByPlayer[player] = nil
		persistedStateSignatureByUserId[player.UserId] = nil
		dirtyStateByUserId[player.UserId] = nil

		if characterConnectionByPlayer[player] then
			characterConnectionByPlayer[player]:Disconnect()
			characterConnectionByPlayer[player] = nil
		end
	end)

	task.spawn(function()
		while started do
			task.wait(CLASS_PROGRESS_AUTOSAVE_SECONDS)
			autosaveDirtyPlayerStates()
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			savePlayerStateForPlayer(player, true)
		end
	end)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return ClassService
