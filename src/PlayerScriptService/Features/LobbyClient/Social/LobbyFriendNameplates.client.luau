local StarterPlayer = game:GetService("StarterPlayer")
local SharedClient = StarterPlayer.StarterPlayerScripts.SharedClient
local PlayerNameplates = require(SharedClient.Friends.PlayerNameplates)

PlayerNameplates.run({
	interactive = true,
})
