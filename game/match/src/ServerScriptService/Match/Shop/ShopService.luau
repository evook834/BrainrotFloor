local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local PlayerDataService = require(ServerScriptService.Shared.PlayerData.PlayerDataService)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local CatalogAndPricing = require(script.Parent.CatalogAndPricing)
local ShopContextFactory = require(script.Parent.ShopContextFactory)
local InventoryIndex = require(script.Parent.InventoryIndex)
local ShopMoney = require(script.Parent.ShopMoney)
local PurchaseFlow = require(script.Parent.PurchaseFlow)
local ShopConstants = require(script.Parent.ShopConstants)
local EnemyDamageService = require(Match.Combat.EnemyDamageService)
local SentryRuntime = require(Match.Weapons.SentryRuntime)
local WeaponAmmoRuntime = require(Match.Weapons.WeaponAmmoRuntime)
local WeaponToolSetup = require(Match.Weapons.WeaponToolSetup)
local WeaponVfx = require(Match.Weapons.WeaponVfx)
local SentryTurretController = require(Match.Weapons.SentryTurretController)
local WeaponToolFactory = require(Match.Weapons.WeaponToolFactory)
local WeaponFireHandlers = require(Match.Weapons.WeaponFireHandlers)
local WeaponRemoteBindings = require(Match.Weapons.WeaponRemoteBindings)

-- Aliases from ShopConstants
local SENTRY_TURRET_FOLDER_NAME = ShopConstants.SENTRY_TURRET_FOLDER_NAME
local DEFAULT_SENTRY_MAX_AMMO = ShopConstants.DEFAULT_SENTRY_MAX_AMMO

-- Aliases from WeaponVfx (VFX creators for sentry runtime)
local createTracerSegment = WeaponVfx.createTracerSegment
local createMuzzleFlash = WeaponVfx.createMuzzleFlash
local createFlamePuff = WeaponVfx.createFlamePuff
local createExplosionEffect = WeaponVfx.createExplosionEffect

-- Aliases from WeaponToolSetup (weapon class; tool creation in WeaponToolFactory)
local resolveWeaponClass = WeaponToolSetup.resolveWeaponClass

local SHOP_DENIED_MESSAGE = "Move closer to the trader."

local ShopService = {}

-- Module state: remotes, weapon catalog, runtimes
local started = false
local remotesFolder = nil
local shopOpenRemote = nil
local shopGetCatalogFunction = nil
local shopBuyWeaponFunction = nil
local shopBuyAmmoFunction = nil
local weaponAimRemote = nil
local weaponFireRemote = nil
local weaponReloadRemote = nil
local damageIndicatorRemote = nil
local weaponById = {}
local ammoRuntime = WeaponAmmoRuntime.new({
	classService = ClassService,
	inventoryIndex = InventoryIndex,
})
local toolRuntimeState = ammoRuntime.getStateMap()
local randomGenerator = Random.new()
local sentryRuntime = nil
local classChangedCleanupDisconnect = nil
local traderRootPart = nil
local traderPrompt = nil
local moneyOps = ShopMoney.create({
	playerDataService = PlayerDataService,
	enemyDamageService = EnemyDamageService,
})
local getCurrentMoney = moneyOps.getCurrentMoney
local trySpendMoney = moneyOps.trySpendMoney
local refundMoney = moneyOps.refundMoney

local function isPlayerInstance(player)
	return player and player:IsA("Player")
end

local function getTraderNames(traderConfig)
	local modelName = traderConfig.ModelName or "WeaponTrader"
	local partName = traderConfig.PartName or "TraderRoot"
	return modelName, partName
end

