--[[
	WeaponFireHandlers — Weapon firing and attack behavior.
	Spread + melee: applyBulletSpread, playMeleeSwing, shoulder-motor helpers.
	Attack executors: fireBulletShot, fireMeleeAttack, fireFlamethrower, fireRocket, fireGrenadeLauncher.
	Flamethrower: createFlameEmitterBurst, createFlamethrowerVisuals, spawnFlamethrowerGroundFire.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local WeaponToolSetup = require(script.Parent.WeaponToolSetup)
local WeaponVfx = require(script.Parent.WeaponVfx)
local AimResolver = require(Match.Combat.AimResolver)
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local WeaponToolFactory = require(script.Parent.WeaponToolFactory)

local getEffectsFolder = WeaponVfx.getEffectsFolder
local createTracerSegment = WeaponVfx.createTracerSegment
local createMuzzleFlash = WeaponVfx.createMuzzleFlash
local createFlamePuff = WeaponVfx.createFlamePuff
local createExplosionEffect = WeaponVfx.createExplosionEffect

local resolveWeaponClass = WeaponToolSetup.resolveWeaponClass
local normalizeWeaponToken = WeaponToolSetup.normalizeWeaponToken

local randomGenerator = Random.new()
local playerGroundFireState = {}

local function isSniperWeaponDefinition(weaponDef)
	if type(weaponDef) ~= "table" then
		return false
	end
	local classIdToken = normalizeWeaponToken(weaponDef.ClassId)
	local classTagToken = normalizeWeaponToken(weaponDef.ClassTag)
	local weaponClassToken = normalizeWeaponToken(resolveWeaponClass(weaponDef))
	return classIdToken == "sniper" or classTagToken == "sniper" or weaponClassToken == "sniper"
end

-- Flamethrower VFX
local function createFlameEmitterBurst(origin, direction, travelDistance)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "FlameEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanTouch = false
	emitterPart.CanQuery = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterPart.CFrame = CFrame.lookAt(origin, origin + direction)
	emitterPart.Parent = getEffectsFolder()

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitterPart

	local flameEmitter = Instance.new("ParticleEmitter")
	flameEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	flameEmitter.Rate = 0
	flameEmitter.LightEmission = 1
	flameEmitter.Lifetime = NumberRange.new(0.14, 0.28)
	flameEmitter.Speed = NumberRange.new(
		math.max(12, travelDistance * 0.85),
		math.max(20, travelDistance * 1.25)
	)
	flameEmitter.SpreadAngle = Vector2.new(24, 24)
	flameEmitter.Drag = 4
	flameEmitter.Acceleration = Vector3.new(0, 16, 0)
	flameEmitter.RotSpeed = NumberRange.new(-150, 150)
	flameEmitter.EmissionDirection = Enum.NormalId.Front
	flameEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.4, 1.25),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	flameEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 1),
	})
	flameEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 140)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 165, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 45, 28)),
	})
	flameEmitter.Parent = attachment
	flameEmitter:Emit(24)

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.Rate = 0
	smokeEmitter.Lifetime = NumberRange.new(0.3, 0.55)
	smokeEmitter.Speed = NumberRange.new(7, 13)
	smokeEmitter.SpreadAngle = Vector2.new(30, 30)
	smokeEmitter.Drag = 6
	smokeEmitter.Acceleration = Vector3.new(0, 9, 0)
	smokeEmitter.EmissionDirection = Enum.NormalId.Front
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(45, 45, 45))
	smokeEmitter.Parent = attachment
	smokeEmitter:Emit(10)

	Debris:AddItem(emitterPart, 0.5)
end

local function createFlamethrowerVisuals(origin, direction, range)
	local visualDistance = math.min(range, 15)
	createMuzzleFlash(origin, Color3.fromRGB(255, 165, 90), 1.15, 0.12)
	createMuzzleFlash(origin + direction * 1.1, Color3.fromRGB(255, 210, 120), 0.62, 0.1)
	createTracerSegment(origin, origin + direction * visualDistance, Color3.fromRGB(255, 130, 70), 0.56, 0.08)
	createTracerSegment(origin, origin + direction * (visualDistance * 0.72), Color3.fromRGB(255, 205, 120), 0.32, 0.07)
	createFlameEmitterBurst(origin, direction, visualDistance)

	local upReference = math.abs(direction:Dot(Vector3.yAxis)) > 0.92 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(upReference)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(direction).Unit

	for i = 1, 9 do
		local progress = i / 9
		local travel = visualDistance * progress
		local spread = (1 - progress) * 0.32
		local jitter = right * randomGenerator:NextNumber(-spread, spread) + up * randomGenerator:NextNumber(-spread, spread)
		local puffPosition = origin + direction * travel + jitter
		local puffSize = randomGenerator:NextNumber(0.48, 0.95) * (1 - progress * 0.2)
		createFlamePuff(puffPosition, puffSize, randomGenerator:NextNumber(0.12, 0.22))
	end
