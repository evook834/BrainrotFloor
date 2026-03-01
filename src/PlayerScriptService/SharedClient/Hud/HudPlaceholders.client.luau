local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudLayoutConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("HudLayoutConfig"))

local HUD_MOVE_MODE_ATTRIBUTE = HudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE

local function applyRoundedCorners(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function createOrReplaceGui(guiName: string, displayOrder: number): ScreenGui
	local existing = playerGui:FindFirstChild(guiName)
	-- In match, WaveHud creates BrainrotHud with GameOverOverlay; do not replace it
	if guiName == "BrainrotHud" and existing and existing:FindFirstChild("GameOverOverlay") then
		return existing
	end
	-- In match, XpBarHud creates the real ClassXpBarHud (XpContainer has LevelPanel); do not replace it
	if guiName == "ClassXpBarHud" and existing then
		local xpContainer = existing:FindFirstChild("XpContainer")
		if xpContainer and xpContainer:FindFirstChild("LevelPanel") then
			return existing
		end
	end
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.Parent = playerGui
	return gui
end

local classXpGui = createOrReplaceGui("ClassXpBarHud", 25)
local classXpGuiIsPlaceholder = not (classXpGui:FindFirstChild("XpContainer") and classXpGui.XpContainer:FindFirstChild("LevelPanel"))
local brainrotHudGui = createOrReplaceGui("BrainrotHud", 20)
local brainrotHudIsPlaceholder = not brainrotHudGui:FindFirstChild("GameOverOverlay")

local nextWaveTimer = nil
if brainrotHudIsPlaceholder then
	nextWaveTimer = Instance.new("TextLabel")
	nextWaveTimer.Name = "NextWaveTimer"
	nextWaveTimer.Size = UDim2.fromOffset(360, 46)
	nextWaveTimer.Position = UDim2.fromScale(0.5, 0.03)
	nextWaveTimer.AnchorPoint = Vector2.new(0.5, 0)
	nextWaveTimer.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	nextWaveTimer.BackgroundTransparency = 0.18
	nextWaveTimer.BorderSizePixel = 0
	nextWaveTimer.TextColor3 = Color3.fromRGB(245, 248, 255)
	nextWaveTimer.Font = Enum.Font.GothamBold
	nextWaveTimer.TextSize = 20
	nextWaveTimer.Text = "NEXT WAVE: 00:15"
	nextWaveTimer.Visible = false
	nextWaveTimer.Parent = brainrotHudGui
	applyRoundedCorners(nextWaveTimer, 10)

	local nextWaveStroke = Instance.new("UIStroke")
	nextWaveStroke.Color = Color3.fromRGB(92, 112, 128)
	nextWaveStroke.Transparency = 0.15
	nextWaveStroke.Thickness = 1
	nextWaveStroke.Parent = nextWaveTimer
end

local xpContainer = nil
if classXpGuiIsPlaceholder then
	xpContainer = Instance.new("Frame")
	xpContainer.Name = "XpContainer"
	xpContainer.Size = UDim2.new(0.62, 0, 0, 76)
	xpContainer.Position = UDim2.new(0.5, 0, 1, -84)
	xpContainer.AnchorPoint = Vector2.new(0.5, 1)
	xpContainer.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	xpContainer.BackgroundTransparency = 0.1
	xpContainer.BorderSizePixel = 0
	xpContainer.Visible = false
	xpContainer.Parent = classXpGui
	applyRoundedCorners(xpContainer, 10)

	local xpSizeConstraint = Instance.new("UISizeConstraint")
	xpSizeConstraint.MinSize = Vector2.new(320, 68)
	xpSizeConstraint.MaxSize = Vector2.new(760, 86)
	xpSizeConstraint.Parent = xpContainer

	local xpStroke = Instance.new("UIStroke")
	xpStroke.Color = Color3.fromRGB(70, 94, 126)
	xpStroke.Transparency = 0.18
	xpStroke.Thickness = 1
	xpStroke.Parent = xpContainer

	local xpScale = Instance.new("UIScale")
	xpScale.Scale = 1
	xpScale.Parent = xpContainer

	local function refreshXpScale()
		local attributeScale = xpContainer:GetAttribute("HudScaleMultiplier")
		if type(attributeScale) == "number" then
			xpScale.Scale = math.clamp(attributeScale, 0.6, 1.45)
		else
			xpScale.Scale = 1
		end
	end

	xpContainer:GetAttributeChangedSignal("HudScaleMultiplier"):Connect(refreshXpScale)
	refreshXpScale()

	local xpTitle = Instance.new("TextLabel")
	xpTitle.Name = "Title"
	xpTitle.Size = UDim2.new(1, -18, 0, 24)
	xpTitle.Position = UDim2.fromOffset(10, 10)
	xpTitle.BackgroundTransparency = 1
	xpTitle.Text = "LV 1  |  HUD PREVIEW"
	xpTitle.TextXAlignment = Enum.TextXAlignment.Left
	xpTitle.TextColor3 = Color3.fromRGB(240, 246, 255)
	xpTitle.Font = Enum.Font.GothamBold
	xpTitle.TextSize = 16
	xpTitle.Parent = xpContainer

	local xpSubTitle = Instance.new("TextLabel")
	xpSubTitle.Name = "SubTitle"
	xpSubTitle.Size = UDim2.new(1, -18, 0, 18)
	xpSubTitle.Position = UDim2.fromOffset(10, 34)
	xpSubTitle.BackgroundTransparency = 1
	xpSubTitle.Text = "XP 0 / 100"
	xpSubTitle.TextXAlignment = Enum.TextXAlignment.Left
	xpSubTitle.TextColor3 = Color3.fromRGB(182, 213, 241)
	xpSubTitle.Font = Enum.Font.GothamSemibold
	xpSubTitle.TextSize = 13
	xpSubTitle.Parent = xpContainer

	local xpBarBackground = Instance.new("Frame")
	xpBarBackground.Name = "BarBackground"
	xpBarBackground.Size = UDim2.new(1, -20, 0, 14)
	xpBarBackground.Position = UDim2.fromOffset(10, 54)
	xpBarBackground.BackgroundColor3 = Color3.fromRGB(32, 42, 55)
	xpBarBackground.BorderSizePixel = 0
	xpBarBackground.Parent = xpContainer
	applyRoundedCorners(xpBarBackground, 6)

	local xpBarFill = Instance.new("Frame")
	xpBarFill.Name = "BarFill"
	xpBarFill.Size = UDim2.fromScale(0.4, 1)
	xpBarFill.BackgroundColor3 = Color3.fromRGB(78, 176, 255)
	xpBarFill.BorderSizePixel = 0
	xpBarFill.Parent = xpBarBackground
	applyRoundedCorners(xpBarFill, 6)
end

local function setPreviewVisible(isVisible: boolean?)
	local visible = isVisible == true
	if nextWaveTimer then
		nextWaveTimer.Visible = visible
	end
	if xpContainer then
		xpContainer.Visible = visible
	end
end

local function refreshPreviewVisibility()
	setPreviewVisible(playerGui:GetAttribute(HUD_MOVE_MODE_ATTRIBUTE) == true)
end

playerGui:GetAttributeChangedSignal(HUD_MOVE_MODE_ATTRIBUTE):Connect(refreshPreviewVisibility)
refreshPreviewVisibility()

