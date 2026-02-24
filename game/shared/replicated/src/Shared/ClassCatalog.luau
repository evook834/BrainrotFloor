local ClassCatalog = {
	-- Add more class entries here. Each class should have a unique Id and WeaponTag.
	{
		Id = "berserker",
		DisplayName = "Berserker",
		Description = "Close-range bruiser that scales hard with melee damage.",
		WeaponTag = "Berserker",
		Progression = {
			BaseXpToLevel = 90,
			XpGrowthPerLevel = 0.035,
			EarlyLevelXpRequirementMultiplier = 1 / 3,
			EarlyLevelXpUntilLevel = 20,
		},
		Bonuses = {
			DamagePerLevel = 0.0025,
			MaxHealthPerLevel = 0.0018,
			MoveSpeedPerLevel = 0.0015,
			DamageReductionPerLevel = 0.0015,
			MeleeRangePerLevel = 0.002,
		},
	},
	{
		Id = "commander",
		DisplayName = "Commander",
		Description = "Tactical weapon specialist with stronger sustained fire control.",
		WeaponTag = "Commander",
		Progression = {
			BaseXpToLevel = 96,
			XpGrowthPerLevel = 0.035,
		},
		Bonuses = {
			WeaponDamagePerLevel = 0.0025,
			ShopDiscountPerLevel = 0.0015,
			MagazineSizePerLevel = 0.002,
			ReloadSpeedPerLevel = 0.0025,
			BulletRangePerLevel = 0.003,
			BulletSpreadReductionPerLevel = 0.0055,
		},
	},
}

return ClassCatalog
