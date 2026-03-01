--[[
	Creates and ensures the Remotes folder and all match remotes (events + WaveEnemiesRemaining IntValue).
	Returns the remotes folder and a map of created/found remotes by name for binding.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootstrapUtil = require(script.Parent.BootstrapUtil)

local RemotesSetup = {}

function RemotesSetup.run(configRemotes)
	local folderName = configRemotes.Folder or "Remotes"
	local remotesFolder = BootstrapUtil.ensureFolder(ReplicatedStorage, folderName)

	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.WaveState)

	local waveEnemiesRemaining = remotesFolder:FindFirstChild("WaveEnemiesRemaining")
	if not waveEnemiesRemaining or not waveEnemiesRemaining:IsA("IntValue") then
		if waveEnemiesRemaining then
			waveEnemiesRemaining:Destroy()
		end
		waveEnemiesRemaining = Instance.new("IntValue")
		waveEnemiesRemaining.Name = "WaveEnemiesRemaining"
		waveEnemiesRemaining.Value = 0
		waveEnemiesRemaining.Parent = remotesFolder
	end

	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.ReturnToLobby)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.MapVote)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.WeaponAim)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.WeaponFire)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.WeaponReload)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.DamageIndicator)
	BootstrapUtil.ensureRemoteEvent(remotesFolder, configRemotes.TeleportLoading)

	return {
		folder = remotesFolder,
		WaveState = remotesFolder:FindFirstChild(configRemotes.WaveState),
		WaveEnemiesRemaining = waveEnemiesRemaining,
		ReturnToLobby = remotesFolder:FindFirstChild(configRemotes.ReturnToLobby),
		MapVote = remotesFolder:FindFirstChild(configRemotes.MapVote),
		TeleportLoading = remotesFolder:FindFirstChild(configRemotes.TeleportLoading),
	}
end

return RemotesSetup
