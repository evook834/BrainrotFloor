local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

export type View = {
	gui: ScreenGui,
	scrim: Frame,
	panel: Frame,
	titleLabel: TextLabel,
	subtitleLabel: TextLabel,
	closeButton: TextButton,
	refreshButton: TextButton,

	requestsCountLabel: TextLabel,
	requestsList: ScrollingFrame,

	nearbyCountLabel: TextLabel,
	nearbyList: ScrollingFrame,

	friendsCountLabel: TextLabel,
	friendsList: ScrollingFrame,

	detailTitle: TextLabel,
	detailStatus: TextLabel,
	detailMeta: TextLabel,
	messageStatusLabel: TextLabel,

	addFriendButton: TextButton,
	acceptButton: TextButton,
	declineButton: TextButton,

	messagesList: ScrollingFrame,
	messageBox: TextBox,
	sendButton: TextButton,
}

local GUI_NAME = "FriendSystemUi"

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function stroke(instance: GuiObject, color: Color3, transparency: number, thickness: number)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = color
	uiStroke.Transparency = transparency
	uiStroke.Thickness = thickness
	uiStroke.Parent = instance
end

local function addPadding(parent: Instance, padding: number)
	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingLeft = UDim.new(0, padding)
	uiPadding.PaddingRight = UDim.new(0, padding)
	uiPadding.PaddingTop = UDim.new(0, padding)
	uiPadding.PaddingBottom = UDim.new(0, padding)
	uiPadding.Parent = parent
end

local function addListLayout(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

local function makeSection(parent: Instance, title: string, size: UDim2, position: UDim2)
	local section = Instance.new("Frame")
	section.Name = title:gsub("%s+", "") .. "Section"
	section.Size = size
	section.Position = position
	section.BackgroundColor3 = Color3.fromRGB(19, 28, 39)
	section.BorderSizePixel = 0
	section.Parent = parent
	round(section, 12)
	stroke(section, Color3.fromRGB(75, 103, 132), 0.35, 1)

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, -24, 0, 26)
	label.Position = UDim2.fromOffset(12, 10)
	label.BackgroundTransparency = 1
	label.Text = title
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(238, 246, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Parent = section

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.fromOffset(64, 24)
	countLabel.Position = UDim2.new(1, -76, 0, 11)
	countLabel.BackgroundColor3 = Color3.fromRGB(35, 50, 67)
	countLabel.BorderSizePixel = 0
	countLabel.Text = "0"
	countLabel.TextColor3 = Color3.fromRGB(183, 223, 241)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 13
	countLabel.Parent = section
	round(countLabel, 10)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -16, 1, -54)
	list.Position = UDim2.fromOffset(8, 42)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(73, 116, 146)
	list.Parent = section
	addPadding(list, 2)
	addListLayout(list, 8)

	return section, countLabel, list
end

