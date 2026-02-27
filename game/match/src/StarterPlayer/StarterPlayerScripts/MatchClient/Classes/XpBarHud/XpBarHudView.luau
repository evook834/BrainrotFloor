--[[
	XpBarHudView — Builds the Class XP bar HUD UI tree (level, perk, bonus, XP bar).
	No remotes or game logic; returns refs and helpers for the controller to update and wire.
]]

local TweenService = game:GetService("TweenService")

local GUI_NAME = "ClassXpBarHud"
local DISPLAY_ORDER = 25

export type ViewRefs = {
	gui: ScreenGui,
	container: Frame,
	levelLabel: TextLabel,
	perkLabel: TextLabel,
	bonusLabel: TextLabel,
	xpNumberLabel: TextLabel,
	barBackground: Frame,
	barFill: Frame,
	barPercentLabel: TextLabel,
	containerScale: UIScale,
	containerStroke: UIStroke,
}

local BASE_CONTAINER_BG_TRANSPARENCY = 0.1
local BASE_STROKE_COLOR = Color3.fromRGB(70, 94, 126)
local BASE_STROKE_TRANSPARENCY = 0.18
local BASE_STROKE_THICKNESS = 1
local BASE_BAR_FILL_COLOR = Color3.fromRGB(78, 176, 255)
local PULSE_STROKE_COLOR = Color3.fromRGB(132, 206, 255)
local PULSE_BAR_FILL_COLOR = Color3.fromRGB(140, 221, 255)
local PULSE_SCALE_BOOST = 1.03
local PULSE_REVERT_DELAY = 0.14

local function build(parent: PlayerGui): ViewRefs
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Parent = parent

	local container = Instance.new("Frame")
	container.Name = "XpContainer"
	container.Size = UDim2.new(0.62, 0, 0, 76)
	container.Position = UDim2.new(0.5, 0, 1, -84)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	container.BackgroundTransparency = BASE_CONTAINER_BG_TRANSPARENCY
	container.BorderSizePixel = 0
	container.Parent = gui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 10)
	containerCorner.Parent = container

	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = BASE_STROKE_COLOR
	containerStroke.Transparency = BASE_STROKE_TRANSPARENCY
	containerStroke.Thickness = BASE_STROKE_THICKNESS
	containerStroke.Parent = container

	local containerSizeConstraint = Instance.new("UISizeConstraint")
	containerSizeConstraint.MinSize = Vector2.new(320, 68)
	containerSizeConstraint.MaxSize = Vector2.new(760, 86)
	containerSizeConstraint.Parent = container

	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LevelPanel"
	leftPanel.Size = UDim2.new(0, 176, 1, 0)
	leftPanel.BackgroundTransparency = 1
	leftPanel.Parent = container

	local leftPadding = Instance.new("UIPadding")
	leftPadding.PaddingTop = UDim.new(0, 8)
	leftPadding.PaddingBottom = UDim.new(0, 8)
	leftPadding.PaddingLeft = UDim.new(0, 12)
	leftPadding.PaddingRight = UDim.new(0, 8)
	leftPadding.Parent = leftPanel

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	leftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	leftLayout.Padding = UDim.new(0, 2)
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Parent = leftPanel

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.LayoutOrder = 1
	levelLabel.Size = UDim2.new(1, 0, 0, 30)
	levelLabel.BackgroundTransparency = 1
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.TextColor3 = Color3.fromRGB(244, 248, 255)
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = 23
	levelLabel.Text = "Lv 1"
	levelLabel.Parent = leftPanel

	local perkLabel = Instance.new("TextLabel")
	perkLabel.Name = "PerkLabel"
	perkLabel.LayoutOrder = 2
	perkLabel.Size = UDim2.new(1, 0, 0, 18)
	perkLabel.BackgroundTransparency = 1
	perkLabel.TextXAlignment = Enum.TextXAlignment.Left
	perkLabel.TextColor3 = Color3.fromRGB(182, 213, 241)
	perkLabel.Font = Enum.Font.GothamSemibold
	perkLabel.TextSize = 13
	perkLabel.Text = "Perk: Unknown"
	perkLabel.Parent = leftPanel

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.LayoutOrder = 3
	bonusLabel.Size = UDim2.new(1, 0, 0, 16)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
	bonusLabel.TextColor3 = Color3.fromRGB(150, 199, 240)
	bonusLabel.Font = Enum.Font.Gotham
	bonusLabel.TextSize = 12
	bonusLabel.Text = "Active: None"
	bonusLabel.Parent = leftPanel

	local xpPanel = Instance.new("Frame")
	xpPanel.Name = "XpPanel"
	xpPanel.Size = UDim2.new(1, -188, 1, 0)
	xpPanel.Position = UDim2.new(0, 188, 0, 0)
	xpPanel.BackgroundTransparency = 1
	xpPanel.Parent = container

	local xpPadding = Instance.new("UIPadding")
	xpPadding.PaddingTop = UDim.new(0, 10)
	xpPadding.PaddingBottom = UDim.new(0, 10)
	xpPadding.PaddingLeft = UDim.new(0, 4)
	xpPadding.PaddingRight = UDim.new(0, 12)
	xpPadding.Parent = xpPanel

	local xpLayout = Instance.new("UIListLayout")
	xpLayout.FillDirection = Enum.FillDirection.Vertical
	xpLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	xpLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	xpLayout.Padding = UDim.new(0, 6)
	xpLayout.SortOrder = Enum.SortOrder.LayoutOrder
	xpLayout.Parent = xpPanel

	local xpNumberLabel = Instance.new("TextLabel")
	xpNumberLabel.Name = "XpNumberLabel"
	xpNumberLabel.LayoutOrder = 1
	xpNumberLabel.Size = UDim2.new(1, 0, 0, 18)
	xpNumberLabel.BackgroundTransparency = 1
	xpNumberLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpNumberLabel.TextColor3 = Color3.fromRGB(231, 240, 250)
	xpNumberLabel.Font = Enum.Font.GothamSemibold
	xpNumberLabel.TextSize = 14
	xpNumberLabel.Text = "XP 0 / 100"
	xpNumberLabel.Parent = xpPanel

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.LayoutOrder = 2
	barBackground.Size = UDim2.new(1, 0, 0, 20)
	barBackground.BackgroundColor3 = Color3.fromRGB(32, 42, 55)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = xpPanel

	local barBackgroundCorner = Instance.new("UICorner")
	barBackgroundCorner.CornerRadius = UDim.new(0, 6)
	barBackgroundCorner.Parent = barBackground

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = BASE_BAR_FILL_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 6)
	barFillCorner.Parent = barFill

	local barPercentLabel = Instance.new("TextLabel")
	barPercentLabel.Name = "BarPercent"
	barPercentLabel.Size = UDim2.fromScale(1, 1)
	barPercentLabel.BackgroundTransparency = 1
	barPercentLabel.TextColor3 = Color3.fromRGB(10, 16, 24)
	barPercentLabel.Font = Enum.Font.GothamBold
	barPercentLabel.TextSize = 12
	barPercentLabel.Text = "0%"
	barPercentLabel.Parent = barBackground

	local containerScale = Instance.new("UIScale")
	containerScale.Scale = 1
	containerScale.Parent = container

	return {
		gui = gui,
		container = container,
		levelLabel = levelLabel,
		perkLabel = perkLabel,
		bonusLabel = bonusLabel,
		xpNumberLabel = xpNumberLabel,
		barBackground = barBackground,
		barFill = barFill,
		barPercentLabel = barPercentLabel,
		containerScale = containerScale,
		containerStroke = containerStroke,
	}
