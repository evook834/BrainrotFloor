--[[
	PricingEngine — Weapon pricing calculations for the shop system.
	Handles base costs, class-based discounts, and ammo refill pricing.
]]

local PricingEngine = {}

local function roundWholeNumber(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

-- Get base weapon cost from definition
function PricingEngine.getBaseCost(weaponDef)
	if not weaponDef or type(weaponDef) ~= "table" then
		return 0
	end
	return roundWholeNumber(weaponDef.Cost)
end

-- Get weapon cost for a specific player (with class discounts)
function PricingEngine.getWeaponCostForPlayer(player, weaponDef, classService)
	local baseCost = PricingEngine.getBaseCost(weaponDef)

	if not player or not player:IsA("Player") or not classService then
		return baseCost
	end

	local discountMultiplier = classService.getWeaponShopCostMultiplier(player, weaponDef)
	if not discountMultiplier or discountMultiplier <= 0 then
		return baseCost
	end

	return math.max(0, math.floor(baseCost * discountMultiplier + 0.5))
end

-- Get ammo refill pricing configuration
function PricingEngine.getAmmoRefillPricingConfig(config)
	local refillConfig = ((config or {}).Shop or {}).AmmoRefill or {}
	local fullRefillCostScale = math.max(0, tonumber(refillConfig.FullRefillCostScale) or 0.35)
	local minimumWeaponRefillCost = roundWholeNumber(refillConfig.MinimumWeaponRefillCost or 10)
	local minimumPurchaseCost = roundWholeNumber(refillConfig.MinimumPurchaseCost or 1)

	return {
		fullRefillCostScale = fullRefillCostScale,
		minimumWeaponRefillCost = minimumWeaponRefillCost,
		minimumPurchaseCost = minimumPurchaseCost,
	}
end

-- Calculate ammo refill cost based on missing ammo percentage
function PricingEngine.calculateRefillCost(player, weaponDef, ammoSnapshot, pricingConfig, context)
	local maxTotalAmmo = ammoSnapshot.maxTotalAmmo
	local missingAmmo = ammoSnapshot.missingAmmo

	if maxTotalAmmo <= 0 or missingAmmo <= 0 then
		return 0, false
	end

	local weaponCost = context.getWeaponCostForPlayer and context.getWeaponCostForPlayer(player, weaponDef) or PricingEngine.getBaseCost(weaponDef)

	local fullRefillCost = math.max(
		pricingConfig.minimumWeaponRefillCost,
		math.floor((weaponCost * pricingConfig.fullRefillCostScale) + 0.5)
	)

	local proportionalCost = math.floor((fullRefillCost * (missingAmmo / maxTotalAmmo)) + 0.5)
	local refillCost = math.max(pricingConfig.minimumPurchaseCost, proportionalCost)

	return math.max(0, refillCost), refillCost > 0
end

return PricingEngine
