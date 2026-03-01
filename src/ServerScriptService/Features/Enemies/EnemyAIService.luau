local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SharedEnemyDefinitions = require(ReplicatedStorage.Shared.Enemy.EnemyDefinitions)
local Config = require(ReplicatedStorage.Shared.GameConfig)
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local DifficultyService = require(Match.Difficulty.DifficultyService)
local EnemyRegistry = require(Match.Enemies.EnemyRegistry)
local EnemyMotionAnimator = require(Match.Enemies.EnemyMotionAnimator)
local ModelRootResolver = require(script.Parent.ModelRootResolver)

local EnemyAIService = {}
local SENTRY_TURRET_FOLDER_NAME = SentryConstants.SENTRY_TURRET_FOLDER_NAME
local SENTRY_ATTR_IS_TURRET = SentryConstants.ATTR_IS_SENTRY_TURRET
local MOVEMENT_STEP_FRACTIONS = { 1, 0.65, 0.35 }
local MOVEMENT_COLLISION_EPSILON = 0.05
local MOVEMENT_COLLISION_PADDING = Vector3.new(0.5, 0, 0.5)
local PLAYER_COLLISION_PADDING = 0.5

local function normalizeAnimationId(rawId)
	if type(rawId) ~= "string" or rawId == "" then
		return ""
	end

	if string.find(rawId, "rbxassetid://", 1, true) == 1 then
		return rawId
	end

	local numericId = tonumber(rawId)
	if numericId then
		return "rbxassetid://" .. tostring(math.floor(numericId))
	end

	return ""
end

local function mergeProfile(templateName)
	local configDefaultProfile = Config.Enemy.DefaultProfile
	local profile = table.clone(
		type(configDefaultProfile) == "table" and configDefaultProfile or SharedEnemyDefinitions.DefaultProfile
	)

	local templateProfiles = Config.Enemy.TemplateProfiles or {}
	local resolvedTemplateName = SharedEnemyDefinitions.resolveBaseTemplateName(templateName)
	local templateProfile = templateProfiles[resolvedTemplateName]
	if templateProfile then
		for key, value in templateProfile do
			profile[key] = value
		end
	end

	profile.ChaseAnimationId = normalizeAnimationId(profile.ChaseAnimationId)
	profile.AttackAnimationId = normalizeAnimationId(profile.AttackAnimationId)
	return profile
end

local function ensureAnimator(enemyModel, humanoid)
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	end

	local controller = enemyModel:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "EnemyAnimationController"
		controller.Parent = enemyModel
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	return animator
end

local function loadAnimationTrack(animator, animationId)
	if animationId == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if not ok then
		warn(string.format("Failed to load animation %s: %s", animationId, tostring(track)))
		return nil
	end

	return track
end

