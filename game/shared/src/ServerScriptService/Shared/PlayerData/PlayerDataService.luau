--[[
	PlayerDataService — Wraps DataService (leifstout/dataService) for persistent,
	auto-replicated player data. Persistence is via ProfileStore (saves on session end).
	Used by Settings, ClassService, and money/inventory.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTemplate = require(ReplicatedStorage.Shared.Player.PlayerDataTemplate)

local PlayerDataService = {}

local PROFILE_STORE_INDEX = "BrainrotFloor_PlayerData_v1"

local started = false
local dataService = nil

local function getDataService()
	if dataService then
		return dataService
	end

	local packages = ReplicatedStorage:FindFirstChild("Packages")
	if not packages then
		warn("[PlayerDataService] Packages not found (run wally install)")
		return nil
	end

	local dataServiceModule = packages:FindFirstChild("DataService")
	if not dataServiceModule then
		warn("[PlayerDataService] DataService package not found")
		return nil
	end

	local ok, module = pcall(require, dataServiceModule)
	if not ok or not module or not module.server then
		warn("[PlayerDataService] Failed to require DataService.server:", tostring(module))
		return nil
	end

	dataService = module.server
	return dataService
end

-- Persistence: ProfileStore (used by DataService) saves to DataStore on session end (PlayerRemoving).
-- No periodic save loop needed; DataService handles leave and BindToClose via ProfileStore.

function PlayerDataService.start()
	if started then
		return true
	end

	local ds = getDataService()
	if not ds then
		return false
	end

	local ok, err = pcall(function()
		ds:init({
			template = PlayerDataTemplate,
			profileStoreIndex = PROFILE_STORE_INDEX,
		})
	end)

	if not ok then
		warn("[PlayerDataService] DataService:init failed:", tostring(err))
		return false
	end

	started = true
	return true
end

function PlayerDataService.isReady()
	return started and dataService ~= nil
end

function PlayerDataService.get(player, path)
	local ds = getDataService()
	if not ds then
		return nil
	end
	return ds:get(player, path)
end

function PlayerDataService.set(player, path, value, dontReplicate)
	local ds = getDataService()
	if not ds then
		return
	end
	ds:set(player, path, value, dontReplicate)
end

function PlayerDataService.update(player, path, callback, dontReplicate)
	local ds = getDataService()
	if not ds then
		return nil
	end
	return ds:update(player, path, callback, dontReplicate)
end

function PlayerDataService.waitForData(player)
	local ds = getDataService()
	if not ds then
		return nil
	end
	return ds:waitForData(player)
end

function PlayerDataService.getChangedSignal(player, path)
	local ds = getDataService()
	if not ds then
		return nil
	end
	return ds:getChangedSignal(player, path)
end

function PlayerDataService.hasProfile(player)
	local ds = getDataService()
	if not ds then
		return false
	end
	return ds:hasProfile(player)
end

function PlayerDataService.getProfile(player)
	local ds = getDataService()
	if not ds then
		return nil
	end
	return ds:getProfile(player)
end

return PlayerDataService
