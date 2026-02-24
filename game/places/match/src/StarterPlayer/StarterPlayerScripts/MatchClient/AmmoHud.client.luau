local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "AmmoHud"

local existingGui = playerGui:FindFirstChild(GUI_NAME)
if existingGui then
	existingGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.DisplayOrder = 35
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "AmmoContainer"
root.Size = UDim2.fromOffset(250, 106)
root.AnchorPoint = Vector2.new(1, 1)
root.Position = UDim2.new(1, -18, 1, -18)
root.BackgroundColor3 = Color3.fromRGB(18, 23, 34)
root.BackgroundTransparency = 0.12
root.BorderSizePixel = 0
root.Visible = false
root.Parent = gui

local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = UDim.new(0, 10)
rootCorner.Parent = root

local rootStroke = Instance.new("UIStroke")
rootStroke.Color = Color3.fromRGB(92, 110, 136)
rootStroke.Transparency = 0.2
rootStroke.Thickness = 1
rootStroke.Parent = root

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 35, 48)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 18, 26)),
})
gradient.Rotation = 90
gradient.Parent = root

local weaponNameLabel = Instance.new("TextLabel")
weaponNameLabel.Name = "WeaponName"
weaponNameLabel.Size = UDim2.new(1, -16, 0, 22)
weaponNameLabel.Position = UDim2.fromOffset(8, 6)
weaponNameLabel.BackgroundTransparency = 1
weaponNameLabel.Text = ""
weaponNameLabel.TextXAlignment = Enum.TextXAlignment.Right
weaponNameLabel.TextColor3 = Color3.fromRGB(206, 219, 242)
weaponNameLabel.Font = Enum.Font.GothamSemibold
weaponNameLabel.TextSize = 14
weaponNameLabel.Parent = root

local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "AmmoValue"
ammoLabel.Size = UDim2.new(1, -16, 0, 44)
ammoLabel.Position = UDim2.fromOffset(8, 28)
ammoLabel.BackgroundTransparency = 1
ammoLabel.Text = ""
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
ammoLabel.TextColor3 = Color3.fromRGB(245, 250, 255)
ammoLabel.Font = Enum.Font.GothamBlack
ammoLabel.TextSize = 36
ammoLabel.Parent = root

local detailsLabel = Instance.new("TextLabel")
detailsLabel.Name = "AmmoDetails"
detailsLabel.Size = UDim2.new(1, -16, 0, 18)
detailsLabel.Position = UDim2.fromOffset(8, 74)
detailsLabel.BackgroundTransparency = 1
detailsLabel.Text = ""
detailsLabel.TextXAlignment = Enum.TextXAlignment.Right
detailsLabel.TextColor3 = Color3.fromRGB(157, 176, 208)
detailsLabel.Font = Enum.Font.Gotham
detailsLabel.TextSize = 13
detailsLabel.Parent = root

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "AmmoStatus"
statusLabel.Size = UDim2.new(1, -16, 0, 16)
statusLabel.Position = UDim2.fromOffset(8, 90)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextColor3 = Color3.fromRGB(255, 206, 111)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 12
statusLabel.Visible = false
statusLabel.Parent = root

local currentCharacter = nil
local currentTool = nil
local characterConnections = {}
local toolConnections = {}

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function toWholeNumber(value, defaultValue)
	local numeric = tonumber(value)
	if numeric == nil then
		return defaultValue
	end
	return math.max(0, math.floor(numeric + 0.5))
end

local function findAliveHumanoid(character)
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function readAmmoSnapshot(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local currentAmmo = toWholeNumber(tool:GetAttribute("CurrentAmmo"), nil)
	local maxAmmo = toWholeNumber(tool:GetAttribute("MaxAmmo"), nil)
	if currentAmmo == nil or maxAmmo == nil or maxAmmo <= 0 then
		return nil
	end

	local reserveAmmo = toWholeNumber(tool:GetAttribute("ReserveAmmo"), 0)
	local totalAmmo = toWholeNumber(tool:GetAttribute("TotalAmmo"), currentAmmo + reserveAmmo)
	if totalAmmo < currentAmmo then
		totalAmmo = currentAmmo
	end

	return {
		weaponName = tostring(tool.Name or "Weapon"),
		currentAmmo = currentAmmo,
		maxAmmo = maxAmmo,
		reserveAmmo = reserveAmmo,
		totalAmmo = totalAmmo,
		isReloading = tool:GetAttribute("IsReloading") == true,
	}
end

local function refreshHud()
	if not currentCharacter or not currentTool then
		root.Visible = false
		return
	end
	if currentTool.Parent ~= currentCharacter then
		root.Visible = false
		return
	end
	if not findAliveHumanoid(currentCharacter) then
		root.Visible = false
		return
	end

	local snapshot = readAmmoSnapshot(currentTool)
	if not snapshot then
		root.Visible = false
		return
	end

	weaponNameLabel.Text = string.upper(snapshot.weaponName)
	ammoLabel.Text = string.format("%d / %d", snapshot.currentAmmo, snapshot.totalAmmo)
	detailsLabel.Text = string.format("MAG %d   RESERVE %d", snapshot.maxAmmo, snapshot.reserveAmmo)

	if snapshot.currentAmmo <= 0 and snapshot.reserveAmmo <= 0 then
		statusLabel.Text = "OUT OF AMMO"
		statusLabel.TextColor3 = Color3.fromRGB(255, 136, 136)
		statusLabel.Visible = true
	elseif snapshot.isReloading then
		statusLabel.Text = "RELOADING"
		statusLabel.TextColor3 = Color3.fromRGB(255, 206, 111)
		statusLabel.Visible = true
	else
		statusLabel.Visible = false
	end

	root.Visible = true
end

local function findEquippedTool(character)
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function bindTool(tool)
	disconnectAll(toolConnections)
	currentTool = tool
	if not currentTool then
		refreshHud()
		return
	end

	local watchedAttributes = {
		"CurrentAmmo",
		"MaxAmmo",
		"ReserveAmmo",
		"TotalAmmo",
		"IsReloading",
	}
	for _, attributeName in ipairs(watchedAttributes) do
		table.insert(toolConnections, currentTool:GetAttributeChangedSignal(attributeName):Connect(refreshHud))
	end

	table.insert(toolConnections, currentTool:GetPropertyChangedSignal("Name"):Connect(refreshHud))
	table.insert(toolConnections, currentTool.AncestryChanged:Connect(function()
		refreshHud()
	end))

	refreshHud()
end

local function bindCharacter(character)
	disconnectAll(characterConnections)
	bindTool(nil)
	currentCharacter = character

	if not currentCharacter then
		refreshHud()
		return
	end

	local equippedTool = findEquippedTool(currentCharacter)
	if equippedTool then
		bindTool(equippedTool)
	end

	local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(characterConnections, humanoid:GetPropertyChangedSignal("Health"):Connect(refreshHud))
		table.insert(characterConnections, humanoid.Died:Connect(refreshHud))
	end

	table.insert(characterConnections, currentCharacter.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
		refreshHud()
	end))

	table.insert(characterConnections, currentCharacter.ChildRemoved:Connect(function(child)
		if child == currentTool then
			bindTool(findEquippedTool(currentCharacter))
		end
		refreshHud()
	end))

	refreshHud()
end

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(bindCharacter)
player.CharacterRemoving:Connect(function(character)
	if character == currentCharacter then
		bindCharacter(nil)
	end
end)
