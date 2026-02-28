--[[
	CatalogAndPricing — Refactored shop catalog and pricing module.
	Composed of smaller, focused sub-modules for better maintainability.
]]

local PricingEngine = require(script.Parent.Catalog.PricingEngine)
local CatalogBuilder = require(script.Parent.Catalog.CatalogBuilder)
local AmmoInventory = require(script.Parent.Catalog.AmmoInventory)

local CatalogAndPricing = {}

local getAmmoRefillPricingConfig = PricingEngine.getAmmoRefillPricingConfig
local getWeaponCostForPlayer = PricingEngine.getWeaponCostForPlayer
local calculateRefillCost = PricingEngine.calculateRefillCost

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
	if not weaponById or not weaponById[requiredWeaponId] then
		return nil
	end

	return requiredWeaponId
end

function CatalogAndPricing.getRequiredOwnedWeaponName(weaponId, weaponById)
	local requiredWeaponDef = weaponById and weaponById[weaponId]
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

function CatalogAndPricing.getClassRestrictionMessage(player, classService)
	if not classService or not player then
		return "Cannot purchase this weapon."
	end

	local className = classService.getPlayerClassName and classService.getPlayerClassName(player)
	return string.format("%s cannot buy this weapon.", className or "This class")
end

function CatalogAndPricing.canPurchaseNow(remotesFolder, config)
	return CatalogBuilder.canPurchaseNow(remotesFolder, config)
end

function CatalogAndPricing.getWeaponCostForPlayer(player, weaponDef, classService)
	return getWeaponCostForPlayer(player, weaponDef, classService)
end

function CatalogAndPricing.buildWeaponAmmoRefillQuote(player, weaponDef, tool, pricingConfig, context)
	return AmmoInventory.buildToolQuote(player, weaponDef, tool, pricingConfig, context)
end

function CatalogAndPricing.buildSentryAmmoRefillQuote(player, weaponDef, sentryRecords, pricingConfig, context)
	return AmmoInventory.buildSentryQuote(player, weaponDef, sentryRecords, pricingConfig, context)
end

function CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, context)
	if context.prunePlayerSentries then
		context.prunePlayerSentries(player)
	end

	local pricingConfig = getAmmoRefillPricingConfig(context.config)
	local ammoContext = {
		weaponById = context.weaponById,
		canPlayerUseWeapon = context.canPlayerUseWeapon,
		collectOwnedWeaponToolsById = context.collectOwnedWeaponToolsById,
		collectOwnedSentryRecordsByWeaponId = context.collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = context.getToolAmmoSnapshot,
		getSentryAmmoSnapshot = context.getSentryAmmoSnapshot,
		getWeaponCostForPlayer = context.getWeaponCostForPlayer,
		calculateRefillCost = function(p, w, a, pc, ctx)
			return calculateRefillCost(p, w, a, pc, { getWeaponCostForPlayer = ctx.getWeaponCostForPlayer })
		end,
	}

	return AmmoInventory.collectQuotes(player, {
		pricingConfig = pricingConfig,
		weaponById = ammoContext.weaponById,
		canPlayerUseWeapon = ammoContext.canPlayerUseWeapon,
		collectOwnedWeaponToolsById = ammoContext.collectOwnedWeaponToolsById,
		collectOwnedSentryRecordsByWeaponId = ammoContext.collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = ammoContext.getToolAmmoSnapshot,
		getSentryAmmoSnapshot = ammoContext.getSentryAmmoSnapshot,
		getWeaponCostForPlayer = ammoContext.getWeaponCostForPlayer,
		calculateRefillCost = ammoContext.calculateRefillCost,
	})
end

function CatalogAndPricing.getCatalogForPlayer(player, context)
	-- Build ammo quotes
	local quotesSummary = CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, context)

	-- Build catalog
	local catalogContext = {
		config = context.config,
		remotesFolder = context.remotesFolder,
		weaponById = context.weaponById,
		canPlayerUseWeapon = context.canPlayerUseWeapon,
		getWeaponCostForPlayer = context.getWeaponCostForPlayer,
		getRequiredOwnedWeaponId = context.getRequiredOwnedWeaponId or CatalogAndPricing.getRequiredOwnedWeaponId,
		getRequiredOwnedWeaponName = context.getRequiredOwnedWeaponName or CatalogAndPricing.getRequiredOwnedWeaponName,
		getMagazineSize = context.getMagazineSize,
		getReloadSeconds = context.getReloadSeconds,
		resolveWeaponClass = context.resolveWeaponClass,
		playerOwnsWeapon = context.playerOwnsWeapon,
		classService = context.classService,
		quotesByWeaponId = quotesSummary.quotesByWeaponId,
		refillSummary = quotesSummary,
	}

	return CatalogBuilder.buildCatalogForPlayer(player, catalogContext)
end

return CatalogAndPricing
