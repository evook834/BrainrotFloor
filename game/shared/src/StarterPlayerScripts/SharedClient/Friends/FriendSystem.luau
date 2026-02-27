local FriendSystemController = require(script.Parent:WaitForChild("FriendSystemController"))

local function start()
	FriendSystemController.start()
end

local function open()
	FriendSystemController.open()
end

local function openForUser(userId: number, displayName: string?, userName: string?)
	FriendSystemController.openForUser(userId, displayName, userName)
end

return {
	start = start,
	open = open,
	openForUser = openForUser,
}
