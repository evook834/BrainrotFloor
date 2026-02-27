local Match = script.Parent.Parent.Parent
local AimResolver = require(Match.Combat.AimResolver)

local WeaponShotResolver = {}

function WeaponShotResolver.getWeaponOriginAndDirection(player, character, rootPart, handle)
	local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
	if handle and handle:IsA("BasePart") then
		origin = handle.Position
	end

	local direction = AimResolver.getPlayerAimDirection(player, character, rootPart, origin)
	if direction.Magnitude <= 0.001 then
		direction = rootPart.CFrame.LookVector
	end
	direction = direction.Unit

	if handle and handle:IsA("BasePart") then
		origin += direction * math.max(0.8, handle.Size.Z * 0.45)
		direction = AimResolver.getPlayerAimDirection(player, character, rootPart, origin)
		if direction.Magnitude <= 0.001 then
			direction = rootPart.CFrame.LookVector
		end
		direction = direction.Unit
	end

	return origin, direction
end

return WeaponShotResolver
