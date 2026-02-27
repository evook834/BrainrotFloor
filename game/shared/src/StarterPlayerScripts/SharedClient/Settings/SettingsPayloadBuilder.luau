--[[
	SettingsPayloadBuilder - Builds the save payload for SettingsSave remote.
	Single place for payload shape so new categories stay in sync.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("SettingsTypes"))

type SettingsState = SettingsTypes.SettingsState

export type SerializedPosition = {
	xScale: number,
	xOffset: number,
	yScale: number,
	yOffset: number,
}

-- Builds the table to send via SettingsSave. If serializedPositions is provided,
-- it is used for hud.positions; otherwise settingsState.hudPositions is used.
function buildSavePayload(settingsState: SettingsState, serializedPositions: { [string]: SerializedPosition }?)
	local positions = serializedPositions or settingsState.hudPositions
	return {
		audio = {
			musicVolume = settingsState.musicVolume,
			musicMuted = settingsState.musicMuted,
			sfxVolume = settingsState.sfxVolume,
			sfxMuted = settingsState.sfxMuted,
		},
		hud = {
			scale = settingsState.hudScale,
			positions = positions,
		},
	}
end

return {
	buildSavePayload = buildSavePayload,
}
