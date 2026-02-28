--[[
	ShopService — Main shop system service.
	Manages shop remotes, weapon catalog, and purchase flows.
	Orchestrates weapon trading and ammo refills.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local CatalogAndPricing = require(script.Parent.CatalogAndPricing)
local ShopContextFactory = require(script.Parent.ShopContextFactory)
local InventoryIndex = require(script.Parent.InventoryIndex)
local CurrencyService = require(script.Parent.Currency.CurrencyService)
local PurchaseFlow = require(script.Parent.PurchaseFlow)
local ShopConstants = require(script.Parent.ShopConstants)
local TraderAccess = require(script.Parent.TraderAccess)
local SentryRuntime = require(Match.Weapons.Sentry.Registry.SentryRuntime)
local WeaponAmmoRuntime = require(Match.Weapons.Tools.WeaponAmmoRuntime)
local WeaponToolSetup = require(Match.Weapons.Tools.WeaponToolSetup)
local WeaponVfx = require(Match.Weapons.Combat.WeaponVfx)
local SentryTurretController = require(Match.Weapons.Sentry.SentryTurretController)
local WeaponToolFactory = require(Match.Weapons.Tools.WeaponToolFactory)
local WeaponFireHandlers = require(Match.Weapons.Combat.WeaponFireHandlers)
local WeaponRemoteBindings = require(Match.Weapons.Combat.WeaponRemoteBindings)

-- Aliases from ShopConstants
local SENTRY_TURRET_FOLDER_NAME = ShopConstants.SENTRY_TURRET_FOLDER_NAME
local DEFAULT_SENTRY_MAX_AMMO = ShopConstants.DEFAULT_SENTRY_MAX_AMMO

-- Aliases from WeaponVfx (VFX creators for sentry runtime)
local createTracerSegment = WeaponVfx.createTracerSegment
local createMuzzleFlash = WeaponVfx.createMuzzleFlash
local createFlamePuff = WeaponVfx.createFlamePuff
local createExplosionEffect = WeaponVfx.createExplosionEffect

-- Aliases from WeaponToolSetup
local resolveWeaponClass = WeaponToolSetup.resolveWeaponClass

local ShopService = {}

-- Module state
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

local function isPlayerInstance(player)
	return player and player:IsA("Player")
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

-- ================================================================================
-- Sentry Turret Helpers
-- ================================================================================

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

local function getSentryTurretFolder()
	return sentryRuntime.getSentryTurretFolder()
end

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

-- ================================================================================
-- Ammo Runtime Helpers
-- ================================================================================

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

-- ================================================================================
-- Weapon Ownership & Catalog Helpers
-- ================================================================================

local function getMagazineSize(weaponDef, player)
	return ammoRuntime.getMagazineSize(weaponDef, player)
end

local function getReloadSeconds(weaponDef, player)
	return ammoRuntime.getReloadSeconds(weaponDef, player)
end

local function playerOwnsWeapon(player, weaponId)
	local normalizedWeaponId = tostring(weaponId or "")
	if normalizedWeaponId == "" then
		return false
	end

	local weaponDef = weaponById[normalizedWeaponId]
	local weaponClass = resolveWeaponClass(weaponDef)
	if weaponClass == "RepairTool" then
		return false
	end

	if weaponClass == "SentryDeployer" then
		if InventoryIndex.hasWeaponTool(player, normalizedWeaponId) then
			return true
		end

		return sentryRuntime.playerOwnsWeaponId(player, normalizedWeaponId)
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

-- ================================================================================
-- Ammo Refill Quotes
-- ================================================================================

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

-- ================================================================================
-- Catalog & Purchase Handlers
-- ================================================================================

local function getCatalogForPlayer(player)
	return TraderAccess.runIfAccessible(player, function()
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
	end, function()
		local _, waveState = canPurchaseNow()
		return TraderAccess.getDeniedCatalogResponse(waveState)
	end)
end

local function buyWeapon(player, weaponId)
	return TraderAccess.runIfAccessible(player, function()
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
				getMoneyAmount = CurrencyService.getMoneyAmount,
				trySpendMoney = CurrencyService.trySpendMoney,
				refundMoney = CurrencyService.refundMoney,
				getWeaponCostForPlayer = getWeaponCostForPlayer,
				createWeaponTool = WeaponToolFactory.createWeaponTool,
			})
		)
	end)
end