end

local function spawnFlamethrowerGroundFire(player, weaponDef, hitResult)
	if not player or not player:IsA("Player") then
		return
	end
	if not hitResult then
		return
	end

	local hitEnemy = EnemyTargeting.resolveEnemyFromRaycastResult(hitResult)
	if hitEnemy then
		return
	end

	local hitNormal = hitResult.Normal
	if typeof(hitNormal) ~= "Vector3" or hitNormal.Magnitude <= 0.001 then
		hitNormal = Vector3.yAxis
	end
	if hitNormal.Y < 0.45 then
		return
	end

	local chance = math.clamp(tonumber(weaponDef.GroundFireChance) or 0.2, 0, 1)
	if chance <= 0 then
		return
	end
	if randomGenerator:NextNumber() > chance then
		return
	end

	local now = os.clock()
	local state = playerGroundFireState[player]
	if not state then
		state = { lastSpawnAt = -math.huge }
		playerGroundFireState[player] = state
	end

	local spawnCooldown = math.max(0.05, tonumber(weaponDef.GroundFireSpawnCooldownSeconds) or 0.45)
	if now - (state.lastSpawnAt or -math.huge) < spawnCooldown then
		return
	end
	state.lastSpawnAt = now

	local radius = math.max(2, tonumber(weaponDef.GroundFireRadius) or 4.5)
	local duration = math.max(0.5, tonumber(weaponDef.GroundFireDurationSeconds) or 2.6)
	local tickInterval = math.max(0.08, tonumber(weaponDef.GroundFireTickIntervalSeconds) or 0.35)
	local damageScale = math.max(0, tonumber(weaponDef.GroundFireDamageScale) or 0.1)
	local damagePerTick = math.max(0, (tonumber(weaponDef.Damage) or 10) * damageScale)
	if damagePerTick <= 0 then
		return
	end

	local centerPosition = hitResult.Position + Vector3.new(0, 0.1, 0)
	local patch = Instance.new("Part")
	patch.Name = "GroundFirePatch"
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanTouch = false
	patch.CanQuery = false
	patch.Material = Enum.Material.Neon
	patch.Color = Color3.fromRGB(255, 120, 55)
	patch.Transparency = 0.35
	patch.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	patch.CFrame = CFrame.new(centerPosition)
	patch.Parent = getEffectsFolder()
	Debris:AddItem(patch, duration + 0.35)

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, patch.Size.Y * 0.5, 0)
	attachment.Parent = patch

	local fireEmitter = Instance.new("ParticleEmitter")
	fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	fireEmitter.LightEmission = 1
	fireEmitter.Rate = 28
	fireEmitter.Lifetime = NumberRange.new(0.2, 0.4)
	fireEmitter.Speed = NumberRange.new(2, 6)
	fireEmitter.SpreadAngle = Vector2.new(20, 20)
	fireEmitter.Acceleration = Vector3.new(0, 10, 0)
	fireEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	fireEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	fireEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 120)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(105, 45, 30)),
	})
	fireEmitter.Parent = attachment

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.Rate = 8
	smokeEmitter.Lifetime = NumberRange.new(0.45, 0.8)
	smokeEmitter.Speed = NumberRange.new(1, 3)
	smokeEmitter.SpreadAngle = Vector2.new(30, 30)
	smokeEmitter.Acceleration = Vector3.new(0, 6, 0)
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 2.4),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(45, 45, 45))
	smokeEmitter.Parent = attachment

	task.delay(duration, function()
		if fireEmitter then fireEmitter.Enabled = false end
		if smokeEmitter then smokeEmitter.Enabled = false end
	end)

	task.spawn(function()
		local elapsed = 0
		local queryHeight = math.max(4, radius * 1.35)
		local querySize = Vector3.new(radius * 2, queryHeight, radius * 2)
		local queryCenter = centerPosition + Vector3.new(0, queryHeight * 0.5, 0)

		while patch.Parent and elapsed < duration do
			local enemyContainer = EnemyTargeting.getEnemyContainer()
			if enemyContainer then
				local overlapParams = OverlapParams.new()
				overlapParams.FilterType = Enum.RaycastFilterType.Include
				overlapParams.FilterDescendantsInstances = { enemyContainer }
				overlapParams.MaxParts = 256
				local touchedParts = Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), querySize, overlapParams)
				local damagedThisTick = {}
				for _, touchedPart in ipairs(touchedParts) do
					local enemyModel = EnemyTargeting.findEnemyModelFromDescendant(touchedPart, enemyContainer)
					if enemyModel and not damagedThisTick[enemyModel] then
						damagedThisTick[enemyModel] = true
						EnemyDamageService.applyDamageToEnemy(player, enemyModel, damagePerTick, weaponDef)
					end
				end
			end
			task.wait(tickInterval)
			elapsed += tickInterval
		end
	end)
