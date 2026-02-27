local CatalogAndPricing = {}

function CatalogAndPricing.canPurchaseNow(remotesFolder, config)
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

function CatalogAndPricing.getWeaponCostForPlayer(player, weaponDef, classService)
	if player and player:IsA("Player") then
		return classService.getWeaponShopCost(player, weaponDef)
	end

	return math.max(0, math.floor((tonumber((weaponDef or {}).Cost) or 0) + 0.5))
end

function CatalogAndPricing.getAmmoRefillPricingConfig(config)
	local refillConfig = ((config or {}).Shop or {}).AmmoRefill or {}
	local fullRefillCostScale = math.max(0, tonumber(refillConfig.FullRefillCostScale) or 0.35)
	local minimumWeaponRefillCost = math.max(0, math.floor((tonumber(refillConfig.MinimumWeaponRefillCost) or 10) + 0.5))
	local minimumPurchaseCost = math.max(0, math.floor((tonumber(refillConfig.MinimumPurchaseCost) or 1) + 0.5))

	return {
		fullRefillCostScale = fullRefillCostScale,
		minimumWeaponRefillCost = minimumWeaponRefillCost,
		minimumPurchaseCost = minimumPurchaseCost,
	}
end

function CatalogAndPricing.getClassRestrictionMessage(player, classService)
	local className = classService.getPlayerClassName(player)
	return string.format("%s cannot buy this weapon.", className)
end

function CatalogAndPricing.getRequiredOwnedWeaponId(weaponDef, weaponById)
	if type(weaponDef) ~= "table" then
		return nil
	end

	local requiredWeaponId = weaponDef.RequiresWeaponId or weaponDef.UpgradeFromWeaponId
	if type(requiredWeaponId) ~= "string" or requiredWeaponId == "" then
		return nil
	end
	if requiredWeaponId == weaponDef.Id then
		return nil
	end
	if not weaponById[requiredWeaponId] then
		return nil
	end

	return requiredWeaponId
end

function CatalogAndPricing.getRequiredOwnedWeaponName(weaponId, weaponById)
	local requiredWeaponDef = weaponById[weaponId]
	if requiredWeaponDef and type(requiredWeaponDef.DisplayName) == "string" and requiredWeaponDef.DisplayName ~= "" then
		return requiredWeaponDef.DisplayName
	end

	return weaponId
end

function CatalogAndPricing.getUpgradeRestrictionMessage(weaponDef, weaponById)
	local requiredWeaponId = CatalogAndPricing.getRequiredOwnedWeaponId(weaponDef, weaponById)
	if not requiredWeaponId then
		return "You do not meet this weapon's upgrade requirement."
	end

	return string.format("Requires %s first.", CatalogAndPricing.getRequiredOwnedWeaponName(requiredWeaponId, weaponById))
end

function CatalogAndPricing.buildWeaponAmmoRefillQuote(player, weaponDef, tool, pricingConfig, context)
	if not (player and player:IsA("Player")) then
		return nil
	end
	if type(weaponDef) ~= "table" or type(weaponDef.Id) ~= "string" or weaponDef.Id == "" then
		return nil
	end
	if not (tool and tool:IsA("Tool")) then
		return nil
	end

	local ammoSnapshot = context.getToolAmmoSnapshot(tool, weaponDef, player)
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

	local maxTotalAmmo = ammoSnapshot.maxTotalAmmo
	local missingAmmo = ammoSnapshot.missingAmmo
	if maxTotalAmmo <= 0 or missingAmmo <= 0 then
		return {
			weaponId = weaponDef.Id,
			tool = tool,
			refillKind = "Tool",
			isRefillable = true,
			canRefill = false,
			cost = 0,
			currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
			maxTotalAmmo = maxTotalAmmo,
			missingAmmo = missingAmmo,
		}
	end

	local weaponCost = context.getWeaponCostForPlayer(player, weaponDef)
	local fullRefillCost = math.max(
		pricingConfig.minimumWeaponRefillCost,
		math.floor((weaponCost * pricingConfig.fullRefillCostScale) + 0.5)
	)
	local proportionalCost = math.floor((fullRefillCost * (missingAmmo / maxTotalAmmo)) + 0.5)
	local refillCost = math.max(pricingConfig.minimumPurchaseCost, proportionalCost)

	return {
		weaponId = weaponDef.Id,
		tool = tool,
		refillKind = "Tool",
		isRefillable = true,
		canRefill = refillCost > 0,
		cost = math.max(0, refillCost),
		currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
		maxTotalAmmo = maxTotalAmmo,
		missingAmmo = missingAmmo,
	}
