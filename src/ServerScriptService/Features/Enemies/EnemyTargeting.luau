--[[
	EnemyTargeting — Find/validate enemy targets for weapon fire and area queries.
	getEnemyContainer, findEnemyModelFromDescendant, resolveEnemyFromRaycastResult,
	projectPointOnSegment, hasClearPathToEnemy,
	getEnemyHitRadius, getEnemyTemplateProfile, getEffectiveEnemyHitRadius,
	findEnemyAlongSegment, getEnemiesInCone.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local EnemyRegistry = require(Match.Enemies.EnemyRegistry)
local AimResolver = require(Match.Combat.AimResolver)

local function getEnemyContainer()
	return EnemyRegistry.getEnemyContainer()
end

local function findEnemyModelFromDescendant(descendant, enemyContainer)
	local current = descendant
	while current and current ~= enemyContainer do
		if current:IsA("Model") and current.Parent == enemyContainer then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function resolveEnemyFromRaycastResult(result)
	if not result then
		return nil
	end

	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return nil
	end

	return findEnemyModelFromDescendant(result.Instance, enemyContainer)
end

local function projectPointOnSegment(point, segmentStart, segmentEnd)
	local segment = segmentEnd - segmentStart
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= 0.0001 then
		return segmentStart, 0
	end

	local t = math.clamp((point - segmentStart):Dot(segment) / lengthSquared, 0, 1)
	return segmentStart + segment * t, t
end

local function hasClearPathToEnemy(character, startPos, enemyModel, enemyRoot, allowEnemyOcclusion)
	local params = AimResolver.buildWeaponRaycastParams(character, {})
	local direction = enemyRoot.Position - startPos
	if direction.Magnitude <= 0.01 then
		return true
	end

	local result = Workspace:Raycast(startPos, direction, params)
	if not result then
		return true
	end

	local hitEnemy = resolveEnemyFromRaycastResult(result)
	if allowEnemyOcclusion and hitEnemy then
		return true
	end
	return hitEnemy == enemyModel
end

local function getEnemyHitRadius(enemyRoot)
	local rootSize = enemyRoot.Size
	local rootRadius = math.max(rootSize.X, rootSize.Z) * 0.55
	return math.clamp(rootRadius, 1.2, 5.5)
end

local function getEnemyTemplateProfile(enemyModel)
	if not enemyModel or not enemyModel:IsA("Model") then
		return nil
	end

	local enemyType = enemyModel:GetAttribute("EnemyType")
	if type(enemyType) ~= "string" or enemyType == "" then
		return nil
	end

	local templateProfiles = Config.Enemy.TemplateProfiles or {}
	local templateProfile = templateProfiles[enemyType]
	if type(templateProfile) == "table" then
		return templateProfile
	end

	return nil
end

local function getEffectiveEnemyHitRadius(enemyModel, enemyRoot)
	local radius = getEnemyHitRadius(enemyRoot)
	local profile = getEnemyTemplateProfile(enemyModel)
	if not profile then
		return radius
	end

	local hitboxScale = tonumber(profile.HitboxScale) or 1
	local hitboxPadding = tonumber(profile.HitboxPadding) or 0
	radius = radius * math.max(0.1, hitboxScale) + math.max(0, hitboxPadding)

	return math.clamp(radius, 1.2, 10)
end

local function getEnemiesAlongSegment(character, segmentStart, segmentEnd, extraRadius, allowEnemyOcclusion)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return {}
	end

	local radiusPadding = math.max(0, extraRadius or 0)
	local hits = {}

	EnemyRegistry.forEachTrackedEnemy(function(enemyModel)
		local enemyRoot = EnemyRegistry.getRootPart(enemyModel)
		if enemyRoot then
			local nearestPoint = projectPointOnSegment(enemyRoot.Position, segmentStart, segmentEnd)
			local distanceFromPath = (enemyRoot.Position - nearestPoint).Magnitude
			local allowedRadius = getEffectiveEnemyHitRadius(enemyModel, enemyRoot) + radiusPadding
			if distanceFromPath <= allowedRadius and hasClearPathToEnemy(character, segmentStart, enemyModel, enemyRoot, allowEnemyOcclusion) then
				table.insert(hits, {
					enemy = enemyModel,
					impactPoint = nearestPoint,
					alongDistance = (nearestPoint - segmentStart).Magnitude,
				})
			end
		end
	end)

	table.sort(hits, function(left, right)
		return left.alongDistance < right.alongDistance
	end)

	return hits
end

local function findEnemyAlongSegment(character, segmentStart, segmentEnd, extraRadius, allowEnemyOcclusion)
	local hits = getEnemiesAlongSegment(character, segmentStart, segmentEnd, extraRadius, allowEnemyOcclusion)
	local firstHit = hits[1]
	if not firstHit then
		return nil, nil
	end

	return firstHit.enemy, firstHit.impactPoint
end

local function getEnemiesInCone(character, origin, lookDirection, range, arcDegrees, allowEnemyOcclusion)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return {}
	end

	local enemies = {}
	local normalizedLook = lookDirection.Magnitude > 0.001 and lookDirection.Unit or Vector3.new(0, 0, -1)
	local halfArcRadians = math.rad(math.clamp((arcDegrees or 90) * 0.5, 1, 179))

	EnemyRegistry.forEachTrackedEnemy(function(enemyModel)
		local enemyRoot = EnemyRegistry.getRootPart(enemyModel)
		if enemyRoot then
			local offset = enemyRoot.Position - origin
			local distance = offset.Magnitude
			local targetRadius = getEffectiveEnemyHitRadius(enemyModel, enemyRoot)
			if distance <= (range + targetRadius) and distance > 0.05 then
				local direction = offset.Unit
				local facingDot = normalizedLook:Dot(direction)
				local angularSlackRadians = math.atan(targetRadius / math.max(distance, 0.01))
				local enemyMinDot = math.cos(math.min(math.rad(179), halfArcRadians + angularSlackRadians))
				if facingDot >= enemyMinDot and hasClearPathToEnemy(character, origin, enemyModel, enemyRoot, allowEnemyOcclusion) then
					table.insert(enemies, enemyModel)
				end
			end
		end
	end)

	return enemies
end

return {
	getEnemyContainer = getEnemyContainer,
	findEnemyModelFromDescendant = findEnemyModelFromDescendant,
	resolveEnemyFromRaycastResult = resolveEnemyFromRaycastResult,
	projectPointOnSegment = projectPointOnSegment,
	hasClearPathToEnemy = hasClearPathToEnemy,
	getEnemyHitRadius = getEnemyHitRadius,
	getEnemyTemplateProfile = getEnemyTemplateProfile,
	getEffectiveEnemyHitRadius = getEffectiveEnemyHitRadius,
	getEnemiesAlongSegment = getEnemiesAlongSegment,
	findEnemyAlongSegment = findEnemyAlongSegment,
	getEnemiesInCone = getEnemiesInCone,
}
