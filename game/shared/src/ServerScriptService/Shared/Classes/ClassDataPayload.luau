--[[
	Shared ClassDataPayload — Builds class list + current selection payload from PlayerData.
	Used by Lobby to serve ClassGetData/ClassSelect (same payload shape as Match ClassState).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassProgression = require(script.Parent.ClassProgression)
local ClassStateHelpers = require(script.Parent.ClassStateHelpers)
local ClassPayloadBuilder = require(script.Parent.ClassPayloadBuilder)
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

	ClassStateHelpers.warnDuplicateClassIds("ClassDataPayload", duplicateClassIds)
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

	PlayerDataService.set(player, { "classes" }, ClassStateHelpers.copyStateForPersistence(state), true)
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
	local maxLevel = getMaxLevel()

	return ClassPayloadBuilder.buildPayload({
		state = state,
		classDef = classDef,
		classOrder = classOrder,
		canSwitch = true,
		waveState = "Lobby",
		maxLevel = maxLevel,
		dependencies = {
			getOrCreateClassProgress = getOrCreateClassProgress,
			getBonusesAtLevel = ClassProgression.getBonusesAtLevel,
			getXpRequiredForNextLevel = getXpRequiredForNextLevel,
			buildPerLevelBonusesFromConfig = ClassProgression.buildPerLevelBonusesFromConfig,
			buildCurrentBonusesWithFallback = ClassProgression.buildCurrentBonusesWithFallback,
		},
	})
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
