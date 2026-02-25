--[[
	ShopConstants — Shared constants for shop, weapon combat, and sentry turrets.
	Used by ShopService (and optionally SentryCombat / WeaponCombat).
]]

local ShopConstants = {}

-- Fire cone / aim
ShopConstants.FIRE_CONE_HALF_ANGLE_DEGREES = 40
ShopConstants.FIRE_CONE_MIN_DOT = math.cos(math.rad(ShopConstants.FIRE_CONE_HALF_ANGLE_DEGREES))

-- Burn DoT
ShopConstants.BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS = 0.5

-- Sentry turrets
ShopConstants.SENTRY_TURRET_FOLDER_NAME = "SentryTurrets"
ShopConstants.MAX_SENTRY_COUNT_PER_PLAYER = 3
ShopConstants.SENTRY_REPAIR_INTERRUPT_SECONDS = 0.45
ShopConstants.DEFAULT_SENTRY_MAX_AMMO = 300
ShopConstants.TURRET_ROCKET_BURST_MODE_TOKEN = "rocketburst"
ShopConstants.DEFAULT_TURRET_ROCKET_SPREAD_DEGREES = 4

return ShopConstants
