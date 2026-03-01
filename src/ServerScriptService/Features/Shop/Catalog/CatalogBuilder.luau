--[[
	CatalogBuilder — Builds weapon catalog for shop UI.
	Creates the list of weapons with pricing, stats, and owned status.
]]

local CatalogBuilder = {}

local function roundWholeNumber(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

-- Build catalog for a single weapon
function CatalogBuilder.buildWeaponEntry(player, weaponDef, context)
	local baseRange = math.max(0, tonumber(weaponDef.Range) or 0)

	-- Calculate class-based range multiplier
	local rangeMultiplier = 1
	if context.classService and context.classService.getWeaponBulletRangeMultiplier then
		rangeMultiplier = math.max(0.1, context.classService.getWeaponBulletRangeMultiplier(player, weaponDef))
	end

	local effectiveRange = math.floor((baseRange * rangeMultiplier) + 0.5)
	local rangeBonusPct = math.max(0, (rangeMultiplier - 1) * 100)

	-- Get pricing info
	local cost = context.getWeaponCostForPlayer(player, weaponDef)

	-- Check ownership and upgrade requirements
	local isOwned = context.playerOwnsWeapon and context.playerOwnsWeapon(player, weaponDef.Id) or false
	local requiredWeaponId = nil
	local requiredWeaponName = nil
	local isUpgradeLocked = false

	if context.getRequiredOwnedWeaponId then
		requiredWeaponId = context.getRequiredOwnedWeaponId(weaponDef, context.weaponById)
		if requiredWeaponId and context.getRequiredOwnedWeaponName then
			requiredWeaponName = context.getRequiredOwnedWeaponName(requiredWeaponId, context.weaponById)
			isUpgradeLocked = not (context.playerOwnsWeapon and context.playerOwnsWeapon(player, requiredWeaponId))
		end
	end

	-- Get ammo quote if owned
	local refillQuote = nil
	if context.quotesByWeaponId and isOwned then
		refillQuote = context.quotesByWeaponId[weaponDef.Id]
	end

	local refillCost = refillQuote and refillQuote.cost or 0
	local canRefill = refillQuote and refillQuote.canRefill or false
	local isRefillable = refillQuote and refillQuote.isRefillable or (context.getMagazineSize and context.getMagazineSize(weaponDef, player) ~= nil)

	return {
		id = weaponDef.Id,
		name = weaponDef.DisplayName,
		weaponClass = context.resolveWeaponClass and context.resolveWeaponClass(weaponDef) or "Unknown",
		cost = cost,
		damage = weaponDef.Damage,
		range = baseRange,
		effectiveRange = effectiveRange,
		rangeBonusPct = rangeBonusPct,
		cooldown = weaponDef.Cooldown,
		magazineSize = context.getMagazineSize and context.getMagazineSize(weaponDef, player),
		reloadSeconds = context.getReloadSeconds and context.getReloadSeconds(weaponDef, player),
		requiresWeaponId = requiredWeaponId,
		requiresWeaponName = requiredWeaponName,
		upgradeLocked = isUpgradeLocked,
		owned = isOwned,
		isRefillable = isRefillable,
		refillCost = isOwned and refillCost or 0,
		canRefill = isOwned and canRefill or false,
		currentAmmoTotal = refillQuote and refillQuote.currentTotalAmmo or nil,
		maxAmmoTotal = refillQuote and refillQuote.maxTotalAmmo or nil,
		missingAmmo = refillQuote and refillQuote.missingAmmo or nil,
	}
end

-- Build complete catalog for player
function CatalogBuilder.buildCatalogForPlayer(player, context)
	local canPurchase, waveState = CatalogBuilder.canPurchaseNow(context.remotesFolder, context.config)

	-- Build quotes if context provides them
	local quotesByWeaponId = {}
	if context.quotesByWeaponId then
		quotesByWeaponId = context.quotesByWeaponId
	end

	local weapons = {}
	for _, weaponDef in ipairs(((context.config or {}).Shop or {}).Weapons or {}) do
		if context.canPlayerUseWeapon and not context.canPlayerUseWeapon(player, weaponDef) then
			continue
		end

		table.insert(weapons, CatalogBuilder.buildWeaponEntry(player, weaponDef, {
			quotesByWeaponId = quotesByWeaponId,
			weaponById = context.weaponById or {},
			getWeaponCostForPlayer = context.getWeaponCostForPlayer,
			getRequiredOwnedWeaponId = context.getRequiredOwnedWeaponId,
			getRequiredOwnedWeaponName = context.getRequiredOwnedWeaponName,
			getMagazineSize = context.getMagazineSize,
			getReloadSeconds = context.getReloadSeconds,
			resolveWeaponClass = context.resolveWeaponClass,
			playerOwnsWeapon = context.playerOwnsWeapon,
			classService = context.classService,
		}))
	end

	-- Sort weapons by cost
	table.sort(weapons, function(a, b)
		return a.cost < b.cost
	end)

	-- Build summary stats
	local refillSummary = context.refillSummary or {
		refillAllCost = 0,
		ownedWeapons = 0,
		ownedRefillableWeapons = 0,
		refillableWeaponsWithMissingAmmo = 0,
	}

	return {
		success = true,
		canPurchase = canPurchase,
		waveState = waveState,
		weapons = weapons,
		refillAllCost = refillSummary.refillAllCost or 0,
		canRefillAll = (refillSummary.refillAllCost or 0) > 0,
		ownedWeapons = refillSummary.ownedWeapons or 0,
		ownedRefillableWeapons = refillSummary.ownedRefillableWeapons or 0,
		refillableWeaponsWithMissingAmmo = refillSummary.refillableWeaponsWithMissingAmmo or 0,
	}
end

-- Check if shop is open for purchases
function CatalogBuilder.canPurchaseNow(remotesFolder, config)
	if not remotesFolder then
		return false, "Unknown"
	end

	local waveState = remotesFolder:GetAttribute("CurrentWaveState")
	if type(waveState) ~= "string" then
		return false, "Unknown"
	end

	local allowedStates = ((config or {}).Shop or {}).PurchaseAllowedStates or {}
	if type(allowedStates[waveState]) == "boolean" then
		return allowedStates[waveState], waveState
	end

	return waveState ~= "InProgress", waveState
end

return CatalogBuilder
