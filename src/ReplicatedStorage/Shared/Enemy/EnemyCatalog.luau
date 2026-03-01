--[[
	EnemyCatalog — Spawnable enemy definitions for wave spawn and lookup.
	Each entry: Id, TemplateName, optional DisplayName, MinWave, MaxWave (nil = all waves),
	Weight for pool selection, IsBoss (true = boss-wave only).
	Wave spawn logic filters by MinWave/MaxWave for normal waves and by IsBoss for boss wave.
	Wave 11 (boss) uses the entry with IsBoss = true; a template with that TemplateName
	(e.g. "Boss") must exist in ServerStorage/EnemyTemplates or spawnSingle returns nil.
]]

local EnemyDefinitions = require(script.Parent:WaitForChild("EnemyDefinitions"))

local EnemyCatalog = {}

for _, entry in ipairs(EnemyDefinitions.Entries) do
	table.insert(EnemyCatalog, {
		Id = entry.Id,
		TemplateName = entry.TemplateName,
		DisplayName = entry.DisplayName,
		MinWave = entry.MinWave,
		MaxWave = entry.MaxWave,
		Weight = entry.Weight,
		IsBoss = entry.IsBoss,
		Danger = entry.Danger,
		Tier = entry.Tier,
	})
end

return EnemyCatalog
