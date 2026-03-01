--[[
	WeaponBulletHandler — Hitscan bullet spread and enemy damage.
]]

local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent.Parent.Parent
local Weapons = script.Parent.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local WeaponToolSetup = require(Weapons.Tools.WeaponToolSetup)
local WeaponVfx = require(script.Parent.Parent.WeaponVfx)
local WeaponCombatShared = require(script.Parent.WeaponCombatShared)

local createTracerSegment = WeaponVfx.createTracerSegment
local createMuzzleFlash = WeaponVfx.createMuzzleFlash
local resolveWeaponClass = WeaponToolSetup.resolveWeaponClass
local normalizeWeaponToken = WeaponToolSetup.normalizeWeaponToken
local resolveShotRay = WeaponCombatShared.resolveShotRay
local buildWeaponRaycastParams = WeaponCombatShared.buildWeaponRaycastParams

local randomGenerator = Random.new()

local function isSniperWeaponDefinition(weaponDef)
	if type(weaponDef) ~= "table" then
		return false
	end
	local classIdToken = normalizeWeaponToken(weaponDef.ClassId)
	local classTagToken = normalizeWeaponToken(weaponDef.ClassTag)
	local weaponClassToken = normalizeWeaponToken(resolveWeaponClass(weaponDef))
	return classIdToken == "sniper" or classTagToken == "sniper" or weaponClassToken == "sniper"
end

local function applyBulletSpread(direction, spreadDegrees)
	local maxDegrees = math.max(0, tonumber(spreadDegrees) or 0)
	if maxDegrees <= 0 then
		return direction
	end
	local coneRadius = math.tan(math.rad(maxDegrees))
	local theta = randomGenerator:NextNumber(0, math.pi * 2)
	local radius = coneRadius * math.sqrt(randomGenerator:NextNumber())
	local referenceUp = math.abs(direction:Dot(Vector3.yAxis)) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(referenceUp)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(direction).Unit
	local offset = right * (math.cos(theta) * radius) + up * (math.sin(theta) * radius)
	local spreadDirection = direction + offset
	if spreadDirection.Magnitude <= 0.001 then
		return direction
	end
	return spreadDirection.Unit
end

local function fireBulletShot(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local isSniperWeapon = isSniperWeaponDefinition(weaponDef)
	local baseRange = math.max(1, tonumber(weaponDef.Range) or 40)
	local range = baseRange * math.max(0.1, ClassService.getWeaponBulletRangeMultiplier(player, weaponDef))
	local rayOrigin, rayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local spreadDegrees = 0
	if not isSniperWeapon then
		spreadDegrees = ClassService.getWeaponSpreadDegrees(player, weaponDef)
		if type(spreadDegrees) ~= "number" then
			spreadDegrees = weaponDef.SpreadDegrees
		end
	end
	rayDirection = applyBulletSpread(rayDirection, spreadDegrees)
	local raycastParams = buildWeaponRaycastParams(character, {})
	local result = Workspace:Raycast(rayOrigin, rayDirection * range, raycastParams)
	local hitPosition = rayOrigin + rayDirection * range
	local enemyTarget = nil

	if result then
		hitPosition = result.Position
		enemyTarget = EnemyTargeting.resolveEnemyFromRaycastResult(result)
	end
	if not enemyTarget then
		local fallbackRadius = 0.75
		local fallbackEnd = hitPosition
		if isSniperWeapon then
			fallbackRadius = math.max(2.5, tonumber(weaponDef.SniperHitAssistRadius) or 2.5)
			fallbackEnd = rayOrigin + (rayDirection * range)
		end
		local fallbackEnemy, fallbackImpact = EnemyTargeting.findEnemyAlongSegment(character, rayOrigin, fallbackEnd, fallbackRadius)
		if fallbackEnemy then
			enemyTarget = fallbackEnemy
			if fallbackImpact then
				hitPosition = fallbackImpact
			end
		end
	end

	createMuzzleFlash(origin, Color3.fromRGB(255, 210, 120), 0.35, 0.06)
	createTracerSegment(origin, hitPosition, Color3.fromRGB(255, 235, 140), 0.13, 0.08)
	if enemyTarget then
		EnemyDamageService.applyDamageToEnemy(player, enemyTarget, weaponDef.Damage or 20, weaponDef)
	end
end

return {
	applyBulletSpread = applyBulletSpread,
	fireBulletShot = fireBulletShot,
}
