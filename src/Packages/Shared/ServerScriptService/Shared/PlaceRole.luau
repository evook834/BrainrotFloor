local PLACEHOLDER_PLACE_ID = 1234567890
local VALID_ROLES = {
	Lobby = true,
	Match = true,
}

local Config = require(script.Parent:WaitForChild("MatchmakingConfig"))

local function toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end

	return n
end

local function addMatchPlaceId(placeIdLookup, rawPlaceId)
	local placeId = toNumber(rawPlaceId, nil)
	if placeId == nil then
		return
	end

	if placeId ~= math.floor(placeId) then
		return
	end

	if placeId <= 0 then
		return
	end

	if placeId == PLACEHOLDER_PLACE_ID then
		return
	end

	placeIdLookup[placeId] = true
end

local function collectMatchPlaceIdLookup()
	local placeIdLookup = {}

	if type(Config.MATCH_PLACE_IDS) == "table" then
		for _, rawPlaceId in ipairs(Config.MATCH_PLACE_IDS) do
			addMatchPlaceId(placeIdLookup, rawPlaceId)
		end
	end

	if next(placeIdLookup) == nil then
		addMatchPlaceId(placeIdLookup, Config.MATCH_PLACE_ID)
	end

	return placeIdLookup
end

local matchPlaceIdLookup = collectMatchPlaceIdLookup()

local function isKnownRole(roleName)
	return VALID_ROLES[roleName] == true
end

local function getForcedRole()
	local forcedRole = Config.FORCE_PLACE_ROLE
	if type(forcedRole) ~= "string" or forcedRole == "" then
		return nil
	end

	if not isKnownRole(forcedRole) then
		warn(("[PlaceRole] Ignoring invalid FORCE_PLACE_ROLE '%s'."):format(tostring(forcedRole)))
		return nil
	end

	return forcedRole
end

local PlaceRole = {}

function PlaceRole.getRole()
	local forcedRole = getForcedRole()
	if forcedRole then
		return forcedRole
	end

	local currentPlaceId = game.PlaceId
	if matchPlaceIdLookup[currentPlaceId] then
		return "Match"
	end

	local lobbyPlaceId = toNumber(Config.LOBBY_PLACE_ID, nil)
	if lobbyPlaceId and lobbyPlaceId > 0 and currentPlaceId == lobbyPlaceId then
		return "Lobby"
	end

	if game.PrivateServerId ~= "" then
		return "Match"
	end

	return "Lobby"
end

function PlaceRole.shouldRunLobbySystems()
	if PlaceRole.getRole() ~= "Lobby" then
		return false
	end

	if game.PrivateServerId ~= "" and not Config.ALLOW_PRIVATE_SERVER_LOBBY then
		return false
	end

	return true
end

function PlaceRole.shouldRunMatchSystems()
	return PlaceRole.getRole() == "Match"
end

return PlaceRole
