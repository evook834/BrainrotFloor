local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local FriendService = require(ServerScriptService.Shared.Friends.FriendService)
local SettingsService = require(ServerScriptService.Shared.Settings.SettingsService)

PlayerDataService.start()
SettingsService.start()
FriendService.start()
