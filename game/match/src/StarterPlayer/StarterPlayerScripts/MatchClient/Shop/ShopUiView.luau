local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DEFAULT_STATUS_COLOR = Color3.fromRGB(225, 235, 245)
local DEFAULT_SUBTITLE_COLOR = Color3.fromRGB(175, 190, 205)

export type View = {
	gui: ScreenGui,
	panel: Frame,
	closeButton: TextButton,
	listFrame: ScrollingFrame,
	refillAllButton: TextButton,
	statusLabel: TextLabel,
	setStatus: (text: string?, color: Color3?) -> (),
	setSubtitle: (text: string, color: Color3?) -> (),
	clearRows: () -> (),
}

local function build(): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "WeaponShopUi"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.Size = UDim2.fromOffset(520, 430)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(75, 95, 120)
	panelStroke.Transparency = 0.18
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -54, 0, 36)
	title.Position = UDim2.fromOffset(18, 10)
	title.BackgroundTransparency = 1
	title.Text = "Weapon Trader"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(245, 248, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -24, 0, 22)
	subtitle.Position = UDim2.fromOffset(18, 46)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Buy only between waves"
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = DEFAULT_SUBTITLE_COLOR
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.Position = UDim2.new(1, -42, 0, 10)
	closeButton.BackgroundColor3 = Color3.fromRGB(52, 56, 70)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(240, 240, 245)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 18
	closeButton.Parent = panel

	local closeButtonCorner = Instance.new("UICorner")
	closeButtonCorner.CornerRadius = UDim.new(0, 8)
	closeButtonCorner.Parent = closeButton

	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "ItemList"
	listFrame.Size = UDim2.new(1, -24, 1, -166)
	listFrame.Position = UDim2.fromOffset(12, 76)
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

	local refillAllButton = Instance.new("TextButton")
	refillAllButton.Name = "RefillAllButton"
	refillAllButton.Size = UDim2.fromOffset(214, 34)
	refillAllButton.Position = UDim2.new(1, -226, 1, -76)
	refillAllButton.BackgroundColor3 = Color3.fromRGB(62, 64, 72)
	refillAllButton.BorderSizePixel = 0
	refillAllButton.AutoButtonColor = false
	refillAllButton.TextColor3 = Color3.fromRGB(240, 245, 240)
	refillAllButton.Font = Enum.Font.GothamBold
	refillAllButton.TextSize = 13
	refillAllButton.Text = "Refill All Owned"
	refillAllButton.Parent = panel

	local refillAllButtonCorner = Instance.new("UICorner")
	refillAllButtonCorner.CornerRadius = UDim.new(0, 8)
	refillAllButtonCorner.Parent = refillAllButton

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -24, 0, 28)
	statusLabel.Position = UDim2.new(0, 12, 1, -34)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ""
	statusLabel.TextColor3 = DEFAULT_STATUS_COLOR
	statusLabel.Font = Enum.Font.GothamSemibold
	statusLabel.TextSize = 14
	statusLabel.Parent = panel

	local function setStatus(text: string?, color: Color3?)
		statusLabel.Text = text or ""
		if color then
			statusLabel.TextColor3 = color
		else
			statusLabel.TextColor3 = DEFAULT_STATUS_COLOR
		end
	end

	local function setSubtitle(text: string, color: Color3?)
		subtitle.Text = text
		if color then
			subtitle.TextColor3 = color
		else
			subtitle.TextColor3 = DEFAULT_SUBTITLE_COLOR
		end
	end

	local function clearRows()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	return {
		gui = gui,
		panel = panel,
		closeButton = closeButton,
		listFrame = listFrame,
		refillAllButton = refillAllButton,
		statusLabel = statusLabel,
		setStatus = setStatus,
		setSubtitle = setSubtitle,
		clearRows = clearRows,
	}
end

return {
	build = build,
}
