-- Re-export shared SettingsService (player data is in DataService via PlayerDataService).
local ServerScriptService = game:GetService("ServerScriptService")
return require(ServerScriptService.Shared.Settings.SettingsService)
