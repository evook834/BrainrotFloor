local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local DifficultyService = {}

-- Snapshot of difficulty configuration from shared GameConfig.
local difficultyConfig: any = {}
local settingsByDifficulty: { [string]: any } = {}
local orderedNames: { string } = {}

do
	local fromConfig = Config.Difficulty
	if type(fromConfig) == "table" then
		difficultyConfig = fromConfig
		local settings = fromConfig.Settings
		if type(settings) == "table" then
			settingsByDifficulty = settings
		end
		if type(fromConfig.OrderedNames) == "table" then
			orderedNames = fromConfig.OrderedNames
		end
	end
end

local function isKnownDifficultyInternal(difficultyName: any): boolean
	if type(difficultyName) ~= "string" or difficultyName == "" then
		return false
	end

	return type(settingsByDifficulty[difficultyName]) == "table"
end

function DifficultyService.getCurrentDifficulty(): string
	local liveDifficulty = Workspace:GetAttribute("Difficulty")
	if isKnownDifficultyInternal(liveDifficulty) then
		return liveDifficulty :: string
	end

	local defaultDifficulty = difficultyConfig.Default
	if isKnownDifficultyInternal(defaultDifficulty) then
		return defaultDifficulty
	end

	for difficultyName, value in pairs(settingsByDifficulty) do
		if type(value) == "table" then
			return difficultyName
		end
	end

	return "Normal"
end

function DifficultyService.getCurrentSettings()
	return DifficultyService.getSettings(DifficultyService.getCurrentDifficulty())
end

function DifficultyService.getSettings(difficultyName: string?)
	local configured = settingsByDifficulty[difficultyName]
	if type(configured) == "table" then
		return configured
	end

	local fallbackDifficulty = DifficultyService.getCurrentDifficulty()
	local fallback = settingsByDifficulty[fallbackDifficulty]
	if type(fallback) == "table" then
		return fallback
	end

	return {}
end

function DifficultyService.getNumberSetting(settingName: string, defaultValue: number?, difficultyName: string?)
	local settings = DifficultyService.getSettings(difficultyName or DifficultyService.getCurrentDifficulty())
	local value = settings[settingName]
	if type(value) == "number" then
		return value
	end

	return defaultValue
end

-- Public utility helpers for callers that need to inspect difficulty config.
function DifficultyService.isKnownDifficulty(difficultyName: string?)
	return isKnownDifficultyInternal(difficultyName)
end

function DifficultyService.getAllDifficulties(): { string }
	if #orderedNames > 0 then
		return orderedNames
	end
	local result = {}
	for difficultyName, value in pairs(settingsByDifficulty) do
		if type(value) == "table" then
			table.insert(result, difficultyName)
		end
	end
	table.sort(result)
	return result
end

return DifficultyService
