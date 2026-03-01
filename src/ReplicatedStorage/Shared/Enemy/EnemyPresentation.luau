local EnemyPresentation = {
	HealthBar = {
		WidthPx = 90,
		HeightPx = 6,
		MaxDistance = 220,
		CriticalThreshold = 0.2,
		LowThreshold = 0.45,
		MidThreshold = 0.7,
		BackgroundColor = Color3.fromRGB(30, 30, 30),
		StrokeColor = Color3.fromRGB(0, 0, 0),
		Colors = {
			High = Color3.fromRGB(65, 220, 90),
			Mid = Color3.fromRGB(245, 215, 70),
			Low = Color3.fromRGB(245, 150, 60),
			Critical = Color3.fromRGB(220, 55, 55),
		},
	},
	DeathCloud = {
		StyleRollMax = {
			Smoke = 38,
			Explosion = 66,
			Shockwave = 84,
		},
		Scale = {
			Min = 0.9,
			Max = 1.9,
			SizeDivisor = 6,
		},
	},
}

return EnemyPresentation
