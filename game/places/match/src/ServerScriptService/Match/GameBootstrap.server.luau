local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local PlaceRole = require(ServerScriptService.Shared.PlaceRole)
local MatchmakingConfig = require(ServerScriptService.Shared.MatchmakingConfig)
local Config = require(ReplicatedStorage.Shared.GameConfig)
local WaveService = require(script.Parent.Services.WaveService)
local ShopService = require(script.Parent.Services.ShopService)
local AmmoPickupService = require(script.Parent.Services.AmmoPickupService)
local ClassService = require(script.Parent.Services.ClassService)
local DifficultyService = require(script.Parent.Services.DifficultyService)
local SettingsService = require(script.Parent.Services.SettingsService)

local PLACEHOLDER_PLACE_ID = 1234567890

if not PlaceRole.shouldRunMatchSystems() then
	warn(("[GameBootstrap] Skipping match systems for place role '%s' (placeId=%s)."):
		format(PlaceRole.getRole(), tostring(game.PlaceId)))
	return
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

		warn(("[GameBootstrap] Expected RemoteEvent at %s/%s, got %s"):
			format(parent.Name, name, existing.ClassName))
		return nil
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end
	return n
end

local function nowSeconds()
	return os.time()
end

local function safeCall(label, callback)
	local ok, resultA, resultB, resultC = pcall(callback)
	if not ok then
		warn(("[GameBootstrap] %s failed: %s"):format(label, tostring(resultA)))
		return false, nil, nil, nil
	end

	return true, resultA, resultB, resultC
end

local MAP_VOTE_REVEAL_DELAY_SECONDS = math.max(0, toNumber(MatchmakingConfig.MAP_VOTE_REVEAL_DELAY_SECONDS, 5))
local MAP_VOTE_DURATION_SECONDS = math.max(1, toNumber(MatchmakingConfig.MAP_VOTE_DURATION_SECONDS, 60))

local matchServers = MemoryStoreService:GetSortedMap(MatchmakingConfig.MEMORYSTORE_MAP_NAME)
local randomGenerator = Random.new()

