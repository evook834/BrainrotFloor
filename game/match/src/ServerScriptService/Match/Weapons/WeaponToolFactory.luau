--[[
	WeaponToolFactory — Creates/configures weapon tools and binds tool events.
	Tool setup: createWeaponTool, configureWeaponTool.
	Player tool lookup: getEquippedWeaponTool, consumeOwnedWeaponInstances.
	Tool event wiring (Activated/Equipped/Unequipped/Destroying) and internal fireWeapon routing.
]]

local Players = game:GetService("Players")

local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local WeaponToolSetup = require(script.Parent.WeaponToolSetup)
local Match = script.Parent.Parent
local AimResolver = require(Match.Combat.AimResolver)

local ammoRuntime = nil
local sentryTurretController = nil
local inventoryIndex = nil
local weaponFireRemote = nil
local fireMeleeAttack = nil
local fireBulletShot = nil
local fireRocket = nil
local fireGrenadeLauncher = nil
local fireFlamethrower = nil

local resolveWeaponClass = WeaponToolSetup.resolveWeaponClass
local normalizeWeaponToken = WeaponToolSetup.normalizeWeaponToken
local isMeleeWeaponClass = WeaponToolSetup.isMeleeWeaponClass
local createToolFromTemplate = WeaponToolSetup.createToolFromTemplate
local createFallbackWeaponTool = WeaponToolSetup.createFallbackWeaponTool
local prepareToolParts = WeaponToolSetup.prepareToolParts
local isDualWieldWeapon = WeaponToolSetup.isDualWieldWeapon
local createDualWieldOffhandVisual = WeaponToolSetup.createDualWieldOffhandVisual
local clearDualWieldOffhand = WeaponToolSetup.clearDualWieldOffhand

function init(options)
	if type(options) ~= "table" then
		return
	end
	ammoRuntime = options.ammoRuntime
	sentryTurretController = options.sentryTurretController
	inventoryIndex = options.inventoryIndex
	weaponFireRemote = options.weaponFireRemote
	fireMeleeAttack = options.fireMeleeAttack
	fireBulletShot = options.fireBulletShot
	fireRocket = options.fireRocket
	fireGrenadeLauncher = options.fireGrenadeLauncher
	fireFlamethrower = options.fireFlamethrower
end

local function getMagazineSize(weaponDef, owner)
	if ammoRuntime then
		return ammoRuntime.getMagazineSize(weaponDef, owner)
	end
	return nil
end

local function getReloadSeconds(weaponDef, owner)
	if ammoRuntime then
		return ammoRuntime.getReloadSeconds(weaponDef, owner)
	end
	return nil
end

local function getToolState(tool, weaponDef, owner)
	if ammoRuntime then
		return ammoRuntime.getToolState(tool, weaponDef, owner)
	end
	return nil
end

local function updateAmmoAttributes(tool, weaponDef, state, owner, skipMirror)
	if ammoRuntime then
		ammoRuntime.updateAmmoAttributes(tool, weaponDef, state, owner, skipMirror)
	end
end

local function tryConsumeAmmo(tool, weaponDef, state, owner)
	if ammoRuntime then
		return ammoRuntime.tryConsumeAmmo(tool, weaponDef, state, owner)
	end
	return false
end

local function startReload(tool, weaponDef, state, owner)
	if ammoRuntime then
		ammoRuntime.startReload(tool, weaponDef, state, owner)
	end
end

local function getWeaponOriginAndDirection(player, character, rootPart, handle)
	local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
	if handle and handle:IsA("BasePart") then
		origin = handle.Position
	end

	local direction = AimResolver.getPlayerAimDirection(player, character, rootPart, origin)
	if direction.Magnitude <= 0.001 then
		direction = rootPart.CFrame.LookVector
	end
	direction = direction.Unit

	if handle and handle:IsA("BasePart") then
		origin += direction * math.max(0.8, handle.Size.Z * 0.45)
		direction = AimResolver.getPlayerAimDirection(player, character, rootPart, origin)
		if direction.Magnitude <= 0.001 then
			direction = rootPart.CFrame.LookVector
		end
		direction = direction.Unit
	end

	return origin, direction
end

