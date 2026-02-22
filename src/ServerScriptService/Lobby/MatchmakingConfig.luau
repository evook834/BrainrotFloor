local Config = {}

-- Shared map place IDs used by all difficulties.
-- If no suitable server is already running for a chosen difficulty,
-- the lobby creates a reserved server on a random place from this list.
Config.MATCH_PLACE_IDS = {
	85990388071078,
	117569264354652,
	93216049725715,
}

-- Legacy single-place fallback (kept for compatibility).
Config.MATCH_PLACE_ID = 85990388071078

-- Shared MemoryStore key used by all lobby and match servers.
Config.MEMORYSTORE_MAP_NAME = "KF_MatchServers_v1"

Config.DIFFICULTIES = {"Easy", "Normal", "Hard"}

Config.MAX_PLAYERS_PER_DIFFICULTY = {
	Easy = 6,
	Normal = 6,
	Hard = 6,
}

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

Config.TELEPORT_RETRIES = 2
Config.TELEPORT_RETRY_DELAY_SECONDS = 1

return Config
