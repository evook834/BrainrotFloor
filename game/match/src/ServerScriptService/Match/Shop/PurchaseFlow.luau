--[[
	PurchaseFlow — Shop purchase transaction logic.
	Handles weapon and ammo purchases with proper refund handling.
]]

local CurrencyService = require(script.Parent.Currency.CurrencyService)
local ShopConstants = require(script.Parent.ShopConstants)

local PurchaseFlow = {}

local MESSAGE_UNKNOWN_WEAPON = "Unknown weapon."
local MESSAGE_BETWEEN_WAVES = "You can only buy between waves."
local MESSAGE_NOT_ENOUGH_MONEY = "Not enough money."
local MESSAGE_NOT_OWNED = "You do not own this weapon."
local MESSAGE_AMMO_FULL = "Ammo is already full."
local MESSAGE_NO_AMMO = "This weapon does not use ammo."
local MESSAGE_ALL_AMMO_FULL = "All owned weapon ammo is already full."

local function failure(message)
	return {
		success = false,
		message = message,
	}
end

local function success(message)
	return {
		success = true,
		message = message,
	}
end

local function canPurchaseRightNow(context)
	local canPurchase, _ = context.canPurchaseNow and context.canPurchaseNow() or { false, "Unknown" }
	return type(canPurchase) == "boolean" and canPurchase
end

local function getMoneyAmount(player, context)
	-- Prefer CurrencyService if available
	if context.getMoneyAmount and type(context.getMoneyAmount) == "function" then
		return context.getMoneyAmount(player)
	end

	-- Legacy: use CurrencyService directly
	return CurrencyService.getMoneyAmount(player)
end

local function tryCharge(player, amount, context)
	local cost = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
	if cost <= 0 then
		return true
	end

	-- Prefer CurrencyService if available
	if context.trySpendMoney and type(context.trySpendMoney) == "function" then
		return context.trySpendMoney(player, cost) == true
	end

	-- Use CurrencyService directly
	return CurrencyService.trySpendMoney(player, cost)
end

local function refundCharge(player, amount, context)
	local refundAmount = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
	if refundAmount <= 0 then
		return
	end

	-- Prefer CurrencyService if available
	if context.refundMoney and type(context.refundMoney) == "function" then
		context.refundMoney(player, refundAmount)
		return
	end

	-- Use CurrencyService directly
	CurrencyService.refundMoney(player, refundAmount)
end

function PurchaseFlow.grantWeapon(player, weaponDef, context)
	if not context.canPlayerUseWeapon then
		return false, "Weapon restriction check unavailable."
	end

	if not context.canPlayerUseWeapon(player, weaponDef) then
		return false, context.getClassRestrictionMessage and context.getClassRestrictionMessage(player) or "Cannot use this weapon."
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	local toolForBackpack = context.createWeaponTool and context.createWeaponTool(weaponDef, player)
	if backpack and toolForBackpack then
		toolForBackpack.Parent = backpack

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:EquipTool(toolForBackpack)
			end
		end
	else
		if toolForBackpack then
			toolForBackpack:Destroy()
		end
	end

	if starterGear and context.createWeaponTool then
		local toolForStarterGear = context.createWeaponTool(weaponDef, player)
		if toolForStarterGear then
			toolForStarterGear.Parent = starterGear
		end
	end

	return true, nil
end

