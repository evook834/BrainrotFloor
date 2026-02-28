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
	fireGrenadeLauncher = fireGrenadeLauncher,
}
