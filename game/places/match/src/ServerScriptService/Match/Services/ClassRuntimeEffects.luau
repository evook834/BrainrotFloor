local ClassRuntimeEffects = {}

function ClassRuntimeEffects.new(config)
	local runtimeConfig = config or {}
	local playersService = runtimeConfig.playersService
	local getPlayerSelectedClassBonuses = runtimeConfig.getPlayerSelectedClassBonuses
	local getPlayerClassDefinition = runtimeConfig.getPlayerClassDefinition
	local getWeaponById = runtimeConfig.getWeaponById
	local isWeaponAllowedForClass = runtimeConfig.isWeaponAllowedForClass
	local getWaveMoveSpeedMultiplier = runtimeConfig.getWaveMoveSpeedMultiplier

	local api = {}

	function api.applyHumanoidClassBonus(humanoid, maxHealthMultiplier)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end

		local baseMaxHealth = humanoid:GetAttribute("ClassBaseMaxHealth")
		if type(baseMaxHealth) ~= "number" or baseMaxHealth <= 0 then
			baseMaxHealth = humanoid.MaxHealth
			humanoid:SetAttribute("ClassBaseMaxHealth", baseMaxHealth)
		end

		local previousMaxHealth = humanoid.MaxHealth
		local previousHealth = humanoid.Health
		local desiredMaxHealth = math.max(1, math.floor((baseMaxHealth * maxHealthMultiplier) + 0.5))
		if math.abs(desiredMaxHealth - previousMaxHealth) < 0.01 then
			return
		end

		local healthRatio = 1
		if previousMaxHealth > 0 then
			healthRatio = math.clamp(previousHealth / previousMaxHealth, 0, 1)
		end

		humanoid.MaxHealth = desiredMaxHealth
		humanoid.Health = math.clamp(desiredMaxHealth * healthRatio, 0, desiredMaxHealth)
	end

	function api.applyHumanoidMoveSpeedBonus(humanoid, moveSpeedMultiplier)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end

		local baseWalkSpeed = humanoid:GetAttribute("ClassBaseWalkSpeed")
		if type(baseWalkSpeed) ~= "number" or baseWalkSpeed <= 0 then
			baseWalkSpeed = humanoid.WalkSpeed
			humanoid:SetAttribute("ClassBaseWalkSpeed", baseWalkSpeed)
		end

		local desiredWalkSpeed = math.max(1, baseWalkSpeed * moveSpeedMultiplier * getWaveMoveSpeedMultiplier())
		if math.abs(desiredWalkSpeed - humanoid.WalkSpeed) < 0.01 then
			return
		end

		humanoid.WalkSpeed = desiredWalkSpeed
	end

	function api.applyCharacterClassBonuses(player, character)
		local _, bonuses = getPlayerSelectedClassBonuses(player)
		if not bonuses then
			return
		end

		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			api.applyHumanoidClassBonus(humanoid, bonuses.maxHealthMultiplier)
			api.applyHumanoidMoveSpeedBonus(humanoid, bonuses.moveSpeedMultiplier)
		end
	end

	function api.refreshAllCharacterClassBonuses()
		for _, player in playersService:GetPlayers() do
			local character = player.Character
			if character then
				api.applyCharacterClassBonuses(player, character)
			end
		end
	end

	function api.enforceContainerLoadout(player, container)
		if not container then
			return
		end

		local classDef = getPlayerClassDefinition(player)
		if not classDef then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local weaponId = child:GetAttribute("WeaponId")
				if type(weaponId) ~= "string" or weaponId == "" then
					continue
				end

				local weaponDef = getWeaponById(weaponId)
				if weaponDef and not isWeaponAllowedForClass(classDef, weaponDef) then
					child:Destroy()
				end
			end
		end
	end

	function api.enforcePlayerLoadout(player)
		api.enforceContainerLoadout(player, player:FindFirstChildOfClass("Backpack"))
		api.enforceContainerLoadout(player, player:FindFirstChild("StarterGear"))
		api.enforceContainerLoadout(player, player.Character)
	end

	return api
end

return ClassRuntimeEffects
