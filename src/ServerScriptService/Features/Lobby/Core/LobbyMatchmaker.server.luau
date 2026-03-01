local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local PLACEHOLDER_PLACE_ID = 1234567890
local Shared = ServerScriptService:WaitForChild("Shared")
local PlaceRole = require(Shared:WaitForChild("Matchmaking"):WaitForChild("PlaceRole"))
local Config = require(Shared:WaitForChild("Matchmaking"):WaitForChild("MatchmakingConfig"))
local matchServers = MemoryStoreService:GetSortedMap(Config.MEMORYSTORE_MAP_NAME)
local randomGenerator = Random.new()

if not PlaceRole.shouldRunLobbySystems() then
	warn(("[LobbyMatchmaker] Skipping lobby systems for place role '%s' (placeId=%s, privateServer=%s)."):format(
		PlaceRole.getRole(),
		tostring(game.PlaceId),
		tostring(game.PrivateServerId ~= "")
	))
	return
end

local wiredButtons = {}
local inFlightByUser = {}
local lastRequestByUser = {}

local function nowSeconds()
	return os.time()
end

local function toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end
	return n
end

local function safeCall(label, callback)
	local ok, resultA, resultB, resultC = pcall(callback)
	if not ok then
		warn(("[LobbyMatchmaker] %s failed: %s"):format(label, tostring(resultA)))
		return false, nil, nil, nil
	end
	return true, resultA, resultB, resultC
