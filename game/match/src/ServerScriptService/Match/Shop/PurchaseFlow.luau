local PurchaseFlow = {}

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
		return {
			success = false,
			message = "Unknown weapon.",
		}
	end

	local canPurchase = context.canPurchaseNow()
	if not canPurchase then
		return {
			success = false,
			message = "You can only buy between waves.",
		}
	end

	if not context.canPlayerUseWeapon(player, weaponDef) then
		return {
			success = false,
			message = context.getClassRestrictionMessage(player),
		}
	end

	local requiredWeaponId = context.getRequiredOwnedWeaponId(weaponDef)
	if requiredWeaponId and not context.playerOwnsWeapon(player, requiredWeaponId) then
		return {
			success = false,
			message = context.getUpgradeRestrictionMessage(weaponDef),
		}
	end

	if context.playerOwnsWeapon(player, weaponId) then
		return {
			success = false,
			message = "You already own this weapon.",
		}
	end

	local moneyValue = context.getMoneyValue(player)
	if not moneyValue then
		return {
			success = false,
			message = "Money data not available.",
		}
	end

	local weaponCost = context.getWeaponCostForPlayer(player, weaponDef)
	if moneyValue.Value < weaponCost then
		return {
			success = false,
			message = "Not enough money.",
		}
	end

	if context.deductMoney then
		context.deductMoney(player, weaponCost)
	else
		moneyValue.Value -= weaponCost
	end
	local granted, grantError = PurchaseFlow.grantWeapon(player, weaponDef, context)
	if not granted then
		if context.addMoney then
			context.addMoney(player, weaponCost)
		else
			moneyValue.Value += weaponCost
		end
		return {
			success = false,
			message = grantError or "Could not grant weapon.",
		}
	end

	local baseCost = math.max(0, math.floor((tonumber(weaponDef.Cost) or 0) + 0.5))
	local purchaseMessage = string.format("Bought %s for $%d", weaponDef.DisplayName, weaponCost)
	if weaponCost < baseCost then
		purchaseMessage = string.format("Bought %s for $%d (class discount)", weaponDef.DisplayName, weaponCost)
	end

	return {
		success = true,
		message = purchaseMessage,
	}
end

function PurchaseFlow.buyAmmoForWeapon(player, weaponId, context)
	local weaponDef = context.weaponById[weaponId]
	if not weaponDef then
		return {
			success = false,
			message = "Unknown weapon.",
		}
	end

	local canPurchase = context.canPurchaseNow()
	if not canPurchase then
		return {
			success = false,
			message = "You can only buy between waves.",
		}
	end

	if not context.canPlayerUseWeapon(player, weaponDef) then
		return {
			success = false,
			message = context.getClassRestrictionMessage(player),
		}
	end

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons(player)
	local quote = refillSummary.quotesByWeaponId[weaponId]
	if not quote then
		return {
			success = false,
			message = "You do not own this weapon.",
		}
	end

	local isSentryRefill = quote.refillKind == "Sentry"
	if isSentryRefill then
		if type(quote.sentryRecords) ~= "table" or #quote.sentryRecords == 0 then
			return {
				success = false,
				message = "You do not own this weapon.",
			}
		end
	elseif not quote.tool or quote.tool.Parent == nil then
		return {
			success = false,
			message = "You do not own this weapon.",
		}
	end

	if quote.isRefillable ~= true then
		return {
			success = false,
			message = "This weapon does not use ammo.",
		}
	end

	if quote.canRefill ~= true or quote.cost <= 0 then
		return {
			success = false,
			message = "Ammo is already full.",
		}
	end

	local moneyValue = context.getMoneyValue(player)
	if not moneyValue then
		return {
			success = false,
			message = "Money data not available.",
		}
	end
	if moneyValue.Value < quote.cost then
		return {
			success = false,
			message = "Not enough money.",
		}
	end

	if context.deductMoney then
		context.deductMoney(player, quote.cost)
	else
		moneyValue.Value -= quote.cost
	end
	local didRefill = false
	if isSentryRefill then
		didRefill = context.refillAmmoForSentryRecords(quote.sentryRecords, weaponDef)
	else
		didRefill = context.refillAmmoForTool(quote.tool, weaponDef, player, "Full", nil)
	end
	if not didRefill then
		if context.addMoney then
			context.addMoney(player, quote.cost)
		else
			moneyValue.Value += quote.cost
		end
		return {
			success = false,
			message = "Ammo is already full.",
		}
	end

	return {
		success = true,
		message = string.format("Refilled %s ammo for $%d", weaponDef.DisplayName, quote.cost),
	}
end

function PurchaseFlow.buyAmmoForAllOwnedWeapons(player, context)
	local canPurchase = context.canPurchaseNow()
	if not canPurchase then
		return {
			success = false,
			message = "You can only buy between waves.",
		}
	end

	local refillSummary = context.collectAmmoRefillQuotesForOwnedWeapons(player)
	if refillSummary.refillAllCost <= 0 or refillSummary.refillableWeaponsWithMissingAmmo <= 0 then
		return {
			success = false,
			message = "All owned weapon ammo is already full.",
		}
	end

	local moneyValue = context.getMoneyValue(player)
	if not moneyValue then
		return {
			success = false,
			message = "Money data not available.",
		}
	end
	if moneyValue.Value < refillSummary.refillAllCost then
		return {
			success = false,
			message = "Not enough money.",
		}
	end

	if context.deductMoney then
		context.deductMoney(player, refillSummary.refillAllCost)
	else
		moneyValue.Value -= refillSummary.refillAllCost
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
		if context.addMoney then
			context.addMoney(player, refillSummary.refillAllCost)
		else
			moneyValue.Value += refillSummary.refillAllCost
		end
		return {
			success = false,
			message = "All owned weapon ammo is already full.",
		}
	end

	local refund = refillSummary.refillAllCost - spent
	if refund > 0 then
		if context.addMoney then
			context.addMoney(player, refund)
		else
			moneyValue.Value += refund
		end
	end

	return {
		success = true,
		message = string.format("Refilled ammo for %d weapon%s for $%d", refilledCount, if refilledCount == 1 then "" else "s", spent),
	}
end

return PurchaseFlow
