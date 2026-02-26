local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local WaveSpawnLogic = require(script.Parent.WaveSpawnLogic)
local WaveSpawnRunner = require(script.Parent.WaveSpawnRunner)

local WaveService = {}

local running = false
local waveNumber = 0
local waveStateRemote = nil
local terminalState = nil
local onWinCallback = nil

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

local function getRemotesFolder()
	if not waveStateRemote then
		return nil
	end
	return waveStateRemote.Parent
end

local function setWaveEnemiesRemaining(value)
	local remotesFolder = getRemotesFolder()
	if not remotesFolder then
		return
	end
	local nv = remotesFolder:FindFirstChild("WaveEnemiesRemaining")
	if nv and nv:IsA("IntValue") then
		nv.Value = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	end
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

	if terminalState == "GameOver" or terminalState == "Won" then
		warn("WaveService cannot start after game over or win")
		return
	end

	waveStateRemote = resolveWaveStateRemote()
	if not waveStateRemote then
		warn("WaveService could not find ReplicatedStorage/Remotes/WaveState")
		return
	end

	running = true
	local bossWaveNumber = math.max(2, tonumber(Config.Wave.BossWaveNumber) or 11)
	local playersForNextWave = math.max(1, #Players:GetPlayers())

	while running do
		waveNumber += 1
		local isBossWave = (waveNumber >= bossWaveNumber)

		setWaveEnemiesRemaining(0)
		broadcastState("Preparing", {
			players = playersForNextWave,
			intermission = Config.Wave.IntermissionSeconds,
			intermissionEndsAt = Workspace:GetServerTimeNow() + Config.Wave.IntermissionSeconds,
		})
		task.wait(Config.Wave.IntermissionSeconds)
		if not running then
			break
		end

		local maxMonstersPerWave = Config.Wave.MaxMonstersPerWave or 1500
		local composition = WaveSpawnLogic.getWaveComposition(waveNumber, playersForNextWave, maxMonstersPerWave)
		local totalCap = composition and composition.totalCap or 0
		setWaveEnemiesRemaining(totalCap)

		broadcastState("InProgress", {
			players = playersForNextWave,
			enemiesRemaining = totalCap,
		})

		local remotesFolder = getRemotesFolder()
		local waveEnemiesRemainingValue = remotesFolder and remotesFolder:FindFirstChild("WaveEnemiesRemaining") or nil
		local spawnOptions = {
			playerCount = playersForNextWave,
			isRunning = function()
				return running
			end,
			onEnemyDied = function()
				if waveEnemiesRemainingValue and waveEnemiesRemainingValue:IsA("IntValue") then
					waveEnemiesRemainingValue.Value = math.max(0, waveEnemiesRemainingValue.Value - 1)
				end
			end,
		}
		WaveSpawnRunner.run(waveNumber, playersForNextWave, spawnOptions)

		local cleared = waitForWaveClear()
		if not running then
			break
		end

		if isBossWave and cleared then
			WaveService.win("BossDefeated")
			break
		end

		playersForNextWave = math.max(1, #Players:GetPlayers())
		setWaveEnemiesRemaining(0)
		broadcastState("Cleared", {
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

function WaveService.win(reason)
	if terminalState == "Won" or terminalState == "GameOver" then
		return
	end

	terminalState = "Won"
	running = false

	if not waveStateRemote then
		waveStateRemote = resolveWaveStateRemote()
	end

	broadcastState("Won", {
		reason = reason or "BossDefeated",
	})

	if type(onWinCallback) == "function" then
		onWinCallback()
	end
end

function WaveService.setOnWinCallback(callback)
	onWinCallback = callback
end

return WaveService
