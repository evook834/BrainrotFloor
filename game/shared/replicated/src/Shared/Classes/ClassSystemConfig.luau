local ClassCatalog = require(script.Parent:WaitForChild("ClassCatalog"))

local ClassSystemConfig = {
	MaxLevel = 200,
	DefaultClassId = "berserker",
	DamageToXpScale = 1,
	XpRequirementMultiplier = 30,
	ProgressionCurve = {
		LevelBandSize = 10,
		DecadeStepMultiplier = 1.2,
		EarlyLevelsFastUntil = 20,
		EarlyLevelsMultiplier = 0.7,
		-- With DamageToXpScale = 1 and ~550k damage XP/hour, this lands near level 200 in ~100 hours.
	},
	SwitchAllowedStates = {
		Preparing = true,
		Cleared = true,
		Blocked = true,
	},
	Classes = ClassCatalog,
}

return ClassSystemConfig
