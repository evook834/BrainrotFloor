local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local DifficultyService = {}

local function getDifficultyConfig()
	local difficultyConfig = Config.Difficulty
	if type(difficultyConfig) == "table" then
		return difficultyConfig
	end

	return {}
end

local function getSettingsTable()
	local difficultyConfig = getDifficultyConfig()
	local settings = difficultyConfig.Settings
	if type(settings) == "table" then
		return settings
	end

	return {}
end

local function isKnownDifficulty(difficultyName)
	if type(difficultyName) ~= "string" or difficultyName == "" then
		return false
	end

	local settings = getSettingsTable()
	return type(settings[difficultyName]) == "table"
end

function DifficultyService.getCurrentDifficulty()
	local liveDifficulty = Workspace:GetAttribute("Difficulty")
	if isKnownDifficulty(liveDifficulty) then
		return liveDifficulty
	end

	local difficultyConfig = getDifficultyConfig()
	local defaultDifficulty = difficultyConfig.Default
	if isKnownDifficulty(defaultDifficulty) then
		return defaultDifficulty
	end

	local settings = getSettingsTable()
	for difficultyName, _ in pairs(settings) do
		return difficultyName
	end

	return "Normal"
end

function DifficultyService.getCurrentSettings()
	return DifficultyService.getSettings(DifficultyService.getCurrentDifficulty())
end

function DifficultyService.getSettings(difficultyName)
	local settings = getSettingsTable()
	local configured = settings[difficultyName]
	if type(configured) == "table" then
		return configured
	end

	local fallback = settings[DifficultyService.getCurrentDifficulty()]
	if type(fallback) == "table" then
		return fallback
	end

	return {}
end

function DifficultyService.getNumberSetting(settingName, defaultValue, difficultyName)
	local settings = DifficultyService.getSettings(difficultyName or DifficultyService.getCurrentDifficulty())
	local value = settings[settingName]
	if type(value) == "number" then
		return value
	end

	return defaultValue
end

return DifficultyService
