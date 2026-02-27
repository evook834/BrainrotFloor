--[[
	Binds weapon combat remotes (aim, fire, reload), initializes damage indicators,
	and wires player lifecycle for sentry cleanup and aim state.
	Called by ShopService.start() after remotes and WeaponToolFactory exist.
]]

local Players = game:GetService("Players")

local Match = script.Parent.Parent.Parent
local AimResolver = require(Match.Combat.AimResolver)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)

local WeaponRemoteBindings = {}
local started = false

local function start(context)
	if started then
		return
	end
	started = true

	local weaponAimRemote = context.weaponAimRemote
	local weaponFireRemote = context.weaponFireRemote
	local weaponReloadRemote = context.weaponReloadRemote
	local damageIndicatorRemote = context.damageIndicatorRemote
	local weaponById = context.weaponById
	local toolRuntimeState = context.toolRuntimeState
	local ammoRuntime = context.ammoRuntime
	local classService = context.classService
	local weaponToolFactory = context.weaponToolFactory
	local sentryRuntime = context.sentryRuntime

	local function canPlayerUseWeapon(player, weaponDef)
		return classService.canPlayerUseWeapon(player, weaponDef)
	end

	local function startReload(tool, weaponDef, state, owner)
		ammoRuntime.startReload(tool, weaponDef, state, owner)
	end

	if damageIndicatorRemote then
		EnemyDamageService.init({ damageIndicatorRemote = damageIndicatorRemote })
	end

	if weaponAimRemote then
		weaponAimRemote.OnServerEvent:Connect(function(player, hitPosition, lookDirection, cameraOrigin)
			AimResolver.updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
		end)
	end

	if weaponFireRemote then
		weaponFireRemote.OnServerEvent:Connect(function(player, weaponId, hitPosition, lookDirection, cameraOrigin)
			if typeof(hitPosition) == "Vector3" and typeof(lookDirection) == "Vector3" then
				AimResolver.updatePlayerAim(player, hitPosition, lookDirection, cameraOrigin)
			end

			local weaponDef = weaponById[weaponId]
			if not weaponDef then
				return
			end
			if not canPlayerUseWeapon(player, weaponDef) then
				classService.enforcePlayerLoadout(player)
				return
			end

			local tool = weaponToolFactory.getEquippedWeaponTool(player, weaponId)
			if not tool then
				return
			end

			local state = toolRuntimeState[tool]
			if not state or type(state.fireHandler) ~= "function" then
				return
			end

			local explicitShotOrigin = nil
			local explicitShotDirection = nil
			if typeof(cameraOrigin) == "Vector3" and typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
				explicitShotOrigin = cameraOrigin
				explicitShotDirection = lookDirection.Unit
			end

			state.fireHandler(player, explicitShotOrigin, explicitShotDirection)
		end)
	end

	if weaponReloadRemote then
		weaponReloadRemote.OnServerEvent:Connect(function(player, weaponId)
			if type(weaponId) ~= "string" or weaponId == "" then
				return
			end

			local weaponDef = weaponById[weaponId]
			if not weaponDef then
				return
			end
			if not canPlayerUseWeapon(player, weaponDef) then
				classService.enforcePlayerLoadout(player)
				return
			end

			local tool = weaponToolFactory.getEquippedWeaponTool(player, weaponId)
			if not tool then
				return
			end

			local state = toolRuntimeState[tool]
			if not state then
				return
			end

			if type(state.reloadHandler) == "function" then
				state.reloadHandler(player)
				return
			end

			startReload(tool, weaponDef, state, player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		sentryRuntime.bindPlayerSentryDeathCleanup(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		AimResolver.clearPlayerAim(player)
		sentryRuntime.clearPlayerSentries(player)
		sentryRuntime.disconnectPlayerSentryDeathBindings(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		sentryRuntime.bindPlayerSentryDeathCleanup(player)
	end
end

WeaponRemoteBindings.start = start

return WeaponRemoteBindings
