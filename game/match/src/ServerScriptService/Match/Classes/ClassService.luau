local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassCombatRules = require(script.Parent.ClassCombatRules)
local ClassPersistence = require(script.Parent.ClassPersistence)
local ClassProgression = require(script.Parent.ClassProgression)
local ClassRuntimeEffects = require(script.Parent.ClassRuntimeEffects)
local ClassStateSync = require(script.Parent.ClassStateSync)

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
local characterConnectionByPlayer = {}
local classPersistence = nil
local classCombatRules = nil
local classRuntimeEffects = nil
local classStateSync = nil
local classChangedCallbacks = {}

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
	return ClassProgression.getMaxLevel(getClassSystemConfig())
end

local function getClassDefinition(classId)
	return classById[normalizeToken(classId)]
end

local getDefaultClassId

local function loadPersistedState(userId)
	return classPersistence.loadPersistedState(userId)
end

local function markPersistedStateDirty(userId)
	classPersistence.markDirty(userId)
end

local function savePersistedState(userId, state, force)
	return classPersistence.savePersistedState(userId, state, force)
end

local function isPersistedStateDirty(userId)
	return classPersistence.isDirty(userId)
end

local function resetPersistedStateTracking(userId, state)
	classPersistence.resetUserStateTracking(userId, state)
end

local function clearPersistedStateTracking(userId)
	classPersistence.clearUser(userId)
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
	return ClassProgression.getXpRequiredForNextLevel(getClassSystemConfig(), classDef, level)
end

local function isKnownClassId(classId)
	return classById[classId] ~= nil
end

classPersistence = ClassPersistence.new({
	dataStoreService = DataStoreService,
	dataStoreName = CLASS_SELECTION_DATASTORE_NAME,
	schemaVersion = CLASS_SELECTION_SCHEMA_VERSION,
	normalizeToken = normalizeToken,
	getDefaultClassId = getDefaultClassId,
	getMaxLevel = getMaxLevel,
	isKnownClassId = isKnownClassId,
})

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
	return ClassProgression.getBonusesAtLevel(classDef, level)
end

local function buildPerLevelBonusesFromConfig(rawBonusConfig)
	return ClassProgression.buildPerLevelBonusesFromConfig(rawBonusConfig)
end

local function buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)
	return ClassProgression.buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)
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
	return classCombatRules.isWeaponAllowedForClass(classDef, weaponDef)
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

classCombatRules = ClassCombatRules.new({
	normalizeToken = normalizeToken,
	getPlayerClassDefinition = getPlayerClassDefinition,
	getPlayerSelectedClassBonuses = getPlayerSelectedClassBonuses,
})

local function getWeaponDefinitionById(weaponId)
	return weaponById[weaponId]
end

local function getClassOrder()
	return classOrder
end

local function getClassStateRemote()
	return classStateRemote
end

classRuntimeEffects = ClassRuntimeEffects.new({
	playersService = Players,
	getPlayerSelectedClassBonuses = getPlayerSelectedClassBonuses,
	getPlayerClassDefinition = getPlayerClassDefinition,
	getWeaponById = getWeaponDefinitionById,
	isWeaponAllowedForClass = isWeaponAllowedForClass,
	getWaveMoveSpeedMultiplier = getWaveMoveSpeedMultiplier,
})

classStateSync = ClassStateSync.new({
	playersService = Players,
	getClassStateRemote = getClassStateRemote,
	getOrCreatePlayerState = getOrCreatePlayerState,
	getPlayerClassDefinition = getPlayerClassDefinition,
	canSwitchClassNow = canSwitchClassNow,
	getOrCreateClassProgress = getOrCreateClassProgress,
	getBonusesAtLevel = getBonusesAtLevel,
	getXpRequiredForNextLevel = getXpRequiredForNextLevel,
	buildPerLevelBonusesFromConfig = buildPerLevelBonusesFromConfig,
	buildCurrentBonusesWithFallback = buildCurrentBonusesWithFallback,
	getClassOrder = getClassOrder,
	getMaxLevel = getMaxLevel,
})

local function applyCharacterClassBonuses(player, character)
	classRuntimeEffects.applyCharacterClassBonuses(player, character)
end

