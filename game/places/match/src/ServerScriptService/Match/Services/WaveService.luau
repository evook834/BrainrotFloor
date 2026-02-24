local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)

local WaveService = {}

local running = false
local waveNumber = 0
local waveStateRemote = nil
local terminalState = nil

local function resolveWaveStateRemote()
	local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		return nil
	end

	local remote = remotesFolder:FindFirstChild(Config.Remotes.WaveState)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function broadcastState(stateName, payload)
	if not waveStateRemote then
		return
	end

	payload = payload or {}
	payload.state = stateName
	payload.wave = waveNumber

	local remotesFolder = waveStateRemote.Parent
	if remotesFolder then
		remotesFolder:SetAttribute("CurrentWaveState", stateName)
		remotesFolder:SetAttribute("CurrentWaveNumber", waveNumber)
		remotesFolder:SetAttribute("IntermissionEndTime", payload.intermissionEndsAt or 0)
	end

	waveStateRemote:FireAllClients(payload)
end

local function waitForWaveClear(timeoutSeconds)
	local startedAt = os.clock()
	local enemyContainer = Workspace:FindFirstChild(Config.Enemy.ContainerName)

	while true do
		if not running then
			return false
		end

		enemyContainer = enemyContainer or Workspace:FindFirstChild(Config.Enemy.ContainerName)
		local remaining = enemyContainer and #enemyContainer:GetChildren() or 0
		if remaining <= 0 then
			return true
		end

		if timeoutSeconds and os.clock() - startedAt >= timeoutSeconds then
			return false
		end

		task.wait(0.5)
	end
end

local function getWaveScalingConfig()
	local scaling = Config.Wave.WaveScaling or {}

	return {
		enabled = scaling.Enabled ~= false,
		basePlayers = math.max(1, math.floor((tonumber(scaling.BasePlayers) or 1) + 0.5)),
		enemiesPerExtraPlayer = math.max(0, tonumber(scaling.EnemiesPerExtraPlayer) or 1),
		maxEnemyCountMultiplier = math.max(1, tonumber(scaling.MaxEnemyCountMultiplier) or 2),
	}
end

local function getScaledWaveEnemyCount(baseEnemyCount, playerCount, scalingConfig)
	local safeBaseEnemyCount = math.max(1, math.floor((tonumber(baseEnemyCount) or 1) + 0.5))
	if not scalingConfig.enabled then
		return safeBaseEnemyCount
	end

	local safePlayerCount = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local extraPlayers = math.max(0, safePlayerCount - scalingConfig.basePlayers)
	local scaledEnemyCount = safeBaseEnemyCount + (extraPlayers * scalingConfig.enemiesPerExtraPlayer)
	scaledEnemyCount = math.min(scaledEnemyCount, safeBaseEnemyCount * scalingConfig.maxEnemyCountMultiplier)

	return math.max(1, math.floor(scaledEnemyCount + 0.5))
end

function WaveService.start()
	if running then
		warn("WaveService is already running")
		return
	end

	if terminalState == "GameOver" then
		warn("WaveService cannot start after game over")
		return
	end

	waveStateRemote = resolveWaveStateRemote()
	if not waveStateRemote then
		warn("WaveService could not find ReplicatedStorage/Remotes/WaveState")
		return
	end

	running = true
	local waveScalingConfig = getWaveScalingConfig()
	local playersForNextWave = math.max(1, #Players:GetPlayers())

	while running do
		waveNumber += 1
		local baseEnemiesToSpawn = Config.Wave.BaseEnemyCount + (waveNumber - 1) * Config.Wave.EnemiesPerWave
		local enemiesToSpawn = getScaledWaveEnemyCount(baseEnemiesToSpawn, playersForNextWave, waveScalingConfig)

		broadcastState("Preparing", {
			enemies = enemiesToSpawn,
			players = playersForNextWave,
			intermission = Config.Wave.IntermissionSeconds,
			intermissionEndsAt = Workspace:GetServerTimeNow() + Config.Wave.IntermissionSeconds,
		})
		task.wait(Config.Wave.IntermissionSeconds)
		if not running then
			break
		end

		broadcastState("InProgress", {
			enemies = enemiesToSpawn,
			players = playersForNextWave,
		})

		local spawned = EnemyService.spawnWave(enemiesToSpawn, waveNumber, {
			playerCount = playersForNextWave,
		})
		if spawned == 0 then
			warn("No enemies were spawned. Add Brainrot enemy models and spawn points.")
			broadcastState("Blocked", {
				reason = "NoEnemyTemplatesOrSpawnPoints",
			})
			playersForNextWave = math.max(1, #Players:GetPlayers())
			task.wait(5)
			continue
		end

		waitForWaveClear()
		if not running then
			break
		end

		playersForNextWave = math.max(1, #Players:GetPlayers())
		broadcastState("Cleared", {
			enemies = spawned,
			nextWavePlayers = playersForNextWave,
		})
		task.wait(2)
	end
end

function WaveService.stop()
	running = false
end

function WaveService.gameOver(reason)
	if terminalState == "GameOver" then
		return
	end

	terminalState = "GameOver"
	running = false

	if not waveStateRemote then
		waveStateRemote = resolveWaveStateRemote()
	end

	broadcastState("GameOver", {
		reason = reason or "AllPlayersDead",
	})
end

return WaveService
