--[[
	WaveHudMessages — Copy for game-over and win states.
	Single source for HUD strings so behaviour and localization can be extended in one place.
]]

function getGameOverMessage(reason: string?): string
	if reason == "AllPlayersDead" then
		return "All players were eliminated at the same time. Respawning is disabled."
	end
	return "The match has ended."
end

function getWinMessage(reason: string?): string
	if reason == "BossDefeated" then
		return "Boss defeated. Choose the next map."
	end
	return "You won!"
end

return {
	getGameOverMessage = getGameOverMessage,
	getWinMessage = getWinMessage,
}
