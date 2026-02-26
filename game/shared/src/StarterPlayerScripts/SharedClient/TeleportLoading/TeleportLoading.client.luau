local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local teleportLoadingRemote = remotesFolder:WaitForChild(Config.Remotes.TeleportLoading)

local currentGui = nil
local guiToken = 0

local hiddenScreenGuis = {}
local playerGuiChildAddedConnection = nil
local hudHidden = false

local function setCoreGuiHidden(hidden)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not hidden)
	end)

	pcall(function()
		StarterGui:SetCore("TopbarEnabled", not hidden)
	end)
end

local function hideOtherScreenGuis()
	if hudHidden then
		return
	end

	hudHidden = true

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name ~= "TeleportLoadingGui" then
			hiddenScreenGuis[child] = child.Enabled
			child.Enabled = false
		end
	end

	playerGuiChildAddedConnection = playerGui.ChildAdded:Connect(function(child)
		if not hudHidden then
			return
		end

		if child:IsA("ScreenGui") and child.Name ~= "TeleportLoadingGui" then
			hiddenScreenGuis[child] = child.Enabled
			child.Enabled = false
		end
	end)

	setCoreGuiHidden(true)
end

local function restoreOtherScreenGuis()
	if not hudHidden then
		return
	end

	hudHidden = false

	if playerGuiChildAddedConnection then
		playerGuiChildAddedConnection:Disconnect()
		playerGuiChildAddedConnection = nil
	end

	for gui, wasEnabled in pairs(hiddenScreenGuis) do
		if gui and gui.Parent == playerGui then
			gui.Enabled = wasEnabled
		end
		hiddenScreenGuis[gui] = nil
	end

	setCoreGuiHidden(false)
end

local function destroyGui()
	guiToken += 1

	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end

	restoreOtherScreenGuis()
end

local function createGui(titleText, messageText)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportLoadingGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10000

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	background.BackgroundTransparency = 0
	background.BorderSizePixel = 0
	background.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.46)
	title.Size = UDim2.fromOffset(800, 54)
	title.BackgroundTransparency = 1
	title.Text = titleText or "Loading"
	title.TextColor3 = Color3.fromRGB(245, 248, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 34
	title.Parent = background

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.54)
	message.Size = UDim2.fromOffset(900, 40)
	message.BackgroundTransparency = 1
	message.Text = messageText or "Teleporting..."
	message.TextColor3 = Color3.fromRGB(210, 220, 235)
	message.Font = Enum.Font.GothamSemibold
	message.TextSize = 22
	message.Parent = background

	return gui
end

local function showGui(titleText, messageText)
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end

	hideOtherScreenGuis()

	currentGui = createGui(titleText, messageText)
	currentGui.Parent = playerGui

	local teleportGui = createGui(titleText, messageText)
	TeleportService:SetTeleportGui(teleportGui)
end

local function showFailure(messageText)
	showGui("Teleport failed", messageText or "Please try again.")

	local myToken = guiToken
	task.delay(2.5, function()
		if myToken ~= guiToken then
			return
		end

		destroyGui()
	end)
end

local function attachArrivingGui(arrivingGui)
	if not arrivingGui or not arrivingGui:IsA("ScreenGui") then
		return
	end

	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end

	hideOtherScreenGuis()

	arrivingGui.Name = "TeleportLoadingGui"
	arrivingGui.ResetOnSpawn = false
	arrivingGui.IgnoreGuiInset = true
	arrivingGui.DisplayOrder = 10000
	arrivingGui.Parent = playerGui

	currentGui = arrivingGui

	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end

		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart", 10)

		task.wait(0.25)
		destroyGui()
	end)
end

teleportLoadingRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.action == "Start" then
		showGui(payload.title, payload.message)
	elseif payload.action == "Failed" then
		showFailure(payload.message)
	elseif payload.action == "Hide" then
		destroyGui()
	end
end)

local arrivingGui = TeleportService:GetArrivingTeleportGui()
if arrivingGui then
	attachArrivingGui(arrivingGui)
end

TeleportService.LocalPlayerArrivedFromTeleport:Connect(function(loadingGui)
	attachArrivingGui(loadingGui)
end)

TeleportService.TeleportInitFailed:Connect(function(failedPlayer, _, errorMessage)
	if failedPlayer ~= player then
		return
	end

	showFailure(errorMessage or "Teleport did not complete.")
end)