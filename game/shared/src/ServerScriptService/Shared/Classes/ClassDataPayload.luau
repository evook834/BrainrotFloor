--[[
	Shared ClassDataPayload — Builds class list + current selection payload from PlayerData.
	Used by Lobby to serve ClassGetData/ClassSelect (same payload shape as Match ClassState).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassProgression = require(script.Parent.ClassProgression)
local ClassStateHelpers = require(script.Parent.ClassStateHelpers)
local PlayerDataService = require(script.Parent.Parent.PlayerData.PlayerDataService)

local classById = {}
local classOrder = {}

local normalizeToken = ClassStateHelpers.normalizeToken

local function getClassSystemConfig()
	return Config.ClassSystem or {}
end

local function getMaxLevel()
	return ClassProgression.getMaxLevel(getClassSystemConfig())
end

local function getXpRequiredForNextLevel(classDef, level)
	return ClassProgression.getXpRequiredForNextLevel(getClassSystemConfig(), classDef, level)
end

local function getDefaultClassId()
	return ClassStateHelpers.getDefaultClassId(getClassSystemConfig(), classById, classOrder)
end

local function buildClassRegistry()
	table.clear(classById)
	table.clear(classOrder)

	local builtClassById, builtClassOrder, duplicateClassIds =
		ClassStateHelpers.buildClassRegistry(getClassSystemConfig())
	for classId, classDef in pairs(builtClassById) do
		classById[classId] = classDef
	end
	for _, classDef in ipairs(builtClassOrder) do
		table.insert(classOrder, classDef)
	end

	local duplicateIds = {}
	for classId in pairs(duplicateClassIds) do
		table.insert(duplicateIds, classId)
	end
	table.sort(duplicateIds)
	for _, classId in ipairs(duplicateIds) do
		warn(string.format("ClassDataPayload found duplicate class id '%s'; using the last definition.", classId))
	end
end

local function getClassDefinition(classId)
	return classById[normalizeToken(classId)]
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
	if type(persistedState) == "table" and (persistedState.selectedClassId or persistedState.progressByClassId) then
		ClassStateHelpers.applyPersistedStateToPlayerState(state, persistedState, {
			classById = classById,
			defaultClassId = getDefaultClassId(),
			maxLevel = getMaxLevel(),
			getXpRequiredForNextLevel = getXpRequiredForNextLevel,
		})
	else
		state.selectedClassId = getDefaultClassId()
		if state.selectedClassId ~= "" then
			state.progressByClassId[state.selectedClassId] = { level = 1, xp = 0 }
		end
	end

	return state
end

local function getOrCreateClassProgress(state, classId)
	return ClassStateHelpers.getOrCreateClassProgress(state, classId)
end

local function writeStateToPlayerData(player, state)
	if not PlayerDataService.isReady() or not state then
		return
	end

	PlayerDataService.set(player, { "classes" }, ClassStateHelpers.copyStateForPersistence(state))
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
	local maxLevel = getMaxLevel()
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
		local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, maxLevel)
		local xp = math.max(0, tonumber(progress.xp) or 0)
		local xpToNext = getXpRequiredForNextLevel(listedClass, level)
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
		maxLevel = maxLevel,
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
