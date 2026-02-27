local ServerScriptService = game:GetService("ServerScriptService")

local ClassPayloadBuilder = require(ServerScriptService.Shared.Classes.ClassPayloadBuilder)

local ClassStateSync = {}
local PUSH_THROTTLE_SECONDS = 0.2

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

	local payloadDependencies = {
		getOrCreateClassProgress = getOrCreateClassProgress,
		getBonusesAtLevel = getBonusesAtLevel,
		getXpRequiredForNextLevel = getXpRequiredForNextLevel,
		buildPerLevelBonusesFromConfig = buildPerLevelBonusesFromConfig,
		buildCurrentBonusesWithFallback = buildCurrentBonusesWithFallback,
	}

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
		return ClassPayloadBuilder.buildPayload({
			state = state,
			classDef = classDef,
			classOrder = getClassOrder(),
			canSwitch = canSwitch,
			waveState = waveState,
			maxLevel = getMaxLevel(),
			dependencies = payloadDependencies,
		})
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
		pushThrottleByPlayer[player] = now + PUSH_THROTTLE_SECONDS

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