local function build(): View
	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 85
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(4, 8, 14)
	scrim.BackgroundTransparency = 0.28
	scrim.BorderSizePixel = 0
	scrim.Visible = false
	scrim.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(960, 600)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(11, 17, 27)
	panel.BorderSizePixel = 0
	panel.Parent = scrim
	round(panel, 16)
	stroke(panel, Color3.fromRGB(88, 135, 174), 0.2, 1)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -28, 0, 60)
	header.Position = UDim2.fromOffset(14, 12)
	header.BackgroundColor3 = Color3.fromRGB(17, 28, 43)
	header.BorderSizePixel = 0
	header.Parent = panel
	round(header, 12)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -180, 0, 28)
	titleLabel.Position = UDim2.fromOffset(16, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Friends List"
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(241, 248, 255)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.Parent = header

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(1, -180, 0, 18)
	subtitleLabel.Position = UDim2.fromOffset(16, 35)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "Manage requests, nearby players, and your current friends."
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.TextColor3 = Color3.fromRGB(167, 196, 222)
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 13
	subtitleLabel.Parent = header

	local refreshButton = Instance.new("TextButton")
	refreshButton.Name = "RefreshButton"
	refreshButton.Size = UDim2.fromOffset(84, 34)
	refreshButton.Position = UDim2.new(1, -132, 0, 13)
	refreshButton.BackgroundColor3 = Color3.fromRGB(37, 89, 104)
	refreshButton.BorderSizePixel = 0
	refreshButton.Text = "Refresh"
	refreshButton.TextColor3 = Color3.fromRGB(236, 248, 252)
	refreshButton.Font = Enum.Font.GothamBold
	refreshButton.TextSize = 13
	refreshButton.Parent = header
	round(refreshButton, 10)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.Position = UDim2.new(1, -42, 0, 13)
	closeButton.BackgroundColor3 = Color3.fromRGB(92, 56, 64)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(246, 241, 244)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 14
	closeButton.Parent = header
	round(closeButton, 10)

	local _, requestsCountLabel, requestsList =
		makeSection(panel, "Pending Requests", UDim2.fromOffset(250, 144), UDim2.fromOffset(14, 84))

	local _, nearbyCountLabel, nearbyList =
		makeSection(panel, "Nearby Players", UDim2.fromOffset(250, 144), UDim2.fromOffset(14, 236))

	local _, friendsCountLabel, friendsList =
		makeSection(panel, "Friends", UDim2.fromOffset(250, 198), UDim2.fromOffset(14, 388))

	local detailCard = Instance.new("Frame")
	detailCard.Name = "DetailCard"
	detailCard.Size = UDim2.fromOffset(668, 500)
	detailCard.Position = UDim2.fromOffset(278, 84)
	detailCard.BackgroundColor3 = Color3.fromRGB(16, 23, 35)
	detailCard.BorderSizePixel = 0
	detailCard.Parent = panel
	round(detailCard, 14)
	stroke(detailCard, Color3.fromRGB(75, 103, 132), 0.35, 1)

	local detailTitle = Instance.new("TextLabel")
	detailTitle.Name = "DetailTitle"
	detailTitle.Size = UDim2.new(1, -24, 0, 28)
	detailTitle.Position = UDim2.fromOffset(12, 12)
	detailTitle.BackgroundTransparency = 1
	detailTitle.Text = "Select a player"
	detailTitle.TextXAlignment = Enum.TextXAlignment.Left
	detailTitle.TextColor3 = Color3.fromRGB(243, 248, 255)
	detailTitle.Font = Enum.Font.GothamBold
	detailTitle.TextSize = 22
	detailTitle.Parent = detailCard

	local detailStatus = Instance.new("TextLabel")
	detailStatus.Name = "DetailStatus"
	detailStatus.Size = UDim2.new(1, -24, 0, 18)
	detailStatus.Position = UDim2.fromOffset(12, 44)
	detailStatus.BackgroundTransparency = 1
	detailStatus.Text = "Use Pending Requests or Nearby Players to open a profile."
	detailStatus.TextXAlignment = Enum.TextXAlignment.Left
	detailStatus.TextColor3 = Color3.fromRGB(165, 198, 222)
	detailStatus.Font = Enum.Font.Gotham
	detailStatus.TextSize = 13
	detailStatus.Parent = detailCard

	local detailMeta = Instance.new("TextLabel")
	detailMeta.Name = "DetailMeta"
	detailMeta.Size = UDim2.new(1, -24, 0, 18)
	detailMeta.Position = UDim2.fromOffset(12, 66)
	detailMeta.BackgroundTransparency = 1
	detailMeta.Text = ""
	detailMeta.TextXAlignment = Enum.TextXAlignment.Left
	detailMeta.TextColor3 = Color3.fromRGB(129, 160, 184)
	detailMeta.Font = Enum.Font.Gotham
	detailMeta.TextSize = 12
	detailMeta.Parent = detailCard

	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.Size = UDim2.new(1, -24, 0, 42)
	actionRow.Position = UDim2.fromOffset(12, 92)
	actionRow.BackgroundTransparency = 1
	actionRow.Parent = detailCard

	local addFriendButton = Instance.new("TextButton")
	addFriendButton.Name = "AddFriendButton"
	addFriendButton.Size = UDim2.fromOffset(180, 38)
	addFriendButton.Position = UDim2.fromOffset(0, 2)
	addFriendButton.BackgroundColor3 = Color3.fromRGB(44, 113, 103)
	addFriendButton.BorderSizePixel = 0
	addFriendButton.Text = "Add Friend"
	addFriendButton.TextColor3 = Color3.fromRGB(239, 251, 248)
	addFriendButton.Font = Enum.Font.GothamBold
	addFriendButton.TextSize = 14
	addFriendButton.Parent = actionRow
	round(addFriendButton, 10)

	local acceptButton = Instance.new("TextButton")
	acceptButton.Name = "AcceptButton"
	acceptButton.Size = UDim2.fromOffset(132, 38)
	acceptButton.Position = UDim2.fromOffset(194, 2)
	acceptButton.BackgroundColor3 = Color3.fromRGB(53, 120, 76)
	acceptButton.BorderSizePixel = 0
	acceptButton.Text = "Accept"
	acceptButton.TextColor3 = Color3.fromRGB(240, 252, 244)
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 14
	acceptButton.Parent = actionRow
	round(acceptButton, 10)

	local declineButton = Instance.new("TextButton")
	declineButton.Name = "DeclineButton"
	declineButton.Size = UDim2.fromOffset(132, 38)
	declineButton.Position = UDim2.fromOffset(338, 2)
	declineButton.BackgroundColor3 = Color3.fromRGB(110, 61, 69)
	declineButton.BorderSizePixel = 0
	declineButton.Text = "Decline"
	declineButton.TextColor3 = Color3.fromRGB(252, 240, 244)
	declineButton.Font = Enum.Font.GothamBold
	declineButton.TextSize = 14
	declineButton.Parent = actionRow
	round(declineButton, 10)

	local messageStatusLabel = Instance.new("TextLabel")
	messageStatusLabel.Name = "MessageStatus"
	messageStatusLabel.Size = UDim2.new(1, -24, 0, 18)
	messageStatusLabel.Position = UDim2.fromOffset(12, 138)
	messageStatusLabel.BackgroundTransparency = 1
	messageStatusLabel.Text = "Messages unlock after both players accept."
	messageStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	messageStatusLabel.TextColor3 = Color3.fromRGB(182, 199, 214)
	messageStatusLabel.Font = Enum.Font.Gotham
	messageStatusLabel.TextSize = 12
	messageStatusLabel.Parent = detailCard

	local messagesList = Instance.new("ScrollingFrame")
	messagesList.Name = "MessagesList"
	messagesList.Size = UDim2.new(1, -24, 0, 264)
	messagesList.Position = UDim2.fromOffset(12, 164)
	messagesList.BackgroundColor3 = Color3.fromRGB(10, 15, 24)
	messagesList.BorderSizePixel = 0
	messagesList.CanvasSize = UDim2.new()
	messagesList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	messagesList.ScrollBarThickness = 6
	messagesList.ScrollBarImageColor3 = Color3.fromRGB(73, 116, 146)
	messagesList.Parent = detailCard
	round(messagesList, 10)
	addPadding(messagesList, 10)
	addListLayout(messagesList, 8)

	local composer = Instance.new("Frame")
	composer.Name = "Composer"
	composer.Size = UDim2.new(1, -24, 0, 50)
	composer.Position = UDim2.fromOffset(12, 438)
	composer.BackgroundTransparency = 1
	composer.Parent = detailCard

	local messageBox = Instance.new("TextBox")
	messageBox.Name = "MessageBox"
	messageBox.Size = UDim2.new(1, -130, 0, 42)
	messageBox.Position = UDim2.fromOffset(0, 4)
	messageBox.BackgroundColor3 = Color3.fromRGB(24, 35, 50)
	messageBox.BorderSizePixel = 0
	messageBox.PlaceholderText = "Type a short message..."
	messageBox.Text = ""
	messageBox.ClearTextOnFocus = false
	messageBox.TextXAlignment = Enum.TextXAlignment.Left
	messageBox.TextColor3 = Color3.fromRGB(240, 246, 255)
	messageBox.PlaceholderColor3 = Color3.fromRGB(124, 152, 178)
	messageBox.Font = Enum.Font.Gotham
	messageBox.TextSize = 14
	messageBox.Parent = composer
	round(messageBox, 10)

	local sendButton = Instance.new("TextButton")
	sendButton.Name = "SendButton"
	sendButton.Size = UDim2.fromOffset(110, 42)
	sendButton.Position = UDim2.new(1, -110, 0, 4)
	sendButton.BackgroundColor3 = Color3.fromRGB(40, 96, 141)
	sendButton.BorderSizePixel = 0
	sendButton.Text = "Send"
	sendButton.TextColor3 = Color3.fromRGB(240, 248, 255)
	sendButton.Font = Enum.Font.GothamBold
	sendButton.TextSize = 14
	sendButton.Parent = composer
	round(sendButton, 10)

	return {
		gui = gui,
		scrim = scrim,
		panel = panel,
		titleLabel = titleLabel,
		subtitleLabel = subtitleLabel,
		closeButton = closeButton,
		refreshButton = refreshButton,
		requestsCountLabel = requestsCountLabel,
		requestsList = requestsList,
		nearbyCountLabel = nearbyCountLabel,
		nearbyList = nearbyList,
		friendsCountLabel = friendsCountLabel,
		friendsList = friendsList,
		detailTitle = detailTitle,
		detailStatus = detailStatus,
		detailMeta = detailMeta,
		messageStatusLabel = messageStatusLabel,
		addFriendButton = addFriendButton,
		acceptButton = acceptButton,
		declineButton = declineButton,
		messagesList = messagesList,
		messageBox = messageBox,
		sendButton = sendButton,
	}
end

return {
	build = build,
}
