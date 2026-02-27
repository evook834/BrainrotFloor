--[[
	WaveSpawnRunner — Runs the director spawn loop: respects AliveCap, 1500 hard cap, role caps.
	Uses Schedule for pressure-based cooldown, Logic for composition and pickTemplate(roleAlive, totalSpawnedByRole).
	Wave ends when (RemainingToSpawn == 0 and Alive == 0) or TotalSpawned >= 1500 then cleanup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local WaveSpawnLogic = require(script.Parent.WaveSpawnLogic)
local WaveSpawnSchedule = require(script.Parent.WaveSpawnSchedule)
local Match = script.Parent.Parent
local EnemyRegistry = require(Match.Enemies.EnemyRegistry)
local EnemyService = require(Match.Enemies.EnemyService)

local TIER_TO_ROLE = {
	Easy = "trash",
	Medium = "medium",
	Hard = "heavy",
	Elite = "special",
}

local function getAliveCount()
	return EnemyRegistry.getAliveCount()
end

local function getAliveByRole()
	return EnemyRegistry.getAliveByRole()
end

local function isRunning(options)
	if type(options) ~= "table" then
		return true
	end
	local fn = options.isRunning
	if type(fn) ~= "function" then
		return true
	end
	return fn() == true
end

function run(waveNumber, playerCount, options)
	waveNumber = math.max(1, tonumber(waveNumber) or 1)
	playerCount = math.max(1, tonumber(playerCount) or 1)
	options = type(options) == "table" and options or {}

	local maxMonstersPerWave = Config.Wave.MaxMonstersPerWave or 1500
	local composition = WaveSpawnLogic.getWaveComposition(waveNumber, playerCount, maxMonstersPerWave)
	local totalCap = composition.totalCap
	local aliveCap = composition.aliveCap
	local pickTemplate = composition.pickTemplate

	if totalCap <= 0 or not pickTemplate then
		return
	end

	local spawnedSoFar = 0
	local totalSpawnedByRole = { trash = 0, medium = 0, heavy = 0, special = 0 }
	local hardCap = math.min(1500, maxMonstersPerWave)

	while spawnedSoFar < totalCap and spawnedSoFar < hardCap do
		if not isRunning(options) then
			break
		end

		local aliveCount = getAliveCount()
		local roleAlive = getAliveByRole()
		local delaySeconds, burstSize = WaveSpawnSchedule.getNextSpawn(
			aliveCount,
			spawnedSoFar,
			totalCap,
			playerCount,
			waveNumber,
			aliveCap
		)

		if delaySeconds > 0 then
			task.wait(delaySeconds)
		end

		if not isRunning(options) then
			break
		end

		if burstSize > 0 then
			local toSpawn = math.min(burstSize, totalCap - spawnedSoFar, hardCap - spawnedSoFar)
			for _ = 1, toSpawn do
				local pick = pickTemplate(roleAlive, totalSpawnedByRole)
				if pick and pick.templateName then
					local spawnOpts = {
						playerCount = options.playerCount,
						isRunning = options.isRunning,
						onEnemyDied = options.onEnemyDied,
						tier = pick.tier,
					}
					EnemyService.spawnSingle(pick.templateName, waveNumber, spawnOpts)
					spawnedSoFar += 1
					local role = TIER_TO_ROLE[pick.tier] or "trash"
					if totalSpawnedByRole[role] ~= nil then
						totalSpawnedByRole[role] += 1
					end
					roleAlive = getAliveByRole()
				end
			end
		end
	end
end

local WaveSpawnRunner = {
	run = run,
	getAliveCount = getAliveCount,
	getAliveByRole = getAliveByRole,
}

return WaveSpawnRunner