local function getNearestTarget(originPosition, acquireRange)
	local nearestHumanoid = nil
	local nearestRootPart = nil
	local nearestDistance = acquireRange
	local nearestPlayer = nil

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoid and rootPart and humanoid.Health > 0 then
				local distance = (rootPart.Position - originPosition).Magnitude
				if distance <= nearestDistance then
					nearestDistance = distance
					nearestHumanoid = humanoid
					nearestRootPart = rootPart
					nearestPlayer = player
				end
			end
		end
	end

	local sentryFolder = Workspace:FindFirstChild(SENTRY_TURRET_FOLDER_NAME)
	if sentryFolder then
		for _, child in ipairs(sentryFolder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute(SENTRY_ATTR_IS_TURRET) == true then
				local humanoid = child:FindFirstChildOfClass("Humanoid")
				local rootPart = ModelRootResolver.resolveRootPart(child)
				if humanoid and rootPart and humanoid.Health > 0 then
					local distance = (rootPart.Position - originPosition).Magnitude
					if distance <= nearestDistance then
						nearestDistance = distance
						nearestHumanoid = humanoid
						nearestRootPart = rootPart
						nearestPlayer = nil
					end
				end
			end
		end
	end

	return nearestHumanoid, nearestRootPart, nearestDistance, nearestPlayer
end

local function getFacingOffsetCFrame(profile)
	local pitchOffsetDegrees = tonumber(profile.FacingPitchOffsetDegrees) or 0
	local yawOffsetDegrees = tonumber(profile.FacingYawOffsetDegrees) or 0
	local rollOffsetDegrees = tonumber(profile.FacingRollOffsetDegrees) or 0
	return CFrame.Angles(math.rad(pitchOffsetDegrees), math.rad(yawOffsetDegrees), math.rad(rollOffsetDegrees))
end

local function getPivotToRootOffset(enemyModel, rootPart)
	local modelPivot = enemyModel:GetPivot()
	return modelPivot:ToObjectSpace(rootPart.CFrame)
end

local function pivotEnemyModelToRoot(enemyModel, desiredRootCFrame, pivotToRootOffset)
	local desiredPivotCFrame = desiredRootCFrame * pivotToRootOffset:Inverse()
	enemyModel:PivotTo(desiredPivotCFrame)
end

local function getCollisionBoxSize(enemyModel, rootPart)
	local ok, size = pcall(function()
		return enemyModel:GetExtentsSize()
	end)

	if ok and size then
		return Vector3.new(
			math.max(rootPart.Size.X, size.X + MOVEMENT_COLLISION_PADDING.X),
			math.max(rootPart.Size.Y, size.Y),
			math.max(rootPart.Size.Z, size.Z + MOVEMENT_COLLISION_PADDING.Z)
		)
	end

	return rootPart.Size + MOVEMENT_COLLISION_PADDING
end

local function getCollisionRadius(enemyModel, rootPart)
	local collisionSize = getCollisionBoxSize(enemyModel, rootPart)
	return math.max(collisionSize.X, collisionSize.Z) * 0.5
end

local function getPlayerCollisionRadius(rootPart)
	return math.max(rootPart.Size.X, rootPart.Size.Z) * 0.5 + PLAYER_COLLISION_PADDING
end

local function getEnemyOverlapData(enemyModel, rootPart, rootPosition)
	local overlaps = {}
	local selfRadius = getCollisionRadius(enemyModel, rootPart)

	EnemyRegistry.forEachTrackedEnemy(function(otherEnemyModel)
		if otherEnemyModel == enemyModel then
			return
		end

		local otherRootPart = EnemyRegistry.getRootPart(otherEnemyModel)
		if not otherRootPart then
			return
		end

		local otherHumanoid = otherEnemyModel:FindFirstChildOfClass("Humanoid")
		if otherHumanoid and otherHumanoid.Health <= 0 then
			return
		end

		local planarDelta = rootPosition - otherRootPart.Position
		planarDelta = Vector3.new(planarDelta.X, 0, planarDelta.Z)
		local planarDistance = planarDelta.Magnitude
		local minDistance = selfRadius + getCollisionRadius(otherEnemyModel, otherRootPart)
		if planarDistance < minDistance then
			table.insert(overlaps, {
				delta = planarDelta,
				distance = planarDistance,
				minDistance = minDistance,
			})
		end
	end)

	return overlaps
end

local function isBlockedByPlayers(candidatePosition, selfRadius)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoid and rootPart and humanoid.Health > 0 then
				local planarDelta = rootPart.Position - candidatePosition
				local planarDistance = Vector3.new(planarDelta.X, 0, planarDelta.Z).Magnitude
				local minDistance = selfRadius + getPlayerCollisionRadius(rootPart)
				if planarDistance < minDistance - MOVEMENT_COLLISION_EPSILON then
					return true
				end
			end
		end
	end

	return false
end

local function isBlockingPart(overlappingPart)
	if not (overlappingPart and overlappingPart.Parent) then
		return false
	end

	local blockerModel = overlappingPart:FindFirstAncestorOfClass("Model")
	if blockerModel and EnemyRegistry.isTracked(blockerModel) then
		return true
	end

	if blockerModel then
		local blockingPlayer = Players:GetPlayerFromCharacter(blockerModel)
		if blockingPlayer then
			local blockingHumanoid = blockerModel:FindFirstChildOfClass("Humanoid")
			return blockingHumanoid ~= nil and blockingHumanoid.Health > 0
		end
	end

	return false
end

local function getBlockingParts(candidateRootCFrame, collisionSize, movementOverlapParams)
	local blockingParts = {}
	local overlappingParts = Workspace:GetPartBoundsInBox(candidateRootCFrame, collisionSize, movementOverlapParams)
	for _, overlappingPart in ipairs(overlappingParts) do
		if isBlockingPart(overlappingPart) then
			table.insert(blockingParts, overlappingPart)
		end
	end

	return blockingParts
end

local function isMovementBlocked(enemyModel, rootPart, currentRootPosition, candidateRootCFrame, collisionSize, movementOverlapParams)
	local candidatePosition = candidateRootCFrame.Position
	local currentOverlaps = getEnemyOverlapData(enemyModel, rootPart, currentRootPosition)
	local candidateOverlaps = getEnemyOverlapData(enemyModel, rootPart, candidatePosition)
	if #candidateOverlaps > 0 then
		local currentPenetration = 0
		for _, overlap in ipairs(currentOverlaps) do
			currentPenetration += overlap.minDistance - overlap.distance
		end

		local candidatePenetration = 0
		for _, overlap in ipairs(candidateOverlaps) do
			candidatePenetration += overlap.minDistance - overlap.distance
		end

		if #candidateOverlaps > #currentOverlaps or candidatePenetration > currentPenetration + MOVEMENT_COLLISION_EPSILON then
			return true
		end
	end

	if isBlockedByPlayers(candidatePosition, getCollisionRadius(enemyModel, rootPart)) then
		return true
	end

	local blockingParts = getBlockingParts(candidateRootCFrame, collisionSize, movementOverlapParams)
	for _, blockingPart in ipairs(blockingParts) do
		local blockerPosition = blockingPart.Position
		local currentDistance = (blockerPosition - currentRootPosition).Magnitude
		local candidateDistance = (blockerPosition - candidateRootCFrame.Position).Magnitude
		if candidateDistance <= currentDistance + MOVEMENT_COLLISION_EPSILON then
			return true
		end
	end

	return false
end

local function getTieBreakDirection(enemyModel, referenceRootCFrame)
	local name = tostring(enemyModel.Name or "")
	local hash = 0
	for index = 1, #name do
		hash = (hash * 33 + string.byte(name, index)) % 1024
	end

	return if hash % 2 == 0 then referenceRootCFrame.RightVector else -referenceRootCFrame.RightVector
end

local function resolveStackedOverlap(enemyModel, rootPart, referenceRootCFrame)
	local rootPosition = referenceRootCFrame.Position
	local overlaps = getEnemyOverlapData(enemyModel, rootPart, rootPosition)
	if #overlaps == 0 then
		return nil
	end

	local separation = Vector3.zero
	local totalPenetration = 0
	for _, overlap in ipairs(overlaps) do
		local away = overlap.delta
		if away.Magnitude <= 0.001 then
			away = getTieBreakDirection(enemyModel, referenceRootCFrame)
		end
		local penetration = overlap.minDistance - overlap.distance
		separation += away.Unit * math.max(0.05, penetration)
		totalPenetration += penetration
	end

	local flatSeparation = Vector3.new(separation.X, 0, separation.Z)
	if flatSeparation.Magnitude <= 0.001 then
		return nil
	end

	local separationDirection = flatSeparation.Unit
	local flatLook = Vector3.new(referenceRootCFrame.LookVector.X, 0, referenceRootCFrame.LookVector.Z)
	if flatLook.Magnitude <= 0.001 then
		flatLook = Vector3.new(0, 0, 1)
	end
	flatLook = flatLook.Unit

	local stepSize = math.max(0.75, totalPenetration + MOVEMENT_COLLISION_EPSILON)
	local currentOverlapCount = #overlaps
	local currentPenetration = totalPenetration
	for _, stepFraction in ipairs(MOVEMENT_STEP_FRACTIONS) do
		local scaledStep = stepSize * stepFraction
		local candidatePosition = rootPosition + separationDirection * scaledStep
		local candidateRootCFrame = CFrame.lookAt(candidatePosition, candidatePosition + flatLook)
		local candidateOverlaps = getEnemyOverlapData(enemyModel, rootPart, candidatePosition)
		local candidatePenetration = 0
		for _, overlap in ipairs(candidateOverlaps) do
			candidatePenetration += overlap.minDistance - overlap.distance
		end
		if #candidateOverlaps < currentOverlapCount or candidatePenetration + MOVEMENT_COLLISION_EPSILON < currentPenetration then
			return candidateRootCFrame
		end
	end

	return nil
end

local function resolveMovementCFrame(enemyModel, rootPart, currentRootPosition, moveDirection, stepSize, facingDirection, collisionSize, movementOverlapParams)
	for _, stepFraction in ipairs(MOVEMENT_STEP_FRACTIONS) do
		local scaledStep = stepSize * stepFraction
		if scaledStep > 0.001 then
			local candidatePosition = currentRootPosition + moveDirection * scaledStep
			local candidateRootCFrame = CFrame.lookAt(candidatePosition, candidatePosition + facingDirection)
			if not isMovementBlocked(enemyModel, rootPart, currentRootPosition, candidateRootCFrame, collisionSize, movementOverlapParams) then
				return candidateRootCFrame
			end
		end
	end

	return CFrame.lookAt(currentRootPosition, currentRootPosition + facingDirection)
end

local function setMovementState(enemyModel, rootPart, referenceRootCFrame, targetPosition, speed, deltaTime, turnSpeed, facingOffsetCFrame, hasFacingOffset, pivotToRootOffset, motionOffsetCFrame, movementOverlapParams, collisionSize)
	local rootPosition = referenceRootCFrame.Position
	local planarTarget = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)
	local direction = planarTarget - rootPosition
	local directionMagnitude = direction.Magnitude
	if directionMagnitude <= 0.01 then
		return
	end

	local moveDirection = direction.Unit
	local stepSize = math.min(speed * deltaTime, directionMagnitude)

	local resolvedHeadingFrame = referenceRootCFrame
	if hasFacingOffset then
		resolvedHeadingFrame *= facingOffsetCFrame:Inverse()
	end
	local currentLook = Vector3.new(resolvedHeadingFrame.LookVector.X, 0, resolvedHeadingFrame.LookVector.Z)

	local desiredLook = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if currentLook.Magnitude <= 0.001 then
		currentLook = desiredLook
	end
	if desiredLook.Magnitude <= 0.001 then
		desiredLook = currentLook
	end

	currentLook = currentLook.Unit
	desiredLook = desiredLook.Unit

	local alpha = math.clamp((turnSpeed or 12) * deltaTime, 0, 1)
	local blendedLook = currentLook:Lerp(desiredLook, alpha)
	if blendedLook.Magnitude <= 0.001 then
		blendedLook = desiredLook
	end

	local flatLook = Vector3.new(blendedLook.X, 0, blendedLook.Z)
	if flatLook.Magnitude <= 0.001 then
		flatLook = desiredLook
	end
	flatLook = flatLook.Unit

	local targetCFrame = resolveMovementCFrame(
		enemyModel,
		rootPart,
		rootPosition,
		moveDirection,
		stepSize,
		flatLook,
		collisionSize,
		movementOverlapParams
	)
	if hasFacingOffset then
		targetCFrame *= facingOffsetCFrame
	end
	if motionOffsetCFrame then
		targetCFrame *= motionOffsetCFrame
	end

	pivotEnemyModelToRoot(enemyModel, targetCFrame, pivotToRootOffset)
