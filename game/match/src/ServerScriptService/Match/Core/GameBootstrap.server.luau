--[[
	Match game bootstrap: place-role check, remotes setup, temp content, map vote & return-to-lobby
	flows, player lifecycle binding, and service startup. Orchestrates Core/Bootstrap modules only;
	all substantive logic lives in Core/Bootstrap/.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlaceRole = require(ServerScriptService.Shared.Matchmaking.PlaceRole)
local MatchmakingConfig = require(ServerScriptService.Shared.Matchmaking.MatchmakingConfig)
local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local SettingsService = require(ServerScriptService.Shared.Settings.SettingsService)

local Match = script.Parent.Parent
local WaveService = require(Match.Waves.WaveService)
local ShopService = require(Match.Shop.ShopService)
local AmmoPickupService = require(Match.Pickups.AmmoPickupService)
local ClassService = require(Match.Classes.ClassService)
local DifficultyService = require(Match.Difficulty.DifficultyService)
local SpectatorService = require(Match.Spectator.SpectatorService)
local OfflinePlayerDataEditor = require(Match.Admin.OfflinePlayerDataEditor)

local BootstrapUtil = require(script.Parent.Bootstrap.BootstrapUtil)
local RemotesSetup = require(script.Parent.Bootstrap.RemotesSetup)
local TempContentSetup = require(script.Parent.Bootstrap.TempContentSetup)
local MapVoteFlow = require(script.Parent.Bootstrap.MapVoteFlow)
local ReturnToLobbyFlow = require(script.Parent.Bootstrap.ReturnToLobbyFlow)
local PlayerLifecycleBootstrap = require(script.Parent.Bootstrap.PlayerLifecycleBootstrap)
local MatchSetup = require(script.Parent.Bootstrap.MatchSetup)

if not PlaceRole.shouldRunMatchSystems() then
	warn(("[GameBootstrap] Skipping match systems for place role '%s' (placeId=%s)."):format(
		PlaceRole.getRole(), tostring(game.PlaceId)))
	return
end

local gameOverTriggered = false
local winTriggered = false

local function getIsGameOver()
	return gameOverTriggered or winTriggered
end

local remotes = RemotesSetup.run(Config.Remotes)

if remotes.ReturnToLobby then
	remotes.ReturnToLobby.OnServerEvent:Connect(
		ReturnToLobbyFlow.createHandler(MatchmakingConfig, remotes.TeleportLoading, PlaceRole.shouldRunMatchSystems)
	)
end

MapVoteFlow.init(remotes)

if remotes.MapVote then
	remotes.MapVote.OnServerEvent:Connect(function(player, payload)
		MapVoteFlow.onVoteSubmitted(player, payload, getIsGameOver)
	end)
end

local function triggerGameOver()
	if gameOverTriggered then return end
	if not PlaceRole.shouldRunMatchSystems() then return end
	gameOverTriggered = true
	Workspace:SetAttribute("GameOver", true)
	WaveService.gameOver("AllPlayersDead")
	task.spawn(function()
		MapVoteFlow.run(getIsGameOver)
	end)
end

local function triggerWin()
	if winTriggered then return end
	if not PlaceRole.shouldRunMatchSystems() then return end
	winTriggered = true
	gameOverTriggered = true
	Workspace:SetAttribute("GameOver", true)
	Workspace:SetAttribute("Won", true)
	task.spawn(function()
		MapVoteFlow.run(getIsGameOver)
	end)
end

local bindPlayerSystems = PlayerLifecycleBootstrap.createBindPlayerSystems({
	configPlayer = Config.Player,
	playerDataService = PlayerDataService,
	spectatorService = SpectatorService,
	getIsGameOver = function()
		return gameOverTriggered
	end,
	triggerGameOver = triggerGameOver,
	sendMapVoteSnapshot = function(player)
		MapVoteFlow.getSnapshotForPlayer(player, getIsGameOver())
	end,
	isMatchRunningForLateJoin = function()
		return not gameOverTriggered and #Players:GetPlayers() > 1
	end,
})

SpectatorService.start()

local templateFolder = BootstrapUtil.ensureFolder(ServerStorage, Config.Enemy.TemplateFolderName)
local spawnFolder = BootstrapUtil.ensureFolder(Workspace, Config.Enemy.SpawnFolderName)
BootstrapUtil.ensureFolder(Workspace, Config.Enemy.ContainerName)
TempContentSetup.ensureTempEnemyTemplate(templateFolder)
TempContentSetup.ensureTempSpawnPoint(spawnFolder)
MatchSetup.ensureDifficultyAttribute(Workspace, function()
	return DifficultyService.getCurrentDifficulty()
end)
Workspace:SetAttribute("GameOver", false)

Players.CharacterAutoLoads = false
Players.PlayerAdded:Connect(bindPlayerSystems)
Players.PlayerRemoving:Connect(function(player)
	SpectatorService.onPlayerRemove(player)
	ReturnToLobbyFlow.clearInFlight(player)
	if MapVoteFlow.removePlayerVote(player) then
		MapVoteFlow.broadcastUpdate()
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerSystems(player)
end

PlayerDataService.start()
OfflinePlayerDataEditor.start()
ClassService.start()
SettingsService.start()
ShopService.start()
AmmoPickupService.start()
WaveService.setOnWinCallback(triggerWin)
WaveService.start()