local function ensureTempEnemyTemplate(templateFolder)
	local hasEnemyModel = false
	for _, child in templateFolder:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart", true) then
			hasEnemyModel = true
			break
		end
	end

	if hasEnemyModel then
		return
	end

	local model = Instance.new("Model")
	model.Name = "TempBrainrot"
	model:SetAttribute("IsTemporaryTestEnemy", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = Color3.fromRGB(255, 85, 85)
	root.Material = Enum.Material.Neon
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 50
	humanoid.Health = 50
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = templateFolder

	warn("Created temporary enemy template at ServerStorage/EnemyTemplates/TempBrainrot")
end

local function ensureTempSpawnPoint(spawnFolder)
	for _, child in spawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			return
		end
	end

	local spawnPart = Instance.new("Part")
	spawnPart.Name = "TempSpawnPoint"
	spawnPart.Size = Vector3.new(6, 1, 6)
	spawnPart.Anchored = true
	spawnPart.CanCollide = false
	spawnPart.Transparency = 0.2
	spawnPart.Material = Enum.Material.ForceField
	spawnPart.Color = Color3.fromRGB(85, 170, 255)
	spawnPart.CFrame = CFrame.new(0, 6, 0)
	spawnPart.Parent = spawnFolder

	warn("Created temporary spawn point at Workspace/SpawnPoints/TempSpawnPoint")
end

local function ensureLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = (Config.Player and Config.Player.StartingMoney) or 0
		money.Parent = leaderstats
	end
end

local function disableHumanoidRegen(humanoid)
	local lastHealth = humanoid.Health
	local adjusting = false

	humanoid.HealthChanged:Connect(function(newHealth)
		if adjusting then
			return
		end

		if newHealth > lastHealth then
			adjusting = true
			humanoid.Health = lastHealth
			adjusting = false
			return
		end

		lastHealth = newHealth
	end)
end

local pendingRespawnByPlayer = {}
local gameOverTriggered = false
local returnLobbyInFlightByUserId = {}
local returnLobbyLastRequestByUserId = {}
local mapVoteRemote = nil
local mapVoteInProgress = false
local mapVoteSessionToken = 0
local mapVoteEndsAt = 0
local mapVotesByUserId = {}
local mapVoteCountsByPlaceId = {}

local difficultyLookup = {}
for _, difficulty in ipairs(MatchmakingConfig.DIFFICULTIES) do
	difficultyLookup[difficulty] = true
end

local function isDifficulty(value)
	return difficultyLookup[value] == true
end

local function normalizePlaceId(value)
	local placeId = toNumber(value, nil)
	if placeId == nil then
		return nil
	end

	if placeId ~= math.floor(placeId) then
		return nil
	end

	if placeId <= 0 or placeId == PLACEHOLDER_PLACE_ID then
		return nil
	end

	return placeId
end

local function getMapVoteLabel(placeId, defaultIndex)
	local labels = MatchmakingConfig.MATCH_PLACE_LABELS
	if type(labels) == "table" then
		local fromNumberKey = labels[placeId]
		if type(fromNumberKey) == "string" and fromNumberKey ~= "" then
			return fromNumberKey
		end

		local fromStringKey = labels[tostring(placeId)]
		if type(fromStringKey) == "string" and fromStringKey ~= "" then
			return fromStringKey
		end
	end

	return ("Map %d"):format(defaultIndex)
end

local function collectMapVoteOptions()
	local options = {}
	local placeIdLookup = {}

	local function addOption(rawPlaceId, explicitLabel)
		local placeId = normalizePlaceId(rawPlaceId)
		if placeId == nil then
			return
		end

		if placeIdLookup[placeId] then
			return
		end

		placeIdLookup[placeId] = true
		table.insert(options, {
			placeId = placeId,
			label = if type(explicitLabel) == "string" and explicitLabel ~= "" then explicitLabel else getMapVoteLabel(placeId, #options + 1),
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
		warn("[GameBootstrap] No valid map vote options configured. Check MATCH_PLACE_IDS.")
	end

	return options, placeIdLookup
end

local mapVoteOptions, mapVoteOptionLookup = collectMapVoteOptions()

local function invalidateRespawn(player)
	pendingRespawnByPlayer[player] = (pendingRespawnByPlayer[player] or 0) + 1
end

local function hasAnyLivingPlayers()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
				return true
			end
		end
	end

	return false
end

local function cancelAllPendingRespawns()
	for _, player in Players:GetPlayers() do
		invalidateRespawn(player)
	end
end

local function resolveDifficultyForNextMap()
	local currentDifficulty = Workspace:GetAttribute("Difficulty")
	if type(currentDifficulty) == "string" and isDifficulty(currentDifficulty) then
		return currentDifficulty
	end

	local fallback = DifficultyService.getCurrentDifficulty()
	if type(fallback) == "string" and isDifficulty(fallback) then
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
	if not mapVoteRemote then
		return
	end

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

	mapVoteRemote:FireAllClients(payload)
end

local function sendMapVoteSnapshot(player)
	if not mapVoteRemote then
		return
	end

	if not gameOverTriggered then
		return
	end

	if mapVoteInProgress then
		mapVoteRemote:FireClient(player, {
			action = "Start",
			endsAt = mapVoteEndsAt,
			options = serializeMapVoteOptions(),
			duration = MAP_VOTE_DURATION_SECONDS,
			difficulty = resolveDifficultyForNextMap(),
		})
	end
end

local function clearMapVotes()
	mapVotesByUserId = {}
	mapVoteCountsByPlaceId = {}
	for _, option in ipairs(mapVoteOptions) do
		mapVoteCountsByPlaceId[option.placeId] = 0
	end
end

local function removePlayerVote(player)
	local userId = player.UserId
	local previousPlaceId = mapVotesByUserId[userId]
	if previousPlaceId == nil then
		return false
	end

	mapVotesByUserId[userId] = nil
	local previousVotes = mapVoteCountsByPlaceId[previousPlaceId] or 0
	mapVoteCountsByPlaceId[previousPlaceId] = math.max(0, previousVotes - 1)
	return true
end

local function registerPlayerVote(player, placeId)
	local userId = player.UserId
	local previousPlaceId = mapVotesByUserId[userId]
	if previousPlaceId == placeId then
		return false
	end

	if previousPlaceId ~= nil then
		local previousVotes = mapVoteCountsByPlaceId[previousPlaceId] or 0
		mapVoteCountsByPlaceId[previousPlaceId] = math.max(0, previousVotes - 1)
	end

	mapVotesByUserId[userId] = placeId
	mapVoteCountsByPlaceId[placeId] = (mapVoteCountsByPlaceId[placeId] or 0) + 1
	return true
end

local function onMapVoteSubmitted(player, payload)
	if not gameOverTriggered or not mapVoteInProgress then
		return
	end

	if player.Parent ~= Players then
		return
	end

	if type(payload) ~= "table" then
		return
	end

	local placeId = normalizePlaceId(payload.placeId)
	if placeId == nil then
		return
	end

	if not mapVoteOptionLookup[placeId] then
		return
	end

	if registerPlayerVote(player, placeId) then
		broadcastMapVote("Update")
	end
end

local function chooseWinningMapOption()
	if #mapVoteOptions == 0 then
		return nil, false
	end

	local highestVotes = -1
	local tiedOptions = {}

	for _, option in ipairs(mapVoteOptions) do
		local votes = mapVoteCountsByPlaceId[option.placeId] or 0
		if votes > highestVotes then
			highestVotes = votes
			tiedOptions = {option}
		elseif votes == highestVotes then
			table.insert(tiedOptions, option)
		end
	end

	if #tiedOptions == 0 then
		return nil, false
	end

	if #tiedOptions == 1 then
		return tiedOptions[1], false
	end

	local randomIndex = randomGenerator:NextInteger(1, #tiedOptions)
	return tiedOptions[randomIndex], true
end

local function maxPlayersForDifficulty(difficulty)
	local configured = toNumber(MatchmakingConfig.MAX_PLAYERS_PER_DIFFICULTY[difficulty], 0)
	if configured > 0 then
		return configured
	end

	return Players.MaxPlayers
end

local function reserveServerForMap(placeId, difficulty, pendingSlots)
	local ok, accessCode, privateServerId = safeCall("ReserveServer", function()
		if type(TeleportService.ReserveServerAsync) == "function" then
			return TeleportService:ReserveServerAsync(placeId)
		end

		return TeleportService:ReserveServer(placeId)
	end)
	if not ok then
		return nil, nil
	end

	if type(accessCode) ~= "string" or accessCode == "" then
		warn("[GameBootstrap] ReserveServer returned an invalid access code.")
		return nil, nil
	end

	if type(privateServerId) ~= "string" or privateServerId == "" then
		warn("[GameBootstrap] ReserveServer returned an invalid private server id.")
		return nil, nil
	end

	local currentTime = nowSeconds()
	local entry = {
		difficulty = difficulty,
		placeId = placeId,
		accessCode = accessCode,
		privateServerId = privateServerId,
		playerCount = 0,
		pendingSlots = math.max(0, pendingSlots),
		maxPlayers = maxPlayersForDifficulty(difficulty),
		lastHeartbeat = currentTime,
		createdAt = currentTime,
	}

	local setOk = safeCall(("SetAsync(%s)"):format(privateServerId), function()
		matchServers:SetAsync(privateServerId, entry, MatchmakingConfig.ENTRY_TTL_SECONDS, currentTime)
	end)
	if not setOk then
		return nil, nil
	end

	return privateServerId, accessCode
end

local function removeServerEntry(matchId)
	safeCall(("RemoveAsync(%s)"):format(tostring(matchId)), function()
		matchServers:RemoveAsync(matchId)
	end)
end

local function teleportAllPlayersToMap(placeId, mapLabel)
	local playersToTeleport = {}
	for _, player in Players:GetPlayers() do
		if player.Parent == Players then
			table.insert(playersToTeleport, player)
		end
	end

	if #playersToTeleport == 0 then
		return true
	end

	local difficulty = resolveDifficultyForNextMap()
	local matchId, accessCode = reserveServerForMap(placeId, difficulty, #playersToTeleport)
	if not matchId or not accessCode then
		warn(("[GameBootstrap] Could not reserve map server for placeId=%s"):format(tostring(placeId)))
		return false
	end

	broadcastMapVote("Teleporting", {
		selectedPlaceId = placeId,
		selectedLabel = mapLabel,
		difficulty = difficulty,
	})

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		difficulty = difficulty,
		matchId = matchId,
		placeId = placeId,
		reason = "MapVoteWinner",
		fromPlaceId = game.PlaceId,
		queuedAt = nowSeconds(),
	})

	local retries = math.max(1, toNumber(MatchmakingConfig.TELEPORT_RETRIES, 1))
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, playersToTeleport, options)
		end)
		if ok then
			return true
		end

		warn(("[GameBootstrap] Map vote teleport failed (attempt %d): %s"):format(attempt, tostring(err)))
		if attempt < retries then
			task.wait(toNumber(MatchmakingConfig.TELEPORT_RETRY_DELAY_SECONDS, 1))
		end
	end

	removeServerEntry(matchId)
	return false
end

local function runMapVoteFlow()
	if #mapVoteOptions == 0 then
		return
	end

	task.wait(MAP_VOTE_REVEAL_DELAY_SECONDS)
	if not gameOverTriggered then
		return
	end

	mapVoteSessionToken += 1
	local activeToken = mapVoteSessionToken
	mapVoteInProgress = true
	clearMapVotes()
	mapVoteEndsAt = Workspace:GetServerTimeNow() + MAP_VOTE_DURATION_SECONDS

	broadcastMapVote("Start", {
		duration = MAP_VOTE_DURATION_SECONDS,
		difficulty = resolveDifficultyForNextMap(),
	})

	task.wait(MAP_VOTE_DURATION_SECONDS)
	if mapVoteSessionToken ~= activeToken then
		return
	end

	mapVoteInProgress = false
	mapVoteEndsAt = 0

	local winner, wasTie = chooseWinningMapOption()
	if winner == nil then
		warn("[GameBootstrap] Map vote ended with no winner.")
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
		warn("[GameBootstrap] Map vote winner chosen, but teleport failed.")
	end
end

local function triggerGameOver()
	if gameOverTriggered then
		return
	end

	if not PlaceRole.shouldRunMatchSystems() then
		return
	end

	gameOverTriggered = true
	Workspace:SetAttribute("GameOver", true)
	cancelAllPendingRespawns()
	WaveService.gameOver("AllPlayersDead")
	task.spawn(runMapVoteFlow)
end

local function resolveLobbyPlaceId()
	local lobbyPlaceId = toNumber(MatchmakingConfig.LOBBY_PLACE_ID, nil)
	if lobbyPlaceId == nil then
		return nil
	end

	if lobbyPlaceId ~= math.floor(lobbyPlaceId) then
		return nil
	end

	if lobbyPlaceId <= 0 or lobbyPlaceId == PLACEHOLDER_PLACE_ID then
		return nil
	end

	return lobbyPlaceId
end

local function sendPlayerToLobby(player)
	if player.Parent ~= Players then
		return false
	end

	local lobbyPlaceId = resolveLobbyPlaceId()
	if not lobbyPlaceId then
		warn("[GameBootstrap] LOBBY_PLACE_ID is invalid. Cannot return players to lobby.")
		return false
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		reason = "GameOver",
		fromPlaceId = game.PlaceId,
		matchId = Workspace:GetAttribute("MatchId"),
		queuedAt = nowSeconds(),
	})

	local retries = math.max(1, toNumber(MatchmakingConfig.TELEPORT_RETRIES, 1))
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(lobbyPlaceId, {player}, options)
		end)
		if ok then
			return true
		end

		warn(("[GameBootstrap] Return-to-lobby teleport failed (attempt %d) for %s: %s"):
			format(attempt, player.Name, tostring(err)))

		if attempt < retries then
			task.wait(toNumber(MatchmakingConfig.TELEPORT_RETRY_DELAY_SECONDS, 1))
		end
	end

	return false