end

local function faceTarget(enemyModel, referenceRootCFrame, targetPosition, turnSpeed, deltaTime, facingOffsetCFrame, hasFacingOffset, pivotToRootOffset, motionOffsetCFrame)
	local rootPosition = referenceRootCFrame.Position
	local planarTarget = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)
	local direction = planarTarget - rootPosition
	if direction.Magnitude <= 0.001 then
		return
	end

	local resolvedHeadingFrame = referenceRootCFrame
	if hasFacingOffset then
		resolvedHeadingFrame *= facingOffsetCFrame:Inverse()
	end
	local currentLook = Vector3.new(resolvedHeadingFrame.LookVector.X, 0, resolvedHeadingFrame.LookVector.Z)

	if currentLook.Magnitude <= 0.001 then
		currentLook = Vector3.new(0, 0, 1)
	end

	local alpha = math.clamp((turnSpeed or 12) * deltaTime, 0, 1)
	local blendedLook = currentLook.Unit:Lerp(direction.Unit, alpha)
	if blendedLook.Magnitude <= 0.001 then
		blendedLook = direction.Unit
	end

	local targetCFrame = CFrame.lookAt(rootPosition, rootPosition + blendedLook.Unit)
	if hasFacingOffset then
		targetCFrame *= facingOffsetCFrame
	end
	if motionOffsetCFrame then
		targetCFrame *= motionOffsetCFrame
	end

	pivotEnemyModelToRoot(enemyModel, targetCFrame, pivotToRootOffset)
