local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local DOT_CURSOR_ICON = "rbxasset://textures/MouseLockedCursor.png"
local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local weaponAimRemote = nil
local weaponFireRemote = nil
if remotesFolder then
	weaponAimRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponAim)
	weaponFireRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponFire)
end

if mouse then
	mouse.Icon = DOT_CURSOR_ICON
end

local gui = Instance.new("ScreenGui")
gui.Name = "CombatCrosshairUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 30
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "CrosshairRoot"
root.Size = UDim2.fromOffset(0, 0)
root.Position = UDim2.fromScale(0.5, 0.5)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.BackgroundTransparency = 1
root.Parent = gui

local currentCharacter = nil
local currentTool = nil
local characterConns = {}
local toolConns = {}
local lastAimSentAt = 0
local aimUpdateInterval = 0.03

local function disconnectAll(list)
	for _, conn in ipairs(list) do
		conn:Disconnect()
	end
	table.clear(list)
end

local function getCrosshairViewportPoint()
	local camera = workspace.CurrentCamera
	if not camera then
		return 0, 0
	end

	local viewportSize = camera.ViewportSize
	local x = viewportSize.X * 0.5
	local y = viewportSize.Y * 0.5
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		local mousePos = UserInputService:GetMouseLocation()
		local insetTopLeft = GuiService:GetGuiInset()
		x = mousePos.X - insetTopLeft.X
		y = mousePos.Y - insetTopLeft.Y
	end

	x = math.clamp(x, 0, viewportSize.X)
	y = math.clamp(y, 0, viewportSize.Y)
	return x, y
end

local function isShopOpen()
	local shopGui = playerGui:FindFirstChild("WeaponShopUi")
	if not shopGui then
		return false
	end

	local shopPanel = shopGui:FindFirstChild("ShopPanel")
	return shopPanel ~= nil and shopPanel:IsA("GuiObject") and shopPanel.Visible
end

local function getCurrentAimData()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil, nil, nil
	end

	local viewportX, viewportY = getCrosshairViewportPoint()
	local cameraRay = camera:ViewportPointToRay(viewportX, viewportY)

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

	return hitPosition, cameraRay.Direction.Unit, cameraRay.Origin
end

local function sendAimUpdate(forceSend)
	if not weaponAimRemote or not currentTool or not currentCharacter then
		return
	end

	local now = os.clock()
	if not forceSend and now - lastAimSentAt < aimUpdateInterval then
		return
	end

	local hitPosition, lookDirection, cameraOrigin = getCurrentAimData()
	if not hitPosition or not lookDirection or not cameraOrigin then
		return
	end

	weaponAimRemote:FireServer(hitPosition, lookDirection, cameraOrigin)
	lastAimSentAt = now
end

local function sendFireRequest()
	if not weaponFireRemote or not currentTool or not currentCharacter then
		return
	end

	local weaponId = currentTool:GetAttribute("WeaponId")
	if type(weaponId) ~= "string" or weaponId == "" then
		return
	end

	local hitPosition, lookDirection, cameraOrigin = getCurrentAimData()
	if not hitPosition or not lookDirection or not cameraOrigin then
		return
	end

	if weaponAimRemote then
		weaponAimRemote:FireServer(hitPosition, lookDirection, cameraOrigin)
	end
	weaponFireRemote:FireServer(weaponId, hitPosition, lookDirection, cameraOrigin)
end

local function updateToolConnections(tool)
	disconnectAll(toolConns)
	currentTool = tool
	if not currentTool then
		return
	end

	table.insert(toolConns, currentTool.Activated:Connect(function()
		sendAimUpdate(true)
		sendFireRequest()
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

RunService.RenderStepped:Connect(function()
	sendAimUpdate(false)

	local crosshairX, crosshairY = getCrosshairViewportPoint()
	root.Position = UDim2.fromOffset(crosshairX, crosshairY)

	local showCrosshair = true
	local shopOpen = isShopOpen()

	if currentCharacter then
		local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health <= 0 then
				showCrosshair = false
			end
		end
	end

	UserInputService.MouseIconEnabled = true
	if mouse and mouse.Icon ~= DOT_CURSOR_ICON then
		mouse.Icon = DOT_CURSOR_ICON
	end

	root.Visible = showCrosshair and not shopOpen
end)
