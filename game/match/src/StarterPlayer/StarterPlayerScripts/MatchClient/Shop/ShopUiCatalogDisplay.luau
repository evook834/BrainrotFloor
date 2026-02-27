--[[
	ShopUiCatalogDisplay — Pure display logic for shop catalog and weapon rows.
	Builds info text, button state, and failure messages from catalog/weapon data.
	Single place to extend when adding new catalog fields or row types.
]]

local ShopUiConstants = require(script.Parent:WaitForChild("ShopUiConstants"))
local ShopUiMessages = require(script.Parent:WaitForChild("ShopUiMessages"))

local function roundWholeNumber(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

function extractCatalogFailure(catalog)
	local failureMessage = ShopUiMessages.CouldNotLoadShopData
	local waveState = ShopUiMessages.UnknownWaveState
	if type(catalog) == "table" then
		if type(catalog.message) == "string" and catalog.message ~= "" then
			failureMessage = catalog.message
		end
		if type(catalog.waveState) == "string" and catalog.waveState ~= "" then
			waveState = catalog.waveState
		end
	end
	return failureMessage, waveState
end

function buildWeaponInfoText(weapon)
	local ammoLine = ""
	if type(weapon.magazineSize) == "number" and weapon.magazineSize > 0 then
		local reloadSeconds = tonumber(weapon.reloadSeconds) or 0
		ammoLine = string.format("  MAG %d  RELOAD %.1fs", weapon.magazineSize, reloadSeconds)
	end

	local displayedRange = math.max(0, math.floor((tonumber(weapon.effectiveRange) or tonumber(weapon.range) or 0) + 0.5))
	local rangeText = string.format("RANGE %d", displayedRange)
	local rangeBonusPct = tonumber(weapon.rangeBonusPct) or 0
	if rangeBonusPct >= 0.05 then
		rangeText = string.format("RANGE %d (+%.1f%% class)", displayedRange, rangeBonusPct)
	end

	local ownedAmmoLine = ""
	if weapon.owned and type(weapon.currentAmmoTotal) == "number" and type(weapon.maxAmmoTotal) == "number" and weapon.maxAmmoTotal > 0 then
		local currentTotal = roundWholeNumber(weapon.currentAmmoTotal)
		local maxTotal = roundWholeNumber(weapon.maxAmmoTotal)
		ownedAmmoLine = string.format("  AMMO %d/%d", currentTotal, maxTotal)
	end

	local upgradeLine = ""
	if not weapon.owned and type(weapon.requiresWeaponName) == "string" and weapon.requiresWeaponName ~= "" then
		if weapon.upgradeLocked == true then
			upgradeLine = string.format("  REQUIRES %s", string.upper(weapon.requiresWeaponName))
		else
			upgradeLine = string.format("  UPGRADE FROM %s", string.upper(weapon.requiresWeaponName))
		end
	end

	return string.format(
		"%s (%s)  |  $%d\nDMG %d  %s  CD %.2fs%s%s%s",
		weapon.name or weapon.id or "?",
		weapon.weaponClass or "Weapon",
		weapon.cost or 0,
		weapon.damage or 0,
		rangeText,
		weapon.cooldown or 0,
		ammoLine,
		ownedAmmoLine,
		upgradeLine
	)
end

export type RefillAllButtonState = {
	text: string,
	backgroundColor: Color3,
	enabled: boolean,
	autoButtonColor: boolean,
}

function getRefillAllButtonState(catalog): RefillAllButtonState
	local canPurchase = catalog.canPurchase == true
	local refillAllCost = roundWholeNumber(catalog.refillAllCost)
	local canRefillAll = catalog.canRefillAll == true and refillAllCost > 0

	if not canPurchase then
		return {
			text = ShopUiMessages.RefillAllWaveActive,
			backgroundColor = ShopUiConstants.ButtonClosed,
			enabled = false,
			autoButtonColor = false,
		}
	end

	if canRefillAll then
		return {
			text = string.format(ShopUiMessages.RefillAllOwnedCost, refillAllCost),
			backgroundColor = ShopUiConstants.ButtonEnabled,
			enabled = true,
			autoButtonColor = true,
		}
	end

	local ownedRefillable = roundWholeNumber(catalog.ownedRefillableWeapons)
	local text = (ownedRefillable <= 0) and ShopUiMessages.NoOwnedAmmoWeapons or ShopUiMessages.AllOwnedAmmoFull
	return {
		text = text,
		backgroundColor = ShopUiConstants.ButtonDisabled,
		enabled = false,
		autoButtonColor = false,
	}
end

export type WeaponRowButtonState = {
	disabled: boolean,
	isAmmoPurchase: boolean,
	text: string,
	backgroundColor: Color3,
}

function getWeaponRowButtonState(weapon, canPurchase): WeaponRowButtonState
	local disabled = false
	local isAmmoPurchase = false
	local text = ShopUiMessages.RowBuy
	local backgroundColor = ShopUiConstants.ButtonEnabled
	local refillCost = roundWholeNumber(weapon.refillCost)

	if weapon.owned then
		if weapon.isRefillable ~= true then
			disabled = true
			text = ShopUiMessages.RowNoAmmo
			backgroundColor = ShopUiConstants.ButtonDisabled
		elseif not canPurchase then
			disabled = true
			text = ShopUiMessages.RowWaveActive
			backgroundColor = ShopUiConstants.ButtonClosed
		elseif weapon.canRefill == true and refillCost > 0 then
			isAmmoPurchase = true
			text = string.format(ShopUiMessages.RowRefillCost, refillCost)
		else
			disabled = true
			text = ShopUiMessages.RowFullAmmo
			backgroundColor = ShopUiConstants.ButtonDisabled
		end
	elseif not canPurchase then
		disabled = true
		text = ShopUiMessages.RowWaveActive
		backgroundColor = ShopUiConstants.ButtonClosed
	elseif weapon.upgradeLocked == true then
		disabled = true
		text = string.format(ShopUiMessages.RowNeedsUpgrade, tostring(weapon.requiresWeaponName or weapon.requiresWeaponId or "Upgrade"))
		backgroundColor = ShopUiConstants.ButtonLocked
	end

	return {
		disabled = disabled,
		isAmmoPurchase = isAmmoPurchase,
		text = text,
		backgroundColor = backgroundColor,
	}
end

export type CatalogFailureDisplay = {
	subtitleText: string,
	subtitleColor: Color3,
	statusMessage: string,
	statusColor: Color3,
	refillText: string,
	refillColor: Color3,
}

function getCatalogFailureDisplay(catalog): CatalogFailureDisplay
	local failureMessage, waveState = extractCatalogFailure(catalog)
	return {
		subtitleText = string.format(ShopUiMessages.StoreUnavailable, waveState),
		subtitleColor = ShopUiConstants.SubtitleClosed,
		statusMessage = failureMessage,
		statusColor = ShopUiConstants.StatusError,
		refillText = ShopUiMessages.RefillAllOwned,
		refillColor = ShopUiConstants.ButtonDisabled,
	}
end

export type SubtitleDisplay = {
	text: string,
	color: Color3,
}

function getSubtitleForCatalog(catalog): SubtitleDisplay
	local canPurchase = catalog.canPurchase == true
	local waveState = catalog.waveState or ShopUiMessages.UnknownWaveState
	if canPurchase then
		return {
			text = ShopUiMessages.SubtitleStoreOpen,
			color = ShopUiConstants.SubtitleOpen,
		}
	end
	return {
		text = string.format(ShopUiMessages.SubtitleStoreClosed, waveState),
		color = ShopUiConstants.SubtitleClosed,
	}
end

return {
	extractCatalogFailure = extractCatalogFailure,
	buildWeaponInfoText = buildWeaponInfoText,
	getRefillAllButtonState = getRefillAllButtonState,
	getWeaponRowButtonState = getWeaponRowButtonState,
	getCatalogFailureDisplay = getCatalogFailureDisplay,
	getSubtitleForCatalog = getSubtitleForCatalog,
}
