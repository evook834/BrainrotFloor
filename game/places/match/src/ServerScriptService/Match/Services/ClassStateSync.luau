local ClassStateSync = {}

function ClassStateSync.new(config)
	local syncConfig = config or {}
	local playersService = syncConfig.playersService
	local getClassStateRemote = syncConfig.getClassStateRemote
	local getOrCreatePlayerState = syncConfig.getOrCreatePlayerState
	local getPlayerClassDefinition = syncConfig.getPlayerClassDefinition
	local canSwitchClassNow = syncConfig.canSwitchClassNow
	local getOrCreateClassProgress = syncConfig.getOrCreateClassProgress
	local getBonusesAtLevel = syncConfig.getBonusesAtLevel
	local getXpRequiredForNextLevel = syncConfig.getXpRequiredForNextLevel
	local buildPerLevelBonusesFromConfig = syncConfig.buildPerLevelBonusesFromConfig
	local buildCurrentBonusesWithFallback = syncConfig.buildCurrentBonusesWithFallback
	local getClassOrder = syncConfig.getClassOrder
	local getMaxLevel = syncConfig.getMaxLevel

	local pushThrottleByPlayer = {}
	local api = {}

	function api.buildPayloadForPlayer(player)
		local state = getOrCreatePlayerState(player)
		local classDef = getPlayerClassDefinition(player)
		if not classDef then
			return {
				success = false,
				message = "No classes configured.",
			}
		end

		local canSwitch, waveState = canSwitchClassNow()
		local currentProgress = getOrCreateClassProgress(state, classDef.Id)
		local selectedClassBonuses = getBonusesAtLevel(classDef, currentProgress.level)
		local selectedPerLevelBonuses = buildPerLevelBonusesFromConfig(classDef.Bonuses)
		local currentBonuses = buildCurrentBonusesWithFallback(
			selectedClassBonuses,
			selectedPerLevelBonuses,
			currentProgress.level
		)

		local classes = {}
		for _, listedClass in ipairs(getClassOrder()) do
			local progress = getOrCreateClassProgress(state, listedClass.Id)
			local level = math.clamp(math.floor(tonumber(progress.level) or 1), 1, getMaxLevel())
			local xp = math.max(0, tonumber(progress.xp) or 0)
			local xpToNext = getXpRequiredForNextLevel(listedClass, level)
			local classBonuses = getBonusesAtLevel(listedClass, level)
			local perLevelBonuses = buildPerLevelBonusesFromConfig(listedClass.Bonuses)
			local classCurrentBonuses = buildCurrentBonusesWithFallback(classBonuses, perLevelBonuses, level)

			table.insert(classes, {
				id = listedClass.Id,
				name = listedClass.DisplayName,
				description = listedClass.Description,
				weaponTag = listedClass.WeaponTag,
				level = level,
				xp = xp,
				xpToNext = xpToNext,
				isCurrent = listedClass.Id == state.selectedClassId,
				currentBonuses = classCurrentBonuses,
				perLevelBonuses = perLevelBonuses,
			})
		end

		return {
			success = true,
			canSwitch = canSwitch,
			waveState = waveState,
			maxLevel = getMaxLevel(),
			currentClassId = classDef.Id,
			currentClassName = classDef.DisplayName,
			currentBonuses = currentBonuses,
			classes = classes,
		}
	end

	function api.pushPlayerState(player, reason, force)
		local classStateRemote = getClassStateRemote()
		if not classStateRemote or player.Parent ~= playersService then
			return
		end

		local now = os.clock()
		if not force then
			local nextPushAt = pushThrottleByPlayer[player] or 0
			if now < nextPushAt then
				return
			end
		end
		pushThrottleByPlayer[player] = now + 0.2

		local payload = api.buildPayloadForPlayer(player)
		payload.reason = reason
		classStateRemote:FireClient(player, payload)
	end

	function api.clearPlayer(player)
		pushThrottleByPlayer[player] = nil
	end

	return api
end

return ClassStateSync
