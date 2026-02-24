local ClassProgression = {}

local bonusPctKeyAliases = {
	Damage = "damagePct",
	WeaponDamage = "damagePct",
	MaxHealth = "maxHealthPct",
	MoveSpeed = "moveSpeedPct",
	MeleeRange = "meleeRangePct",
	DamageReduction = "damageReductionPct",
	ShopDiscount = "shopDiscountPct",
	ShopCostReduction = "shopDiscountPct",
	MagazineSize = "magazineSizePct",
	MagSize = "magazineSizePct",
	ReloadSpeed = "reloadSpeedPct",
	Reload = "reloadSpeedPct",
	BulletRange = "bulletRangePct",
	WeaponRange = "bulletRangePct",
	Range = "bulletRangePct",
	BulletSpreadReduction = "bulletSpreadReductionPct",
	SpreadReduction = "bulletSpreadReductionPct",
	Accuracy = "bulletSpreadReductionPct",
}

local function resolveBonusPctKeyFromPerLevel(rawBonusKey)
	if type(rawBonusKey) ~= "string" then
		return nil
	end

	local stem = string.match(rawBonusKey, "^(.+)PerLevel$")
	if not stem or stem == "" then
		return nil
	end

	local alias = bonusPctKeyAliases[stem]
	if alias then
		return alias
	end

	return string.lower(string.sub(stem, 1, 1)) .. string.sub(stem, 2) .. "Pct"
end

local function summarizeBonuses(bonuses)
	local resolvedBonuses = bonuses or {}
	local damageMultiplier = resolvedBonuses.damageMultiplier or 1
	local maxHealthMultiplier = resolvedBonuses.maxHealthMultiplier or 1
	local moveSpeedMultiplier = resolvedBonuses.moveSpeedMultiplier or 1
	local meleeRangeMultiplier = resolvedBonuses.meleeRangeMultiplier or 1
	local incomingDamageMultiplier = resolvedBonuses.incomingDamageMultiplier or 1
	local shopCostMultiplier = resolvedBonuses.shopCostMultiplier or 1
	local shopDiscount = resolvedBonuses.shopDiscount or 0
	local magazineSizeMultiplier = resolvedBonuses.magazineSizeMultiplier or 1
	local reloadTimeMultiplier = resolvedBonuses.reloadTimeMultiplier or 1
	local bulletRangeMultiplier = resolvedBonuses.bulletRangeMultiplier or 1
	local bulletSpreadMultiplier = resolvedBonuses.bulletSpreadMultiplier or 1
	local reloadSpeedMultiplier = 1 / math.max(0.1, reloadTimeMultiplier)

	return {
		damageMultiplier = damageMultiplier,
		maxHealthMultiplier = maxHealthMultiplier,
		moveSpeedMultiplier = moveSpeedMultiplier,
		meleeRangeMultiplier = meleeRangeMultiplier,
		incomingDamageMultiplier = incomingDamageMultiplier,
		shopCostMultiplier = shopCostMultiplier,
		shopDiscount = shopDiscount,
		magazineSizeMultiplier = magazineSizeMultiplier,
		reloadTimeMultiplier = reloadTimeMultiplier,
		bulletRangeMultiplier = bulletRangeMultiplier,
		bulletSpreadMultiplier = bulletSpreadMultiplier,
		damagePct = (damageMultiplier - 1) * 100,
		maxHealthPct = (maxHealthMultiplier - 1) * 100,
		moveSpeedPct = (moveSpeedMultiplier - 1) * 100,
		meleeRangePct = (meleeRangeMultiplier - 1) * 100,
		damageReductionPct = (1 - incomingDamageMultiplier) * 100,
		shopDiscountPct = shopDiscount * 100,
		magazineSizePct = (magazineSizeMultiplier - 1) * 100,
		reloadSpeedPct = (reloadSpeedMultiplier - 1) * 100,
		bulletRangePct = (bulletRangeMultiplier - 1) * 100,
		bulletSpreadReductionPct = (1 - bulletSpreadMultiplier) * 100,
	}
end

function ClassProgression.getMaxLevel(rawClassSystemConfig)
	local classSystemConfig = rawClassSystemConfig or {}
	local maxLevel = math.floor(tonumber(classSystemConfig.MaxLevel) or 200)
	if maxLevel < 1 then
		maxLevel = 1
	end
	return maxLevel
end

