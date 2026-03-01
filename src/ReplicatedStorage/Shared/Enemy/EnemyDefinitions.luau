local EnemyDefinitions = {}
local KNOWN_VARIANT_PREFIXES = {
	"diamond",
	"galaxy",
	"gold",
	"hacker",
	"lava",
	"rainbow",
}

EnemyDefinitions.DefaultProfile = {
	MoveSpeed = 12,
	AttackRange = 4.5,
	AttackDamage = 10,
	AttackCooldown = 1.2,
	AcquireRange = 220,
	ThinkInterval = 0.15,
	TurnSpeed = 12,
	FacingPitchOffsetDegrees = 0,
	FacingYawOffsetDegrees = 0,
	FacingRollOffsetDegrees = 0,
	AttackWindup = 0.2,
	ChaseAnimationId = "",
	AttackAnimationId = "",
}

EnemyDefinitions.DefaultDanger = "Weakling"
EnemyDefinitions.DangerLevels = {
	"Weakling",
	"Medium",
	"Hard",
	"VeryHard",
	"MaxDanger",
}

local DANGER_ALIAS_TO_DATA = {
	easy = { danger = "Weakling", tier = "Easy" },
	weakling = { danger = "Weakling", tier = "Easy" },
	weaklings = { danger = "Weakling", tier = "Easy" },
	medium = { danger = "Medium", tier = "Medium" },
	mediums = { danger = "Medium", tier = "Medium" },
	hard = { danger = "Hard", tier = "Hard" },
	veryhard = { danger = "VeryHard", tier = "Elite" },
	elite = { danger = "VeryHard", tier = "Elite" },
	maxdanger = { danger = "MaxDanger", tier = "Elite" },
}

local function normalizeDanger(value)
	if type(value) == "string" then
		local normalizedKey = string.lower(value):gsub("[%s_%-]", "")
		local data = DANGER_ALIAS_TO_DATA[normalizedKey]
		if data then
			return data.danger, data.tier
		end
	end

	local defaultData = DANGER_ALIAS_TO_DATA[string.lower(EnemyDefinitions.DefaultDanger)]
	return defaultData.danger, defaultData.tier
end

