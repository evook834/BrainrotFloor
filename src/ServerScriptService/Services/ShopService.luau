local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

local started = false
local remotesFolder = nil
local shopOpenRemote = nil
local shopGetCatalogFunction = nil
local shopBuyWeaponFunction = nil
local weaponById = {}

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

local function getEnemyContainer()
	return Workspace:FindFirstChild(Config.Enemy.ContainerName)
end

local function resolveEnemyRoot(enemyModel)
	if enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") then
		return enemyModel.PrimaryPart
	end

	local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		enemyModel.PrimaryPart = humanoidRootPart
		return humanoidRootPart
	end

	local anyPart = enemyModel:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		enemyModel.PrimaryPart = anyPart
	end
	return anyPart
end

local function findEnemyModelFromDescendant(descendant, enemyContainer)
	local current = descendant
	while current and current ~= enemyContainer do
		if current:IsA("Model") and current.Parent == enemyContainer then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function findTargetEnemy(character, origin, lookVector, range)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	local hit = Workspace:Raycast(origin, lookVector * range, raycastParams)
	if hit then
		local directTarget = findEnemyModelFromDescendant(hit.Instance, enemyContainer)
		if directTarget then
			return directTarget
		end
	end

	local bestTarget = nil
	local bestScore = -math.huge
	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = resolveEnemyRoot(enemyModel)
			if enemyRoot then
				local offset = enemyRoot.Position - origin
				local distance = offset.Magnitude
				if distance <= range and distance > 0.05 then
					local direction = offset.Unit
					local facingScore = lookVector:Dot(direction)
					if facingScore > 0 then
						local score = facingScore * 100 - distance
						if score > bestScore then
							bestScore = score
							bestTarget = enemyModel
						end
					end
				end
			end
		end
	end

	return bestTarget
end

local function getMoneyValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local moneyValue = leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("IntValue") then
		return moneyValue
	end

	return nil
end

local function addMoney(player, amount)
	local moneyValue = getMoneyValue(player)
	if not moneyValue then
		return
	end

	moneyValue.Value += math.max(0, math.floor(amount + 0.5))
end

local function rewardEnemyKill(player, enemyModel)
	if enemyModel:GetAttribute("KillRewardPaid") then
		return
	end

	enemyModel:SetAttribute("KillRewardPaid", true)
	local bounty = enemyModel:GetAttribute("Bounty")
	if type(bounty) ~= "number" then
		bounty = Config.Enemy.BaseBounty or 25
	end

	addMoney(player, bounty)
end

local function applyDamageToEnemy(player, enemyModel, damage)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local previousHealth = humanoid.Health
		if previousHealth <= 0 then
			return
		end

		humanoid:TakeDamage(damage)
		if previousHealth > 0 and humanoid.Health <= 0 then
			rewardEnemyKill(player, enemyModel)
		end
		return
	end

	local maxHealth = enemyModel:GetAttribute("EnemyMaxHealth")
	if type(maxHealth) ~= "number" then
		maxHealth = Config.Enemy.NonHumanoidMaxHealth or 120
	end

	local health = enemyModel:GetAttribute("EnemyHealth")
	if type(health) ~= "number" then
		health = maxHealth
	end

	health -= damage
	enemyModel:SetAttribute("EnemyMaxHealth", maxHealth)
	enemyModel:SetAttribute("EnemyHealth", health)

	if health <= 0 then
		rewardEnemyKill(player, enemyModel)
		enemyModel:Destroy()
	end
end

local function createFallbackWeaponTool(weaponDef)
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = weaponDef.Range >= 20 and Vector3.new(1, 1, 3) or Vector3.new(1, 1, 2)
	handle.Color = weaponDef.Color or Color3.fromRGB(180, 180, 180)
	handle.Material = Enum.Material.Metal
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function createCenterHandleForModel(model, tool)
	local ok, bboxCFrame, bboxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not bboxCFrame then
		return nil
	end

	local oldHandle = model:FindFirstChild("Handle", true)
	if oldHandle and oldHandle:IsA("BasePart") then
		oldHandle.Name = "VisualHandle"
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(
		math.clamp((bboxSize and bboxSize.X or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Y or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Z or 1) * 0.15, 0.2, 1)
	)
	handle.CFrame = bboxCFrame
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Anchored = false
	handle.Parent = tool
	return handle
end

local function hasWeldBetween(partA, partB)
	for _, child in partA:GetChildren() do
		if child:IsA("WeldConstraint") then
			if (child.Part0 == partA and child.Part1 == partB) or (child.Part0 == partB and child.Part1 == partA) then
				return true
			end
		end
	end
	return false
end

local function prepareToolParts(tool, handle)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= handle and not hasWeldBetween(handle, descendant) then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = handle
			end
		end
	end
end

