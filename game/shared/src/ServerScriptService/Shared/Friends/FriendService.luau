local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(script.Parent.Parent:WaitForChild("PlayerData"):WaitForChild("PlayerDataService"))

local FriendService = {}

local PRESENCE_STORE_NAME = "BrainrotFloor_FriendPresence_v1"
local DISPATCH_TOPIC = "BrainrotFloor_FriendDispatch_v1"
local PRESENCE_TTL_SECONDS = 60 * 60 * 24 * 45
local PRESENCE_STALE_SECONDS = 120
local PRESENCE_HEARTBEAT_SECONDS = 45
local REQUEST_BLOCK_SECONDS = 10 * 60
local SOCIAL_SCHEMA_VERSION = 1
local MAX_NAME_LENGTH = 32
local MAX_MESSAGE_LENGTH = 180
local MAX_MESSAGES_PER_FRIEND = 30

local started = false
local remotesFolder = nil
local friendGetStateFunction = nil
local friendActionFunction = nil
local friendStateRemote = nil
local presenceStore = MemoryStoreService:GetSortedMap(PRESENCE_STORE_NAME)
local dispatchSubscription = nil

local function nowSeconds()
	return os.time()
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

local function toUserIdKey(userId)
	return tostring(userId)
end

local function clampString(value, maxLength, fallback)
	local resolved = value
	if type(resolved) ~= "string" then
		resolved = fallback or ""
	end

	resolved = string.gsub(resolved, "[\r\n]", " ")
	resolved = string.sub(resolved, 1, maxLength)
	if resolved == "" then
		resolved = fallback or ""
	end

	return resolved
end

local function normalizeLookupName(value)
	local normalized = clampString(value, MAX_NAME_LENGTH, "")
	normalized = string.match(normalized, "^%s*(.-)%s*$") or ""
	normalized = string.gsub(normalized, "^@+", "")
	return normalized
end