local function normalizeTemplateLookupKey(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedKey = string.lower(value)
	normalizedKey = normalizedKey:gsub("[%s_%-]+", " ")
	normalizedKey = normalizedKey:gsub("^%s+", "")
	normalizedKey = normalizedKey:gsub("%s+$", "")
	return normalizedKey
end

-- Add one entry per model in ServerStorage/EnemyTemplates using the exact model name as the key.
-- Valid Danger values: "Weakling", "Medium", "Hard", "VeryHard", "MaxDanger".
EnemyDefinitions.TemplateSettings = {
	["Banana Dancana"] = {
		DisplayName = "Banana Dancana",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
		Profile = {
			MoveSpeed = 11,
			AttackRange = 5,
			AttackDamage = 14,
			AttackCooldown = 1,
			TurnSpeed = 14,
			SpawnOffsetY = -0.5,
			ChaseAnimationId = "rbxassetid://507777826",
			AttackAnimationId = "rbxassetid://522635514",
		},
	},
	["Fluri Flura"] = {
		DisplayName = "Fluri Flura",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
		Profile = {
			MoveSpeed = 11,
			AttackRange = 5,
			AttackDamage = 14,
			AttackCooldown = 1,
			TurnSpeed = 14,
			SpawnOffsetY = -0.5,
			ChaseAnimationId = "rbxassetid://507777826",
			AttackAnimationId = "rbxassetid://522635514",
		},
	},
	["Gorillo Watermelondrillo"] = {
		DisplayName = "Gorillo Watermelondrillo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Medium",
	},
	["Lionel Cactuseli"] = {
		DisplayName = "Lionel Cactuseli",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Medium",
	},
	["Strawberrelli Flamingelli"] = {
		DisplayName = "Strawberrelli Flamingelli",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Strawberry Elephant"] = {
		DisplayName = "Strawberry Elephant",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Svinina Bombardino"] = {
		DisplayName = "Svinina Bombardino",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Swag Soda"] = {
		DisplayName = "Swag Soda",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Ta Ta Ta Ta Sahur"] = {
		DisplayName = "Ta Ta Ta Ta Sahur",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Talpa Di Fero Tigroligre Frutonni"] = {
		DisplayName = "Talpa Di Fero Tigroligre Frutonni",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tim Cheese"] = {
		DisplayName = "Tim Cheese",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tirilikalika Tirilikalako"] = {
		DisplayName = "Tirilikalika Tirilikalako",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Torrtuginni Dragonfrutini"] = {
		DisplayName = "Torrtuginni Dragonfrutini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tralaledon"] = {
		DisplayName = "Tralaledon",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tralalero Tralala"] = {
		DisplayName = "Tralalero Tralala",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tralalita Tralala"] = {
		DisplayName = "Tralalita Tralala",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["1x1x1x1"] = {
		DisplayName = "1x1x1x1",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Agarrini La Pallini"] = {
		DisplayName = "Agarrini La Pallini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Avocadini Guffo"] = {
		DisplayName = "Avocadini Guffo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Ballerina Cappuccina"] = {
		DisplayName = "Ballerina Cappuccina",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Ballerino Lololo"] = {
		DisplayName = "Ballerino Lololo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bambini Crostini"] = {
		DisplayName = "Bambini Crostini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bananini Kittini"] = {
		DisplayName = "Bananini Kittini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bananita Dolphinita"] = {
		DisplayName = "Bananita Dolphinita",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Blueberrinni Octopusini"] = {
		DisplayName = "Blueberrinni Octopusini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bobrito Bandito"] = {
		DisplayName = "Bobrito Bandito",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bombardiro Crocodilo"] = {
		DisplayName = "Bombardiro Crocodilo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Bombombini Gusini"] = {
		DisplayName = "Bombombini Gusini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Boneca Ambalabu"] = {
		DisplayName = "Boneca Ambalabu",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Brr Brr Patapim"] = {
		DisplayName = "Brr Brr Patapim",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Brri Brri Bicus Dicus"] = {
		DisplayName = "Brri Brri Bicus Dicus",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Burbaloni Luliloli"] = {
		DisplayName = "Burbaloni Luliloli",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Cachorrito Melonito"] = {
		DisplayName = "Cachorrito Melonito",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Cacto Hipopotamo"] = {
		DisplayName = "Cacto Hipopotamo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Cappuccino Assassino"] = {
		DisplayName = "Cappuccino Assassino",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Cavallo Virtuoso"] = {
		DisplayName = "Cavallo Virtuoso",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Chef Crabracadabra"] = {
		DisplayName = "Chef Crabracadabra",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Chicleteira Bicicleteira"] = {
		DisplayName = "Chicleteira Bicicleteira",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Chicleteirina Bicicleteirina"] = {
		DisplayName = "Chicleteirina Bicicleteirina",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Chillin Chili"] = {
		DisplayName = "Chillin Chili",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Chimpanzini Bananini"] = {
		DisplayName = "Chimpanzini Bananini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Cocofanto Elefanto"] = {
		DisplayName = "Cocofanto Elefanto",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Dragon Cannelloni"] = {
		DisplayName = "Dragon Cannelloni",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Esok Sekolah"] = {
		DisplayName = "Esok Sekolah",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Espresso Signora"] = {
		DisplayName = "Espresso Signora",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Frigo Camelo"] = {
		DisplayName = "Frigo Camelo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Ganganzelli Trulala"] = {
		DisplayName = "Ganganzelli Trulala",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Gangster Footera"] = {
		DisplayName = "Gangster Footera",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Garamararam"] = {
		DisplayName = "Garamararam",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Girafa Celeste"] = {
		DisplayName = "Girafa Celeste",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Glorbo Fruttodrillo"] = {
		DisplayName = "Glorbo Fruttodrillo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Illuminato Triangolo"] = {
		DisplayName = "Illuminato Triangolo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Job Job Job Sahur"] = {
		DisplayName = "Job Job Job Sahur",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Karkerkar Kurkur"] = {
		DisplayName = "Karkerkar Kurkur",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["La Grande Combinasion"] = {
		DisplayName = "La Grande Combinasion",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["La Vacca"] = {
		DisplayName = "La Vacca",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Saturno Saturnita"] = {
		DisplayName = "Saturno Saturnita",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Lerulerulerule"] = {
		DisplayName = "Lerulerulerule",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Lirili Larila"] = {
		DisplayName = "Lirili Larila",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Los Tralaleritos"] = {
		DisplayName = "Los Tralaleritos",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Madudung"] = {
		DisplayName = "Madudung",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Matteo"] = {
		DisplayName = "Matteo",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Meowl"] = {
		DisplayName = "Meowl",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Noo My Examen"] = {
		DisplayName = "Noo My Examen",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Nyannini Cattalini"] = {
		DisplayName = "Nyannini Cattalini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Odin Din Din Dun"] = {
		DisplayName = "Odin Din Din Dun",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Orangutini Ananassini"] = {
		DisplayName = "Orangutini Ananassini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Orcalero Orcala"] = {
		DisplayName = "Orcalero Orcala",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pakrahmatmamat"] = {
		DisplayName = "Pakrahmatmamat",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pakrahmatmatina"] = {
		DisplayName = "Pakrahmatmatina",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pandaccini Bananini"] = {
		DisplayName = "Pandaccini Bananini",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pipi Kiwi"] = {
		DisplayName = "Pipi Kiwi",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pipi Potato"] = {
		DisplayName = "Pipi Potato",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Pot Hotspot"] = {
		DisplayName = "Pot Hotspot",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
		["Quesadilla Crocodila"] = {
		DisplayName = "Quesadilla Crocodila",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Rhino Toasterino"] = {
		DisplayName = "Rhino Toasterino",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Six Seven"] = {
		DisplayName = "Six Seven",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Smurfo Gatto"] = {
		DisplayName = "Smurfo Gatto",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tric Trac Barabum"] = {
		DisplayName = "Tric Trac Barabum",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Triplito Tralaleritos"] = {
		DisplayName = "Triplito Tralaleritos",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Trippi Troppi"] = {
		DisplayName = "Trippi Troppi",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Trippi Troppi Troppa Trippa"] = {
		DisplayName = "Trippi Troppi Troppa Trippa",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Trulimero Trulicina"] = {
		DisplayName = "Trulimero Trulicina",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["Tung Sahur"] = {
		DisplayName = "Tung Sahur",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
	["W Or L"] = {
		DisplayName = "W Or L",
		MinWave = 1,
		MaxWave = nil,
		Weight = 1,
		IsBoss = false,
		Danger = "Weakling",
	},
}

local NORMALIZED_TEMPLATE_NAME_TO_BASE = {}

for templateName in pairs(EnemyDefinitions.TemplateSettings) do
	local normalizedKey = normalizeTemplateLookupKey(templateName)
	if normalizedKey and normalizedKey ~= "" then
		NORMALIZED_TEMPLATE_NAME_TO_BASE[normalizedKey] = templateName
	end
end

local function resolveBaseTemplateName(templateName)
	if type(templateName) ~= "string" or templateName == "" then
		return templateName
	end

	if EnemyDefinitions.TemplateSettings[templateName] then
		return templateName
	end

	local normalizedKey = normalizeTemplateLookupKey(templateName)
	if not normalizedKey or normalizedKey == "" then
		return templateName
	end

	local directMatch = NORMALIZED_TEMPLATE_NAME_TO_BASE[normalizedKey]
	if directMatch then
		return directMatch
	end

	while true do
		local strippedPrefix = false

		for _, prefix in ipairs(KNOWN_VARIANT_PREFIXES) do
			local prefixToken = prefix .. " "
			if string.sub(normalizedKey, 1, #prefixToken) == prefixToken then
				normalizedKey = string.sub(normalizedKey, #prefixToken + 1)
				strippedPrefix = true
				break
			end
		end

		if not strippedPrefix then
			break
		end

		local resolvedBaseName = NORMALIZED_TEMPLATE_NAME_TO_BASE[normalizedKey]
		if resolvedBaseName then
			return resolvedBaseName
		end
	end

	return templateName
end

EnemyDefinitions.normalizeDanger = normalizeDanger
EnemyDefinitions.resolveBaseTemplateName = resolveBaseTemplateName

local function buildEntries()
	local entries = {}

	for templateName, templateSettings in pairs(EnemyDefinitions.TemplateSettings) do
		if type(templateName) == "string" and templateName ~= "" and type(templateSettings) == "table" then
			local danger, tier = normalizeDanger(templateSettings.Danger)
			local minWave = tonumber(templateSettings.MinWave)
			local maxWave = tonumber(templateSettings.MaxWave)
			local weight = tonumber(templateSettings.Weight)

			table.insert(entries, {
				Id = tostring(templateSettings.Id or templateName),
				TemplateName = templateName,
				DisplayName = tostring(templateSettings.DisplayName or templateName),
				MinWave = if minWave then math.max(1, math.floor(minWave + 0.5)) else 1,
				MaxWave = if maxWave then math.max(1, math.floor(maxWave + 0.5)) else nil,
				Weight = if weight then math.max(0, weight) else 1,
				IsBoss = templateSettings.IsBoss == true,
				Danger = danger,
				Tier = tier,
				Profile = if type(templateSettings.Profile) == "table" then table.clone(templateSettings.Profile) else nil,
			})
		end
	end

	table.sort(entries, function(a, b)
		return a.TemplateName < b.TemplateName
	end)

	return entries
end

EnemyDefinitions.Entries = buildEntries()

return EnemyDefinitions
