--[[
	Shared SettingsService — Binds SettingsGet/SettingsSave remotes and reads/writes
	player settings via PlayerDataService (DataService). Used in both Lobby and Match.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Settings.SettingsConfig)
local PlayerDataService = require(script.Parent.Parent.PlayerData.PlayerDataService)

local SettingsService = {}

local SETTINGS_SCHEMA_VERSION = 1

local started = false
local remotesFolder = nil

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

local function migrateSettings(rawSettings)
	-- Migration logic for future schema versions
	-- Returns: migratedSettings, wasMigrated

	if type(rawSettings) ~= "table" then
		return nil, false
	end

	local schemaVersion = tonumber(rawSettings.schemaVersion)
	if schemaVersion == nil then
		-- No schema version means pre-schema data
		-- Return default with migration flag
		return nil, false
	end

	if schemaVersion == SETTINGS_SCHEMA_VERSION then
		return rawSettings, false
	end

	-- Future migrations can be added here based on schemaVersion
	-- Example:
	-- if schemaVersion == 0 then
	--     rawSettings = migrateFromV0(rawSettings)
	--     rawSettings.schemaVersion = 1
	-- end

	return rawSettings, schemaVersion ~= SETTINGS_SCHEMA_VERSION
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

	-- Apply migration first
	rawSettings = migrateSettings(rawSettings) or rawSettings

	local rawAudio = rawSettings.audio
	if type(rawAudio) == "table" then
		sanitized.audio.musicVolume = clampNumber(rawAudio.musicVolume, 1, 0, 1)
		sanitized.audio.musicMuted = clampBool(rawAudio.musicMuted, false)
		sanitized.audio.sfxVolume = clampNumber(rawAudio.sfxVolume, 1, 0, 1)
		sanitized.audio.sfxMuted = clampBool(rawAudio.sfxMuted, false)
	end
	local rawHud = rawSettings.hud
	if type(rawHud) == "table" then
		sanitized.hud.scale = clampNumber(rawHud.scale, 1, SettingsConfig.Hud.Scale.Min, SettingsConfig.Hud.Scale.Max)
		local rawPositions = rawHud.positions
		if type(rawPositions) == "table" then
			local storedCount = 0
			for key, rawPosition in pairs(rawPositions) do
				if storedCount >= SettingsConfig.Hud.MaxPositionEntries then
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

local defaultSettings = sanitizeSettings({})

function SettingsService.start()
	if started then
		return
	end
	if not PlayerDataService.isReady() then
		warn("[SettingsService] PlayerDataService not ready; call PlayerDataService.start() first.")
		return
	end

	started = true
	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = Config.Remotes.Folder
		remotesFolder.Parent = ReplicatedStorage
	end

	local settingsGetFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.SettingsGet)
	local settingsSaveRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.SettingsSave)

	settingsGetFunction.OnServerInvoke = function(player)
		if not player or not player:IsA("Player") then
			return { success = false, message = "Invalid player" }
		end
		PlayerDataService.waitForData(player)
		local settings = PlayerDataService.get(player, { "settings" })
		return {
			success = true,
			settings = sanitizeSettings(type(settings) == "table" and settings or defaultSettings),
		}
	end

	settingsSaveRemote.OnServerEvent:Connect(function(player, rawSettings)
		if not player or not player:IsA("Player") then
			return
		end
		if type(rawSettings) ~= "table" then
			return
		end
		PlayerDataService.set(player, { "settings" }, sanitizeSettings(rawSettings))
	end)
end

function SettingsService.stop()
	if not started then
		return
	end

	started = false
	if remotesFolder then
		remotesFolder:Destroy()
		remotesFolder = nil
	end
end

return SettingsService
