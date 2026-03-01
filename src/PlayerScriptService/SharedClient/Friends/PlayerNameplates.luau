local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local FriendSystem = require(script.Parent:WaitForChild("FriendSystem"))
local ClassIconAssets = require(ReplicatedStorage.Shared.Classes.ClassIconAssets)
local Config = require(ReplicatedStorage.Shared.GameConfig)

export type RunOptions = {
	interactive: boolean?,
}

local nameplatesByPlayer = {}
local connectionsByPlayer = {}
local started = false
local renderLoopStarted = false
local worldClickConnection = nil
local activeOptions: RunOptions = {
	interactive = false,
}

local BASE_OFFSET_Y = 2.1
local CLOSE_OFFSET_Y = 2.75
local CLOSE_DISTANCE = 4
local FAR_DISTANCE = 10
local SELECTED_CLASS_ID_ATTRIBUTE = "SelectedClassId"
local classDataById = {}

for _, classData in ipairs((Config.ClassSystem and Config.ClassSystem.Classes) or {}) do
	if type(classData) == "table" and type(classData.Id) == "string" and classData.Id ~= "" then
		classDataById[ClassIconAssets.normalizeIconKey(classData.Id)] = classData
	end
end

local function disconnectPlayerConnections(player)
	local connections = connectionsByPlayer[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	connectionsByPlayer[player] = nil
end

local function destroyNameplate(player)
	local existing = nameplatesByPlayer[player]
	if existing then
		existing:Destroy()
		nameplatesByPlayer[player] = nil
	end
end

local function buildLabelText(targetPlayer)
	return targetPlayer.DisplayName
end

local function getPlayerClassIconContent(targetPlayer)
	local classId = targetPlayer:GetAttribute(SELECTED_CLASS_ID_ATTRIBUTE)
	if type(classId) ~= "string" or classId == "" then
		return nil
	end

	local classData = classDataById[ClassIconAssets.normalizeIconKey(classId)]

	return ClassIconAssets.getClassIconContent({
		id = classId,
		name = classData and classData.DisplayName or nil,
		weaponTag = classData and classData.WeaponTag or nil,
	})
end

local function updateWorldClickBinding()
	if worldClickConnection then
		worldClickConnection:Disconnect()
		worldClickConnection = nil
	end
end

local function createPlateSurface(targetPlayer, parent)
	local iconImage = getPlayerClassIconContent(targetPlayer) or ""

	local surface = Instance.new("Frame")
	surface.Name = "Nameplate"
	surface.BackgroundTransparency = 1
	surface.Parent = parent

	surface.Size = UDim2.fromScale(1, 1)
	surface.BorderSizePixel = 0
	surface.ClipsDescendants = false

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.AutomaticSize = Enum.AutomaticSize.X
	content.Size = UDim2.fromOffset(0, 42)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = surface

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	if iconImage ~= "" then
		local iconContainer = Instance.new("Frame")
		iconContainer.Name = "ClassIconContainer"
		iconContainer.BackgroundTransparency = 1
		iconContainer.BorderSizePixel = 0
		iconContainer.Size = UDim2.fromOffset(34, 34)
		iconContainer.LayoutOrder = 1
		iconContainer.Parent = content

		local iconShadow = Instance.new("ImageLabel")
		iconShadow.Name = "ClassIconShadow"
		iconShadow.BackgroundTransparency = 1
		iconShadow.BorderSizePixel = 0
		iconShadow.AnchorPoint = Vector2.new(0.5, 0.5)
		iconShadow.Position = UDim2.new(0.5, 1, 0.5, 1)
		iconShadow.Size = UDim2.fromOffset(46, 46)
		iconShadow.Image = iconImage
		iconShadow.ImageColor3 = Color3.fromRGB(12, 18, 28)
		iconShadow.ImageTransparency = 0.4
		iconShadow.ScaleType = Enum.ScaleType.Fit
		iconShadow.Parent = iconContainer

		local classIcon = Instance.new("ImageLabel")
		classIcon.Name = "ClassIcon"
		classIcon.BackgroundTransparency = 1
		classIcon.BorderSizePixel = 0
		classIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		classIcon.Position = UDim2.fromScale(0.5, 0.5)
		classIcon.Size = UDim2.fromOffset(46, 46)
		classIcon.Image = iconImage
		classIcon.ImageTransparency = 0
		classIcon.ScaleType = Enum.ScaleType.Fit
		classIcon.Parent = iconContainer
	end

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 42)
	label.Text = buildLabelText(targetPlayer)
	label.TextColor3 = Color3.fromRGB(242, 247, 255)
	label.TextScaled = false
	label.TextSize = 15
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.LayoutOrder = 2
	label.Parent = content
end

local function createNameplate(targetPlayer, character)
	destroyNameplate(targetPlayer)

	if not character or not character.Parent then
		return
	end

	local adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FriendNameplate"
	billboard.Size = UDim2.fromOffset(240, 42)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, BASE_OFFSET_Y, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Adornee = adornee
	billboard.Parent = character

	createPlateSurface(targetPlayer, billboard)

	nameplatesByPlayer[targetPlayer] = billboard
end

local function updateNameplateOffsets()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position
	for _, billboard in pairs(nameplatesByPlayer) do
		local adornee = billboard.Adornee
		if not adornee or not adornee:IsA("BasePart") then
			continue
		end

		local distance = (cameraPosition - adornee.Position).Magnitude
		local alpha = math.clamp((FAR_DISTANCE - distance) / (FAR_DISTANCE - CLOSE_DISTANCE), 0, 1)
		local offsetY = BASE_OFFSET_Y + ((CLOSE_OFFSET_Y - BASE_OFFSET_Y) * alpha)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	end
end

local function startRenderLoop()
	if renderLoopStarted then
		return
	end

	renderLoopStarted = true
	RunService.RenderStepped:Connect(function()
		updateNameplateOffsets()
	end)
end

local function bindPlayer(targetPlayer)
	disconnectPlayerConnections(targetPlayer)

	local connections = {}
	connectionsByPlayer[targetPlayer] = connections

	table.insert(connections, targetPlayer.CharacterAdded:Connect(function(character)
		task.defer(createNameplate, targetPlayer, character)
	end))

	table.insert(connections, targetPlayer:GetPropertyChangedSignal("DisplayName"):Connect(function()
		if targetPlayer.Character then
			createNameplate(targetPlayer, targetPlayer.Character)
		end
	end))

	table.insert(connections, targetPlayer:GetAttributeChangedSignal(SELECTED_CLASS_ID_ATTRIBUTE):Connect(function()
		if targetPlayer.Character then
			createNameplate(targetPlayer, targetPlayer.Character)
		end
	end))

	if targetPlayer.Character then
		task.defer(createNameplate, targetPlayer, targetPlayer.Character)
	end
end

local function rerenderAll()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer.Character then
			createNameplate(targetPlayer, targetPlayer.Character)
		end
	end
end

local function run(options: RunOptions?)
	activeOptions = options or activeOptions
	updateWorldClickBinding()

	if started then
		rerenderAll()
		return
	end

	started = true
	FriendSystem.start()
	startRenderLoop()

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		bindPlayer(targetPlayer)
	end

	Players.PlayerAdded:Connect(function(targetPlayer)
		bindPlayer(targetPlayer)
	end)

	Players.PlayerRemoving:Connect(function(targetPlayer)
		destroyNameplate(targetPlayer)
		disconnectPlayerConnections(targetPlayer)
	end)
end

return {
	run = run,
}
