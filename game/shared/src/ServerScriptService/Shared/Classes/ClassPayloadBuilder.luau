--[[
	Shared ClassPayloadBuilder — single source for class state payload shape.
	Used by Match ClassStateSync and Lobby ClassDataPayload.
]]

local ClassPayloadBuilder = {}

local function buildClassPayloadEntry(state, listedClass, maxLevel, dependencies)
	local getOrCreateClassProgress = dependencies.getOrCreateClassProgress
	local getBonusesAtLevel = dependencies.getBonusesAtLevel
	local getXpRequiredForNextLevel = dependencies.getXpRequiredForNextLevel
	local buildPerLevelBonusesFromConfig = dependencies.buildPerLevelBonusesFromConfig
	local buildCurrentBonusesWithFallback = dependencies.buildCurrentBonusesWithFallback

	local progress = getOrCreateClassProgress(state, listedClass.Id)
	local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, maxLevel)
	local xp = math.max(0, tonumber(progress.xp) or 0)
	local xpToNext = getXpRequiredForNextLevel(listedClass, level)
	local classBonuses = getBonusesAtLevel(listedClass, level)
	local perLevelBonuses = buildPerLevelBonusesFromConfig(listedClass.Bonuses)
	local classCurrentBonuses = buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)

	return {
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
	}
end

function ClassPayloadBuilder.buildPayload(options)
	local payloadOptions = options or {}
	local state = payloadOptions.state
	local classDef = payloadOptions.classDef
	local classOrder = payloadOptions.classOrder or {}
	local canSwitch = payloadOptions.canSwitch
	local waveState = payloadOptions.waveState
	local maxLevel = math.max(1, math.floor(tonumber(payloadOptions.maxLevel) or 1))
	local dependencies = payloadOptions.dependencies or {}

	local getOrCreateClassProgress = dependencies.getOrCreateClassProgress
	local getBonusesAtLevel = dependencies.getBonusesAtLevel
	local getXpRequiredForNextLevel = dependencies.getXpRequiredForNextLevel
	local buildPerLevelBonusesFromConfig = dependencies.buildPerLevelBonusesFromConfig
	local buildCurrentBonusesWithFallback = dependencies.buildCurrentBonusesWithFallback

	if type(state) ~= "table" or type(classDef) ~= "table" then
		return {
			success = false,
			message = "No classes configured.",
		}
	end

	if type(getOrCreateClassProgress) ~= "function"
		or type(getBonusesAtLevel) ~= "function"
		or type(getXpRequiredForNextLevel) ~= "function"
		or type(buildPerLevelBonusesFromConfig) ~= "function"
		or type(buildCurrentBonusesWithFallback) ~= "function"
	then
		return {
			success = false,
			message = "Class payload dependencies are unavailable.",
		}
	end

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
		table.insert(classes, buildClassPayloadEntry(state, listedClass, maxLevel, dependencies))
	end

	return {
		success = true,
		canSwitch = canSwitch == true,
		waveState = tostring(waveState or "Unknown"),
		maxLevel = maxLevel,
		currentClassId = classDef.Id,
		currentClassName = classDef.DisplayName,
		currentBonuses = currentBonuses,
		classes = classes,
	}
end

return ClassPayloadBuilder