local function consumeOwnedWeaponInstances(player, weaponId)
	if inventoryIndex then
		return inventoryIndex.destroyWeaponToolsById(player, weaponId)
	end
end

local function configureWeaponTool(tool, weaponDef, owner)
	local weaponClass = resolveWeaponClass(weaponDef)
	local dualWieldEnabled = isDualWieldWeapon(weaponDef)

	tool.Name = weaponDef.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponDef.Id)
	tool:SetAttribute("WeaponClass", weaponClass)
	tool:SetAttribute("ClassTag", weaponDef.ClassTag)
	tool:SetAttribute("RequiredClassId", weaponDef.ClassId)
	tool:SetAttribute("DualWield", dualWieldEnabled)
	tool:SetAttribute("AutoFire", weaponDef.AutoFire == true or isMeleeWeaponClass(weaponClass))
	tool:SetAttribute("Damage", weaponDef.Damage)
	tool:SetAttribute("Range", weaponDef.Range)
	tool:SetAttribute("Cooldown", weaponDef.Cooldown)
	tool:SetAttribute("TurretPlacementDistance", weaponDef.TurretPlacementDistance)
	tool:SetAttribute("TurretPlacementRotationDeg", weaponDef.TurretPlacementRotationDeg)
	tool:SetAttribute("MagazineSize", getMagazineSize(weaponDef, owner))
	tool:SetAttribute("ReloadSeconds", getReloadSeconds(weaponDef, owner))

	local handle = tool:FindFirstChild("Handle", true)
	tool.RequiresHandle = handle ~= nil
	if handle and handle:IsA("BasePart") then
		handle.CanCollide = false
		prepareToolParts(tool, handle)
	end

	local grip = CFrame.new(-0.3, -0.8, 0)
	if typeof(weaponDef.GripPositionOffset) == "Vector3" then
		grip *= CFrame.new(weaponDef.GripPositionOffset)
	end
	if typeof(weaponDef.GripRotationDeg) == "Vector3" then
		grip *= CFrame.Angles(
			math.rad(weaponDef.GripRotationDeg.X),
			math.rad(weaponDef.GripRotationDeg.Y),
			math.rad(weaponDef.GripRotationDeg.Z)
		)
	end
	tool.Grip = grip

	local state = getToolState(tool, weaponDef, owner)
	state.baseGrip = tool.Grip
	state.dualWieldEnabled = dualWieldEnabled
	state.nextDualWieldShotLeft = false
	updateAmmoAttributes(tool, weaponDef, state, owner)

	local function fireWeapon(owner, character, humanoid, rootPart, explicitShotOrigin, explicitShotDirection)
		if not ClassService.canPlayerUseWeapon(owner, weaponDef) then
			ClassService.enforcePlayerLoadout(owner)
			return
		end

		local now = os.clock()
		local cooldown = math.max(0.05, tonumber(weaponDef.Cooldown) or 0.25)
		if now - (state.lastActivatedAt or -math.huge) < cooldown then
			return
		end

		if state.isReloading then
			return
		end

		if weaponClass == "Flamethrower" and state.isBursting then
			return
		end

		if weaponClass ~= "SentryDeployer" and weaponClass ~= "RepairTool" and not AimResolver.canPlayerFireTowardRequestedDirection(owner, rootPart, explicitShotDirection) then
			return
		end

		if not tryConsumeAmmo(tool, weaponDef, state, owner) then
			return
		end

		state.lastActivatedAt = now

		if dualWieldEnabled then
			local hasOffhandVisual = state.offhandRoot and state.offhandRoot.Parent ~= nil
			if not hasOffhandVisual then
				createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
			end
		end

		local origin, direction = getWeaponOriginAndDirection(owner, character, rootPart, handle)
		local shotOrigin, shotDirection = nil, nil
		if typeof(explicitShotOrigin) == "Vector3" and typeof(explicitShotDirection) == "Vector3" and explicitShotDirection.Magnitude > 0.001 then
			shotOrigin = explicitShotOrigin
			shotDirection = AimResolver.clampDirectionToForwardFireArc(rootPart, explicitShotDirection, direction)
		else
			shotOrigin, shotDirection = AimResolver.getPlayerShotRay(owner, rootPart, origin, direction)
		end

		if weaponClass == "SentryDeployer" then
			local didDeploy = sentryTurretController and sentryTurretController.deploySentryTurret(owner, character, rootPart, weaponDef, shotOrigin, shotDirection)
			if didDeploy then
				consumeOwnedWeaponInstances(owner, weaponDef.Id)
			end
		elseif weaponClass == "RepairTool" then
			if sentryTurretController then
				sentryTurretController.repairOwnedSentries(owner, weaponDef)
			end
		elseif isMeleeWeaponClass(weaponClass) then
			if fireMeleeAttack then
				fireMeleeAttack(owner, character, origin, direction, weaponDef, state, tool)
			end
		elseif weaponClass == "Flamethrower" then
			if fireFlamethrower then
				fireFlamethrower(owner, character, weaponDef, state, handle)
			end
		elseif weaponClass == "RPG" then
			if fireRocket then
				fireRocket(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
			end
		elseif weaponClass == "GrenadeLauncher" then
			if fireGrenadeLauncher then
				fireGrenadeLauncher(owner, character, origin, direction, weaponDef, shotOrigin, shotDirection)
			end
		else
			local muzzleOrigin = origin
			if dualWieldEnabled and state.nextDualWieldShotLeft and state.offhandRoot and state.offhandRoot.Parent then
				local offhandRoot = state.offhandRoot
				muzzleOrigin = offhandRoot.Position + (direction * math.max(0.8, offhandRoot.Size.Z * 0.45))
			end

			if fireBulletShot then
				fireBulletShot(owner, character, muzzleOrigin, direction, weaponDef, shotOrigin, shotDirection)
			end

			if dualWieldEnabled then
				state.nextDualWieldShotLeft = not state.nextDualWieldShotLeft
			end
		end
	end

	state.fireHandler = function(owner, explicitShotOrigin, explicitShotDirection)
		if not owner or not owner:IsA("Player") then
			return
		end

		local character = owner.Character
		if not character or tool.Parent ~= character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			return
		end

		fireWeapon(owner, character, humanoid, rootPart, explicitShotOrigin, explicitShotDirection)
	end

	state.reloadHandler = function(owner)
		if not owner or not owner:IsA("Player") then
			return
		end

		if not ClassService.canPlayerUseWeapon(owner, weaponDef) then
			ClassService.enforcePlayerLoadout(owner)
			return
		end

		local character = owner.Character
		if not character or tool.Parent ~= character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		startReload(tool, weaponDef, state, owner)
	end

	tool.Activated:Connect(function()
		if weaponFireRemote then
			return
		end

		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end

		local owner = Players:GetPlayerFromCharacter(character)
		if not owner then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			return
		end

		fireWeapon(owner, character, humanoid, rootPart, nil, nil)
	end)

	tool.Equipped:Connect(function()
		if not dualWieldEnabled then
			return
		end

		local character = tool.Parent
		if character and character:IsA("Model") then
			createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
		end
	end)

	tool.Unequipped:Connect(function()
		if dualWieldEnabled then
			clearDualWieldOffhand(state)
			state.nextDualWieldShotLeft = false
		end
	end)

	tool.Destroying:Connect(function()
		if state then
			clearDualWieldOffhand(state)
			state.fireHandler = nil
			state.reloadHandler = nil
		end
		if ammoRuntime then
			ammoRuntime.clearToolState(tool)
		end
	end)
end

local function createWeaponTool(weaponDef, owner)
	local tool = createToolFromTemplate(weaponDef)
	if not tool then
		tool = createFallbackWeaponTool(weaponDef)
	end

	configureWeaponTool(tool, weaponDef, owner)
	return tool
end

local function getEquippedWeaponTool(player, weaponId)
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
			return child
		end
	end

	return nil
end

return {
	init = init,
	createWeaponTool = createWeaponTool,
	configureWeaponTool = configureWeaponTool,
	getEquippedWeaponTool = getEquippedWeaponTool,
	consumeOwnedWeaponInstances = consumeOwnedWeaponInstances,
	getWeaponOriginAndDirection = getWeaponOriginAndDirection,
}
