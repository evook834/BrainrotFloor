--[[
	CurrencyService — Shop currency/money operations.
	Single source of truth for shop money operations using PlayerDataService.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local Match = script.Parent.Parent.Parent
local EnemyDamageService = require(Match.Combat.EnemyDamageService)

local function normalizeMoneyAmount(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function isPlayerInstance(player)
	return player and player:IsA("Player")
end

local function canUsePlayerData(player)
	return isPlayerInstance(player) and PlayerDataService.isReady() and PlayerDataService.hasProfile(player)
end

local function getMoneyAmount(player)
	if canUsePlayerData(player) then
		local savedMoney = PlayerDataService.get(player, { "money" })
		if savedMoney ~= nil then
			return normalizeMoneyAmount(savedMoney)
		end
	end

	-- Fallback: check leaderstats Money value
	local moneyValue = EnemyDamageService.getMoneyValue(player)
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
		PlayerDataService.update(player, { "money" }, function(m)
			local currentMoney = normalizeMoneyAmount(m)
			if currentMoney < spendAmount then
				return currentMoney
			end

			didSpend = true
			return currentMoney - spendAmount
		end, true)
		return didSpend
	end

	-- Fallback: leaderstats Money value
	local moneyValue = EnemyDamageService.getMoneyValue(player)
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
		PlayerDataService.update(player, { "money" }, function(m)
			return normalizeMoneyAmount(m) + refundAmount
		end, true)
		return
	end

	-- Fallback: leaderstats Money value
	local moneyValue = EnemyDamageService.getMoneyValue(player)
	if moneyValue then
		moneyValue.Value += refundAmount
	end
end

return {
	getMoneyAmount = getMoneyAmount,
	trySpendMoney = trySpendMoney,
	refundMoney = refundMoney,
}
