local PurchaseFlow = {}

local MESSAGE_UNKNOWN_WEAPON = "Unknown weapon."
local MESSAGE_BETWEEN_WAVES = "You can only buy between waves."
local MESSAGE_NOT_ENOUGH_MONEY = "Not enough money."
local MESSAGE_MONEY_UNAVAILABLE = "Money data not available."
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
	return context.canPurchaseNow() == true
end

local function getCurrentMoney(player, context)
	if type(context.getCurrentMoney) == "function" then
		return context.getCurrentMoney(player)
	end

	if type(context.getMoneyValue) == "function" then
		local moneyValue = context.getMoneyValue(player)
		if moneyValue then
			return moneyValue.Value
		end
	end

	return nil
end

local function ensureMoney(player, requiredAmount, context)
	local currentMoney = getCurrentMoney(player, context)
	if currentMoney == nil then
		return nil, failure(MESSAGE_MONEY_UNAVAILABLE)
	end

	if currentMoney < requiredAmount then
		return nil, failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	return currentMoney, nil
end

local function tryCharge(player, amount, context)
	local cost = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
	if cost <= 0 then
		return true
	end

	if type(context.trySpendMoney) == "function" then
		return context.trySpendMoney(player, cost) == true
	end

	local moneyValue = if type(context.getMoneyValue) == "function" then context.getMoneyValue(player) else nil
	if not moneyValue or moneyValue.Value < cost then
		return false
	end

	if type(context.deductMoney) == "function" then
		context.deductMoney(player, cost)
	else
		moneyValue.Value -= cost
	end

	return true
end

local function refundCharge(player, amount, context)
	local refundAmount = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
	if refundAmount <= 0 then
		return
	end

	if type(context.refundMoney) == "function" then
		context.refundMoney(player, refundAmount)
		return
	end

	if type(context.addMoney) == "function" then
		context.addMoney(player, refundAmount)
		return
	end

	local moneyValue = if type(context.getMoneyValue) == "function" then context.getMoneyValue(player) else nil
	if moneyValue then
		moneyValue.Value += refundAmount
	end
end

function PurchaseFlow.grantWeapon(player, weaponDef, context)
	if not context.canPlayerUseWeapon(player, weaponDef) then
		return false, context.getClassRestrictionMessage(player)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	local toolForBackpack = context.createWeaponTool(weaponDef, player)
	if backpack then
		toolForBackpack.Parent = backpack

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid:EquipTool(toolForBackpack)
			end
		end
	else
		toolForBackpack:Destroy()
	end

	if starterGear then
		local toolForStarterGear = context.createWeaponTool(weaponDef, player)
		toolForStarterGear.Parent = starterGear
	end

	return true, nil
end

function PurchaseFlow.buyWeapon(player, weaponId, context)
	local weaponDef = context.weaponById[weaponId]
	if not weaponDef then
		return failure(MESSAGE_UNKNOWN_WEAPON)
	end

	if not canPurchaseRightNow(context) then
		return failure(MESSAGE_BETWEEN_WAVES)
	end

	if not context.canPlayerUseWeapon(player, weaponDef) then
		return failure(context.getClassRestrictionMessage(player))
	end

	local requiredWeaponId = context.getRequiredOwnedWeaponId(weaponDef)
	if requiredWeaponId and not context.playerOwnsWeapon(player, requiredWeaponId) then
		return failure(context.getUpgradeRestrictionMessage(weaponDef))
	end

	if context.playerOwnsWeapon(player, weaponId) then
		return failure("You already own this weapon.")
	end

	local weaponCost = context.getWeaponCostForPlayer(player, weaponDef)
	local _, moneyFailure = ensureMoney(player, weaponCost, context)
	if moneyFailure then
		return moneyFailure
	end

	if not tryCharge(player, weaponCost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	local granted, grantError = PurchaseFlow.grantWeapon(player, weaponDef, context)
	if not granted then
		refundCharge(player, weaponCost, context)
		return failure(grantError or "Could not grant weapon.")
	end

	local baseCost = math.max(0, math.floor((tonumber(weaponDef.Cost) or 0) + 0.5))
	local purchaseMessage = string.format("Bought %s for $%d", weaponDef.DisplayName, weaponCost)
	if weaponCost < baseCost then
		purchaseMessage = string.format("Bought %s for $%d (class discount)", weaponDef.DisplayName, weaponCost)
	end

	return success(purchaseMessage)
end

function PurchaseFlow.buyAmmoForWeapon(player, weaponId, context)
	local weaponDef = context.weaponById[weaponId]
	if not weaponDef then
		return failure(MESSAGE_UNKNOWN_WEAPON)
	end

	if not canPurchaseRightNow(context) then
		return failure(MESSAGE_BETWEEN_WAVES)
	end

	if not context.canPlayerUseWeapon(player, weaponDef) then
		return failure(context.getClassRestrictionMessage(player))
	end

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons(player)
	local quote = refillSummary.quotesByWeaponId[weaponId]
	if not quote then
		return failure(MESSAGE_NOT_OWNED)
	end

	local isSentryRefill = quote.refillKind == "Sentry"
	if isSentryRefill then
		if type(quote.sentryRecords) ~= "table" or #quote.sentryRecords == 0 then
			return failure(MESSAGE_NOT_OWNED)
		end
	elseif not quote.tool or quote.tool.Parent == nil then
		return failure(MESSAGE_NOT_OWNED)
	end

	if quote.isRefillable ~= true then
		return failure(MESSAGE_NO_AMMO)
	end

	if quote.canRefill ~= true or quote.cost <= 0 then
		return failure(MESSAGE_AMMO_FULL)
	end

	local _, moneyFailure = ensureMoney(player, quote.cost, context)
	if moneyFailure then
		return moneyFailure
	end

	if not tryCharge(player, quote.cost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	local didRefill = false
	if isSentryRefill then
		didRefill = context.refillAmmoForSentryRecords(quote.sentryRecords, weaponDef)
	else
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

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons(player)
	if refillSummary.refillAllCost <= 0 or refillSummary.refillableWeaponsWithMissingAmmo <= 0 then
		return failure(MESSAGE_ALL_AMMO_FULL)
	end

	local _, moneyFailure = ensureMoney(player, refillSummary.refillAllCost, context)
	if moneyFailure then
		return moneyFailure
	end

	if not tryCharge(player, refillSummary.refillAllCost, context) then
		return failure(MESSAGE_NOT_ENOUGH_MONEY)
	end

	local spent = 0
	local refilledCount = 0

	for weaponId, quote in pairs(refillSummary.quotesByWeaponId) do
		if quote.canRefill == true and quote.cost > 0 then
			local weaponDef = context.weaponById[weaponId]
			if weaponDef then
				local didRefill = false
				if quote.refillKind == "Sentry" then
					didRefill = context.refillAmmoForSentryRecords(quote.sentryRecords, weaponDef)
				elseif quote.tool and quote.tool.Parent then
					didRefill = context.refillAmmoForTool(quote.tool, weaponDef, player, "Full", nil)
				end

				if didRefill then
					refilledCount += 1
					spent += quote.cost
				end
			end
		end
	end

	if refilledCount <= 0 then
		refundCharge(player, refillSummary.refillAllCost, context)
		return failure(MESSAGE_ALL_AMMO_FULL)
	end

	local refund = refillSummary.refillAllCost - spent
	if refund > 0 then
		refundCharge(player, refund, context)
	end

	return success(string.format("Refilled ammo for %d weapon%s for $%d", refilledCount, if refilledCount == 1 then "" else "s", spent))
end

return PurchaseFlow