local function findTraderRootPart(traderModel, partName)
	local rootPart = traderModel:FindFirstChild(partName)
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = traderModel:FindFirstChildWhichIsA("BasePart")
	end
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function ensureRemote(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if instance and instance.ClassName == className then
		return instance
	end

	if instance then
		instance:Destroy()
	end

	instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function getSentryTurretFolder()
	return sentryRuntime.getSentryTurretFolder()
end

local function getMagazineSize(weaponDef, player)
	return ammoRuntime.getMagazineSize(weaponDef, player)
end

local function getReloadSeconds(weaponDef, player)
	return ammoRuntime.getReloadSeconds(weaponDef, player)
end

sentryRuntime = SentryRuntime.new({
	modelRootResolver = ModelRootResolver,
	createExplosionEffect = createExplosionEffect,
	createMuzzleFlash = createMuzzleFlash,
	createTracerSegment = createTracerSegment,
	createFlamePuff = createFlamePuff,
	randomGenerator = randomGenerator,
	sentryTurretFolderName = SENTRY_TURRET_FOLDER_NAME,
	defaultSentryMaxAmmo = DEFAULT_SENTRY_MAX_AMMO,
})

local function clearPlayerSentries(player, options)
	sentryRuntime.clearPlayerSentries(player, options)
end

local function prunePlayerSentries(player)
	return sentryRuntime.prunePlayerSentries(player)
end

local function collectOwnedSentryRecordsByWeaponId(player)
	return sentryRuntime.collectOwnedSentryRecordsByWeaponId(player)
end

SentryTurretController.init({ sentryRuntime = sentryRuntime, fireRocket = WeaponFireHandlers.fireRocket })

local function normalizeAmmoRefillMode(value)
	return ammoRuntime.normalizeAmmoRefillMode(value)
end

local function refillAmmoForTool(tool, weaponDef, owner, refillMode, reserveAmount)
	return ammoRuntime.refillAmmoForTool(tool, weaponDef, owner, refillMode, reserveAmount)
end

local function refillAmmoForSentryRecords(sentryRecords, weaponDef)
	return sentryRuntime.refillAmmoForSentryRecords(sentryRecords, weaponDef)
end

local function getSentryAmmoSnapshot(sentryRecords, weaponDef)
	return sentryRuntime.getSentryAmmoSnapshot(sentryRecords, weaponDef)
end

local function playerOwnsWeapon(player, weaponId)
	local normalizedWeaponId = tostring(weaponId or "")
	if normalizedWeaponId == "" then
		return false
	end

	if InventoryIndex.hasWeaponTool(player, normalizedWeaponId) then
		return true
	end

	return sentryRuntime.playerOwnsWeaponId(player, normalizedWeaponId)
end

local function getRequiredOwnedWeaponId(weaponDef)
	return CatalogAndPricing.getRequiredOwnedWeaponId(weaponDef, weaponById)
end

local function getUpgradeRestrictionMessage(weaponDef)
	return CatalogAndPricing.getUpgradeRestrictionMessage(weaponDef, weaponById)
end

local function canPurchaseNow()
	return CatalogAndPricing.canPurchaseNow(remotesFolder, Config)
end

local function canPlayerUseWeapon(player, weaponDef)
	return ClassService.canPlayerUseWeapon(player, weaponDef)
end

local function getWeaponCostForPlayer(player, weaponDef)
	return CatalogAndPricing.getWeaponCostForPlayer(player, weaponDef, ClassService)
end

local function collectOwnedWeaponToolsById(player)
	return InventoryIndex.collectFirstWeaponToolById(player)
end

local function getToolAmmoSnapshot(tool, weaponDef, owner)
	return ammoRuntime.getToolAmmoSnapshot(tool, weaponDef, owner)
end

local function collectAmmoRefillQuotesForOwnedWeapons(player)
	return CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(
		player,
		ShopContextFactory.createAmmoQuoteContext({
			config = Config,
			weaponById = weaponById,
			canPlayerUseWeapon = canPlayerUseWeapon,
			collectOwnedWeaponToolsById = collectOwnedWeaponToolsById,
			prunePlayerSentries = prunePlayerSentries,
			collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
			getToolAmmoSnapshot = getToolAmmoSnapshot,
			getSentryAmmoSnapshot = getSentryAmmoSnapshot,
			getWeaponCostForPlayer = getWeaponCostForPlayer,
		})
	)
end

local function getClassRestrictionMessage(player)
	return CatalogAndPricing.getClassRestrictionMessage(player, ClassService)
end

local function getTraderConfig()
	return Config.Shop.Trader or {}
end

local function resolveTraderRootPart()
	if traderRootPart and traderRootPart.Parent then
		return traderRootPart
	end

	local traderConfig = getTraderConfig()
	local modelName, partName = getTraderNames(traderConfig)
	local traderModel = Workspace:FindFirstChild(modelName)
	if not (traderModel and traderModel:IsA("Model")) then
		return nil
	end

	local rootPart = findTraderRootPart(traderModel, partName)
	if rootPart then
		traderRootPart = rootPart
		return rootPart
	end

	return nil
end

local function getTraderAccessDistance()
	if traderPrompt and traderPrompt.Parent then
		return math.max(0, tonumber(traderPrompt.MaxActivationDistance) or 0)
	end

	return math.max(0, tonumber(getTraderConfig().MaxActivationDistance) or 12)
end

local function canPlayerAccessShop(player)
	if not isPlayerInstance(player) then
		return false
	end

	local rootPart = resolveTraderRootPart()
	if not rootPart then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local characterRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not (characterRoot and characterRoot:IsA("BasePart")) then
		characterRoot = character:FindFirstChildWhichIsA("BasePart")
	end
	if not (characterRoot and characterRoot:IsA("BasePart")) then
		return false
	end

	local allowedDistance = getTraderAccessDistance() + (rootPart.Size.Magnitude * 0.5) + 3
	return (characterRoot.Position - rootPart.Position).Magnitude <= allowedDistance
end

local function getShopDeniedResponse()
	return {
		success = false,
		message = SHOP_DENIED_MESSAGE,
	}
end

local function getDeniedCatalogResponse(waveState)
	return {
		success = false,
		message = SHOP_DENIED_MESSAGE,
		canPurchase = false,
		waveState = waveState,
		weapons = {},
		refillAllCost = 0,
		canRefillAll = false,
		ownedWeapons = 0,
		ownedRefillableWeapons = 0,
		refillableWeaponsWithMissingAmmo = 0,
	}
end

local function runShopPurchaseIfAccessible(player, callback)
	if not canPlayerAccessShop(player) then
		return getShopDeniedResponse()
	end

	return callback()
end

local function getCatalogForPlayer(player)
	if not canPlayerAccessShop(player) then
		local _, waveState = canPurchaseNow()
		return getDeniedCatalogResponse(waveState)
	end

	return CatalogAndPricing.getCatalogForPlayer(
		player,
		ShopContextFactory.createCatalogContext({
			config = Config,
			classService = ClassService,
			weaponById = weaponById,
			remotesFolder = remotesFolder,
			canPlayerUseWeapon = canPlayerUseWeapon,
			playerOwnsWeapon = playerOwnsWeapon,
			resolveWeaponClass = resolveWeaponClass,
			getWeaponCostForPlayer = getWeaponCostForPlayer,
			getMagazineSize = getMagazineSize,
			getReloadSeconds = getReloadSeconds,
			collectOwnedWeaponToolsById = collectOwnedWeaponToolsById,
			prunePlayerSentries = prunePlayerSentries,
			collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
			getToolAmmoSnapshot = getToolAmmoSnapshot,
			getSentryAmmoSnapshot = getSentryAmmoSnapshot,
		})
	)
end

local function buyWeapon(player, weaponId)
	return runShopPurchaseIfAccessible(player, function()
		return PurchaseFlow.buyWeapon(
			player,
			weaponId,
			ShopContextFactory.createWeaponPurchaseContext({
				weaponById = weaponById,
				canPurchaseNow = canPurchaseNow,
				canPlayerUseWeapon = canPlayerUseWeapon,
				getClassRestrictionMessage = getClassRestrictionMessage,
				getRequiredOwnedWeaponId = getRequiredOwnedWeaponId,
				playerOwnsWeapon = playerOwnsWeapon,
				getUpgradeRestrictionMessage = getUpgradeRestrictionMessage,
				getCurrentMoney = getCurrentMoney,
				trySpendMoney = trySpendMoney,
				refundMoney = refundMoney,
				getWeaponCostForPlayer = getWeaponCostForPlayer,
				createWeaponTool = WeaponToolFactory.createWeaponTool,
			})
		)
	end)
end

local function buyAmmoForWeapon(player, weaponId)
	return runShopPurchaseIfAccessible(player, function()
		return PurchaseFlow.buyAmmoForWeapon(
			player,
			weaponId,
			ShopContextFactory.createAmmoPurchaseContext({
				weaponById = weaponById,
				canPurchaseNow = canPurchaseNow,
				canPlayerUseWeapon = canPlayerUseWeapon,
				getClassRestrictionMessage = getClassRestrictionMessage,
				collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
				getCurrentMoney = getCurrentMoney,
				trySpendMoney = trySpendMoney,
				refundMoney = refundMoney,
				refillAmmoForTool = refillAmmoForTool,
				refillAmmoForSentryRecords = refillAmmoForSentryRecords,
			})
		)
	end)
end

local function buyAmmoForAllOwnedWeapons(player)
	return runShopPurchaseIfAccessible(player, function()
		return PurchaseFlow.buyAmmoForAllOwnedWeapons(
			player,
			ShopContextFactory.createAllAmmoPurchaseContext({
				weaponById = weaponById,
				canPurchaseNow = canPurchaseNow,
				collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
				getCurrentMoney = getCurrentMoney,
				trySpendMoney = trySpendMoney,
				refundMoney = refundMoney,
				refillAmmoForTool = refillAmmoForTool,
				refillAmmoForSentryRecords = refillAmmoForSentryRecords,
			})
		)
	end)
end

function ShopService.refillPlayerAmmo(player, options)
	if not isPlayerInstance(player) then
		return false
	end

	local refillMode = "ReserveOnly"
	local reserveAmount = nil
	if type(options) == "table" then
		refillMode = normalizeAmmoRefillMode(options.mode)
		reserveAmount = options.reserveAmount
	end

	local anyRefilled = false
	for _, tool in ipairs(InventoryIndex.getAllTools(player)) do
		local weaponId = tool:GetAttribute("WeaponId")
		if type(weaponId) == "string" and weaponId ~= "" then
			local weaponDef = weaponById[weaponId]
			if weaponDef and refillAmmoForTool(tool, weaponDef, player, refillMode, reserveAmount) then
				anyRefilled = true
			end
		end
	end

	return anyRefilled
end

local function ensureTraderPrompt()
	local traderConfig = getTraderConfig()
	local modelName, partName = getTraderNames(traderConfig)

	local traderModel = Workspace:FindFirstChild(modelName)
	if not (traderModel and traderModel:IsA("Model")) then
		traderModel = Instance.new("Model")
		traderModel.Name = modelName
		traderModel.Parent = Workspace
	end

	local rootPart = findTraderRootPart(traderModel, partName)

	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = partName
		rootPart.Size = Vector3.new(3, 6, 2)
		rootPart.Color = Color3.fromRGB(120, 85, 70)
		rootPart.Material = Enum.Material.WoodPlanks
		rootPart.Anchored = true
		rootPart.CFrame = CFrame.new(traderConfig.Position or Vector3.new(0, 4, -25))
		rootPart.Parent = traderModel
	end

	traderModel.PrimaryPart = rootPart
	traderRootPart = rootPart

	local prompt = rootPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = rootPart
	end

	prompt.ActionText = traderConfig.ActionText or "Open Store"
	prompt.ObjectText = traderConfig.ObjectText or "Weapon Trader"
	prompt.MaxActivationDistance = traderConfig.MaxActivationDistance or 12
	prompt.HoldDuration = traderConfig.HoldDuration or 0.15
	prompt.RequiresLineOfSight = false
	traderPrompt = prompt

	prompt.Triggered:Connect(function(player)
		if shopOpenRemote then
			shopOpenRemote:FireClient(player)
		end
	end)
end

local function getInvalidRequestResponse(message)
	return {
		success = false,
		message = message,
	}
end

function ShopService.start()
	if started then
		return
	end

	local turretFolder = getSentryTurretFolder()
	for _, child in ipairs(turretFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	table.clear(weaponById)
	for _, weaponDef in ipairs(Config.Shop.Weapons or {}) do
		weaponById[weaponDef.Id] = weaponDef
	end

	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		warn("ShopService could not find remotes folder")
		return
	end

	shopOpenRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.ShopOpen)
	shopGetCatalogFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopGetCatalog)
	shopBuyWeaponFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyWeapon)
	shopBuyAmmoFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyAmmo)
	weaponAimRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponAim)
	weaponFireRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponFire)
	weaponReloadRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponReload)
	damageIndicatorRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.DamageIndicator)
	WeaponToolFactory.init({
		ammoRuntime = ammoRuntime,
		sentryTurretController = SentryTurretController,
		inventoryIndex = InventoryIndex,
		weaponFireRemote = weaponFireRemote,
		fireMeleeAttack = WeaponFireHandlers.fireMeleeAttack,
		fireBulletShot = WeaponFireHandlers.fireBulletShot,
		fireRocket = WeaponFireHandlers.fireRocket,
		fireGrenadeLauncher = WeaponFireHandlers.fireGrenadeLauncher,
		fireFlamethrower = WeaponFireHandlers.fireFlamethrower,
	})

	WeaponRemoteBindings.start({
		weaponAimRemote = weaponAimRemote,
		weaponFireRemote = weaponFireRemote,
		weaponReloadRemote = weaponReloadRemote,
		damageIndicatorRemote = damageIndicatorRemote,
		weaponById = weaponById,
		toolRuntimeState = toolRuntimeState,
		ammoRuntime = ammoRuntime,
		classService = ClassService,
		weaponToolFactory = WeaponToolFactory,
		sentryRuntime = sentryRuntime,
	})

	-- Bind shop remotes
	shopGetCatalogFunction.OnServerInvoke = function(player)
		return getCatalogForPlayer(player)
	end

	if not classChangedCleanupDisconnect and type(ClassService.registerClassChangedCallback) == "function" then
		classChangedCleanupDisconnect = ClassService.registerClassChangedCallback(function(player, previousClassId, selectedClassId)
			if not isPlayerInstance(player) then
				return
			end
			if previousClassId == selectedClassId then
				return
			end

			clearPlayerSentries(player, {
				playDestroyEffect = true,
			})
		end)
	end

	shopBuyWeaponFunction.OnServerInvoke = function(player, weaponId)
		if type(weaponId) ~= "string" then
			return getInvalidRequestResponse("Invalid purchase request.")
		end

		return buyWeapon(player, weaponId)
	end

	shopBuyAmmoFunction.OnServerInvoke = function(player, request)
		if type(request) == "string" then
			return buyAmmoForWeapon(player, request)
		end

		if type(request) ~= "table" then
			return getInvalidRequestResponse("Invalid ammo purchase request.")
		end

		if request.allOwned == true then
			return buyAmmoForAllOwnedWeapons(player)
		end

		local weaponId = request.weaponId
		if type(weaponId) ~= "string" or weaponId == "" then
			return getInvalidRequestResponse("Invalid weapon ammo request.")
		end

		return buyAmmoForWeapon(player, weaponId)
	end

	ensureTraderPrompt()
	started = true
end

return ShopService
