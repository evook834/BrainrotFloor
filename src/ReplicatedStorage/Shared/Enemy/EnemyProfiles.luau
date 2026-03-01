local EnemyDefinitions = require(script.Parent:WaitForChild("EnemyDefinitions"))

local EnemyProfiles = {
	DefaultProfile = table.clone(EnemyDefinitions.DefaultProfile),
	TemplateProfiles = {},
}

for _, entry in ipairs(EnemyDefinitions.Entries) do
	if type(entry.Profile) == "table" then
		EnemyProfiles.TemplateProfiles[entry.TemplateName] = table.clone(entry.Profile)
	end
end

return EnemyProfiles
