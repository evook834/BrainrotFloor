local ShopMoney = {}

local function normalizeMoneyAmount(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function isPlayerInstance(player)
	return player and player:IsA("Player")
end

function ShopMoney.create(options)
	options = options or {}

	local playerDataService = options.playerDataService
	local enemyDamageService = options.enemyDamageService

	local function canUsePlayerData(player)
		return isPlayerInstance(player) and playerDataService.isReady()
	end

	local function getCurrentMoney(player)
		if not isPlayerInstance(player) then
			return nil
		end

		if canUsePlayerData(player) then
			local savedMoney = playerDataService.get(player, { "money" })
			if savedMoney ~= nil then
				return normalizeMoneyAmount(savedMoney)
			end
		end

		local moneyValue = enemyDamageService.getMoneyValue(player)
		if moneyValue then
			return normalizeMoneyAmount(moneyValue.Value)
		end

		return nil
	end

	local function trySpendMoney(player, amount)
		local spendAmount = normalizeMoneyAmount(amount)
		if spendAmount <= 0 then
			return true
		end
		if not isPlayerInstance(player) then
			return false
		end

		if canUsePlayerData(player) then
			local didSpend = false
			playerDataService.update(player, { "money" }, function(m)
				local currentMoney = normalizeMoneyAmount(m)
				if currentMoney < spendAmount then
					return currentMoney
				end

				didSpend = true
				return currentMoney - spendAmount
			end)
			return didSpend
		end

		local moneyValue = enemyDamageService.getMoneyValue(player)
		if not moneyValue or moneyValue.Value < spendAmount then
			return false
		end

		moneyValue.Value -= spendAmount
		return true
	end

	local function refundMoney(player, amount)
		local refundAmount = normalizeMoneyAmount(amount)
		if refundAmount <= 0 then
			return
		end
		if not isPlayerInstance(player) then
			return
		end

		if canUsePlayerData(player) then
			playerDataService.update(player, { "money" }, function(m)
				return normalizeMoneyAmount(m) + refundAmount
			end)
			return
		end

		local moneyValue = enemyDamageService.getMoneyValue(player)
		if moneyValue then
			moneyValue.Value += refundAmount
		end
	end

	return {
		getCurrentMoney = getCurrentMoney,
		trySpendMoney = trySpendMoney,
		refundMoney = refundMoney,
	}
end

return ShopMoney