function ClassProgression.getXpRequiredForNextLevel(rawClassSystemConfig, classDef, level)
	if not classDef then
		return nil
	end

	local classSystemConfig = rawClassSystemConfig or {}
	if level >= ClassProgression.getMaxLevel(classSystemConfig) then
		return nil
	end

	local progression = classDef.Progression or {}
	local baseXp = math.max(10, tonumber(progression.BaseXpToLevel) or 100)
	local growth = math.clamp(tonumber(progression.XpGrowthPerLevel) or 0.05, 0, 1)
	local requirement = baseXp * ((1 + growth) ^ math.max(0, level - 1))

	local progressionCurve = classSystemConfig.ProgressionCurve or {}
	local levelBandSize = math.max(1, math.floor(tonumber(progressionCurve.LevelBandSize) or 10))
	local decadeStepMultiplier = math.max(1, tonumber(progressionCurve.DecadeStepMultiplier) or 1)
	if decadeStepMultiplier > 1 then
		local levelBandIndex = math.floor(math.max(0, level - 1) / levelBandSize)
		requirement *= decadeStepMultiplier ^ levelBandIndex
	end

	local earlyLevelsFastUntil = math.max(1, math.floor(tonumber(progressionCurve.EarlyLevelsFastUntil) or 1))
	local earlyLevelsMultiplier = math.clamp(tonumber(progressionCurve.EarlyLevelsMultiplier) or 1, 0.1, 1)
	if earlyLevelsMultiplier < 1 and level <= earlyLevelsFastUntil then
		local blendAlpha = 1
		if earlyLevelsFastUntil > 1 then
			blendAlpha = (level - 1) / (earlyLevelsFastUntil - 1)
		end
		local earlyScale = earlyLevelsMultiplier + ((1 - earlyLevelsMultiplier) * blendAlpha)
		requirement *= earlyScale
	end

	local classXpRequirementMultiplier = math.max(0.001, tonumber(progression.XpRequirementMultiplier) or 1)
	requirement *= classXpRequirementMultiplier

	local earlyLevelXpRequirementMultiplier = math.max(0.001, tonumber(progression.EarlyLevelXpRequirementMultiplier) or 1)
	if earlyLevelXpRequirementMultiplier ~= 1 then
		local earlyLevelXpUntilLevel = math.max(
			1,
			math.floor(tonumber(progression.EarlyLevelXpUntilLevel) or earlyLevelsFastUntil)
		)
		if level <= earlyLevelXpUntilLevel then
			requirement *= earlyLevelXpRequirementMultiplier
		end
	end

	local xpRequirementMultiplier = math.max(0.001, tonumber(classSystemConfig.XpRequirementMultiplier) or 1)
	requirement *= xpRequirementMultiplier

	return math.max(1, math.floor(requirement + 0.5))
end

function ClassProgression.applyXpGain(rawClassSystemConfig, classDef, level, xp, rawXpGain)
	local resolvedLevel = tonumber(level) or 1
	local resolvedXp = tonumber(xp) or 0
	local xpGain = math.max(0, tonumber(rawXpGain) or 0)
	local maxLevel = ClassProgression.getMaxLevel(rawClassSystemConfig)
	local leveledUp = false

	while xpGain > 0 and resolvedLevel < maxLevel do
		local xpToNext = ClassProgression.getXpRequiredForNextLevel(rawClassSystemConfig, classDef, resolvedLevel)
		if not xpToNext then
			break
		end

		local missingXp = math.max(0, xpToNext - resolvedXp)
		if xpGain >= missingXp then
			xpGain -= missingXp
			resolvedLevel += 1
			resolvedXp = 0
			leveledUp = true
		else
			resolvedXp += xpGain
			xpGain = 0
		end
	end

	if resolvedLevel >= maxLevel then
		resolvedLevel = maxLevel
		resolvedXp = 0
	end

	return {
		level = resolvedLevel,
		xp = resolvedXp,
		leveledUp = leveledUp,
	}
end

