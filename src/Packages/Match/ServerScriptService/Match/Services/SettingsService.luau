local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local SettingsService = {}

local SETTINGS_DATASTORE_NAME = "BrainrotFloor_PlayerSettings_v1"
local SETTINGS_SCHEMA_VERSION = 1
local SETTINGS_AUTOSAVE_SECONDS = 30
local SETTINGS_SAVE_THROTTLE_SECONDS = 8

local DEFAULT_SETTINGS = {
	schemaVersion = SETTINGS_SCHEMA_VERSION,
	audio = {
		musicVolume = 1,
		musicMuted = false,
		sfxVolume = 1,
		sfxMuted = false,
	},
	hud = {
		scale = 1,
		positions = {},
	},
}

local started = false
local settingsStore = nil
local settingsStoreUnavailable = false
local persistedStateSignatureByUserId = {}
local dirtyStateByUserId = {}
local lastSaveAttemptAtByUserId = {}
local stateByUserId = {}

local remotesFolder = nil
local settingsGetFunction = nil
local settingsSaveRemote = nil

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

local function clampNumber(value, fallback, minimum, maximum)
	local numberValue = tonumber(value)
	if numberValue == nil then
		numberValue = fallback
	end
	return math.clamp(numberValue, minimum, maximum)
end

local function clampBool(value, fallback)
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function sanitizePosition(rawPosition)
	if type(rawPosition) ~= "table" then
		return nil
	end

	local xScale = clampNumber(rawPosition.xScale, 0, -10, 10)
	local xOffset = math.floor(clampNumber(rawPosition.xOffset, 0, -10000, 10000) + 0.5)
	local yScale = clampNumber(rawPosition.yScale, 0, -10, 10)
	local yOffset = math.floor(clampNumber(rawPosition.yOffset, 0, -10000, 10000) + 0.5)

	return {
		xScale = xScale,
		xOffset = xOffset,
		yScale = yScale,
		yOffset = yOffset,
	}
end

local function sanitizeSettings(rawSettings)
	local sanitized = {
		schemaVersion = SETTINGS_SCHEMA_VERSION,
		audio = {
			musicVolume = 1,
			musicMuted = false,
			sfxVolume = 1,
			sfxMuted = false,
		},
		hud = {
			scale = 1,
			positions = {},
		},
	}

	if type(rawSettings) ~= "table" then
		return sanitized
	end

	local rawAudio = rawSettings.audio
	if type(rawAudio) == "table" then
		sanitized.audio.musicVolume = clampNumber(rawAudio.musicVolume, 1, 0, 1)
		sanitized.audio.musicMuted = clampBool(rawAudio.musicMuted, false)
		sanitized.audio.sfxVolume = clampNumber(rawAudio.sfxVolume, 1, 0, 1)
		sanitized.audio.sfxMuted = clampBool(rawAudio.sfxMuted, false)
	end

	local rawHud = rawSettings.hud
	if type(rawHud) == "table" then
		sanitized.hud.scale = clampNumber(rawHud.scale, 1, 0.6, 1.45)
		local rawPositions = rawHud.positions
		if type(rawPositions) == "table" then
			local storedCount = 0
			for key, rawPosition in pairs(rawPositions) do
				if storedCount >= 120 then
					break
				end
				if type(key) == "string" and key ~= "" and #key <= 180 then
					local sanitizedPosition = sanitizePosition(rawPosition)
					if sanitizedPosition then
						sanitized.hud.positions[key] = sanitizedPosition
						storedCount += 1
					end
				end
			end
		end
	end

	return sanitized
end

local function copySettings(settings)
	return sanitizeSettings(settings)
end

local function buildStateSignature(settings)
	local audio = settings.audio or {}
	local hud = settings.hud or {}
	local positions = hud.positions or {}

	local parts = {
		string.format("mv=%.4f", tonumber(audio.musicVolume) or 1),
		string.format("mm=%d", audio.musicMuted and 1 or 0),
		string.format("sv=%.4f", tonumber(audio.sfxVolume) or 1),
		string.format("sm=%d", audio.sfxMuted and 1 or 0),
		string.format("hs=%.4f", tonumber(hud.scale) or 1),
	}

	local keys = {}
	for key in pairs(positions) do
		table.insert(keys, key)
	end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local position = positions[key] or {}
		table.insert(
			parts,
			string.format(
				"%s:%.4f:%d:%.4f:%d",
				key,
				tonumber(position.xScale) or 0,
				math.floor((tonumber(position.xOffset) or 0) + 0.5),
				tonumber(position.yScale) or 0,
				math.floor((tonumber(position.yOffset) or 0) + 0.5)
			)
		)
	end

	return table.concat(parts, "|")