local function refreshAllCharacterClassBonuses()
	classRuntimeEffects.refreshAllCharacterClassBonuses()
end

local function enforcePlayerLoadout(player)
	classRuntimeEffects.enforcePlayerLoadout(player)
end

local function buildPayloadForPlayer(player)
	return classStateSync.buildPayloadForPlayer(player)
end

local function pushPlayerState(player, reason, force)
	classStateSync.pushPlayerState(player, reason, force)
end

local function removeClassChangedCallback(callback)
	for index = #classChangedCallbacks, 1, -1 do
		if classChangedCallbacks[index] == callback then
			table.remove(classChangedCallbacks, index)
		end
	end
end

local function notifyClassChanged(player, previousClassId, selectedClassId)
	for _, callback in ipairs(classChangedCallbacks) do
		local ok, callbackError = pcall(callback, player, previousClassId, selectedClassId)
		if not ok then
			warn(
				string.format(
					"ClassService class changed callback failed for %s: %s",
					tostring(player and player.Name),
					tostring(callbackError)
				)
			)
		end
	end
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

	local previousClassId = state.selectedClassId
	state.selectedClassId = classDef.Id
	getOrCreateClassProgress(state, classDef.Id)
	markPersistedStateDirty(player.UserId)
	savePersistedState(player.UserId, state, true)

	if player.Character then
		applyCharacterClassBonuses(player, player.Character)
	end
	enforcePlayerLoadout(player)
	notifyClassChanged(player, previousClassId, classDef.Id)
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
	resetPersistedStateTracking(userId, state)

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
	if not force and not isPersistedStateDirty(userId) then
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

function ClassService.registerClassChangedCallback(callback)
	if type(callback) ~= "function" then
		return function() end
	end

	table.insert(classChangedCallbacks, callback)
	local isDisconnected = false

	return function()
		if isDisconnected then
			return
		end
		isDisconnected = true
		removeClassChangedCallback(callback)
	end
end

function ClassService.canPlayerUseWeapon(player, weaponDef)
	return classCombatRules.canPlayerUseWeapon(player, weaponDef)
end

function ClassService.getWeaponDamageMultiplier(player, weaponDef)
	return classCombatRules.getWeaponDamageMultiplier(player, weaponDef)
end

function ClassService.getIncomingDamageMultiplier(player)
	return classCombatRules.getIncomingDamageMultiplier(player)
end

function ClassService.getRepairSpeedMultiplier(player)
	return classCombatRules.getRepairSpeedMultiplier(player)
end

function ClassService.getTurretDamageMultiplier(player)
	return classCombatRules.getTurretDamageMultiplier(player)
end

function ClassService.getMeleeRangeMultiplier(player, weaponDef)
	return classCombatRules.getMeleeRangeMultiplier(player, weaponDef)
end

function ClassService.getWeaponShopCost(player, weaponDef)
	return classCombatRules.getWeaponShopCost(player, weaponDef)
end

function ClassService.getWeaponMagazineSize(player, weaponDef)
	return classCombatRules.getWeaponMagazineSize(player, weaponDef)
end

function ClassService.getWeaponReloadSeconds(player, weaponDef)
	return classCombatRules.getWeaponReloadSeconds(player, weaponDef)
end

function ClassService.getWeaponSpreadDegrees(player, weaponDef)
	return classCombatRules.getWeaponSpreadDegrees(player, weaponDef)
end

function ClassService.getWeaponBulletRangeMultiplier(player, weaponDef)
	return classCombatRules.getWeaponBulletRangeMultiplier(player, weaponDef)
end

function ClassService.getBurnOnHitConfig(player, weaponDef)
	return classCombatRules.getBurnOnHitConfig(player, weaponDef)
end

function ClassService.getCriticalHitConfig(player, weaponDef)
	return classCombatRules.getCriticalHitConfig(player, weaponDef)
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
	local progressionResult = ClassProgression.applyXpGain(
		getClassSystemConfig(),
		classDef,
		progress.level,
		progress.xp,
		xpGain
	)
	progress.level = progressionResult.level
	progress.xp = progressionResult.xp
	local leveledUp = progressionResult.leveledUp

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
		classStateSync.clearPlayer(player)
		clearPersistedStateTracking(player.UserId)

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