end

-- Shoulder motor helpers
local function isRightShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then return false end
	local motorName = motor.Name
	if motorName == "RightShoulder" or motorName == "Right Shoulder" then return true end
	local part0, part1 = motor.Part0, motor.Part1
	if not part0 or not part1 then return false end
	local part0Name, part1Name = part0.Name, part1.Name
	if part1Name ~= "Right Arm" and part1Name ~= "RightUpperArm" then return false end
	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findRightShoulderMotor(character)
	if not character or not character:IsA("Model") then return nil end
	local directR15 = character:FindFirstChild("RightShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then return directR15 end
	local directR6 = character:FindFirstChild("Right Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then return directR6 end
	for _, descendant in character:GetDescendants() do
		if isRightShoulderMotor(descendant) then return descendant end
	end
	return nil
end

local function isLeftShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then return false end
	local motorName = motor.Name
	if motorName == "LeftShoulder" or motorName == "Left Shoulder" then return true end
	local part0, part1 = motor.Part0, motor.Part1
	if not part0 or not part1 then return false end
	local part0Name, part1Name = part0.Name, part1.Name
	if part1Name ~= "Left Arm" and part1Name ~= "LeftUpperArm" then return false end
	return part0Name == "Torso" or part0Name == "UpperTorso"
end

local function findLeftShoulderMotor(character)
	if not character or not character:IsA("Model") then return nil end
	local directR15 = character:FindFirstChild("LeftShoulder", true)
	if directR15 and directR15:IsA("Motor6D") then return directR15 end
	local directR6 = character:FindFirstChild("Left Shoulder", true)
	if directR6 and directR6:IsA("Motor6D") then return directR6 end
	for _, descendant in character:GetDescendants() do
		if isLeftShoulderMotor(descendant) then return descendant end
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
	if type(windupSideDegrees) ~= "number" then windupSideDegrees = -swingSideDegrees * 0.55 end
	local windupRollDegrees = tonumber(weaponDef.SwingWindupRollDegrees)
	if type(windupRollDegrees) ~= "number" then windupRollDegrees = -swingRollDegrees * 0.35 end

	local shoulderMotor = findRightShoulderMotor(character)
	if not shoulderMotor then return end

	local baseC0 = shoulderMotor.C0
	local windupC0 = baseC0 * CFrame.Angles(math.rad(windupDegrees), math.rad(windupSideDegrees), math.rad(windupRollDegrees))
	local strikeC0 = baseC0 * CFrame.Angles(math.rad(-swingForwardDegrees), math.rad(swingSideDegrees), math.rad(swingRollDegrees))

	local function animateMotorC0(fromC0, toC0, durationSeconds)
		local duration = math.max(0.01, durationSeconds)
		local start = os.clock()
		while shoulderMotor.Parent do
			if state.swingToken ~= swingToken then return false end
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			local easedAlpha = 1 - ((1 - alpha) * (1 - alpha))
			shoulderMotor.C0 = fromC0:Lerp(toC0, easedAlpha)
			if alpha >= 1 then return true end
			RunService.Heartbeat:Wait()
		end
		return false
	end

	task.spawn(function()
		local windupTime = swingDuration * 0.24
		local strikeTime = swingDuration * 0.38
		local recoverTime = swingDuration * 0.38
		if not animateMotorC0(baseC0, windupC0, windupTime) then return end
		if not animateMotorC0(windupC0, strikeC0, strikeTime) then return end
		animateMotorC0(strikeC0, baseC0, recoverTime)
	end)
end

local function applyBulletSpread(direction, spreadDegrees)
	local maxDegrees = math.max(0, tonumber(spreadDegrees) or 0)
	if maxDegrees <= 0 then return direction end
	local coneRadius = math.tan(math.rad(maxDegrees))
	local theta = randomGenerator:NextNumber(0, math.pi * 2)
	local radius = coneRadius * math.sqrt(randomGenerator:NextNumber())
	local referenceUp = math.abs(direction:Dot(Vector3.yAxis)) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(referenceUp)
	if right.Magnitude <= 0.001 then right = Vector3.xAxis end
	right = right.Unit
	local up = right:Cross(direction).Unit
	local offset = right * (math.cos(theta) * radius) + up * (math.sin(theta) * radius)
	local spreadDirection = direction + offset
	if spreadDirection.Magnitude <= 0.001 then return direction end
	return spreadDirection.Unit
end

-- Attack executors
local function fireBulletShot(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local isSniperWeapon = isSniperWeaponDefinition(weaponDef)
	local baseRange = math.max(1, tonumber(weaponDef.Range) or 40)
	local range = baseRange * math.max(0.1, ClassService.getWeaponBulletRangeMultiplier(player, weaponDef))
	local rayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local rayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local spreadDegrees = 0
	if not isSniperWeapon then
		spreadDegrees = ClassService.getWeaponSpreadDegrees(player, weaponDef)
		if type(spreadDegrees) ~= "number" then spreadDegrees = weaponDef.SpreadDegrees end
	end
	rayDirection = applyBulletSpread(rayDirection, spreadDegrees)
	local raycastParams = AimResolver.buildWeaponRaycastParams(character, {})
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
			if fallbackImpact then hitPosition = fallbackImpact end
		end
	end

	createMuzzleFlash(origin, Color3.fromRGB(255, 210, 120), 0.35, 0.06)
	createTracerSegment(origin, hitPosition, Color3.fromRGB(255, 235, 140), 0.13, 0.08)
	if enemyTarget then
		EnemyDamageService.applyDamageToEnemy(player, enemyTarget, weaponDef.Damage or 20, weaponDef)
	end
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
		for _, enemyModel in ipairs(hits) do targetsByModel[enemyModel] = true end
	end
	collectTargets(origin, direction, range, arcDegrees)

	local loweredOrigin = origin - Vector3.new(0, originDrop, 0)
	local downwardDirection = direction + Vector3.new(0, -downwardBias, 0)
	if downwardDirection.Magnitude > 0.001 then downwardDirection = downwardDirection.Unit else downwardDirection = direction end
	collectTargets(loweredOrigin, downwardDirection, range + groundRangeBonus, arcDegrees + groundArcBonus)

	if next(targetsByModel) == nil then
		local fallbackEnd = loweredOrigin + downwardDirection * (range + groundRangeBonus)
		local fallbackEnemy = EnemyTargeting.findEnemyAlongSegment(character, loweredOrigin, fallbackEnd, groundExtraRadius, true)
		if fallbackEnemy then targetsByModel[fallbackEnemy] = true end
	end

	for enemyModel in pairs(targetsByModel) do
		EnemyDamageService.applyDamageToEnemy(player, enemyModel, damage, weaponDef)
	end
end

local function fireFlamethrower(player, character, weaponDef, state, handle)
	if state.isBursting then return end
	state.isBursting = true

	local burstTicks = math.max(1, math.floor((tonumber(weaponDef.BurstTicks) or 5) + 0.5))
	local burstInterval = math.max(0.03, tonumber(weaponDef.BurstIntervalSeconds) or 0.07)
	local range = math.max(4, tonumber(weaponDef.Range) or 25)
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 60
	local tickDamage = math.max(1, (tonumber(weaponDef.Damage) or 10) / burstTicks)

	task.spawn(function()
		for _ = 1, burstTicks do
			if not character.Parent then break end
			local liveRootPart = character:FindFirstChild("HumanoidRootPart")
			if not liveRootPart then break end

			local origin, direction = WeaponToolFactory.getWeaponOriginAndDirection(player, character, liveRootPart, handle)
			createFlamethrowerVisuals(origin, direction, range)
			local raycastParams = AimResolver.buildWeaponRaycastParams(character, {})
			local impactResult = Workspace:Raycast(origin, direction * range, raycastParams)
			if impactResult then spawnFlamethrowerGroundFire(player, weaponDef, impactResult) end

			local targets = EnemyTargeting.getEnemiesInCone(character, origin, direction, range, arcDegrees, true)
			for _, enemyModel in ipairs(targets) do
				EnemyDamageService.applyDamageToEnemy(player, enemyModel, tickDamage, weaponDef)
			end
			task.wait(burstInterval)
		end
		state.isBursting = false
	end)
end

local function fireRocket(player, character, origin, direction, weaponDef, shotOrigin, shotDirection, damageContext)
	local speed = math.max(30, tonumber(weaponDef.ProjectileSpeed) or 140)
	local range = math.max(30, tonumber(weaponDef.Range) or 120)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 16)
	local blastDamage = tonumber(weaponDef.Damage) or 100
	local aimRayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local aimRayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local aimRaycastParams = AimResolver.buildWeaponRaycastParams(character, {})
	local aimRaycastResult = Workspace:Raycast(aimRayOrigin, aimRayDirection * range, aimRaycastParams)
	local aimTargetPosition = aimRayOrigin + aimRayDirection * range
	if aimRaycastResult then aimTargetPosition = aimRaycastResult.Position end

	local toAimTarget = aimTargetPosition - origin
	if toAimTarget.Magnitude > 0.01 then direction = toAimTarget.Unit end

	local rocket = Instance.new("Part")
	rocket.Name = "RocketProjectile"
	rocket.Size = Vector3.new(0.45, 0.45, 2.2)
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(120, 125, 130)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanTouch = false
	rocket.CanQuery = false
	rocket.CFrame = CFrame.lookAt(origin, origin + direction)
	rocket.Parent = getEffectsFolder()
	Debris:AddItem(rocket, 8)

	local tailAttachment = Instance.new("Attachment")
	tailAttachment.Position = Vector3.new(0, 0, rocket.Size.Z * 0.5)
	tailAttachment.Parent = rocket
	local tailFire = Instance.new("Fire")
	tailFire.Size = 2.5
	tailFire.Heat = 8
	tailFire.Color = Color3.fromRGB(255, 185, 90)
	tailFire.SecondaryColor = Color3.fromRGB(255, 95, 45)
	tailFire.Parent = rocket

	task.spawn(function()
		local currentPosition = origin
		local traveled = 0
		local raycastParams = AimResolver.buildWeaponRaycastParams(character, { rocket })

		while rocket.Parent and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepDistance = math.min(speed * deltaTime, range - traveled)
			local raycastResult = Workspace:Raycast(currentPosition, direction * stepDistance, raycastParams)
			local stepEndPosition = currentPosition + direction * stepDistance
			local nextPosition = stepEndPosition
			local directTarget = nil
			if raycastResult then
				nextPosition = raycastResult.Position
				directTarget = EnemyTargeting.resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = EnemyTargeting.findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.15)
				if fallbackEnemy then
					directTarget = fallbackEnemy
					if fallbackImpact then nextPosition = fallbackImpact end
				end
			end

			rocket.CFrame = CFrame.lookAt(nextPosition, nextPosition + direction)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(255, 170, 95), 0.22, 0.08)
			currentPosition = nextPosition
			traveled += stepDistance

			if raycastResult or directTarget then
				if directTarget then
					EnemyDamageService.applyDamageToEnemy(player, directTarget, blastDamage, weaponDef, damageContext)
				end
				break
			end
		end

		if rocket.Parent then
			createExplosionEffect(currentPosition, blastRadius)
			EnemyDamageService.applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef, damageContext)
			rocket:Destroy()
		end
	end)
