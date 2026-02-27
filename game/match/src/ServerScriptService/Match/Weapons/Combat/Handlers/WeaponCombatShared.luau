--[[
	WeaponCombatShared — Shared helper math/raycast utilities for combat handlers.
]]

local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent.Parent.Parent
local AimResolver = require(Match.Combat.AimResolver)

local WeaponCombatShared = {}

function WeaponCombatShared.resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local rayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local rayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	return rayOrigin, rayDirection
end

function WeaponCombatShared.resolveAimTargetPosition(character, rayOrigin, rayDirection, range)
	local raycastParams = WeaponCombatShared.buildWeaponRaycastParams(character, {})
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection * range, raycastParams)
	local targetPosition = rayOrigin + rayDirection * range
	if raycastResult then
		targetPosition = raycastResult.Position
	end
	return targetPosition
end

function WeaponCombatShared.buildWeaponRaycastParams(character, additionalExclusions)
	return AimResolver.buildWeaponRaycastParams(character, additionalExclusions or {})
end

function WeaponCombatShared.retargetDirectionToward(origin, direction, targetPosition)
	local nextDirection = direction
	local toTarget = targetPosition - origin
	if toTarget.Magnitude > 0.01 then
		nextDirection = toTarget.Unit
	end
	return nextDirection
end

return WeaponCombatShared
