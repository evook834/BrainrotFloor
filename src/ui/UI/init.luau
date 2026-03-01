-- ui/UI exports
return {
	Shop = require(script.Shop),
	-- Classes, Combat, Waves, Spectator are temporarily empty until React Luau components are added
	-- These are currently handled by PlayerScriptService.Features.*
	Classes = require(script.Classes) or {},
	Combat = require(script.Combat) or {},
	Waves = require(script.Waves) or {},
	Spectator = require(script.Spectator) or {},
	Common = require(script.Common) or {},
	types = require(script.uitypes),
}