local function findShopItemTemplate(weaponDef)
	local shopItemsFolder = ServerStorage:FindFirstChild("ShopItems")
	if not shopItemsFolder then
		return nil
	end

	local idLower = string.lower(weaponDef.Id or "")
	local nameLower = string.lower(weaponDef.DisplayName or "")
	for _, child in shopItemsFolder:GetChildren() do
		local childNameLower = string.lower(child.Name)
		if childNameLower == idLower or childNameLower == nameLower then
			return child
		end
	end

	return nil
end

local function createToolFromTemplate(weaponDef)
	local template = findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Tool") then
		return template:Clone()
	end

	local tool = Instance.new("Tool")
	local cloned = template:Clone()

	if template:IsA("Model") then
		cloned.Parent = tool
		local handle = createCenterHandleForModel(cloned, tool)

		if not (handle and handle:IsA("BasePart")) then
			tool:Destroy()
			warn(string.format("Shop item template '%s' could not create centered handle", template.Name))
			return nil
		end

		return tool
	end

	if template:IsA("BasePart") then
		cloned.Name = "Handle"
		cloned.Parent = tool
		return tool
	end

	tool:Destroy()
	warn(string.format("Shop item template '%s' is unsupported type %s", template.Name, template.ClassName))
	return nil
end

local function configureWeaponTool(tool, weaponDef)
	tool.Name = weaponDef.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponDef.Id)
	tool:SetAttribute("Damage", weaponDef.Damage)
	tool:SetAttribute("Range", weaponDef.Range)
	tool:SetAttribute("Cooldown", weaponDef.Cooldown)

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

	local lastActivatedAt = -math.huge
	tool.Activated:Connect(function()
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

		local now = os.clock()
		if now - lastActivatedAt < weaponDef.Cooldown then
			return
		end
		lastActivatedAt = now

		local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
		local lookVector = rootPart.CFrame.LookVector
		local target = findTargetEnemy(character, origin, lookVector, weaponDef.Range)
		if target then
			applyDamageToEnemy(owner, target, weaponDef.Damage)
		end
	end)
end

local function createWeaponTool(weaponDef)
	local tool = createToolFromTemplate(weaponDef)
	if not tool then
		tool = createFallbackWeaponTool(weaponDef)
	end

	configureWeaponTool(tool, weaponDef)

	return tool
end

local function playerOwnsWeapon(player, weaponId)
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
					return true
				end
			end
		end
	end

	return false
end

local function canPurchaseNow()
	if not remotesFolder then
		return true, "Unknown"
	end

	local waveState = remotesFolder:GetAttribute("CurrentWaveState")
	if type(waveState) ~= "string" then
		return true, "Unknown"
	end

	local allowedStates = Config.Shop.PurchaseAllowedStates or {}
	if type(allowedStates[waveState]) == "boolean" then
		return allowedStates[waveState], waveState
	end

	return waveState ~= "InProgress", waveState
end

local function getCatalogForPlayer(player)
	local canPurchase, waveState = canPurchaseNow()
	local weapons = {}

	for _, weaponDef in ipairs(Config.Shop.Weapons or {}) do
		table.insert(weapons, {
			id = weaponDef.Id,
			name = weaponDef.DisplayName,
			cost = weaponDef.Cost,
			damage = weaponDef.Damage,
			range = weaponDef.Range,
			cooldown = weaponDef.Cooldown,
			owned = playerOwnsWeapon(player, weaponDef.Id),
		})
	end

	table.sort(weapons, function(a, b)
		return a.cost < b.cost
	end)

	return {
		success = true,
		canPurchase = canPurchase,
		waveState = waveState,
		weapons = weapons,
	}
end

local function grantWeapon(player, weaponDef)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	local toolForBackpack = createWeaponTool(weaponDef)
	if backpack then
		toolForBackpack.Parent = backpack
	else
		toolForBackpack:Destroy()
	end

	if starterGear then
		local toolForStarterGear = createWeaponTool(weaponDef)
		toolForStarterGear.Parent = starterGear
	end
end

local function buyWeapon(player, weaponId)
	local weaponDef = weaponById[weaponId]
	if not weaponDef then
		return {
			success = false,
			message = "Unknown weapon.",
		}
	end

	local canPurchase = canPurchaseNow()
	if not canPurchase then
		return {
			success = false,
			message = "You can only buy between waves.",
		}
	end

	if playerOwnsWeapon(player, weaponId) then
		return {
			success = false,
			message = "You already own this weapon.",
		}
	end

	local moneyValue = getMoneyValue(player)
	if not moneyValue then
		return {
			success = false,
			message = "Money data not available.",
		}
	end

	if moneyValue.Value < weaponDef.Cost then
		return {
			success = false,
			message = "Not enough money.",
		}
	end

	moneyValue.Value -= weaponDef.Cost
	grantWeapon(player, weaponDef)

	return {
		success = true,
		message = string.format("Bought %s for $%d", weaponDef.DisplayName, weaponDef.Cost),
	}
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

	shopGetCatalogFunction.OnServerInvoke = function(player)
		return getCatalogForPlayer(player)
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

	ensureTraderPrompt()
end

return ShopService
