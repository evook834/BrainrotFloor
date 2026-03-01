--[[
	WaveHudRemotes — Resolves Remotes folder and Wave HUD remotes (WaveState, ReturnToLobby, MapVote).
	Centralizes resolution and warnings so WaveHudController stays focused on logic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_WAIT_TIMEOUT = 15

local Config = require(ReplicatedStorage.Shared.GameConfig)

export type WaveHudRemotesResult = {
	remotesFolder: Instance?,
	waveState: RemoteEvent?,
	returnToLobby: RemoteEvent?,
	mapVote: RemoteEvent?,
}

local function resolveRemote(remotesFolder: Instance?, name: string, className: string): (RemoteEvent | RemoteFunction)?
	if not remotesFolder then return nil end
	local candidate = remotesFolder:WaitForChild(name, REMOTE_WAIT_TIMEOUT)
	if candidate and candidate:IsA(className) then
		return candidate :: any
	end
	return nil
end

function resolve(): WaveHudRemotesResult
	local folderName = Config.Remotes and Config.Remotes.Folder or "Remotes"
	local remotesFolder = ReplicatedStorage:WaitForChild(folderName, REMOTE_WAIT_TIMEOUT) :: Instance?
	if not remotesFolder then
		warn("WaveHud could not find ReplicatedStorage/Remotes")
		return { remotesFolder = nil, waveState = nil, returnToLobby = nil, mapVote = nil }
	end

	local waveState = resolveRemote(remotesFolder, Config.Remotes.WaveState, "RemoteEvent")
	if not waveState then
		warn("WaveHud could not find ReplicatedStorage/Remotes/WaveState")
	end

	local returnToLobby = resolveRemote(remotesFolder, Config.Remotes.ReturnToLobby, "RemoteEvent") :: RemoteEvent?
	if not returnToLobby then
		local child = remotesFolder:FindFirstChild(Config.Remotes.ReturnToLobby)
		if child and not child:IsA("RemoteEvent") then
			warn("WaveHud found ReturnToLobby remote with unexpected class")
		else
			warn("WaveHud could not find ReplicatedStorage/Remotes/ReturnToLobby")
		end
	end

	local mapVote = resolveRemote(remotesFolder, Config.Remotes.MapVote, "RemoteEvent") :: RemoteEvent?
	if not mapVote then
		local child = remotesFolder:FindFirstChild(Config.Remotes.MapVote)
		if child and not child:IsA("RemoteEvent") then
			warn("WaveHud found MapVote remote with unexpected class")
		else
			warn("WaveHud could not find ReplicatedStorage/Remotes/MapVote")
		end
	end

	return {
		remotesFolder = remotesFolder,
		waveState = waveState,
		returnToLobby = returnToLobby,
		mapVote = mapVote,
	}
end

return {
	resolve = resolve,
}
