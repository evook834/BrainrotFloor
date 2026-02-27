--[[
	ShopUiMessages — User-facing copy for the weapon shop UI.
	Single source for strings so behaviour and localization can be extended in one place.
]]

local ShopUiMessages = {
	-- Controller: shop actions
	ShopActionFailedRemote = "Shop action failed: remote error.",
	ShopActionSuccessDefault = "Shop action successful.",
	ShopActionDeniedDefault = "Shop action denied.",

	-- Controller: open/empty state
	OpenStatusHint = "Buy weapons or refill owned ammo.",
	EmptyCatalogStatus = "No weapons available for your current class.",

	-- CatalogDisplay: subtitle (success path)
	SubtitleStoreOpen = "Buy only between waves | Store OPEN",
	SubtitleStoreClosed = "Store CLOSED while wave is active (%s)",

	-- CatalogDisplay: failure
	CouldNotLoadShopData = "Could not load shop data.",
	UnknownWaveState = "Unknown",
	StoreUnavailable = "Store unavailable (%s)",
	RefillAllOwned = "Refill All Owned",

	-- CatalogDisplay: refill-all button
	RefillAllWaveActive = "Refill All (Wave Active)",
	RefillAllOwnedCost = "Refill All Owned ($%d)",
	NoOwnedAmmoWeapons = "No Owned Ammo Weapons",
	AllOwnedAmmoFull = "All Owned Ammo Full",

	-- CatalogDisplay: weapon row button
	RowNoAmmo = "No Ammo",
	RowWaveActive = "Wave Active",
	RowRefillCost = "Refill $%d",
	RowFullAmmo = "Full Ammo",
	RowNeedsUpgrade = "Needs %s",
	RowBuy = "Buy",
}

return ShopUiMessages
