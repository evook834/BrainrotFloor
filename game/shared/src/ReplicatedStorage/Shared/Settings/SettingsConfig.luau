--[[
	SettingsConfig - Shared configuration for the Settings system.
	Used by both client (SettingsHudLayoutController, SettingsMenuUi) and server (SettingsService).
]]

return {
	-- Audio settings
	Audio = {
		MusicVolume = {
			Default = 1,
			Min = 0,
			Max = 1,
		},
		SfxVolume = {
			Default = 1,
			Min = 0,
			Max = 1,
		},
	},

	-- HUD settings
	Hud = {
		Scale = {
			Default = 1,
			Min = 0.6,
			Max = 1.45,
			Step = 0.05,
		},
		MaxPositionEntries = 120,
	},

	-- HUD move mode
	HudMoveMode = {
		-- Attribute name used on PlayerGui to track HUD move mode state
		Attribute = "LobbyHudMoveModeEnabled",
	},

	-- Spectator mode (HUDs that hide when spectating listen to this)
	SpectatorMode = {
		Attribute = "SpectatorModeActive",
	},

	-- HUD roots that cannot be dragged by the user
	NonDraggableHudRoots = {
		["CombatCrosshairUi/CrosshairRoot"] = true,
		["BrainrotHud/RespawnTimer"] = true,
		["BrainrotHud/GameOverOverlay"] = true,
	},

	-- HUD ScreenGui names that contain draggable HUD elements
	HudScreenGuiNames = {
		BrainrotHud = true,
		ClassXpBarHud = true,
		SprintStaminaHud = true,
		CombatCrosshairUi = true,
		AmmoHud = true,
	},

	-- HUD roots that require special handling (e.g., special scale treatment)
	SpecialHudRoots = {
		["ClassXpBarHud/XpContainer"] = {
			UseAttributeScale = true,
		},
	},

	-- Save debounce delay (seconds) - time to wait after last change before saving
	SaveDebounceDelay = 0.8,
}
