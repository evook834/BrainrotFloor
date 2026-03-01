local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SharedEnemyDefinitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)

local EnemyMotionAnimator = {}

local WALK_STYLES = {
	{ speed = 7.2, sway = 0.08, vertical = 0.12, pitch = 7, roll = 5, attackPush = 0.28, attackLift = 0.04, attackPitch = 12, attackRoll = 4, attackDuration = 0.32 },
	{ speed = 8.1, sway = 0.05, vertical = 0.08, pitch = 5, roll = 8, attackPush = 0.22, attackLift = 0.02, attackPitch = 10, attackRoll = 8, attackDuration = 0.28 },
	{ speed = 6.6, sway = 0.11, vertical = 0.15, pitch = 9, roll = 4, attackPush = 0.34, attackLift = 0.05, attackPitch = 14, attackRoll = 3, attackDuration = 0.36 },
	{ speed = 7.8, sway = 0.07, vertical = 0.1, pitch = 6, roll = 6, attackPush = 0.26, attackLift = 0.03, attackPitch = 11, attackRoll = 6, attackDuration = 0.3 },
}

local FLY_STYLES = {
	{ speed = 5.9, sway = 0.06, vertical = 0.18, pitch = 8, roll = 12, attackPush = 0.22, attackLift = 0.08, attackPitch = 18, attackRoll = 10, attackDuration = 0.34 },
	{ speed = 6.8, sway = 0.09, vertical = 0.14, pitch = 6, roll = 16, attackPush = 0.2, attackLift = 0.05, attackPitch = 16, attackRoll = 13, attackDuration = 0.3 },
	{ speed = 5.2, sway = 0.04, vertical = 0.22, pitch = 10, roll = 9, attackPush = 0.24, attackLift = 0.1, attackPitch = 20, attackRoll = 7, attackDuration = 0.38 },
	{ speed = 6.1, sway = 0.07, vertical = 0.16, pitch = 7, roll = 14, attackPush = 0.21, attackLift = 0.07, attackPitch = 17, attackRoll = 11, attackDuration = 0.32 },
}

local FLY_NAME_HINTS = {
	"angel",
	"bird",
	"bombard",
	"celeste",
	"dragon",
	"fly",
	"saturn",
	"ufo",
}

local FLY_RIG_HINTS = {
	"booster",
	"engine",
	"jet",
	"propeller",
	"rotor",
	"thruster",
	"wing",
}

local ARM_NAME_HINTS = {
	"arm",
	"claw",
	"elbow",
	"fist",
	"hand",
	"shoulder",
	"wing",
}

local LEG_NAME_HINTS = {
	"ankle",
	"foot",
	"hip",
	"hoof",
	"knee",
	"leg",
	"paw",
	"thigh",
}

local EXCLUDED_JOINT_NAME_HINTS = {
	"neck",
	"root",
	"waist",
}

local JOINT_UPDATE_INTERVAL = 1 / 30

local function containsKeyword(text, keywords)
	for _, keyword in ipairs(keywords) do
		if string.find(text, keyword, 1, true) then
			return true
		end
	end

	return false
end

local function getElapsed(state)
	return math.max(0, os.clock() - state.startedAt)
end

local function hashName(name)
	local value = 0

	for index = 1, #name do
		value = (value * 33 + string.byte(name, index)) % 2147483647
	end

	return value
end

local function toRadians(degrees)
	return math.rad(tonumber(degrees) or 0)
end

local function clamp(value, minValue, maxValue)
	return math.max(minValue, math.min(maxValue, value))
end

local function scaleStyle(baseStyle, seed)
	local speedScale = 0.92 + ((seed % 5) * 0.03)
	local motionScale = 0.9 + ((math.floor(seed / 5) % 4) * 0.05)
	local attackScale = 0.9 + ((math.floor(seed / 19) % 4) * 0.05)

	return {
		speed = baseStyle.speed * speedScale,
		sway = baseStyle.sway * motionScale,
		vertical = baseStyle.vertical * motionScale,
		pitch = toRadians(baseStyle.pitch) * motionScale,
		roll = toRadians(baseStyle.roll) * motionScale,
		attackPush = baseStyle.attackPush * attackScale,
		attackLift = baseStyle.attackLift * attackScale,
		attackPitch = toRadians(baseStyle.attackPitch) * attackScale,
		attackRoll = toRadians(baseStyle.attackRoll) * attackScale,
		attackDuration = baseStyle.attackDuration,
	}
end

local function getJointNameBlob(motor)
	local names = { motor.Name }

	if motor.Part0 then
		table.insert(names, motor.Part0.Name)
	end

	if motor.Part1 then
		table.insert(names, motor.Part1.Name)
	end

	return string.lower(table.concat(names, " "))
end

