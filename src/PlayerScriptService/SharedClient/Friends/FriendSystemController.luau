local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Config = require(sharedFolder:WaitForChild("GameConfig"))
local FriendSystemView = require(script.Parent:WaitForChild("FriendSystemView"))

type View = FriendSystemView.View

type FriendEntry = {
	userId: number,
	displayName: string,
	userName: string,
	label: string,
	online: boolean?,
	lastSeenAt: number?,
	since: number?,
	blockedUntil: number?,
}

type SocialState = {
	incomingRequests: { FriendEntry },
	outgoingRequests: { FriendEntry },
	friends: { FriendEntry },
	requestCooldownsByUserId: { [string]: number },
	conversationsByUserId: { [string]: { [number]: any } },
	summary: {
		friendCount: number,
		incomingCount: number,
		outgoingCount: number,
	}?,
}

type Session = {
	view: View,
	connections: { RBXScriptConnection },
	renderConnections: { RBXScriptConnection },
	nearbyConnections: { RBXScriptConnection },
	friendGetStateFunction: RemoteFunction?,
	friendActionFunction: RemoteFunction?,
	friendStateRemote: RemoteEvent?,
	hasBoundStateRemote: boolean,
	state: SocialState,
	selectedUserId: number?,
	selectedIdentity: { displayName: string?, userName: string? }?,
	statusMessageTask: thread?,
}

local FriendSystemController = {}

local REMOTE_WAIT_TIMEOUT_SECONDS = 3
local NEARBY_MAX_DISTANCE_STUDS = 40

local session: Session? = nil
local sendAction

local function defaultState(): SocialState
	return {
		incomingRequests = {},
		outgoingRequests = {},
		friends = {},
		requestCooldownsByUserId = {},
		conversationsByUserId = {},
		summary = {
			friendCount = 0,
			incomingCount = 0,
			outgoingCount = 0,
		},
	}
end

local function normalizeUserId(value)
	local parsed = tonumber(value)
	if parsed == nil then
		return nil
	end

	parsed = math.floor(parsed)
	if parsed <= 0 then
		return nil
	end

	return parsed
end

local function disconnectConnections(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local direct = remotesFolder:FindFirstChild(remoteName)
	if direct and direct:IsA(className) then
		return direct
	end

	local awaited = remotesFolder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT_SECONDS)
	if awaited and awaited:IsA(className) then
		return awaited
	end

	return nil
end

local function getRemotesFolder()
	local direct = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if direct and direct:IsA("Folder") then
		return direct
	end

	local awaited = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT_TIMEOUT_SECONDS)
	if awaited and awaited:IsA("Folder") then
		return awaited
	end

	return nil
end

local function destroyDynamicChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function setButtonEnabled(button: TextButton, enabled: boolean, enabledColor: Color3, disabledColor: Color3)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then enabledColor else disabledColor
end