end

function setHudDisplay(
	refs: ViewRefs,
	levelText: string,
	perkText: string,
	activeBonusText: string,
	xpText: string,
	progress: number
)
	refs.levelLabel.Text = levelText
	refs.perkLabel.Text = perkText
	refs.bonusLabel.Text = activeBonusText
	refs.xpNumberLabel.Text = xpText
	refs.barFill.Size = UDim2.fromScale(progress, 1)
	refs.barPercentLabel.Text = string.format("%d%%", math.floor((progress * 100) + 0.5))
end

local levelUpPulseToken = 0
function playLevelUpPulse(refs: ViewRefs, hudScaleMultiplier: number)
	levelUpPulseToken += 1
	local activeToken = levelUpPulseToken

	TweenService:Create(
		refs.containerScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = hudScaleMultiplier * 1.03 }
	):Play()
	TweenService:Create(
		refs.container,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.02 }
	):Play()
	TweenService:Create(
		refs.containerStroke,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Color = PULSE_STROKE_COLOR,
			Transparency = 0.03,
			Thickness = 2,
		}
	):Play()
	TweenService:Create(
		refs.barFill,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = PULSE_BAR_FILL_COLOR }
	):Play()

	task.delay(PULSE_REVERT_DELAY, function()
		if activeToken ~= levelUpPulseToken then
			return
		end
		TweenService:Create(
			refs.containerScale,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = hudScaleMultiplier }
		):Play()
		TweenService:Create(
			refs.container,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = BASE_CONTAINER_BG_TRANSPARENCY }
		):Play()
		TweenService:Create(
			refs.containerStroke,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Color = BASE_STROKE_COLOR,
				Transparency = BASE_STROKE_TRANSPARENCY,
				Thickness = BASE_STROKE_THICKNESS,
			}
		):Play()
		TweenService:Create(
			refs.barFill,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = BASE_BAR_FILL_COLOR }
		):Play()
	end)
end

return {
	build = build,
	setHudDisplay = setHudDisplay,
	playLevelUpPulse = playLevelUpPulse,
}