end

local function onReturnToLobbyRequested(player)
	if not gameOverTriggered then
		return
	end

	if not PlaceRole.shouldRunMatchSystems() then
		return
	end

	local userId = player.UserId
	if returnLobbyInFlightByUserId[userId] then
		return
	end

	local currentTime = nowSeconds()
	local previousRequestTime = toNumber(returnLobbyLastRequestByUserId[userId], 0)
	local cooldownSeconds = math.max(0, toNumber(MatchmakingConfig.REQUEST_COOLDOWN_SECONDS, 1))
	if (currentTime - previousRequestTime) < cooldownSeconds then
		return
	end

	returnLobbyLastRequestByUserId[userId] = currentTime
	returnLobbyInFlightByUserId[userId] = true

	local ok, didTeleport = pcall(sendPlayerToLobby, player)
	returnLobbyInFlightByUserId[userId] = nil

	if not ok then
		warn(("[GameBootstrap] Return-to-lobby request failed for %s: %s"):
			format(player.Name, tostring(didTeleport)))
		return
	end

	if not didTeleport then
		warn(("[GameBootstrap] Return-to-lobby request could not teleport %s"):format(player.Name))
	end
end

local function ensureDifficultyAttribute()
	local currentDifficulty = Workspace:GetAttribute("Difficulty")
	if type(currentDifficulty) == "string" and currentDifficulty ~= "" then
		return
	end

	Workspace:SetAttribute("Difficulty", DifficultyService.getCurrentDifficulty())
