--[[
	AimResolver — Tracks and validates player aim; produces final shot ray/direction.
	Used by weapon fire, sentry placement, and raycasting (WeaponRemoteBindings, WeaponToolFactory, WeaponFireHandlers, SentryTurretController, EnemyTargeting).
]]

local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent
local ShopConstants = require(Match.Shop.ShopConstants)
local WeaponVfx = require(Match.Weapons.Combat.WeaponVfx)

local FIRE_CONE_MIN_DOT = ShopConstants.FIRE_CONE_MIN_DOT

local playerAimState = {}

local function getHorizontalUnit(vector)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 0.001 then
		return nil
	end
	return horizontal.Unit
end

local function isDirectionWithinForwardFireArc(rootPart, direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return true
	end
	if not rootPart or not rootPart:IsA("BasePart") then
		return true
	end

	local forwardHorizontal = getHorizontalUnit(rootPart.CFrame.LookVector)
	local directionHorizontal = getHorizontalUnit(direction)
	if not forwardHorizontal or not directionHorizontal then
		return true
	end

	-- Allow only a narrow horizontal cone around where the character is facing.
	return forwardHorizontal:Dot(directionHorizontal) >= FIRE_CONE_MIN_DOT
end

local function clampDirectionToForwardFireArc(rootPart, direction, fallbackDirection)
	local fallback = fallbackDirection
	if typeof(fallback) ~= "Vector3" or fallback.Magnitude <= 0.001 then
		if rootPart and rootPart:IsA("BasePart") then
			fallback = rootPart.CFrame.LookVector
		else
			fallback = Vector3.new(0, 0, -1)
		end
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return fallback.Unit
	end

	local directionUnit = direction.Unit
	if isDirectionWithinForwardFireArc(rootPart, directionUnit) then
		return directionUnit
	end

	return fallback.Unit
end

local function buildWeaponRaycastParams(character, additionalExclusions)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local exclusions = { character, WeaponVfx.getEffectsFolder() }
	for _, item in ipairs(additionalExclusions or {}) do
		table.insert(exclusions, item)
	end

	raycastParams.FilterDescendantsInstances = exclusions
	return raycastParams
end

local function updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
	if typeof(hitPosition) ~= "Vector3" then
		return
	end
	if typeof(lookDirection) ~= "Vector3" or lookDirection.Magnitude <= 0.001 then
		return
	end
	if cameraOrigin ~= nil and typeof(cameraOrigin) ~= "Vector3" then
		return
	end

	playerAimState[player] = {
		hitPosition = hitPosition,
		lookDirection = lookDirection.Unit,
		cameraOrigin = cameraOrigin,
		updatedAt = os.clock(),
	}
end

local function getFreshAimState(player)
	local aimState = playerAimState[player]
	if not aimState then
		return nil
	end

	if os.clock() - (aimState.updatedAt or 0) > 0.8 then
		return nil
	end

	return aimState
end

local function clearPlayerAim(player)
	playerAimState[player] = nil
end

local function canPlayerFireTowardRequestedDirection(player, rootPart, explicitShotDirection)
	local requestedDirection = explicitShotDirection
	if typeof(requestedDirection) ~= "Vector3" or requestedDirection.Magnitude <= 0.001 then
		local aimState = getFreshAimState(player)
		if aimState and typeof(aimState.lookDirection) == "Vector3" and aimState.lookDirection.Magnitude > 0.001 then
			requestedDirection = aimState.lookDirection
		else
			requestedDirection = rootPart.CFrame.LookVector
		end
	end

	return isDirectionWithinForwardFireArc(rootPart, requestedDirection)
end

local function getPlayerAimDirection(player, character, rootPart, origin)
	local baseDirection = rootPart.CFrame.LookVector
	local aimState = getFreshAimState(player)
	if not aimState then
		return baseDirection
	end

	local cameraOrigin = aimState.cameraOrigin
	local lookDirection = aimState.lookDirection
	if typeof(cameraOrigin) == "Vector3" then
		local range = 1800
		local raycastParams = buildWeaponRaycastParams(character, {})
		local raycastResult = Workspace:Raycast(cameraOrigin, lookDirection * range, raycastParams)
		local targetPosition = cameraOrigin + lookDirection * range
		if raycastResult then
			targetPosition = raycastResult.Position
		end

		local toTarget = targetPosition - origin
		if toTarget.Magnitude > 0.01 then
			return toTarget.Unit
		end
	end

	local aimDirection = nil
	local toHit = aimState.hitPosition - origin
	if toHit.Magnitude > 0.01 then
		aimDirection = toHit.Unit
	else
		aimDirection = aimState.lookDirection
	end

	if typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude <= 0.001 then
		return baseDirection
	end

	return clampDirectionToForwardFireArc(rootPart, aimDirection, baseDirection)
end

local function getPlayerShotRay(player, rootPart, fallbackOrigin, fallbackDirection)
	local aimState = getFreshAimState(player)
	if aimState and typeof(aimState.cameraOrigin) == "Vector3" then
		local lookDirection = aimState.lookDirection
		if typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
			return aimState.cameraOrigin, clampDirectionToForwardFireArc(rootPart, lookDirection, fallbackDirection)
		end
	end

	if typeof(fallbackOrigin) == "Vector3" and typeof(fallbackDirection) == "Vector3" and fallbackDirection.Magnitude > 0.001 then
		return fallbackOrigin, clampDirectionToForwardFireArc(rootPart, fallbackDirection, rootPart.CFrame.LookVector)
	end

	return rootPart.Position + Vector3.new(0, 1.5, 0), clampDirectionToForwardFireArc(rootPart, rootPart.CFrame.LookVector, rootPart.CFrame.LookVector)
end

return {
	updatePlayerAim = updatePlayerAim,
	getFreshAimState = getFreshAimState,
	clearPlayerAim = clearPlayerAim,
	getHorizontalUnit = getHorizontalUnit,
	isDirectionWithinForwardFireArc = isDirectionWithinForwardFireArc,
	clampDirectionToForwardFireArc = clampDirectionToForwardFireArc,
	canPlayerFireTowardRequestedDirection = canPlayerFireTowardRequestedDirection,
	getPlayerAimDirection = getPlayerAimDirection,
	getPlayerShotRay = getPlayerShotRay,
	buildWeaponRaycastParams = buildWeaponRaycastParams,
}
