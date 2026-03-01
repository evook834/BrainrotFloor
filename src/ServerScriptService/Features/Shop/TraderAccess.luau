--[[
	TraderAccess — Shop access and trader prompt helpers.
	Encapsulates distance checks and ProximityPrompt setup for the weapon trader.
	Used by ShopService to gate catalog/purchase requests without changing behavior.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local SHOP_DENIED_MESSAGE = "Move closer to the trader."

local TraderAccess = {}

-- Module state for cached trader parts/prompt
local traderRootPart: BasePart? = nil
local traderPrompt: ProximityPrompt? = nil

local function isPlayerInstance(player)
	return player and player:IsA("Player")
end

local function getTraderConfig()
	return (Config.Shop and Config.Shop.Trader) or {}
end

local function getTraderNames(traderConfig)
	local modelName = traderConfig.ModelName or "WeaponTrader"
	local partName = traderConfig.PartName or "TraderRoot"
	return modelName, partName
end

local function findTraderRootPart(traderModel: Model, partName: string)
	local rootPart = traderModel:FindFirstChild(partName)
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = traderModel:FindFirstChildWhichIsA("BasePart")
	end
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function resolveTraderRootPart(): BasePart?
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

function TraderAccess.canPlayerAccessShop(player)
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

function TraderAccess.getShopDeniedResponse(message)
	return {
		success = false,
		message = message or SHOP_DENIED_MESSAGE,
	}
end

function TraderAccess.getDeniedCatalogResponse(waveState, message)
	return {
		success = false,
		message = message or SHOP_DENIED_MESSAGE,
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

function TraderAccess.runIfAccessible(player, onAccessible, onDenied)
	if not TraderAccess.canPlayerAccessShop(player) then
		if onDenied then
			return onDenied()
		end

		return TraderAccess.getShopDeniedResponse()
	end

	return onAccessible()
end

function TraderAccess.ensureTraderPrompt(onTriggered)
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

	if type(onTriggered) == "function" then
		prompt.Triggered:Connect(function(player)
			if isPlayerInstance(player) then
				onTriggered(player)
			end
		end)
	end
end

return TraderAccess