end
local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteEvent(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end

		warn(("[LobbyMatchmaker] Expected RemoteEvent at %s/%s, got %s"):format(
			parent.Name,
			name,
			existing.ClassName
		))
		return nil
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local teleportLoadingRemote = ensureRemoteEvent(
	ensureFolder(ReplicatedStorage, GameConfig.Remotes.Folder),
	GameConfig.Remotes.TeleportLoading
)

local function notifyTeleportStarting(player, title, message)
	if not teleportLoadingRemote then
		return
	end

	teleportLoadingRemote:FireClient(player, {
		action = "Start",
		title = title,
		message = message,
	})

	-- Give the client a moment to call SetTeleportGui before TeleportAsync.
	task.wait(0.1)
end

local function notifyTeleportFailed(player, message)
	if not teleportLoadingRemote then
		return
	end

	teleportLoadingRemote:FireClient(player, {
		action = "Failed",
		message = message,
	})
end
local function addMatchPlaceId(placeIds, placeIdLookup, rawPlaceId)
	local placeId = toNumber(rawPlaceId, nil)
	if placeId == nil then
		return
	end

	if placeId ~= math.floor(placeId) then
		warn(("[LobbyMatchmaker] Ignoring non-integer place id '%s'."):format(tostring(rawPlaceId)))
		return
	end

	if placeId <= 0 then
		warn(("[LobbyMatchmaker] Ignoring invalid place id '%s'."):format(tostring(rawPlaceId)))
		return
	end

	if placeId == PLACEHOLDER_PLACE_ID then
		warn("[LobbyMatchmaker] Ignoring template placeholder place id 1234567890.")
		return
	end

	if placeIdLookup[placeId] then
		return
	end

	placeIdLookup[placeId] = true
	table.insert(placeIds, placeId)
end

local function collectMatchPlaceIds()
	local placeIds = {}
	local placeIdLookup = {}

	if type(Config.MATCH_PLACE_IDS) == "table" then
		for _, rawPlaceId in ipairs(Config.MATCH_PLACE_IDS) do
			addMatchPlaceId(placeIds, placeIdLookup, rawPlaceId)
		end
	end

	if #placeIds == 0 then
		addMatchPlaceId(placeIds, placeIdLookup, Config.MATCH_PLACE_ID)
	end

	if #placeIds == 0 then
		warn("[LobbyMatchmaker] No valid match place IDs configured. Set MATCH_PLACE_IDS in MatchmakingConfig.")
	end

	return placeIds, placeIdLookup
end

local matchPlaceIds, matchPlaceIdLookup = collectMatchPlaceIds()

local function hasConfiguredMatchPlaces()
	return #matchPlaceIds > 0
end

local function chooseRandomMatchPlaceId()
	if #matchPlaceIds == 0 then
		return nil
	end

	if #matchPlaceIds == 1 then
		return matchPlaceIds[1]
	end

	local randomIndex = randomGenerator:NextInteger(1, #matchPlaceIds)
	return matchPlaceIds[randomIndex]
end

local function resolveEntryPlaceId(value)
	local placeId = toNumber(value and value.placeId, nil)
	if placeId == nil and #matchPlaceIds == 1 then
		-- Backward compatibility with old entries that predate placeId field.
		placeId = matchPlaceIds[1]
	end
	if placeId == nil then
		return nil
	end

	if placeId ~= math.floor(placeId) then
		return nil
	end

	if not matchPlaceIdLookup[placeId] then
		return nil
	end

	return placeId
end

local function removeServerEntry(serverKey)
	safeCall(("RemoveAsync(%s)"):format(serverKey), function()
		matchServers:RemoveAsync(serverKey)
	end)
end

local function fetchCandidateServers(difficulty)
	local candidates = {}
	local currentTime = nowSeconds()

	local ok, entries = safeCall("GetRangeAsync", function()
		return matchServers:GetRangeAsync(Enum.SortDirection.Descending, Config.SCAN_PAGE_SIZE)
	end)
	if not ok or type(entries) ~= "table" then
		return candidates
	end

	for _, entry in ipairs(entries) do
		local serverKey = entry.key
		local value = entry.value
		if type(serverKey) ~= "string" then
			continue
		end

		if type(value) ~= "table" then
			continue
		end

		local heartbeat = toNumber(value.lastHeartbeat, 0)
		if (currentTime - heartbeat) > Config.STALE_AFTER_SECONDS then
			removeServerEntry(serverKey)
			continue
		end

		if value.difficulty ~= difficulty then
			continue
		end

		if type(value.accessCode) ~= "string" or value.accessCode == "" then
			continue
		end

		local placeId = resolveEntryPlaceId(value)
		if placeId == nil then
			continue
		end

		local playerCount = math.max(toNumber(value.playerCount, 0), 0)
		local pendingSlots = math.max(toNumber(value.pendingSlots, 0), 0)
		local maxPlayers = math.max(toNumber(value.maxPlayers, 0), 0)
		local effectiveCount = playerCount + pendingSlots

		if maxPlayers > 0 and effectiveCount < maxPlayers then
			table.insert(candidates, {
				key = serverKey,
				placeId = placeId,
				accessCode = value.accessCode,
				effectiveCount = effectiveCount,
			})
		end
	end

	-- Pack players into already-running matches before creating new ones.
	table.sort(candidates, function(a, b)
		return a.effectiveCount > b.effectiveCount
	end)

	return candidates
end

local function reserveSlot(serverKey, difficulty)
	local didReserve = false
	local accessCode
	local reservedPlaceId

	local ok = safeCall(("UpdateAsync reserve %s"):format(serverKey), function()
		matchServers:UpdateAsync(serverKey, function(oldValue, oldSortKey)
			if type(oldValue) ~= "table" then
				return nil
			end

			if oldValue.difficulty ~= difficulty then
				return oldValue, oldSortKey
			end

			local placeId = resolveEntryPlaceId(oldValue)
			if placeId == nil then
				return oldValue, oldSortKey
			end

			local currentTime = nowSeconds()
			local heartbeat = toNumber(oldValue.lastHeartbeat, 0)
			if (currentTime - heartbeat) > Config.STALE_AFTER_SECONDS then
				return nil
			end

			local maxPlayers = math.max(toNumber(oldValue.maxPlayers, 0), 0)
			local playerCount = math.max(toNumber(oldValue.playerCount, 0), 0)
			local pendingSlots = math.max(toNumber(oldValue.pendingSlots, 0), 0)
			if maxPlayers <= 0 or (playerCount + pendingSlots) >= maxPlayers then
				return oldValue, oldSortKey
			end

			oldValue.placeId = placeId
			oldValue.pendingSlots = pendingSlots + 1
			oldValue.lastHeartbeat = currentTime

			didReserve = true
			accessCode = oldValue.accessCode
			reservedPlaceId = placeId

			return oldValue, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end)

	if not ok then
		return false, nil, nil
	end

	return didReserve, accessCode, reservedPlaceId
end

local function releaseSlot(serverKey)
	safeCall(("UpdateAsync release %s"):format(serverKey), function()
		matchServers:UpdateAsync(serverKey, function(oldValue, oldSortKey)
			if type(oldValue) ~= "table" then
				return nil
			end

			local pendingSlots = math.max(toNumber(oldValue.pendingSlots, 0), 0)
			oldValue.pendingSlots = math.max(pendingSlots - 1, 0)
			oldValue.lastHeartbeat = nowSeconds()

			return oldValue, oldSortKey
		end, Config.ENTRY_TTL_SECONDS)
	end)
end

local function teleportToReservedServer(player, placeId, difficulty, matchId, accessCode)
	if player.Parent ~= Players then
		return false
	end

	if not matchPlaceIdLookup[placeId] then
		warn(("[LobbyMatchmaker] Target placeId %s is not in MATCH_PLACE_IDS. Teleport canceled."):format(tostring(placeId)))
		return false
	end

	warn(("[LobbyMatchmaker] Teleporting %s -> placeId=%s difficulty=%s matchId=%s"):format(
		player.Name,
		tostring(placeId),
		tostring(difficulty),
		tostring(matchId)
	))

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		difficulty = difficulty,
		matchId = matchId,
		placeId = placeId,
		fromPlaceId = game.PlaceId,
		queuedAt = nowSeconds(),
	})

	local retries = math.max(1, toNumber(Config.TELEPORT_RETRIES, 1))
	notifyTeleportStarting(
	player,
	"Joining match",
	string.format("Teleporting to %s difficulty...", tostring(difficulty))
	)
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, {player}, options)
		end)
		if ok then
			warn(("[LobbyMatchmaker] TeleportAsync succeeded for %s"):format(player.Name))
			return true
		end

		warn(("[LobbyMatchmaker] TeleportAsync failed (attempt %d) for %s: %s"):format(
			attempt,
			player.Name,
			tostring(err)
		))

		if attempt < retries then
			task.wait(Config.TELEPORT_RETRY_DELAY_SECONDS)
		end
	end

	notifyTeleportFailed(player, "Could not join the match. Please try again.")
	return false
