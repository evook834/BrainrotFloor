--[[
	WeaponProjectileHandler — Rocket and grenade projectile simulation.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)
local Match = script.Parent.Parent.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local WeaponVfx = require(script.Parent.Parent.WeaponVfx)
local WeaponCombatShared = require(script.Parent.WeaponCombatShared)

local getEffectsFolder = WeaponVfx.getEffectsFolder
local createTracerSegment = WeaponVfx.createTracerSegment
local createExplosionEffect = WeaponVfx.createExplosionEffect
local createFlareExplosionEffect = WeaponVfx.createFlareExplosionEffect
local createFlamePuff = WeaponVfx.createFlamePuff
local resolveShotRay = WeaponCombatShared.resolveShotRay
local resolveAimTargetPosition = WeaponCombatShared.resolveAimTargetPosition
local retargetDirectionToward = WeaponCombatShared.retargetDirectionToward
local buildWeaponRaycastParams = WeaponCombatShared.buildWeaponRaycastParams
local SENTRY_TURRET_FOLDER_NAME = SentryConstants.SENTRY_TURRET_FOLDER_NAME
local SENTRY_ATTR_IS_TURRET = SentryConstants.ATTR_IS_SENTRY_TURRET

local function appendLivePlayerCharacters(exclusions)
	for _, player in ipairs(Players:GetPlayers()) do
		local playerCharacter = player.Character
		if playerCharacter then
			table.insert(exclusions, playerCharacter)
		end
	end
end

local function appendSentryTurretFolder(exclusions)
	local sentryFolder = Workspace:FindFirstChild(SENTRY_TURRET_FOLDER_NAME)
	if sentryFolder then
		table.insert(exclusions, sentryFolder)
	end
end

local function shouldIgnoreSentryTurrets(character, damageContext)
	if type(damageContext) == "table" and damageContext.ignoreSentryTurrets == true then
		return true
	end

	return character and character:IsA("Model") and character:GetAttribute(SENTRY_ATTR_IS_TURRET) == true
end

local function cloneDamageContext(damageContext)
	if type(damageContext) ~= "table" then
		return {}
	end

	local clonedContext = {}
	for key, value in pairs(damageContext) do
		clonedContext[key] = value
	end
	return clonedContext
end

local function hasExplosionBurnConfig(weaponDef)
	return math.max(0, tonumber(weaponDef and weaponDef.BurnDamageFractionPerSecond) or 0) > 0
end

local function hasGroundFireConfig(weaponDef)
	return math.max(0, tonumber(weaponDef and weaponDef.GroundFireRadius) or 0) > 0
		and math.max(0, tonumber(weaponDef and weaponDef.GroundFireDurationSeconds) or 0) > 0
		and math.max(0, tonumber(weaponDef and weaponDef.GroundFireDamageScale) or 0) > 0
end

local function buildExplosionBurnConfig(weaponDef)
	return {
		durationSeconds = math.max(0.25, tonumber(weaponDef.BurnDurationSeconds) or 4),
		tickIntervalSeconds = math.max(0.1, tonumber(weaponDef.BurnTickIntervalSeconds) or 0.5),
		damageFractionPerSecond = math.max(0, tonumber(weaponDef.BurnDamageFractionPerSecond) or 0.18),
		baseDamage = math.max(0, tonumber(weaponDef.BurnBaseDamage) or tonumber(weaponDef.Damage) or 0),
	}
end

local function orientFlareProjectile(part, position, direction)
	if not (part and part:IsA("BasePart")) then
		return
	end

	part.CFrame = CFrame.lookAt(position, position + direction)
end

local function resolveGroundFirePosition(character, position)
	local enemyContainer = EnemyTargeting.getEnemyContainer()
	local exclusions = {}
	if enemyContainer then
		table.insert(exclusions, enemyContainer)
	end

	local raycastParams = buildWeaponRaycastParams(character, exclusions)
	local probeStart = position + Vector3.new(0, 10, 0)
	local groundResult = Workspace:Raycast(probeStart, Vector3.new(0, -28, 0), raycastParams)
	if groundResult then
		local groundNormal = groundResult.Normal
		if typeof(groundNormal) ~= "Vector3" or groundNormal.Magnitude <= 0.001 then
			groundNormal = Vector3.yAxis
		end
		return groundResult.Position + (groundNormal * 0.08), groundNormal
	end

	return position, Vector3.yAxis
end

local function applyStickyAttachment(stickyBomb, targetPart, position)
	if not (stickyBomb and stickyBomb.Parent) then
		return
	end

	stickyBomb.CFrame = CFrame.new(position)
	if targetPart and targetPart:IsA("BasePart") and targetPart.Parent then
		stickyBomb.Anchored = false
		stickyBomb.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "StickyBombWeld"
		weld.Part0 = stickyBomb
		weld.Part1 = targetPart
		weld.Parent = stickyBomb
	else
		stickyBomb.Anchored = true
	end
end

local function spawnGroundFirePatch(player, character, centerPosition, weaponDef)
	if not player or not player:IsA("Player") then
		return
	end

	local radius = ClassService.getWeaponGroundFireRadius(player, weaponDef)
	if type(radius) ~= "number" then
		radius = tonumber(weaponDef.GroundFireRadius) or 8
	end
	radius = math.max(3, radius)

	local duration = ClassService.getWeaponGroundFireDurationSeconds(player, weaponDef)
	if type(duration) ~= "number" then
		duration = tonumber(weaponDef.GroundFireDurationSeconds) or 6
	end
	duration = math.max(0.5, duration)
	local tickInterval = math.max(0.1, tonumber(weaponDef.GroundFireTickIntervalSeconds) or 0.4)
	local damageScale = math.max(0, tonumber(weaponDef.GroundFireDamageScale) or 0.05)
	local damagePerTick = math.max(0, (tonumber(weaponDef.Damage) or 0) * damageScale)
	if damagePerTick <= 0 then
		return
	end

	local groundPosition = resolveGroundFirePosition(character, centerPosition)

	local patch = Instance.new("Part")
	patch.Name = "WeaponGroundFire"
	patch.Anchored = true
	patch.CanCollide = false
	patch.CanTouch = false
	patch.CanQuery = false
	patch.Material = Enum.Material.Neon
	patch.Color = Color3.fromRGB(255, 88, 64)
	patch.Transparency = 0.28
	patch.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	patch.CFrame = CFrame.new(groundPosition + Vector3.new(0, 0.02, 0))
	patch.Parent = getEffectsFolder()
	Debris:AddItem(patch, duration + 0.4)

	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, patch.Size.Y * 0.5, 0)
	attachment.Parent = patch

	local fireEmitter = Instance.new("ParticleEmitter")
	fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	fireEmitter.LightEmission = 1
	fireEmitter.Rate = 42
	fireEmitter.Lifetime = NumberRange.new(0.22, 0.42)
	fireEmitter.Speed = NumberRange.new(3, 7)
	fireEmitter.SpreadAngle = Vector2.new(24, 24)
	fireEmitter.Acceleration = Vector3.new(0, 12, 0)
	fireEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 0.22),
	})
	fireEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 1),
	})
	fireEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 238, 150)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 122, 72)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 34, 24)),
	})
	fireEmitter.Parent = attachment

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.Rate = 12
	smokeEmitter.Lifetime = NumberRange.new(0.5, 0.9)
	smokeEmitter.Speed = NumberRange.new(1.5, 4)
	smokeEmitter.SpreadAngle = Vector2.new(32, 32)
	smokeEmitter.Acceleration = Vector3.new(0, 7, 0)
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.8),
		NumberSequenceKeypoint.new(1, 3.4),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(85, 78, 72), Color3.fromRGB(42, 38, 36))
	smokeEmitter.Parent = attachment

	local burnConfig = ClassService.getBurnOnHitConfig(player, weaponDef)

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
		local queryHeight = math.max(4, radius * 1.6)
		local querySize = Vector3.new(radius * 2, queryHeight, radius * 2)
		local queryCenter = groundPosition + Vector3.new(0, queryHeight * 0.5, 0)
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
			end

			if enemyContainer and overlapParams then
				local touchedParts = Workspace:GetPartBoundsInBox(CFrame.new(queryCenter), querySize, overlapParams)
				local damagedThisTick = {}
				for _, touchedPart in ipairs(touchedParts) do
					local enemyModel = EnemyTargeting.findEnemyModelFromDescendant(touchedPart, enemyContainer)
					if enemyModel and not damagedThisTick[enemyModel] then
						damagedThisTick[enemyModel] = true
						EnemyDamageService.applyDamageToEnemy(player, enemyModel, damagePerTick, weaponDef, {
							allowBurnOnHit = false,
							allowCriticalHits = false,
						})
						if type(burnConfig) == "table" then
							EnemyDamageService.applyBurnDotFromWeapon(player, enemyModel, weaponDef, burnConfig)
						end
					end
				end
			end

			task.wait(tickInterval)
			elapsed += tickInterval
		end
	end)
