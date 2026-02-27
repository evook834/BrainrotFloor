local InventoryIndex = {}

local function normalizeWeaponId(weaponId)
	local normalizedWeaponId = tostring(weaponId or "")
	if normalizedWeaponId == "" then
		return nil
	end

	return normalizedWeaponId
end

local function shouldIncludeContainer(container, seen)
	if not container then
		return false
	end
	if seen[container] then
		return false
	end
	if typeof(container) ~= "Instance" then
		return false
	end

	seen[container] = true
	return true
end

local function collectContainers(player, options)
	local containers = {}
	local seen = {}

	if not (player and player:IsA("Player")) then
		return containers
	end

	local includeCharacter = options == nil or options.includeCharacter ~= false
	local includeBackpack = options == nil or options.includeBackpack ~= false
	local includeStarterGear = options == nil or options.includeStarterGear ~= false

	if includeCharacter and shouldIncludeContainer(player.Character, seen) then
		table.insert(containers, player.Character)
	end

	if includeBackpack then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if shouldIncludeContainer(backpack, seen) then
			table.insert(containers, backpack)
		end
	end

	if includeStarterGear then
		local starterGear = player:FindFirstChild("StarterGear")
		if shouldIncludeContainer(starterGear, seen) then
			table.insert(containers, starterGear)
		end
	end

	return containers
end

function InventoryIndex.getContainers(player, options)
	return collectContainers(player, options)
end

function InventoryIndex.getAllTools(player, options)
	local tools = {}
	local seenTools = {}

	for _, container in ipairs(collectContainers(player, options)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and not seenTools[child] then
				seenTools[child] = true
				table.insert(tools, child)
			end
		end
	end

	return tools
end

function InventoryIndex.getWeaponToolsById(player, weaponId, options)
	local normalizedWeaponId = normalizeWeaponId(weaponId)
	if not normalizedWeaponId then
		return {}
	end

	local matchingTools = {}
	for _, tool in ipairs(InventoryIndex.getAllTools(player, options)) do
		if tool:GetAttribute("WeaponId") == normalizedWeaponId then
			table.insert(matchingTools, tool)
		end
	end

	return matchingTools
end

function InventoryIndex.collectFirstWeaponToolById(player, options)
	local toolsByWeaponId = {}

	for _, tool in ipairs(InventoryIndex.getAllTools(player, options)) do
		local weaponId = tool:GetAttribute("WeaponId")
		if type(weaponId) == "string" and weaponId ~= "" and not toolsByWeaponId[weaponId] then
			toolsByWeaponId[weaponId] = tool
		end
	end

	return toolsByWeaponId
end

function InventoryIndex.hasWeaponTool(player, weaponId, options)
	local normalizedWeaponId = normalizeWeaponId(weaponId)
	if not normalizedWeaponId then
		return false
	end

	for _, tool in ipairs(InventoryIndex.getAllTools(player, options)) do
		if tool:GetAttribute("WeaponId") == normalizedWeaponId then
			return true
		end
	end

	return false
end

function InventoryIndex.destroyWeaponToolsById(player, weaponId, options)
	local normalizedWeaponId = normalizeWeaponId(weaponId)
	if not normalizedWeaponId then
		return false
	end

	local destroyedAny = false
	for _, tool in ipairs(InventoryIndex.getWeaponToolsById(player, normalizedWeaponId, options)) do
		destroyedAny = true
		tool:Destroy()
	end

	return destroyedAny
end

return InventoryIndex
