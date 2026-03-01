local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ModelRootResolver = require(script.Parent.ModelRootResolver)

local EnemySpawnResolver = {}

local function getTemplateProfile(templateName)
	local templateProfile = (Config.Enemy.TemplateProfiles or {})[templateName]
	if type(templateProfile) == "table" then
		return templateProfile
	end

	return nil
end

function EnemySpawnResolver.getEnemyTemplates()
	local folder = ServerStorage:FindFirstChild(Config.Enemy.TemplateFolderName)
	if not folder then
		return {}
	end

	local templates = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and ModelRootResolver.resolveRootPart(child) then
			table.insert(templates, child)
		end
	end

	return templates
end

function EnemySpawnResolver.getTemplateByName(templateName)
	local folder = ServerStorage:FindFirstChild(Config.Enemy.TemplateFolderName)
	if not folder then
		return nil
	end

	local template = folder:FindFirstChild(templateName)
	if template and template:IsA("Model") and ModelRootResolver.resolveRootPart(template) then
		return template
	end

	return nil
end

function EnemySpawnResolver.getSpawnPoints()
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

function EnemySpawnResolver.getEnemyContainer()
	local container = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if container then
		return container
	end

	container = Instance.new("Folder")
	container.Name = Config.Enemy.ContainerName
	container.Parent = Workspace
	return container
end

function EnemySpawnResolver.getSpawnOffsetY(enemyModel, templateName, spawnPoint)
	local halfHeight = 2
	local ok, _, size = pcall(function()
		return enemyModel:GetBoundingBox()
	end)
	if ok and size then
		halfHeight = size.Y * 0.5
	end

	local templateProfile = getTemplateProfile(templateName)
	local profileOffsetY = 0
	if type(templateProfile) == "table" and type(templateProfile.SpawnOffsetY) == "number" then
		profileOffsetY = templateProfile.SpawnOffsetY
	end

	local spawnPartHalfHeight = 0
	if spawnPoint and spawnPoint:IsA("BasePart") then
		spawnPartHalfHeight = spawnPoint.Size.Y * 0.5
	end

	return spawnPartHalfHeight + halfHeight + (Config.Enemy.SpawnPaddingY or 0.1) + profileOffsetY
end

function EnemySpawnResolver.addTemplateHitboxProxy(enemyModel, templateName, rootPart)
	local templateProfile = getTemplateProfile(templateName)
	if not templateProfile then
		return
	end

	local hitboxScale = tonumber(templateProfile.HitboxScale) or 1
	local hitboxPadding = tonumber(templateProfile.HitboxPadding) or 0
	if hitboxScale <= 1 and hitboxPadding <= 0 then
		return
	end

	local scaledSize = rootPart.Size * math.max(0.1, hitboxScale)
	local totalPadding = math.max(0, hitboxPadding) * 2
	local proxySize = Vector3.new(
		math.max(0.2, scaledSize.X + totalPadding),
		math.max(0.2, scaledSize.Y + totalPadding),
		math.max(0.2, scaledSize.Z + totalPadding)
	)

	local existingProxy = enemyModel:FindFirstChild("HitboxProxy")
	if existingProxy and existingProxy:IsA("BasePart") then
		existingProxy:Destroy()
	end

	local proxy = Instance.new("Part")
	proxy.Name = "HitboxProxy"
	proxy.Size = proxySize
	proxy.CFrame = rootPart.CFrame
	proxy.Transparency = 1
	proxy.Anchored = false
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = true
	proxy.CastShadow = false
	proxy.Massless = true
	proxy.Parent = enemyModel

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HitboxProxyWeld"
	weld.Part0 = proxy
	weld.Part1 = rootPart
	weld.Parent = proxy
end

return EnemySpawnResolver
