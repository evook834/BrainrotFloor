--[[
	AmmoHudPayloadUtil — Pure helpers for reading tool ammo state and building display data.
	No UI or remotes; used by AmmoHudController.
]]

local AmmoHudConstants = require(script.Parent.AmmoHudConstants)

export type AmmoSnapshot = {
	weaponName: string,
	currentAmmo: number,
	maxAmmo: number,
	reserveAmmo: number,
	totalAmmo: number,
	isReloading: boolean,
}

export type AmmoDisplay = {
	weaponName: string,
	ammoText: string,
	detailsText: string,
	statusText: string?,
	statusColor: Color3?,
}

local function toWholeNumber(value: any, defaultValue: number?): number?
	local numeric = tonumber(value)
	if numeric == nil then
		return defaultValue
	end
	return math.max(0, math.floor(numeric + 0.5))
end

function readAmmoSnapshot(tool: Instance?): AmmoSnapshot?
	if not tool or not tool:IsA("Tool") then
		return nil
	end
	local currentAmmo = toWholeNumber(tool:GetAttribute("CurrentAmmo"), nil)
	local maxAmmo = toWholeNumber(tool:GetAttribute("MaxAmmo"), nil)
	if currentAmmo == nil or maxAmmo == nil or maxAmmo <= 0 then
		return nil
	end
	local reserveAmmo = toWholeNumber(tool:GetAttribute("ReserveAmmo"), 0)
	local totalAmmo = toWholeNumber(tool:GetAttribute("TotalAmmo"), currentAmmo + reserveAmmo)
	if totalAmmo < currentAmmo then
		totalAmmo = currentAmmo
	end
	return {
		weaponName = tostring(tool.Name or "Weapon"),
		currentAmmo = currentAmmo,
		maxAmmo = maxAmmo,
		reserveAmmo = reserveAmmo,
		totalAmmo = totalAmmo,
		isReloading = tool:GetAttribute("IsReloading") == true,
	}
end

function buildDisplayFromSnapshot(snapshot: AmmoSnapshot): AmmoDisplay
	local weaponName = string.upper(snapshot.weaponName)
	local ammoText = string.format("%d / %d", snapshot.currentAmmo, snapshot.totalAmmo)
	local detailsText = string.format("MAG %d   RESERVE %d", snapshot.maxAmmo, snapshot.reserveAmmo)
	local statusText: string? = nil
	local statusColor: Color3? = nil
	if snapshot.currentAmmo <= 0 and snapshot.reserveAmmo <= 0 then
		statusText = AmmoHudConstants.STATUS_OUT_OF_AMMO
		statusColor = AmmoHudConstants.COLOR_STATUS_OUT_OF_AMMO
	elseif snapshot.isReloading then
		statusText = AmmoHudConstants.STATUS_RELOADING
		statusColor = AmmoHudConstants.COLOR_STATUS_RELOADING
	end
	return {
		weaponName = weaponName,
		ammoText = ammoText,
		detailsText = detailsText,
		statusText = statusText,
		statusColor = statusColor,
	}
end

local PREVIEW_DISPLAY: AmmoDisplay = {
	weaponName = AmmoHudConstants.PREVIEW_WEAPON_NAME,
	ammoText = AmmoHudConstants.PREVIEW_AMMO_TEXT,
	detailsText = AmmoHudConstants.PREVIEW_DETAILS_TEXT,
	statusText = nil,
	statusColor = nil,
}

function buildFallbackDisplay(tool: Instance?): AmmoDisplay
	local name = (tool and tool:IsA("Tool") and tool.Name) or "Weapon"
	return {
		weaponName = string.upper(name),
		ammoText = "— / —",
		detailsText = "—",
		statusText = nil,
		statusColor = nil,
	}
end

return {
	readAmmoSnapshot = readAmmoSnapshot,
	buildDisplayFromSnapshot = buildDisplayFromSnapshot,
	buildFallbackDisplay = buildFallbackDisplay,
	PREVIEW_DISPLAY = PREVIEW_DISPLAY,
}
