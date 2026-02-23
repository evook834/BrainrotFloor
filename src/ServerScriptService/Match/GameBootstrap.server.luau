local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local PlaceRole = require(ServerScriptService.Shared.PlaceRole)
local MatchmakingConfig = require(ServerScriptService.Shared.MatchmakingConfig)
local Config = require(ReplicatedStorage.Shared.GameConfig)
local WaveService = require(script.Parent.Services.WaveService)
local ShopService = require(script.Parent.Services.ShopService)
local ClassService = require(script.Parent.Services.ClassService)
local DifficultyService = require(script.Parent.Services.DifficultyService)
local PLACEHOLDER_PLACE_ID = 1234567890

if not PlaceRole.shouldRunMatchSystems() then
	warn(("[GameBootstrap] Skipping match systems for place role '%s' (placeId=%s)."):format(
		PlaceRole.getRole(),
		tostring(game.PlaceId)
	))
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

		warn(("[GameBootstrap] Expected RemoteEvent at %s/%s, got %s"):format(
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

local function toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end
	return n
end

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
		queuedAt = os.time(),
	})

	local retries = math.max(1, toNumber(MatchmakingConfig.TELEPORT_RETRIES, 1))
	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(lobbyPlaceId, {player}, options)
		end)
		if ok then
			return true
		end

		warn(("[GameBootstrap] Return-to-lobby teleport failed (attempt %d) for %s: %s"):format(
			attempt,
			player.Name,
			tostring(err)
		))

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

	local currentTime = os.time()
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
		warn(("[GameBootstrap] Return-to-lobby request failed for %s: %s"):format(player.Name, tostring(didTeleport)))
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
end)
for _, player in Players:GetPlayers() do
	bindPlayerSystems(player)
end

ClassService.start()
ShopService.start()
WaveService.start()