end

local function createReservedServer(difficulty)
	if not hasConfiguredMatchPlaces() then
		warn("[LobbyMatchmaker] MATCH_PLACE_IDS is empty. Cannot reserve server.")
		return nil, nil, nil
	end

	local placeId = chooseRandomMatchPlaceId()
	if placeId == nil then
		warn("[LobbyMatchmaker] Could not choose a match place id.")
		return nil, nil, nil
	end

	local maxPlayers = Config.getMaxPlayersForDifficulty(difficulty, Players.MaxPlayers)
	if maxPlayers <= 0 then
		warn(("[LobbyMatchmaker] Max players missing for difficulty '%s'"):format(tostring(difficulty)))
		return nil, nil, nil
	end

	local ok, accessCode, privateServerId = safeCall("ReserveServer", function()
		if type(TeleportService.ReserveServerAsync) == "function" then
			return TeleportService:ReserveServerAsync(placeId)
		end

		return TeleportService:ReserveServer(placeId)
	end)
	if not ok then
		return nil, nil, nil
	end

	if type(accessCode) ~= "string" or accessCode == "" then
		warn("[LobbyMatchmaker] ReserveServer returned an invalid access code.")
		return nil, nil, nil
	end
	if type(privateServerId) ~= "string" or privateServerId == "" then
		warn("[LobbyMatchmaker] ReserveServer returned an invalid private server id.")
		return nil, nil, nil
	end

	local currentTime = nowSeconds()
	local entry = {
		difficulty = difficulty,
		placeId = placeId,
		accessCode = accessCode,
		privateServerId = privateServerId,
		playerCount = 0,
		pendingSlots = 1,
		maxPlayers = maxPlayers,
		lastHeartbeat = currentTime,
		createdAt = currentTime,
	}

	local setOk = safeCall(("SetAsync(%s)"):format(privateServerId), function()
		matchServers:SetAsync(privateServerId, entry, Config.ENTRY_TTL_SECONDS, currentTime)
	end)
	if not setOk then
		return nil, nil, nil
	end

	return privateServerId, accessCode, placeId
