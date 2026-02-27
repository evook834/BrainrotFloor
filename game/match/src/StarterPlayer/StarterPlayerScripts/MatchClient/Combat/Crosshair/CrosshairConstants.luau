--[[
	CrosshairConstants — Shared constants for crosshair, scope, dual-wield, and sentry placement.
]]

return {
	-- Cursor
	DOT_CURSOR_ICON = "rbxasset://textures/MouseLockedCursor.png",

	-- Scope
	DEFAULT_SCOPE_ZOOM_FOV = 18,
	SCOPE_ZOOM_FOV_MIN = 8,
	SCOPE_ZOOM_FOV_MAX = 70,
	SCOPE_CIRCLE_MASK_SEGMENTS = 128,
	SCOPE_UI_EXEMPT_GUI_NAMES = {
		AmmoHud = true,
	},

	-- Weapon IDs that hide the weapon model while scoped
	HIDE_WEAPON_MODEL_WHILE_SCOPED_IDS = {
		awp = true,
	},

	-- Sentry
	SENTRY_DEPLOYER_CLASS_TOKEN = "sentrydeployer",
	SENTRY_PREVIEW_VALID_COLOR = Color3.fromRGB(90, 240, 135),
	SENTRY_PREVIEW_INVALID_COLOR = Color3.fromRGB(235, 95, 95),
	SENTRY_PREVIEW_PADDING = Vector3.new(0.25, 0.25, 0.25),
	WEAPON_EFFECTS_FOLDER_NAME = "WeaponEffects",

	-- Aim
	AIM_UPDATE_INTERVAL = 0.03,
	AIM_RAYCAST_MAX_DISTANCE = 1800,
	SENTRY_PLACEMENT_DEFAULT_MAX_DISTANCE = 180,
}
