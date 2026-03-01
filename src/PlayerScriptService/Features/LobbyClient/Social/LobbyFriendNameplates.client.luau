local SharedClient = script.Parent.Parent.Parent:WaitForChild("SharedClient")
local PlayerNameplates = require(SharedClient:WaitForChild("Friends"):WaitForChild("PlayerNameplates"))

PlayerNameplates.run({
	interactive = true,
})
