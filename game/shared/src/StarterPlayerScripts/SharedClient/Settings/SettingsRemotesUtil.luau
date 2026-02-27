local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_WAIT_TIMEOUT_SECONDS = 15

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Config = require(sharedFolder:WaitForChild("GameConfig"))

local function resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	candidate = remotesFolder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT_SECONDS)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

local function getSharedRemotesFolder(): Instance?
	return ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT_TIMEOUT_SECONDS)
end

local function resolveSettingsSaveRemote(): RemoteEvent?
	local remotesFolder = getSharedRemotesFolder()
	if not remotesFolder then
		return nil
	end

	return resolveRemote(remotesFolder, Config.Remotes.SettingsSave, "RemoteEvent") :: RemoteEvent?
end

return {
	resolveRemote = resolveRemote,
	getSharedRemotesFolder = getSharedRemotesFolder,
	resolveSettingsSaveRemote = resolveSettingsSaveRemote,
}

