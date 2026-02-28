--[[
	WeaponProjectileHandler — Rocket and grenade projectile simulation.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Match = script.Parent.Parent.Parent.Parent
local EnemyTargeting = require(Match.Enemies.EnemyTargeting)
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

local function appendLivePlayerCharacters(exclusions)
	for _, player in ipairs(Players:GetPlayers()) do
		local playerCharacter = player.Character
		if playerCharacter then
			table.insert(exclusions, playerCharacter)
		end
	end
end

local function buildFlareBurnConfig(weaponDef)
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

local function fireRocket(player, character, origin, direction, weaponDef, shotOrigin, shotDirection, damageContext)
	local speed = math.max(30, tonumber(weaponDef.ProjectileSpeed) or 140)
	local range = math.max(30, tonumber(weaponDef.Range) or 120)
	local blastRadius = math.max(4, tonumber(weaponDef.BlastRadius) or 16)
	local blastDamage = tonumber(weaponDef.Damage) or 100
	local aimRayOrigin, aimRayDirection = resolveShotRay(origin, direction, shotOrigin, shotDirection)
	local aimTargetPosition = resolveAimTargetPosition(character, aimRayOrigin, aimRayDirection, range)
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
		local raycastExclusions = { rocket }
		if type(damageContext) == "table" and damageContext.ignorePlayerCharacters then
			appendLivePlayerCharacters(raycastExclusions)
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
			createExplosionEffect(currentPosition, blastRadius)
			EnemyDamageService.applyBlastDamage(player, currentPosition, blastRadius, blastDamage, weaponDef, damageContext)
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
			local burnConfig = buildFlareBurnConfig(weaponDef)
			for _, enemyModel in ipairs(hitEnemies) do
				EnemyDamageService.applyBurnDotFromWeapon(player, enemyModel, weaponDef, burnConfig)
			end
			flare:Destroy()
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
	fireGrenadeLauncher = fireGrenadeLauncher,
}
