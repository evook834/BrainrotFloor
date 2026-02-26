--[[
	EnemyCatalog — Spawnable enemy definitions for wave spawn and lookup.
	Each entry: Id, TemplateName, optional DisplayName, MinWave, MaxWave (nil = all waves),
	Weight for pool selection, IsBoss (true = boss-wave only).
	Wave spawn logic filters by MinWave/MaxWave for normal waves and by IsBoss for boss wave.
	Wave 11 (boss) uses the entry with IsBoss = true; a template with that TemplateName
	(e.g. "Boss") must exist in ServerStorage/EnemyTemplates or spawnSingle returns nil.
]]

local EnemyCatalog = {
	{ Id = "ramar", TemplateName = "Ramar", DisplayName = "Ramar", MinWave = 1, MaxWave = nil, Weight = 1, IsBoss = false },
	{ Id = "bombardiro_crocodilo", TemplateName = "Bombardiro_Crocodilo", DisplayName = "Bombardiro Crocodilo", MinWave = 1, MaxWave = nil, Weight = 1, IsBoss = false },
	{ Id = "karkerkar_tries", TemplateName = "KarKerKar_Tries", DisplayName = "KarKerKar Tries", MinWave = 1, MaxWave = nil, Weight = 1, IsBoss = false },
	{ Id = "boss", TemplateName = "Boss", DisplayName = "Boss", MinWave = 11, MaxWave = 11, Weight = 1, IsBoss = true },
}

return EnemyCatalog
