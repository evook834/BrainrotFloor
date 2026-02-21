local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local WaveService = require(script.Services.WaveService)

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local remotesFolder = ensureFolder(ReplicatedStorage, Config.Remotes.Folder)
if not remotesFolder:FindFirstChild(Config.Remotes.WaveState) then
	local waveStateRemote = Instance.new("RemoteEvent")
	waveStateRemote.Name = Config.Remotes.WaveState
	waveStateRemote.Parent = remotesFolder
end

ensureFolder(Workspace, Config.Enemy.SpawnFolderName)
ensureFolder(Workspace, Config.Enemy.ContainerName)

WaveService.start()
