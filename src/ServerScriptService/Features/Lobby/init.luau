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

-- Lobby features (Core modules)
require(script.Core.LobbyMatchmaker)
require(script.Core.LobbySettings)
require(script.Core.LobbyClassRemotes)
