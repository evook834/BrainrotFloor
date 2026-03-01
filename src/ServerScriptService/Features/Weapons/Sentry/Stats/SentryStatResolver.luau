--[[
	SentryStatResolver — Resolves turret stats from weapon def (ammo, damage, fire rate, rockets, etc.).
	Pure helpers; no runtime state.
]]

local SentryStatResolver = {}

local function roundNearestInteger(value, fallbackValue)
	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" then
		numberValue = tonumber(fallbackValue) or 0
	end
	return math.floor(numberValue + 0.5)
end

local function resolvePositiveRounded(value, fallbackValue, minimumValue)
	local minValue = tonumber(minimumValue) or 1
	local rounded = roundNearestInteger(value, fallbackValue)
	return math.max(minValue, rounded)
end

local function firstNumericCandidate(candidates)
	if type(candidates) ~= "table" then
		return nil
	end
	for _, candidate in ipairs(candidates) do
		local numeric = tonumber(candidate)
		if type(numeric) == "number" then
			return numeric
		end
	end
	return nil
end

function SentryStatResolver.resolveTurretMaxAmmo(weaponDef, defaultMaxAmmo)
	local configuredMaxAmmo = tonumber(weaponDef and weaponDef.TurretMaxAmmo)
	return resolvePositiveRounded(configuredMaxAmmo, defaultMaxAmmo, 1)
end

function SentryStatResolver.resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)
	local maxAmmo = resolvePositiveRounded(turretMaxAmmo, 1, 1)
	local configuredInitialAmmo = tonumber(weaponDef and weaponDef.TurretInitialAmmo)
	if type(configuredInitialAmmo) ~= "number" then
		return maxAmmo
	end

	return math.clamp(math.floor(configuredInitialAmmo + 0.5), 0, maxAmmo)
end

function SentryStatResolver.resolveAmmoState(ammoValue, maxAmmoValue, fallbackMaxAmmo)
	local maxAmmo = resolvePositiveRounded(maxAmmoValue, fallbackMaxAmmo, 1)
	local ammoNumber = tonumber(ammoValue)
	if type(ammoNumber) ~= "number" then
		ammoNumber = maxAmmo
	end
	local ammo = math.clamp(math.floor(ammoNumber + 0.5), 0, maxAmmo)
	return ammo, maxAmmo
end

function SentryStatResolver.resolveAmmoStateFromCandidates(maxAmmoCandidates, ammoCandidates, fallbackMaxAmmo)
	local rawMaxAmmo = firstNumericCandidate(maxAmmoCandidates)
	local maxAmmo = resolvePositiveRounded(rawMaxAmmo, fallbackMaxAmmo, 1)
	local rawAmmo = firstNumericCandidate(ammoCandidates)
	local ammo, _ = SentryStatResolver.resolveAmmoState(rawAmmo, maxAmmo, maxAmmo)
	return ammo, maxAmmo
end

function SentryStatResolver.resolveCombatStats(weaponDef, options)
	local normalizedWeaponDef = if type(weaponDef) == "table" then weaponDef else {}
	local normalizeWeaponToken = options and options.normalizeWeaponToken
	local defaultRocketSpreadDegrees = tonumber(options and options.defaultRocketSpreadDegrees) or 0
	local attackModeSource = normalizedWeaponDef.TurretAttackMode or "Bullet"
	local turretAttackMode = if type(normalizeWeaponToken) == "function"
		then normalizeWeaponToken(attackModeSource)
		else tostring(attackModeSource)

	return {
		turretMaxHealth = math.max(50, tonumber(normalizedWeaponDef.TurretMaxHealth) or 420),
		turretDamage = math.max(1, tonumber(normalizedWeaponDef.TurretDamage) or 26),
		turretFireCooldown = math.max(0.05, tonumber(normalizedWeaponDef.TurretFireCooldown) or 0.2),
		turretAcquireRange = math.max(100, tonumber(normalizedWeaponDef.TurretAcquireRange) or 100000),
		turretThinkInterval = math.max(0.05, tonumber(normalizedWeaponDef.TurretThinkInterval) or 0.08),
		turretAttackMode = turretAttackMode,
		turretRocketCount = math.max(1, math.floor((tonumber(normalizedWeaponDef.TurretRocketCount) or 1) + 0.5)),
		turretRocketBlastRadius = math.max(4, tonumber(normalizedWeaponDef.TurretRocketBlastRadius) or 8),
		turretRocketProjectileSpeed = math.max(30, tonumber(normalizedWeaponDef.TurretRocketProjectileSpeed) or 140),
		turretRocketRange = math.max(20, tonumber(normalizedWeaponDef.TurretRocketRange) or tonumber(normalizedWeaponDef.Range) or 180),
		turretRocketSpreadDegrees = math.max(
			0,
			tonumber(normalizedWeaponDef.TurretRocketSpreadDegrees) or defaultRocketSpreadDegrees
		),
	}
end

return SentryStatResolver
