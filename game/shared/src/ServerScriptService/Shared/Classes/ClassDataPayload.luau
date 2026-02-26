--[[
	Shared ClassDataPayload — Builds class list + current selection payload from PlayerData.
	Used by Lobby to serve ClassGetData/ClassSelect (same payload shape as Match ClassState).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassProgression = require(script.Parent.ClassProgression)
local PlayerDataService = require(script.Parent.Parent.PlayerData.PlayerDataService)

local classById = {}
local classOrder = {}

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
	return ClassProgression.getMaxLevel(getClassSystemConfig())
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

local function getClassDefinition(classId)
	return classById[normalizeToken(classId)]
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
	local xpToNext = ClassProgression.getXpRequiredForNextLevel(getClassSystemConfig(), classDef, level)
	if xpToNext then
		xp = math.min(xp, math.max(0, xpToNext - 1))
	else
		level = maxLevel
		xp = 0
	end
	return { level = level, xp = xp }
end

-- Returns { selectedClassId, progressByClassId } from PlayerData (with defaults).
local function getPlayerState(player)
	local state = {
		selectedClassId = "",
		progressByClassId = {},
	}
	if not PlayerDataService.isReady() then
		state.selectedClassId = getDefaultClassId()
		if state.selectedClassId ~= "" then
			state.progressByClassId[state.selectedClassId] = { level = 1, xp = 0 }
		end
		return state
	end
	PlayerDataService.waitForData(player)
	local persistedState = PlayerDataService.get(player, { "classes" })
	local selectedClassId = normalizeToken(persistedState and persistedState.selectedClassId)
	if selectedClassId == "" or not classById[selectedClassId] then
		selectedClassId = getDefaultClassId()
	end
	state.selectedClassId = selectedClassId
	if type(persistedState) == "table" and type(persistedState.progressByClassId) == "table" then
		for classId, rawProgress in pairs(persistedState.progressByClassId) do
			local normalizedClassId = normalizeToken(classId)
			local sanitizedProgress = sanitizeLoadedProgress(normalizedClassId, rawProgress)
			if sanitizedProgress then
				state.progressByClassId[normalizedClassId] = sanitizedProgress
			end
		end
	end
	if state.selectedClassId ~= "" and not state.progressByClassId[state.selectedClassId] then
		state.progressByClassId[state.selectedClassId] = { level = 1, xp = 0 }
	end
	return state
end

local function getOrCreateClassProgress(state, classId)
	local progress = state.progressByClassId[classId]
	if progress then
		return progress
	end
	state.progressByClassId[classId] = { level = 1, xp = 0 }
	return state.progressByClassId[classId]
end

local function writeStateToPlayerData(player, state)
	if not PlayerDataService.isReady() or not state then
		return
	end
	local copy = {
		selectedClassId = state.selectedClassId or "",
		progressByClassId = {},
	}
	for classId, progress in pairs(state.progressByClassId or {}) do
		copy.progressByClassId[classId] = {
			level = math.floor(tonumber(progress.level) or 1),
			xp = math.max(0, tonumber(progress.xp) or 0),
		}
	end
	PlayerDataService.set(player, { "classes" }, copy)
end

function buildPayloadForPlayer(player)
	if #classOrder == 0 then
		return {
			success = false,
			message = "No classes configured.",
		}
	end
	local state = getPlayerState(player)
	local classDef = getClassDefinition(state.selectedClassId)
	if not classDef then
		return {
			success = false,
			message = "No classes configured.",
		}
	end
	local currentProgress = getOrCreateClassProgress(state, classDef.Id)
	local selectedClassBonuses = ClassProgression.getBonusesAtLevel(classDef, currentProgress.level)
	local selectedPerLevelBonuses = ClassProgression.buildPerLevelBonusesFromConfig(classDef.Bonuses)
	local currentBonuses = ClassProgression.buildCurrentBonusesWithFallback(
		selectedClassBonuses,
		selectedPerLevelBonuses,
		currentProgress.level
	)
	local classes = {}
	for _, listedClass in ipairs(classOrder) do
		local progress = getOrCreateClassProgress(state, listedClass.Id)
		local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, getMaxLevel())
		local xp = math.max(0, tonumber(progress.xp) or 0)
		local xpToNext = ClassProgression.getXpRequiredForNextLevel(getClassSystemConfig(), listedClass, level)
		local classBonuses = ClassProgression.getBonusesAtLevel(listedClass, level)
		local perLevelBonuses = ClassProgression.buildPerLevelBonusesFromConfig(listedClass.Bonuses)
		local classCurrentBonuses = ClassProgression.buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)
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
		canSwitch = true,
		waveState = "Lobby",
		maxLevel = getMaxLevel(),
		currentClassId = classDef.Id,
		currentClassName = classDef.DisplayName,
		currentBonuses = currentBonuses,
		classes = classes,
	}
end

function selectClass(player, classId)
	if type(classId) ~= "string" then
		return { success = false, message = "Invalid class selection." }
	end
	local classDef = getClassDefinition(classId)
	if not classDef then
		return { success = false, message = "Unknown class." }
	end
	local state = getPlayerState(player)
	if state.selectedClassId == classDef.Id then
		return {
			success = true,
			message = string.format("%s is already selected.", classDef.DisplayName),
			state = buildPayloadForPlayer(player),
		}
	end
	state.selectedClassId = classDef.Id
	getOrCreateClassProgress(state, classDef.Id)
	writeStateToPlayerData(player, state)
	return {
		success = true,
		message = string.format("Selected class: %s", classDef.DisplayName),
		state = buildPayloadForPlayer(player),
	}
end

-- Call once when using this module (e.g. when Lobby starts) so class registry is built.
function init()
	buildClassRegistry()
end

return {
	buildPayloadForPlayer = buildPayloadForPlayer,
	selectClass = selectClass,
	init = init,
}
