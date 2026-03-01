--[[
	Place IDs for lobby and match. Used by client (e.g. ClientEntry) to detect
	place role and by server (MatchmakingConfig) for matchmaking.
]]

local PlaceConfig = {}

PlaceConfig.LOBBY_PLACE_ID = 72744824144957

PlaceConfig.MATCH_PLACE_IDS = {
	124937386174828,
	133374266851323,
	121897811274933,
}

-- Legacy single-place fallback (kept for compatibility).
PlaceConfig.MATCH_PLACE_ID = 117308283626623

return PlaceConfig
