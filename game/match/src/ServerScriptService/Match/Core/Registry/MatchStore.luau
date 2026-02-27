--[[
	MatchStore — Thin wrapper around MemoryStore SortedMap for match registry entries.
	Exposes get/update/remove with pcall and optional warning on failure.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")

local MatchStore = {}

--- Create a store interface for the given map name.
--- @param mapName string
--- @param defaultTtlSeconds number
--- @param logPrefix string — used when logging failures (e.g. "[MatchServerRegistry]")
--- @return { get: (key: string) -> (boolean, any), update: (key: string, updater: (any, any) -> (any?, any?), ttlSeconds: number?) -> boolean, remove: (key: string) -> boolean }
function MatchStore.create(mapName, defaultTtlSeconds, logPrefix)
	local map = MemoryStoreService:GetSortedMap(mapName)
	local prefix = logPrefix or "[MatchStore]"

	local function safeCall(label, callback)
		local ok, a, b = pcall(callback)
		if not ok then
			warn(("%s %s failed: %s"):format(prefix, label, tostring(a)))
		end
		return ok, a, b
	end

	return {
		get = function(key)
			local ok, value = safeCall("GetAsync", function()
				return map:GetAsync(key)
			end)
			return ok, value
		end,

		update = function(key, updater, ttlSeconds)
			local ttl = ttlSeconds or defaultTtlSeconds
			local ok = safeCall("UpdateAsync", function()
				map:UpdateAsync(key, updater, ttl)
			end)
			return ok
		end,

		remove = function(key)
			local ok = safeCall("RemoveAsync", function()
				map:RemoveAsync(key)
			end)
			return ok
		end,
	}
end

return MatchStore