end

local function resolveLiveTargetRootPart(targetHumanoid, fallbackRootPart)
	if targetHumanoid and targetHumanoid.Parent then
		local liveTargetRoot = ModelRootResolver.resolveRootPart(targetHumanoid.Parent)
		if liveTargetRoot then
			return liveTargetRoot
		end
	end

	if fallbackRootPart and fallbackRootPart.Parent then
		return fallbackRootPart
	end

	return nil
end

local function prepareModelForMovement(enemyModel, rootPart)
	for _, descendant in enemyModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Weapon raycasts rely on query/touch visibility on enemy parts.
			descendant.CanQuery = true
			descendant.CanTouch = true

			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	if rootPart and rootPart:IsDescendantOf(enemyModel) then
		rootPart.CanCollide = true
	end
end

local function stopTrack(track)
	if track and track.IsPlaying then
		track:Stop(0.1)
	end
end

local function getEnemyDamageMultiplier(enemyModel)
	local fromAttribute = tonumber(enemyModel:GetAttribute("EnemyDamageMultiplier"))
	if fromAttribute ~= nil then
		return math.max(0, fromAttribute)
	end

	local difficulty = enemyModel:GetAttribute("Difficulty")
	local fromDifficulty = tonumber(DifficultyService.getNumberSetting("EnemyDamageMultiplier", 1, difficulty))
	if fromDifficulty == nil then
		return 1
	end

	return math.max(0, fromDifficulty)
