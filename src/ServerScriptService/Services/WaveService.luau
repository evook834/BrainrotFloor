local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local waveStateRemote = remotesFolder:WaitForChild(Config.Remotes.WaveState)

local WaveService = {}

local running = false
local waveNumber = 0

local function broadcastState(stateName, payload)
	payload = payload or {}
	payload.state = stateName
	payload.wave = waveNumber
	waveStateRemote:FireAllClients(payload)
end

local function waitForWaveClear(timeoutSeconds)
	local startedAt = os.clock()
	local enemyContainer = Workspace:FindFirstChild(Config.Enemy.ContainerName)

	while true do
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

function WaveService.start()
	if running then
		warn("WaveService is already running")
		return
	end

	running = true

	while running do
		waveNumber += 1
		local enemiesToSpawn = Config.Wave.BaseEnemyCount + (waveNumber - 1) * Config.Wave.EnemiesPerWave

		broadcastState("Preparing", {
			enemies = enemiesToSpawn,
			intermission = Config.Wave.IntermissionSeconds,
		})
		task.wait(Config.Wave.IntermissionSeconds)

		broadcastState("InProgress", {
			enemies = enemiesToSpawn,
		})

		local spawned = EnemyService.spawnWave(enemiesToSpawn, Config.Wave.SpawnBatchDelay)
		if spawned == 0 then
			warn("No enemies were spawned. Add Brainrot enemy models and spawn points.")
			broadcastState("Blocked", {
				reason = "NoEnemyTemplatesOrSpawnPoints",
			})
			task.wait(5)
			continue
		end

		waitForWaveClear()
		broadcastState("Cleared", {
			enemies = spawned,
		})
		task.wait(2)
	end
end

function WaveService.stop()
	running = false
end

return WaveService
