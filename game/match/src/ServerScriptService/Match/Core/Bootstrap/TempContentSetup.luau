--[[
	Ensures temporary dev/test content when missing: enemy template and spawn point.
	Called during match bootstrap so the match can run in Studio without full content.
]]

local TempContentSetup = {}

function TempContentSetup.ensureTempEnemyTemplate(templateFolder)
	local hasEnemyModel = false
	for _, child in templateFolder:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart", true) then
			hasEnemyModel = true
			break
		end
	end

	if hasEnemyModel then
		return
	end

	local model = Instance.new("Model")
	model.Name = "TempBrainrot"
	model:SetAttribute("IsTemporaryTestEnemy", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = Color3.fromRGB(255, 85, 85)
	root.Material = Enum.Material.Neon
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 50
	humanoid.Health = 50
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = templateFolder

	warn("Created temporary enemy template at ServerStorage/EnemyTemplates/TempBrainrot")
end

function TempContentSetup.ensureTempSpawnPoint(spawnFolder)
	for _, child in spawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			return
		end
	end

	local spawnPart = Instance.new("Part")
	spawnPart.Name = "TempSpawnPoint"
	spawnPart.Size = Vector3.new(6, 1, 6)
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.Transparency = 0.2
	spawnPart.Material = Enum.Material.ForceField
	spawnPart.Color = Color3.fromRGB(85, 170, 255)
	spawnPart.CFrame = CFrame.new(0, 6, 0)
	spawnPart.Parent = spawnFolder

	warn("Created temporary spawn point at Workspace/SpawnPoints/TempSpawnPoint")
end

return TempContentSetup
