local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)

local Config = {}

-- Runtime routing for shared scripts across multiple places.
-- Set to "Lobby" or "Match" only when you need to force behavior during testing.
Config.FORCE_PLACE_ROLE = nil

Config.LOBBY_PLACE_ID = PlaceConfig.LOBBY_PLACE_ID
Config.MATCH_PLACE_IDS = PlaceConfig.MATCH_PLACE_IDS
Config.MATCH_PLACE_ID = PlaceConfig.MATCH_PLACE_ID

-- Shared MemoryStore key used by all lobby and match servers.
Config.MEMORYSTORE_MAP_NAME = "KF_MatchServers_v1"

-- Ordered difficulty list for matchmaking; single source of truth from shared DifficultyConfig.
Config.DIFFICULTIES = type(GameConfig.Difficulty) == "table" and type(GameConfig.Difficulty.OrderedNames) == "table"
	and GameConfig.Difficulty.OrderedNames
	or { "Easy", "Normal", "Hard" }

-- Max players per difficulty; derived from DifficultyConfig (Settings[].MaxPlayers or DefaultMaxPlayers).
Config.MAX_PLAYERS_PER_DIFFICULTY = {}
do
	local diff = GameConfig.Difficulty
	local defaultMax = (type(diff) == "table" and type(diff.DefaultMaxPlayers) == "number" and diff.DefaultMaxPlayers > 0)
		and diff.DefaultMaxPlayers or 6
	for _, name in ipairs(Config.DIFFICULTIES) do
		local settings = type(diff) == "table" and type(diff.Settings) == "table" and diff.Settings[name]
		local n = type(settings) == "table" and type(settings.MaxPlayers) == "number" and settings.MaxPlayers > 0
			and settings.MaxPlayers or defaultMax
		Config.MAX_PLAYERS_PER_DIFFICULTY[name] = n
	end
end

Config.DEFAULT_MAX_PLAYERS = 6

function Config.isDifficulty(value)
	if type(value) ~= "string" or value == "" then
		return false
	end
	for _, d in ipairs(Config.DIFFICULTIES) do
		if d == value then
			return true
		end
	end
	return false
end

function Config.getMaxPlayersForDifficulty(difficulty, fallbackMax)
	local n = tonumber(Config.MAX_PLAYERS_PER_DIFFICULTY[difficulty])
	if n and n > 0 then
		return n
	end
	return fallbackMax or Config.DEFAULT_MAX_PLAYERS
end

Config.ENTRY_TTL_SECONDS = 120
Config.STALE_AFTER_SECONDS = 30
Config.HEARTBEAT_SECONDS = 5
Config.SCAN_PAGE_SIZE = 100

Config.BUTTONS_FOLDER_NAME = "DifficultyButtons"
Config.BUTTON_DIFFICULTY_ATTRIBUTE = "Difficulty"
Config.PROMPT_HOLD_DURATION = 1.75
Config.PROMPT_MAX_DISTANCE = 12
Config.REQUEST_COOLDOWN_SECONDS = 2
Config.ALLOW_PRIVATE_SERVER_LOBBY = false
Config.MAP_VOTE_REVEAL_DELAY_SECONDS = 5
Config.MAP_VOTE_DURATION_SECONDS = 60

Config.TELEPORT_RETRIES = 2
Config.TELEPORT_RETRY_DELAY_SECONDS = 1

return Config