local function classifyJointRole(nameBlob, relativePosition)
	if containsKeyword(nameBlob, EXCLUDED_JOINT_NAME_HINTS) then
		return nil
	end

	if containsKeyword(nameBlob, ARM_NAME_HINTS) then
		return "arm"
	end

	if containsKeyword(nameBlob, LEG_NAME_HINTS) then
		return "leg"
	end

	local absoluteX = math.abs(relativePosition.X)
	if relativePosition.Y <= -0.35 then
		return "leg"
	end

	if relativePosition.Y >= 0.1 and absoluteX >= 0.2 then
		return "arm"
	end

	if absoluteX >= 0.9 then
		return "arm"
	end

	if absoluteX >= 0.35 then
		return "generic"
	end

	return nil
end

local function buildJointDefinition(rootPart, state, motor)
	local connectedPart = motor.Part1 or motor.Part0
	if not connectedPart or not connectedPart:IsA("BasePart") then
		return nil
	end

	local relativePosition = rootPart.CFrame:PointToObjectSpace(connectedPart.Position)
	local nameBlob = getJointNameBlob(motor)
	local role = classifyJointRole(nameBlob, relativePosition)
	if not role then
		return nil
	end

	local sideSign = if relativePosition.X >= 0 then 1 else -1
	local distanceScale = clamp(relativePosition.Magnitude / 3, 0.7, 1.35)
	local isFlying = state.locomotionMode == "fly"
	local phaseOffset = if sideSign < 0 then math.pi else 0

	local pitchAmplitude = toRadians(if role == "leg" then (isFlying and 8 or 18) else (isFlying and 15 or 14)) * distanceScale
	local rollAmplitude = toRadians(if role == "generic" then 5 else (isFlying and 14 or 8)) * distanceScale
	local liftAmplitude = (if role == "leg" then 0.02 else 0.035) * distanceScale
	local attackPitchAmplitude = toRadians(if role == "arm" then 24 else 8) * distanceScale
	local attackRollAmplitude = toRadians(if role == "arm" then 10 else 4) * distanceScale
	local attackReach = (if role == "arm" then 0.18 else 0.05) * distanceScale

	return {
		motor = motor,
		baseTransform = motor.Transform,
		role = role,
		sideSign = sideSign,
		phaseOffset = phaseOffset,
		pitchAmplitude = pitchAmplitude,
		rollAmplitude = rollAmplitude,
		liftAmplitude = liftAmplitude,
		attackPitchAmplitude = attackPitchAmplitude,
		attackRollAmplitude = attackRollAmplitude,
		attackReach = attackReach,
	}
end

