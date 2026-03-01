--[[
	WaveSpawnSchedule — When to spawn: cadence or director pressure-based cooldown.
	Director mode: when aliveCap is provided, delay = lerp(CooldownMin, CooldownMax, Alive/AliveCap)
	so we refill quickly when underfilled and avoid instant floods when near cap.
	Returns delaySeconds and burstSize; respects totalCap and 1500 hard cap (caller checks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.GameConfig)

local RECHECK_DELAY_WHEN_FULL = 0.75
local DIRECTOR_TICK = 0.25

export type SpawnCadencePlayerScaling = {
	Enabled: boolean,
	BasePlayers: number,
	BurstSizeBase: number,
	BurstSizePerExtraPlayer: number,
	MaxBurstSize: number,
	IntervalMultiplierPerExtraPlayer: number,
	MinIntervalMultiplier: number,
	GroupPauseMultiplierPerExtraPlayer: number,
	MinGroupPauseMultiplier: number,
}

export type SpawnCadence = {
	BaseIntervalSeconds: number,
	MinIntervalSeconds: number,
	WaveAccelerationPerWave: number,
	IntraWaveAcceleration: number,
	GroupSize: number,
	GroupPauseSeconds: number,
	PlayerScaling: SpawnCadencePlayerScaling,
}

local function getSpawnCadence(): SpawnCadence
	local configuredCadence = Config.Wave.SpawnCadence or {}
	local playerScaling = configuredCadence.PlayerScaling or {}
	return {
		BaseIntervalSeconds = configuredCadence.BaseIntervalSeconds or 3,
		MinIntervalSeconds = configuredCadence.MinIntervalSeconds or 1.2,
		WaveAccelerationPerWave = configuredCadence.WaveAccelerationPerWave or 0.12,
		IntraWaveAcceleration = configuredCadence.IntraWaveAcceleration or 0.6,
		GroupSize = configuredCadence.GroupSize or 4,
		GroupPauseSeconds = configuredCadence.GroupPauseSeconds or 1.0,
		PlayerScaling = {
			Enabled = playerScaling.Enabled ~= false,
			BasePlayers = playerScaling.BasePlayers or 1,
			BurstSizeBase = playerScaling.BurstSizeBase or 1,
			BurstSizePerExtraPlayer = playerScaling.BurstSizePerExtraPlayer or 1,
			MaxBurstSize = playerScaling.MaxBurstSize or 4,
			IntervalMultiplierPerExtraPlayer = playerScaling.IntervalMultiplierPerExtraPlayer or 0.12,
			MinIntervalMultiplier = playerScaling.MinIntervalMultiplier or 0.45,
			GroupPauseMultiplierPerExtraPlayer = playerScaling.GroupPauseMultiplierPerExtraPlayer or 0.08,
			MinGroupPauseMultiplier = playerScaling.MinGroupPauseMultiplier or 0.5,
		},
	}
end

local function getPlayerSpawnModifiers(playerCount: number, cadence: SpawnCadence): (number, number, number)
	local scaling = cadence.PlayerScaling
	if not scaling.Enabled then
		return 1, 1, 1
	end

	local basePlayers = math.max(1, scaling.BasePlayers)
	local extraPlayers = math.max(0, playerCount - basePlayers)

	local burstSize = scaling.BurstSizeBase + extraPlayers * scaling.BurstSizePerExtraPlayer
	burstSize = math.clamp(burstSize, 1, math.max(1, scaling.MaxBurstSize))
	burstSize = math.max(1, math.floor(burstSize + 0.5))

	local intervalMultiplier = 1 - extraPlayers * scaling.IntervalMultiplierPerExtraPlayer
	intervalMultiplier = math.max(scaling.MinIntervalMultiplier, intervalMultiplier)

	local groupPauseMultiplier = 1 - extraPlayers * scaling.GroupPauseMultiplierPerExtraPlayer
	groupPauseMultiplier = math.max(scaling.MinGroupPauseMultiplier, groupPauseMultiplier)

	return burstSize, intervalMultiplier, groupPauseMultiplier
end

local function getDelayUntilNextBurst(
	spawnedThisWave: number,
	totalCap: number,
	waveNumber: number,
	cadence: SpawnCadence,
	intervalMultiplier: number,
	groupPauseMultiplier: number
): number
	if totalCap <= 0 or spawnedThisWave >= totalCap then
		return 0
	end

	local waveAcceleration = math.max(0, waveNumber - 1) * cadence.WaveAccelerationPerWave
	local progress = 0
	if totalCap > 1 then
		progress = (spawnedThisWave - 1) / (totalCap - 1)
	end
	progress = math.clamp(progress, 0, 1)
	local intraWaveAcceleration = cadence.IntraWaveAcceleration * progress

	local interval = (cadence.BaseIntervalSeconds - waveAcceleration - intraWaveAcceleration) * intervalMultiplier
	interval = math.max(cadence.MinIntervalSeconds, interval)

	if cadence.GroupSize > 0 and spawnedThisWave > 0 and spawnedThisWave % cadence.GroupSize == 0 then
		interval += cadence.GroupPauseSeconds * groupPauseMultiplier
	end

	return interval
end

local function getTargetAlive(aliveCount: number, playerCount: number, spawnedThisWave: number, totalCap: number): number
	local traj = Config.Wave.Trajectory or {}
	local base = tonumber(traj.TargetAliveBase) or 8
	local perPlayer = tonumber(traj.TargetAlivePerPlayer) or 4
	local maxTarget = tonumber(traj.MaxTargetAlive) or 60

	local target = base + perPlayer * math.max(0, playerCount)
	target = math.min(target, maxTarget)
	target = math.min(target, aliveCount + math.max(0, totalCap - spawnedThisWave))
	return math.max(0, math.floor(target + 0.5))
end

-- Director pressure-based cooldown: lerp(CooldownMin, CooldownMax, Alive/AliveCap).
local function getDirectorCooldown(aliveCount: number, aliveCap: number): number
	aliveCap = math.max(1, tonumber(aliveCap) or 1)
	local ratio = math.clamp((tonumber(aliveCount) or 0) / aliveCap, 0, 1)
	local dir = Config.Wave.Director
	local cMin = (dir and tonumber(dir.CooldownMin)) or 0.15
	local cMax = (dir and tonumber(dir.CooldownMax)) or 1.0
	return cMin + (cMax - cMin) * ratio
end

function getNextSpawn(
	aliveCount: number,
	spawnedThisWave: number,
	totalCap: number,
	playerCount: number,
	waveNumber: number,
	aliveCap: number?
): (number, number)
	aliveCount = math.max(0, tonumber(aliveCount) or 0)
	spawnedThisWave = math.max(0, tonumber(spawnedThisWave) or 0)
	totalCap = math.max(0, tonumber(totalCap) or 0)
	playerCount = math.max(1, tonumber(playerCount) or 1)
	waveNumber = math.max(1, tonumber(waveNumber) or 1)
	aliveCap = tonumber(aliveCap)

	if spawnedThisWave >= totalCap then
		return RECHECK_DELAY_WHEN_FULL, 0
	end

	-- Director mode: use aliveCap as target concurrency and pressure-based cooldown
	if aliveCap and aliveCap > 0 then
		if aliveCount >= aliveCap then
			return RECHECK_DELAY_WHEN_FULL, 0
		end
		local delaySeconds = getDirectorCooldown(aliveCount, aliveCap)
		local room = totalCap - spawnedThisWave
		local gap = aliveCap - aliveCount
		local burstSize = math.min(math.max(1, math.floor(gap + 0.5)), math.max(0, room))
		if burstSize <= 0 then
			return RECHECK_DELAY_WHEN_FULL, 0
		end
		return math.max(DIRECTOR_TICK, delaySeconds), burstSize
	end

	-- Legacy: trajectory-based target alive
	local targetAlive = getTargetAlive(aliveCount, playerCount, spawnedThisWave, totalCap)
	if aliveCount >= targetAlive then
		return RECHECK_DELAY_WHEN_FULL, 0
	end

	local cadence = getSpawnCadence()
	local burstMax, intervalMultiplier, groupPauseMultiplier = getPlayerSpawnModifiers(playerCount, cadence)
	local gap = targetAlive - aliveCount
	local room = totalCap - spawnedThisWave
	local burstSize = math.min(burstMax, math.max(0, gap), math.max(0, room))
	burstSize = math.floor(burstSize + 0.5)

	if burstSize <= 0 then
		return RECHECK_DELAY_WHEN_FULL, 0
	end

	local delaySeconds = getDelayUntilNextBurst(spawnedThisWave, totalCap, waveNumber, cadence, intervalMultiplier, groupPauseMultiplier)
	return math.max(0.1, delaySeconds), burstSize
end

local WaveSpawnSchedule = {
	getNextSpawn = getNextSpawn,
}

return WaveSpawnSchedule
