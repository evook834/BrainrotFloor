local WeaponCatalog = require(script.Parent:WaitForChild("WeaponCatalog"))

local ShopConfig = {
	PurchaseAllowedStates = {
		Preparing = true,
		Cleared = true,
		Blocked = true,
	},
	Trader = {
		ModelName = "WeaponTrader",
		PartName = "TraderRoot",
		Position = Vector3.new(0, 4, -25),
		ActionText = "Open Store",
		ObjectText = "Weapon Trader",
		MaxActivationDistance = 12,
		HoldDuration = 0.15,
	},
	Weapons = WeaponCatalog,
}

return ShopConfig
