local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local EnemyService = {}

local function getEnemyTemplates()
	local folder = ServerStorage:FindFirstChild(Config.Enemy.TemplateFolderName)
	if not folder then
		return {}
	end

	local templates = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			table.insert(templates, child)
		end
	end

	return templates
end

local function getSpawnPoints()
	local spawnFolder = Workspace:FindFirstChild(Config.Enemy.SpawnFolderName)
	if not spawnFolder then
		return {}
	end

	local points = {}
	for _, child in spawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end

	return points
end

local function getEnemyContainer()
	local container = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if container then
		return container
	end

	container = Instance.new("Folder")
	container.Name = Config.Enemy.ContainerName
	container.Parent = Workspace
	return container
end

local function chooseRandom(list)
	return list[math.random(1, #list)]
end

function EnemyService.spawnWave(enemyCount, batchDelay)
	local templates = getEnemyTemplates()
	local spawnPoints = getSpawnPoints()

	if #templates == 0 then
		warn("No enemy templates found in ServerStorage/EnemyTemplates")
		return 0
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in Workspace/SpawnPoints")
		return 0
	end

	local container = getEnemyContainer()
	local spawned = 0

	for i = 1, enemyCount do
		local template = chooseRandom(templates)
		local spawnPoint = chooseRandom(spawnPoints)
		local enemy = template:Clone()
		enemy.Name = string.format("Brainrot_%d", i)

		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local root = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart

		if root and humanoid then
			enemy:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
			enemy.Parent = container
			spawned += 1

			humanoid.Died:Once(function()
				task.delay(2, function()
					if enemy and enemy.Parent then
						enemy:Destroy()
					end
				end)
			end)
		else
			warn(string.format("Template %s is missing Humanoid or root part", template:GetFullName()))
			enemy:Destroy()
		end

		task.wait(batchDelay or 0)
	end

	return spawned
end

return EnemyService
