--[[
	CrosshairWeaponConfig — Builds weapon lookup tables from shared config for crosshair/combat client.
	Single place for dual-wield and scoped weapon flags; extend here when adding new weapon behaviors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Constants = require(script.Parent.CrosshairConstants)

local DEFAULT_SCOPE_ZOOM_FOV = Constants.DEFAULT_SCOPE_ZOOM_FOV
local SCOPE_ZOOM_FOV_MIN = Constants.SCOPE_ZOOM_FOV_MIN
local SCOPE_ZOOM_FOV_MAX = Constants.SCOPE_ZOOM_FOV_MAX

local function buildFromConfig()
	local dualWieldWeaponIds = {}
	local scopedWeaponSettingsById = {}

	local weapons = (Config.Shop and Config.Shop.Weapons) or {}
	for _, weaponDef in ipairs(weapons) do
		if type(weaponDef) ~= "table" or type(weaponDef.Id) ~= "string" or weaponDef.Id == "" then
			continue
		end

		if weaponDef.DualWield == true then
			dualWieldWeaponIds[weaponDef.Id] = true
		end

		local isScopedWeapon = weaponDef.Scoped == true
			or weaponDef.Scope == true
			or type(weaponDef.ScopeZoomFov) == "number"
			or type(weaponDef.ScopeOverlayStyle) == "string"

		if isScopedWeapon then
			scopedWeaponSettingsById[weaponDef.Id] = {
				zoomFov = math.clamp(
					tonumber(weaponDef.ScopeZoomFov) or tonumber(weaponDef.ZoomFov) or DEFAULT_SCOPE_ZOOM_FOV,
					SCOPE_ZOOM_FOV_MIN,
					SCOPE_ZOOM_FOV_MAX
				),
				requiresFirstPerson = weaponDef.ScopeRequiresFirstPerson ~= false,
				autoScopeInFirstPerson = weaponDef.AutoScopeInFirstPerson == true,
			}
		end
	end

	return {
		dualWieldWeaponIds = dualWieldWeaponIds,
		scopedWeaponSettingsById = scopedWeaponSettingsById,
	}
end

return {
	buildFromConfig = buildFromConfig,
}
