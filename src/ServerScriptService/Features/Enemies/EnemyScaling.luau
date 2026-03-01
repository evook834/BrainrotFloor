local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local DifficultyService = require(Match.Difficulty.DifficultyService)

local EnemyScaling = {}

local function roundPositiveInteger(value)
	return math.max(1, math.floor((tonumber(value) or 1) + 0.5))
end

function EnemyScaling.resolvePlayerCount(options)
	if type(options) == "table" and type(options.playerCount) == "number" then
		return roundPositiveInteger(options.playerCount)
	end

	return math.max(1, #Players:GetPlayers())
end

function EnemyScaling.getEnemyHealthMultiplierForDifficulty(difficulty)
	local multiplier = tonumber(DifficultyService.getNumberSetting("EnemyHealthMultiplier", 1, difficulty)) or 1
	if multiplier <= 0 then
		return 1
	end

	return multiplier
end

function EnemyScaling.getEnemyHealthMultiplierForPlayers(playerCount)
	local scaling = Config.Wave.WaveScaling or {}
	if scaling.Enabled == false then
		return 1
	end

	local basePlayers = roundPositiveInteger(scaling.BasePlayers)
	local extraPlayers = math.max(0, roundPositiveInteger(playerCount) - basePlayers)
	local multiplierPerExtraPlayer = math.max(0, tonumber(scaling.EnemyHealthMultiplierPerExtraPlayer) or 0.15)
	local maxMultiplier = math.max(1, tonumber(scaling.MaxEnemyHealthMultiplier) or 1.75)
	local multiplier = 1 + (extraPlayers * multiplierPerExtraPlayer)

	return math.max(1, math.min(maxMultiplier, multiplier))
end

function EnemyScaling.getEnemyDamageMultiplierForDifficulty(difficulty)
	local multiplier = tonumber(DifficultyService.getNumberSetting("EnemyDamageMultiplier", 1, difficulty)) or 1
	if multiplier < 0 then
		return 0
	end

	return multiplier
end

function EnemyScaling.buildWaveContext(waveNumber, options)
	local activeWaveNumber = roundPositiveInteger(waveNumber)
	local activeDifficulty = DifficultyService.getCurrentDifficulty()
	local playerCountForWave = EnemyScaling.resolvePlayerCount(options)
	local enemyDifficultyHealthMultiplier = EnemyScaling.getEnemyHealthMultiplierForDifficulty(activeDifficulty)
	local enemyPlayerHealthMultiplier = EnemyScaling.getEnemyHealthMultiplierForPlayers(playerCountForWave)

	return {
		activeWaveNumber = activeWaveNumber,
		activeDifficulty = activeDifficulty,
		playerCountForWave = playerCountForWave,
		enemyPlayerHealthMultiplier = enemyPlayerHealthMultiplier,
		enemyHealthMultiplier = enemyDifficultyHealthMultiplier * enemyPlayerHealthMultiplier,
		enemyDamageMultiplier = EnemyScaling.getEnemyDamageMultiplierForDifficulty(activeDifficulty),
	}
end

return EnemyScaling
