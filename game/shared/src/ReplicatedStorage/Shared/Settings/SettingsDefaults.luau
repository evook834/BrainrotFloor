--[[
	SettingsDefaults - Builds default settings state from SettingsConfig.
	Single source for initial client state; server uses its own sanitizeSettings defaults.
]]

local SettingsConfig = require(script.Parent:WaitForChild("SettingsConfig"))
local SettingsTypes = require(script.Parent:WaitForChild("SettingsTypes"))

type SettingsState = SettingsTypes.SettingsState

local function getDefaultSettingsState(): SettingsState
	return {
		musicVolume = SettingsConfig.Audio.MusicVolume.Default,
		musicMuted = false,
		sfxVolume = SettingsConfig.Audio.SfxVolume.Default,
		sfxMuted = false,
		hudScale = SettingsConfig.Hud.Scale.Default,
		hudPositions = {},
	}
end

return {
	getDefaultSettingsState = getDefaultSettingsState,
}
