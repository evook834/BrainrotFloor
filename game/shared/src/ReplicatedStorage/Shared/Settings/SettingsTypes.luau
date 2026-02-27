--[[
	SettingsTypes - Shared type definitions for the Settings system.
	Used by client controllers and menu so new settings fields stay in sync.
]]

export type SettingsState = {
	musicVolume: number,
	musicMuted: boolean,
	sfxVolume: number,
	sfxMuted: boolean,
	hudScale: number,
	hudPositions: { [string]: any },
}

export type RunOptions = {
	hudMoveModeAttribute: string?,
	canReturnToLobby: boolean?,
}

return {}