end

local function fireRocket(player, character, origin, direction, weaponDef, shotOrigin, shotDirection, damageContext)
	local speed = math.max(30, tonumber(weaponDef.ProjectileSpeed) or 140)
	local range = math.max(30, tonumber(weaponDef.Range) or 120)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 16)
	local blastDamage = tonumber(weaponDef.Damage) or 100
	local hasIncendiaryPayload = hasExplosionBurnConfig(weaponDef) or hasGroundFireConfig(weaponDef)
	local ignoreSentryTurrets = shouldIgnoreSentryTurrets(character, damageContext)
	local aimRayOrigin, aimRayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local aimRaycastExclusions = {}
	if ignoreSentryTurrets then
		appendSentryTurretFolder(aimRaycastExclusions)
	end
	local aimTargetPosition = resolveAimTargetPosition(character, aimRayOrigin, aimRayDirection, range, aimRaycastExclusions)
	direction = retargetDirectionToward(origin, direction, aimTargetPosition)

	local rocket = Instance.new("Part")
	rocket.Name = "RocketProjectile"
	rocket.Size = Vector3.new(0.45, 0.45, 2.2)
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(120, 125, 130)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanTouch = false
	rocket.CanQuery = false
	if hasIncendiaryPayload then
		rocket.Material = Enum.Material.Neon
		rocket.Color = typeof(weaponDef.Color) == "Color3" and weaponDef.Color or Color3.fromRGB(255, 108, 62)
		rocket.Transparency = 0.04
	end
	rocket.CFrame = CFrame.lookAt(origin, origin + direction)
	rocket.Parent = getEffectsFolder()
	Debris:AddItem(rocket, 8)

	local noseAttachment = Instance.new("Attachment")
	noseAttachment.Position = Vector3.new(0, 0, -rocket.Size.Z * 0.5)
	noseAttachment.Parent = rocket
	local tailAttachment = Instance.new("Attachment")
	tailAttachment.Position = Vector3.new(0, 0, rocket.Size.Z * 0.5)
	tailAttachment.Parent = rocket
	if hasIncendiaryPayload then
		local flightLight = Instance.new("PointLight")
		flightLight.Color = rocket.Color
		flightLight.Brightness = 3.2
		flightLight.Range = 13
		flightLight.Parent = rocket

		local shellEmitter = Instance.new("ParticleEmitter")
		shellEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		shellEmitter.LightEmission = 1
		shellEmitter.LockedToPart = true
		shellEmitter.Rate = 54
		shellEmitter.Lifetime = NumberRange.new(0.08, 0.16)
		shellEmitter.Speed = NumberRange.new(0.15, 0.9)
		shellEmitter.SpreadAngle = Vector2.new(16, 16)
		shellEmitter.Acceleration = Vector3.new(0, 3, 0)
		shellEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(0.5, 0.26),
			NumberSequenceKeypoint.new(1, 0),
		})
		shellEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.02),
			NumberSequenceKeypoint.new(1, 1),
		})
		shellEmitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 175)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 175, 92)),
			ColorSequenceKeypoint.new(1, rocket.Color),
		})
		shellEmitter.Parent = noseAttachment

		local smokeEmitter = Instance.new("ParticleEmitter")
		smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smokeEmitter.LockedToPart = true
		smokeEmitter.Rate = 12
		smokeEmitter.Lifetime = NumberRange.new(0.18, 0.34)
		smokeEmitter.Speed = NumberRange.new(1.5, 3.5)
		smokeEmitter.Drag = 4
		smokeEmitter.SpreadAngle = Vector2.new(20, 20)
		smokeEmitter.Acceleration = Vector3.new(0, 4, 0)
		smokeEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		smokeEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(95, 88, 84), Color3.fromRGB(48, 42, 40))
		smokeEmitter.Parent = tailAttachment

		local fireTrail = Instance.new("Trail")
		fireTrail.Attachment0 = noseAttachment
		fireTrail.Attachment1 = tailAttachment
		fireTrail.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), rocket.Color)
		fireTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.04),
			NumberSequenceKeypoint.new(1, 1),
		})
		fireTrail.Lifetime = 0.14
		fireTrail.MinLength = 0.04
		fireTrail.FaceCamera = true
		fireTrail.Parent = rocket
	else
		local tailFire = Instance.new("Fire")
		tailFire.Size = 2.5
		tailFire.Heat = 8
		tailFire.Color = Color3.fromRGB(255, 185, 90)
		tailFire.SecondaryColor = Color3.fromRGB(255, 95, 45)
		tailFire.Parent = rocket
	end

	task.spawn(function()
		local currentPosition = origin
		local traveled = 0
		local raycastExclusions = { rocket }
		if type(damageContext) == "table" and damageContext.ignorePlayerCharacters then
			appendLivePlayerCharacters(raycastExclusions)
		end
		if ignoreSentryTurrets then
			appendSentryTurretFolder(raycastExclusions)
		end
		local raycastParams = buildWeaponRaycastParams(character, raycastExclusions)

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
					if fallbackImpact then
						nextPosition = fallbackImpact
					end
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
			if hasIncendiaryPayload then
				createFlareExplosionEffect(currentPosition, blastRadius * 1.1, rocket.Color)
			else
				createExplosionEffect(currentPosition, blastRadius)
			end

			local burnConfig = nil
			if hasExplosionBurnConfig(weaponDef) then
				burnConfig = buildExplosionBurnConfig(weaponDef)
			end

			local hitEnemies = nil
			if burnConfig then
				local blastContext = cloneDamageContext(damageContext)
				blastContext.allowBurnOnHit = false
				hitEnemies = EnemyDamageService.applyBlastDamage(
					player,
					currentPosition,
					blastRadius,
					blastDamage,
					weaponDef,
					blastContext
				)
				for _, enemyModel in ipairs(hitEnemies) do
					EnemyDamageService.applyBurnDotFromWeapon(player, enemyModel, weaponDef, burnConfig)
				end
			else
				hitEnemies = EnemyDamageService.applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef, damageContext)
			end

			if hasGroundFireConfig(weaponDef) then
				spawnGroundFirePatch(player, character, currentPosition, weaponDef)
			end
			rocket:Destroy()
		end
	end)