end

local function sendPlayerToDifficulty(player, difficulty)
	if not hasConfiguredMatchPlaces() then
		return false
	end

	if player.Parent ~= Players then
		return false
	end

	local candidates = fetchCandidateServers(difficulty)

	for _, candidate in ipairs(candidates) do
		local reserved, accessCode, placeId = reserveSlot(candidate.key, difficulty)
		if reserved and accessCode and placeId then
			local didTeleport = teleportToReservedServer(player, placeId, difficulty, candidate.key, accessCode)
			if didTeleport then
				return true
			end

			releaseSlot(candidate.key)
		end
	end

	local matchId, accessCode, placeId = createReservedServer(difficulty)
	if not matchId or not accessCode or not placeId then
		return false
	end

	local didTeleport = teleportToReservedServer(player, placeId, difficulty, matchId, accessCode)
	if didTeleport then
		return true
	end

	removeServerEntry(matchId)
	return false
end

local function onPromptTriggered(player, difficulty)
	if not Config.isDifficulty(difficulty) then
		warn(("[LobbyMatchmaker] Prompt triggered with invalid difficulty '%s'"):format(tostring(difficulty)))
		return
	end

	local userId = player.UserId
	if inFlightByUser[userId] then
		return
	end

	local currentTime = nowSeconds()
	local previous = toNumber(lastRequestByUser[userId], 0)
	if (currentTime - previous) < Config.REQUEST_COOLDOWN_SECONDS then
		return
	end
	lastRequestByUser[userId] = currentTime

	inFlightByUser[userId] = true
	local ok, didRoute = pcall(sendPlayerToDifficulty, player, difficulty)
	inFlightByUser[userId] = nil

	if not ok then
		warn(("[LobbyMatchmaker] Failed to route %s to difficulty '%s': %s"):format(
			player.Name,
			difficulty,
			tostring(didRoute)
		))
		return
	end

	if not didRoute then
		warn(("[LobbyMatchmaker] Failed to route %s to difficulty '%s'"):format(player.Name, difficulty))
	end
end

local function resolveButtonDifficulty(buttonPart)
	local attributeName = Config.BUTTON_DIFFICULTY_ATTRIBUTE
	if type(attributeName) == "string" and attributeName ~= "" then
		local difficultyFromAttribute = buttonPart:GetAttribute(attributeName)
		if type(difficultyFromAttribute) == "string" and difficultyFromAttribute ~= "" then
			return difficultyFromAttribute
		end
	end

	return buttonPart.Name
end

local function wireButton(buttonPart)
	if wiredButtons[buttonPart] then
		return
	end

	local difficulty = resolveButtonDifficulty(buttonPart)
	if not Config.isDifficulty(difficulty) then
		warn(("[LobbyMatchmaker] Ignoring button '%s'. Expected configured difficulty name."):format(buttonPart.Name))
		return
	end

	local prompt = buttonPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = buttonPart
	end

	prompt.ActionText = "Join"
	prompt.ObjectText = difficulty
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Config.PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = Config.PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false

	prompt.Triggered:Connect(function(player)
		onPromptTriggered(player, difficulty)
	end)

	wiredButtons[buttonPart] = true
end

local buttonsFolder = Workspace:FindFirstChild(Config.BUTTONS_FOLDER_NAME)
if not buttonsFolder then
	buttonsFolder = Workspace:WaitForChild(Config.BUTTONS_FOLDER_NAME, 30)
end

if not buttonsFolder then
	warn(("[LobbyMatchmaker] Missing Workspace/%s folder. Lobby buttons were not wired."):format(
		Config.BUTTONS_FOLDER_NAME
	))
	return
end

for _, child in ipairs(buttonsFolder:GetChildren()) do
	if child:IsA("BasePart") then
		wireButton(child)
	end
end

buttonsFolder.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		wireButton(child)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	inFlightByUser[player.UserId] = nil
	lastRequestByUser[player.UserId] = nil
end)
