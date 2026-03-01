--[[
	AmmoInventory — Ammo refill quote calculations for owned weapons.
	Handles tool-based weapons and sentry turrets.
]]

local AmmoInventory = {}

local function roundWholeNumber(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

-- Build ammo refill quote for a tool-based weapon
function AmmoInventory.buildToolQuote(player, weaponDef, tool, pricingConfig, context)
	if not (player and player:IsA("Player")) then
		return nil
	end
	if not weaponDef or type(weaponDef) ~= "table" or not weaponDef.Id then
		return nil
	end
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local ammoSnapshot = context.getToolAmmoSnapshot and context.getToolAmmoSnapshot(tool, weaponDef, player)
	if not ammoSnapshot then
		return {
			weaponId = weaponDef.Id,
			tool = tool,
			refillKind = "Tool",
			isRefillable = false,
			canRefill = false,
			cost = 0,
			currentTotalAmmo = nil,
			maxTotalAmmo = nil,
			missingAmmo = nil,
		}
	end

	local refillCost, canRefill
	if context.calculateRefillCost then
		refillCost, canRefill = context.calculateRefillCost(player, weaponDef, ammoSnapshot, pricingConfig, context)
	else
		-- Fallback if calculateRefillCost not in context
		local maxTotalAmmo = ammoSnapshot.maxTotalAmmo
		local missingAmmo = ammoSnapshot.missingAmmo
		if maxTotalAmmo <= 0 or missingAmmo <= 0 then
			refillCost, canRefill = 0, false
		else
			refillCost, canRefill = math.max(0, math.floor((missingAmmo / maxTotalAmmo) * 50) + 1), true
		end
	end

	return {
		weaponId = weaponDef.Id,
		tool = tool,
		refillKind = "Tool",
		isRefillable = true,
		canRefill = canRefill,
		cost = math.max(0, refillCost),
		currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
		maxTotalAmmo = ammoSnapshot.maxTotalAmmo,
		missingAmmo = ammoSnapshot.missingAmmo,
	}
end

-- Build ammo refill quote for sentry turret weapons
function AmmoInventory.buildSentryQuote(player, weaponDef, sentryRecords, pricingConfig, context)
	if not (player and player:IsA("Player")) then
		return nil
	end
	if not weaponDef or type(weaponDef) ~= "table" or not weaponDef.Id then
		return nil
	end
	if not sentryRecords or type(sentryRecords) ~= "table" or #sentryRecords == 0 then
		return nil
	end

	local ammoSnapshot = context.getSentryAmmoSnapshot and context.getSentryAmmoSnapshot(sentryRecords, weaponDef)
	if not ammoSnapshot then
		return nil
	end

	local refillCost, canRefill
	if context.calculateRefillCost then
		refillCost, canRefill = context.calculateRefillCost(player, weaponDef, ammoSnapshot, pricingConfig, context)
	else
		local maxTotalAmmo = ammoSnapshot.maxTotalAmmo
		local missingAmmo = ammoSnapshot.missingAmmo
		if maxTotalAmmo <= 0 or missingAmmo <= 0 then
			refillCost, canRefill = 0, false
		else
			refillCost, canRefill = math.max(0, math.floor((missingAmmo / maxTotalAmmo) * 50) + 1), true
		end
	end

	return {
		weaponId = weaponDef.Id,
		sentryRecords = sentryRecords,
		refillKind = "Sentry",
		isRefillable = true,
		canRefill = canRefill,
		cost = math.max(0, refillCost),
		currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
		maxTotalAmmo = ammoSnapshot.maxTotalAmmo,
		missingAmmo = ammoSnapshot.missingAmmo,
	}
end

-- Collect ammo quotes for all owned weapons
function AmmoInventory.collectQuotes(player, context)
	local pricingConfig = context.pricingConfig or { fullRefillCostScale = 0.35, minimumWeaponRefillCost = 10, minimumPurchaseCost = 1 }

	-- Get owned tools
	local toolsByWeaponId = context.collectOwnedWeaponToolsById and context.collectOwnedWeaponToolsById(player) or {}
	local sentryRecordsByWeaponId = context.collectOwnedSentryRecordsByWeaponId and context.collectOwnedSentryRecordsByWeaponId(player) or {}

	local quotesByWeaponId = {}
	local ownedWeaponIds = {}

	-- Process active sentries first so deployed sentries own the refill row for their weapon.
	for weaponId, sentryRecords in pairs(sentryRecordsByWeaponId) do
		local weaponDef = context.weaponById and context.weaponById[weaponId]
		if weaponDef and context.canPlayerUseWeapon and context.canPlayerUseWeapon(player, weaponDef) then
			ownedWeaponIds[weaponId] = true
			local sentryQuote = AmmoInventory.buildSentryQuote(player, weaponDef, sentryRecords, pricingConfig, context)
			if sentryQuote then
				quotesByWeaponId[weaponId] = sentryQuote
			end
		end
	end

	-- Process tool weapons after sentries. If a live sentry exists, keep the sentry quote.
	for weaponId, tool in pairs(toolsByWeaponId) do
		if quotesByWeaponId[weaponId] ~= nil then
			continue
		end

		local weaponDef = context.weaponById and context.weaponById[weaponId]
		if weaponDef and context.canPlayerUseWeapon and context.canPlayerUseWeapon(player, weaponDef) then
			ownedWeaponIds[weaponId] = true
			local quote = AmmoInventory.buildToolQuote(player, weaponDef, tool, pricingConfig, context)
			if quote then
				quotesByWeaponId[weaponId] = quote
			end
		end
	end

	-- Calculate summary stats
	local refillAllCost = 0
	local ownedWeapons = 0
	local ownedRefillableWeapons = 0
	local refillableWeaponsWithMissingAmmo = 0

	for _ in pairs(ownedWeaponIds) do
		ownedWeapons += 1
	end

	for _, quote in pairs(quotesByWeaponId) do
		if quote.isRefillable then
			ownedRefillableWeapons += 1
		end
		if quote.canRefill and quote.cost > 0 then
			refillableWeaponsWithMissingAmmo += 1
			refillAllCost += quote.cost
		end
	end

	return {
		quotesByWeaponId = quotesByWeaponId,
		refillAllCost = math.max(0, roundWholeNumber(refillAllCost)),
		ownedWeapons = ownedWeapons,
		ownedRefillableWeapons = ownedRefillableWeapons,
		refillableWeaponsWithMissingAmmo = refillableWeaponsWithMissingAmmo,
	}
end

return AmmoInventory
