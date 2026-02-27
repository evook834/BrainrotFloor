local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ModelRootResolver = require(script.Parent.ModelRootResolver)

local EnemyRegistry = {}

local TIER_TO_ROLE = {
	Easy = "trash",
	Medium = "medium",
	Hard = "heavy",
	Elite = "special",
}

local activeContainer = nil
local trackedEntriesByModel = {}
local trackedModels = {}
local trackedIndexByModel = {}
local aliveCount = 0
local aliveByRole = {
	trash = 0,
	medium = 0,
	heavy = 0,
	special = 0,
}

local workspaceAddedConnection = nil
local workspaceRemovedConnection = nil
local containerAddedConnection = nil
local containerRemovedConnection = nil

local function adjustAliveCount(role, delta)
	aliveCount += delta
	if aliveByRole[role] ~= nil then
		aliveByRole[role] += delta
	end
end

local function resolveRole(enemyModel)
	local tier = enemyModel:GetAttribute("EnemyTier")
	if type(tier) ~= "string" then
		tier = "Easy"
	end

	return TIER_TO_ROLE[tier] or "trash"
end

local function resolveAlive(enemyModel, humanoid)
	if not enemyModel or enemyModel.Parent == nil then
		return false
	end

	if humanoid then
		return humanoid.Health > 0
	end

	return true
end

local function resolveRootPart(entry)
	local enemyModel = entry.model
	if not enemyModel or enemyModel.Parent == nil then
		entry.rootPart = nil
		return nil
	end

	local rootPart = entry.rootPart
	if rootPart and rootPart.Parent and rootPart:IsDescendantOf(enemyModel) then
		return rootPart
	end

	rootPart = ModelRootResolver.resolveRootPart(enemyModel)
	if rootPart and rootPart:IsA("BasePart") then
		entry.rootPart = rootPart
		return rootPart
	end

	entry.rootPart = nil
	return nil
end

local function setEntryAlive(entry, nextAlive)
	if entry.alive == nextAlive then
		return
	end

	entry.alive = nextAlive
	adjustAliveCount(entry.role, nextAlive and 1 or -1)
end

local function setEntryRole(entry, nextRole)
	if entry.role == nextRole then
		return
	end

	if entry.alive then
		if aliveByRole[entry.role] ~= nil then
			aliveByRole[entry.role] -= 1
		end
		if aliveByRole[nextRole] ~= nil then
			aliveByRole[nextRole] += 1
		end
	end

	entry.role = nextRole
end

local function untrackEnemy(enemyModel)
	local entry = trackedEntriesByModel[enemyModel]
	if not entry then
		return
	end

	if entry.alive then
		adjustAliveCount(entry.role, -1)
	end

	for _, connection in ipairs(entry.connections) do
		connection:Disconnect()
	end

	trackedEntriesByModel[enemyModel] = nil

	local index = trackedIndexByModel[enemyModel]
	if index ~= nil then
		local lastIndex = #trackedModels
		local lastModel = trackedModels[lastIndex]
		trackedModels[index] = lastModel
		trackedModels[lastIndex] = nil
		trackedIndexByModel[enemyModel] = nil
		if lastModel and lastModel ~= enemyModel then
			trackedIndexByModel[lastModel] = index
		end
	end
end

local function trackEnemy(enemyModel)
	if not enemyModel:IsA("Model") or trackedEntriesByModel[enemyModel] then
		return
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	local entry = {
		model = enemyModel,
		humanoid = humanoid,
		role = resolveRole(enemyModel),
		alive = false,
		rootPart = nil,
		connections = {},
	}

	trackedEntriesByModel[enemyModel] = entry
	table.insert(trackedModels, enemyModel)
	trackedIndexByModel[enemyModel] = #trackedModels
	resolveRootPart(entry)
	setEntryAlive(entry, resolveAlive(enemyModel, humanoid))

	table.insert(entry.connections, enemyModel.AncestryChanged:Connect(function()
		if enemyModel.Parent ~= activeContainer then
			untrackEnemy(enemyModel)
		end
	end))
	table.insert(entry.connections, enemyModel:GetAttributeChangedSignal("EnemyTier"):Connect(function()
		setEntryRole(entry, resolveRole(enemyModel))
	end))
	table.insert(entry.connections, enemyModel:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
		entry.rootPart = nil
		resolveRootPart(entry)
	end))

	if humanoid then
		table.insert(entry.connections, humanoid.HealthChanged:Connect(function()
			setEntryAlive(entry, resolveAlive(enemyModel, humanoid))
		end))
	end
end

local function refreshTrackedEnemy(enemyModel)
	local entry = trackedEntriesByModel[enemyModel]
	if not entry then
		return
	end

	setEntryRole(entry, resolveRole(enemyModel))
	entry.rootPart = nil
	resolveRootPart(entry)
	setEntryAlive(entry, resolveAlive(enemyModel, entry.humanoid))
end

local function clearTrackedEnemies()
	while #trackedModels > 0 do
		untrackEnemy(trackedModels[#trackedModels])
	end
end

local function unbindContainer()
	if containerAddedConnection then
		containerAddedConnection:Disconnect()
		containerAddedConnection = nil
	end
	if containerRemovedConnection then
		containerRemovedConnection:Disconnect()
		containerRemovedConnection = nil
	end

	clearTrackedEnemies()
	activeContainer = nil
end

local function bindContainer(container)
	if activeContainer == container then
		return
	end

	unbindContainer()
	activeContainer = container

	for _, child in ipairs(container:GetChildren()) do
		trackEnemy(child)
	end

	containerAddedConnection = container.ChildAdded:Connect(function(child)
		trackEnemy(child)
	end)
	containerRemovedConnection = container.ChildRemoved:Connect(function(child)
		untrackEnemy(child)
	end)
end

local function init()
	workspaceAddedConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == Config.Enemy.ContainerName then
			bindContainer(child)
		end
	end)

	workspaceRemovedConnection = Workspace.ChildRemoved:Connect(function(child)
		if child == activeContainer then
			unbindContainer()
		end
	end)

	local existingContainer = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if existingContainer then
		bindContainer(existingContainer)
	end
end

function EnemyRegistry.getEnemyContainer()
	return activeContainer
end

function EnemyRegistry.isTracked(enemyModel)
	return trackedEntriesByModel[enemyModel] ~= nil
end

function EnemyRegistry.getRootPart(enemyModel)
	local entry = trackedEntriesByModel[enemyModel]
	if entry then
		return resolveRootPart(entry)
	end

	return ModelRootResolver.resolveRootPart(enemyModel)
end

function EnemyRegistry.forEachTrackedEnemy(visitor)
	for index = 1, #trackedModels do
		local enemyModel = trackedModels[index]
		if enemyModel and trackedEntriesByModel[enemyModel] then
			visitor(enemyModel)
		end
	end
end

function EnemyRegistry.registerEnemy(enemyModel)
	if not enemyModel or not enemyModel:IsA("Model") then
		return
	end

	if trackedEntriesByModel[enemyModel] then
		refreshTrackedEnemy(enemyModel)
		return
	end

	trackEnemy(enemyModel)
end

function EnemyRegistry.getAliveCount()
	return aliveCount
end

function EnemyRegistry.getAliveByRole()
	return {
		trash = aliveByRole.trash,
		medium = aliveByRole.medium,
		heavy = aliveByRole.heavy,
		special = aliveByRole.special,
	}
end

init()

return EnemyRegistry