local function startsWithIgnoreCase(value, prefixLower)
	return string.sub(string.lower(value), 1, #prefixLower) == prefixLower
end

local function buildIdentity(displayName, userName, fallbackName)
	local safeUserName = clampString(userName, MAX_NAME_LENGTH, fallbackName or "Player")
	local safeDisplayName = clampString(displayName, MAX_NAME_LENGTH, safeUserName)

	return {
		displayName = safeDisplayName,
		userName = safeUserName,
	}
end

local function buildIdentityFromPlayer(player)
	return buildIdentity(player.DisplayName, player.Name, player.Name)
end

local function mergeIdentity(baseEntry, presenceEntry, fallbackName)
	local displayName = nil
	local userName = nil

	if type(baseEntry) == "table" then
		displayName = baseEntry.displayName
		userName = baseEntry.userName
	end

	if type(presenceEntry) == "table" then
		displayName = presenceEntry.displayName or displayName
		userName = presenceEntry.userName or userName
	end

	return buildIdentity(displayName, userName, fallbackName)
end

local function ensureRemote(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function ensureSocialData(rawValue)
	local social = rawValue
	if type(social) ~= "table" then
		social = {}
	end

	social.schemaVersion = SOCIAL_SCHEMA_VERSION
	social.friendsByUserId = if type(social.friendsByUserId) == "table" then social.friendsByUserId else {}
	social.incomingRequestsByUserId =
		if type(social.incomingRequestsByUserId) == "table" then social.incomingRequestsByUserId else {}
	social.outgoingRequestsByUserId =
		if type(social.outgoingRequestsByUserId) == "table" then social.outgoingRequestsByUserId else {}
	social.requestCooldownsByUserId =
		if type(social.requestCooldownsByUserId) == "table" then social.requestCooldownsByUserId else {}
	social.conversationsByUserId =
		if type(social.conversationsByUserId) == "table" then social.conversationsByUserId else {}

	return social
end

local function ensureConversationBucket(social, otherUserId)
	local key = toUserIdKey(otherUserId)
	local bucket = social.conversationsByUserId[key]
	if type(bucket) ~= "table" then
		bucket = {}
		social.conversationsByUserId[key] = bucket
	end

	return bucket
end

local function appendConversationMessage(social, otherUserId, messageEntry)
	local bucket = ensureConversationBucket(social, otherUserId)
	table.insert(bucket, messageEntry)

	while #bucket > MAX_MESSAGES_PER_FRIEND do
		table.remove(bucket, 1)
	end
end

local function getActiveCooldown(social, targetUserId)
	local expiresAt = tonumber(social.requestCooldownsByUserId[toUserIdKey(targetUserId)]) or 0
	if expiresAt <= nowSeconds() then
		return 0
	end

	return expiresAt
end

local function ensurePlayerSocial(player)
	PlayerDataService.waitForData(player)
	PlayerDataService.update(player, { "social" }, function(currentValue)
		return ensureSocialData(currentValue)
	end)
end

local function mutatePlayerSocial(player, callback)
	PlayerDataService.waitForData(player)

	local callbackResult = nil
	local updatedSocial = nil
	PlayerDataService.update(player, { "social" }, function(currentValue)
		local social = ensureSocialData(currentValue)
		updatedSocial = social
		callbackResult = callback(social)
		return social
	end)

	return updatedSocial, callbackResult
end

local function mutateOfflineSocial(userId, callback)
	return PlayerDataService.editOfflineUser(userId, function(data)
		data.social = ensureSocialData(data.social)
		callback(data.social)
	end)
end

local function shouldFallbackToDispatch(errorMessage)
	if type(errorMessage) ~= "string" then
		return false
	end

	local normalized = string.lower(errorMessage)
	if string.find(normalized, "no profile", 1, true) then
		return false
	end

	return string.find(normalized, "online", 1, true) ~= nil
		or string.find(normalized, "lock", 1, true) ~= nil
		or string.find(normalized, "session", 1, true) ~= nil
end

local function readPresence(userId)
	local ok, value = pcall(function()
		return presenceStore:GetAsync(toUserIdKey(userId))
	end)
	if not ok or type(value) ~= "table" then
		return nil
	end

	return value
end

local function buildPresenceFromPlayer(player)
	local currentTime = nowSeconds()
	local identity = buildIdentityFromPlayer(player)

	return {
		displayName = identity.displayName,
		userName = identity.userName,
		online = true,
		lastSeenAt = currentTime,
		updatedAt = currentTime,
		placeId = game.PlaceId,
		jobId = game.JobId,
	}
end

local function getPresenceForUser(userId)
	local storedPresence = readPresence(userId)
	if type(storedPresence) == "table" and storedPresence.online ~= true then
		return storedPresence
	end

	local livePlayer = Players:GetPlayerByUserId(userId)
	if livePlayer and livePlayer.Parent == Players then
		return buildPresenceFromPlayer(livePlayer)
	end

	return storedPresence
end

local function isPresenceOnline(entry)
	if type(entry) ~= "table" or entry.online ~= true then
		return false
	end

	local updatedAt = tonumber(entry.updatedAt) or tonumber(entry.lastSeenAt) or 0
	if updatedAt <= 0 then
		return false
	end

	return (nowSeconds() - updatedAt) <= PRESENCE_STALE_SECONDS
end

local function writePresence(player, isOnline)
	local currentTime = nowSeconds()
	local identity = buildIdentityFromPlayer(player)

	local ok, err = pcall(function()
		presenceStore:SetAsync(toUserIdKey(player.UserId), {
			displayName = identity.displayName,
			userName = identity.userName,
			online = isOnline,
			lastSeenAt = currentTime,
			updatedAt = currentTime,
			placeId = game.PlaceId,
			jobId = game.JobId,
		}, PRESENCE_TTL_SECONDS, currentTime)
	end)

	if not ok then
		warn(("[FriendService] Presence update failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function publishDispatch(payload)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(DISPATCH_TOPIC, payload)
	end)

	if not ok then
		warn(("[FriendService] Messaging publish failed: %s"):format(tostring(err)))
		return false
	end

	return true
end

local function buildSummaryLabel(displayName, userName)
	if displayName ~= userName then
		return ("%s (@%s)"):format(displayName, userName)
	end

	return displayName
end

local function buildRequestArray(rawMap, cooldownsByUserId)
	local items = {}

	for rawKey, rawEntry in pairs(rawMap) do
		local userId = normalizeUserId(rawKey)
		if userId ~= nil and type(rawEntry) == "table" then
			local identity = mergeIdentity(rawEntry, getPresenceForUser(userId), tostring(userId))
			table.insert(items, {
				userId = userId,
				displayName = identity.displayName,
				userName = identity.userName,
				label = buildSummaryLabel(identity.displayName, identity.userName),
				createdAt = math.max(0, tonumber(rawEntry.createdAt) or 0),
				blockedUntil = math.max(0, tonumber(cooldownsByUserId[toUserIdKey(userId)]) or 0),
			})
		end
	end

	table.sort(items, function(a, b)
		if a.createdAt == b.createdAt then
			return a.label < b.label
		end
		return a.createdAt > b.createdAt
	end)

	return items
end

local function buildFriendArray(rawMap)
	local items = {}

	for rawKey, rawEntry in pairs(rawMap) do
		local userId = normalizeUserId(rawKey)
		if userId ~= nil and type(rawEntry) == "table" then
			local presence = getPresenceForUser(userId)
			local identity = mergeIdentity(rawEntry, presence, tostring(userId))
			local lastSeenAt = math.max(
				math.max(0, tonumber(rawEntry.lastSeenAt) or 0),
				math.max(0, tonumber(presence and presence.lastSeenAt) or 0)
			)

			table.insert(items, {
				userId = userId,
				displayName = identity.displayName,
				userName = identity.userName,
				label = buildSummaryLabel(identity.displayName, identity.userName),
				since = math.max(0, tonumber(rawEntry.since) or 0),
				online = isPresenceOnline(presence),
				lastSeenAt = lastSeenAt,
				placeId = if type(presence) == "table" then tonumber(presence.placeId) else nil,
			})
		end
	end

	table.sort(items, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return a.label < b.label
	end)

	return items
end

local function buildConversationsPayload(rawMap)
	local payload = {}

	for rawKey, rawMessages in pairs(rawMap) do
		local userId = normalizeUserId(rawKey)
		if userId ~= nil and type(rawMessages) == "table" then
			local messages = {}

			for _, rawMessage in ipairs(rawMessages) do
				if type(rawMessage) == "table" then
					local fromUserId = normalizeUserId(rawMessage.fromUserId)
					if fromUserId ~= nil then
						table.insert(messages, {
							fromUserId = fromUserId,
							fromDisplayName = clampString(rawMessage.fromDisplayName, MAX_NAME_LENGTH, "Player"),
							body = clampString(rawMessage.body, MAX_MESSAGE_LENGTH, ""),
							createdAt = math.max(0, tonumber(rawMessage.createdAt) or 0),
						})
					end
				end
			end

			payload[toUserIdKey(userId)] = messages
		end
	end

	return payload
end

local function buildCooldownPayload(rawMap)
	local payload = {}
	local currentTime = nowSeconds()

	for rawKey, rawValue in pairs(rawMap) do
		local userId = normalizeUserId(rawKey)
		local expiresAt = tonumber(rawValue) or 0
		if userId ~= nil and expiresAt > currentTime then
			payload[toUserIdKey(userId)] = expiresAt
		end
	end

	return payload
end

local function buildStatePayloadFromSocial(player, social)
	local normalizedSocial = ensureSocialData(social)
	local cooldownPayload = buildCooldownPayload(normalizedSocial.requestCooldownsByUserId)
	local incomingRequests = buildRequestArray(normalizedSocial.incomingRequestsByUserId, cooldownPayload)
	local outgoingRequests = buildRequestArray(normalizedSocial.outgoingRequestsByUserId, cooldownPayload)
	local friends = buildFriendArray(normalizedSocial.friendsByUserId)

	return {
		success = true,
		playerUserId = player.UserId,
		incomingRequests = incomingRequests,
		outgoingRequests = outgoingRequests,
		friends = friends,
		requestCooldownsByUserId = cooldownPayload,
		conversationsByUserId = buildConversationsPayload(normalizedSocial.conversationsByUserId),
		summary = {
			friendCount = #friends,
			incomingCount = #incomingRequests,
			outgoingCount = #outgoingRequests,
		},
	}
end

local function buildStatePayload(player)
	PlayerDataService.waitForData(player)
	return buildStatePayloadFromSocial(player, PlayerDataService.get(player, { "social" }))
end

local function fireStatePayload(player, payload)
	if not friendStateRemote or player.Parent ~= Players then
		return
	end

	friendStateRemote:FireClient(player, payload)
end

local function pushState(player)
	if not friendStateRemote or player.Parent ~= Players then
		return
	end

	local ok, payload = pcall(buildStatePayload, player)
	if not ok then
		warn(("[FriendService] Failed to build state for %s: %s"):format(player.Name, tostring(payload)))
		return
	end

	fireStatePayload(player, payload)
end

local function notifyFriendsPresenceChanged(player)
	PlayerDataService.waitForData(player)
	local social = ensureSocialData(PlayerDataService.get(player, { "social" }))

	for rawKey in pairs(social.friendsByUserId) do
		local friendUserId = normalizeUserId(rawKey)
		if friendUserId == nil then
			continue
		end

		local friendPlayer = Players:GetPlayerByUserId(friendUserId)
		if friendPlayer then
			pushState(friendPlayer)
		elseif isPresenceOnline(readPresence(friendUserId)) then
			publishDispatch({
				targetUserId = friendUserId,
				kind = "PresenceRefresh",
			})
		end
	end
end

local function pushStateFromSocial(player, social)
	if not friendStateRemote or player.Parent ~= Players then
		return
	end

	local ok, payload = pcall(buildStatePayloadFromSocial, player, social)
	if not ok then
		warn(("[FriendService] Failed to build updated state for %s: %s"):format(player.Name, tostring(payload)))
		return
	end

	fireStatePayload(player, payload)
end

local function mutatePlayerSocialAndPush(player, callback)
	local updatedSocial = mutatePlayerSocial(player, callback)
	if type(updatedSocial) == "table" then
		pushStateFromSocial(player, updatedSocial)
		return updatedSocial
	end

	pushState(player)
	return nil
end

local function applyIncomingRequestToSocial(social, fromUserId, identity, sentAt)
	local senderKey = toUserIdKey(fromUserId)
	if social.friendsByUserId[senderKey] then
		return
	end

	social.incomingRequestsByUserId[senderKey] = {
		displayName = identity.displayName,
		userName = identity.userName,
		createdAt = sentAt,
	}
end

local function applyAcceptedFriendshipToSocial(social, otherUserId, identity, acceptedAt)
	local otherKey = toUserIdKey(otherUserId)
	social.incomingRequestsByUserId[otherKey] = nil
	social.outgoingRequestsByUserId[otherKey] = nil
	social.requestCooldownsByUserId[otherKey] = nil
	social.friendsByUserId[otherKey] = {
		displayName = identity.displayName,
		userName = identity.userName,
		since = acceptedAt,
		lastSeenAt = acceptedAt,
	}
end

local function applyRejectedRequestToSocial(social, otherUserId, cooldownUntil)
	local otherKey = toUserIdKey(otherUserId)
	social.outgoingRequestsByUserId[otherKey] = nil
	social.requestCooldownsByUserId[otherKey] = cooldownUntil
end

local function applyRemovedFriendshipToSocial(social, otherUserId)
	local otherKey = toUserIdKey(otherUserId)
	social.friendsByUserId[otherKey] = nil
	social.conversationsByUserId[otherKey] = nil
end

local function applyConversationToSocial(social, otherUserId, messageEntry)
	appendConversationMessage(social, otherUserId, messageEntry)
end

local function deliverToUser(targetUserId, remotePayload, localCallback, offlineCallback)
	local livePlayer = Players:GetPlayerByUserId(targetUserId)
	if livePlayer then
		local updatedSocial = localCallback(livePlayer)
		if type(updatedSocial) == "table" then
			pushStateFromSocial(livePlayer, updatedSocial)
		else
			pushState(livePlayer)
		end
		return true
	end

	local presence = readPresence(targetUserId)
	local success, errorMessage = mutateOfflineSocial(targetUserId, offlineCallback)
	if success then
		return true
	end

	if isPresenceOnline(presence) or shouldFallbackToDispatch(errorMessage) then
		return publishDispatch(remotePayload)
	end

	warn(("[FriendService] Could not update user %s: %s"):format(tostring(targetUserId), tostring(errorMessage)))
	return false
end

local function filterOutgoingMessage(player, rawMessage)
	local trimmed = clampString(rawMessage, MAX_MESSAGE_LENGTH, "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	if trimmed == "" then
		return nil, "Enter a message first."
	end

	local ok, filteredOrError = pcall(function()
		local result = TextService:FilterStringAsync(trimmed, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)

	if not ok or type(filteredOrError) ~= "string" then
		return nil, "Message filtering failed."
	end

	local filtered = clampString(filteredOrError, MAX_MESSAGE_LENGTH, "")
	if filtered == "" then
		return nil, "Message is empty after filtering."
	end

	return filtered, nil
end

local function findLivePlayerByLookupName(targetName)
	local exactMatches = {}
	local prefixMatches = {}
	local targetNameLower = string.lower(targetName)

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local userNameLower = string.lower(otherPlayer.Name)
		local displayNameLower = string.lower(otherPlayer.DisplayName)
		local isExactMatch = userNameLower == targetNameLower or displayNameLower == targetNameLower
		local isPrefixMatch = startsWithIgnoreCase(otherPlayer.Name, targetNameLower)
			or startsWithIgnoreCase(otherPlayer.DisplayName, targetNameLower)

		if isExactMatch then
			table.insert(exactMatches, otherPlayer)
		elseif isPrefixMatch then
			table.insert(prefixMatches, otherPlayer)
		end
	end

	if #exactMatches == 1 then
		return exactMatches[1], nil
	end
	if #exactMatches > 1 then
		return nil, "More than one player matches that name. Use the exact @username."
	end
	if #prefixMatches == 1 then
		return prefixMatches[1], nil
	end
	if #prefixMatches > 1 then
		return nil, "More than one player matches that name. Use the exact @username."
	end

	return nil, nil
end

local function resolveRequestTarget(payload)
	local targetUserId = normalizeUserId(payload and payload.targetUserId)
	if targetUserId ~= nil then
		return targetUserId, nil, nil
	end

	local targetName = normalizeLookupName(payload and payload.targetName)
	if targetName == "" then
		return nil, nil, "Choose a player first."
	end

	local livePlayer, liveLookupError = findLivePlayerByLookupName(targetName)
	if liveLookupError then
		return nil, nil, liveLookupError
	end
	if livePlayer then
		return livePlayer.UserId, buildIdentityFromPlayer(livePlayer), nil
	end

	local ok, resolvedUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(targetName)
	end)
	if not ok then
		return nil, nil, "Could not find that player. Use their exact username."
	end

	return resolvedUserId, buildIdentity(targetName, targetName, targetName), nil
end

local function handleSendRequest(player, payload)
	local targetUserId, resolvedTargetIdentity, lookupError = resolveRequestTarget(payload)
	if targetUserId == nil then
		return { success = false, message = lookupError or "Choose a player first." }
	end

	if targetUserId == player.UserId then
		return { success = false, message = "You cannot friend yourself." }
	end

	PlayerDataService.waitForData(player)
	local social = ensureSocialData(PlayerDataService.get(player, { "social" }))
	local targetKey = toUserIdKey(targetUserId)

	if social.friendsByUserId[targetKey] then
		return { success = false, message = "You are already friends." }
	end

	if social.outgoingRequestsByUserId[targetKey] then
		return { success = false, message = "Friend request already sent." }
	end

	if social.incomingRequestsByUserId[targetKey] then
		return { success = false, message = "They already sent you a request." }
	end

	local cooldownUntil = getActiveCooldown(social, targetUserId)
	if cooldownUntil > 0 then
		local remainingSeconds = math.max(0, cooldownUntil - nowSeconds())
		local remainingMinutes = math.max(1, math.ceil(remainingSeconds / 60))
		return {
			success = false,
			message = ("You can try again in about %d minute(s)."):format(remainingMinutes),
		}
	end

	local senderIdentity = buildIdentityFromPlayer(player)
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	local targetPresence = readPresence(targetUserId)
	local fallbackTargetIdentity = resolvedTargetIdentity or buildIdentity(
		payload and payload.targetDisplayName,
		payload and payload.targetUserName,
		"Player"
	)
	local targetIdentity = if targetPlayer
		then buildIdentityFromPlayer(targetPlayer)
		else mergeIdentity(fallbackTargetIdentity, targetPresence, "Player")
	local sentAt = nowSeconds()

	local delivered = deliverToUser(
		targetUserId,
		{
			targetUserId = targetUserId,
			kind = "IncomingRequest",
			fromUserId = player.UserId,
			fromDisplayName = senderIdentity.displayName,
			fromUserName = senderIdentity.userName,
			sentAt = sentAt,
		},
		function(otherPlayer)
			return mutatePlayerSocial(otherPlayer, function(otherSocial)
				applyIncomingRequestToSocial(otherSocial, player.UserId, senderIdentity, sentAt)
			end)
		end,
		function(otherSocial)
			applyIncomingRequestToSocial(otherSocial, player.UserId, senderIdentity, sentAt)
		end
	)

	if not delivered then
		return { success = false, message = "That player could not receive your request." }
	end

	mutatePlayerSocialAndPush(player, function(currentSocial)
		currentSocial.outgoingRequestsByUserId[targetKey] = {
			displayName = targetIdentity.displayName,
			userName = targetIdentity.userName,
			createdAt = sentAt,
		}
		currentSocial.requestCooldownsByUserId[targetKey] = nil
	end)

	return { success = true, message = "Friend request sent." }
end

local function handleRespondToRequest(player, payload)
	local targetUserId = normalizeUserId(payload and payload.targetUserId)
	if targetUserId == nil then
		return { success = false, message = "Choose a request first." }
	end

	local acceptRequest = payload and payload.accept == true
	local requesterKey = toUserIdKey(targetUserId)

	PlayerDataService.waitForData(player)
	local social = ensureSocialData(PlayerDataService.get(player, { "social" }))
	local incomingEntry = social.incomingRequestsByUserId[requesterKey]
	if type(incomingEntry) ~= "table" then
		return { success = false, message = "That request is no longer pending." }
	end

	local requesterPlayer = Players:GetPlayerByUserId(targetUserId)
	local requesterPresence = readPresence(targetUserId)
	local requesterIdentity = if requesterPlayer
		then buildIdentityFromPlayer(requesterPlayer)
		else mergeIdentity(incomingEntry, requesterPresence, tostring(targetUserId))

	if acceptRequest then
		local acceptedAt = nowSeconds()
		local myIdentity = buildIdentityFromPlayer(player)
		local delivered = deliverToUser(
			targetUserId,
			{
				targetUserId = targetUserId,
				kind = "AcceptedFriendship",
				otherUserId = player.UserId,
				otherDisplayName = myIdentity.displayName,
				otherUserName = myIdentity.userName,
				acceptedAt = acceptedAt,
			},
			function(otherPlayer)
				return mutatePlayerSocial(otherPlayer, function(otherSocial)
					applyAcceptedFriendshipToSocial(otherSocial, player.UserId, myIdentity, acceptedAt)
				end)
			end,
			function(otherSocial)
				applyAcceptedFriendshipToSocial(otherSocial, player.UserId, myIdentity, acceptedAt)
			end
		)

		if not delivered then
			return { success = false, message = "Could not finish the friendship right now." }
		end

		mutatePlayerSocialAndPush(player, function(currentSocial)
			applyAcceptedFriendshipToSocial(currentSocial, targetUserId, requesterIdentity, acceptedAt)
		end)

		return { success = true, message = "Friend added." }
	end

	local cooldownUntil = nowSeconds() + REQUEST_BLOCK_SECONDS
	local delivered = deliverToUser(
		targetUserId,
		{
			targetUserId = targetUserId,
			kind = "RejectedRequest",
			otherUserId = player.UserId,
			cooldownUntil = cooldownUntil,
		},
		function(otherPlayer)
			return mutatePlayerSocial(otherPlayer, function(otherSocial)
				applyRejectedRequestToSocial(otherSocial, player.UserId, cooldownUntil)
			end)
		end,
		function(otherSocial)
			applyRejectedRequestToSocial(otherSocial, player.UserId, cooldownUntil)
		end
	)

	if not delivered then
		return { success = false, message = "Could not reject that request right now." }
	end

	mutatePlayerSocialAndPush(player, function(currentSocial)
		currentSocial.incomingRequestsByUserId[requesterKey] = nil
		currentSocial.outgoingRequestsByUserId[requesterKey] = nil
	end)

	return { success = true, message = "Request declined." }
end

local function handleSendMessage(player, payload)
	local targetUserId = normalizeUserId(payload and payload.targetUserId)
	if targetUserId == nil then
		return { success = false, message = "Choose a friend first." }
	end

	PlayerDataService.waitForData(player)
	local social = ensureSocialData(PlayerDataService.get(player, { "social" }))
	local targetKey = toUserIdKey(targetUserId)
	local friendEntry = social.friendsByUserId[targetKey]
	if type(friendEntry) ~= "table" then
		return { success = false, message = "You can only message current friends." }
	end

	local filteredBody, filterError = filterOutgoingMessage(player, payload and payload.message)
	if filteredBody == nil then
		return { success = false, message = filterError }
	end

	local sentAt = nowSeconds()
	local senderIdentity = buildIdentityFromPlayer(player)
	local messageEntry = {
		fromUserId = player.UserId,
		fromDisplayName = senderIdentity.displayName,
		body = filteredBody,
		createdAt = sentAt,
	}

	local delivered = deliverToUser(
		targetUserId,
		{
			targetUserId = targetUserId,
			kind = "IncomingMessage",
			otherUserId = player.UserId,
			otherDisplayName = senderIdentity.displayName,
			body = filteredBody,
			sentAt = sentAt,
		},
		function(otherPlayer)
			return mutatePlayerSocial(otherPlayer, function(otherSocial)
				if not otherSocial.friendsByUserId[toUserIdKey(player.UserId)] then
					return
				end
				applyConversationToSocial(otherSocial, player.UserId, messageEntry)
			end)
		end,
		function(otherSocial)
			if not otherSocial.friendsByUserId[toUserIdKey(player.UserId)] then
				return
			end
			applyConversationToSocial(otherSocial, player.UserId, messageEntry)
		end
	)

	if not delivered then
		return { success = false, message = "Your friend could not receive that message." }
	end

	mutatePlayerSocialAndPush(player, function(currentSocial)
		applyConversationToSocial(currentSocial, targetUserId, messageEntry)
	end)

	return { success = true, message = "Message sent." }
end

local function handleRemoveFriend(player, payload)
	local targetUserId = normalizeUserId(payload and payload.targetUserId)
	if targetUserId == nil then
		return { success = false, message = "Choose a friend first." }
	end

	PlayerDataService.waitForData(player)
	local social = ensureSocialData(PlayerDataService.get(player, { "social" }))
	local targetKey = toUserIdKey(targetUserId)
	if type(social.friendsByUserId[targetKey]) ~= "table" then
		return { success = false, message = "That player is not in your friends list." }
	end

	mutatePlayerSocialAndPush(player, function(currentSocial)
		applyRemovedFriendshipToSocial(currentSocial, targetUserId)
	end)

	local delivered = deliverToUser(
		targetUserId,
		{
			targetUserId = targetUserId,
			kind = "RemovedFriendship",
			otherUserId = player.UserId,
		},
		function(otherPlayer)
			return mutatePlayerSocial(otherPlayer, function(otherSocial)
				applyRemovedFriendshipToSocial(otherSocial, player.UserId)
			end)
		end,
		function(otherSocial)
			applyRemovedFriendshipToSocial(otherSocial, player.UserId)
		end
	)

	if not delivered then
		warn(
			("[FriendService] Removed %s from %s locally, but could not sync the other side right now.")
				:format(tostring(targetUserId), player.Name)
		)
	end

	return { success = true, message = "Friend removed." }
end

local function handleAction(player, payload)
	if not player or not player:IsA("Player") then
		return { success = false, message = "Invalid player." }
	end

	if type(payload) ~= "table" then
		return { success = false, message = "Invalid request." }
	end

	local actionName = payload.action
	if actionName == "sendRequest" then
		return handleSendRequest(player, payload)
	end
	if actionName == "respondRequest" then
		return handleRespondToRequest(player, payload)
	end
	if actionName == "sendMessage" then
		return handleSendMessage(player, payload)
	end
	if actionName == "removeFriend" then
		return handleRemoveFriend(player, payload)
	end

	return { success = false, message = "Unknown action." }
end

local function applyDispatch(payload)
	if type(payload) ~= "table" then
		return
	end

	local targetUserId = normalizeUserId(payload.targetUserId)
	if targetUserId == nil then
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return
	end

	local actionName = payload.kind
	if actionName == "IncomingRequest" then
		local fromUserId = normalizeUserId(payload.fromUserId)
		if fromUserId == nil then
			return
		end

		local identity = buildIdentity(payload.fromDisplayName, payload.fromUserName, "Player")
		local sentAt = math.max(0, tonumber(payload.sentAt) or nowSeconds())
		mutatePlayerSocialAndPush(targetPlayer, function(social)
			applyIncomingRequestToSocial(social, fromUserId, identity, sentAt)
		end)
		return
	end

	if actionName == "AcceptedFriendship" then
		local otherUserId = normalizeUserId(payload.otherUserId)
		if otherUserId == nil then
			return
		end

		local identity = buildIdentity(payload.otherDisplayName, payload.otherUserName, "Player")
		local acceptedAt = math.max(0, tonumber(payload.acceptedAt) or nowSeconds())
		mutatePlayerSocialAndPush(targetPlayer, function(social)
			applyAcceptedFriendshipToSocial(social, otherUserId, identity, acceptedAt)
		end)
		return
	end

	if actionName == "RejectedRequest" then
		local otherUserId = normalizeUserId(payload.otherUserId)
		if otherUserId == nil then
			return
		end

		local cooldownUntil = math.max(nowSeconds(), tonumber(payload.cooldownUntil) or nowSeconds())
		mutatePlayerSocialAndPush(targetPlayer, function(social)
			applyRejectedRequestToSocial(social, otherUserId, cooldownUntil)
		end)
		return
	end

	if actionName == "RemovedFriendship" then
		local otherUserId = normalizeUserId(payload.otherUserId)
		if otherUserId == nil then
			return
		end

		mutatePlayerSocialAndPush(targetPlayer, function(social)
			applyRemovedFriendshipToSocial(social, otherUserId)
		end)
		return
	end

	if actionName == "PresenceRefresh" then
		pushState(targetPlayer)
		return
	end

	if actionName == "IncomingMessage" then
		local otherUserId = normalizeUserId(payload.otherUserId)
		if otherUserId == nil then
			return
		end

		local entry = {
			fromUserId = otherUserId,
			fromDisplayName = clampString(payload.otherDisplayName, MAX_NAME_LENGTH, "Player"),
			body = clampString(payload.body, MAX_MESSAGE_LENGTH, ""),
			createdAt = math.max(0, tonumber(payload.sentAt) or nowSeconds()),
		}

		mutatePlayerSocialAndPush(targetPlayer, function(social)
			if not social.friendsByUserId[toUserIdKey(otherUserId)] then
				return
			end
			applyConversationToSocial(social, otherUserId, entry)
		end)
	end
end

local function startPresenceHeartbeat()
	task.spawn(function()
		while started do
			task.wait(PRESENCE_HEARTBEAT_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				writePresence(player, true)
			end
		end
	end)
end

local function subscribeToDispatch()
	if dispatchSubscription ~= nil then
		return
	end

	local ok, subscriptionOrError = pcall(function()
		return MessagingService:SubscribeAsync(DISPATCH_TOPIC, function(message)
			applyDispatch(message.Data)
		end)
	end)

	if not ok then
		warn(("[FriendService] Messaging subscribe failed: %s"):format(tostring(subscriptionOrError)))
		return
	end

	dispatchSubscription = subscriptionOrError
end

local function onPlayerAdded(player)
	task.spawn(function()
		ensurePlayerSocial(player)
		writePresence(player, true)
		pushState(player)
		notifyFriendsPresenceChanged(player)
	end)
end

local function onPlayerRemoving(player)
	writePresence(player, false)
	notifyFriendsPresenceChanged(player)
end

function FriendService.start()
	if started then
		return
	end

	if not PlayerDataService.isReady() then
		warn("[FriendService] PlayerDataService not ready; call PlayerDataService.start() first.")
		return
	end

	started = true
	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = Config.Remotes.Folder
		remotesFolder.Parent = ReplicatedStorage
	end

	friendGetStateFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.FriendGetState)
	friendActionFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.FriendAction)
	friendStateRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.FriendState)

	friendGetStateFunction.OnServerInvoke = function(player)
		if not player or not player:IsA("Player") then
			return { success = false, message = "Invalid player." }
		end

		return buildStatePayload(player)
	end

	friendActionFunction.OnServerInvoke = function(player, payload)
		return handleAction(player, payload)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	subscribeToDispatch()
	startPresenceHeartbeat()

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			writePresence(player, false)
		end
	end)
end

return FriendService
