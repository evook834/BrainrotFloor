local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local SettingsService = require(ServerScriptService.Shared.Settings.SettingsService)

PlayerDataService.start()
SettingsService.start()