local function round(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function connectButtonPress(
	connections: { RBXScriptConnection },
	button: TextButton,
	callback: () -> ()
)
	local pressLocked = false
	local function handlePress()
		if pressLocked then
			return
		end

		pressLocked = true
		callback()
		task.delay(0.2, function()
			pressLocked = false
		end)
	end

	table.insert(connections, button.Activated:Connect(handlePress))
	table.insert(connections, button.MouseButton1Click:Connect(handlePress))
end

local function formatDateTime(unixTime: number?)
	local resolved = math.max(0, tonumber(unixTime) or 0)
	if resolved <= 0 then
		return "unknown"
	end

	return os.date("%b %d, %Y %H:%M", resolved)
end

local function findEntry(entries: { FriendEntry }, userId: number): FriendEntry?
	for _, entry in ipairs(entries) do
		if entry.userId == userId then
			return entry
		end
	end

	return nil
end

local function sortFriends(entries: { FriendEntry })
	table.sort(entries, function(a, b)
		local aOnline = a.online == true
		local bOnline = b.online == true
		if aOnline ~= bOnline then
			return aOnline
		end

		return a.label < b.label
	end)
end

local function getCharacterRootPart(targetPlayer)
	local character = targetPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	local fallbackRoot = character:FindFirstChild("Head")
	if fallbackRoot and fallbackRoot:IsA("BasePart") then
		return fallbackRoot
	end

	return nil
end

local function buildNearbyPlayers(currentSession: Session)
	local localRoot = getCharacterRootPart(player)
	if not localRoot then
		return {}
	end

	local nearbyEntries = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer == player then
			continue
		end

		local otherRoot = getCharacterRootPart(otherPlayer)
		if not otherRoot then
			continue
		end

		local distance = (localRoot.Position - otherRoot.Position).Magnitude
		if distance > NEARBY_MAX_DISTANCE_STUDS then
			continue
		end

		table.insert(nearbyEntries, {
			userId = otherPlayer.UserId,
			displayName = otherPlayer.DisplayName,
			userName = otherPlayer.Name,
			label = if otherPlayer.DisplayName ~= otherPlayer.Name
				then ("%s (@%s)"):format(otherPlayer.DisplayName, otherPlayer.Name)
				else otherPlayer.DisplayName,
			distance = distance,
			incoming = findEntry(currentSession.state.incomingRequests, otherPlayer.UserId) ~= nil,
			outgoing = findEntry(currentSession.state.outgoingRequests, otherPlayer.UserId) ~= nil,
			friend = findEntry(currentSession.state.friends, otherPlayer.UserId) ~= nil,
			cooldownUntil =
				tonumber(currentSession.state.requestCooldownsByUserId[tostring(otherPlayer.UserId)]) or 0,
		})
	end

	table.sort(nearbyEntries, function(a, b)
		if math.abs(a.distance - b.distance) < 0.05 then
			return a.label < b.label
		end

		return a.distance < b.distance
	end)

	return nearbyEntries
end

local function buildSelectionIdentity(currentSession: Session, userId: number)
	local incomingEntry = findEntry(currentSession.state.incomingRequests, userId)
	if incomingEntry then
		return incomingEntry.displayName, incomingEntry.userName
	end

	local outgoingEntry = findEntry(currentSession.state.outgoingRequests, userId)
	if outgoingEntry then
		return outgoingEntry.displayName, outgoingEntry.userName
	end

	local friendEntry = findEntry(currentSession.state.friends, userId)
	if friendEntry then
		return friendEntry.displayName, friendEntry.userName
	end

	local livePlayer = Players:GetPlayerByUserId(userId)
	if livePlayer then
		return livePlayer.DisplayName, livePlayer.Name
	end

	local identity = currentSession.selectedIdentity
	if identity then
		local fallbackName = identity.userName or identity.displayName or "Player"
		return identity.displayName or fallbackName, fallbackName
	end

	return "Player", "Player"
end

local function ensureSelection(currentSession: Session)
	local selectedUserId = currentSession.selectedUserId
	if selectedUserId ~= nil then
		return
	end

	local fallbackEntry = currentSession.state.incomingRequests[1]
		or currentSession.state.friends[1]
		or currentSession.state.outgoingRequests[1]

	if fallbackEntry then
		currentSession.selectedUserId = fallbackEntry.userId
		currentSession.selectedIdentity = {
			displayName = fallbackEntry.displayName,
			userName = fallbackEntry.userName,
		}
	end
end

local function setStatusMessage(currentSession: Session, text: string, color: Color3)
	currentSession.view.messageStatusLabel.Text = text
	currentSession.view.messageStatusLabel.TextColor3 = color
end

local function flashStatusMessage(currentSession: Session, text: string, color: Color3)
	if currentSession.statusMessageTask then
		task.cancel(currentSession.statusMessageTask)
	end

	setStatusMessage(currentSession, text, color)

	currentSession.statusMessageTask = task.delay(4, function()
		if session ~= currentSession then
			return
		end

		currentSession.statusMessageTask = nil
		if currentSession.selectedUserId then
			return
		end

		setStatusMessage(currentSession, "Messages unlock after both players accept.", Color3.fromRGB(182, 199, 214))
	end)
end

local function renderListEntry(
	container: ScrollingFrame,
	entry: FriendEntry,
	isSelected: boolean,
	subtitleText: string,
	baseColor: Color3
)
	local card = Instance.new("Frame")
	card.Name = tostring(entry.userId)
	card.Size = UDim2.new(1, -4, 0, 54)
	card.BackgroundColor3 = if isSelected then Color3.fromRGB(36, 64, 92) else baseColor
	card.BorderSizePixel = 0
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local selectButton = Instance.new("TextButton")
	selectButton.Name = "SelectButton"
	selectButton.Size = UDim2.new(1, 0, 1, 0)
	selectButton.BackgroundTransparency = 1
	selectButton.BorderSizePixel = 0
	selectButton.Text = ""
	selectButton.ZIndex = 1
	selectButton.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.Text = entry.label
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(241, 247, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.ZIndex = 2
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -16, 0, 18)
	subtitle.Position = UDim2.fromOffset(8, 29)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = subtitleText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Color3.fromRGB(168, 196, 221)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 11
	subtitle.ZIndex = 2
	subtitle.Parent = card

	return card, selectButton
end

local function renderRequests(currentSession: Session)
	local view = currentSession.view
	destroyDynamicChildren(view.requestsList)
	view.requestsCountLabel.Text = tostring(#currentSession.state.incomingRequests)

	local hasAnyRequest = false
	for _, entry in ipairs(currentSession.state.incomingRequests) do
		hasAnyRequest = true
		local card, selectButton = renderListEntry(
			view.requestsList,
			entry,
			currentSession.selectedUserId == entry.userId,
			("Waiting since %s"):format(formatDateTime(entry.createdAt)),
			Color3.fromRGB(26, 41, 58)
		)

		connectButtonPress(currentSession.renderConnections, selectButton, function()
			currentSession.selectedUserId = entry.userId
			currentSession.selectedIdentity = {
				displayName = entry.displayName,
				userName = entry.userName,
			}
			FriendSystemController.render()
		end)
	end

	if not hasAnyRequest then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 36)
		empty.BackgroundTransparency = 1
		empty.Text = "No pending requests yet."
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.Parent = view.requestsList
	end
end

local function requestRemoveFriend(currentSession: Session, userId: number, identity)
	local removedEntry = nil
	local removedIndex = nil
	for index, entry in ipairs(currentSession.state.friends) do
		if entry.userId == userId then
			removedEntry = entry
			removedIndex = index
			break
		end
	end

	local conversationKey = tostring(userId)
	local removedConversation = currentSession.state.conversationsByUserId[conversationKey]
	local previousSelectedUserId = currentSession.selectedUserId
	local previousIdentity = currentSession.selectedIdentity

	if removedEntry and removedIndex then
		table.remove(currentSession.state.friends, removedIndex)
		currentSession.state.conversationsByUserId[conversationKey] = nil
		if currentSession.state.summary then
			currentSession.state.summary.friendCount = #currentSession.state.friends
		end
	end

	if currentSession.selectedUserId == userId then
		currentSession.selectedUserId = nil
		currentSession.selectedIdentity = nil
	end

	if removedEntry then
		ensureSelection(currentSession)
		FriendSystemController.render()
	end

	local didRemove = sendAction({
		action = "removeFriend",
		targetUserId = userId,
	}, nil)

	if didRemove then
		return true
	end

	if removedEntry then
		local targetIndex = removedIndex
		if targetIndex < 1 then
			targetIndex = 1
		end
		if targetIndex > (#currentSession.state.friends + 1) then
			targetIndex = #currentSession.state.friends + 1
		end

		table.insert(currentSession.state.friends, targetIndex, removedEntry)
		sortFriends(currentSession.state.friends)
		currentSession.state.conversationsByUserId[conversationKey] = removedConversation
		if currentSession.state.summary then
			currentSession.state.summary.friendCount = #currentSession.state.friends
		end
	end

	currentSession.selectedUserId = previousSelectedUserId
	currentSession.selectedIdentity = previousIdentity or identity
	FriendSystemController.render()

	return false
end

local function renderFriends(currentSession: Session)
	local view = currentSession.view
	destroyDynamicChildren(view.friendsList)
	view.friendsCountLabel.Text = tostring(#currentSession.state.friends)

	local hasAnyFriend = false
	for _, entry in ipairs(currentSession.state.friends) do
		hasAnyFriend = true
		local subtitle = if entry.online
			then "Online now"
			else ("Last seen %s"):format(formatDateTime(entry.lastSeenAt))
		local card, selectButton = renderListEntry(
			view.friendsList,
			entry,
			currentSession.selectedUserId == entry.userId,
			subtitle,
			Color3.fromRGB(22, 35, 50)
		)
		local title = card:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Size = UDim2.new(1, -88, 0, 22)
		end

		local subtitleLabel = card:FindFirstChild("Subtitle")
		if subtitleLabel and subtitleLabel:IsA("TextLabel") then
			subtitleLabel.Size = UDim2.new(1, -88, 0, 18)
		end

		local deleteButton = Instance.new("TextButton")
		deleteButton.Name = "DeleteButton"
		deleteButton.Size = UDim2.fromOffset(64, 30)
		deleteButton.Position = UDim2.new(1, -72, 0.5, -15)
		deleteButton.Active = true
		deleteButton.AutoButtonColor = true
		deleteButton.BackgroundColor3 = Color3.fromRGB(110, 61, 69)
		deleteButton.BorderSizePixel = 0
		deleteButton.Text = "Delete"
		deleteButton.TextColor3 = Color3.fromRGB(252, 240, 244)
		deleteButton.Font = Enum.Font.GothamBold
		deleteButton.TextSize = 11
		deleteButton.ZIndex = 3
		deleteButton.Parent = card
		round(deleteButton, 9)

		selectButton.Size = UDim2.new(1, -92, 1, 0)

		connectButtonPress(currentSession.renderConnections, selectButton, function()
			currentSession.selectedUserId = entry.userId
			currentSession.selectedIdentity = {
				displayName = entry.displayName,
				userName = entry.userName,
			}
			FriendSystemController.render()
		end)
		local deleteRequested = false
		local function handleDelete()
			if deleteRequested then
				return
			end

			deleteRequested = true
			deleteButton.Active = false
			local didRemove = requestRemoveFriend(currentSession, entry.userId, {
				displayName = entry.displayName,
				userName = entry.userName,
			})
			if not didRemove then
				deleteRequested = false
				deleteButton.Active = true
			end
		end

		connectButtonPress(currentSession.renderConnections, deleteButton, handleDelete)
	end

	if not hasAnyFriend then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 36)
		empty.BackgroundTransparency = 1
		empty.Text = "No friends yet. Send a request from Nearby Players to get started."
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.Parent = view.friendsList
	end
end

local function renderNearbyPlayers(currentSession: Session)
	local view = currentSession.view
	local nearbyEntries = buildNearbyPlayers(currentSession)
	local previousCanvasPosition = view.nearbyList.CanvasPosition
	destroyDynamicChildren(view.nearbyList)
	view.nearbyCountLabel.Text = tostring(#nearbyEntries)

	if #nearbyEntries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 36)
		empty.BackgroundTransparency = 1
		empty.Text = ("No players within %d studs right now."):format(NEARBY_MAX_DISTANCE_STUDS)
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.Parent = view.nearbyList
		view.nearbyList.CanvasPosition = previousCanvasPosition
		return
	end

	for _, entry in ipairs(nearbyEntries) do
		local card = Instance.new("Frame")
		card.Name = tostring(entry.userId)
		card.Size = UDim2.new(1, -4, 0, 54)
		card.BackgroundColor3 = if currentSession.selectedUserId == entry.userId
			then Color3.fromRGB(36, 64, 92)
			else Color3.fromRGB(24, 38, 54)
		card.BorderSizePixel = 0
		card.Parent = view.nearbyList

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = card

		local selectButton = Instance.new("TextButton")
		selectButton.Name = "SelectButton"
		selectButton.Size = UDim2.new(1, -88, 1, 0)
		selectButton.BackgroundTransparency = 1
		selectButton.Text = ""
		selectButton.Parent = card

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, -100, 0, 22)
		title.Position = UDim2.fromOffset(8, 6)
		title.BackgroundTransparency = 1
		title.Text = entry.label
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(241, 247, 255)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 13
		title.Parent = card

		local subtitle = Instance.new("TextLabel")
		subtitle.Name = "Subtitle"
		subtitle.Size = UDim2.new(1, -100, 0, 18)
		subtitle.Position = UDim2.fromOffset(8, 29)
		subtitle.BackgroundTransparency = 1
		subtitle.Text = ("%d studs away"):format(math.max(1, math.floor(entry.distance + 0.5)))
		subtitle.TextXAlignment = Enum.TextXAlignment.Left
		subtitle.TextColor3 = Color3.fromRGB(168, 196, 221)
		subtitle.Font = Enum.Font.Gotham
		subtitle.TextSize = 11
		subtitle.Parent = card

		local actionButton = Instance.new("TextButton")
		actionButton.Name = "ActionButton"
		actionButton.Size = UDim2.fromOffset(72, 34)
		actionButton.Position = UDim2.new(1, -80, 0.5, -17)
		actionButton.BorderSizePixel = 0
		actionButton.TextColor3 = Color3.fromRGB(239, 251, 248)
		actionButton.Font = Enum.Font.GothamBold
		actionButton.TextSize = 12
		actionButton.Parent = card
		local actionEnabled = false

		if entry.friend then
			actionButton.Text = "Friends"
			actionButton.BackgroundColor3 = Color3.fromRGB(62, 77, 83)
		elseif entry.outgoing then
			actionButton.Text = "Pending"
			actionButton.BackgroundColor3 = Color3.fromRGB(62, 77, 83)
		elseif entry.incoming then
			actionButton.Text = "Review"
			actionButton.BackgroundColor3 = Color3.fromRGB(53, 120, 76)
			actionEnabled = true
		elseif entry.cooldownUntil > os.time() then
			actionButton.Text = "Cooldown"
			actionButton.BackgroundColor3 = Color3.fromRGB(84, 67, 70)
		else
			actionButton.Text = "Add"
			actionButton.BackgroundColor3 = Color3.fromRGB(44, 113, 103)
			actionEnabled = true
		end

		actionButton.AutoButtonColor = actionEnabled
		actionButton.Active = actionEnabled
		round(actionButton, 10)

		local function selectEntry()
			currentSession.selectedUserId = entry.userId
			currentSession.selectedIdentity = {
				displayName = entry.displayName,
				userName = entry.userName,
			}
		end

		connectButtonPress(currentSession.nearbyConnections, selectButton, function()
			selectEntry()
			FriendSystemController.render()
		end)
		connectButtonPress(currentSession.nearbyConnections, actionButton, function()
			selectEntry()

			if entry.incoming then
				FriendSystemController.render()
				return
			end

			sendAction({
				action = "sendRequest",
				targetUserId = entry.userId,
				targetDisplayName = entry.displayName,
				targetUserName = entry.userName,
			}, nil)
		end)
	end

	view.nearbyList.CanvasPosition = previousCanvasPosition
end

local function renderMessages(currentSession: Session, messages, selectedUserId: number?, selectedDisplayName: string, isFriend: boolean)
	local view = currentSession.view
	destroyDynamicChildren(view.messagesList)

	if not selectedUserId then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 48)
		empty.BackgroundTransparency = 1
		empty.Text = "Pick a nearby player, friend, or pending request to see details here."
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.Parent = view.messagesList
		return
	end

	if not isFriend then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 48)
		empty.BackgroundTransparency = 1
		empty.Text = "Direct messages open once both players are friends."
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.Parent = view.messagesList
		return
	end

	local didRenderMessage = false
	for _, message in ipairs(messages or {}) do
		if type(message) ~= "table" then
			continue
		end

		didRenderMessage = true
		local isMine = message.fromUserId == player.UserId

		local bubble = Instance.new("TextLabel")
		bubble.Size = UDim2.new(1, -6, 0, 0)
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.BackgroundColor3 = if isMine then Color3.fromRGB(36, 74, 110) else Color3.fromRGB(31, 44, 60)
		bubble.BorderSizePixel = 0
		bubble.TextWrapped = true
		bubble.TextXAlignment = Enum.TextXAlignment.Left
		bubble.TextYAlignment = Enum.TextYAlignment.Top
		bubble.Font = Enum.Font.Gotham
		bubble.TextSize = 13
		bubble.TextColor3 = Color3.fromRGB(236, 244, 255)
		bubble.Text = string.format(
			"%s - %s\n%s",
			if isMine then "You" else (message.fromDisplayName or selectedDisplayName),
			formatDateTime(message.createdAt),
			tostring(message.body or "")
		)
		bubble.Parent = view.messagesList

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = bubble

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = bubble
	end

	if not didRenderMessage then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 36)
		empty.BackgroundTransparency = 1
		empty.Text = ("Start the conversation with %s."):format(selectedDisplayName)
		empty.TextWrapped = true
		empty.TextColor3 = Color3.fromRGB(129, 160, 184)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 13
		empty.Parent = view.messagesList
	end
