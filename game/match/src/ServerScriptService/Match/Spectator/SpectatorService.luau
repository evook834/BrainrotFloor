-- SpectatorService - Server-side spectator system for dead players
-- Manages spectator state, respawn scheduling, and client notifications
--
-- Usage:
--   1. Call SpectatorService.start() in your match bootstrap
--   2. Call SpectatorService.onPlayerDeath(player) when a player dies
--   3. Call SpectatorService.onPlayerRespawn(player, character) when a player spawns
--   4. Call SpectatorService.onPlayerRemove(player) when a player leaves

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local SpectatorService = {}

-- Module state
local started = false
local spectatingPlayers = {}  -- { [player] = true }
local pendingRespawnByPlayer = {}  -- { [player] = respawnToken }
local respawnDelaySeconds = 60

local spectatorRemote = nil
local spectatorRequestRemote = nil

--============================================================================================--
-- Internal Helper Functions ------------------------------------------------------------------
--============================================================================================--

local function getLivingPlayerUserIds()
	local userIds = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent ~= Players then
			continue
		end
		local character = player.Character
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
			table.insert(userIds, player.UserId)
		end
	end
	return userIds
end

local function hasAnyLivingPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
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

local function notifySpectator(targetPlayer, isSpectating, livingPlayerUserIds, respawnsAt)
	if not spectatorRemote or targetPlayer.Parent ~= Players then
		return
	end
	spectatorRemote:FireClient(targetPlayer, {
		isSpectating = isSpectating,
		livingPlayerUserIds = livingPlayerUserIds or {},
		respawnsAt = respawnsAt,
	})
end

local function notifyAllSpectators()
	if not started or not spectatorRemote then
		return
	end
	local living = getLivingPlayerUserIds()
	for spectatingPlayer, _ in pairs(spectatingPlayers) do
		if spectatingPlayer.Parent == Players then
			local respawnsAt = pendingRespawnByPlayer[spectatingPlayer] and (Workspace:GetServerTimeNow() + respawnDelaySeconds) or nil
			notifySpectator(spectatingPlayer, true, living, respawnsAt)
		end
	end
end

--============================================================================================--
-- Public API ---------------------------------------------------------------------------------
--============================================================================================--

-- Initialize the spectator service (called during match bootstrap)
function SpectatorService.start()
	if started then
		warn("SpectatorService is already running")
		return
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		warn("SpectatorService could not find remotes folder")
		return
	end

	-- Setup remote event for state updates
	spectatorRemote = remotesFolder:FindFirstChild(Config.Remotes.SpectatorState)
	if spectatorRemote and spectatorRemote:IsA("RemoteEvent") then
		-- Already exists, just use it
	elseif spectatorRemote then
		spectatorRemote:Destroy()
		spectatorRemote = nil
	end
	if not spectatorRemote then
		spectatorRemote = Instance.new("RemoteEvent")
		spectatorRemote.Name = Config.Remotes.SpectatorState
		spectatorRemote.Parent = remotesFolder
	end

	-- Setup remote function for requests
	spectatorRequestRemote = remotesFolder:FindFirstChild(Config.Remotes.SpectatorRequest)
	if spectatorRequestRemote and spectatorRequestRemote:IsA("RemoteFunction") then
		-- Already exists, just use it
	elseif spectatorRequestRemote then
		spectatorRequestRemote:Destroy()
		spectatorRequestRemote = nil
	end
	if not spectatorRequestRemote then
		spectatorRequestRemote = Instance.new("RemoteFunction")
		spectatorRequestRemote.Name = Config.Remotes.SpectatorRequest
		spectatorRequestRemote.Parent = remotesFolder
	end

	-- Setup server-side request handler
	if spectatorRequestRemote then
		spectatorRequestRemote.OnServerInvoke = function(player, request)
			return SpectatorService.handleRequest(player, request)
		end
	end

	-- Setup respawn delay from config
	respawnDelaySeconds = (Config.Player and Config.Player.RespawnDelaySeconds) or 60

	started = true
end

-- Stop the spectator service
function SpectatorService.stop()
	started = false
	spectatorRemote = nil
	spectatorRequestRemote = nil
	table.clear(spectatingPlayers)
	table.clear(pendingRespawnByPlayer)
end

