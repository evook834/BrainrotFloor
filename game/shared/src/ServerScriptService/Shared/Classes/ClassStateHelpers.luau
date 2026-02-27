--[[
	Shared ClassStateHelpers — class-token, registry, and state-copy helpers.
	Used by Match ClassService and Lobby ClassDataPayload to keep behavior aligned.
]]

local ClassStateHelpers = {}

function ClassStateHelpers.normalizeToken(value)
	if type(value) ~= "string" then
		return ""
	end

	return string.lower((string.gsub(value, "[^%w]", "")))
end

function ClassStateHelpers.buildClassRegistry(rawClassSystemConfig)
	local classSystemConfig = rawClassSystemConfig or {}
	local classById = {}
	local classOrder = {}
	local duplicateClassIds = {}

	for _, rawClass in ipairs(classSystemConfig.Classes or {}) do
		if type(rawClass) == "table" then
			local id = ClassStateHelpers.normalizeToken(rawClass.Id)
			if id ~= "" then
				if classById[id] then
					duplicateClassIds[id] = true
				end

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

	return classById, classOrder, duplicateClassIds
end

function ClassStateHelpers.warnDuplicateClassIds(scope, duplicateClassIds)
	local duplicateIds = {}
	for classId in pairs(duplicateClassIds or {}) do
		table.insert(duplicateIds, classId)
	end
	table.sort(duplicateIds)

	for _, classId in ipairs(duplicateIds) do
		warn(string.format("%s found duplicate class id '%s'; using the last definition.", tostring(scope), classId))
	end
end

function ClassStateHelpers.getDefaultClassId(rawClassSystemConfig, classById, classOrder)
	local classSystemConfig = rawClassSystemConfig or {}
	local configured = ClassStateHelpers.normalizeToken(classSystemConfig.DefaultClassId)
	if configured ~= "" and classById[configured] then
		return configured
	end

	local firstClass = classOrder[1]
	if firstClass then
		return firstClass.Id
	end

	return ""
end

function ClassStateHelpers.getOrCreateClassProgress(state, classId)
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

function ClassStateHelpers.sanitizeLoadedProgress(rawProgress, classDef, maxLevel, getXpRequiredForNextLevel)
	if type(rawProgress) ~= "table" or not classDef then
		return nil
	end

	local level = math.clamp(math.floor(tonumber(rawProgress.level) or 1), 1, math.max(1, tonumber(maxLevel) or 1))
	local xp = math.max(0, tonumber(rawProgress.xp) or 0)
	local xpToNext = getXpRequiredForNextLevel(classDef, level)
	if xpToNext then
		xp = math.min(xp, math.max(0, xpToNext - 1))
	else
		level = math.max(1, tonumber(maxLevel) or 1)
		xp = 0
	end

	return {
		level = level,
		xp = xp,
	}
end

function ClassStateHelpers.applyPersistedStateToPlayerState(state, persistedState, options)
	local resolvedOptions = options or {}
	local classById = resolvedOptions.classById or {}
	local defaultClassId = resolvedOptions.defaultClassId or ""
	local maxLevel = math.max(1, tonumber(resolvedOptions.maxLevel) or 1)
	local getXpRequiredForNextLevel = resolvedOptions.getXpRequiredForNextLevel

	local selectedClassId = ClassStateHelpers.normalizeToken(persistedState and persistedState.selectedClassId)
	if selectedClassId == "" or not classById[selectedClassId] then
		selectedClassId = defaultClassId
	end

	state.selectedClassId = selectedClassId
	table.clear(state.progressByClassId)

	if type(persistedState) == "table" and type(persistedState.progressByClassId) == "table" then
		for classId, rawProgress in pairs(persistedState.progressByClassId) do
			local normalizedClassId = ClassStateHelpers.normalizeToken(classId)
			local classDef = classById[normalizedClassId]
			if classDef and type(getXpRequiredForNextLevel) == "function" then
				local sanitizedProgress = ClassStateHelpers.sanitizeLoadedProgress(
					rawProgress,
					classDef,
					maxLevel,
					getXpRequiredForNextLevel
				)
				if sanitizedProgress then
					state.progressByClassId[normalizedClassId] = sanitizedProgress
				end
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

function ClassStateHelpers.copyStateForPersistence(state)
	local copy = {
		selectedClassId = state and state.selectedClassId or "",
		progressByClassId = {},
	}

	for classId, progress in pairs((state and state.progressByClassId) or {}) do
		copy.progressByClassId[classId] = {
			level = math.floor(tonumber(progress.level) or 1),
			xp = math.max(0, tonumber(progress.xp) or 0),
		}
	end

	return copy
end

return ClassStateHelpers
