local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ENABLE_LEGACY_DUAL_WIELD_POSE = false

if not ENABLE_LEGACY_DUAL_WIELD_POSE then
	return
end

local player = Players.LocalPlayer
local renderStepName = string.format("DualWieldPoseHard_%d", player.UserId)
local dualWieldWeaponIds = {}

for _, weaponDef in ipairs((Config.Shop and Config.Shop.Weapons) or {}) do
	if type(weaponDef) == "table" and type(weaponDef.Id) == "string" and weaponDef.Id ~= "" and weaponDef.DualWield == true then
		dualWieldWeaponIds[weaponDef.Id] = true
	end
end

local activeCharacter = nil
local leftShoulder = nil
local rightShoulder = nil
local savedState = nil
local savedRightState = nil

local function tryGet(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if not ok then
		return nil
	end
	return value
end

local function trySet(instance, propertyName, value)
	pcall(function()
		instance[propertyName] = value
	end)
end

local function isR6ShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	if motor.Name == "Left Shoulder" or motor.Name == "Right Shoulder" then
		return true
	end

	local part1 = motor.Part1
	if not part1 then
		return false
	end

	return string.lower(part1.Name) == "left arm" or string.lower(part1.Name) == "right arm"
end

local function findPartByNames(character, names)
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function getEquippedTool(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

local function isDualPistolTool(tool)
	if not tool then
		return false
	end

	local dualWield = tool:GetAttribute("DualWield")
	if type(dualWield) == "boolean" then
		return dualWield
	end

	local weaponId = tool:GetAttribute("WeaponId")
	if type(weaponId) == "string" and dualWieldWeaponIds[weaponId] == true then
		return true
	end

	return false
end

local function getTorsoPart(character)
	return findPartByNames(character, { "UpperTorso", "Torso" })
end

local function isArmLike(motor)
	local motorName = string.lower(motor.Name)
	local part1 = motor.Part1
	if not part1 then
		return false
	end

	local part1Name = string.lower(part1.Name)
	if string.find(part1Name, "leg", 1, true) or string.find(motorName, "hip", 1, true) then
		return false
	end

	return string.find(part1Name, "arm", 1, true) ~= nil
		or string.find(part1Name, "hand", 1, true) ~= nil
		or string.find(motorName, "shoulder", 1, true) ~= nil
end

local function findShoulderBySide(character, wantLeft)
	local torso = getTorsoPart(character)
	if not torso then
		return nil
	end

	local best = nil
	local bestScore = -math.huge
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 == torso and descendant.Part1 and isArmLike(descendant) then
			local localPos = torso.CFrame:PointToObjectSpace(descendant.Part1.Position)
			local onSide = (wantLeft and localPos.X < -0.05) or ((not wantLeft) and localPos.X > 0.05)
			if onSide and localPos.Y > -0.5 then
				local score = localPos.Y
				local motorName = string.lower(descendant.Name)
				local part1Name = string.lower(descendant.Part1.Name)
				if string.find(motorName, "shoulder", 1, true) then
					score += 10
				end
				if string.find(part1Name, "upperarm", 1, true) then
					score += 8
				end
				if string.find(part1Name, "arm", 1, true) then
					score += 3
				end
				if score > bestScore then
					bestScore = score
					best = descendant
				end
			end
		end
	end

	return best
end

local function restorePose()
	if leftShoulder and leftShoulder.Parent and savedState then
		if typeof(savedState.transform) == "CFrame" then
			trySet(leftShoulder, "Transform", savedState.transform)
		else
			trySet(leftShoulder, "Transform", CFrame.new())
		end
		if typeof(savedState.c0) == "CFrame" then
			trySet(leftShoulder, "C0", savedState.c0)
		end
		if type(savedState.maxVelocity) == "number" then
			trySet(leftShoulder, "MaxVelocity", savedState.maxVelocity)
		end
		if type(savedState.desiredAngle) == "number" then
			trySet(leftShoulder, "DesiredAngle", savedState.desiredAngle)
		end
	end

	if rightShoulder and rightShoulder.Parent and savedRightState then
		if typeof(savedRightState.transform) == "CFrame" then
			trySet(rightShoulder, "Transform", savedRightState.transform)
		else
			trySet(rightShoulder, "Transform", CFrame.new())
		end
		if typeof(savedRightState.c0) == "CFrame" then
			trySet(rightShoulder, "C0", savedRightState.c0)
		end
		if type(savedRightState.maxVelocity) == "number" then
			trySet(rightShoulder, "MaxVelocity", savedRightState.maxVelocity)
		end
		if type(savedRightState.desiredAngle) == "number" then
			trySet(rightShoulder, "DesiredAngle", savedRightState.desiredAngle)
		end
	end

	activeCharacter = nil
	leftShoulder = nil
	rightShoulder = nil
	savedState = nil
	savedRightState = nil
end

local function setupForCharacter(character)
	restorePose()

	activeCharacter = character
	leftShoulder = findShoulderBySide(character, true) or character:FindFirstChild("LeftShoulder", true) or character:FindFirstChild("Left Shoulder", true)
	rightShoulder = findShoulderBySide(character, false) or character:FindFirstChild("RightShoulder", true) or character:FindFirstChild("Right Shoulder", true)

	if not leftShoulder then
		return
	end

	savedState = {
		transform = tryGet(leftShoulder, "Transform"),
		c0 = tryGet(leftShoulder, "C0"),
		maxVelocity = tryGet(leftShoulder, "MaxVelocity"),
		desiredAngle = tryGet(leftShoulder, "DesiredAngle"),
	}
	if rightShoulder then
		savedRightState = {
			transform = tryGet(rightShoulder, "Transform"),
			c0 = tryGet(rightShoulder, "C0"),
			maxVelocity = tryGet(rightShoulder, "MaxVelocity"),
			desiredAngle = tryGet(rightShoulder, "DesiredAngle"),
		}
	end
end

local function updatePose()
	local character = player.Character
	if not character then
		restorePose()
		return
	end

	local tool = getEquippedTool(character)
	if not isDualPistolTool(tool) then
		restorePose()
		return
	end

	if activeCharacter ~= character or not leftShoulder or not leftShoulder.Parent then
		setupForCharacter(character)
	end
	if not leftShoulder then
		return
	end

	local isR6 = isR6ShoulderMotor(leftShoulder)

	local function chooseForwardFallback(shoulder, baseC0, useR6)
		if not (shoulder and shoulder.Part0 and typeof(baseC0) == "CFrame") then
			return CFrame.Angles(if useR6 then math.rad(-70) else math.rad(-35), 0, 0)
		end

		local pitchA = if useR6 then math.rad(-70) else math.rad(-35)
		local pitchB = -pitchA
		local deltaA = CFrame.Angles(pitchA, 0, 0)
		local deltaB = CFrame.Angles(pitchB, 0, 0)
		local forward = shoulder.Part0.CFrame.LookVector
		local c1Inverse = shoulder.C1:Inverse()
		local predictedA = shoulder.Part0.CFrame * (baseC0 * deltaA) * c1Inverse
		local predictedB = shoulder.Part0.CFrame * (baseC0 * deltaB) * c1Inverse
		local scoreA = predictedA.LookVector:Dot(forward)
		local scoreB = predictedB.LookVector:Dot(forward)
		return if scoreA >= scoreB then deltaA else deltaB
	end

	local appliedFromRight = false

	trySet(leftShoulder, "Transform", CFrame.new())

	if
		rightShoulder
		and rightShoulder.Parent
		and savedState
		and savedRightState
		and typeof(savedState.c0) == "CFrame"
		and typeof(savedRightState.c0) == "CFrame"
	then
		local rightDelta = savedRightState.c0:ToObjectSpace(rightShoulder.C0)
		local _, rightDeltaAngle = rightDelta:ToAxisAngle()
		if rightDeltaAngle > 0.02 then
			trySet(leftShoulder, "C0", savedState.c0 * rightDelta)
			appliedFromRight = true
		end
	end

	if not appliedFromRight and savedState and typeof(savedState.c0) == "CFrame" then
		local fallbackDelta = chooseForwardFallback(leftShoulder, savedState.c0, isR6)
		trySet(leftShoulder, "C0", savedState.c0 * fallbackDelta)
	end
end

RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Character.Value + 4, updatePose)