end

local function fireFlareGun(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local speed = math.max(25, tonumber(weaponDef.ProjectileSpeed) or 95)
	local range = math.max(20, tonumber(weaponDef.Range) or 90)
	local blastRadius = math.max(3, tonumber(weaponDef.BlastRadius) or 10)
	local blastDamage = tonumber(weaponDef.Damage) or 55
	local gravity = math.max(10, Workspace.Gravity * math.clamp(tonumber(weaponDef.ProjectileGravityScale) or 0.16, 0.05, 0.6))
	local aimRayOrigin, aimRayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local aimTargetPosition = resolveAimTargetPosition(character, aimRayOrigin, aimRayDirection, range)
	direction = retargetDirectionToward(origin, direction, aimTargetPosition)

	local flare = Instance.new("Part")
	flare.Name = "FlareProjectile"
	flare.Size = Vector3.new(0.28, 0.28, 1.35)
	flare.Material = Enum.Material.Neon
	flare.Color = typeof(weaponDef.Color) == "Color3" and weaponDef.Color or Color3.fromRGB(255, 110, 70)
	flare.Transparency = 0.04
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanTouch = false
	flare.CanQuery = false
	orientFlareProjectile(flare, origin, direction)
	flare.Parent = getEffectsFolder()
	Debris:AddItem(flare, 8)

	local light = Instance.new("PointLight")
	light.Color = flare.Color
	light.Brightness = 4.5
	light.Range = 14

	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Position = Vector3.new(0, 0, -flare.Size.Z * 0.5)
	frontAttachment.Parent = flare
	local backAttachment = Instance.new("Attachment")
	backAttachment.Position = Vector3.new(0, 0, flare.Size.Z * 0.5)
	backAttachment.Parent = flare
	light.Parent = flare

	local coreEmitter = Instance.new("ParticleEmitter")
	coreEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	coreEmitter.LightEmission = 1
	coreEmitter.LockedToPart = true
	coreEmitter.Rate = 48
	coreEmitter.Lifetime = NumberRange.new(0.08, 0.14)
	coreEmitter.Speed = NumberRange.new(0.2, 0.9)
	coreEmitter.SpreadAngle = Vector2.new(10, 10)
	coreEmitter.Acceleration = Vector3.new(0, 2, 0)
	coreEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(0.45, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	coreEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(1, 1),
	})
	coreEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 175)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 180, 90)),
		ColorSequenceKeypoint.new(1, flare.Color),
	})
	coreEmitter.Parent = frontAttachment

	local emberEmitter = Instance.new("ParticleEmitter")
	emberEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emberEmitter.LightEmission = 1
	emberEmitter.LockedToPart = true
	emberEmitter.Rate = 18
	emberEmitter.Lifetime = NumberRange.new(0.12, 0.22)
	emberEmitter.Speed = NumberRange.new(3, 7)
	emberEmitter.Drag = 5
	emberEmitter.SpreadAngle = Vector2.new(16, 16)
	emberEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 235, 160), Color3.fromRGB(255, 120, 70))
	emberEmitter.Parent = backAttachment

	local smokeEmitter = Instance.new("ParticleEmitter")
	smokeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeEmitter.LockedToPart = true
	smokeEmitter.Rate = 10
	smokeEmitter.Lifetime = NumberRange.new(0.18, 0.3)
	smokeEmitter.Speed = NumberRange.new(1.5, 3.5)
	smokeEmitter.Drag = 4
	smokeEmitter.SpreadAngle = Vector2.new(20, 20)
	smokeEmitter.Acceleration = Vector3.new(0, 4, 0)
	smokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.65),
	})
	smokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeEmitter.Color = ColorSequence.new(Color3.fromRGB(95, 88, 84), Color3.fromRGB(48, 42, 40))
	smokeEmitter.Parent = backAttachment

	local trail = Instance.new("Trail")
	trail.Attachment0 = frontAttachment
	trail.Attachment1 = backAttachment
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 165), flare.Color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.16
	trail.MinLength = 0.02
	trail.FaceCamera = true
	trail.Parent = flare

	task.spawn(function()
		local currentPosition = origin
		local velocity = direction * speed
		local traveled = 0
		local raycastParams = buildWeaponRaycastParams(character, { flare })
		local puffDistanceAccumulator = 0

		while flare.Parent and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepTime = math.min(deltaTime, 0.06)
			local nextVelocity = velocity + Vector3.new(0, -gravity, 0) * stepTime
			local displacement = (velocity + nextVelocity) * 0.5 * stepTime
			local stepDistance = displacement.Magnitude
			if stepDistance <= 0.0001 then
				velocity = nextVelocity
				continue
			end
			if traveled + stepDistance > range then
				displacement = displacement.Unit * (range - traveled)
				stepDistance = displacement.Magnitude
			end
			local raycastResult = Workspace:Raycast(currentPosition, displacement, raycastParams)
			local stepEndPosition = currentPosition + displacement
			local nextPosition = stepEndPosition
			local directTarget = nil

			if raycastResult then
				nextPosition = raycastResult.Position
				directTarget = EnemyTargeting.resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = EnemyTargeting.findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.1)
				if fallbackEnemy then
					directTarget = fallbackEnemy
					if fallbackImpact then
						nextPosition = fallbackImpact
					end
				end
			end

			local facing = displacement.Unit
			orientFlareProjectile(flare, nextPosition, facing)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(255, 205, 120), 0.06, 0.06)
			puffDistanceAccumulator += (nextPosition - currentPosition).Magnitude
			if puffDistanceAccumulator >= 5 then
				puffDistanceAccumulator = 0
				createFlamePuff(nextPosition - (facing * 0.8), 0.65, 0.1)
			end
			currentPosition = nextPosition
			velocity = nextVelocity
			traveled += stepDistance

			if raycastResult or directTarget then
				break
			end
		end

		if flare.Parent then
			createFlareExplosionEffect(currentPosition, blastRadius, flare.Color)
			local hitEnemies = EnemyDamageService.applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef, {
				allowBurnOnHit = false,
			})
			local burnConfig = buildExplosionBurnConfig(weaponDef)
			for _, enemyModel in ipairs(hitEnemies) do
				EnemyDamageService.applyBurnDotFromWeapon(player, enemyModel, weaponDef, burnConfig)
			end
			flare:Destroy()
		end
	end)
