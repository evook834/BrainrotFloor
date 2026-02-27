--[[
	Return-to-lobby: resolve lobby place id, send a single player to lobby with retries and loading UI.
	Cooldown and in-flight state to avoid duplicate requests. Used by GameBootstrap.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local BootstrapUtil = require(script.Parent.BootstrapUtil)

local ReturnToLobbyFlow = {}

local returnLobbyInFlightByUserId = {}
local returnLobbyLastRequestByUserId = {}

function ReturnToLobbyFlow.resolveLobbyPlaceId(matchmakingConfig)
	local lobbyPlaceId = BootstrapUtil.toNumber(matchmakingConfig.LOBBY_PLACE_ID, nil)
	if lobbyPlaceId == nil then
		return nil
	end
	if lobbyPlaceId ~= math.floor(lobbyPlaceId) then
		return nil
	end
	if lobbyPlaceId <= 0 or lobbyPlaceId == BootstrapUtil.PLACEHOLDER_PLACE_ID then
		return nil
	end
	return lobbyPlaceId
end

function ReturnToLobbyFlow.sendPlayerToLobby(player, matchmakingConfig, teleportLoadingRemote)
	if player.Parent ~= Players then
		return false
	end

	local lobbyPlaceId = ReturnToLobbyFlow.resolveLobbyPlaceId(matchmakingConfig)
	if not lobbyPlaceId then
		warn("[ReturnToLobbyFlow] LOBBY_PLACE_ID is invalid. Cannot return players to lobby.")
		return false
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		reason = "GameOver",
		fromPlaceId = game.PlaceId,
		matchId = Workspace:GetAttribute("MatchId"),
		queuedAt = BootstrapUtil.nowSeconds(),
	})

	local retries = math.max(1, BootstrapUtil.toNumber(matchmakingConfig.TELEPORT_RETRIES, 1))

	if teleportLoadingRemote then
		teleportLoadingRemote:FireClient(player, {
			action = "Start",
			title = "Returning to lobby",
			message = "Teleporting you back to the lobby...",
		})
		task.wait(0.1)
	end

	for attempt = 1, retries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(lobbyPlaceId, { player }, options)
		end)
		if ok then
			return true
		end
		warn(("[ReturnToLobbyFlow] Return-to-lobby teleport failed (attempt %d) for %s: %s"):format(
			attempt, player.Name, tostring(err)))
		if attempt < retries then
			task.wait(BootstrapUtil.toNumber(matchmakingConfig.TELEPORT_RETRY_DELAY_SECONDS, 1))
		end
	end

	if teleportLoadingRemote then
		teleportLoadingRemote:FireClient(player, {
			action = "Failed",
			message = "Could not return to the lobby. Please try again.",
		})
	end
	return false
end

function ReturnToLobbyFlow.createHandler(matchmakingConfig, teleportLoadingRemote, shouldRunMatchSystems)
	return function(player)
		if not (shouldRunMatchSystems and shouldRunMatchSystems()) then
			return
		end

		local userId = player.UserId
		if returnLobbyInFlightByUserId[userId] then
			return
		end

		local currentTime = BootstrapUtil.nowSeconds()
		local previousRequestTime = BootstrapUtil.toNumber(returnLobbyLastRequestByUserId[userId], 0)
		local cooldownSeconds = math.max(0, BootstrapUtil.toNumber(matchmakingConfig.REQUEST_COOLDOWN_SECONDS, 1))
		if (currentTime - previousRequestTime) < cooldownSeconds then
			return
		end

		returnLobbyLastRequestByUserId[userId] = currentTime
		returnLobbyInFlightByUserId[userId] = true

		local ok, didTeleport = pcall(ReturnToLobbyFlow.sendPlayerToLobby, player, matchmakingConfig, teleportLoadingRemote)
		returnLobbyInFlightByUserId[userId] = nil

		if not ok then
			warn(("[ReturnToLobbyFlow] Return-to-lobby request failed for %s: %s"):format(
				player.Name, tostring(didTeleport)))
			return
		end
		if not didTeleport then
			warn(("[ReturnToLobbyFlow] Return-to-lobby request could not teleport %s"):format(player.Name))
		end
	end
end

function ReturnToLobbyFlow.clearInFlight(player)
	if player then
		returnLobbyInFlightByUserId[player.UserId] = nil
		returnLobbyLastRequestByUserId[player.UserId] = nil
	end
end

return ReturnToLobbyFlow
