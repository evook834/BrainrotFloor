--[[ Lobby class selection UI — thin launcher for shared ClassUi. ]]
local StarterPlayer = game:GetService("StarterPlayer")
local SharedClient = StarterPlayer.StarterPlayerScripts.SharedClient
local ClassUi = require(SharedClient:WaitForChild("Classes"):WaitForChild("ClassUi"))
ClassUi.run({ isLobby = true })
