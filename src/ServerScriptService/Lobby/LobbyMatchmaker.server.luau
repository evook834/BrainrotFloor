local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local function resolveConfigModule()
	local localConfig = script.Parent:FindFirstChild("MatchmakingConfig")
	if localConfig and localConfig:IsA("ModuleScript") then
		return localConfig
	end

	local fallbackConfig = ServerScriptService:FindFirstChild("MatchmakingConfig")
	if fallbackConfig and fallbackConfig:IsA("ModuleScript") then
		return fallbackConfig
	end

	return nil
end

local function requireConfig()
	local configInstance = resolveConfigModule()
	if not configInstance then
		error("[LobbyMatchmaker] Missing MatchmakingConfig ModuleScript. Expected Lobby/MatchmakingConfig.")
	end

	return require(configInstance)
end

local Config = requireConfig()
local matchServers = MemoryStoreService:GetSortedMap(Config.MEMORYSTORE_MAP_NAME)
local matchPlaceId = tonumber(Config.MATCH_PLACE_ID)

if matchPlaceId == 1234567890 then
	warn("[LobbyMatchmaker] Config.MATCH_PLACE_ID is still the template placeholder (1234567890). Set it to your Match place's PlaceId.")
end

if game.PrivateServerId ~= "" and not Config.ALLOW_PRIVATE_SERVER_LOBBY then
	warn("[LobbyMatchmaker] Private server detected. Skipping lobby matchmaking button wiring.")
	return
end

local difficultyLookup = {}
for _, difficulty in ipairs(Config.DIFFICULTIES) do
	difficultyLookup[difficulty] = true
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

local function isDifficulty(value)
	return difficultyLookup[value] == true
end

local function isMatchPlaceConfigured()
	if type(matchPlaceId) ~= "number" then
		return false
	end
	if matchPlaceId <= 0 then
		return false
	end
	return matchPlaceId ~= 1234567890
end

local function maxPlayersForDifficulty(difficulty)
	local configured = toNumber(Config.MAX_PLAYERS_PER_DIFFICULTY[difficulty], 0)
	if configured > 0 then
		return configured
	end
	return Players.MaxPlayers
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

		local playerCount = math.max(toNumber(value.playerCount, 0), 0)
		local pendingSlots = math.max(toNumber(value.pendingSlots, 0), 0)
		local maxPlayers = math.max(toNumber(value.maxPlayers, 0), 0)
		local effectiveCount = playerCount + pendingSlots

		if maxPlayers > 0 and effectiveCount < maxPlayers then
			table.insert(candidates, {
				key = serverKey,
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

	local ok = safeCall(("UpdateAsync reserve %s"):format(serverKey), function()
		matchServers:UpdateAsync(serverKey, function(oldValue, oldSortKey)
			if type(oldValue) ~= "table" then
				return nil
			end

			if oldValue.difficulty ~= difficulty then
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

			oldValue.pendingSlots = pendingSlots + 1
			oldValue.lastHeartbeat = currentTime

			didReserve = true
			accessCode = oldValue.accessCode

			return oldValue, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end)

	if not ok then
		return false, nil
	end

	return didReserve, accessCode
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

local function teleportToReservedServer(player, difficulty, matchId, accessCode)
	if player.Parent ~= Players then
		return false
	end

	if not isMatchPlaceConfigured() then
		warn("[LobbyMatchmaker] MATCH_PLACE_ID is invalid. Teleport canceled.")
		return false
	end

	warn(("[LobbyMatchmaker] Teleporting %s -> placeId=%s difficulty=%s matchId=%s"):format(
		player.Name,
		tostring(matchPlaceId),
		tostring(difficulty),
		tostring(matchId)
	))

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		difficulty = difficulty,
		matchId = matchId,
		fromPlaceId = game.PlaceId,
		queuedAt = nowSeconds(),
	})

	local retries = math.max(1, toNumber(Config.TELEPORT_RETRIES, 1))
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(matchPlaceId, {player}, options)
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

	return false
end

local function createReservedServer(difficulty)
	if not isMatchPlaceConfigured() then
		warn("[LobbyMatchmaker] MATCH_PLACE_ID is invalid. Cannot reserve server.")
		return nil, nil
	end

	local maxPlayers = maxPlayersForDifficulty(difficulty)
	if maxPlayers <= 0 then
		warn(("[LobbyMatchmaker] Max players missing for difficulty '%s'"):format(tostring(difficulty)))
		return nil, nil
	end

	local ok, accessCode, privateServerId = safeCall("ReserveServer", function()
		if type(TeleportService.ReserveServerAsync) == "function" then
			return TeleportService:ReserveServerAsync(matchPlaceId)
		end

		return TeleportService:ReserveServer(matchPlaceId)
	end)
	if not ok then
		return nil, nil
	end

	if type(accessCode) ~= "string" or accessCode == "" then
		warn("[LobbyMatchmaker] ReserveServer returned an invalid access code.")
		return nil, nil
	end
	if type(privateServerId) ~= "string" or privateServerId == "" then
		warn("[LobbyMatchmaker] ReserveServer returned an invalid private server id.")
		return nil, nil
	end

	local currentTime = nowSeconds()
	local entry = {
		difficulty = difficulty,
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
		return nil, nil
	end

	return privateServerId, accessCode
end

local function sendPlayerToDifficulty(player, difficulty)
	if not isMatchPlaceConfigured() then
		return false
	end

	if player.Parent ~= Players then
		return false
	end

	local candidates = fetchCandidateServers(difficulty)

	for _, candidate in ipairs(candidates) do
		local reserved, accessCode = reserveSlot(candidate.key, difficulty)
		if reserved and accessCode then
			local didTeleport = teleportToReservedServer(player, difficulty, candidate.key, accessCode)
			if didTeleport then
				return true
			end

			releaseSlot(candidate.key)
		end
	end

	local matchId, accessCode = createReservedServer(difficulty)
	if not matchId or not accessCode then
		return false
	end

	local didTeleport = teleportToReservedServer(player, difficulty, matchId, accessCode)
	if didTeleport then
		return true
	end

	removeServerEntry(matchId)
	return false
end

local function onPromptTriggered(player, difficulty)
	if not isDifficulty(difficulty) then
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
	if not isDifficulty(difficulty) then
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
