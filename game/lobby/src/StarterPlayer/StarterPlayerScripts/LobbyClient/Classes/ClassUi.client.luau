--[[ Lobby class selection UI — thin launcher for shared ClassUi. ]]
local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local ClassUi = require(SharedClient:WaitForChild("Classes"):WaitForChild("ClassUi"))
ClassUi.run({ isLobby = true })