local function collectLimbJoints(enemyModel, rootPart, state)
	local joints = {}

	for _, descendant in ipairs(enemyModel:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local jointDefinition = buildJointDefinition(rootPart, state, descendant)
			if jointDefinition then
				table.insert(joints, jointDefinition)
			end
		end
	end

	return joints
end

local function resolveLocomotionMode(enemyModel, baseTemplateName)
	local lowerBaseName = string.lower(baseTemplateName)
	if containsKeyword(lowerBaseName, FLY_NAME_HINTS) then
		return "fly"
	end

	for _, descendant in ipairs(enemyModel:GetDescendants()) do
		local lowerName = string.lower(descendant.Name)
		if containsKeyword(lowerName, FLY_RIG_HINTS) then
			return "fly"
		end
	end

	return "walk"
end

local function getAttackAlpha(state)
	if state.style.attackDuration <= 0 or state.lastAttackAt == nil then
		return 0
	end

	local elapsedSinceAttack = os.clock() - state.lastAttackAt
	if elapsedSinceAttack < 0 or elapsedSinceAttack > state.style.attackDuration then
		return 0
	end

	local progress = elapsedSinceAttack / state.style.attackDuration
	return math.sin(progress * math.pi)
end

local function applyJointTransforms(state)
	if state.destroyed then
		return
	end

	local cycle = getElapsed(state) * state.style.speed
	local attackAlpha = getAttackAlpha(state)

	for _, joint in ipairs(state.joints) do
		local motor = joint.motor
		if motor and motor.Parent then
			local pitch = 0
			local roll = 0
			local translation = Vector3.zero

			if state.isMoving then
				local wave = math.sin(cycle + joint.phaseOffset)
				local secondaryWave = math.sin(cycle * 0.5 + joint.phaseOffset)

				if state.locomotionMode == "fly" then
					if joint.role == "leg" then
						pitch = -joint.pitchAmplitude * 0.35 + wave * joint.pitchAmplitude * 0.35
						translation = Vector3.new(0, math.abs(wave) * joint.liftAmplitude, 0)
					else
						pitch = -wave * joint.pitchAmplitude * 0.55
						roll = joint.sideSign * joint.rollAmplitude * (0.45 + secondaryWave * 0.55)
						translation = Vector3.new(0, math.abs(wave) * joint.liftAmplitude, 0)
					end
				else
					if joint.role == "arm" then
						pitch = -wave * joint.pitchAmplitude
						roll = joint.sideSign * secondaryWave * joint.rollAmplitude
					elseif joint.role == "leg" then
						pitch = wave * joint.pitchAmplitude
						roll = joint.sideSign * secondaryWave * joint.rollAmplitude * 0.35
					else
						pitch = -wave * joint.pitchAmplitude * 0.45
						roll = joint.sideSign * secondaryWave * joint.rollAmplitude * 0.6
					end
				end
			end

			if attackAlpha > 0 then
				if joint.role == "arm" or joint.role == "generic" then
					pitch -= joint.attackPitchAmplitude * attackAlpha
					roll += joint.sideSign * joint.attackRollAmplitude * attackAlpha
					translation += Vector3.new(0, 0, -joint.attackReach * attackAlpha)
				else
					pitch += joint.attackPitchAmplitude * 0.35 * attackAlpha
				end
			end

			motor.Transform = joint.baseTransform * CFrame.new(translation) * CFrame.Angles(pitch, 0, roll)
		end
	end
end

local function resetJointTransforms(state)
	for _, joint in ipairs(state.joints) do
		local motor = joint.motor
		if motor and motor.Parent then
			motor.Transform = joint.baseTransform
		end
	end
end

local function startJointLoop(state)
	if state.loopStarted or #state.joints == 0 then
		return
	end

	state.loopStarted = true

	task.spawn(function()
		local lastUpdateAt = os.clock()

		while not state.destroyed and state.enemyModel.Parent do
			local now = os.clock()
			if now - lastUpdateAt >= JOINT_UPDATE_INTERVAL then
				lastUpdateAt = now
				applyJointTransforms(state)
			end
			RunService.Heartbeat:Wait()
		end

		resetJointTransforms(state)
	end)
end

function EnemyMotionAnimator.createState(enemyModel, templateName, rootPart)
	local baseTemplateName = SharedEnemyDefinitions.resolveBaseTemplateName(templateName)
	if type(baseTemplateName) ~= "string" or baseTemplateName == "" then
		baseTemplateName = tostring(templateName or "Enemy")
	end

	local seed = hashName(baseTemplateName)
	local locomotionMode = resolveLocomotionMode(enemyModel, baseTemplateName)
	local styleList = if locomotionMode == "fly" then FLY_STYLES else WALK_STYLES
	local baseStyle = styleList[(seed % #styleList) + 1]

	local state = {
		enemyModel = enemyModel,
		startedAt = os.clock() - ((seed % 97) / 17),
		lastAttackAt = nil,
		lastAppliedOffset = CFrame.new(),
		locomotionMode = locomotionMode,
		style = scaleStyle(baseStyle, seed),
		isMoving = false,
		destroyed = false,
		joints = {},
		loopStarted = false,
	}

	if rootPart then
		state.joints = collectLimbJoints(enemyModel, rootPart, state)
	end

	startJointLoop(state)
	return state
end

function EnemyMotionAnimator.step(state, deltaTime)
	return
end

function EnemyMotionAnimator.triggerAttack(state)
	if not state then
		return
	end

	state.lastAttackAt = os.clock()
end

function EnemyMotionAnimator.getReferenceRootCFrame(state, liveRootCFrame)
	if not state then
		return liveRootCFrame
	end

	return liveRootCFrame * state.lastAppliedOffset:Inverse()
end

function EnemyMotionAnimator.commitOffset(state, offsetCFrame)
	if not state then
		return
	end

	state.lastAppliedOffset = offsetCFrame or CFrame.new()
end

function EnemyMotionAnimator.clearOffset(state)
	EnemyMotionAnimator.commitOffset(state, CFrame.new())
end

function EnemyMotionAnimator.setMoving(state, isMoving)
	if not state then
		return
	end

	state.isMoving = isMoving == true
end

function EnemyMotionAnimator.destroy(state)
	if not state or state.destroyed then
		return
	end

	state.destroyed = true
	resetJointTransforms(state)
end

function EnemyMotionAnimator.getRootMotionOffset(state, isMoving)
	if not state then
		return CFrame.new()
	end

	local style = state.style
	local motionOffset = CFrame.new()

	if isMoving == true then
		local cycle = getElapsed(state) * style.speed

		if state.locomotionMode == "fly" then
			local lift = math.sin(cycle) * style.vertical
			local sway = math.sin(cycle * 0.65 + 0.4) * style.sway
			local pitch = math.cos(cycle * 0.8) * style.pitch
			local roll = math.sin(cycle * 1.4) * style.roll
			motionOffset = CFrame.new(sway, lift, 0) * CFrame.Angles(pitch, 0, roll)
		else
			local stride = math.sin(cycle)
			local bounce = math.abs(stride) * style.vertical
			local sway = stride * style.sway
			local pitch = -math.abs(math.cos(cycle)) * style.pitch
			local roll = math.sin(cycle * 0.55 + 0.2) * style.roll
			motionOffset = CFrame.new(sway, bounce, 0) * CFrame.Angles(pitch, 0, roll)
		end
	end

	local attackAlpha = getAttackAlpha(state)
	if attackAlpha > 0 then
		local attackOffset = CFrame.new(0, style.attackLift * attackAlpha, -style.attackPush * attackAlpha)
			* CFrame.Angles(-style.attackPitch * attackAlpha, 0, style.attackRoll * attackAlpha)
		motionOffset *= attackOffset
	end

	return motionOffset
end

return EnemyMotionAnimator
