--[[
	ShopUiRemotes — Resolves Remotes folder and shop remotes (ShopOpen, ShopGetCatalog, ShopBuyWeapon, ShopBuyAmmo, WaveState, ClassState).
	Centralizes resolution and warnings so ShopUiController stays focused on logic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_WAIT_TIMEOUT = 15

local Config = require(ReplicatedStorage.Shared.GameConfig)

export type ShopUiRemotesResult = {
	remotesFolder: Instance?,
	shopOpen: RemoteEvent?,
	shopGetCatalog: RemoteFunction?,
	shopBuyWeapon: RemoteFunction?,
	shopBuyAmmo: RemoteFunction?,
	waveState: RemoteEvent?,
	classState: RemoteEvent?,
	allRequiredPresent: boolean,
}

local function resolveRemote(remotesFolder: Instance?, name: string, className: string): (RemoteEvent | RemoteFunction)?
	if not remotesFolder then
		return nil
	end
	local candidate = remotesFolder:WaitForChild(name, REMOTE_WAIT_TIMEOUT)
	if candidate and candidate:IsA(className) then
		return candidate :: any
	end
	return nil
end

local function findRemote(remotesFolder: Instance?, name: string): Instance?
	if not remotesFolder then
		return nil
	end
	return remotesFolder:FindFirstChild(name)
end

function resolve(): ShopUiRemotesResult
	local folderName = Config.Remotes and Config.Remotes.Folder or "Remotes"
	local remotesFolder = ReplicatedStorage:WaitForChild(folderName, REMOTE_WAIT_TIMEOUT) :: Instance?
	if not remotesFolder then
		warn("ShopUi could not find ReplicatedStorage/Remotes")
		return {
			remotesFolder = nil,
			shopOpen = nil,
			shopGetCatalog = nil,
			shopBuyWeapon = nil,
			shopBuyAmmo = nil,
			waveState = nil,
			classState = nil,
			allRequiredPresent = false,
		}
	end

	local shopOpen = resolveRemote(remotesFolder, Config.Remotes.ShopOpen, "RemoteEvent") :: RemoteEvent?
	local shopGetCatalog = resolveRemote(remotesFolder, Config.Remotes.ShopGetCatalog, "RemoteFunction") :: RemoteFunction?
	local shopBuyWeapon = resolveRemote(remotesFolder, Config.Remotes.ShopBuyWeapon, "RemoteFunction") :: RemoteFunction?
	local shopBuyAmmo = resolveRemote(remotesFolder, Config.Remotes.ShopBuyAmmo, "RemoteFunction") :: RemoteFunction?

	local waveStateChild = findRemote(remotesFolder, Config.Remotes.WaveState)
	local waveState = (waveStateChild and waveStateChild:IsA("RemoteEvent")) and waveStateChild :: RemoteEvent or nil

	local classStateChild = findRemote(remotesFolder, Config.Remotes.ClassState)
	local classState = (classStateChild and classStateChild:IsA("RemoteEvent")) and classStateChild :: RemoteEvent or nil

	local allRequiredPresent = shopOpen ~= nil and shopGetCatalog ~= nil and shopBuyWeapon ~= nil and shopBuyAmmo ~= nil
	if not allRequiredPresent then
		warn("ShopUi is missing one or more shop remotes")
	end

	return {
		remotesFolder = remotesFolder,
		shopOpen = shopOpen,
		shopGetCatalog = shopGetCatalog,
		shopBuyWeapon = shopBuyWeapon,
		shopBuyAmmo = shopBuyAmmo,
		waveState = waveState,
		classState = classState,
		allRequiredPresent = allRequiredPresent,
	}
end

return {
	resolve = resolve,
}
