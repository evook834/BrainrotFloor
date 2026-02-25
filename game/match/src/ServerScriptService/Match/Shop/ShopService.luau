local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local CatalogAndPricing = require(script.Parent.CatalogAndPricing)
local InventoryIndex = require(script.Parent.InventoryIndex)
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
	return CatalogAndPricing.collectAmmoRefillQuotesForOwnedWeapons(player, {
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
end

local function getClassRestrictionMessage(player)
	return CatalogAndPricing.getClassRestrictionMessage(player, ClassService)
end

local function getCatalogForPlayer(player)
	return CatalogAndPricing.getCatalogForPlayer(player, {
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
end

local function buyWeapon(player, weaponId)
	return PurchaseFlow.buyWeapon(player, weaponId, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		canPlayerUseWeapon = canPlayerUseWeapon,
		getClassRestrictionMessage = getClassRestrictionMessage,
		getRequiredOwnedWeaponId = getRequiredOwnedWeaponId,
		playerOwnsWeapon = playerOwnsWeapon,
		getUpgradeRestrictionMessage = getUpgradeRestrictionMessage,
		getMoneyValue = EnemyDamageService.getMoneyValue,
		getWeaponCostForPlayer = getWeaponCostForPlayer,
		createWeaponTool = WeaponToolFactory.createWeaponTool,
	})
end

local function buyAmmoForWeapon(player, weaponId)
	return PurchaseFlow.buyAmmoForWeapon(player, weaponId, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		canPlayerUseWeapon = canPlayerUseWeapon,
		getClassRestrictionMessage = getClassRestrictionMessage,
		collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyValue = EnemyDamageService.getMoneyValue,
		refillAmmoForTool = refillAmmoForTool,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
	})
end

local function buyAmmoForAllOwnedWeapons(player)
	return PurchaseFlow.buyAmmoForAllOwnedWeapons(player, {
		weaponById = weaponById,
		canPurchaseNow = canPurchaseNow,
		collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
		getMoneyValue = EnemyDamageService.getMoneyValue,
		refillAmmoForTool = refillAmmoForTool,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
	})
end

function ShopService.refillPlayerAmmo(player, options)
	if not player or not player:IsA("Player") then
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
	local traderConfig = Config.Shop.Trader or {}
	local modelName = traderConfig.ModelName or "WeaponTrader"
	local partName = traderConfig.PartName or "TraderRoot"

	local traderModel = Workspace:FindFirstChild(modelName)
	if not (traderModel and traderModel:IsA("Model")) then
		traderModel = Instance.new("Model")
		traderModel.Name = modelName
		traderModel.Parent = Workspace
	end

	local rootPart = traderModel:FindFirstChild(partName)
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = traderModel:FindFirstChildWhichIsA("BasePart")
	end

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

	prompt.Triggered:Connect(function(player)
		if shopOpenRemote then
			shopOpenRemote:FireClient(player)
		end
	end)
end

function ShopService.start()
	if started then
		return
	end
	started = true

	local turretFolder = getSentryTurretFolder()
	for _, child in ipairs(turretFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

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
			if not player or not player:IsA("Player") then
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
			return {
				success = false,
				message = "Invalid purchase request.",
			}
		end

		return buyWeapon(player, weaponId)
	end

	shopBuyAmmoFunction.OnServerInvoke = function(player, request)
		if type(request) == "string" then
			return buyAmmoForWeapon(player, request)
		end

		if type(request) ~= "table" then
			return {
				success = false,
				message = "Invalid ammo purchase request.",
			}
		end

		if request.allOwned == true then
			return buyAmmoForAllOwnedWeapons(player)
		end

		local weaponId = request.weaponId
		if type(weaponId) ~= "string" or weaponId == "" then
			return {
				success = false,
				message = "Invalid weapon ammo request.",
			}
		end

		return buyAmmoForWeapon(player, weaponId)
	end

	ensureTraderPrompt()
end

return ShopService
