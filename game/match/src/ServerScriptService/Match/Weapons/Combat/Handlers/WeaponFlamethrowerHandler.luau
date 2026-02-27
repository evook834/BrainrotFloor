--[[
	WeaponFlamethrowerHandler — Flamethrower burst VFX and area damage.
]]

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent.Parent.Parent
local Weapons = script.Parent.Parent.Parent
local AimResolver = require(Match.Combat.AimResolver)
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local WeaponToolFactory = require(Weapons.Tools.WeaponToolFactory)
local WeaponVfx = require(script.Parent.Parent.WeaponVfx)

local getEffectsFolder = WeaponVfx.getEffectsFolder
local createTracerSegment = WeaponVfx.createTracerSegment
local createMuzzleFlash = WeaponVfx.createMuzzleFlash
local createFlamePuff = WeaponVfx.createFlamePuff

local randomGenerator = Random.new()
local playerGroundFireState = {}

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
		if fireEmitter then
			fireEmitter.Enabled = false
		end
		if smokeEmitter then
			smokeEmitter.Enabled = false
		end
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

local function fireFlamethrower(player, character, weaponDef, state, handle)
	if state.isBursting then
		return
	end
	state.isBursting = true

	local burstTicks = math.max(1, math.floor((tonumber(weaponDef.BurstTicks) or 5) + 0.5))
	local burstInterval = math.max(0.03, tonumber(weaponDef.BurstIntervalSeconds) or 0.07)
	local range = math.max(4, tonumber(weaponDef.Range) or 25)
	local arcDegrees = tonumber(weaponDef.ArcDegrees) or 60
	local tickDamage = math.max(1, (tonumber(weaponDef.Damage) or 10) / burstTicks)

	task.spawn(function()
		for _ = 1, burstTicks do
			if not character.Parent then
				break
			end
			local liveRootPart = character:FindFirstChild("HumanoidRootPart")
			if not liveRootPart then
				break
			end

			local origin, direction = WeaponToolFactory.getWeaponOriginAndDirection(player, character, liveRootPart, handle)
			createFlamethrowerVisuals(origin, direction, range)
			local raycastParams = AimResolver.buildWeaponRaycastParams(character, {})
			local impactResult = Workspace:Raycast(origin, direction * range, raycastParams)
			if impactResult then
				spawnFlamethrowerGroundFire(player, weaponDef, impactResult)
			end

			local targets = EnemyTargeting.getEnemiesInCone(character, origin, direction, range, arcDegrees, true)
			for _, enemyModel in ipairs(targets) do
				EnemyDamageService.applyDamageToEnemy(player, enemyModel, tickDamage, weaponDef)
			end
			task.wait(burstInterval)
		end
		state.isBursting = false
	end)
end

return {
	createFlameEmitterBurst = createFlameEmitterBurst,
	createFlamethrowerVisuals = createFlamethrowerVisuals,
	spawnFlamethrowerGroundFire = spawnFlamethrowerGroundFire,
	fireFlamethrower = fireFlamethrower,
}
