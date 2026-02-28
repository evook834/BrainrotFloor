--[[
	WeaponVfx — Weapon effects folder and VFX creators (tracer, muzzle flash, flame, explosion).
	Used by ShopService and SentryRuntime for combat visuals.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WeaponVfx = {}

local weaponEffectsFolder = nil
local randomGenerator = Random.new()

function WeaponVfx.getEffectsFolder()
	if weaponEffectsFolder and weaponEffectsFolder.Parent == Workspace then
		return weaponEffectsFolder
	end
	weaponEffectsFolder = Workspace:FindFirstChild("WeaponEffects")
	if weaponEffectsFolder and weaponEffectsFolder:IsA("Folder") then
		return weaponEffectsFolder
	end
	if weaponEffectsFolder then
		weaponEffectsFolder:Destroy()
	end
	weaponEffectsFolder = Instance.new("Folder")
	weaponEffectsFolder.Name = "WeaponEffects"
	weaponEffectsFolder.Parent = Workspace
	return weaponEffectsFolder
end

function WeaponVfx.createTracerSegment(startPos, endPos, color, thickness, lifetimeSeconds)
	local delta = endPos - startPos
	local length = delta.Magnitude
	if length <= 0.05 then
		return
	end
	local segment = Instance.new("Part")
	segment.Name = "WeaponTracer"
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false
	segment.CanQuery = false
	segment.Material = Enum.Material.Neon
	segment.Color = color or Color3.fromRGB(255, 230, 140)
	segment.Size = Vector3.new(thickness or 0.18, thickness or 0.18, length)
	segment.CFrame = CFrame.lookAt((startPos + endPos) * 0.5, endPos)
	segment.Parent = WeaponVfx.getEffectsFolder()
	Debris:AddItem(segment, lifetimeSeconds or 0.1)
end

function WeaponVfx.createMuzzleFlash(position, color, size, lifetimeSeconds)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = color or Color3.fromRGB(255, 190, 95)
	flash.Size = Vector3.new(size or 0.5, size or 0.5, size or 0.5)
	flash.CFrame = CFrame.new(position)
	flash.Parent = WeaponVfx.getEffectsFolder()
	Debris:AddItem(flash, lifetimeSeconds or 0.08)
end

function WeaponVfx.createFlamePuff(position, size, lifetimeSeconds)
	local puff = Instance.new("Part")
	puff.Name = "FlamePuff"
	puff.Shape = Enum.PartType.Ball
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanTouch = false
	puff.CanQuery = false
	puff.Material = Enum.Material.Neon
	puff.Color = Color3.fromRGB(255, 168, 85)
	puff.Transparency = 0.15
	puff.Size = Vector3.new(size, size, size)
	puff.CFrame = CFrame.new(position)
	puff.Parent = WeaponVfx.getEffectsFolder()
	local puffLifetime = math.max(0.08, lifetimeSeconds or 0.14)
	local expandScale = randomGenerator:NextNumber(1.5, 2.2)
	local tween = TweenService:Create(
		puff,
		TweenInfo.new(puffLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = puff.Size * expandScale,
			Transparency = 1,
			Color = Color3.fromRGB(130, 58, 30),
		}
	)
	tween:Play()
	Debris:AddItem(puff, puffLifetime + 0.05)
end

function WeaponVfx.createExplosionEffect(position, radius)
	local blast = Instance.new("Part")
	blast.Name = "RocketExplosion"
	blast.Shape = Enum.PartType.Ball
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanTouch = false
	blast.CanQuery = false
	blast.Material = Enum.Material.Neon
	blast.Color = Color3.fromRGB(255, 145, 70)
	blast.Transparency = 0.2
	blast.Size = Vector3.new(2, 2, 2)
	blast.CFrame = CFrame.new(position)
	blast.Parent = WeaponVfx.getEffectsFolder()
	local tween = TweenService:Create(
		blast,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(radius * 2, radius * 2, radius * 2),
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(blast, 0.25)
end

function WeaponVfx.createFlareExplosionEffect(position, radius, color)
	local effectRadius = math.max(3, tonumber(radius) or 8)
	local flareColor = typeof(color) == "Color3" and color or Color3.fromRGB(255, 105, 70)
	local glowColor = Color3.fromRGB(255, 235, 165)

	WeaponVfx.createExplosionEffect(position, effectRadius * 0.9)

	local flash = Instance.new("Part")
	flash.Name = "FlareExplosionFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = glowColor
	flash.Transparency = 0.06
	flash.Size = Vector3.new(1.4, 1.4, 1.4)
	flash.CFrame = CFrame.new(position)
	flash.Parent = WeaponVfx.getEffectsFolder()
	local flashTween = TweenService:Create(
		flash,
		TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(effectRadius * 2.8, effectRadius * 2.8, effectRadius * 2.8),
			Transparency = 1,
			Color = flareColor,
		}
	)
	flashTween:Play()
	Debris:AddItem(flash, 0.3)

	local burstAnchor = Instance.new("Part")
	burstAnchor.Name = "FlareExplosionBurst"
	burstAnchor.Anchored = true
	burstAnchor.CanCollide = false
	burstAnchor.CanTouch = false
	burstAnchor.CanQuery = false
	burstAnchor.Transparency = 1
	burstAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	burstAnchor.CFrame = CFrame.new(position)
	burstAnchor.Parent = WeaponVfx.getEffectsFolder()
	Debris:AddItem(burstAnchor, 1.2)

	local burstAttachment = Instance.new("Attachment")
	burstAttachment.Parent = burstAnchor

	local burstLight = Instance.new("PointLight")
	burstLight.Color = glowColor
	burstLight.Brightness = 9
	burstLight.Range = effectRadius * 4.5
	burstLight.Parent = burstAnchor
	local lightTween = TweenService:Create(
		burstLight,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Brightness = 0,
			Range = effectRadius * 1.5,
		}
	)
	lightTween:Play()

	local fireBurst = Instance.new("ParticleEmitter")
	fireBurst.Texture = "rbxasset://textures/particles/fire_main.dds"
	fireBurst.LightEmission = 1
	fireBurst.Lifetime = NumberRange.new(0.16, 0.3)
	fireBurst.Speed = NumberRange.new(effectRadius * 1.8, effectRadius * 3.2)
	fireBurst.Drag = 5
	fireBurst.SpreadAngle = Vector2.new(55, 55)
	fireBurst.RotSpeed = NumberRange.new(-140, 140)
	fireBurst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, effectRadius * 0.38),
		NumberSequenceKeypoint.new(0.45, effectRadius * 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	fireBurst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 1),
	})
	fireBurst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, glowColor),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 175, 85)),
		ColorSequenceKeypoint.new(1, flareColor),
	})
	fireBurst.Parent = burstAttachment

	local emberBurst = Instance.new("ParticleEmitter")
	emberBurst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emberBurst.LightEmission = 1
	emberBurst.Lifetime = NumberRange.new(0.22, 0.48)
	emberBurst.Speed = NumberRange.new(effectRadius * 3.2, effectRadius * 5.2)
	emberBurst.Drag = 8
	emberBurst.SpreadAngle = Vector2.new(70, 70)
	emberBurst.Acceleration = Vector3.new(0, 8, 0)
	emberBurst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(0.5, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberBurst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberBurst.Color = ColorSequence.new(glowColor, flareColor)
	emberBurst.Parent = burstAttachment

	local smokeBurst = Instance.new("ParticleEmitter")
	smokeBurst.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeBurst.Lifetime = NumberRange.new(0.4, 0.8)
	smokeBurst.Speed = NumberRange.new(effectRadius * 0.7, effectRadius * 1.5)
	smokeBurst.Drag = 3
	smokeBurst.SpreadAngle = Vector2.new(45, 45)
	smokeBurst.Acceleration = Vector3.new(0, 6, 0)
	smokeBurst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, effectRadius * 0.28),
		NumberSequenceKeypoint.new(0.65, effectRadius * 0.82),
		NumberSequenceKeypoint.new(1, effectRadius * 1.15),
	})
	smokeBurst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.38),
		NumberSequenceKeypoint.new(0.35, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeBurst.Color = ColorSequence.new(Color3.fromRGB(110, 96, 82), Color3.fromRGB(48, 42, 38))
	smokeBurst.Parent = burstAttachment

	fireBurst:Emit(math.max(8, math.floor(effectRadius * 1.2)))
	emberBurst:Emit(math.max(10, math.floor(effectRadius * 1.5)))
	smokeBurst:Emit(math.max(6, math.floor(effectRadius * 0.8)))

	local puffCount = math.clamp(math.floor(effectRadius * 0.7), 4, 8)
	for index = 1, puffCount do
		local angle = ((index - 1) / puffCount) * math.pi * 2
		local offsetDistance = effectRadius * randomGenerator:NextNumber(0.25, 0.7)
		local offset = Vector3.new(
			math.cos(angle) * offsetDistance,
			randomGenerator:NextNumber(0.1, 0.65) * effectRadius * 0.2,
			math.sin(angle) * offsetDistance
		)
		WeaponVfx.createFlamePuff(position + offset, effectRadius * randomGenerator:NextNumber(0.22, 0.42), 0.18)
	end
	WeaponVfx.createFlamePuff(position, math.max(1.6, effectRadius * 0.9), 0.24)
end

return WeaponVfx
