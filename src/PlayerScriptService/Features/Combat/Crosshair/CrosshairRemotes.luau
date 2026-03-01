--[[
	CrosshairRemotes — Resolves weapon aim, fire, and reload remotes for the crosshair/combat client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)

local weaponAimRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.WeaponAim) or nil
local weaponFireRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.WeaponFire) or nil
local weaponReloadRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.WeaponReload) or nil

local function getRemotes()
	return {
		weaponAim = weaponAimRemote,
		weaponFire = weaponFireRemote,
		weaponReload = weaponReloadRemote,
	}
end

return {
	getRemotes = getRemotes,
	getWeaponAim = function()
		return weaponAimRemote
	end,
	getWeaponFire = function()
		return weaponFireRemote
	end,
	getWeaponReload = function()
		return weaponReloadRemote
	end,
}