end

local function scheduleRespawn(player)
	if gameOverTriggered then
		return
	end

	local respawnDelaySeconds = (Config.Player and Config.Player.RespawnDelaySeconds) or 60
	local respawnToken = (pendingRespawnByPlayer[player] or 0) + 1
	pendingRespawnByPlayer[player] = respawnToken

	task.spawn(function()
		task.wait(respawnDelaySeconds)
		if player.Parent ~= Players then
			return
		end

		if pendingRespawnByPlayer[player] ~= respawnToken then
			return
		end

		if gameOverTriggered then
			return
		end

		player:LoadCharacter()
	end)
end

local function bindPlayerSystems(player)
	ensureLeaderstats(player)

	sendMapVoteSnapshot(player)

	local function onCharacter(character)
		invalidateRespawn(player)

		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end

		if Config.Player and Config.Player.DisableHealthRegen then
			disableHumanoidRegen(humanoid)
		end

		humanoid.Died:Connect(function()
			task.defer(function()
				if gameOverTriggered then
					return
				end

				if hasAnyLivingPlayers() then
					scheduleRespawn(player)
					return
				end

				triggerGameOver()
			end)
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	elseif not gameOverTriggered then
		player:LoadCharacter()
	end
end

local remotesFolder = ensureFolder(ReplicatedStorage, Config.Remotes.Folder)
ensureRemoteEvent(remotesFolder, Config.Remotes.WaveState)

local returnToLobbyRemote = ensureRemoteEvent(remotesFolder, Config.Remotes.ReturnToLobby)
if returnToLobbyRemote then
	returnToLobbyRemote.OnServerEvent:Connect(onReturnToLobbyRequested)
end

mapVoteRemote = ensureRemoteEvent(remotesFolder, Config.Remotes.MapVote)
if mapVoteRemote then
	mapVoteRemote.OnServerEvent:Connect(onMapVoteSubmitted)
end

local templateFolder = ensureFolder(ServerStorage, Config.Enemy.TemplateFolderName)
local spawnFolder = ensureFolder(Workspace, Config.Enemy.SpawnFolderName)
ensureFolder(Workspace, Config.Enemy.ContainerName)
ensureTempEnemyTemplate(templateFolder)
ensureTempSpawnPoint(spawnFolder)
ensureDifficultyAttribute()
Workspace:SetAttribute("GameOver", false)

Players.CharacterAutoLoads = false
Players.PlayerAdded:Connect(bindPlayerSystems)
Players.PlayerRemoving:Connect(function(player)
	pendingRespawnByPlayer[player] = nil
	returnLobbyInFlightByUserId[player.UserId] = nil
	returnLobbyLastRequestByUserId[player.UserId] = nil

	if mapVoteInProgress and removePlayerVote(player) then
		broadcastMapVote("Update")
	end
end)
for _, player in Players:GetPlayers() do
	bindPlayerSystems(player)
end

ClassService.start()
SettingsService.start()
ShopService.start()
AmmoPickupService.start()
WaveService.start()
