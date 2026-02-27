--[[
	MatchServerRegistry — Registers this reserved match server in MemoryStore so the lobby
	can route players. Heartbeats keep the entry alive; difficulty is set from JoinData or
	existing store; pending slots are consumed when players join. Entry is removed on BindToClose.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ServerScriptService:WaitForChild("Shared")
local Matchmaking = Shared:WaitForChild("Matchmaking")
local PlaceRole = require(Matchmaking:WaitForChild("PlaceRole"))
local Config = require(Matchmaking:WaitForChild("MatchmakingConfig"))

local MatchStore = require(script.Parent.MatchStore)
local RegistryEntry = require(script.Parent.RegistryEntry)
local RegistryJoinData = require(script.Parent.RegistryJoinData)

local LOG_PREFIX = "[MatchServerRegistry]"

local MatchServerRegistry = {}

function MatchServerRegistry.run()
	if not PlaceRole.shouldRunMatchSystems() then
		warn(("%s Skipping match registry for place role '%s' (placeId=%s)."):format(
			LOG_PREFIX,
			PlaceRole.getRole(),
			tostring(game.PlaceId)
		))
		return
	end

	local matchKey = game.PrivateServerId
	if matchKey == "" then
		if not RunService:IsStudio() then
			warn(("%s PrivateServerId is empty. This script should run in reserved servers."):format(LOG_PREFIX))
		end
		return
	end

	Workspace:SetAttribute("MatchId", matchKey)
	Workspace:SetAttribute("MatchPlaceId", game.PlaceId)

	local store = MatchStore.create(Config.MEMORYSTORE_MAP_NAME, Config.ENTRY_TTL_SECONDS, LOG_PREFIX)
	local activeDifficulty
	local pendingConsumedByUserId = {}
	local warnedMissingAccessCode = false

	local function setActiveDifficulty(difficulty)
		if not Config.isDifficulty(difficulty) then
			return
		end
		if activeDifficulty and activeDifficulty ~= difficulty then
			warn(("%s Received mismatched difficulty '%s' while '%s' is active"):format(
				LOG_PREFIX,
				tostring(difficulty),
				tostring(activeDifficulty)
			))
			return
		end
		activeDifficulty = difficulty
		Workspace:SetAttribute("Difficulty", difficulty)
	end

	local function loadDifficultyFromStore()
		local ok, value = store.get(matchKey)
		if not ok then
			return
		end
		if type(value) == "table" and Config.isDifficulty(value.difficulty) then
			setActiveDifficulty(value.difficulty)
		end
	end

	local function consumePendingSlot()
		local currentTime = os.time()
		local currentPlayers = #Players:GetPlayers()
		store.update(matchKey, function(oldValue, oldSortKey)
			if type(oldValue) ~= "table" then
				return nil
			end
			RegistryEntry.applyConsumePendingSlot(oldValue, currentTime, currentPlayers)
			return oldValue, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end

	local function heartbeat()
		local currentTime = os.time()
		local currentPlayers = #Players:GetPlayers()
		store.update(matchKey, function(oldValue, oldSortKey)
			local entry = type(oldValue) == "table" and oldValue or nil
			if not activeDifficulty and entry and Config.isDifficulty(entry.difficulty) then
				setActiveDifficulty(entry.difficulty)
			end
			if not activeDifficulty then
				return entry, oldSortKey
			end
			entry = RegistryEntry.buildHeartbeatEntry(entry, {
				difficulty = activeDifficulty,
				currentTime = currentTime,
				currentPlayers = currentPlayers,
				placeId = game.PlaceId,
				jobId = game.JobId,
				privateServerId = matchKey,
				maxPlayers = Config.getMaxPlayersForDifficulty(activeDifficulty, Players.MaxPlayers),
			})
			if not RegistryEntry.hasAccessCode(entry) and not warnedMissingAccessCode then
				warnedMissingAccessCode = true
				warn(("%s accessCode is missing from the match entry; lobby cannot route new players to this server."):format(LOG_PREFIX))
			end
			return entry, currentTime
		end, Config.ENTRY_TTL_SECONDS)
	end

	local function onPlayerAdded(player)
		local data = RegistryJoinData.read(player)
		if data then
			if data.difficulty then
				setActiveDifficulty(data.difficulty)
			end
			if data.placeId and data.placeId ~= game.PlaceId then
				warn(("%s JoinData placeId (%s) does not match current game.PlaceId (%s)."):format(
					LOG_PREFIX,
					tostring(data.placeId),
					tostring(game.PlaceId)
				))
			end
			local userId = player.UserId
			if data.matchId == matchKey and not pendingConsumedByUserId[userId] then
				pendingConsumedByUserId[userId] = true
				consumePendingSlot()
			end
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
		store.remove(matchKey)
	end)
end

return MatchServerRegistry
