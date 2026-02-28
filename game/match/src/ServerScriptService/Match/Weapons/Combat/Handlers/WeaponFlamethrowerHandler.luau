--[[
	WeaponFlamethrowerHandler — Flamethrower burst VFX and area damage.
]]

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent.Parent.Parent
local Weapons = script.Parent.Parent.Parent
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local WeaponShotResolver = require(Weapons.Tools.WeaponShotResolver)
local WeaponVfx = require(script.Parent.Parent.WeaponVfx)
local WeaponCombatShared = require(script.Parent.WeaponCombatShared)

local getEffectsFolder = WeaponVfx.getEffectsFolder
local buildWeaponRaycastParams = WeaponCombatShared.buildWeaponRaycastParams

local randomGenerator = Random.new()
local playerGroundFireState = setmetatable({}, { __mode = "k" })
local effectEnabledState = setmetatable({}, { __mode = "k" })

local function createFlameEmitterBurst(_origin, _direction, _travelDistance)
	return
end

local function createFlamethrowerVisuals(_origin, _direction, _range)
	return
end

local function setFlamethrowerModelEffectsEnabled(handle, enabled)
	if not handle then
		return
	end

	local effectRoot = handle.Parent or handle
	for _, descendant in ipairs(effectRoot:GetDescendants()) do
		local isToggleEffect = descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam")
		if isToggleEffect then
			if enabled then
				if effectEnabledState[descendant] == nil then
					effectEnabledState[descendant] = descendant.Enabled
				end
				descendant.Enabled = true
				if descendant:IsA("ParticleEmitter") and descendant.Rate <= 0 then
					local emitCount = math.max(1, math.floor((tonumber(descendant:GetAttribute("BurstCount")) or 1) + 0.5))
					descendant:Emit(emitCount)
				end
			else
				local previousEnabled = effectEnabledState[descendant]
				if previousEnabled ~= nil then
					descendant.Enabled = previousEnabled
					effectEnabledState[descendant] = nil
				end
			end
		end
	end
end

local function resolveFlamethrowerPath(character, origin, direction, range)
	local worldExclusions = {}
	local enemyContainer = EnemyTargeting.getEnemyContainer()
	if enemyContainer then
		table.insert(worldExclusions, enemyContainer)
	end
	local worldRaycastParams = buildWeaponRaycastParams(character, worldExclusions)
	local straightLength = math.max(2, range * 0.78)
	local straightVector = direction * straightLength
	local straightImpact = Workspace:Raycast(origin, straightVector, worldRaycastParams)
	if straightImpact then
		return {
			straightDirection = direction,
			straightLength = (straightImpact.Position - origin).Magnitude,
			dropOrigin = nil,
			dropDirection = nil,
			dropLength = 0,
			impactResult = straightImpact,
		}
	end

	local straightEnd = origin + straightVector
	local nominalEnd = origin + direction * range
	local probeHeight = math.max(8, range * 0.3)
	local probeDepth = math.max(12, range * 1.1)
	local groundProbeParams = worldRaycastParams
	local probeStart = nominalEnd + Vector3.new(0, probeHeight, 0)
	local groundResult = Workspace:Raycast(probeStart, Vector3.new(0, -(probeHeight + probeDepth), 0), groundProbeParams)
	local dropEnd = groundResult and groundResult.Position or (nominalEnd - Vector3.new(0, math.max(4, range * 0.2), 0))
	local dropVector = dropEnd - straightEnd
	local dropLength = dropVector.Magnitude
	if dropLength <= 0.05 then
		return {
			straightDirection = direction,
			straightLength = straightLength,
			dropOrigin = nil,
			dropDirection = nil,
			dropLength = 0,
			impactResult = groundResult,
		}
	end

	local dropDirection = dropVector.Unit
	local dropImpact = Workspace:Raycast(straightEnd, dropVector, worldRaycastParams)
	local resolvedDropLength = dropLength
	local impactResult = groundResult
	if dropImpact then
		resolvedDropLength = (dropImpact.Position - straightEnd).Magnitude
		impactResult = dropImpact
	end

	return {
		straightDirection = direction,
		straightLength = straightLength,
		dropOrigin = straightEnd,
		dropDirection = dropDirection,
		dropLength = resolvedDropLength,
		impactResult = impactResult,
	}
end

local function applyFlamethrowerPathDamage(player, character, origin, pathState, tickDamage, weaponDef, arcDegrees)
	local hitEnemies = {}
	local straightRange = math.max(0, pathState.straightLength or 0)
	if straightRange > 0.05 then
		local straightTargets = EnemyTargeting.getEnemiesInCone(
			character,
			origin,
			pathState.straightDirection,
			straightRange,
			arcDegrees,
			true
		)
		for _, enemyModel in ipairs(straightTargets) do
			if not hitEnemies[enemyModel] then
				hitEnemies[enemyModel] = true
				EnemyDamageService.applyDamageToEnemy(player, enemyModel, tickDamage, weaponDef)
			end
		end
	end

	local dropOrigin = pathState.dropOrigin
	local dropDirection = pathState.dropDirection
	local dropRange = math.max(0, pathState.dropLength or 0)
	if dropOrigin and dropDirection and dropRange > 0.05 then
		local dropTargets = EnemyTargeting.getEnemiesInCone(
			character,
			dropOrigin,
			dropDirection,
			dropRange,
			arcDegrees,
			true
		)
		for _, enemyModel in ipairs(dropTargets) do
			if not hitEnemies[enemyModel] then
				hitEnemies[enemyModel] = true
				EnemyDamageService.applyDamageToEnemy(player, enemyModel, tickDamage, weaponDef)
			end
		end
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
		local overlapParams = nil
		local overlapContainer = nil

		while patch.Parent and elapsed < duration do
			local enemyContainer = EnemyTargeting.getEnemyContainer()
			if enemyContainer then
				if enemyContainer ~= overlapContainer then
					overlapContainer = enemyContainer
					overlapParams = OverlapParams.new()
					overlapParams.FilterType = Enum.RaycastFilterType.Include
					overlapParams.FilterDescendantsInstances = { enemyContainer }
					overlapParams.MaxParts = 256
				end
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
		setFlamethrowerModelEffectsEnabled(handle, true)
		for _ = 1, burstTicks do
			if not character.Parent then
				break
			end
			local liveRootPart = character:FindFirstChild("HumanoidRootPart")
			if not liveRootPart then
				break
			end

			local origin, direction = WeaponShotResolver.getWeaponOriginAndDirection(player, character, liveRootPart, handle)
			local pathState = resolveFlamethrowerPath(character, origin, direction, range)
			local impactResult = pathState.impactResult
			if impactResult then
				spawnFlamethrowerGroundFire(player, weaponDef, impactResult)
			end

			applyFlamethrowerPathDamage(player, character, origin, pathState, tickDamage, weaponDef, arcDegrees)
			task.wait(burstInterval)
		end
		setFlamethrowerModelEffectsEnabled(handle, false)
		state.isBursting = false
	end)
end

return {
	createFlameEmitterBurst = createFlameEmitterBurst,
	createFlamethrowerVisuals = createFlamethrowerVisuals,
	spawnFlamethrowerGroundFire = spawnFlamethrowerGroundFire,
	fireFlamethrower = fireFlamethrower,
}
