--[[
	MapVotePayloadUtil — Normalizes raw map-vote payloads from the server into a typed shape.
	Used by WaveHudController; no UI or remotes.
]]

export type MapVoteOption = {
	placeId: number,
	label: string,
	votes: number,
}

local function normalizePlaceId(value: any): number?
	local placeId = tonumber(value)
	if placeId == nil then return nil end
	if placeId ~= math.floor(placeId) then return nil end
	if placeId <= 0 then return nil end
	return placeId
end

function normalizeMapVoteOptions(rawOptions: any): { MapVoteOption }
	local normalized: { MapVoteOption } = {}
	if type(rawOptions) ~= "table" then return normalized end
	for _, rawOption in ipairs(rawOptions) do
		if type(rawOption) == "table" then
			local placeId = normalizePlaceId(rawOption.placeId)
			if placeId ~= nil then
				local label = rawOption.label
				if type(label) ~= "string" or label == "" then
					label = ("Map %d"):format(#normalized + 1)
				end
				local votes = math.max(0, math.floor(tonumber(rawOption.votes) or 0))
				table.insert(normalized, { placeId = placeId, label = label, votes = votes })
			end
		end
	end
	return normalized
end

function formatMapVoteTimerText(endsAt: number?, getServerTime: () -> number): string
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return "Vote ends soon"
	end
	local remaining = math.max(0, math.ceil(endsAt - getServerTime()))
	return string.format("Vote ends in %02ds", remaining)
end

return {
	normalizeMapVoteOptions = normalizeMapVoteOptions,
	formatMapVoteTimerText = formatMapVoteTimerText,
}