end

local function fireGrenadeLauncher(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local speed = math.max(35, tonumber(weaponDef.ProjectileSpeed) or 110)
	local range = math.max(25, tonumber(weaponDef.Range) or 110)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 12)
	local blastDamage = tonumber(weaponDef.Damage) or 90
	local fuseSeconds = math.max(0.35, tonumber(weaponDef.FuseSeconds) or 2.5)
	local lobFactor = math.clamp(tonumber(weaponDef.LobFactor) or 0.15, -0.2, 0.55)
	local gravity = math.max(20, Workspace.Gravity)

	local aimRayOrigin = typeof(shotOrigin) == "Vector3" and shotOrigin or origin
	local aimRayDirection = typeof(shotDirection) == "Vector3" and shotDirection.Unit or direction
	local aimRaycastParams = AimResolver.buildWeaponRaycastParams(character, {})
	local aimRaycastResult = Workspace:Raycast(aimRayOrigin, aimRayDirection * range, aimRaycastParams)
	local aimTargetPosition = aimRayOrigin + aimRayDirection * range
	if aimRaycastResult then aimTargetPosition = aimRaycastResult.Position end

	local toAimTarget = aimTargetPosition - origin
	if toAimTarget.Magnitude > 0.01 then direction = toAimTarget.Unit end
	direction = (direction + Vector3.new(0, lobFactor, 0)).Unit

	local grenade = Instance.new("Part")
	grenade.Name = "GrenadeProjectile"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(0.9, 0.9, 0.9)
	grenade.Material = Enum.Material.Metal
	grenade.Color = Color3.fromRGB(112, 132, 86)
	grenade.Anchored = true
	grenade.CanCollide = false
	grenade.CanTouch = false
	grenade.CanQuery = false
	grenade.CFrame = CFrame.new(origin)
	grenade.Parent = getEffectsFolder()
	Debris:AddItem(grenade, 8)

	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Position = Vector3.new(0, 0, -grenade.Size.Z * 0.45)
	frontAttachment.Parent = grenade
	local backAttachment = Instance.new("Attachment")
	backAttachment.Position = Vector3.new(0, 0, grenade.Size.Z * 0.45)
	backAttachment.Parent = grenade
	local trail = Instance.new("Trail")
	trail.Attachment0 = frontAttachment
	trail.Attachment1 = backAttachment
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 218, 145), Color3.fromRGB(158, 136, 94))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.08
	trail.MinLength = 0.05
	trail.Parent = grenade

	task.spawn(function()
		local currentPosition = origin
		local velocity = direction * speed
		local elapsed = 0
		local traveled = 0
		local raycastParams = AimResolver.buildWeaponRaycastParams(character, { grenade })
		local directTarget = nil

		while grenade.Parent and elapsed < fuseSeconds and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepTime = math.min(deltaTime, 0.06)
			local nextVelocity = velocity + Vector3.new(0, -gravity, 0) * stepTime
			local displacement = (velocity + nextVelocity) * 0.5 * stepTime

			if displacement.Magnitude <= 0.0001 then
				velocity = nextVelocity
				elapsed += stepTime
				continue
			end

			local raycastResult = Workspace:Raycast(currentPosition, displacement, raycastParams)
			local stepEndPosition = currentPosition + displacement
			local nextPosition = stepEndPosition

			if raycastResult then
				nextPosition = raycastResult.Position
				directTarget = EnemyTargeting.resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = EnemyTargeting.findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.35)
				if fallbackEnemy then
					directTarget = fallbackEnemy
					if fallbackImpact then nextPosition = fallbackImpact end
				end
			end

			local facing = displacement.Unit
			grenade.CFrame = CFrame.lookAt(nextPosition, nextPosition + facing)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(225, 190, 120), 0.18, 0.08)
			currentPosition = nextPosition
			velocity = nextVelocity
			elapsed += stepTime
			traveled += displacement.Magnitude

			if raycastResult or directTarget then
				if directTarget then
					EnemyDamageService.applyDamageToEnemy(player, directTarget, blastDamage, weaponDef)
				end
				break
			end
		end

		if grenade.Parent then
			createExplosionEffect(currentPosition, blastRadius)
			EnemyDamageService.applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef)
			grenade:Destroy()
		end
	end)
end

return {
	applyBulletSpread = applyBulletSpread,
	playMeleeSwing = playMeleeSwing,
	findLeftShoulderMotor = findLeftShoulderMotor,
	findRightShoulderMotor = findRightShoulderMotor,
	createFlameEmitterBurst = createFlameEmitterBurst,
	createFlamethrowerVisuals = createFlamethrowerVisuals,
	spawnFlamethrowerGroundFire = spawnFlamethrowerGroundFire,
	fireBulletShot = fireBulletShot,
	fireMeleeAttack = fireMeleeAttack,
	fireFlamethrower = fireFlamethrower,
	fireRocket = fireRocket,
	fireGrenadeLauncher = fireGrenadeLauncher,
}
