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

return WeaponVfx
