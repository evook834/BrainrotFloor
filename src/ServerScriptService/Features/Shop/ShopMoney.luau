--[[
	ShopMoney — Deprecated module, re-exported for backward compatibility.
	Use CurrencyService instead.
]]

warn("ShopMoney is deprecated. Use Shop.Currency.CurrencyService instead.")

return require(script.Parent.Currency.CurrencyService)