function ClassProgression.getBonusesAtLevel(classDef, level)
	local levelIndex = math.max(1, math.floor(tonumber(level) or 1))
	local bonusLevels = levelIndex - 1
	local bonuses = classDef and classDef.Bonuses or {}

	local damagePerLevel = math.max(
		0,
		tonumber(bonuses.DamagePerLevel)
			or tonumber(bonuses.WeaponDamagePerLevel)
			or 0
	)
	local damageMultiplier = 1 + (damagePerLevel * bonusLevels)
	local maxHealthMultiplier = 1 + (math.max(0, tonumber(bonuses.MaxHealthPerLevel) or 0) * bonusLevels)
	local moveSpeedMultiplier = 1 + (math.max(0, tonumber(bonuses.MoveSpeedPerLevel) or 0) * bonusLevels)
	local meleeRangeMultiplier = 1 + (math.max(0, tonumber(bonuses.MeleeRangePerLevel) or 0) * bonusLevels)
	local totalDamageReduction = math.clamp(
		math.max(0, tonumber(bonuses.DamageReductionPerLevel) or 0) * bonusLevels,
		0,
		0.85
	)
	local incomingDamageMultiplier = 1 - totalDamageReduction
	local shopDiscount = math.clamp(
		math.max(0, tonumber(bonuses.ShopDiscountPerLevel) or tonumber(bonuses.ShopCostReductionPerLevel) or 0) * bonusLevels,
		0,
		0.9
	)
	local magazineSizeMultiplier = 1
		+ (
			math.max(0, tonumber(bonuses.MagazineSizePerLevel) or tonumber(bonuses.MagSizePerLevel) or 0) * bonusLevels
		)
	local reloadSpeedBonus = math.max(0, tonumber(bonuses.ReloadSpeedPerLevel) or tonumber(bonuses.ReloadPerLevel) or 0)
		* bonusLevels
	local reloadTimeMultiplier = 1 / (1 + reloadSpeedBonus)
	local bulletRangeMultiplier = 1
		+ (
			math.max(
				0,
				tonumber(bonuses.BulletRangePerLevel)
					or tonumber(bonuses.WeaponRangePerLevel)
					or tonumber(bonuses.RangePerLevel)
					or 0
			) * bonusLevels
		)
	local spreadReduction = math.clamp(
		math.max(
			0,
			tonumber(bonuses.BulletSpreadReductionPerLevel)
				or tonumber(bonuses.SpreadReductionPerLevel)
				or tonumber(bonuses.AccuracyPerLevel)
				or 0
		) * bonusLevels,
		0,
		0.8
	)
	local bulletSpreadMultiplier = 1 - spreadReduction

	return {
		damageMultiplier = math.max(0, damageMultiplier),
		maxHealthMultiplier = math.max(0.1, maxHealthMultiplier),
		moveSpeedMultiplier = math.max(0.1, moveSpeedMultiplier),
		meleeRangeMultiplier = math.max(0.1, meleeRangeMultiplier),
		incomingDamageMultiplier = math.max(0.05, incomingDamageMultiplier),
		shopCostMultiplier = math.max(0.1, 1 - shopDiscount),
		shopDiscount = shopDiscount,
		magazineSizeMultiplier = math.max(0.1, magazineSizeMultiplier),
		reloadTimeMultiplier = math.max(0.1, reloadTimeMultiplier),
		bulletRangeMultiplier = math.max(0.1, bulletRangeMultiplier),
		bulletSpreadMultiplier = math.max(0.2, bulletSpreadMultiplier),
	}
end

function ClassProgression.buildPerLevelBonusesFromConfig(rawBonusConfig)
	local perLevelBonuses = {}
	if type(rawBonusConfig) ~= "table" then
		return perLevelBonuses
	end

	for rawBonusKey, rawPerLevelValue in pairs(rawBonusConfig) do
		local pctKey = resolveBonusPctKeyFromPerLevel(rawBonusKey)
		local perLevelValue = tonumber(rawPerLevelValue)
		if pctKey and perLevelValue then
			local pctValue = perLevelValue * 100
			local existing = perLevelBonuses[pctKey]
			if type(existing) ~= "number" or math.abs(pctValue) > math.abs(existing) then
				perLevelBonuses[pctKey] = pctValue
			end
		end
	end

	return perLevelBonuses
end

function ClassProgression.buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)
	local currentBonuses = summarizeBonuses(classBonuses)
	local bonusLevels = math.max(0, math.floor(tonumber(level) or 1) - 1)

	for pctKey, perLevelValue in pairs(perLevelBonuses or {}) do
		if currentBonuses[pctKey] == nil then
			currentBonuses[pctKey] = (tonumber(perLevelValue) or 0) * bonusLevels
		end
	end

	return currentBonuses
end

return ClassProgression
