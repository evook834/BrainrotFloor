local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Shared = ServerScriptService:WaitForChild("Shared")
local PlaceRole = require(Shared:WaitForChild("PlaceRole"))
local Config = require(Shared:WaitForChild("MatchmakingConfig"))
local matchServers = MemoryStoreService:GetSortedMap(Config.MEMORYSTORE_MAP_NAME)

if not PlaceRole.shouldRunMatchSystems() then
	warn(("[MatchServerRegistry] Skipping match registry for place role '%s' (placeId=%s)."):format(
		PlaceRole.getRole(),
		tostring(game.PlaceId)
	))
	return
end

local MATCH_KEY = game.PrivateServerId
if MATCH_KEY == "" then
	warn("[MatchServerRegistry] PrivateServerId is empty. This script should run in reserved servers.")
	return
end

Workspace:SetAttribute("MatchId", MATCH_KEY)
Workspace:SetAttribute("MatchPlaceId", game.PlaceId)

local difficultyLookup = {}
for _, difficulty in ipairs(Config.DIFFICULTIES) do
	difficultyLookup[difficulty] = true
end

local activeDifficulty
local pendingConsumedByUserId = {}
local warnedMissingAccessCode = false

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
		warn(("[MatchServerRegistry] %s failed: %s"):format(label, tostring(resultA)))
		return false, nil, nil, nil
	end
	return true, resultA, resultB, resultC
end

local function isDifficulty(value)
	return difficultyLookup[value] == true
end

local function maxPlayersForDifficulty(difficulty)
	local configured = Config.MAX_PLAYERS_PER_DIFFICULTY[difficulty]
	if tonumber(configured) and configured > 0 then
		return configured
	end
	return Players.MaxPlayers
end

local function setActiveDifficulty(difficulty)
	if not isDifficulty(difficulty) then
		return
	end

	if activeDifficulty and activeDifficulty ~= difficulty then
		warn(("[MatchServerRegistry] Received mismatched difficulty '%s' while '%s' is active"):format(
			tostring(difficulty),
			tostring(activeDifficulty)
		))
		return
	end

	activeDifficulty = difficulty
	Workspace:SetAttribute("Difficulty", difficulty)
end

local function readDifficultyFromJoinData(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if type(teleportData) ~= "table" then
		return nil, nil, nil
	end

	local difficulty = teleportData.difficulty
	local matchId = teleportData.matchId
	local placeId = toNumber(teleportData.placeId, nil)

	if not isDifficulty(difficulty) then
		difficulty = nil
	end

	if type(matchId) ~= "string" then
		matchId = nil
	end

	return difficulty, matchId, placeId
end

local function loadDifficultyFromStore()
	local ok, value = safeCall("GetAsync", function()
		return matchServers:GetAsync(MATCH_KEY)
	end)
	if not ok then
		return
	end

	if type(value) == "table" and isDifficulty(value.difficulty) then
		setActiveDifficulty(value.difficulty)
	end
end

local function consumePendingSlot()
	local currentTime = nowSeconds()
	local currentPlayers = #Players:GetPlayers()

	safeCall("UpdateAsync consume pending slot", function()
		matchServers:UpdateAsync(MATCH_KEY, function(oldValue, oldSortKey)
			if type(oldValue) ~= "table" then
				return nil
			end

			local pendingSlots = math.max(toNumber(oldValue.pendingSlots, 0), 0)
			oldValue.pendingSlots = math.max(pendingSlots - 1, 0)
			oldValue.playerCount = currentPlayers
			oldValue.lastHeartbeat = currentTime

			return oldValue, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end)
end

local function heartbeat()
	local currentTime = nowSeconds()
	local currentPlayers = #Players:GetPlayers()

	safeCall("UpdateAsync heartbeat", function()
		matchServers:UpdateAsync(MATCH_KEY, function(oldValue, oldSortKey)
			local entry = oldValue
			if type(entry) ~= "table" then
				entry = nil
			end

			if not activeDifficulty and entry and isDifficulty(entry.difficulty) then
				setActiveDifficulty(entry.difficulty)
			end

			if not activeDifficulty then
				-- Wait until we know the server difficulty from teleport data or existing store data.
				return entry, oldSortKey
			end

			if not entry then
				entry = {}
			end

			entry.difficulty = activeDifficulty
			entry.placeId = game.PlaceId
			entry.privateServerId = MATCH_KEY
			entry.serverJobId = game.JobId
			entry.playerCount = currentPlayers
			entry.maxPlayers = maxPlayersForDifficulty(activeDifficulty)
			entry.pendingSlots = math.max(toNumber(entry.pendingSlots, 0), 0)
			entry.lastHeartbeat = currentTime
			entry.createdAt = toNumber(entry.createdAt, currentTime)

			if (type(entry.accessCode) ~= "string" or entry.accessCode == "") and not warnedMissingAccessCode then
				warnedMissingAccessCode = true
				warn("[MatchServerRegistry] accessCode is missing from the match entry; lobby cannot route new players to this server.")
			end

			return entry, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end)
end

local function onPlayerAdded(player)
	local difficulty, matchId, placeId = readDifficultyFromJoinData(player)
	if difficulty then
		setActiveDifficulty(difficulty)
	end

	if placeId and placeId ~= game.PlaceId then
		warn(("[MatchServerRegistry] JoinData placeId (%s) does not match current game.PlaceId (%s)."):format(
			tostring(placeId),
			tostring(game.PlaceId)
		))
	end

	local userId = player.UserId
	if matchId == MATCH_KEY and not pendingConsumedByUserId[userId] then
		pendingConsumedByUserId[userId] = true
		consumePendingSlot()
	end

	heartbeat()
end

local function onPlayerRemoving(player)
	pendingConsumedByUserId[player.UserId] = nil
	heartbeat()
end

loadDifficultyFromStore()

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

task.spawn(function()
	while true do
		task.wait(Config.HEARTBEAT_SECONDS)
		heartbeat()
	end
end)

game:BindToClose(function()
	safeCall("RemoveAsync on close", function()
		matchServers:RemoveAsync(MATCH_KEY)
	end)
end)
