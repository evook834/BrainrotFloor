--[[
	Lobby entry point - starts lobby systems when running as lobby place.
	Runs LobbyMatchmaker, LobbySettings, and LobbyClassRemotes.
]]
local ServerScriptService = game:GetService("ServerScriptService")

local PlaceRole = require(ServerScriptService.Shared.Matchmaking.PlaceRole)
local Shared = ServerScriptService.Shared

if not PlaceRole.shouldRunLobbySystems() then
	return
end

-- Start Lobby systems
require(Shared.PlayerData.PlayerDataService).start()
require(Shared.Settings.SettingsService).start()
require(Shared.Friends.FriendService).start()

-- Setup remotes for client use (WaveState, ReturnToLobby, MapVote, etc.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesSetup = require(ServerScriptService.Features.Core.Bootstrap.RemotesSetup)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
RemotesSetup.run(GameConfig.Remotes)

-- Lobby features (Core modules)
require(script.Core.LobbyMatchmaker)
require(script.Core.LobbySettings)
require(script.Core.LobbyClassRemotes)
