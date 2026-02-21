local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 10)
local weaponAimRemote = nil
if remotesFolder then
	weaponAimRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponAim, 10)
end

local gui = Instance.new("ScreenGui")
gui.Name = "CombatCrosshairUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "CrosshairRoot"
root.Size = UDim2.fromOffset(0, 0)
root.Position = UDim2.fromScale(0.5, 0.5)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.BackgroundTransparency = 1
root.Parent = gui

local function makeBar(name, horizontal)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.BackgroundColor3 = Color3.fromRGB(235, 245, 255)
	bar.BorderSizePixel = 0
	if horizontal then
		bar.Size = UDim2.fromOffset(10, 2)
	else
		bar.Size = UDim2.fromOffset(2, 10)
	end
	bar.Parent = root
	return bar
end

local leftBar = makeBar("Left", true)
local rightBar = makeBar("Right", true)
local topBar = makeBar("Top", false)
local bottomBar = makeBar("Bottom", false)

local centerDot = Instance.new("Frame")
centerDot.Name = "CenterDot"
centerDot.Size = UDim2.fromOffset(4, 4)
centerDot.Position = UDim2.fromOffset(-2, -2)
centerDot.BackgroundColor3 = Color3.fromRGB(235, 245, 255)
centerDot.BorderSizePixel = 0
centerDot.Parent = root

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = centerDot

local currentCharacter = nil
local currentTool = nil
local recoil = 0
local characterConns = {}
local toolConns = {}
local lastAimSentAt = 0
local aimUpdateInterval = 0.08

local function disconnectAll(list)
	for _, conn in ipairs(list) do
		conn:Disconnect()
	end
	table.clear(list)
end

local function sendAimUpdate(forceSend)
	if not weaponAimRemote or not currentTool or not currentCharacter then
		return
	end

	local now = os.clock()
	if not forceSend and now - lastAimSentAt < aimUpdateInterval then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return
	end

	local centerX = viewportSize.X * 0.5
	local centerY = viewportSize.Y * 0.5
	local cameraRay = camera:ViewportPointToRay(centerX, centerY)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { currentCharacter }
	raycastParams.IgnoreWater = true

	local maxDistance = 1800
	local raycastResult = workspace:Raycast(cameraRay.Origin, cameraRay.Direction * maxDistance, raycastParams)
	local hitPosition = cameraRay.Origin + cameraRay.Direction * maxDistance
	if raycastResult then
		hitPosition = raycastResult.Position
	end

	weaponAimRemote:FireServer(hitPosition, cameraRay.Direction.Unit)
	lastAimSentAt = now
end

local function updateToolConnections(tool)
	disconnectAll(toolConns)
	currentTool = tool
	if not currentTool then
		return
	end

	table.insert(toolConns, currentTool.Activated:Connect(function()
		recoil = math.clamp(recoil + 3, 0, 12)
		sendAimUpdate(true)
	end))

	table.insert(toolConns, currentTool.Destroying:Connect(function()
		if currentTool == tool then
			updateToolConnections(nil)
		end
	end))
end

local function bindCharacter(character)
	disconnectAll(characterConns)
	updateToolConnections(nil)
	currentCharacter = character

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			updateToolConnections(child)
			break
		end
	end

	table.insert(characterConns, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			updateToolConnections(child)
		end
	end))

	table.insert(characterConns, character.ChildRemoved:Connect(function(child)
		if child == currentTool then
			updateToolConnections(nil)
		end
	end))
end

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(bindCharacter)

RunService.RenderStepped:Connect(function(deltaTime)
	recoil = math.max(0, recoil - deltaTime * 10)
	sendAimUpdate(false)

	local moveSpread = 0
	local baseSpread = 5
	local color = Color3.fromRGB(230, 240, 255)
	local showCrosshair = true

	if currentCharacter then
		local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			moveSpread = math.clamp(humanoid.MoveDirection.Magnitude * 3.2, 0, 4)
			if humanoid.Health <= 0 then
				showCrosshair = false
			end
		end
	end

	if currentTool then
		local weaponClass = tostring(currentTool:GetAttribute("WeaponClass") or "")
		if weaponClass == "Melee" then
			baseSpread = 3
		elseif weaponClass == "Flamethrower" then
			baseSpread = 7
		elseif weaponClass == "RPG" then
			baseSpread = 9
		else
			baseSpread = 5
		end

		if currentTool:GetAttribute("IsReloading") == true then
			color = Color3.fromRGB(255, 175, 95)
		else
			color = Color3.fromRGB(235, 245, 255)
		end
	else
		color = Color3.fromRGB(190, 200, 215)
	end

	root.Visible = showCrosshair
	if not showCrosshair then
		return
	end

	local spread = baseSpread + moveSpread + recoil
	local barLength = 10
	local barThickness = 2

	leftBar.Size = UDim2.fromOffset(barLength, barThickness)
	leftBar.Position = UDim2.fromOffset(-(spread + barLength), -math.floor(barThickness * 0.5))
	rightBar.Size = UDim2.fromOffset(barLength, barThickness)
	rightBar.Position = UDim2.fromOffset(spread, -math.floor(barThickness * 0.5))
	topBar.Size = UDim2.fromOffset(barThickness, barLength)
	topBar.Position = UDim2.fromOffset(-math.floor(barThickness * 0.5), -(spread + barLength))
	bottomBar.Size = UDim2.fromOffset(barThickness, barLength)
	bottomBar.Position = UDim2.fromOffset(-math.floor(barThickness * 0.5), spread)

	leftBar.BackgroundColor3 = color
	rightBar.BackgroundColor3 = color
	topBar.BackgroundColor3 = color
	bottomBar.BackgroundColor3 = color
	centerDot.BackgroundColor3 = color
end)
