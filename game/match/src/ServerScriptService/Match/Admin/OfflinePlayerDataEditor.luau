--[[
	OfflinePlayerDataEditor — Server-only. Binds EditOfflinePlayerData RemoteFunction.
	Allows editing saved player data by userId when the player is offline (Studio only by default).
	Payload: (userId: number, edits: { { path: string, value: any } }) -> { success: boolean, message?: string }
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)

local function setPath(data, path, value)
	if type(data) ~= "table" or type(path) ~= "string" or path == "" then
		return
	end
	local parts = string.split(path, ".")
	local current = data
	for i = 1, #parts - 1 do
		local key = parts[i]
		if key == "" then
			return
		end
		if current[key] == nil then
			current[key] = {}
		end
		if type(current[key]) ~= "table" then
			return
		end
		current = current[key]
	end
	local lastKey = parts[#parts]
	if lastKey ~= "" then
		current[lastKey] = value
	end
end

local function applyEdits(data, edits)
	if type(edits) ~= "table" then
		return
	end
	for _, edit in ipairs(edits) do
		if type(edit) == "table" and type(edit.path) == "string" then
			setPath(data, edit.path, edit.value)
		end
	end
end

local function ensureRemoteFunction(parent, name)
	local instance = parent:FindFirstChild(name)
	if instance and instance:IsA("RemoteFunction") then
		return instance
	end
	if instance then
		instance:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function canEditOfflineData(player)
	return RunService:IsStudio()
end

local function start()
	if not PlayerDataService.isReady() then
		warn("[OfflinePlayerDataEditor] PlayerDataService not ready; start it first (e.g. via GameBootstrap).")
		return
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = Config.Remotes.Folder
		remotesFolder.Parent = ReplicatedStorage
	end

	local remote = ensureRemoteFunction(remotesFolder, Config.Remotes.EditOfflinePlayerData)
	remote.OnServerInvoke = function(caller, userId, edits)
		if not canEditOfflineData(caller) then
			return { success = false, message = "Not allowed" }
		end
		if type(userId) ~= "number" then
			userId = tonumber(userId)
		end
		if userId == nil or userId < 1 then
			return { success = false, message = "Invalid userId" }
		end
		local success, err = PlayerDataService.editOfflineUser(userId, function(data)
			applyEdits(data, edits or {})
		end)
		if success then
			return { success = true }
		end
		return { success = false, message = err or "Unknown error" }
	end
end

return { start = start }
