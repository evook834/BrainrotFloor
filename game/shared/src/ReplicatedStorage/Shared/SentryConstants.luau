--[[
	SentryConstants — Shared sentry config used by client and server.
	Single source for workspace folder name, model attributes, and UI element names.
]]

local SentryConstants = {}

-- Workspace
SentryConstants.SENTRY_TURRET_FOLDER_NAME = "SentryTurrets"

-- Model attributes (set on sentry Model; used by server and by client/EnemyAI for detection)
SentryConstants.ATTR_IS_SENTRY_TURRET = "IsSentryTurret"
SentryConstants.ATTR_SENTRY_OWNER_USER_ID = "SentryOwnerUserId"
SentryConstants.ATTR_SENTRY_OWNER_NAME = "SentryOwnerName"
SentryConstants.ATTR_SENTRY_WEAPON_ID = "SentryWeaponId"
SentryConstants.ATTR_TURRET_MAX_HEALTH = "TurretMaxHealth"
SentryConstants.ATTR_TURRET_HEALTH = "TurretHealth"
SentryConstants.ATTR_TURRET_LAST_DAMAGED_AT = "TurretLastDamagedAt"
SentryConstants.ATTR_TURRET_MAX_AMMO = "TurretMaxAmmo"
SentryConstants.ATTR_TURRET_AMMO = "TurretAmmo"
SentryConstants.ATTR_TURRET_OUT_OF_AMMO = "TurretOutOfAmmo"

-- Turret health bar UI (BillboardGui name and child TextLabel name; server builds, server sync reads)
SentryConstants.TURRET_BILLBOARD_NAME = "TurretHealthBar"
SentryConstants.TURRET_AMMO_LABEL_NAME = "AmmoText"

return SentryConstants
