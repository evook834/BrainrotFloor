--[[
	Lobby class remotes — Binds ClassGetData and ClassSelect in the Lobby so players can
	select their class before match. Selection is persisted via PlayerDataService and applies in Match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local SettingsService = require(ServerScriptService.Shared.Settings.SettingsService)
local ClassDataPayload = require(ServerScriptService.Shared.Classes.ClassDataPayload)

PlayerDataService.start()
SettingsService.start()

local function ensureRemote(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if instance and instance.ClassName == className then
		return instance
	end
	if instance then
		instance:Destroy()
	end
	instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

ClassDataPayload.init()

local function queuePlayerClassAttributeSync(player)
	task.defer(function()
		if player.Parent == Players then
			ClassDataPayload.syncPlayerClassAttribute(player)
		end
	end)
end

Players.PlayerAdded:Connect(queuePlayerClassAttributeSync)

for _, player in ipairs(Players:GetPlayers()) do
	queuePlayerClassAttributeSync(player)
end

local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = Config.Remotes.Folder
	remotesFolder.Parent = ReplicatedStorage
end

local classGetDataFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ClassGetData)
local classSelectFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ClassSelect)

classGetDataFunction.OnServerInvoke = function(player)
	if not player or not player:IsA("Player") then
		return { success = false, message = "Invalid player." }
	end
	return ClassDataPayload.buildPayloadForPlayer(player)
end

classSelectFunction.OnServerInvoke = function(player, classId)
	if not player or not player:IsA("Player") then
		return { success = false, message = "Invalid player." }
	end
	return ClassDataPayload.selectClass(player, classId)
end
