local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyPresentation = require(ReplicatedStorage.Shared.Enemy.EnemyPresentation)
local EnemyModelUtils = require(script.Parent.EnemyModelUtils)

local ENEMY_CONTAINER_NAME = Config.Enemy.ContainerName
local HEALTH_BAR_CONFIG = EnemyPresentation.HealthBar
local HEALTH_BAR_COLORS = HEALTH_BAR_CONFIG.Colors

local ENEMY_TRACKING = {}
local activeContainer: Instance? = nil
local containerAddedConnection: RBXScriptConnection? = nil
local containerRemovedConnection: RBXScriptConnection? = nil

local function getHealthColor(healthRatio: number): Color3
	if healthRatio <= HEALTH_BAR_CONFIG.CriticalThreshold then
		return HEALTH_BAR_COLORS.Critical
	end
	if healthRatio <= HEALTH_BAR_CONFIG.LowThreshold then
		return HEALTH_BAR_COLORS.Low
	end
	if healthRatio <= HEALTH_BAR_CONFIG.MidThreshold then
		return HEALTH_BAR_COLORS.Mid
	end
	return HEALTH_BAR_COLORS.High
end

local function createHealthBar(enemyModel: Model, rootPart: BasePart): (BillboardGui, Frame)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyHealthBar"
	billboard.Adornee = rootPart
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = HEALTH_BAR_CONFIG.MaxDistance
	billboard.Size = UDim2.fromOffset(HEALTH_BAR_CONFIG.WidthPx, HEALTH_BAR_CONFIG.HeightPx)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, EnemyModelUtils.getHealthBarOffset(enemyModel), 0)
	billboard.Parent = enemyModel

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = HEALTH_BAR_CONFIG.BackgroundColor
	background.BackgroundTransparency = 0.25
	background.BorderSizePixel = 0
	background.Parent = billboard

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, 5)
	backgroundCorner.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Color = HEALTH_BAR_CONFIG.StrokeColor
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = HEALTH_BAR_COLORS.High
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	return billboard, fill
end

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function stopTrackingEnemy(enemyModel: Model)
	local trackedState = ENEMY_TRACKING[enemyModel]
	if not trackedState then
		return
	end

	disconnectAll(trackedState.connections)
	if trackedState.gui and trackedState.gui.Parent then
		trackedState.gui:Destroy()
	end

	ENEMY_TRACKING[enemyModel] = nil
end

local function trackEnemy(enemyModel: Model)
	if ENEMY_TRACKING[enemyModel] then
		return
	end

	local state = {
		connections = {},
		gui = nil,
		fill = nil,
	}
	ENEMY_TRACKING[enemyModel] = state

	local function ensureBar()
		if state.fill and state.gui and state.gui.Parent then
			return
		end

		local rootPart = EnemyModelUtils.resolveRootPart(enemyModel)
		if not rootPart then
			return
		end

		local billboard, fill = createHealthBar(enemyModel, rootPart)
		state.gui = billboard
		state.fill = fill
	end

	local function updateBar()
		ensureBar()
		if not state.fill then
			return
		end

		local maxHealth = enemyModel:GetAttribute("EnemyMaxHealth")
		local currentHealth = enemyModel:GetAttribute("EnemyHealth")

		if type(maxHealth) ~= "number" or maxHealth <= 0 then
			maxHealth = 1
		end
		if type(currentHealth) ~= "number" then
			currentHealth = maxHealth
		end

		local healthRatio = math.clamp(currentHealth / maxHealth, 0, 1)
		state.fill.Size = UDim2.fromScale(healthRatio, 1)
		state.fill.BackgroundColor3 = getHealthColor(healthRatio)
	end

	table.insert(state.connections, enemyModel:GetAttributeChangedSignal("EnemyHealth"):Connect(updateBar))
	table.insert(state.connections, enemyModel:GetAttributeChangedSignal("EnemyMaxHealth"):Connect(updateBar))
	table.insert(state.connections, enemyModel:GetPropertyChangedSignal("PrimaryPart"):Connect(updateBar))
	table.insert(state.connections, enemyModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			stopTrackingEnemy(enemyModel)
		end
	end))

	updateBar()
end

local function bindContainer(container: Instance)
	if activeContainer == container then
		return
	end

	if containerAddedConnection then
		containerAddedConnection:Disconnect()
		containerAddedConnection = nil
	end
	if containerRemovedConnection then
		containerRemovedConnection:Disconnect()
		containerRemovedConnection = nil
	end

	for enemyModel, _ in pairs(ENEMY_TRACKING) do
		stopTrackingEnemy(enemyModel)
	end

	activeContainer = container

	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			trackEnemy(child)
		end
	end

	containerAddedConnection = container.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			trackEnemy(child)
		end
	end)

	containerRemovedConnection = container.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			stopTrackingEnemy(child)
		end
	end)
end

local existingContainer = Workspace:FindFirstChild(ENEMY_CONTAINER_NAME)
if existingContainer then
	bindContainer(existingContainer)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == ENEMY_CONTAINER_NAME then
		bindContainer(child)
	end
end)