end

local function renderDetail(currentSession: Session)
	local view = currentSession.view
	local selectedUserId = currentSession.selectedUserId
	local incomingEntry = if selectedUserId then findEntry(currentSession.state.incomingRequests, selectedUserId) else nil
	local outgoingEntry = if selectedUserId then findEntry(currentSession.state.outgoingRequests, selectedUserId) else nil
	local friendEntry = if selectedUserId then findEntry(currentSession.state.friends, selectedUserId) else nil

	if not selectedUserId then
		view.detailTitle.Text = "Select a player"
		view.detailStatus.Text = "Use Pending Requests or Nearby Players to open a profile."
		view.detailMeta.Text = ""
		view.addFriendButton.Visible = false
		view.acceptButton.Visible = false
		view.declineButton.Visible = false
		view.messageBox.Text = ""
		view.messageBox.ClearTextOnFocus = false
		view.messageBox.PlaceholderText = "Type a short message..."
		setButtonEnabled(view.sendButton, false, Color3.fromRGB(40, 96, 141), Color3.fromRGB(50, 58, 70))
		renderMessages(currentSession, nil, nil, "", false)
		setStatusMessage(currentSession, "Messages unlock after both players accept.", Color3.fromRGB(182, 199, 214))
		return
	end

	local displayName, userName = buildSelectionIdentity(currentSession, selectedUserId)
	local isIncoming = incomingEntry ~= nil
	local isOutgoing = outgoingEntry ~= nil
	local isFriend = friendEntry ~= nil
	local isSelf = selectedUserId == player.UserId
	local livePlayer = Players:GetPlayerByUserId(selectedUserId)
	local blockedUntil = tonumber(currentSession.state.requestCooldownsByUserId[tostring(selectedUserId)]) or 0
	local hasActiveCooldown = blockedUntil > os.time()

	view.detailTitle.Text = if displayName ~= userName
		then ("%s (@%s)"):format(displayName, userName)
		else displayName

	if isFriend and friendEntry then
		view.detailStatus.Text = if friendEntry.online then "Online now" else "Offline"
		view.detailMeta.Text = if friendEntry.online
			then "You can chat right away."
			else ("Last seen on a server: %s"):format(formatDateTime(friendEntry.lastSeenAt))
	elseif isIncoming then
		view.detailStatus.Text = "Incoming friend request"
		view.detailMeta.Text = "Accept to unlock direct messages."
	elseif isOutgoing then
		view.detailStatus.Text = "Request pending"
		view.detailMeta.Text = "Waiting for them to respond."
	elseif isSelf then
		view.detailStatus.Text = "This is you"
		view.detailMeta.Text = "Other players can send you a request from their Friends List."
	elseif livePlayer then
		view.detailStatus.Text = "In this server now"
		view.detailMeta.Text = "Send a request to connect."
	else
		view.detailStatus.Text = "Offline"
		view.detailMeta.Text = if hasActiveCooldown
			then ("Request cooldown until %s"):format(formatDateTime(blockedUntil))
			else "This player is not currently in your server."
	end

	view.addFriendButton.Visible = not isIncoming and not isSelf
	view.acceptButton.Visible = isIncoming
	view.declineButton.Visible = isIncoming

	if isFriend then
		view.addFriendButton.Text = "Delete Friend"
		setButtonEnabled(view.addFriendButton, true, Color3.fromRGB(110, 61, 69), Color3.fromRGB(62, 77, 83))
	elseif isOutgoing then
		view.addFriendButton.Text = "Request Pending"
		setButtonEnabled(view.addFriendButton, false, Color3.fromRGB(44, 113, 103), Color3.fromRGB(62, 77, 83))
	elseif hasActiveCooldown then
		view.addFriendButton.Text = "Cooldown Active"
		setButtonEnabled(view.addFriendButton, false, Color3.fromRGB(44, 113, 103), Color3.fromRGB(84, 67, 70))
	else
		view.addFriendButton.Text = "Add Friend"
		setButtonEnabled(view.addFriendButton, true, Color3.fromRGB(44, 113, 103), Color3.fromRGB(62, 77, 83))
	end

	setButtonEnabled(view.acceptButton, isIncoming, Color3.fromRGB(53, 120, 76), Color3.fromRGB(60, 70, 62))
	setButtonEnabled(view.declineButton, isIncoming, Color3.fromRGB(110, 61, 69), Color3.fromRGB(73, 62, 65))
	setButtonEnabled(view.sendButton, isFriend, Color3.fromRGB(40, 96, 141), Color3.fromRGB(50, 58, 70))
	view.messageBox.TextEditable = isFriend
	view.messageBox.PlaceholderText = if isFriend then "Type a short message..." else "Become friends to chat"
	renderMessages(
		currentSession,
		currentSession.state.conversationsByUserId[tostring(selectedUserId)],
		selectedUserId,
		displayName,
		isFriend
	)

	if isFriend then
		setStatusMessage(currentSession, "Friend chat is synced in-game.", Color3.fromRGB(166, 205, 224))
	elseif isIncoming then
		setStatusMessage(currentSession, "Accept or decline this request.", Color3.fromRGB(182, 199, 214))
	elseif isOutgoing then
		setStatusMessage(currentSession, "Waiting for the other player to respond.", Color3.fromRGB(182, 199, 214))
	else
		setStatusMessage(currentSession, "Use Add Friend to start the connection.", Color3.fromRGB(182, 199, 214))
	end
