local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local WaveService = require(script.Parent.Services.WaveService)

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureTempEnemyTemplate(templateFolder)
	local hasEnemyModel = false
	for _, child in templateFolder:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
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

local function ensureTempSpawnPoint(spawnFolder)
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

local remotesFolder = ensureFolder(ReplicatedStorage, Config.Remotes.Folder)
if not remotesFolder:FindFirstChild(Config.Remotes.WaveState) then
	local waveStateRemote = Instance.new("RemoteEvent")
	waveStateRemote.Name = Config.Remotes.WaveState
	waveStateRemote.Parent = remotesFolder
end

local templateFolder = ensureFolder(ServerStorage, Config.Enemy.TemplateFolderName)
local spawnFolder = ensureFolder(Workspace, Config.Enemy.SpawnFolderName)
ensureFolder(Workspace, Config.Enemy.ContainerName)
ensureTempEnemyTemplate(templateFolder)
ensureTempSpawnPoint(spawnFolder)

WaveService.start()
