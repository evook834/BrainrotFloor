local EnemyProfiles = {
	DefaultProfile = {
		MoveSpeed = 12,
		AttackRange = 4.5,
		AttackDamage = 10,
		AttackCooldown = 1.2,
		AcquireRange = 220,
		ThinkInterval = 0.15,
		TurnSpeed = 12,
		AttackWindup = 0.2,
		ChaseAnimationId = "",
		AttackAnimationId = "",
	},
	TemplateProfiles = {
		Ramar = {
			MoveSpeed = 11,
			AttackRange = 5,
			AttackDamage = 14,
			AttackCooldown = 1,
			TurnSpeed = 14,
			SpawnOffsetY = -0.5,
			ChaseAnimationId = "rbxassetid://507777826",
			AttackAnimationId = "rbxassetid://522635514",
		},
		Bombardiro_Crocodilo = {
			FacingYawOffsetDegrees = 270,
			HitboxScale = 2.8,
			HitboxPadding = 1.1,
		},
		KarKerKar_Tries = {
			FacingPitchOffsetDegrees = 90,
		},
	},
}

return EnemyProfiles
