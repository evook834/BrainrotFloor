--[[
	WaveSpawnLogic — KF1-style director: WaveTotalTarget, AliveCap, role caps, composition.
	Returns isBossWave, totalCap (WaveTotalTarget clamped), aliveCap, roleCaps, targetCountByRole,
	and pickTemplate(roleAlive, totalSpawnedByRole) -> { templateName, tier }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local DifficultyService = require(Match.Difficulty.DifficultyService)

export type Role = "trash" | "medium" | "heavy" | "special"

export type RoleCounts = {
	trash: number,
	medium: number,
	heavy: number,
	special: number,
}

export type WaveComposition = {
	isBossWave: boolean,
	totalCap: number,
	aliveCap: number,
	roleCaps: RoleCounts,
	targetCountByRole: RoleCounts,
	pickTemplate: (RoleCounts?, RoleCounts?) -> { templateName: string, tier: string }?,
}

local DEFAULT_TIER = "Easy"

-- Catalog tier (Easy/Medium/Hard/Elite) maps to director role (trash/medium/heavy/special).
local TIER_TO_ROLE: { [string]: Role } = {
	Easy = "trash",
	Medium = "medium",
	Hard = "heavy",
	Elite = "special",
}

local function getTier(entry)
	local t = entry.Tier
	if type(t) == "string" and (t == "Easy" or t == "Medium" or t == "Hard" or t == "Elite") then
		return t
	end
	return DEFAULT_TIER
end

local function getRole(entry): Role
	return TIER_TO_ROLE[getTier(entry)] or "trash"
end

-- KF1-style: Easy dominates early, Medium/Hard/Elite ramp by wave. All multipliers non-negative.
local function tierMultiplier(waveNumber, tier)
	local w = math.max(1, math.floor(waveNumber + 0.5))
	if tier == "Easy" then
		return math.max(0, 1 - (w - 1) * 0.12)
	end
	if tier == "Medium" then
		if w < 2 then
			return 0
		end
		return math.min(1, (w - 2) * 0.22)
	end
	if tier == "Hard" then
		if w < 5 then
			return 0
		end
		return math.min(1, (w - 5) / 5)
	end
	if tier == "Elite" then
		if w < 7 then
			return 0
		end
		return math.min(1, (w - 7) / 3)
	end
	return 1
end

local function weightedRandomPick(entriesWithWeights)
	local total = 0
	for _, ew in entriesWithWeights do
		total += ew.weight
	end
	if total <= 0 then
		if #entriesWithWeights > 0 then
			return entriesWithWeights[math.random(1, #entriesWithWeights)].entry
		end
		return nil
	end
	local r = math.random() * total
	for _, ew in entriesWithWeights do
		r -= ew.weight
		if r <= 0 then
			return ew.entry
		end
	end
	return entriesWithWeights[#entriesWithWeights].entry
end

-- Director scaling: CountMult(p) = 1 + K * (p-1)^exp
local function countMult(playerCount: number): number
	local dir = Config.Wave.Director
	if not dir then
		return 1
	end
	local p = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local k = tonumber(dir.CountMultK) or 0.50
	local exp = tonumber(dir.CountMultExp) or 0.60
	return 1 + k * ((p - 1) ^ exp)
end

-- AliveMult(p) = 1 + K * (p-1)^exp
local function aliveMult(playerCount: number): number
	local dir = Config.Wave.Director
	if not dir then
		return 1
	end
	local p = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local k = tonumber(dir.AliveMultK) or 0.35
	local exp = tonumber(dir.AliveMultExp) or 0.70
	return 1 + k * ((p - 1) ^ exp)
end

local function getDiffMultipliers(difficulty: string): (number, number)
	local settings = DifficultyService.getSettings(difficulty)
	return tonumber(settings.DiffTotal) or 1, tonumber(settings.DiffAlive) or 1
end

-- Role caps: TrashCap/MediumCap from fractions of AliveCap; SpecialCap/HeavyCap from formulas.
local function computeRoleCaps(aliveCap: number, waveNumber: number, playerCount: number, difficulty: string): RoleCounts
	local w = math.max(1, math.floor((tonumber(waveNumber) or 1) + 0.5))
	local p = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local dir = Config.Wave.Director or {}
	local trashFrac = tonumber(dir.TrashCapFraction) or 0.70
	local medFrac = tonumber(dir.MediumCapFraction) or 0.28

	local trashCap = math.max(0, math.floor(aliveCap * trashFrac + 0.5))
	local mediumCap = math.max(0, math.floor(aliveCap * medFrac + 0.5))
	local specialCap = 1 + math.floor(w / 3) + math.floor((p - 1) / 6)
	local heavyCap = math.max(0, math.floor((w - 6) / 2) + math.floor((p - 1) / 10))

	if difficulty == "Hard" or difficulty == "Nightmare" then
		specialCap += 1
		heavyCap += 1
	end

	return {
		trash = trashCap,
		medium = mediumCap,
		heavy = math.max(0, heavyCap),
		special = math.max(0, specialCap),
	}
end

-- Target spawn counts by role from composition % and wave total.
local function computeTargetCountByRole(waveTotalPlanned: number, waveNumber: number): RoleCounts
	local comp = Config.Wave.CompositionPercentByWave
	if type(comp) ~= "table" then
		return { trash = waveTotalPlanned, medium = 0, heavy = 0, special = 0 }
	end
	local w = math.max(1, math.min(10, math.floor((tonumber(waveNumber) or 1) + 0.5)))
	local row = comp[w] or comp[10] or { trash = 100, medium = 0, heavy = 0, special = 0 }
	return {
		trash = math.max(0, math.floor(waveTotalPlanned * (tonumber(row.trash) or 100) / 100 + 0.5)),
		medium = math.max(0, math.floor(waveTotalPlanned * (tonumber(row.medium) or 0) / 100 + 0.5)),
		heavy = math.max(0, math.floor(waveTotalPlanned * (tonumber(row.heavy) or 0) / 100 + 0.5)),
		special = math.max(0, math.floor(waveTotalPlanned * (tonumber(row.special) or 0) / 100 + 0.5)),
	}
end

-- Legacy: total cap when Director is not used (e.g. no Director table).
local function getScaledWaveCapLegacy(waveNumber: number, playerCount: number, maxMonstersPerWave: number): number
	local wave = math.max(1, math.floor((tonumber(waveNumber) or 1) + 0.5))
	local players = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local cap = math.max(1, tonumber(maxMonstersPerWave) or 1500)

	local baseEnemiesPerWave = math.max(1, tonumber(Config.Wave.BaseEnemiesPerWave) or 10)
	local baseCount = baseEnemiesPerWave * wave

	local scaling = Config.Wave.WaveScaling or {}
	local basePlayers = math.max(1, tonumber(scaling.BasePlayers) or 1)
	local perExtra = tonumber(scaling.EnemiesPerExtraPlayer) or 1
	local maxMult = math.max(1, tonumber(scaling.MaxEnemyCountMultiplier) or 2)
	local playerScale = 1 + (players - basePlayers) * perExtra * 0.15
	playerScale = math.min(maxMult, math.max(1, playerScale))

	local difficulty = DifficultyService.getCurrentDifficulty()
	local healthMult = tonumber(DifficultyService.getNumberSetting("EnemyHealthMultiplier", 1, difficulty)) or 1
	local countMult = tonumber(DifficultyService.getNumberSetting("EnemyCountMultiplier", 1, difficulty)) or 1
	local ttkScale = (healthMult > 0) and (1 / healthMult) or 1

	local total = baseCount * playerScale * countMult * ttkScale
	total = math.max(1, math.floor(total + 0.5))
	return math.min(total, cap)
end

function getWaveComposition(waveNumber: number, playerCount: number, maxMonstersPerWave: number): WaveComposition
	local catalog = Config.Enemy.Catalog
	if type(catalog) ~= "table" or #catalog == 0 then
		return {
			isBossWave = false,
			totalCap = 0,
			aliveCap = 0,
			roleCaps = { trash = 0, medium = 0, heavy = 0, special = 0 },
			targetCountByRole = { trash = 0, medium = 0, heavy = 0, special = 0 } :: RoleCounts,
			pickTemplate = function()
				return nil
			end,
		}
	end

	local bossWaveNumber = Config.Wave.BossWaveNumber or 11
	local isBossWave = (waveNumber >= bossWaveNumber)
	local wave = math.max(1, math.floor((tonumber(waveNumber) or 1) + 0.5))
	local players = math.max(1, math.floor((tonumber(playerCount) or 1) + 0.5))
	local cap = math.max(1, tonumber(maxMonstersPerWave) or 1500)
	local difficulty = DifficultyService.getCurrentDifficulty()

	if isBossWave then
		local totalCap = math.min(math.max(1, playerCount), 10)
		local pool = {}
		for _, entry in catalog do
			if entry.IsBoss then
				table.insert(pool, { entry = entry, weight = entry.Weight or 1 })
			end
		end
		local pickTemplate = function()
			local entry = weightedRandomPick(pool)
			if entry and entry.TemplateName then
				return { templateName = entry.TemplateName, tier = getTier(entry) }
			end
			return nil
		end
		return {
			isBossWave = true,
			totalCap = totalCap,
			aliveCap = totalCap,
			roleCaps = { trash = 0, medium = 0, heavy = 0, special = 0 } :: RoleCounts,
			targetCountByRole = { trash = 0, medium = 0, heavy = 0, special = 0 } :: RoleCounts,
			pickTemplate = pickTemplate,
		}
	end

	-- Director path: WaveTotalTarget, AliveCap, role caps, composition.
	local dir = Config.Wave.Director
	if not dir or type(dir.BaseWaveTotal) ~= "table" or type(dir.BaseAliveCap) ~= "table" then
		local totalCap = getScaledWaveCapLegacy(waveNumber, playerCount, cap)
		local pool = buildPool(catalog, waveNumber)
		local pickTemplate = function(roleAlive, totalSpawnedByRole)
			return pickFromPool(pool, roleAlive, { trash = totalCap, medium = 0, heavy = 0, special = 0 }, totalSpawnedByRole, totalCap)
		end
		return {
			isBossWave = false,
			totalCap = totalCap,
			aliveCap = totalCap,
			roleCaps = { trash = totalCap, medium = 0, heavy = 0, special = 0 } :: RoleCounts,
			targetCountByRole = { trash = totalCap, medium = 0, heavy = 0, special = 0 } :: RoleCounts,
			pickTemplate = pickTemplate,
		}
	end

	local baseTotal = dir.BaseWaveTotal[wave] or dir.BaseWaveTotal[#dir.BaseWaveTotal] or 20
	local baseAlive = dir.BaseAliveCap[wave] or dir.BaseAliveCap[#dir.BaseAliveCap] or 8
	local diffTotal, diffAlive = getDiffMultipliers(difficulty)
	local waveTotalTarget = math.min(cap, math.floor(0.5 + baseTotal * countMult(players) * diffTotal))
	local waveTotalPlanned = math.min(waveTotalTarget, tonumber(dir.WaveTotalPlannedMax) or 1400)
	local aliveCapMin = math.max(0, tonumber(dir.AliveCapMin) or 8)
	local aliveCapMax = math.max(aliveCapMin, tonumber(dir.AliveCapMax) or 120)
	local aliveCap = math.clamp(math.floor(0.5 + baseAlive * aliveMult(players) * diffAlive), aliveCapMin, aliveCapMax)

	local roleCaps = computeRoleCaps(aliveCap, waveNumber, players, difficulty)
	local targetCountByRole = computeTargetCountByRole(waveTotalPlanned, waveNumber)

	local pool = buildPool(catalog, waveNumber)
	local pickTemplate = function(roleAlive, totalSpawnedByRole)
		return pickFromPool(pool, roleAlive, roleCaps, totalSpawnedByRole, waveTotalPlanned)
	end

	return {
		isBossWave = false,
		totalCap = waveTotalPlanned,
		aliveCap = aliveCap,
		roleCaps = roleCaps,
		targetCountByRole = targetCountByRole,
		pickTemplate = pickTemplate,
	}
end

function buildPool(catalog, waveNumber: number)
	local pool = {}
	for _, entry in catalog do
		if entry.IsBoss then
			continue
		end
		local minW = entry.MinWave
		local maxW = entry.MaxWave
		if type(minW) ~= "number" then
			minW = 1
		end
		if maxW ~= nil and type(maxW) ~= "number" then
			maxW = nil
		end
		if waveNumber < minW then
			continue
		end
		if maxW ~= nil and waveNumber > maxW then
			continue
		end
		local tier = getTier(entry)
		local mult = tierMultiplier(waveNumber, tier)
		if mult <= 0 then
			continue
		end
		local w = (entry.Weight or 1) * mult
		table.insert(pool, { entry = entry, weight = w })
	end
	return pool
end

-- roleAlive/totalSpawnedByRole: { trash, medium, heavy, special } (use tier names for keys if needed; we use role).
function pickFromPool(
	pool,
	roleAlive: RoleCounts?,
	roleCaps: RoleCounts?,
	totalSpawnedByRole: RoleCounts?,
	waveTotalPlanned: number?
)
	if #pool == 0 then
		return nil
	end
	roleAlive = roleAlive or { trash = 0, medium = 0, heavy = 0, special = 0 }
	roleCaps = roleCaps or { trash = 999, medium = 0, heavy = 0, special = 0 }
	totalSpawnedByRole = totalSpawnedByRole or { trash = 0, medium = 0, heavy = 0, special = 0 }

	local candidates = {}
	for _, pw in pool do
		local entry = pw.entry
		local role = getRole(entry)
		if roleAlive[role] and roleAlive[role] >= (roleCaps[role] or 0) then
			continue
		end
		local need = (waveTotalPlanned or 0) - (totalSpawnedByRole[role] or 0)
		local weight = pw.weight * math.max(0.01, 1 + need / math.max(1, waveTotalPlanned))
		table.insert(candidates, { entry = entry, weight = weight })
	end
	if #candidates == 0 then
		return nil
	end
	local chosen = weightedRandomPick(candidates)
	if not chosen or not chosen.TemplateName then
		return nil
	end
	return { templateName = chosen.TemplateName, tier = getTier(chosen) }
end

type WaveSpawnLogicModule = {
	getWaveComposition: (number, number, number) -> WaveComposition,
	buildPool: (catalog: { [number]: any }, number) -> { any },
	pickFromPool: (any, RoleCounts?, RoleCounts?, RoleCounts?, number?) -> { templateName: string, tier: string }?,
	countMult: (number) -> number,
	aliveMult: (number) -> number,
	computeRoleCaps: (number, number, number, string) -> RoleCounts,
	computeTargetCountByRole: (number, number) -> RoleCounts,
	getRole: (any) -> Role,
	getTier: (any) -> string,
}

local WaveSpawnLogic: WaveSpawnLogicModule = {
	getWaveComposition = getWaveComposition,
	buildPool = buildPool,
	pickFromPool = pickFromPool,
	countMult = countMult,
	aliveMult = aliveMult,
	computeRoleCaps = computeRoleCaps,
	computeTargetCountByRole = computeTargetCountByRole,
	getRole = getRole,
	getTier = getTier,
}

return WaveSpawnLogic