end

function CatalogAndPricing.buildSentryAmmoRefillQuote(player, weaponDef, sentryRecords, pricingConfig, context)
	if not (player and player:IsA("Player")) then
		return nil
	end
	if type(weaponDef) ~= "table" or type(weaponDef.Id) ~= "string" or weaponDef.Id == "" then
		return nil
	end
	if type(sentryRecords) ~= "table" or #sentryRecords == 0 then
		return nil
	end

	local ammoSnapshot = context.getSentryAmmoSnapshot(sentryRecords, weaponDef)
	if not ammoSnapshot then
		return nil
	end

	local maxTotalAmmo = ammoSnapshot.maxTotalAmmo
	local missingAmmo = ammoSnapshot.missingAmmo
	if maxTotalAmmo <= 0 or missingAmmo <= 0 then
		return {
			weaponId = weaponDef.Id,
			refillKind = "Sentry",
			sentryRecords = sentryRecords,
			isRefillable = true,
			canRefill = false,
			cost = 0,
			currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
			maxTotalAmmo = maxTotalAmmo,
			missingAmmo = missingAmmo,
		}
	end

	local weaponCost = context.getWeaponCostForPlayer(player, weaponDef)
	local fullRefillCost = math.max(
		pricingConfig.minimumWeaponRefillCost,
		math.floor((weaponCost * pricingConfig.fullRefillCostScale) + 0.5)
	)
	local proportionalCost = math.floor((fullRefillCost * (missingAmmo / maxTotalAmmo)) + 0.5)
	local refillCost = math.max(pricingConfig.minimumPurchaseCost, proportionalCost)

	return {
		weaponId = weaponDef.Id,
		refillKind = "Sentry",
		sentryRecords = sentryRecords,
		isRefillable = true,
		canRefill = refillCost > 0,
		cost = math.max(0, refillCost),
		currentTotalAmmo = ammoSnapshot.currentTotalAmmo,
		maxTotalAmmo = maxTotalAmmo,
		missingAmmo = missingAmmo,
	}
end

function CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, context)
	local pricingConfig = CatalogAndPricing.getAmmoRefillPricingConfig(context.config)
	local toolsByWeaponId = context.collectOwnedWeaponToolsById(player)
	context.prunePlayerSentries(player)
	local sentryRecordsByWeaponId = context.collectOwnedSentryRecordsByWeaponId(player)
	local quotesByWeaponId = {}
	local ownedWeaponIds = {}

	for weaponId, tool in pairs(toolsByWeaponId) do
		local weaponDef = context.weaponById[weaponId]
		if weaponDef and context.canPlayerUseWeapon(player, weaponDef) then
			ownedWeaponIds[weaponId] = true
			local quote = CatalogAndPricing.buildWeaponAmmoRefillQuote(player, weaponDef, tool, pricingConfig, context)
			if quote then
				quotesByWeaponId[weaponId] = quote
			end
		end
	end

	for weaponId, sentryRecords in pairs(sentryRecordsByWeaponId) do
		local weaponDef = context.weaponById[weaponId]
		if weaponDef and context.canPlayerUseWeapon(player, weaponDef) then
			ownedWeaponIds[weaponId] = true
			local sentryQuote = CatalogAndPricing.buildSentryAmmoRefillQuote(
				player,
				weaponDef,
				sentryRecords,
				pricingConfig,
				context
			)
			if sentryQuote then
				quotesByWeaponId[weaponId] = sentryQuote
			end
		end
	end

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
		refillAllCost = math.max(0, refillAllCost),
		ownedWeapons = ownedWeapons,
		ownedRefillableWeapons = ownedRefillableWeapons,
		refillableWeaponsWithMissingAmmo = refillableWeaponsWithMissingAmmo,
	}
