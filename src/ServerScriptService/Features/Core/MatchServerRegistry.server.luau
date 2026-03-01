-- Entry script: starts the match server registry (MemoryStore heartbeat, difficulty from JoinData, unregister on close).
local MatchServerRegistry = require(script.Parent.Registry.MatchServerRegistry)
MatchServerRegistry.run()
