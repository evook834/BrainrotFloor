local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

export type View = {
	gui: ScreenGui,
	openButton: TextButton,
	panel: Frame,
	closeButton: TextButton,
	statusLabel: TextLabel,
	currentIcon: ImageLabel,
	currentInfo: TextLabel,
	listFrame: ScrollingFrame,
	bonusInfoMenu: Frame,
	bonusInfoCloseButton: TextButton,
	bonusInfoText: TextLabel,
	bonusInfoScroll: ScrollingFrame,
}

local function build(): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClassSelectUi"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenClassPanel"
	openButton.Size = UDim2.fromOffset(146, 40)
	openButton.Position = UDim2.new(0, 12, 0.5, 24)
	openButton.BackgroundColor3 = Color3.fromRGB(86, 118, 156)
	openButton.BorderSizePixel = 0
	openButton.Text = "Classes"
	openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	openButton.TextTransparency = 0
	openButton.Font = Enum.Font.GothamBold
	openButton.TextSize = 16
	openButton.Parent = gui

	local openButtonCorner = Instance.new("UICorner")
	openButtonCorner.CornerRadius = UDim.new(0, 10)
	openButtonCorner.Parent = openButton

	local openButtonStroke = Instance.new("UIStroke")
	openButtonStroke.Color = Color3.fromRGB(132, 162, 198)
	openButtonStroke.Transparency = 0.04
	openButtonStroke.Thickness = 1
	openButtonStroke.Parent = openButton

	local openButtonGradient = Instance.new("UIGradient")
	openButtonGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(118, 152, 194)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(66, 97, 132)),
	})
	openButtonGradient.Rotation = 90
	openButtonGradient.Parent = openButton

	local panel = Instance.new("Frame")
	panel.Name = "ClassPanel"
	panel.Size = UDim2.fromOffset(380, 500)
	panel.Position = UDim2.new(0, 176, 0.5, -250)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(78, 95, 120)
	panelStroke.Transparency = 0.14
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -62, 0, 34)
	title.Position = UDim2.fromOffset(14, 8)
	title.BackgroundTransparency = 1
	title.Text = "Class Selection"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(245, 248, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -24, 0, 22)
	subtitle.Position = UDim2.fromOffset(14, 40)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = ""
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Color3.fromRGB(168, 227, 188)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.Position = UDim2.new(1, -42, 0, 8)
	closeButton.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(240, 240, 245)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 18
	closeButton.Parent = panel

	local currentInfo = Instance.new("TextLabel")
	currentInfo.Name = "CurrentInfo"
	currentInfo.Size = UDim2.new(1, -118, 0, 86)
	currentInfo.Position = UDim2.fromOffset(100, 70)
	currentInfo.BackgroundColor3 = Color3.fromRGB(24, 29, 37)
	currentInfo.BackgroundTransparency = 0.12
	currentInfo.BorderSizePixel = 0
	currentInfo.Text = ""
	currentInfo.TextWrapped = true
	currentInfo.TextXAlignment = Enum.TextXAlignment.Left
	currentInfo.TextYAlignment = Enum.TextYAlignment.Top
	currentInfo.TextColor3 = Color3.fromRGB(224, 232, 242)
	currentInfo.Font = Enum.Font.GothamSemibold
	currentInfo.TextSize = 14
	currentInfo.Parent = panel

	local currentInfoCorner = Instance.new("UICorner")
	currentInfoCorner.CornerRadius = UDim.new(0, 8)
	currentInfoCorner.Parent = currentInfo

	local currentIcon = Instance.new("ImageLabel")
	currentIcon.Name = "CurrentIcon"
	currentIcon.Size = UDim2.fromOffset(76, 76)
	currentIcon.Position = UDim2.fromOffset(14, 75)
	currentIcon.BackgroundColor3 = Color3.fromRGB(24, 29, 37)
	currentIcon.BackgroundTransparency = 0.08
	currentIcon.BorderSizePixel = 0
	currentIcon.Image = ""
	currentIcon.ScaleType = Enum.ScaleType.Fit
	currentIcon.Parent = panel

	local currentIconCorner = Instance.new("UICorner")
	currentIconCorner.CornerRadius = UDim.new(0, 10)
	currentIconCorner.Parent = currentIcon

	local currentIconStroke = Instance.new("UIStroke")
	currentIconStroke.Color = Color3.fromRGB(76, 92, 116)
	currentIconStroke.Transparency = 0.18
	currentIconStroke.Thickness = 1
	currentIconStroke.Parent = currentIcon

	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "ClassList"
	listFrame.Size = UDim2.new(1, -24, 1, -234)
	listFrame.Position = UDim2.fromOffset(12, 166)
	listFrame.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
	listFrame.BackgroundTransparency = 0.15
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarImageColor3 = Color3.fromRGB(95, 115, 140)
	listFrame.ScrollBarThickness = 6
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.Parent = panel

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)
	listPadding.Parent = listFrame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -24, 0, 52)
	statusLabel.Position = UDim2.new(0, 12, 1, -58)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
	statusLabel.Font = Enum.Font.GothamSemibold
	statusLabel.TextSize = 14
	statusLabel.Parent = panel

	local bonusInfoMenu = Instance.new("Frame")
	bonusInfoMenu.Name = "BonusInfoMenu"
	bonusInfoMenu.Size = UDim2.fromOffset(228, 154)
	bonusInfoMenu.Position = UDim2.fromOffset(12, 170)
	bonusInfoMenu.BackgroundColor3 = Color3.fromRGB(20, 25, 32)
	bonusInfoMenu.BackgroundTransparency = 0.06
	bonusInfoMenu.BorderSizePixel = 0
	bonusInfoMenu.Visible = false
	bonusInfoMenu.ZIndex = 20
	bonusInfoMenu.Parent = panel

	local bonusInfoMenuCorner = Instance.new("UICorner")
	bonusInfoMenuCorner.CornerRadius = UDim.new(0, 8)
	bonusInfoMenuCorner.Parent = bonusInfoMenu

	local bonusInfoMenuStroke = Instance.new("UIStroke")
	bonusInfoMenuStroke.Color = Color3.fromRGB(90, 124, 160)
	bonusInfoMenuStroke.Transparency = 0.1
	bonusInfoMenuStroke.Thickness = 1
	bonusInfoMenuStroke.Parent = bonusInfoMenu

	local bonusInfoTitle = Instance.new("TextLabel")
	bonusInfoTitle.Name = "Title"
	bonusInfoTitle.Size = UDim2.new(1, -30, 0, 24)
	bonusInfoTitle.Position = UDim2.fromOffset(8, 6)
	bonusInfoTitle.BackgroundTransparency = 1
	bonusInfoTitle.Text = "Class Bonuses"
	bonusInfoTitle.TextXAlignment = Enum.TextXAlignment.Left
	bonusInfoTitle.TextYAlignment = Enum.TextYAlignment.Center
	bonusInfoTitle.TextColor3 = Color3.fromRGB(232, 238, 245)
	bonusInfoTitle.Font = Enum.Font.GothamBold
	bonusInfoTitle.TextSize = 13
	bonusInfoTitle.ZIndex = 21
	bonusInfoTitle.Parent = bonusInfoMenu

	local bonusInfoCloseButton = Instance.new("TextButton")
	bonusInfoCloseButton.Name = "Close"
	bonusInfoCloseButton.Size = UDim2.fromOffset(18, 18)
	bonusInfoCloseButton.Position = UDim2.new(1, -24, 0, 8)
	bonusInfoCloseButton.BackgroundColor3 = Color3.fromRGB(62, 67, 78)
	bonusInfoCloseButton.BorderSizePixel = 0
	bonusInfoCloseButton.Text = "X"
	bonusInfoCloseButton.TextColor3 = Color3.fromRGB(235, 238, 242)
	bonusInfoCloseButton.Font = Enum.Font.GothamBold
	bonusInfoCloseButton.TextSize = 11
	bonusInfoCloseButton.ZIndex = 21
	bonusInfoCloseButton.Parent = bonusInfoMenu

	local bonusInfoCloseCorner = Instance.new("UICorner")
	bonusInfoCloseCorner.CornerRadius = UDim.new(0, 5)
	bonusInfoCloseCorner.Parent = bonusInfoCloseButton

	local bonusInfoScroll = Instance.new("ScrollingFrame")
	bonusInfoScroll.Name = "Scroll"
	bonusInfoScroll.Size = UDim2.new(1, -16, 1, -38)
	bonusInfoScroll.Position = UDim2.fromOffset(8, 30)
	bonusInfoScroll.BackgroundTransparency = 1
	bonusInfoScroll.BorderSizePixel = 0
	bonusInfoScroll.CanvasSize = UDim2.new()
	bonusInfoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bonusInfoScroll.ScrollBarThickness = 5
	bonusInfoScroll.ScrollBarImageColor3 = Color3.fromRGB(112, 142, 172)
	bonusInfoScroll.ZIndex = 21
	bonusInfoScroll.Parent = bonusInfoMenu

	local bonusInfoText = Instance.new("TextLabel")
	bonusInfoText.Name = "Text"
	bonusInfoText.Size = UDim2.new(1, -4, 0, 0)
	bonusInfoText.Position = UDim2.fromOffset(0, 0)
	bonusInfoText.AutomaticSize = Enum.AutomaticSize.Y
	bonusInfoText.BackgroundTransparency = 1
	bonusInfoText.TextWrapped = true
	bonusInfoText.TextXAlignment = Enum.TextXAlignment.Left
	bonusInfoText.TextYAlignment = Enum.TextYAlignment.Top
	bonusInfoText.TextColor3 = Color3.fromRGB(208, 221, 236)
	bonusInfoText.Font = Enum.Font.Gotham
	bonusInfoText.TextSize = 12
	bonusInfoText.Text = ""
	bonusInfoText.ZIndex = 21
	bonusInfoText.Parent = bonusInfoScroll

	return {
		gui = gui,
		openButton = openButton,
		panel = panel,
		closeButton = closeButton,
		statusLabel = statusLabel,
		currentIcon = currentIcon,
		currentInfo = currentInfo,
		listFrame = listFrame,
		bonusInfoMenu = bonusInfoMenu,
		bonusInfoCloseButton = bonusInfoCloseButton,
		bonusInfoText = bonusInfoText,
		bonusInfoScroll = bonusInfoScroll,
	}
end

return {
	build = build,
}

