--[[
	RegistryJoinData — Reads and normalizes JoinData.TeleportData for match registry.
	Single place for the teleport payload shape (difficulty, matchId, placeId); extend here if more fields are needed.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ServerScriptService:WaitForChild("Shared")
local Matchmaking = Shared:WaitForChild("Matchmaking")
local Config = require(Matchmaking:WaitForChild("MatchmakingConfig"))

local RegistryJoinData = {}

--- @param player Player
--- @return { difficulty: string?, matchId: string?, placeId: number? }?
function RegistryJoinData.read(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if type(teleportData) ~= "table" then
		return nil
	end

	local difficulty = teleportData.difficulty
	if not Config.isDifficulty(difficulty) then
		difficulty = nil
	end

	local matchId = teleportData.matchId
	if type(matchId) ~= "string" then
		matchId = nil
	end

	local placeId = type(teleportData.placeId) == "number" and teleportData.placeId or tonumber(teleportData.placeId)

	return {
		difficulty = difficulty,
		matchId = matchId,
		placeId = placeId,
	}
end

return RegistryJoinData
