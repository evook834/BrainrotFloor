local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TeleportLoading = {}

local GUI_NAME = "TeleportLoadingGui"
local LOBBY_BUTTONS_FOLDER_NAME = "DifficultyButtons"
local FAILURE_HIDE_DELAY = 2.5

local initialized = false
local currentGui = nil
local animationToken = 0
local timeoutToken = 0

local heldLobbyPrompt = nil
local heldLobbyPromptTriggered = false

local difficultyLookup = {}
for difficultyName, _ in pairs((Config.Difficulty and Config.Difficulty.Settings) or {}) do
	difficultyLookup[difficultyName] = true
end

local function createGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10_000

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(5, 7, 10)
	backdrop.BackgroundTransparency = 0.12
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(520, 180)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(90, 112, 140)
	panelStroke.Transparency = 0.12
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 22)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "Loading"
	title.TextColor3 = Color3.fromRGB(245, 248, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.LayoutOrder = 2
	subtitle.Size = UDim2.new(1, 0, 0, 52)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Teleporting..."
	subtitle.TextWrapped = true
	subtitle.TextColor3 = Color3.fromRGB(205, 216, 232)
	subtitle.Font = Enum.Font.GothamSemibold
	subtitle.TextSize = 18
	subtitle.Parent = panel

	local dots = Instance.new("TextLabel")
	dots.Name = "Dots"
	dots.LayoutOrder = 3
	dots.Size = UDim2.new(1, 0, 0, 28)
	dots.BackgroundTransparency = 1
	dots.Text = "."
	dots.TextColor3 = Color3.fromRGB(150, 190, 245)
	dots.Font = Enum.Font.GothamBold
	dots.TextSize = 24
	dots.Parent = panel

	return gui
end

local function getLabel(gui, name)
	if not gui then
		return nil
	end

	local backdrop = gui:FindFirstChild("Backdrop")
	local panel = backdrop and backdrop:FindFirstChild("Panel")

	if not panel then
		return nil
	end

	return panel:FindFirstChild(name)
end

local function setText(gui, titleText, subtitleText)
	local title = getLabel(gui, "Title")
	local subtitle = getLabel(gui, "Subtitle")

	if title and title:IsA("TextLabel") then
		title.Text = titleText or "Loading"
	end

	if subtitle and subtitle:IsA("TextLabel") then
		subtitle.Text = subtitleText or "Teleporting..."
	end
end

local function startDots(gui)
	animationToken += 1
	local myToken = animationToken

	task.spawn(function()
		local dots = getLabel(gui, "Dots")
		local states = {".", "..", "..."}
		local index = 1

		while animationToken == myToken do
			if not gui or gui.Parent == nil then
				break
			end

			if dots and dots:IsA("TextLabel") then
				dots.Text = states[index]
			end

			index += 1
			if index > #states then
				index = 1
			end

			task.wait(0.35)
		end
	end)
end

local function destroyCurrentGui()
	animationToken += 1
	timeoutToken += 1

	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
end

local function ensureCurrentGui()
	if currentGui and currentGui.Parent == playerGui then
		return currentGui
	end

	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		currentGui = existing
		return currentGui
	end

	currentGui = createGui()
	currentGui.Parent = playerGui
	return currentGui
end

local function scheduleHideAfterArrival()
	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end

		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart", 10)

		task.wait(0.35)
		TeleportLoading.hide()
	end)
end

local function attachArrivingGui(arrivingGui)
	if not arrivingGui or not arrivingGui:IsA("ScreenGui") then
		return
	end

	destroyCurrentGui()

	arrivingGui.Name = GUI_NAME
	arrivingGui.ResetOnSpawn = false
	arrivingGui.IgnoreGuiInset = true
	arrivingGui.DisplayOrder = 10_000
	arrivingGui.Parent = playerGui

	currentGui = arrivingGui
	startDots(currentGui)
	scheduleHideAfterArrival()
end

local function getLobbyPromptDifficulty(prompt)
	if type(prompt.ObjectText) == "string" and prompt.ObjectText ~= "" then
		return prompt.ObjectText
	end

	local parent = prompt.Parent
	if parent and parent:IsA("Instance") then
		local attr = parent:GetAttribute("Difficulty")
		if type(attr) == "string" and attr ~= "" then
			return attr
		end
	end

	return "match"
end

local function isLobbyTeleportPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end

	local buttonsFolder = workspace:FindFirstChild(LOBBY_BUTTONS_FOLDER_NAME)
	if buttonsFolder and prompt:IsDescendantOf(buttonsFolder) then
		return true
	end

	return difficultyLookup[prompt.ObjectText] == true
end

function TeleportLoading.show(options)
	options = options or {}

	local title = options.title or "Loading"
	local subtitle = options.subtitle or "Teleporting..."
	local timeoutSeconds = tonumber(options.timeoutSeconds)
	local timeoutMessage = options.timeoutMessage or "Teleport did not complete. Please try again."

	local gui = ensureCurrentGui()
	setText(gui, title, subtitle)
	startDots(gui)

	local teleportGui = createGui()
	setText(teleportGui, title, subtitle)
	TeleportService:SetTeleportGui(teleportGui)

	timeoutToken += 1
	local myTimeoutToken = timeoutToken

	if timeoutSeconds and timeoutSeconds > 0 then
		task.delay(timeoutSeconds, function()
			if timeoutToken ~= myTimeoutToken then
				return
			end

			TeleportLoading.showFailure(timeoutMessage)
		end)
	end
end

function TeleportLoading.showFailure(message)
	local gui = ensureCurrentGui()
	setText(gui, "Teleport failed", message or "Please try again.")
	startDots(gui)

	timeoutToken += 1
	local myTimeoutToken = timeoutToken

	task.delay(FAILURE_HIDE_DELAY, function()
		if timeoutToken ~= myTimeoutToken then
			return
		end

		TeleportLoading.hide()
	end)
end

function TeleportLoading.hide()
	destroyCurrentGui()
end

function TeleportLoading.init()
	if initialized then
		return
	end

	initialized = true

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

		local message = "Please try again."
		if type(errorMessage) == "string" and errorMessage ~= "" then
			message = errorMessage
		end

		TeleportLoading.showFailure(message)
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, playerWhoTriggered)
		if playerWhoTriggered ~= player then
			return
		end
		if not isLobbyTeleportPrompt(prompt) then
			return
		end

		heldLobbyPrompt = prompt
		heldLobbyPromptTriggered = false

		TeleportLoading.show({
			title = "Joining match",
			subtitle = "Preparing teleport...",
			timeoutSeconds = 20,
			timeoutMessage = "Could not join a match. Please try again.",
		})
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWhoTriggered)
		if playerWhoTriggered ~= player then
			return
		end
		if not isLobbyTeleportPrompt(prompt) then
			return
		end

		heldLobbyPrompt = prompt
		heldLobbyPromptTriggered = true

		local difficulty = getLobbyPromptDifficulty(prompt)

		TeleportLoading.show({
			title = "Joining match",
			subtitle = string.format("Finding a %s server...", difficulty),
			timeoutSeconds = 20,
			timeoutMessage = "Could not join a match. Please try again.",
		})
	end)

	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, playerWhoTriggered)
		if playerWhoTriggered ~= player then
			return
		end
		if heldLobbyPrompt ~= prompt then
			return
		end

		local wasTriggered = heldLobbyPromptTriggered
		heldLobbyPrompt = nil
		heldLobbyPromptTriggered = false

		if wasTriggered then
			return
		end

		TeleportLoading.hide()
	end)
end

return TeleportLoading