end

local function getSettingsStore()
	if settingsStore then
		return settingsStore
	end
	if settingsStoreUnavailable then
		return nil
	end

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(SETTINGS_DATASTORE_NAME)
	end)
	if not ok or not store then
		settingsStoreUnavailable = true
		warn(string.format("SettingsService could not get player settings DataStore: %s", tostring(store)))
		return nil
	end

	settingsStore = store
	return settingsStore
end

local function getStoreKey(userId)
	return string.format("u:%d", math.max(0, math.floor(tonumber(userId) or 0)))
end

local function loadPersistedState(userId)
	local store = getSettingsStore()
	if not store then
		return nil
	end

	local key = getStoreKey(userId)
	local ok, value = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn(string.format("SettingsService failed to load settings for userId %s: %s", tostring(userId), tostring(value)))
		return nil
	end

	if type(value) ~= "table" then
		return nil
	end

	return sanitizeSettings(value)
end

local function markStateDirty(userId)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end
	dirtyStateByUserId[userId] = true
end

local function savePersistedState(userId, state, force)
	if type(userId) ~= "number" or userId <= 0 then
		return false
	end

	local sanitizedState = sanitizeSettings(state)
	local signature = buildStateSignature(sanitizedState)
	if persistedStateSignatureByUserId[userId] == signature and (not force or dirtyStateByUserId[userId] ~= true) then
		dirtyStateByUserId[userId] = nil
		return true
	end

	local store = getSettingsStore()
	if not store then
		return false
	end

	local key = getStoreKey(userId)
	local ok, errOrResult = pcall(function()
		store:SetAsync(key, sanitizedState)
	end)
	if not ok then
		warn(
			string.format(
				"SettingsService failed to save settings for userId %s: %s",
				tostring(userId),
				tostring(errOrResult)
			)
		)
		return false
	end

	persistedStateSignatureByUserId[userId] = signature
	dirtyStateByUserId[userId] = nil
	lastSaveAttemptAtByUserId[userId] = os.clock()
	return true
end

local function bindPlayer(player)
	local userId = player.UserId
	local loadedState = loadPersistedState(userId)
	local state = copySettings(loadedState or DEFAULT_SETTINGS)
	stateByUserId[userId] = state
	persistedStateSignatureByUserId[userId] = buildStateSignature(state)
	dirtyStateByUserId[userId] = nil
	lastSaveAttemptAtByUserId[userId] = 0
end

local function savePlayerState(player, force)
	if not player or not player:IsA("Player") then
		return false
	end

	local userId = player.UserId
	local state = stateByUserId[userId]
	if not state then
		return false
	end
	if not force and dirtyStateByUserId[userId] ~= true then
		return true
	end

	return savePersistedState(userId, state, force)
end

local function autosaveDirtyStates()
	for _, player in Players:GetPlayers() do
		savePlayerState(player, false)
	end
end

function SettingsService.start()
	if started then
		return
	end
	started = true

	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = Config.Remotes.Folder
		remotesFolder.Parent = ReplicatedStorage
	end

	settingsGetFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.SettingsGet)
	settingsSaveRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.SettingsSave)

	settingsGetFunction.OnServerInvoke = function(player)
		if not player or not player:IsA("Player") then
			return {
				success = false,
				message = "Invalid player",
			}
		end

		local userId = player.UserId
		local state = stateByUserId[userId]
		if not state then
			bindPlayer(player)
			state = stateByUserId[userId]
		end

		return {
			success = true,
			settings = copySettings(state or DEFAULT_SETTINGS),
		}
	end

	settingsSaveRemote.OnServerEvent:Connect(function(player, rawSettings)
		if not player or not player:IsA("Player") then
			return
		end
		if type(rawSettings) ~= "table" then
			return
		end

		local userId = player.UserId
		local sanitizedState = sanitizeSettings(rawSettings)
		stateByUserId[userId] = sanitizedState
		markStateDirty(userId)

		local now = os.clock()
		local lastSaveAttempt = tonumber(lastSaveAttemptAtByUserId[userId]) or 0
		if now - lastSaveAttempt >= SETTINGS_SAVE_THROTTLE_SECONDS then
			savePersistedState(userId, sanitizedState, false)
		end
	end)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayerState(player, true)

		local userId = player.UserId
		stateByUserId[userId] = nil
		dirtyStateByUserId[userId] = nil
		persistedStateSignatureByUserId[userId] = nil
		lastSaveAttemptAtByUserId[userId] = nil
	end)

	task.spawn(function()
		while started do
			task.wait(SETTINGS_AUTOSAVE_SECONDS)
			autosaveDirtyStates()
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			savePlayerState(player, true)
		end
	end)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return SettingsService