end

function CatalogAndPricing.getCatalogForPlayer(player, context)
	local canPurchase, waveState = CatalogAndPricing.canPurchaseNow(context.remotesFolder, context.config)
	local weapons = {}
	local refillSummary = CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, context)
	local quotesByWeaponId = refillSummary.quotesByWeaponId

	for _, weaponDef in ipairs(((context.config or {}).Shop or {}).Weapons or {}) do
		if not context.canPlayerUseWeapon(player, weaponDef) then
			continue
		end

		local baseRange = math.max(0, tonumber(weaponDef.Range) or 0)
		local rangeMultiplier = math.max(0.1, context.classService.getWeaponBulletRangeMultiplier(player, weaponDef))
		local effectiveRange = math.floor((baseRange * rangeMultiplier) + 0.5)
		local rangeBonusPct = math.max(0, (rangeMultiplier - 1) * 100)
		local isOwned = context.playerOwnsWeapon(player, weaponDef.Id)
		local requiredWeaponId = CatalogAndPricing.getRequiredOwnedWeaponId(weaponDef, context.weaponById)
		local requiredWeaponName = if requiredWeaponId
			then CatalogAndPricing.getRequiredOwnedWeaponName(requiredWeaponId, context.weaponById)
			else nil
		local isUpgradeLocked = requiredWeaponId ~= nil and not context.playerOwnsWeapon(player, requiredWeaponId)
		local refillQuote = quotesByWeaponId[weaponDef.Id]
		local refillCost = if refillQuote then refillQuote.cost else 0
		local canRefill = if refillQuote then refillQuote.canRefill else false
		local isRefillable = if refillQuote then refillQuote.isRefillable else context.getMagazineSize(weaponDef, player) ~= nil

		table.insert(weapons, {
			id = weaponDef.Id,
			name = weaponDef.DisplayName,
			weaponClass = context.resolveWeaponClass(weaponDef),
			cost = context.getWeaponCostForPlayer(player, weaponDef),
			damage = weaponDef.Damage,
			range = baseRange,
			effectiveRange = effectiveRange,
			rangeBonusPct = rangeBonusPct,
			cooldown = weaponDef.Cooldown,
			magazineSize = context.getMagazineSize(weaponDef, player),
			reloadSeconds = context.getReloadSeconds(weaponDef, player),
			requiresWeaponId = requiredWeaponId,
			requiresWeaponName = requiredWeaponName,
			upgradeLocked = isUpgradeLocked,
			owned = isOwned,
			isRefillable = isRefillable,
			refillCost = if isOwned then refillCost else 0,
			canRefill = if isOwned then canRefill else false,
			currentAmmoTotal = if refillQuote then refillQuote.currentTotalAmmo else nil,
			maxAmmoTotal = if refillQuote then refillQuote.maxTotalAmmo else nil,
			missingAmmo = if refillQuote then refillQuote.missingAmmo else nil,
		})
	end

	table.sort(weapons, function(a, b)
		return a.cost < b.cost
	end)

	return {
		success = true,
		canPurchase = canPurchase,
		waveState = waveState,
		weapons = weapons,
		refillAllCost = refillSummary.refillAllCost,
		canRefillAll = refillSummary.refillAllCost > 0,
		ownedWeapons = refillSummary.ownedWeapons,
		ownedRefillableWeapons = refillSummary.ownedRefillableWeapons,
		refillableWeaponsWithMissingAmmo = refillSummary.refillableWeaponsWithMissingAmmo,
	}
end

return CatalogAndPricing
