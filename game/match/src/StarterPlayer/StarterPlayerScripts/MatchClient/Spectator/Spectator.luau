-- Match spectator launcher - runs the spectator system for dead players
--
-- Usage:
--   Call Spectator.run(options) from match-specific client scripts
--   Options:
--     - isLobby: true if running in lobby context (default: false)

local SpectatorController = require(script.SpectatorController)

local Spectator = {}

function Spectator.run(options)
	SpectatorController.run(options)
end

function Spectator.stop()
	SpectatorController.stop()
end

return Spectator
