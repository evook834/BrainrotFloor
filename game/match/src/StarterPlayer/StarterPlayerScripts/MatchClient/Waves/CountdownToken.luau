--[[
	CountdownToken — Cancellable countdown token so multiple loops (e.g. intermission, respawn, map vote)
	can run without overwriting each other. Call begin() to invalidate previous tokens; isActive(token)
	returns whether the given token is still the current one.
]]

export type CountdownToken = {
	begin: () -> number,
	isActive: (value: number) -> boolean,
}

function create(): CountdownToken
	local token = 0
	return {
		begin = function(): number
			token += 1
			return token
		end,
		isActive = function(value: number): boolean
			return value == token
		end,
	}
end

return {
	create = create,
}
