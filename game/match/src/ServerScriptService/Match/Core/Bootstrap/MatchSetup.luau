--[[
	One-time match environment setup: Workspace attributes (e.g. Difficulty), etc.
	Extend this module when adding more "match ready" setup steps so GameBootstrap stays thin.
]]

local MatchSetup = {}

--- Ensures Workspace has a valid Difficulty attribute; sets from getDifficulty() if missing.
function MatchSetup.ensureDifficultyAttribute(workspace, getDifficulty)
	local current = workspace:GetAttribute("Difficulty")
	if type(current) == "string" and current ~= "" then
		return
	end
	workspace:SetAttribute("Difficulty", getDifficulty())
end

return MatchSetup