end

local function normalizeState(rawState)
	if type(rawState) ~= "table" then
		return defaultState()
	end

	return {
		incomingRequests = type(rawState.incomingRequests) == "table" and rawState.incomingRequests or {},
		outgoingRequests = type(rawState.outgoingRequests) == "table" and rawState.outgoingRequests or {},
		friends = type(rawState.friends) == "table" and rawState.friends or {},
		requestCooldownsByUserId =
			type(rawState.requestCooldownsByUserId) == "table" and rawState.requestCooldownsByUserId or {},
		conversationsByUserId =
			type(rawState.conversationsByUserId) == "table" and rawState.conversationsByUserId or {},
		summary = type(rawState.summary) == "table" and rawState.summary or {
			friendCount = 0,
			incomingCount = 0,
			outgoingCount = 0,
		},
	}
end

local function applyState(currentSession: Session, rawState, preserveSelection: boolean)
	currentSession.state = normalizeState(rawState)

	if not preserveSelection then
		currentSession.selectedUserId = nil
		currentSession.selectedIdentity = nil
	end

	ensureSelection(currentSession)
	FriendSystemController.render()
end

local function invokeServer(currentSession: Session, remoteFunction: RemoteFunction?, payload)
	if not remoteFunction then
		return false, { success = false, message = "Friend remotes are not ready." }
	end

	local ok, response = pcall(function()
		return remoteFunction:InvokeServer(payload)
	end)

	if not ok then
		return false, { success = false, message = "Server call failed." }
	end

	return true, response