local function buyAmmoForWeapon(player, weaponId)
	return TraderAccess.runIfAccessible(player, function()
		return PurchaseFlow.buyAmmoForWeapon(
			player,
			weaponId,
			ShopContextFactory.createAmmoPurchaseContext({
				weaponById = weaponById,
				canPurchaseNow = canPurchaseNow,
				canPlayerUseWeapon = canPlayerUseWeapon,
				getClassRestrictionMessage = getClassRestrictionMessage,
				collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
				getMoneyAmount = CurrencyService.getMoneyAmount,
				trySpendMoney = CurrencyService.trySpendMoney,
				refundMoney = CurrencyService.refundMoney,
				refillAmmoForTool = refillAmmoForTool,
				refillAmmoForSentryRecords = refillAmmoForSentryRecords,
			})
		)
	end)
end

local function buyAmmoForAllOwnedWeapons(player)
	return TraderAccess.runIfAccessible(player, function()
		return PurchaseFlow.buyAmmoForAllOwnedWeapons(
			player,
			ShopContextFactory.createAllAmmoPurchaseContext({
				weaponById = weaponById,
				canPurchaseNow = canPurchaseNow,
				collectAmmoRefillQuotesForOwnedWeapons = collectAmmoRefillQuotesForOwnedWeapons,
				getMoneyAmount = CurrencyService.getMoneyAmount,
				trySpendMoney = CurrencyService.trySpendMoney,
				refundMoney = CurrencyService.refundMoney,
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

-- ================================================================================
-- Shop UI & Trader
-- ================================================================================

local function getInvalidRequestResponse(message)
	return {
		success = false,
		message = message,
	}
end

-- ================================================================================
-- Service Lifecycle
-- ================================================================================

function ShopService.start()
	if started then
		return
	end

	-- Clear existing sentry turrets
	local turretFolder = getSentryTurretFolder()
	for _, child in ipairs(turretFolder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	-- Initialize weapon catalog
	table.clear(weaponById)
	for _, weaponDef in ipairs(Config.Shop.Weapons or {}) do
		weaponById[weaponDef.Id] = weaponDef
	end

	-- Get remotes folder
	remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not remotesFolder then
		warn("ShopService could not find remotes folder")
		return
	end

	-- Create shop remotes
	shopOpenRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.ShopOpen)
	shopGetCatalogFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopGetCatalog)
	shopBuyWeaponFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyWeapon)
	shopBuyAmmoFunction = ensureRemote(remotesFolder, "RemoteFunction", Config.Remotes.ShopBuyAmmo)

	-- Create combat remotes
	weaponAimRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponAim)
	weaponFireRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponFire)
	weaponReloadRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.WeaponReload)
	damageIndicatorRemote = ensureRemote(remotesFolder, "RemoteEvent", Config.Remotes.DamageIndicator)

	-- Initialize weapon tool factory (handler registry from WeaponFireHandlers for scalability)
	WeaponToolFactory.init({
		ammoRuntime = ammoRuntime,
		sentryTurretController = SentryTurretController,
		inventoryIndex = InventoryIndex,
		weaponFireRemote = weaponFireRemote,
		fireMeleeAttack = WeaponFireHandlers.fireMeleeAttack,
		fireBulletShot = WeaponFireHandlers.fireBulletShot,
		getClassFireHandlers = WeaponFireHandlers.getClassFireHandlers,
	})

	-- Start weapon remote bindings
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

	-- Bind shop remote handlers
	shopGetCatalogFunction.OnServerInvoke = function(player)
		return getCatalogForPlayer(player)
	end

	-- Handle class changes (clear player sentries on class change)
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

	-- Bind purchase handlers
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

	-- Ensure trader prompt exists
	TraderAccess.ensureTraderPrompt(function(player)
		if shopOpenRemote then
			shopOpenRemote:FireClient(player)
		end
	end)

	started = true
end

function ShopService.stop()
	if not started then
		return
	end

	-- Clean up class changed callback
	if classChangedCleanupDisconnect then
		classChangedCleanupDisconnect:Disconnect()
		classChangedCleanupDisconnect = nil
	end

	-- Clear remotes
	if remotesFolder then
		local remotesToClear = {
			Config.Remotes.ShopOpen,
			Config.Remotes.ShopGetCatalog,
			Config.Remotes.ShopBuyWeapon,
			Config.Remotes.ShopBuyAmmo,
			Config.Remotes.WeaponAim,
			Config.Remotes.WeaponFire,
			Config.Remotes.WeaponReload,
			Config.Remotes.DamageIndicator,
		}
		for _, name in ipairs(remotesToClear) do
			local remote = remotesFolder:FindFirstChild(name)
			if remote then
				remote:Destroy()
			end
		end
	end

	started = false
end

return ShopService
