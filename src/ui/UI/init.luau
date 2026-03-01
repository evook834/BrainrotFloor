-- ui/UI exports
local function requireChild(name: string)
	local child = script:FindFirstChild(name)
	if child and child:IsA("ModuleScript") then
		return require(child)
	end
	return nil
end

return {
	Shop = require(script.Shop),
	-- Classes, Combat, Waves, Spectator, Common are optional until components exist
	Classes = requireChild("Classes") or {},
	Combat = requireChild("Combat") or {},
	Waves = requireChild("Waves") or {},
	Spectator = requireChild("Spectator") or {},
	Common = requireChild("Common") or {},
	types = require(script.uitypes),
}
