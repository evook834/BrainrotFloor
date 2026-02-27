--[[
	SettingsRemotesUtil - Utilities for resolving Settings system remotes.
	Provides centralized remote resolution to avoid duplication across controllers.

	Note: This module is in StarterPlayerScripts/SharedClient which cannot require
	ReplicatedStorage. We use game:GetService("ReplicatedStorage") to access paths
	instead of require() to avoid dependency issues.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_WAIT_TIMEOUT_SECONDS = 15

local SettingsRemotesUtil = {}

function SettingsRemotesUtil.resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
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

function SettingsRemotesUtil.getSharedRemotesFolder(): Instance?
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if not sharedFolder or not sharedFolder:IsA("Folder") then
		return nil
	end

	local ConfigModule = sharedFolder:FindFirstChild("GameConfig")
	if not ConfigModule or not ConfigModule:IsA("ModuleScript") then
		return nil
	end

	local ok, Config = pcall(require, ConfigModule)
	if not ok or not Config or not Config.Remotes or not Config.Remotes.Folder then
		return nil
	end

	return ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
end

function SettingsRemotesUtil.resolveSettingsGetFunction(): RemoteFunction?
	local remotesFolder = SettingsRemotesUtil.getSharedRemotesFolder()
	if not remotesFolder then
		return nil
	end

	local ok, Config = pcall(function()
		return require(ReplicatedStorage.Shared.GameConfig)
	end)
	if not ok or not Config or not Config.Remotes then
		return nil
	end

	return SettingsRemotesUtil.resolveRemote(remotesFolder, Config.Remotes.SettingsGet, "RemoteFunction")
end

function SettingsRemotesUtil.resolveSettingsSaveRemote(): RemoteEvent?
	local remotesFolder = SettingsRemotesUtil.getSharedRemotesFolder()
	if not remotesFolder then
		return nil
	end

	local ok, Config = pcall(function()
		return require(ReplicatedStorage.Shared.GameConfig)
	end)
	if not ok or not Config or not Config.Remotes then
		return nil
	end

	return SettingsRemotesUtil.resolveRemote(remotesFolder, Config.Remotes.SettingsSave, "RemoteEvent")
end

return SettingsRemotesUtil