end

local function bindStateRemote(currentSession: Session)
	if currentSession.hasBoundStateRemote or not currentSession.friendStateRemote then
		return
	end

	currentSession.hasBoundStateRemote = true
	table.insert(currentSession.connections, currentSession.friendStateRemote.OnClientEvent:Connect(function(payload)
		applyState(currentSession, payload, true)
	end))
end

local function refreshRemoteRefs(currentSession: Session)
	local remotesFolder = getRemotesFolder()
	if not currentSession.friendGetStateFunction then
		currentSession.friendGetStateFunction = resolveRemote(remotesFolder, Config.Remotes.FriendGetState, "RemoteFunction")
	end
	if not currentSession.friendActionFunction then
		currentSession.friendActionFunction = resolveRemote(remotesFolder, Config.Remotes.FriendAction, "RemoteFunction")
	end
	if not currentSession.friendStateRemote then
		currentSession.friendStateRemote = resolveRemote(remotesFolder, Config.Remotes.FriendState, "RemoteEvent")
	end

	bindStateRemote(currentSession)
end

function FriendSystemController.refresh(preserveSelection: boolean?)
	local currentSession = session
	if not currentSession then
		return
	end

	refreshRemoteRefs(currentSession)
	local ok, response = invokeServer(currentSession, currentSession.friendGetStateFunction, nil)
	if not ok or type(response) ~= "table" or response.success ~= true then
		flashStatusMessage(currentSession, "Could not load your friends right now.", Color3.fromRGB(241, 166, 166))
		return
	end

	applyState(currentSession, response, preserveSelection == true)
