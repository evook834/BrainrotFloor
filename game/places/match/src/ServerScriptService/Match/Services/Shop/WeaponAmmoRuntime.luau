local WeaponAmmoRuntime = {}

function WeaponAmmoRuntime.new(options)
	local classService = options and options.classService
	local inventoryIndex = options and options.inventoryIndex
	if type(classService) ~= "table" then
		error("WeaponAmmoRuntime.new requires options.classService", 2)
	end
	if type(inventoryIndex) ~= "table" then
		error("WeaponAmmoRuntime.new requires options.inventoryIndex", 2)
	end

	local toolRuntimeState = options and options.toolRuntimeState
	if type(toolRuntimeState) ~= "table" then
		toolRuntimeState = setmetatable({}, { __mode = "k" })
	end

	local updateAmmoAttributes

	local function getMagazineSize(weaponDef, player)
		local magazineSize = nil
		if player and player:IsA("Player") then
			magazineSize = classService.getWeaponMagazineSize(player, weaponDef)
		else
			magazineSize = tonumber(weaponDef and weaponDef.MagazineSize)
		end

		if not magazineSize then
			return nil
		end

		magazineSize = math.floor(magazineSize + 0.5)
		if magazineSize <= 0 then
			return nil
		end

		return magazineSize
	end

	local function getReloadSeconds(weaponDef, player)
		local reloadSeconds = nil
		if player and player:IsA("Player") then
			reloadSeconds = classService.getWeaponReloadSeconds(player, weaponDef)
		else
			reloadSeconds = tonumber(weaponDef and weaponDef.ReloadSeconds)
		end

		if type(reloadSeconds) ~= "number" then
			return nil
		end

		return math.max(0.2, reloadSeconds)
	end

	local function getReserveAmmoCapacity(weaponDef, magazineSize)
		if type(magazineSize) ~= "number" or magazineSize <= 0 then
			return nil
		end

		local explicitReserve = tonumber(weaponDef and weaponDef.ReserveAmmo)
		if type(explicitReserve) == "number" then
			return math.max(0, math.floor(explicitReserve + 0.5))
		end

		local spareMagazines = tonumber(weaponDef and weaponDef.SpareMagazines)
		if type(spareMagazines) == "number" then
			return math.max(0, math.floor(spareMagazines + 0.5)) * magazineSize
		end

		return magazineSize * 4
	end

	local function syncToolCombatStats(tool, weaponDef, state, owner)
		local magazineSize = getMagazineSize(weaponDef, owner)
		local reloadSeconds = getReloadSeconds(weaponDef, owner)
		local reserveAmmoCapacity = getReserveAmmoCapacity(weaponDef, magazineSize)

		state.magazineSize = magazineSize
		state.reloadSeconds = reloadSeconds
		state.reserveAmmoCapacity = reserveAmmoCapacity

		tool:SetAttribute("MagazineSize", magazineSize)
		tool:SetAttribute("ReloadSeconds", reloadSeconds)
	end

	local function getToolState(tool, weaponDef, owner)
		local state = toolRuntimeState[tool]
		if state then
			return state
		end

		local magazineSize = getMagazineSize(weaponDef, owner)
		local reserveAmmoCapacity = getReserveAmmoCapacity(weaponDef, magazineSize)
		state = {
			lastActivatedAt = -math.huge,
			ammo = magazineSize,
			reserveAmmo = reserveAmmoCapacity,
			isReloading = false,
			isBursting = false,
			baseGrip = tool.Grip,
			swingToken = 0,
			magazineSize = magazineSize,
			reserveAmmoCapacity = reserveAmmoCapacity,
			reloadSeconds = getReloadSeconds(weaponDef, owner),
		}
		toolRuntimeState[tool] = state
		return state
	end

	local function mirrorAmmoStateAcrossOwnedTools(sourceTool, weaponDef, sourceState, owner)
		if not (owner and owner:IsA("Player")) then
			return
		end
		if not (sourceTool and sourceTool:IsA("Tool")) then
			return
		end

		local weaponId = sourceTool:GetAttribute("WeaponId")
		if type(weaponId) ~= "string" or weaponId == "" then
			return
		end

		for _, tool in ipairs(inventoryIndex.getWeaponToolsById(owner, weaponId)) do
			if tool ~= sourceTool then
				local mirroredState = getToolState(tool, weaponDef, owner)
				mirroredState.ammo = sourceState.ammo
				mirroredState.reserveAmmo = sourceState.reserveAmmo
				mirroredState.isReloading = false
				updateAmmoAttributes(tool, weaponDef, mirroredState, owner, true)
			end
		end
	end

	updateAmmoAttributes = function(tool, weaponDef, state, owner, skipMirror)
		syncToolCombatStats(tool, weaponDef, state, owner)
		local magazineSize = state.magazineSize
		if not magazineSize then
			tool:SetAttribute("MaxAmmo", nil)
			tool:SetAttribute("CurrentAmmo", nil)
			tool:SetAttribute("ReserveAmmo", nil)
			tool:SetAttribute("ReserveAmmoMax", nil)
			tool:SetAttribute("TotalAmmo", nil)
			tool:SetAttribute("TotalAmmoMax", nil)
			tool:SetAttribute("IsReloading", false)
			tool.ToolTip = tostring((weaponDef and weaponDef.DisplayName) or tool.Name)
			return
		end

		state.ammo = math.max(0, math.floor((tonumber(state.ammo) or magazineSize) + 0.5))
		state.ammo = math.min(state.ammo, magazineSize)
		state.reserveAmmoCapacity = math.max(0, math.floor((tonumber(state.reserveAmmoCapacity) or 0) + 0.5))
		state.reserveAmmo = math.max(0, math.floor((tonumber(state.reserveAmmo) or state.reserveAmmoCapacity) + 0.5))
		if state.reserveAmmo > state.reserveAmmoCapacity then
			state.reserveAmmo = state.reserveAmmoCapacity
		end

		local totalAmmo = state.ammo + state.reserveAmmo
		local totalAmmoCapacity = magazineSize + state.reserveAmmoCapacity
		tool:SetAttribute("MaxAmmo", magazineSize)
		tool:SetAttribute("CurrentAmmo", state.ammo)
		tool:SetAttribute("ReserveAmmo", state.reserveAmmo)
		tool:SetAttribute("ReserveAmmoMax", state.reserveAmmoCapacity)
		tool:SetAttribute("TotalAmmo", totalAmmo)
		tool:SetAttribute("TotalAmmoMax", totalAmmoCapacity)
		tool:SetAttribute("IsReloading", state.isReloading == true)

		if state.isReloading then
			tool.ToolTip = string.format("%s | Reloading...", tostring((weaponDef and weaponDef.DisplayName) or tool.Name))
		elseif totalAmmo <= 0 then
			tool.ToolTip = string.format("%s | Out of ammo", tostring((weaponDef and weaponDef.DisplayName) or tool.Name))
		else
			tool.ToolTip = string.format(
				"%s | Ammo %d/%d | Reserve %d",
				tostring((weaponDef and weaponDef.DisplayName) or tool.Name),
				state.ammo,
				magazineSize,
				state.reserveAmmo
			)
		end

		if skipMirror ~= true then
			mirrorAmmoStateAcrossOwnedTools(tool, weaponDef, state, owner)
		end
	end

	local function startReload(tool, weaponDef, state, owner)
		syncToolCombatStats(tool, weaponDef, state, owner)
		local magazineSize = state.magazineSize
		if not magazineSize or state.isReloading then
			return
		end

		state.ammo = math.max(0, math.floor((tonumber(state.ammo) or magazineSize) + 0.5))
		state.ammo = math.min(state.ammo, magazineSize)
		state.reserveAmmo = math.max(0, math.floor((tonumber(state.reserveAmmo) or 0) + 0.5))
		if state.ammo >= magazineSize or state.reserveAmmo <= 0 then
			updateAmmoAttributes(tool, weaponDef, state, owner)
			return
		end

		state.isReloading = true
		updateAmmoAttributes(tool, weaponDef, state, owner)

		local reloadSeconds = math.max(0.2, tonumber(state.reloadSeconds) or 2)
		task.delay(reloadSeconds, function()
			state.isReloading = false
			syncToolCombatStats(tool, weaponDef, state, owner)
			local refreshedMagazineSize = state.magazineSize
			if refreshedMagazineSize then
				local currentAmmo = math.max(0, math.floor((tonumber(state.ammo) or 0) + 0.5))
				local reserveAmmo = math.max(0, math.floor((tonumber(state.reserveAmmo) or 0) + 0.5))
				local neededAmmo = math.max(0, refreshedMagazineSize - currentAmmo)
				local loadedAmmo = math.min(neededAmmo, reserveAmmo)
				state.ammo = currentAmmo + loadedAmmo
				state.reserveAmmo = reserveAmmo - loadedAmmo
			end
			if tool.Parent then
				updateAmmoAttributes(tool, weaponDef, state, owner)
			end
		end)
	end

	local function tryConsumeAmmo(tool, weaponDef, state, owner)
		syncToolCombatStats(tool, weaponDef, state, owner)
		local magazineSize = state.magazineSize
		if not magazineSize then
			return true
		end

		if state.isReloading then
			return false
		end

		state.ammo = math.max(0, math.floor((tonumber(state.ammo) or magazineSize) + 0.5))
		state.ammo = math.min(state.ammo, magazineSize)
		state.reserveAmmo = math.max(0, math.floor((tonumber(state.reserveAmmo) or 0) + 0.5))

		if state.ammo <= 0 then
			if state.reserveAmmo > 0 then
				startReload(tool, weaponDef, state, owner)
			else
				updateAmmoAttributes(tool, weaponDef, state, owner)
			end
			return false
		end

		state.ammo -= 1
		updateAmmoAttributes(tool, weaponDef, state, owner)

		if state.ammo <= 0 and state.reserveAmmo > 0 then
			startReload(tool, weaponDef, state, owner)
		end

		return true
	end

	local function normalizeAmmoRefillMode(value)
		if type(value) ~= "string" then
			return "ReserveOnly"
		end

		local normalized = string.lower(value)
		if normalized == "full" then
			return "Full"
		end
		if normalized == "magazineonly" then
			return "MagazineOnly"
		end
		return "ReserveOnly"
	end

	local function refillAmmoForTool(tool, weaponDef, owner, refillMode, reserveAmount)
		local state = getToolState(tool, weaponDef, owner)
		syncToolCombatStats(tool, weaponDef, state, owner)

		local magazineSize = state.magazineSize
		if type(magazineSize) ~= "number" or magazineSize <= 0 then
			return false
		end

		local reserveAmmoCapacity = math.max(0, math.floor((tonumber(state.reserveAmmoCapacity) or 0) + 0.5))
		local ammoBefore = math.max(0, math.floor((tonumber(state.ammo) or 0) + 0.5))
		local reserveBefore = math.max(0, math.floor((tonumber(state.reserveAmmo) or 0) + 0.5))

		state.ammo = math.clamp(ammoBefore, 0, magazineSize)
		state.reserveAmmo = math.clamp(reserveBefore, 0, reserveAmmoCapacity)

		if refillMode == "Full" then
			state.ammo = magazineSize
			state.reserveAmmo = reserveAmmoCapacity
			state.isReloading = false
		elseif refillMode == "MagazineOnly" then
			state.ammo = magazineSize
			state.isReloading = false
		else
			local roundedReserveAmount = tonumber(reserveAmount)
			if type(roundedReserveAmount) == "number" and roundedReserveAmount > 0 then
				local ammoToAdd = math.max(0, math.floor(roundedReserveAmount + 0.5))
				state.reserveAmmo = math.min(reserveAmmoCapacity, state.reserveAmmo + ammoToAdd)
			else
				state.reserveAmmo = reserveAmmoCapacity
			end
		end

		updateAmmoAttributes(tool, weaponDef, state, owner)
		return state.ammo > ammoBefore or state.reserveAmmo > reserveBefore
	end

	local function getToolAmmoSnapshot(tool, weaponDef, owner)
		if not (tool and tool:IsA("Tool")) then
			return nil
		end

		local magazineSize = getMagazineSize(weaponDef, owner)
		if type(magazineSize) ~= "number" or magazineSize <= 0 then
			return nil
		end

		local reserveAmmoCapacity = getReserveAmmoCapacity(weaponDef, magazineSize)
		if type(reserveAmmoCapacity) ~= "number" or reserveAmmoCapacity < 0 then
			reserveAmmoCapacity = 0
		end

		local state = toolRuntimeState[tool]
		local currentAmmo = if state then state.ammo else tool:GetAttribute("CurrentAmmo")
		local reserveAmmo = if state then state.reserveAmmo else tool:GetAttribute("ReserveAmmo")

		currentAmmo = math.clamp(math.floor((tonumber(currentAmmo) or magazineSize) + 0.5), 0, magazineSize)
		reserveAmmo = math.clamp(math.floor((tonumber(reserveAmmo) or reserveAmmoCapacity) + 0.5), 0, reserveAmmoCapacity)

		local currentTotalAmmo = currentAmmo + reserveAmmo
		local maxTotalAmmo = magazineSize + reserveAmmoCapacity
		local missingAmmo = math.max(0, maxTotalAmmo - currentTotalAmmo)

		return {
			currentAmmo = currentAmmo,
			reserveAmmo = reserveAmmo,
			magazineSize = magazineSize,
			reserveAmmoCapacity = reserveAmmoCapacity,
			currentTotalAmmo = currentTotalAmmo,
			maxTotalAmmo = maxTotalAmmo,
			missingAmmo = missingAmmo,
		}
	end

	return {
		getStateMap = function()
			return toolRuntimeState
		end,
		clearToolState = function(tool)
			toolRuntimeState[tool] = nil
		end,
		getMagazineSize = getMagazineSize,
		getReloadSeconds = getReloadSeconds,
		getReserveAmmoCapacity = getReserveAmmoCapacity,
		syncToolCombatStats = syncToolCombatStats,
		getToolState = getToolState,
		updateAmmoAttributes = updateAmmoAttributes,
		startReload = startReload,
		tryConsumeAmmo = tryConsumeAmmo,
		normalizeAmmoRefillMode = normalizeAmmoRefillMode,
		refillAmmoForTool = refillAmmoForTool,
		getToolAmmoSnapshot = getToolAmmoSnapshot,
	}
end

return WeaponAmmoRuntime
