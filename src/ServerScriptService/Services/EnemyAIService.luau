local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassService = require(script.Parent.ClassService)

local EnemyAIService = {}

local defaultProfile = {
	MoveSpeed = 12,
	AttackRange = 4.5,
	AttackDamage = 12,
	AttackCooldown = 1.2,
	AcquireRange = 200,
	ThinkInterval = 0.15,
	TurnSpeed = 12,
	FacingPitchOffsetDegrees = 0,
	FacingYawOffsetDegrees = 0,
	FacingRollOffsetDegrees = 0,
	AttackWindup = 0.2,
	ChaseAnimationId = "",
	AttackAnimationId = "",
}

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

local function resolveRootPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		model.PrimaryPart = humanoidRootPart
		return humanoidRootPart
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		model.PrimaryPart = anyPart
		return anyPart
	end

	return nil
end

local function mergeProfile(templateName)
	local profile = table.clone(defaultProfile)

	local configDefaultProfile = Config.Enemy.DefaultProfile or {}
	for key, value in configDefaultProfile do
		profile[key] = value
	end

	local templateProfiles = Config.Enemy.TemplateProfiles or {}
	local templateProfile = templateProfiles[templateName]
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
				end
			end
		end
	end

	return nearestHumanoid, nearestRootPart, nearestDistance
end

local function getFacingOffsetCFrame(profile)
	local pitchOffsetDegrees = tonumber(profile.FacingPitchOffsetDegrees) or 0
	local yawOffsetDegrees = tonumber(profile.FacingYawOffsetDegrees) or 0
	local rollOffsetDegrees = tonumber(profile.FacingRollOffsetDegrees) or 0
	return CFrame.Angles(math.rad(pitchOffsetDegrees), math.rad(yawOffsetDegrees), math.rad(rollOffsetDegrees))
end

local function setMovementState(enemyModel, rootPart, humanoid, targetPosition, speed, deltaTime, turnSpeed, facingOffsetCFrame, hasFacingOffset)
	local planarTarget = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
	local direction = planarTarget - rootPart.Position
	local directionMagnitude = direction.Magnitude
	if directionMagnitude <= 0.01 then
		return
	end

	if humanoid then
		humanoid.WalkSpeed = speed
		humanoid:MoveTo(targetPosition)
		if not hasFacingOffset then
			return
		end
	end

	local destination = rootPart.Position
	if not humanoid then
		local stepSize = math.min(speed * deltaTime, directionMagnitude)
		destination += direction.Unit * stepSize
	end

	local resolvedHeadingFrame = rootPart.CFrame
	if hasFacingOffset then
		resolvedHeadingFrame *= facingOffsetCFrame:Inverse()
	end
	local currentLook = Vector3.new(resolvedHeadingFrame.LookVector.X, 0, resolvedHeadingFrame.LookVector.Z)

	local desiredLook = Vector3.new(direction.Unit.X, 0, direction.Unit.Z)
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

	local targetCFrame = CFrame.lookAt(destination, destination + flatLook)
	if hasFacingOffset then
		targetCFrame *= facingOffsetCFrame
	end

	enemyModel:PivotTo(targetCFrame)
end

local function faceTarget(enemyModel, rootPart, targetPosition, turnSpeed, deltaTime, facingOffsetCFrame, hasFacingOffset)
	local planarTarget = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
	local direction = planarTarget - rootPart.Position
	if direction.Magnitude <= 0.001 then
		return
	end

	local resolvedHeadingFrame = rootPart.CFrame
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

	local targetCFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + blendedLook.Unit)
	if hasFacingOffset then
		targetCFrame *= facingOffsetCFrame
	end

	enemyModel:PivotTo(targetCFrame)
end

local function waitForNextTick(hasHumanoid, thinkInterval)
	if hasHumanoid then
		task.wait(thinkInterval)
		return thinkInterval
	end

	return RunService.Heartbeat:Wait()
end

local function prepareModelForMovement(enemyModel, humanoid)
	for _, descendant in enemyModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Weapon raycasts rely on query/touch visibility on enemy parts.
			descendant.CanQuery = true
			descendant.CanTouch = true

			if humanoid then
				descendant.Anchored = false
			else
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
	end
end

local function stopTrack(track)
	if track and track.IsPlaying then
		track:Stop(0.1)
	end
end

function EnemyAIService.start(enemyModel, templateName)
	local rootPart = resolveRootPart(enemyModel)
	if not rootPart then
		return
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	local profile = mergeProfile(templateName)
	local facingOffsetCFrame = getFacingOffsetCFrame(profile)
	local hasFacingOffset = facingOffsetCFrame ~= CFrame.new()

	prepareModelForMovement(enemyModel, humanoid)

	if humanoid then
		humanoid.AutoRotate = not hasFacingOffset
	end

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	local animator = ensureAnimator(enemyModel, humanoid)
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

	task.spawn(function()
		while enemyModel.Parent do
			local deltaTime = waitForNextTick(humanoid ~= nil, profile.ThinkInterval)

			if humanoid and humanoid.Health <= 0 then
				break
			end

			rootPart = resolveRootPart(enemyModel)
			if not rootPart then
				break
			end

			local targetHumanoid, targetRootPart, distance = getNearestTarget(rootPart.Position, profile.AcquireRange)
			if targetHumanoid and targetRootPart then
				if distance <= profile.AttackRange then
					stopTrack(chaseTrack)
					if not humanoid or hasFacingOffset then
						faceTarget(
							enemyModel,
							rootPart,
							targetRootPart.Position,
							profile.TurnSpeed,
							deltaTime,
							facingOffsetCFrame,
							hasFacingOffset
						)
					end

					local now = os.clock()
					if now - lastAttackAt >= profile.AttackCooldown then
						lastAttackAt = now

						if attackTrack then
							attackTrack:Play(0.05, 1, 1)
						end

						task.delay(profile.AttackWindup, function()
							if not enemyModel.Parent or not targetHumanoid.Parent then
								return
							end

							local liveRootPart = resolveRootPart(enemyModel)
							local liveTargetRoot = targetHumanoid.Parent:FindFirstChild("HumanoidRootPart")
							if not liveRootPart or not liveTargetRoot then
								return
							end

							local attackDistance = (liveTargetRoot.Position - liveRootPart.Position).Magnitude
							if attackDistance <= profile.AttackRange + 1.5 and targetHumanoid.Health > 0 then
								local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
								local damageMultiplier = targetPlayer and ClassService.getIncomingDamageMultiplier(targetPlayer) or 1
								local finalDamage = math.max(0, (tonumber(profile.AttackDamage) or 0) * damageMultiplier)
								if finalDamage > 0 then
									targetHumanoid:TakeDamage(finalDamage)
								end
							end
						end)
					end
				else
					if chaseTrack and not chaseTrack.IsPlaying then
						chaseTrack:Play(0.15, 1, 1)
					end

					setMovementState(
						enemyModel,
						rootPart,
						humanoid,
						targetRootPart.Position,
						profile.MoveSpeed,
						deltaTime,
						profile.TurnSpeed,
						facingOffsetCFrame,
						hasFacingOffset
					)
				end
			else
				stopTrack(chaseTrack)
			end
		end

		stopTrack(chaseTrack)
		stopTrack(attackTrack)
	end)
end

return EnemyAIService
