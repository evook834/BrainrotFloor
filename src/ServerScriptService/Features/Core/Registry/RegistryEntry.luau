--[[
	RegistryEntry — Builds or updates the MemoryStore entry shape for match server heartbeats.
	Single place to extend or change the entry schema; preserves existing accessCode.
]]

local function toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end
	return n
end

local RegistryEntry = {}

--- @param existingEntry table? — existing entry (may be nil); accessCode is preserved
--- @param opts { difficulty: string, currentTime: number, currentPlayers: number, placeId: number, jobId: string, privateServerId: string, maxPlayers: number }
--- @return table — entry suitable for UpdateAsync value
function RegistryEntry.buildHeartbeatEntry(existingEntry, opts)
	local entry = type(existingEntry) == "table" and existingEntry or {}
	entry.difficulty = opts.difficulty
	entry.placeId = opts.placeId
	entry.privateServerId = opts.privateServerId
	entry.serverJobId = opts.jobId
	entry.playerCount = opts.currentPlayers
	entry.maxPlayers = opts.maxPlayers
	entry.pendingSlots = math.max(toNumber(entry.pendingSlots, 0), 0)
	entry.lastHeartbeat = opts.currentTime
	entry.createdAt = toNumber(entry.createdAt, opts.currentTime)
	-- accessCode is set by lobby when creating the reserved server; never overwritten here
	return entry
end

--- @param entry table
--- @return boolean
function RegistryEntry.hasAccessCode(entry)
	return type(entry) == "table"
		and type(entry.accessCode) == "string"
		and entry.accessCode ~= ""
end

--- Apply pending-slot consume update to an existing entry (mutates and returns it).
--- @param entry table
--- @param currentTime number
--- @param currentPlayers number
--- @return table
function RegistryEntry.applyConsumePendingSlot(entry, currentTime, currentPlayers)
	local pendingSlots = math.max(toNumber(entry.pendingSlots, 0), 0)
	entry.pendingSlots = math.max(pendingSlots - 1, 0)
	entry.playerCount = currentPlayers
	entry.lastHeartbeat = currentTime
	return entry
end

return RegistryEntry