end

local function fireStickyBombLauncher(player, character, origin, direction, weaponDef, shotOrigin, shotDirection)
	local speed = math.max(35, tonumber(weaponDef.ProjectileSpeed) or 105)
	local range = math.max(25, tonumber(weaponDef.Range) or 120)
	local blastRadius = math.max(5, tonumber(weaponDef.BlastRadius) or 18)
	local blastDamage = tonumber(weaponDef.Damage) or 150
	local stickDelaySeconds = math.max(0.25, tonumber(weaponDef.StickDelaySeconds) or 2)
	local blinkInterval = math.max(0.05, tonumber(weaponDef.BlinkIntervalSeconds) or 0.1)
	local lobFactor = math.clamp(tonumber(weaponDef.LobFactor) or 0.16, -0.2, 0.55)
	local gravity = math.max(20, Workspace.Gravity)

	local aimRayOrigin, aimRayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local aimTargetPosition = resolveAimTargetPosition(character, aimRayOrigin, aimRayDirection, range)
	direction = retargetDirectionToward(origin, direction, aimTargetPosition)
	direction = (direction + Vector3.new(0, lobFactor, 0)).Unit

	local stickyBomb = Instance.new("Part")
	stickyBomb.Name = "StickyBombProjectile"
	stickyBomb.Shape = Enum.PartType.Ball
	stickyBomb.Size = Vector3.new(0.8, 0.8, 0.8)
	stickyBomb.Material = Enum.Material.Neon
	stickyBomb.Color = Color3.fromRGB(120, 18, 18)
	stickyBomb.Transparency = 0.08
	stickyBomb.Anchored = true
	stickyBomb.CanCollide = false
	stickyBomb.CanTouch = false
	stickyBomb.CanQuery = false
	stickyBomb.CFrame = CFrame.new(origin)
	stickyBomb.Parent = getEffectsFolder()
	Debris:AddItem(stickyBomb, stickDelaySeconds + 8)

	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Position = Vector3.new(0, 0, -stickyBomb.Size.Z * 0.45)
	frontAttachment.Parent = stickyBomb
	local backAttachment = Instance.new("Attachment")
	backAttachment.Position = Vector3.new(0, 0, stickyBomb.Size.Z * 0.45)
	backAttachment.Parent = stickyBomb

	local trail = Instance.new("Trail")
	trail.Attachment0 = frontAttachment
	trail.Attachment1 = backAttachment
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 170, 130), Color3.fromRGB(180, 40, 40))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.08
	trail.MinLength = 0.04
	trail.FaceCamera = true
	trail.Parent = stickyBomb

	local blinkLight = Instance.new("PointLight")
	blinkLight.Color = Color3.fromRGB(255, 72, 72)
	blinkLight.Brightness = 1.4
	blinkLight.Range = 8
	blinkLight.Parent = stickyBomb

	task.spawn(function()
		local currentPosition = origin
		local velocity = direction * speed
		local traveled = 0
		local raycastParams = buildWeaponRaycastParams(character, { stickyBomb })
		local impactResult = nil
		local stuckEnemy = nil

		while stickyBomb.Parent and traveled < range do
			local deltaTime = RunService.Heartbeat:Wait()
			local stepTime = math.min(deltaTime, 0.06)
			local nextVelocity = velocity + Vector3.new(0, -gravity, 0) * stepTime
			local displacement = (velocity + nextVelocity) * 0.5 * stepTime
			local stepDistance = displacement.Magnitude

			if stepDistance <= 0.0001 then
				velocity = nextVelocity
				continue
			end

			if traveled + stepDistance > range then
				displacement = displacement.Unit * (range - traveled)
				stepDistance = displacement.Magnitude
			end

			local raycastResult = Workspace:Raycast(currentPosition, displacement, raycastParams)
			local stepEndPosition = currentPosition + displacement
			local nextPosition = stepEndPosition

			if raycastResult then
				nextPosition = raycastResult.Position
				impactResult = raycastResult
				stuckEnemy = EnemyTargeting.resolveEnemyFromRaycastResult(raycastResult)
			else
				local fallbackEnemy, fallbackImpact = EnemyTargeting.findEnemyAlongSegment(character, currentPosition, stepEndPosition, 1.3)
				if fallbackEnemy then
					stuckEnemy = fallbackEnemy
					nextPosition = fallbackImpact or stepEndPosition
				end
			end

			local facing = displacement.Unit
			stickyBomb.CFrame = CFrame.lookAt(nextPosition, nextPosition + facing)
			createTracerSegment(currentPosition, nextPosition, Color3.fromRGB(255, 110, 92), 0.12, 0.08)
			currentPosition = nextPosition
			velocity = nextVelocity
			traveled += stepDistance

			if impactResult or stuckEnemy then
				break
			end
		end

		if not stickyBomb.Parent then
			return
		end

		local stickTargetPart = nil
		if stuckEnemy then
			if impactResult and impactResult.Instance and impactResult.Instance:IsA("BasePart") then
				stickTargetPart = impactResult.Instance
			else
				stickTargetPart = ModelRootResolver.resolveRootPart(stuckEnemy)
			end
		elseif impactResult and impactResult.Instance and impactResult.Instance:IsA("BasePart") then
			stickTargetPart = impactResult.Instance
		end

		trail.Enabled = false
		createFlamePuff(currentPosition, 0.45, 0.08)
		applyStickyAttachment(stickyBomb, stickTargetPart, currentPosition)

		local blinkState = false
		local detonateAt = os.clock() + stickDelaySeconds
		while stickyBomb.Parent and os.clock() < detonateAt do
			blinkState = not blinkState
			if blinkState then
				stickyBomb.Color = Color3.fromRGB(255, 50, 50)
				stickyBomb.Transparency = 0
				blinkLight.Brightness = 5
			else
				stickyBomb.Color = Color3.fromRGB(92, 10, 10)
				stickyBomb.Transparency = 0.2
				blinkLight.Brightness = 0.8
			end
			task.wait(blinkInterval)
		end

		if stickyBomb.Parent then
			local detonationPosition = stickyBomb.Position
			createExplosionEffect(detonationPosition, blastRadius)
			EnemyDamageService.applyBlastDamage(player, detonationPosition, blastRadius, blastDamage, weaponDef, {
				allowBurnOnHit = false,
				allowCriticalHits = false,
			})
			spawnGroundFirePatch(player, character, detonationPosition, weaponDef)
			stickyBomb:Destroy()
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

	local aimRayOrigin, aimRayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local aimTargetPosition = resolveAimTargetPosition(character, aimRayOrigin, aimRayDirection, range)
	direction = retargetDirectionToward(origin, direction, aimTargetPosition)
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
		local raycastParams = buildWeaponRaycastParams(character, { grenade })
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
					if fallbackImpact then
						nextPosition = fallbackImpact
					end
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
	fireRocket = fireRocket,
	fireFlareGun = fireFlareGun,
	fireStickyBombLauncher = fireStickyBombLauncher,
	fireGrenadeLauncher = fireGrenadeLauncher,
}