function PurchaseFlow.buyWeapon(player, weaponId, context)
	local weaponDef = context.weaponById and context.weaponById[weaponId]
	if not weaponDef then
		return failure(MESSAGE_UNKNOWN_WEAPON)
	end

	if not canPurchaseRightNow(context) then
		return failure(MESSAGE_BETWEEN_WAVES)
	end

	if context.canPlayerUseWeapon and not context.canPlayerUseWeapon(player, weaponDef) then
		return failure(context.getClassRestrictionMessage and context.getClassRestrictionMessage(player) or "Cannot use this weapon.")
	end

	if context.getRequiredOwnedWeaponId then
		local requiredWeaponId = context.getRequiredOwnedWeaponId(weaponDef)
		if requiredWeaponId and context.playerOwnsWeapon and not context.playerOwnsWeapon(player, requiredWeaponId) then
			return failure(context.getUpgradeRestrictionMessage and context.getUpgradeRestrictionMessage(weaponDef) or "Upgrade requirement not met.")
		end
	end

	if context.playerOwnsWeapon and context.playerOwnsWeapon(player, weaponId) then
		return failure("You already own this weapon.")
	end

	local weaponCost = context.getWeaponCostForPlayer and context.getWeaponCostForPlayer(player, weaponDef) or 0

	-- Check if player can afford
	local currentMoney = getMoneyAmount(player, context)
	if currentMoney == nil then
		return failure("Money data not available.")
	end
	if currentMoney < weaponCost then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Charge the player
	if not tryCharge(player, weaponCost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Grant the weapon
	local granted, grantError = PurchaseFlow.grantWeapon(player, weaponDef, context)
	if not granted then
		refundCharge(player, weaponCost, context)
		return failure(grantError or "Could not grant weapon.")
	end

	-- Build success message
	local baseCost = math.max(0, math.floor((tonumber(weaponDef.Cost) or 0) + 0.5))
	local purchaseMessage = string.format("Bought %s for $%d", weaponDef.DisplayName, weaponCost)
	if weaponCost < baseCost then
		purchaseMessage = string.format("Bought %s for $%d (class discount)", weaponDef.DisplayName, weaponCost)
	end

	return success(purchaseMessage)
end

function PurchaseFlow.buyAmmoForWeapon(player, weaponId, context)
	local weaponDef = context.weaponById and context.weaponById[weaponId]
	if not weaponDef then
		return failure(MESSAGE_UNKNOWN_WEAPON)
	end

	if not canPurchaseRightNow(context) then
		return failure(MESSAGE_BETWEEN_WAVES)
	end

	if context.canPlayerUseWeapon and not context.canPlayerUseWeapon(player, weaponDef) then
		return failure(context.getClassRestrictionMessage and context.getClassRestrictionMessage(player) or "Cannot use this weapon.")
	end

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons and context.collectAmmoRefillQuotesForOwnedWeapons(player) or { quotesByWeaponId = {} }
	local quote = refillSummary.quotesByWeaponId and refillSummary.quotesByWeaponId[weaponId]
	if not quote then
		return failure(MESSAGE_NOT_OWNED)
	end

	local isSentryRefill = quote.refillKind == "Sentry"
	if isSentryRefill then
		if type(quote.sentryRecords) ~= "table" or #quote.sentryRecords == 0 then
			return failure(MESSAGE_NOT_OWNED)
		end
	elseif not quote.tool or (quote.tool.Parent == nil) then
		return failure(MESSAGE_NOT_OWNED)
	end

	if quote.isRefillable ~= true then
		return failure(MESSAGE_NO_AMMO)
	end

	if quote.canRefill ~= true or quote.cost <= 0 then
		return failure(MESSAGE_AMMO_FULL)
	end

	-- Check if player can afford
	local currentMoney = getMoneyAmount(player, context)
	if currentMoney == nil then
		return failure("Money data not available.")
	end
	if currentMoney < quote.cost then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Charge the player
	if not tryCharge(player, quote.cost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Refill the ammo
	local didRefill = false
	if isSentryRefill and context.refillAmmoForSentryRecords then
		didRefill = context.refillAmmoForSentryRecords(quote.sentryRecords, weaponDef)
	elseif context.refillAmmoForTool then
		didRefill = context.refillAmmoForTool(quote.tool, weaponDef, player, "Full", nil)
	end

	if not didRefill then
		refundCharge(player, quote.cost, context)
		return failure(MESSAGE_AMMO_FULL)
	end

	return success(string.format("Refilled %s ammo for $%d", weaponDef.DisplayName, quote.cost))
end

function PurchaseFlow.buyAmmoForAllOwnedWeapons(player, context)
	if not canPurchaseRightNow(context) then
		return failure(MESSAGE_BETWEEN_WAVES)
	end

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons and context.collectAmmoRefillQuotesForOwnedWeapons(player) or { quotesByWeaponId = {} }
	if (refillSummary.refillAllCost or 0) <= 0 or (refillSummary.refillableWeaponsWithMissingAmmo or 0) <= 0 then
		return failure(MESSAGE_ALL_AMMO_FULL)
	end

	-- Check if player can afford
	local currentMoney = getMoneyAmount(player, context)
	if currentMoney == nil then
		return failure("Money data not available.")
	end
	if currentMoney < refillSummary.refillAllCost then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Charge the player
	if not tryCharge(player, refillSummary.refillAllCost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	-- Refill weapons
	local spent = 0
	local refilledCount = 0

	for weaponId, quote in pairs(refillSummary.quotesByWeaponId) do
		if quote.canRefill == true and quote.cost > 0 then
			local weaponDef = context.weaponById and context.weaponById[weaponId]
			if weaponDef then
				local didRefill = false
				if quote.refillKind == "Sentry" and context.refillAmmoForSentryRecords then
					didRefill = context.refillAmmoForSentryRecords(quote.sentryRecords, weaponDef)
				elseif quote.tool and quote.tool.Parent and context.refillAmmoForTool then
					didRefill = context.refillAmmoForTool(quote.tool, weaponDef, player, "Full", nil)
				end

				if didRefill then
					refilledCount += 1
					spent += quote.cost
				end
			end
		end
	end

	-- Handle partial refund if some weapons couldn't be refilled
	if refilledCount <= 0 then
		refundCharge(player, refillSummary.refillAllCost, context)
		return failure(MESSAGE_ALL_AMMO_FULL)
	end

	local refund = (refillSummary.refillAllCost or 0) - spent
	if refund > 0 then
		refundCharge(player, refund, context)
	end

	return success(string.format("Refilled ammo for %d weapon%s for $%d", refilledCount, refilledCount == 1 and "" or "s", spent))
end

return PurchaseFlow
