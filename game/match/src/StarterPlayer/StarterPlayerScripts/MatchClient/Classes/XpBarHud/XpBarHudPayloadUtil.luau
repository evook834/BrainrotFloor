--[[
	XpBarHudPayloadUtil — Pure helpers for class payload parsing and XP/level display text.
	No UI or remotes; used by XpBarHudController.
]]

local REASON_LEVEL_UP = "LevelUp"

-- Display strings for lobby preview (HUD move mode) and empty state (no class data).
-- Each is { levelText, perkText, activeBonusText, xpText, progress } for setHudDisplay.
local LOBBY_PREVIEW_DISPLAY = { "Lv 1", "Perk: Lobby preview", "Active: No perk bonus yet", "XP 0 / 100", 0.4 }
local EMPTY_STATE_DISPLAY = { "Lv 1", "Perk: Unknown", "Active: None", "XP 0 / 100", 0 }

local function formatWholeNumber(value: number): string
	local numericValue = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	local text = tostring(numericValue)
	while true do
		local updated, substitutions = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = updated
		if substitutions == 0 then
			break
		end
	end
	return text
end

export type ClassData = {
	level: number?,
	name: string?,
	xp: number?,
	xpToNext: number?,
	isCurrent: boolean?,
	currentBonuses: { [string]: number? }?,
}

export type ClassPayload = {
	success: boolean?,
	reason: string?,
	currentClassName: string?,
	classes: { ClassData }?,
}

local function getCurrentClassData(payload: ClassPayload): ClassData?
	if type(payload) ~= "table" then
		return nil
	end
	for _, classData in ipairs(payload.classes or {}) do
		if classData.isCurrent then
			return classData
		end
	end
	return nil
end

local function getActivePerkText(classData: ClassData?): string
	if type(classData) ~= "table" then
		return "Active: None"
	end
	local bonuses = classData.currentBonuses or {}
	local candidates = {
		{ label = "DMG", value = tonumber(bonuses.damagePct) or 0 },
		{ label = "HP", value = tonumber(bonuses.maxHealthPct) or 0 },
		{ label = "Move", value = tonumber(bonuses.moveSpeedPct) or 0 },
		{ label = "DR", value = tonumber(bonuses.damageReductionPct) or 0 },
		{ label = "Melee", value = tonumber(bonuses.meleeRangePct) or 0 },
		{ label = "Shop", value = tonumber(bonuses.shopDiscountPct) or 0 },
		{ label = "Reload", value = tonumber(bonuses.reloadSpeedPct) or 0 },
		{ label = "Mag", value = tonumber(bonuses.magazineSizePct) or 0 },
		{ label = "Range", value = tonumber(bonuses.bulletRangePct) or 0 },
		{ label = "Spread", value = tonumber(bonuses.bulletSpreadReductionPct) or 0 },
		{ label = "Burn", value = tonumber(bonuses.burnChancePct) or 0 },
		{ label = "Crit", value = tonumber(bonuses.criticalHitChancePct) or 0 },
		{ label = "Super Crit", value = tonumber(bonuses.superCriticalHitChancePct) or 0 },
	}
	local bestLabel: string? = nil
	local bestValue = 0
	for _, candidate in ipairs(candidates) do
		if candidate.value > bestValue then
			bestValue = candidate.value
			bestLabel = candidate.label
		end
	end
	if not bestLabel or bestValue <= 0 then
		return "Active: No perk bonus yet"
	end
	return string.format("Active: %s +%.1f%%", bestLabel, bestValue)
end

local function formatXpProgressAndPercent(xp: number, xpToNext: number?): (string, number)
	if type(xpToNext) == "number" and xpToNext > 0 then
		local progress = math.clamp(xp / xpToNext, 0, 1)
		local text = string.format("XP %s / %s", formatWholeNumber(xp), formatWholeNumber(xpToNext))
		return text, progress
	end
	return string.format("XP %s / MAX", formatWholeNumber(xp)), 1
end

return {
	REASON_LEVEL_UP = REASON_LEVEL_UP,
	LOBBY_PREVIEW_DISPLAY = LOBBY_PREVIEW_DISPLAY,
	EMPTY_STATE_DISPLAY = EMPTY_STATE_DISPLAY,
	formatWholeNumber = formatWholeNumber,
	getCurrentClassData = getCurrentClassData,
	getActivePerkText = getActivePerkText,
	formatXpProgressAndPercent = formatXpProgressAndPercent,
}
