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
	{
		Id = "sniper",
		DisplayName = "Sniper",
		Description = "Heavy-hitting marksman built for deliberate single-target eliminations.",
		WeaponTag = "Sniper",
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
			CriticalHitChance = 0.003,
			CriticalHitChancePerLevel = 0.00005,
			SuperCriticalHitChance = 0.00035,
			SuperCriticalHitChancePerLevel = 0.000008,
		},
	},
	{
		Id = "pyromaniac",
		DisplayName = "Pyromaniac",
		Description = "Flame specialist with chance to ignite enemies and deal burn damage over time.",
		WeaponTag = "Pyro",
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
			BurnChance = 0.005,
			BurnChancePerLevel = 0.0008,
			BurnDurationSeconds = 2,
			BurnDamageFractionPerSecond = 0.1,
		},
	},
	{
		Id = "sentrytech",
		DisplayName = "Sentry Tech",
		Description = "Deploys and repairs sentries. Debuff: takes double damage from all enemies.",
		WeaponTag = "SentryTech",
		Progression = {
			BaseXpToLevel = 94,
			XpGrowthPerLevel = 0.035,
		},
		Bonuses = {
			MoveSpeedPerLevel = 0.0035,
			RepairSpeedPerLevel = 0.002,
			TurretDamagePerLevel = 0.044,
			IncomingDamageMultiplier = 2,
		},
	},
}

return ClassCatalog
