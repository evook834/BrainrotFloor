--[[
	Default player data template for DataService (ProfileStore).
	JSON-compatible only. Used for new players and reconciliation.
]]

local PlayerConfig = require(script.Parent.PlayerConfig)

local SETTINGS_SCHEMA_VERSION = 1

return {
	settings = {
		schemaVersion = SETTINGS_SCHEMA_VERSION,
		audio = {
			musicVolume = 1,
			musicMuted = false,
			sfxVolume = 1,
			sfxMuted = false,
		},
		hud = {
			scale = 1,
			positions = {},
		},
	},
	classes = {
		selectedClassId = "",
		progressByClassId = {},
	},
	money = (PlayerConfig and PlayerConfig.StartingMoney) or 0,
	inventory = {},
}
