--[[
	EnemyCatalog — Spawnable enemy definitions for wave spawn and lookup.
	Each entry: Id (stable id), TemplateName (matches ServerStorage template + EnemyProfiles key),
	optional DisplayName, MinWave, MaxWave, Weight for pool selection.
	Wave spawn logic uses this to decide which enemy types can spawn in a given wave.
]]

local EnemyCatalog = {
	{ Id = "ramar", TemplateName = "Ramar", DisplayName = "Ramar", MinWave = 1, Weight = 1 },
	{ Id = "bombardiro_crocodilo", TemplateName = "Bombardiro_Crocodilo", DisplayName = "Bombardiro Crocodilo", MinWave = 1, Weight = 1 },
	{ Id = "karkerkar_tries", TemplateName = "KarKerKar_Tries", DisplayName = "KarKerKar Tries", MinWave = 1, Weight = 1 },
}

return EnemyCatalog
