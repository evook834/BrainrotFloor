--[[
	DifficultyConfig — single source of truth for difficulty names, gameplay tuning, and matchmaking.
	Used by GameConfig; matchmaking (DIFFICULTIES, MAX_PLAYERS_PER_DIFFICULTY) and match server (DifficultyService) derive from this.

	Per-difficulty Settings keys (extend as needed):
	- Gameplay: EnemyHealthMultiplier, EnemyDamageMultiplier, EnemyCountMultiplier, DiffTotal, DiffAlive,
	  DiffExtraSpecialCap, DiffExtraHeavyCap (director role-cap bonus).
	- Matchmaking: MaxPlayers (server slot cap; optional, falls back to DefaultMaxPlayers).
]]

local DifficultyConfig = {
	Default = "Normal",
	DefaultMaxPlayers = 6,
	-- Display/matchmaking order. Must match keys in Settings.
	OrderedNames = { "Easy", "Normal", "Hard" },
	Settings = {
		Easy = {
			EnemyHealthMultiplier = 0.8,
			EnemyDamageMultiplier = 0.9,
			EnemyCountMultiplier = 0.9,
			DiffTotal = 0.85,
			DiffAlive = 0.90,
			MaxPlayers = 6,
		},
		Normal = {
			EnemyHealthMultiplier = 1.0,
			EnemyDamageMultiplier = 1.0,
			EnemyCountMultiplier = 1.0,
			DiffTotal = 1.0,
			DiffAlive = 1.0,
			MaxPlayers = 6,
		},
		Hard = {
			EnemyHealthMultiplier = 1.35,
			EnemyDamageMultiplier = 1.2,
			EnemyCountMultiplier = 1.15,
			DiffTotal = 1.25,
			DiffAlive = 1.15,
			DiffExtraSpecialCap = 1,
			DiffExtraHeavyCap = 1,
			MaxPlayers = 6,
		},
		-- Nightmare (future): add to OrderedNames and Settings with DiffTotal/DiffAlive, caps, MaxPlayers.
	},
}

return DifficultyConfig
