local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local FriendSystem = require(script.Parent:WaitForChild("FriendSystem"))

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

local function updateWorldClickBinding()
	if worldClickConnection then
		worldClickConnection:Disconnect()
		worldClickConnection = nil
	end
end

local function createPlateSurface(targetPlayer, parent)
	local surface = Instance.new("TextButton")
	surface.Name = "NameLabel"
	surface.BackgroundTransparency = 1
	surface.Parent = parent

	surface.Size = UDim2.fromScale(1, 1)
	surface.BackgroundColor3 = Color3.fromRGB(31, 54, 79)
	surface.BackgroundTransparency = 1
	surface.BorderSizePixel = 0
	surface.Text = buildLabelText(targetPlayer)
	surface.TextColor3 = Color3.fromRGB(242, 247, 255)
	surface.TextScaled = false
	surface.TextSize = 15
	surface.Font = Enum.Font.GothamBold
	surface.AutoButtonColor = false
	surface.Active = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = surface

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 144, 188)
	stroke.Transparency = 1
	stroke.Thickness = 1
	stroke.Parent = surface
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
	billboard.Size = UDim2.fromOffset(220, 42)
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