end

function EnemyAIService.start(enemyModel, templateName)
	local rootPart = EnemyRegistry.getRootPart(enemyModel)
	if not rootPart then
		return
	end
	local pivotToRootOffset = getPivotToRootOffset(enemyModel, rootPart)

	local healthHumanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	local profile = mergeProfile(templateName)
	local enemyDamageMultiplier = getEnemyDamageMultiplier(enemyModel)
	local facingOffsetCFrame = getFacingOffsetCFrame(profile)
	local hasFacingOffset = facingOffsetCFrame ~= CFrame.new()
	local motionState = EnemyMotionAnimator.createState(enemyModel, templateName, rootPart)
	local collisionSize = getCollisionBoxSize(enemyModel, rootPart)
	local movementOverlapParams = OverlapParams.new()
	movementOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	movementOverlapParams.FilterDescendantsInstances = { enemyModel }
	movementOverlapParams.MaxParts = 24

	prepareModelForMovement(enemyModel, rootPart)

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	local animator = ensureAnimator(enemyModel, healthHumanoid)
	local chaseTrack = loadAnimationTrack(animator, profile.ChaseAnimationId)
	if chaseTrack then
		chaseTrack.Priority = Enum.AnimationPriority.Movement
		chaseTrack.Looped = true
	end

	local attackTrack = loadAnimationTrack(animator, profile.AttackAnimationId)
	if attackTrack then
		attackTrack.Priority = Enum.AnimationPriority.Action
		attackTrack.Looped = false
	end

	local lastAttackAt = -math.huge
	local thinkInterval = math.max(0.03, tonumber(profile.ThinkInterval) or 0.15)
	local currentTargetHumanoid = nil
	local currentTargetRootPart = nil
	local currentTargetPlayer = nil
	local timeUntilRetarget = 0

	task.spawn(function()
		while enemyModel.Parent do
			local deltaTime = RunService.Heartbeat:Wait()

			if healthHumanoid and healthHumanoid.Health <= 0 then
				break
			end

			rootPart = EnemyRegistry.getRootPart(enemyModel)
			if not rootPart then
				break
			end
			pivotToRootOffset = getPivotToRootOffset(enemyModel, rootPart)
			collisionSize = getCollisionBoxSize(enemyModel, rootPart)
			local referenceRootCFrame = EnemyMotionAnimator.getReferenceRootCFrame(motionState, rootPart.CFrame)
			local separationCFrame = resolveStackedOverlap(enemyModel, rootPart, referenceRootCFrame)
			if separationCFrame then
				pivotEnemyModelToRoot(enemyModel, separationCFrame, pivotToRootOffset)
				EnemyMotionAnimator.clearOffset(motionState)
				continue
			end

			timeUntilRetarget -= deltaTime

			local liveTargetRootPart = resolveLiveTargetRootPart(currentTargetHumanoid, currentTargetRootPart)
			local distance = nil
			local shouldRetarget = timeUntilRetarget <= 0

			if currentTargetHumanoid and currentTargetHumanoid.Health <= 0 then
				shouldRetarget = true
			end

			if currentTargetHumanoid and liveTargetRootPart then
				distance = (liveTargetRootPart.Position - referenceRootCFrame.Position).Magnitude
				if distance > profile.AcquireRange then
					shouldRetarget = true
				end
			elseif currentTargetHumanoid or currentTargetRootPart then
				shouldRetarget = true
			end

			if shouldRetarget then
				currentTargetHumanoid, currentTargetRootPart, distance, currentTargetPlayer =
					getNearestTarget(referenceRootCFrame.Position, profile.AcquireRange)
				liveTargetRootPart = resolveLiveTargetRootPart(currentTargetHumanoid, currentTargetRootPart)

				if currentTargetHumanoid and liveTargetRootPart then
					distance = (liveTargetRootPart.Position - referenceRootCFrame.Position).Magnitude
				else
					currentTargetHumanoid = nil
					currentTargetRootPart = nil
					currentTargetPlayer = nil
					distance = nil
				end

				timeUntilRetarget = thinkInterval
			end

			if currentTargetHumanoid and liveTargetRootPart and distance then
				if distance <= profile.AttackRange then
					stopTrack(chaseTrack)
					EnemyMotionAnimator.setMoving(motionState, false)
					local now = os.clock()
					if now - lastAttackAt >= profile.AttackCooldown then
						lastAttackAt = now
						EnemyMotionAnimator.triggerAttack(motionState)

						if attackTrack then
							attackTrack:Play(0.05, 1, 1)
						end

						local attackTargetHumanoid = currentTargetHumanoid
						local attackTargetPlayer = currentTargetPlayer

						task.delay(profile.AttackWindup, function()
							if not enemyModel.Parent or not attackTargetHumanoid or not attackTargetHumanoid.Parent then
								return
							end

							local liveRootPart = EnemyRegistry.getRootPart(enemyModel)
							local liveTargetRoot = ModelRootResolver.resolveRootPart(attackTargetHumanoid.Parent)
							if not liveRootPart or not liveTargetRoot then
								return
							end

							local attackDistance = (liveTargetRoot.Position - liveRootPart.Position).Magnitude
							if attackDistance <= profile.AttackRange + 1.5 and attackTargetHumanoid.Health > 0 then
								local damageMultiplier = attackTargetPlayer and ClassService.getIncomingDamageMultiplier(attackTargetPlayer) or 1
								local baseDamage = (tonumber(profile.AttackDamage) or 0) * enemyDamageMultiplier
								local finalDamage = math.max(0, baseDamage * damageMultiplier)
								if finalDamage > 0 then
									attackTargetHumanoid:TakeDamage(finalDamage)
								end
							end
						end)
					end

					EnemyMotionAnimator.step(motionState, deltaTime)
					local attackMotionOffset = EnemyMotionAnimator.getRootMotionOffset(motionState, false)
					faceTarget(
						enemyModel,
						referenceRootCFrame,
						liveTargetRootPart.Position,
						profile.TurnSpeed,
						deltaTime,
						facingOffsetCFrame,
						hasFacingOffset,
						pivotToRootOffset,
						attackMotionOffset
					)
					EnemyMotionAnimator.commitOffset(motionState, attackMotionOffset)
				else
					if chaseTrack and not chaseTrack.IsPlaying then
						chaseTrack:Play(0.15, 1, 1)
					end
					EnemyMotionAnimator.setMoving(motionState, true)
					EnemyMotionAnimator.step(motionState, deltaTime)
					local movementMotionOffset = EnemyMotionAnimator.getRootMotionOffset(motionState, true)

					setMovementState(
						enemyModel,
						rootPart,
						referenceRootCFrame,
						liveTargetRootPart.Position,
						profile.MoveSpeed,
						deltaTime,
						profile.TurnSpeed,
						facingOffsetCFrame,
						hasFacingOffset,
						pivotToRootOffset,
						movementMotionOffset,
						movementOverlapParams,
						collisionSize
					)
					EnemyMotionAnimator.commitOffset(motionState, movementMotionOffset)
				end
			else
				stopTrack(chaseTrack)
				EnemyMotionAnimator.setMoving(motionState, false)
				EnemyMotionAnimator.step(motionState, deltaTime)
				pivotEnemyModelToRoot(enemyModel, referenceRootCFrame, pivotToRootOffset)
				EnemyMotionAnimator.clearOffset(motionState)
			end
		end

		EnemyMotionAnimator.setMoving(motionState, false)
		EnemyMotionAnimator.destroy(motionState)
		stopTrack(chaseTrack)
		stopTrack(attackTrack)
	end)
end

return EnemyAIService
