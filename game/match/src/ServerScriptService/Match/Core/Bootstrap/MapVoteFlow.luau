--[[
	Map vote flow: collect options, run vote session, reserve server, teleport party.
	Used by GameBootstrap when game ends (all dead or win). Exposes onVoteSubmitted,
	onPlayerRemoving, getSnapshotForPlayer, and run.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ServerScriptService = game:GetService("ServerScriptService")
local Match = script.Parent.Parent.Parent
local DifficultyService = require(Match.Difficulty.DifficultyService)
local MatchmakingConfig = require(ServerScriptService.Shared.Matchmaking.MatchmakingConfig)

local BootstrapUtil = require(script.Parent.BootstrapUtil)

local MapVoteFlow = {}

local mapVoteInProgress = false
local mapVoteSessionToken = 0
local mapVoteEndsAt = 0
local mapVotesByUserId = {}
local mapVoteCountsByPlaceId = {}
local mapVoteFinishedEvent = Instance.new("BindableEvent")
local mapVoteOptions = {}
local mapVoteOptionLookup = {}
local mapVoteRemoteRef = nil
local teleportLoadingRemoteRef = nil
local matchServers = nil
local randomGenerator = Random.new()
local revealDelaySeconds = 0
local durationSeconds = 1

local function normalizePlaceId(value)
	local placeId = BootstrapUtil.toNumber(value, nil)
	if placeId == nil then return nil end
	if placeId ~= math.floor(placeId) then return nil end
	if placeId <= 0 or placeId == BootstrapUtil.PLACEHOLDER_PLACE_ID then return nil end
	return placeId
end

local function getMapVoteLabel(placeId, defaultIndex)
	local labels = MatchmakingConfig.MATCH_PLACE_LABELS
	if type(labels) == "table" then
		local fromNumberKey = labels[placeId]
		if type(fromNumberKey) == "string" and fromNumberKey ~= "" then return fromNumberKey end
		local fromStringKey = labels[tostring(placeId)]
		if type(fromStringKey) == "string" and fromStringKey ~= "" then return fromStringKey end
	end
	return ("Map %d"):format(defaultIndex)
end

local function collectMapVoteOptions()
	local options = {}
	local placeIdLookup = {}

	local function addOption(rawPlaceId, explicitLabel)
		local placeId = normalizePlaceId(rawPlaceId)
		if placeId == nil then return end
		if placeIdLookup[placeId] then return end
		placeIdLookup[placeId] = true
		table.insert(options, {
			placeId = placeId,
			label = (type(explicitLabel) == "string" and explicitLabel ~= "") and explicitLabel or getMapVoteLabel(placeId, #options + 1),
		})
	end

	local configuredVoteOptions = MatchmakingConfig.MAP_VOTE_OPTIONS
	if type(configuredVoteOptions) == "table" and #configuredVoteOptions > 0 then
		for _, rawOption in ipairs(configuredVoteOptions) do
			if type(rawOption) == "table" then
				addOption(rawOption.placeId or rawOption.PlaceId, rawOption.label or rawOption.name or rawOption.Name)
			else
				addOption(rawOption)
			end
		end
	end

	if #options == 0 and type(MatchmakingConfig.MATCH_PLACE_IDS) == "table" then
		for _, rawPlaceId in ipairs(MatchmakingConfig.MATCH_PLACE_IDS) do
			addOption(rawPlaceId)
		end
	end

	if #options == 0 then
		addOption(MatchmakingConfig.MATCH_PLACE_ID)
	end

	if #options == 0 then
		warn("[MapVoteFlow] No valid map vote options configured. Check MATCH_PLACE_IDS.")
	end

	return options, placeIdLookup
end

function MapVoteFlow.init(remotes)
	mapVoteRemoteRef = remotes.MapVote
	teleportLoadingRemoteRef = remotes.TeleportLoading
	matchServers = MemoryStoreService:GetSortedMap(MatchmakingConfig.MEMORYSTORE_MAP_NAME)
	revealDelaySeconds = math.max(0, BootstrapUtil.toNumber(MatchmakingConfig.MAP_VOTE_REVEAL_DELAY_SECONDS, 5))
	durationSeconds = math.max(1, BootstrapUtil.toNumber(MatchmakingConfig.MAP_VOTE_DURATION_SECONDS, 60))
	mapVoteOptions, mapVoteOptionLookup = collectMapVoteOptions()
end

local function resolveDifficultyForNextMap()
	local currentDifficulty = Workspace:GetAttribute("Difficulty")
	if type(currentDifficulty) == "string" and MatchmakingConfig.isDifficulty(currentDifficulty) then
		return currentDifficulty
	end
	local fallback = DifficultyService.getCurrentDifficulty()
	if type(fallback) == "string" and MatchmakingConfig.isDifficulty(fallback) then
		return fallback
	end
	return MatchmakingConfig.DIFFICULTIES[1]
end

local function serializeMapVoteOptions()
	local serialized = {}
	for _, option in ipairs(mapVoteOptions) do
		table.insert(serialized, {
			placeId = option.placeId,
			label = option.label,
			votes = mapVoteCountsByPlaceId[option.placeId] or 0,
		})
	end
	return serialized
end

local function broadcastMapVote(action, extraPayload)
	if not mapVoteRemoteRef then return end
	local payload = {
		action = action,
		endsAt = mapVoteEndsAt,
		options = serializeMapVoteOptions(),
	}
	if type(extraPayload) == "table" then
		for key, value in pairs(extraPayload) do
			payload[key] = value
		end
	end
	mapVoteRemoteRef:FireAllClients(payload)
end

local function notifyTeleportStarting(playersOrPlayer, title, message)
	if not teleportLoadingRemoteRef then return end
	if typeof(playersOrPlayer) == "Instance" then
		teleportLoadingRemoteRef:FireClient(playersOrPlayer, { action = "Start", title = title, message = message })
	else
		for _, player in ipairs(playersOrPlayer) do
			teleportLoadingRemoteRef:FireClient(player, { action = "Start", title = title, message = message })
		end
	end
	task.wait(0.1)
end

local function notifyTeleportFailed(playersOrPlayer, message)
	if not teleportLoadingRemoteRef then return end
	if typeof(playersOrPlayer) == "Instance" then
		teleportLoadingRemoteRef:FireClient(playersOrPlayer, { action = "Failed", message = message })
	else
		for _, player in ipairs(playersOrPlayer) do
			teleportLoadingRemoteRef:FireClient(player, { action = "Failed", message = message })
		end
	end
end

local function clearMapVotes()
	mapVotesByUserId = {}
	mapVoteCountsByPlaceId = {}
	for _, option in ipairs(mapVoteOptions) do
		mapVoteCountsByPlaceId[option.placeId] = 0
	end
end

local function getActiveMapVotePlayerCount()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent == Players then
			count += 1
		end
	end
	return count
end

local function getSubmittedMapVoteCount()
	local count = 0
	for _ in pairs(mapVotesByUserId) do
		count += 1
	end
	return count
end

local function allActivePlayersHaveVoted()
	local activePlayers = getActiveMapVotePlayerCount()
	if activePlayers <= 0 then return true end
	return getSubmittedMapVoteCount() >= activePlayers
end

local function tryFinishMapVoteEarly()
	if not mapVoteInProgress then return end
	if allActivePlayersHaveVoted() then
		mapVoteFinishedEvent:Fire(mapVoteSessionToken)
	end
end

function MapVoteFlow.removePlayerVote(player)
	local userId = player.UserId
	local previousPlaceId = mapVotesByUserId[userId]
	if previousPlaceId == nil then return false end
	mapVotesByUserId[userId] = nil
	local previousVotes = mapVoteCountsByPlaceId[previousPlaceId] or 0
	mapVoteCountsByPlaceId[previousPlaceId] = math.max(0, previousVotes - 1)
	return true
end

local function registerPlayerVote(player, placeId)
	local userId = player.UserId
	local previousPlaceId = mapVotesByUserId[userId]
	if previousPlaceId == placeId then return false end
	if previousPlaceId ~= nil then
		local previousVotes = mapVoteCountsByPlaceId[previousPlaceId] or 0
		mapVoteCountsByPlaceId[previousPlaceId] = math.max(0, previousVotes - 1)
	end
	mapVotesByUserId[userId] = placeId
	mapVoteCountsByPlaceId[placeId] = (mapVoteCountsByPlaceId[placeId] or 0) + 1
	return true
end

function MapVoteFlow.onVoteSubmitted(player, payload, isGameOverGetter)
	local isGameOver = type(isGameOverGetter) == "function" and isGameOverGetter() or isGameOverGetter
	if not isGameOver or not mapVoteInProgress then return end
	if player.Parent ~= Players then return end
	if type(payload) ~= "table" then return end
	local placeId = normalizePlaceId(payload.placeId)
	if placeId == nil then return end
	if not mapVoteOptionLookup[placeId] then return end
	if registerPlayerVote(player, placeId) then
		broadcastMapVote("Update")
		tryFinishMapVoteEarly()
	end
end

local function chooseWinningMapOption()
	if #mapVoteOptions == 0 then return nil, false end
	local highestVotes = -1
	local tiedOptions = {}
	for _, option in ipairs(mapVoteOptions) do
		local votes = mapVoteCountsByPlaceId[option.placeId] or 0
		if votes > highestVotes then
			highestVotes = votes
			tiedOptions = { option }
		elseif votes == highestVotes then
			table.insert(tiedOptions, option)
		end
	end
	if #tiedOptions == 0 then return nil, false end
	if #tiedOptions == 1 then return tiedOptions[1], false end
	local randomIndex = randomGenerator:NextInteger(1, #tiedOptions)
	return tiedOptions[randomIndex], true
end

local function reserveServerForMap(placeId, difficulty, pendingSlots)
	local ok, accessCode, privateServerId = BootstrapUtil.safeCall("ReserveServer", function()
		if type(TeleportService.ReserveServerAsync) == "function" then
			return TeleportService:ReserveServerAsync(placeId)
		end
		return TeleportService:ReserveServer(placeId)
	end)
	if not ok then return nil, nil end
	if type(accessCode) ~= "string" or accessCode == "" then
		warn("[MapVoteFlow] ReserveServer returned an invalid access code.")
		return nil, nil
	end
	if type(privateServerId) ~= "string" or privateServerId == "" then
		warn("[MapVoteFlow] ReserveServer returned an invalid private server id.")
		return nil, nil
	end
	local currentTime = BootstrapUtil.nowSeconds()
	local entry = {
		difficulty = difficulty,
		placeId = placeId,
		accessCode = accessCode,
		privateServerId = privateServerId,
		playerCount = 0,
		pendingSlots = math.max(0, pendingSlots),
		maxPlayers = MatchmakingConfig.getMaxPlayersForDifficulty(difficulty, Players.MaxPlayers),
		lastHeartbeat = currentTime,
		createdAt = currentTime,
	}
	local setOk = BootstrapUtil.safeCall(("SetAsync(%s)"):format(privateServerId), function()
		matchServers:SetAsync(privateServerId, entry, MatchmakingConfig.ENTRY_TTL_SECONDS, currentTime)
	end)
	if not setOk then return nil, nil end
	return privateServerId, accessCode
end

local function removeServerEntry(matchId)
	BootstrapUtil.safeCall(("RemoveAsync(%s)"):format(tostring(matchId)), function()
		matchServers:RemoveAsync(matchId)
	end)
end

local function teleportAllPlayersToMap(placeId, mapLabel)
	local playersToTeleport = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent == Players then
			table.insert(playersToTeleport, player)
		end
	end
	if #playersToTeleport == 0 then return true end

	local difficulty = resolveDifficultyForNextMap()
	local matchId, accessCode = reserveServerForMap(placeId, difficulty, #playersToTeleport)
	if not matchId or not accessCode then
		warn(("[MapVoteFlow] Could not reserve map server for placeId=%s"):format(tostring(placeId)))
		return false
	end

	broadcastMapVote("Teleporting", {
		selectedPlaceId = placeId,
		selectedLabel = mapLabel,
		difficulty = difficulty,
	})

	notifyTeleportStarting(
		playersToTeleport,
		"Loading next map",
		string.format("Loading %s (%s difficulty)...", tostring(mapLabel), tostring(difficulty))
	)

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		difficulty = difficulty,
		matchId = matchId,
		placeId = placeId,
		reason = "MapVoteWinner",
		fromPlaceId = game.PlaceId,
		queuedAt = BootstrapUtil.nowSeconds(),
	})

	local retries = math.max(1, BootstrapUtil.toNumber(MatchmakingConfig.TELEPORT_RETRIES, 1))
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, playersToTeleport, options)
		end)
		if ok then return true end
		warn(("[MapVoteFlow] Map vote teleport failed (attempt %d): %s"):format(attempt, tostring(err)))
		if attempt < retries then
			task.wait(BootstrapUtil.toNumber(MatchmakingConfig.TELEPORT_RETRY_DELAY_SECONDS, 1))
		end
	end
	removeServerEntry(matchId)
	notifyTeleportFailed(playersToTeleport, "Could not load the next map. Please try again.")
	return false
end

function MapVoteFlow.run(isGameOverGetter)
	if #mapVoteOptions == 0 then return end

	task.wait(revealDelaySeconds)
	if not isGameOverGetter or not isGameOverGetter() then return end

	mapVoteSessionToken += 1
	local activeToken = mapVoteSessionToken
	mapVoteInProgress = true
	clearMapVotes()
	mapVoteEndsAt = Workspace:GetServerTimeNow() + durationSeconds

	broadcastMapVote("Start", {
		duration = durationSeconds,
		difficulty = resolveDifficultyForNextMap(),
	})

	local voteFinished = false
	local voteFinishedConnection = mapVoteFinishedEvent.Event:Connect(function(sessionToken)
		if sessionToken ~= activeToken or voteFinished then return end
		voteFinished = true
	end)

	tryFinishMapVoteEarly()

	while not voteFinished do
		local remaining = mapVoteEndsAt - Workspace:GetServerTimeNow()
		if remaining <= 0 then break end
		task.wait(math.min(0.25, remaining))
	end

	voteFinishedConnection:Disconnect()

	if mapVoteSessionToken ~= activeToken then
		mapVoteInProgress = false
		mapVoteEndsAt = 0
		return
	end

	mapVoteInProgress = false
	mapVoteEndsAt = 0

	local winner, wasTie = chooseWinningMapOption()
	if winner == nil then
		warn("[MapVoteFlow] Map vote ended with no winner.")
		return
	end

	broadcastMapVote("End", {
		selectedPlaceId = winner.placeId,
		selectedLabel = winner.label,
		wasTie = wasTie,
	})

	task.wait(1.5)
	local didTeleport = teleportAllPlayersToMap(winner.placeId, winner.label)
	if not didTeleport then
		warn("[MapVoteFlow] Map vote winner chosen, but teleport failed.")
	end
end

function MapVoteFlow.getSnapshotForPlayer(player, isGameOver)
	if not mapVoteRemoteRef then return end
	if not isGameOver then return end
	if not mapVoteInProgress then return end
	mapVoteRemoteRef:FireClient(player, {
		action = "Start",
		endsAt = mapVoteEndsAt,
		options = serializeMapVoteOptions(),
		duration = durationSeconds,
		difficulty = resolveDifficultyForNextMap(),
	})
end

function MapVoteFlow.broadcastUpdate()
	if mapVoteInProgress then
		broadcastMapVote("Update")
	end
	tryFinishMapVoteEarly()
end

return MapVoteFlow
