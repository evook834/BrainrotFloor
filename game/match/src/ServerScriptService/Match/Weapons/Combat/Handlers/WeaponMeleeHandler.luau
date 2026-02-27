--[[
	WeaponMeleeHandler — Shoulder swing animation and melee hit resolution.
]]

local RunService = game:GetService("RunService")

local Match = script.Parent.Parent.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)

local function isRightShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end
	local motorName = motor.Name
	if motorName == "RightShoulder" or motorName == "Right Shoulder" then
		return true
	end
	local part0, part1 = motor.Part0, motor.Part1
	if not part0 or not part1 then
		return false
	end
	local part0Name, part1Name = part0.Name, part1.Name
	if part1Name ~= "Right Arm" and part1Name ~= "RightUpperArm" then
		return false
	end
	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findRightShoulderMotor(character)
	if not character or not character:IsA("Model") then
		return nil
	end
	local directR15 = character:FindFirstChild("RightShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then
		return directR15
	end
	local directR6 = character:FindFirstChild("Right Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then
		return directR6
	end
	for _, descendant in character:GetDescendants() do
		if isRightShoulderMotor(descendant) then
			return descendant
		end
	end
	return nil
end

local function isLeftShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end
	local motorName = motor.Name
	if motorName == "LeftShoulder" or motorName == "Left Shoulder" then
		return true
	end
	local part0, part1 = motor.Part0, motor.Part1
	if not part0 or not part1 then
		return false
	end
	local part0Name, part1Name = part0.Name, part1.Name
	if part1Name ~= "Left Arm" and part1Name ~= "LeftUpperArm" then
		return false
	end
	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findLeftShoulderMotor(character)
	if not character or not character:IsA("Model") then
		return nil
	end
	local directR15 = character:FindFirstChild("LeftShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then
		return directR15
	end
	local directR6 = character:FindFirstChild("Left Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then
		return directR6
	end
	for _, descendant in character:GetDescendants() do
		if isLeftShoulderMotor(descendant) then
			return descendant
		end
	end
	return nil
end

local function playMeleeSwing(character, weaponDef, state)
	state.swingToken = (state.swingToken or 0) + 1
	local swingToken = state.swingToken

	local swingForwardDegrees = tonumber(weaponDef.SwingForwardDegrees) or 70
	local swingDuration = math.max(0.08, tonumber(weaponDef.SwingDuration) or 0.18)
	local swingSideDegrees = tonumber(weaponDef.SwingSideDegrees)
	if type(swingSideDegrees) ~= "number" then
		swingSideDegrees = math.max(8, math.min(22, math.abs(swingForwardDegrees) * 0.24))
	end
	local swingRollDegrees = tonumber(weaponDef.SwingRollDegrees) or (-0.5 * swingSideDegrees)
	local windupDegrees = tonumber(weaponDef.SwingWindupDegrees)
	if type(windupDegrees) ~= "number" then
		windupDegrees = math.max(8, math.min(24, math.abs(swingForwardDegrees) * 0.32))
	end
	local windupSideDegrees = tonumber(weaponDef.SwingWindupSideDegrees)
	if type(windupSideDegrees) ~= "number" then
		windupSideDegrees = -swingSideDegrees * 0.55
	end
	local windupRollDegrees = tonumber(weaponDef.SwingWindupRollDegrees)
	if type(windupRollDegrees) ~= "number" then
		windupRollDegrees = -swingRollDegrees * 0.35
	end

	local shoulderMotor = findRightShoulderMotor(character)
	if not shoulderMotor then
		return
	end

	local baseC0 = shoulderMotor.C0
	local windupC0 = baseC0 * CFrame.Angles(math.rad(windupDegrees), math.rad(windupSideDegrees), math.rad(windupRollDegrees))
	local strikeC0 = baseC0 * CFrame.Angles(math.rad(-swingForwardDegrees), math.rad(swingSideDegrees), math.rad(swingRollDegrees))

	local function animateMotorC0(fromC0, toC0, durationSeconds)
		local duration = math.max(0.01, durationSeconds)
		local start = os.clock()
		while shoulderMotor.Parent do
			if state.swingToken ~= swingToken then
				return false
			end
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			local easedAlpha = 1 - ((1 - alpha) * (1 - alpha))
			shoulderMotor.C0 = fromC0:Lerp(toC0, easedAlpha)
			if alpha >= 1 then
				return true
			end
			RunService.Heartbeat:Wait()
		end
		return false
	end

	task.spawn(function()
		local windupTime = swingDuration * 0.24
		local strikeTime = swingDuration * 0.38
		local recoverTime = swingDuration * 0.38
		if not animateMotorC0(baseC0, windupC0, windupTime) then
			return
		end
		if not animateMotorC0(windupC0, strikeC0, strikeTime) then
			return
		end
		animateMotorC0(strikeC0, baseC0, recoverTime)
	end)
end

local function fireMeleeAttack(player, character, origin, direction, weaponDef, state, tool)
	playMeleeSwing(character, weaponDef, state)

	local meleeRangeMultiplier = math.max(0.1, ClassService.getMeleeRangeMultiplier(player, weaponDef))
	local range = math.max(1, tonumber(weaponDef.Range) or 8) * meleeRangeMultiplier
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 90
	local downwardBias = math.clamp(tonumber(weaponDef.MeleeDownwardBias) or 0.34, 0, 0.85)
	local originDrop = math.max(0, tonumber(weaponDef.MeleeOriginDrop) or 1.15)
	local groundRangeBonus = math.max(0, tonumber(weaponDef.MeleeGroundRangeBonus) or 1.2) * meleeRangeMultiplier
	local groundArcBonus = math.max(0, tonumber(weaponDef.MeleeGroundArcBonus) or 14)
	local groundExtraRadius = math.max(0, tonumber(weaponDef.MeleeGroundExtraRadius) or 1.8) * meleeRangeMultiplier
	local damage = weaponDef.Damage or 15

	local targetsByModel = {}
	local function collectTargets(hitOrigin, hitDirection, hitRange, hitArcDegrees)
		local hits = EnemyTargeting.getEnemiesInCone(character, hitOrigin, hitDirection, hitRange, hitArcDegrees, true)
		for _, enemyModel in ipairs(hits) do
			targetsByModel[enemyModel] = true
		end
	end
	collectTargets(origin, direction, range, arcDegrees)

	local loweredOrigin = origin - Vector3.new(0, originDrop, 0)
	local downwardDirection = direction + Vector3.new(0, -downwardBias, 0)
	if downwardDirection.Magnitude > 0.001 then
		downwardDirection = downwardDirection.Unit
	else
		downwardDirection = direction
	end
	collectTargets(loweredOrigin, downwardDirection, range + groundRangeBonus, arcDegrees + groundArcBonus)

	if next(targetsByModel) == nil then
		local fallbackEnd = loweredOrigin + downwardDirection * (range + groundRangeBonus)
		local fallbackEnemy = EnemyTargeting.findEnemyAlongSegment(character, loweredOrigin, fallbackEnd, groundExtraRadius, true)
		if fallbackEnemy then
			targetsByModel[fallbackEnemy] = true
		end
	end

	for enemyModel in pairs(targetsByModel) do
		EnemyDamageService.applyDamageToEnemy(player, enemyModel, damage, weaponDef)
	end
end

return {
	playMeleeSwing = playMeleeSwing,
	findLeftShoulderMotor = findLeftShoulderMotor,
	findRightShoulderMotor = findRightShoulderMotor,
	fireMeleeAttack = fireMeleeAttack,
}
