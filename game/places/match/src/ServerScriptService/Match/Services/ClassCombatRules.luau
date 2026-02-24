local ClassCombatRules = {}

function ClassCombatRules.new(config)
	local combatConfig = config or {}
	local normalizeToken = combatConfig.normalizeToken
	local getPlayerClassDefinition = combatConfig.getPlayerClassDefinition
	local getPlayerSelectedClassBonuses = combatConfig.getPlayerSelectedClassBonuses

	local api = {}

	function api.isWeaponAllowedForClass(classDef, weaponDef)
		if not classDef or type(weaponDef) ~= "table" then
			return false
		end

		local classIdToken = normalizeToken(classDef.Id)
		local classWeaponTagToken = normalizeToken(classDef.WeaponTag)

		local requiredClassIdToken = normalizeToken(weaponDef.ClassId)
		if requiredClassIdToken ~= "" then
			return requiredClassIdToken == classIdToken
		end

		local weaponTagToken = normalizeToken(weaponDef.ClassTag)
		if weaponTagToken ~= "" then
			if classWeaponTagToken ~= "" and weaponTagToken == classWeaponTagToken then
				return true
			end
			return weaponTagToken == classIdToken
		end

		return false
	end

	function api.canPlayerUseWeapon(player, weaponDef)
		if not player or not player:IsA("Player") then
			return false
		end
		if type(weaponDef) ~= "table" then
			return false
		end

		local classDef = getPlayerClassDefinition(player)
		return api.isWeaponAllowedForClass(classDef, weaponDef)
	end

	local function getPlayerWeaponBonuses(player, weaponDef)
		if not player or not player:IsA("Player") then
			return nil
		end
		if type(weaponDef) ~= "table" then
			return nil
		end

		local classDef, bonuses = getPlayerSelectedClassBonuses(player)
		if not classDef or not api.isWeaponAllowedForClass(classDef, weaponDef) then
			return nil
		end

		return bonuses
	end

	function api.getWeaponDamageMultiplier(player, weaponDef)
		if not api.canPlayerUseWeapon(player, weaponDef) then
			return 0
		end

		local _, bonuses = getPlayerSelectedClassBonuses(player)
		if not bonuses then
			return 0
		end

		return math.max(0, bonuses.damageMultiplier)
	end

	function api.getIncomingDamageMultiplier(player)
		if not player or not player:IsA("Player") then
			return 1
		end

		local _, bonuses = getPlayerSelectedClassBonuses(player)
		if not bonuses then
			return 1
		end

		return math.max(0.05, bonuses.incomingDamageMultiplier)
	end

	function api.getMeleeRangeMultiplier(player, weaponDef)
		if not player or not player:IsA("Player") then
			return 1
		end
		if weaponDef and type(weaponDef) == "table" and not api.canPlayerUseWeapon(player, weaponDef) then
			return 1
		end

		local _, bonuses = getPlayerSelectedClassBonuses(player)
		if not bonuses then
			return 1
		end

		return math.max(0.1, bonuses.meleeRangeMultiplier)
	end

	function api.getWeaponShopCost(player, weaponDef)
		local baseCost = math.max(0, math.floor((tonumber(weaponDef and weaponDef.Cost) or 0) + 0.5))
		if baseCost <= 0 then
			return 0
		end

		local bonuses = getPlayerWeaponBonuses(player, weaponDef)
		if not bonuses then
			return baseCost
		end

		local adjustedCost = math.floor((baseCost * math.max(0.1, bonuses.shopCostMultiplier or 1)) + 0.5)
		return math.max(1, adjustedCost)
	end

	function api.getWeaponMagazineSize(player, weaponDef)
		local baseMagazineSize = tonumber(weaponDef and weaponDef.MagazineSize)
		if not baseMagazineSize then
			return nil
		end

		baseMagazineSize = math.floor(baseMagazineSize + 0.5)
		if baseMagazineSize <= 0 then
			return nil
		end

		local bonuses = getPlayerWeaponBonuses(player, weaponDef)
		if not bonuses then
			return baseMagazineSize
		end

		local adjustedMagazineSize = math.floor((baseMagazineSize * math.max(0.1, bonuses.magazineSizeMultiplier or 1)) + 0.5)
		return math.max(1, adjustedMagazineSize)
	end

	function api.getWeaponReloadSeconds(player, weaponDef)
		local configuredReload = tonumber(weaponDef and weaponDef.ReloadSeconds)
		if not configuredReload then
			return nil
		end

		local reloadSeconds = math.max(0.2, configuredReload)
		local bonuses = getPlayerWeaponBonuses(player, weaponDef)
		if not bonuses then
			return reloadSeconds
		end

		return math.max(0.2, reloadSeconds * math.max(0.1, bonuses.reloadTimeMultiplier or 1))
	end

	function api.getWeaponSpreadDegrees(player, weaponDef)
		local baseSpreadDegrees = tonumber(weaponDef and weaponDef.SpreadDegrees)
		if type(baseSpreadDegrees) ~= "number" then
			return nil
		end
		if baseSpreadDegrees <= 0 then
			return 0
		end

		local bonuses = getPlayerWeaponBonuses(player, weaponDef)
		if not bonuses then
			return baseSpreadDegrees
		end

		return math.max(0, baseSpreadDegrees * math.max(0.2, bonuses.bulletSpreadMultiplier or 1))
	end

	function api.getWeaponBulletRangeMultiplier(player, weaponDef)
		local bonuses = getPlayerWeaponBonuses(player, weaponDef)
		if not bonuses then
			return 1
		end

		return math.max(0.1, bonuses.bulletRangeMultiplier or 1)
	end

	return api
end

return ClassCombatRules
