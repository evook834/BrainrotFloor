--[[
	XpBarHudRemotes — Resolves Remotes folder and class remotes (ClassGetData, ClassState).
	Centralizes resolution and warnings so XpBarHudController stays focused on logic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_WAIT_TIMEOUT = 15

local Config = require(ReplicatedStorage.Shared.GameConfig)

export type XpBarHudRemotesResult = {
	classGetData: RemoteFunction?,
	classState: RemoteEvent?,
}

local function resolveRemote(remotesFolder: Instance?, name: string, className: string): (RemoteEvent | RemoteFunction)?
	if not remotesFolder then
		return nil
	end
	local candidate = remotesFolder:WaitForChild(name, REMOTE_WAIT_TIMEOUT)
	if candidate and candidate:IsA(className) then
		return candidate
	end
	return nil
end

function resolve(): XpBarHudRemotesResult
	local folderName = Config.Remotes and Config.Remotes.Folder or "Remotes"
	local remotesFolder = ReplicatedStorage:WaitForChild(folderName, REMOTE_WAIT_TIMEOUT)
	if not remotesFolder then
		warn("XpBarHud could not find ReplicatedStorage/Remotes")
		return { classGetData = nil, classState = nil }
	end

	local classGetData = resolveRemote(remotesFolder, Config.Remotes.ClassGetData, "RemoteFunction")
	if not classGetData then
		warn("XpBarHud could not find ReplicatedStorage/Remotes/ClassGetData")
	end

	local classState = remotesFolder:FindFirstChild(Config.Remotes.ClassState)
	if classState and not classState:IsA("RemoteEvent") then
		classState = nil
	end

	return {
		classGetData = classGetData,
		classState = classState,
	}
end

return {
	resolve = resolve,
}
