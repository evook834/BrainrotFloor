local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyFactory = require(script.Parent.EnemyFactory)
local EnemyScaling = require(script.Parent.EnemyScaling)
local EnemySpawnResolver = require(script.Parent.EnemySpawnResolver)

local EnemyService = {}

local function chooseRandom(list)
	return list[math.random(1, #list)]
end

local function getSpawnCadence()
	local configuredCadence = Config.Wave.SpawnCadence or {}
	local playerScaling = configuredCadence.PlayerScaling or {}
	return {
		InitialDelaySeconds = configuredCadence.InitialDelaySeconds or 2,
		BaseIntervalSeconds = configuredCadence.BaseIntervalSeconds or 3,
		MinIntervalSeconds = configuredCadence.MinIntervalSeconds or 1.2,
		WaveAccelerationPerWave = configuredCadence.WaveAccelerationPerWave or 0.12,
		IntraWaveAcceleration = configuredCadence.IntraWaveAcceleration or 0.6,
		GroupSize = configuredCadence.GroupSize or 4,
		GroupPauseSeconds = configuredCadence.GroupPauseSeconds or 1.0,
		IntraBurstDelaySeconds = configuredCadence.IntraBurstDelaySeconds or 0.08,
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

local function getPlayerSpawnModifiers(playerCount, cadence)
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

local function getDelayUntilNextBurst(spawnedCount, enemyCount, waveNumber, cadence, intervalMultiplier, groupPauseMultiplier)
	if spawnedCount >= enemyCount then
		return 0
	end

	local waveAcceleration = math.max(0, waveNumber - 1) * cadence.WaveAccelerationPerWave
	local progress = 0
	if enemyCount > 1 then
		progress = (spawnedCount - 1) / (enemyCount - 1)
	end
	local intraWaveAcceleration = cadence.IntraWaveAcceleration * progress

	local interval = (cadence.BaseIntervalSeconds - waveAcceleration - intraWaveAcceleration) * intervalMultiplier
	interval = math.max(cadence.MinIntervalSeconds, interval)

	if cadence.GroupSize > 0 and spawnedCount % cadence.GroupSize == 0 then
		interval += cadence.GroupPauseSeconds * groupPauseMultiplier
	end

	return interval
end

function EnemyService.spawnWave(enemyCount, waveNumber, options)
	local templates = EnemySpawnResolver.getEnemyTemplates()
	local spawnPoints = EnemySpawnResolver.getSpawnPoints()

	if #templates == 0 then
		warn("No spawnable enemy templates found in ServerStorage/EnemyTemplates; check EnemyDefinitions")
		return 0
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in Workspace/SpawnPoints")
		return 0
	end

	local container = EnemySpawnResolver.getEnemyContainer()
	local spawned = 0
	local cadence = getSpawnCadence()
	local waveContext = EnemyScaling.buildWaveContext(waveNumber, options)

	if enemyCount > 0 and cadence.InitialDelaySeconds > 0 then
		task.wait(cadence.InitialDelaySeconds)
	end

	local spawnIndex = 0
	while spawnIndex < enemyCount do
		local cadencePlayerCount = EnemyScaling.resolvePlayerCount(nil)
		local burstSize, intervalMultiplier, groupPauseMultiplier = getPlayerSpawnModifiers(cadencePlayerCount, cadence)
		local toSpawnNow = math.min(burstSize, enemyCount - spawnIndex)

		for burstIndex = 1, toSpawnNow do
			spawnIndex += 1
			local template = chooseRandom(templates)
			local spawnPoint = chooseRandom(spawnPoints)
			local enemy = EnemyFactory.spawnFromTemplate(template, spawnPoint, container, waveContext, {
				enemyName = string.format("Brainrot_%d", spawnIndex),
			})
			if enemy then
				spawned += 1
			end

			if burstIndex < toSpawnNow and cadence.IntraBurstDelaySeconds > 0 then
				task.wait(cadence.IntraBurstDelaySeconds)
			end
		end

		local nextDelay = getDelayUntilNextBurst(
			spawnIndex,
			enemyCount,
			waveContext.activeWaveNumber,
			cadence,
			intervalMultiplier,
			groupPauseMultiplier
		)
		if nextDelay > 0 then
			task.wait(nextDelay)
		end
	end

	return spawned
end

function EnemyService.spawnSingle(templateName, waveNumber, options)
	local template = EnemySpawnResolver.getTemplateByName(templateName)
	if not template then
		warn(string.format("EnemyService.spawnSingle: template %q not found or not defined in EnemyDefinitions", tostring(templateName)))
		return nil
	end

	local spawnPoints = EnemySpawnResolver.getSpawnPoints()
	if #spawnPoints == 0 then
		warn("No spawn points found in Workspace/SpawnPoints")
		return nil
	end

	local resolvedOptions = type(options) == "table" and options or {}
	local enemyTier = (type(resolvedOptions.tier) == "string" and resolvedOptions.tier) or "Easy"
	local enemyDanger = (type(resolvedOptions.danger) == "string" and resolvedOptions.danger) or "Weakling"

	return EnemyFactory.spawnFromTemplate(
		template,
		chooseRandom(spawnPoints),
		EnemySpawnResolver.getEnemyContainer(),
		EnemyScaling.buildWaveContext(waveNumber, resolvedOptions),
		{
			enemyName = string.format("Brainrot_%s_%s", templateName, tostring(os.clock()):gsub("%.", "_")),
			enemyTier = enemyTier,
			enemyDanger = enemyDanger,
			onEnemyDied = resolvedOptions.onEnemyDied,
		}
	)
end

return EnemyService
