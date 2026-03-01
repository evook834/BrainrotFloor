--[[
	ShopContextFactory — Factory for creating context objects for shop modules.
	Provides dependency injection for catalog, pricing, and purchase operations.
]]

local ShopContextFactory = {}

function ShopContextFactory.createAmmoQuoteContext(deps)
	return {
		config = deps.config,
		weaponById = deps.weaponById,
		canPlayerUseWeapon = deps.canPlayerUseWeapon,
		collectOwnedWeaponToolsById = deps.collectOwnedWeaponToolsById,
		prunePlayerSentries = deps.prunePlayerSentries,
		collectOwnedSentryRecordsByWeaponId = deps.collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = deps.getToolAmmoSnapshot,
		getSentryAmmoSnapshot = deps.getSentryAmmoSnapshot,
		getWeaponCostForPlayer = deps.getWeaponCostForPlayer,
	}
end

function ShopContextFactory.createCatalogContext(deps)
	return {
		config = deps.config,
		classService = deps.classService,
		weaponById = deps.weaponById,
		remotesFolder = deps.remotesFolder,
		canPlayerUseWeapon = deps.canPlayerUseWeapon,
		playerOwnsWeapon = deps.playerOwnsWeapon,
		resolveWeaponClass = deps.resolveWeaponClass,
		getWeaponCostForPlayer = deps.getWeaponCostForPlayer,
		getMagazineSize = deps.getMagazineSize,
		getReloadSeconds = deps.getReloadSeconds,
		collectOwnedWeaponToolsById = deps.collectOwnedWeaponToolsById,
		prunePlayerSentries = deps.prunePlayerSentries,
		collectOwnedSentryRecordsByWeaponId = deps.collectOwnedSentryRecordsByWeaponId,
		getToolAmmoSnapshot = deps.getToolAmmoSnapshot,
		getSentryAmmoSnapshot = deps.getSentryAmmoSnapshot,
	}
end

function ShopContextFactory.createWeaponPurchaseContext(deps)
	return {
		weaponById = deps.weaponById,
		canPurchaseNow = deps.canPurchaseNow,
		canPlayerUseWeapon = deps.canPlayerUseWeapon,
		getClassRestrictionMessage = deps.getClassRestrictionMessage,
		getRequiredOwnedWeaponId = deps.getRequiredOwnedWeaponId,
		playerOwnsWeapon = deps.playerOwnsWeapon,
		getUpgradeRestrictionMessage = deps.getUpgradeRestrictionMessage,
		getMoneyAmount = deps.getMoneyAmount,
		trySpendMoney = deps.trySpendMoney,
		refundMoney = deps.refundMoney,
		getWeaponCostForPlayer = deps.getWeaponCostForPlayer,
		createWeaponTool = deps.createWeaponTool,
	}
end

function ShopContextFactory.createAmmoPurchaseContext(deps)
	return {
		weaponById = deps.weaponById,
		canPurchaseNow = deps.canPurchaseNow,
		canPlayerUseWeapon = deps.canPlayerUseWeapon,
		getClassRestrictionMessage = deps.getClassRestrictionMessage,
		collectAmmoRefillQuotesForOwnedWeapons = deps.collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyAmount = deps.getMoneyAmount,
		trySpendMoney = deps.trySpendMoney,
		refundMoney = deps.refundMoney,
		refillAmmoForTool = deps.refillAmmoForTool,
		refillAmmoForSentryRecords = deps.refillAmmoForSentryRecords,
	}
end

function ShopContextFactory.createAllAmmoPurchaseContext(deps)
	return {
		weaponById = deps.weaponById,
		canPurchaseNow = deps.canPurchaseNow,
		collectAmmoRefillQuotesForOwnedWeapons = deps.collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyAmount = deps.getMoneyAmount,
		trySpendMoney = deps.trySpendMoney,
		refundMoney = deps.refundMoney,
		refillAmmoForTool = deps.refillAmmoForTool,
		refillAmmoForSentryRecords = deps.refillAmmoForSentryRecords,
	}
end

return ShopContextFactory