-- Handle spectator requests from clients (via SpectatorRequest remote)
-- Returns: { success = bool, message = string?, isSpectating = bool? }
function SpectatorService.handleRequest(player, request)
	if player.Parent ~= Players then
		return { success = false, message = "Player no longer in game" }
	end

	if request == "enterSpectate" then
		if spectatingPlayers[player] == true then
			return { success = false, message = "Already spectating", isSpectating = true }
		end
		if not hasAnyLivingPlayers() then
			return { success = false, message = "No living players to spectate" }
		end
		spectatingPlayers[player] = true
		local respawnsAt = Workspace:GetServerTimeNow() + respawnDelaySeconds
		notifySpectator(player, true, getLivingPlayerUserIds(), respawnsAt)
		notifyAllSpectators()
		return { success = true, isSpectating = true }
	elseif request == "toggleSpectate" then
		local wasSpectating = spectatingPlayers[player] == true
		if wasSpectating then
			spectatingPlayers[player] = nil
			pendingRespawnByPlayer[player] = nil
			notifySpectator(player, false, {}, 0)
			notifyAllSpectators()
			return { success = true, isSpectating = false }
		else
			if not hasAnyLivingPlayers() then
				return { success = false, message = "No living players to spectate" }
			end
			spectatingPlayers[player] = true
			local respawnsAt = Workspace:GetServerTimeNow() + respawnDelaySeconds
			notifySpectator(player, true, getLivingPlayerUserIds(), respawnsAt)
			notifyAllSpectators()
			return { success = true, isSpectating = true }
		end
	elseif request == "spawnNow" then
		if spectatingPlayers[player] ~= true then
			return { success = false, message = "Not in spectator mode" }
		end
		spectatingPlayers[player] = nil
		pendingRespawnByPlayer[player] = nil
		player:LoadCharacter()
		notifySpectator(player, false, {}, 0)
		notifyAllSpectators()
		return { success = true, isSpectating = false }
	elseif request == "exitSpectate" then
		if spectatingPlayers[player] ~= true then
			return { success = false, message = "Not in spectator mode" }
		end
		spectatingPlayers[player] = nil
		pendingRespawnByPlayer[player] = nil
		notifySpectator(player, false, {}, 0)
		notifyAllSpectators()
		return { success = true, isSpectating = false }
	else
		return { success = false, message = ("Unknown request: %s"):format(tostring(request)) }
	end
end

-- Check if a player is spectating
function SpectatorService.isSpectating(player)
	if not player or player.Parent ~= Players then
		return false
	end
	return spectatingPlayers[player] == true
end

-- Get all spectating players
function SpectatorService.getSpectatingPlayers()
	return spectatingPlayers
end

-- Get list of living player UserIds (for notifications)
function SpectatorService.getLivingPlayerUserIds()
	return getLivingPlayerUserIds()
end

-- Called when a player dies
-- Returns true if player entered spectating, false if no living players
function SpectatorService.onPlayerDeath(player)
	if not started then
		return false
	end

	if not hasAnyLivingPlayers() then
		return false
	end

	-- Invalidate any pending respawn
	local respawnToken = (pendingRespawnByPlayer[player] or 0) + 1
	pendingRespawnByPlayer[player] = respawnToken

	-- Mark player as spectating
	spectatingPlayers[player] = true
	notifyAllSpectators()

	-- Schedule the actual respawn
	task.spawn(function()
		task.wait(respawnDelaySeconds)
		if player.Parent ~= Players then
			return
		end

		-- Check if this is still the valid respawn token
		if pendingRespawnByPlayer[player] ~= respawnToken then
			return
		end

		spectatingPlayers[player] = nil
		pendingRespawnByPlayer[player] = nil
		notifySpectator(player, false, {}, 0)
		notifyAllSpectators()
		player:LoadCharacter()
	end)

	return true
end

-- Called when a player respawns (character loads)
function SpectatorService.onPlayerRespawn(player, character)
	local wasSpectating = spectatingPlayers[player] == true
	spectatingPlayers[player] = nil
	pendingRespawnByPlayer[player] = nil
	if wasSpectating and spectatorRemote then
		notifySpectator(player, false, {}, 0)
		notifyAllSpectators()
	end
end

-- Called when a player joins during an active match (late join)
-- Caller must check if match is running before calling
function SpectatorService.onPlayerJoinDuringMatch(player)
	if not started then
		return
	end

	spectatingPlayers[player] = true
	local respawnsAt = Workspace:GetServerTimeNow() + respawnDelaySeconds
	notifySpectator(player, true, getLivingPlayerUserIds(), respawnsAt)
	notifyAllSpectators()

	-- Schedule a respawn for the late joiner
	task.spawn(function()
		task.wait(respawnDelaySeconds)
		if player.Parent ~= Players then
			return
		end
		if spectatingPlayers[player] ~= true then
			return
		end
		spectatingPlayers[player] = nil
		pendingRespawnByPlayer[player] = nil
		notifySpectator(player, false, {}, 0)
		notifyAllSpectators()
		player:LoadCharacter()
	end)
end

-- Called when a player is removed from the game
function SpectatorService.onPlayerRemove(player)
	pendingRespawnByPlayer[player] = nil
	spectatingPlayers[player] = nil
end

return SpectatorService