end

sendAction = function(payload, successMessage)
	local currentSession = session
	if not currentSession then
		return false
	end

	refreshRemoteRefs(currentSession)
	local ok, response = invokeServer(currentSession, currentSession.friendActionFunction, payload)
	if not ok or type(response) ~= "table" then
		flashStatusMessage(currentSession, "That action failed.", Color3.fromRGB(241, 166, 166))
		return false
	end

	if response.success == true then
		if successMessage then
			flashStatusMessage(currentSession, successMessage, Color3.fromRGB(172, 224, 192))
		elseif type(response.message) == "string" then
			flashStatusMessage(currentSession, response.message, Color3.fromRGB(172, 224, 192))
		end

		FriendSystemController.refresh(true)
		return true
	end

	flashStatusMessage(
		currentSession,
		type(response.message) == "string" and response.message or "That action could not be completed.",
		Color3.fromRGB(241, 166, 166)
	)

	return false
end

function FriendSystemController.render()
	local currentSession = session
	if not currentSession then
		return
	end

	disconnectConnections(currentSession.renderConnections)
	disconnectConnections(currentSession.nearbyConnections)
	renderRequests(currentSession)
	renderNearbyPlayers(currentSession)
	renderFriends(currentSession)
	renderDetail(currentSession)
end

local function ensureStarted()
	if session then
		return session
	end

	local view = FriendSystemView.build()
	local remotesFolder = getRemotesFolder()

	local newSession: Session = {
		view = view,
		connections = {},
		renderConnections = {},
		nearbyConnections = {},
		friendGetStateFunction = resolveRemote(remotesFolder, Config.Remotes.FriendGetState, "RemoteFunction"),
		friendActionFunction = resolveRemote(remotesFolder, Config.Remotes.FriendAction, "RemoteFunction"),
		friendStateRemote = resolveRemote(remotesFolder, Config.Remotes.FriendState, "RemoteEvent"),
		hasBoundStateRemote = false,
		state = defaultState(),
		selectedUserId = nil,
		selectedIdentity = nil,
		statusMessageTask = nil,
	}
	session = newSession

	connectButtonPress(newSession.connections, view.closeButton, function()
		view.scrim.Visible = false
	end)

	connectButtonPress(newSession.connections, view.refreshButton, function()
		FriendSystemController.render()
		FriendSystemController.refresh(true)
	end)

	connectButtonPress(newSession.connections, view.addFriendButton, function()
		if not newSession.selectedUserId then
			return
		end

		local selectedFriend = findEntry(newSession.state.friends, newSession.selectedUserId)
		if selectedFriend then
			requestRemoveFriend(newSession, newSession.selectedUserId, {
				displayName = selectedFriend.displayName,
				userName = selectedFriend.userName,
			})
			return
		end

		sendAction({
			action = "sendRequest",
			targetUserId = newSession.selectedUserId,
			targetDisplayName = newSession.selectedIdentity and newSession.selectedIdentity.displayName or nil,
			targetUserName = newSession.selectedIdentity and newSession.selectedIdentity.userName or nil,
		}, nil)
	end)

	connectButtonPress(newSession.connections, view.acceptButton, function()
		if not newSession.selectedUserId then
			return
		end

		sendAction({
			action = "respondRequest",
			targetUserId = newSession.selectedUserId,
			accept = true,
		}, nil)
	end)

	connectButtonPress(newSession.connections, view.declineButton, function()
		if not newSession.selectedUserId then
			return
		end

		sendAction({
			action = "respondRequest",
			targetUserId = newSession.selectedUserId,
			accept = false,
		}, nil)
	end)

	connectButtonPress(newSession.connections, view.sendButton, function()
		if not newSession.selectedUserId then
			return
		end

		local message = view.messageBox.Text
		local didSend = sendAction({
			action = "sendMessage",
			targetUserId = newSession.selectedUserId,
			message = message,
		}, nil)
		if didSend then
			view.messageBox.Text = ""
		end
	end)

	bindStateRemote(newSession)

	task.spawn(function()
		local refreshElapsedSeconds = 0
		while session == newSession do
			task.wait(2)
			if not view.scrim.Visible then
				refreshElapsedSeconds = 0
				continue
			end

			refreshElapsedSeconds += 2
			if refreshElapsedSeconds >= 20 then
				refreshElapsedSeconds = 0
				FriendSystemController.refresh(true)
			else
				disconnectConnections(newSession.nearbyConnections)
				renderNearbyPlayers(newSession)
			end
		end
	end)

	task.defer(function()
		if session == newSession then
			FriendSystemController.refresh(false)
		end
	end)
	return newSession
end

function FriendSystemController.start()
	ensureStarted()
end

function FriendSystemController.open()
	local currentSession = ensureStarted()
	currentSession.view.scrim.Visible = true
	task.defer(function()
		if session == currentSession then
			FriendSystemController.refresh(true)
		end
	end)
end

function FriendSystemController.openForUser(userId: number, displayName: string?, userName: string?)
	local normalizedUserId = normalizeUserId(userId)
	if not normalizedUserId then
		return
	end

	local currentSession = ensureStarted()
	currentSession.selectedUserId = normalizedUserId
	currentSession.selectedIdentity = {
		displayName = displayName,
		userName = userName,
	}
	currentSession.view.scrim.Visible = true
	task.defer(function()
		if session == currentSession then
			FriendSystemController.refresh(true)
		end
	end)
end

return FriendSystemController
