--[[
	ClassChangedClientEvent — Client-side signal when the local player's class selection
	has been accepted by the server. Used by Shop and XpBar to refresh without relying on
	ClassState replication. Class UI fires this when ClassSelect returns success.
]]

local event = Instance.new("BindableEvent")

local ClassChangedClientEvent = {}

function ClassChangedClientEvent.fire(payload: { any })
	event:Fire(payload)
end

function ClassChangedClientEvent.connect(callback: (payload: { any }) -> ())
	return event.Event:Connect(callback)
end

return ClassChangedClientEvent
