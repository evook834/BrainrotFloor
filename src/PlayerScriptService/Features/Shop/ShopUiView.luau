local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ShopUiConstants = require(script.Parent:WaitForChild("ShopUiConstants"))
local ShopUiMessages = require(script.Parent:WaitForChild("ShopUiMessages"))

export type WeaponRowRefs = {
	row: Frame,
	infoLabel: TextLabel,
	buyButton: TextButton,
}

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
	buildWeaponRow: (listFrame: ScrollingFrame, index: number) -> WeaponRowRefs,
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
	panel.BackgroundColor3 = ShopUiConstants.PanelBackground
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = ShopUiConstants.PanelStroke
	panelStroke.Transparency = 0.18
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -54, 0, 36)
	title.Position = UDim2.fromOffset(18, 10)
	title.BackgroundTransparency = 1
	title.Text = ShopUiMessages.Title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = ShopUiConstants.TitleColor
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -24, 0, 22)
	subtitle.Position = UDim2.fromOffset(18, 46)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = ShopUiMessages.SubtitleInitial
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = ShopUiConstants.DefaultSubtitleColor
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 14
	subtitle.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.Position = UDim2.new(1, -42, 0, 10)
	closeButton.BackgroundColor3 = ShopUiConstants.CloseButtonBackground
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = ShopUiConstants.CloseButtonText
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
	listFrame.BackgroundColor3 = ShopUiConstants.ListBackground
	listFrame.BackgroundTransparency = 0.15
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarImageColor3 = ShopUiConstants.ListScrollBar
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
	refillAllButton.BackgroundColor3 = ShopUiConstants.RefillAllButtonDefault
	refillAllButton.BorderSizePixel = 0
	refillAllButton.AutoButtonColor = false
	refillAllButton.TextColor3 = ShopUiConstants.ButtonText
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
	statusLabel.TextColor3 = ShopUiConstants.DefaultStatusColor
	statusLabel.Font = Enum.Font.GothamSemibold
	statusLabel.TextSize = 14
	statusLabel.Parent = panel

	local function setStatus(text: string?, color: Color3?)
		statusLabel.Text = text or ""
		if color then
			statusLabel.TextColor3 = color
		else
			statusLabel.TextColor3 = ShopUiConstants.DefaultStatusColor
		end
	end

	local function setSubtitle(text: string, color: Color3?)
		subtitle.Text = text
		if color then
			subtitle.TextColor3 = color
		else
			subtitle.TextColor3 = ShopUiConstants.DefaultSubtitleColor
		end
	end

	local function clearRows()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function buildWeaponRow(parentListFrame: ScrollingFrame, index: number): WeaponRowRefs
		local row = Instance.new("Frame")
		row.Name = "WeaponRow_" .. tostring(index)
		row.Size = UDim2.new(1, -4, 0, 64)
		row.BackgroundColor3 = ShopUiConstants.RowBackground
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = parentListFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.Size = UDim2.new(1, -146, 1, 0)
		info.Position = UDim2.fromOffset(10, 0)
		info.BackgroundTransparency = 1
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Center
		info.TextWrapped = true
		info.Font = Enum.Font.GothamSemibold
		info.TextSize = 14
		info.TextColor3 = ShopUiConstants.InfoText
		info.Parent = row

		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.fromOffset(118, 40)
		buyButton.Position = UDim2.new(1, -126, 0.5, -20)
		buyButton.BackgroundColor3 = ShopUiConstants.ButtonEnabled
		buyButton.BorderSizePixel = 0
		buyButton.TextColor3 = ShopUiConstants.ButtonText
		buyButton.Font = Enum.Font.GothamBold
		buyButton.TextSize = 14
		buyButton.Text = "Buy"
		buyButton.Parent = row

		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0, 8)
		buyCorner.Parent = buyButton

		return {
			row = row,
			infoLabel = info,
			buyButton = buyButton,
		}
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
		buildWeaponRow = buildWeaponRow,
	}
end

return {
	build = build,
}
