local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ShopService = require(script.Parent.ShopService)

local AmmoPickupService = {}

local started = false
local randomGenerator = Random.new()
local fallbackTemplate = nil
local activePickupsFolder = nil
local zoneStateByInstance = {}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		warn(string.format("[AmmoPickupService] Expected Folder at %s/%s, got %s", parent:GetFullName(), name, folder.ClassName))
		return nil
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function toWholeNumber(value, defaultValue, minValue)
	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" then
		numberValue = defaultValue
	end
	if type(numberValue) ~= "number" then
		return nil
	end

	numberValue = math.floor(numberValue + 0.5)
	if type(minValue) == "number" then
		numberValue = math.max(minValue, numberValue)
	end
	return numberValue
end

local function toNumber(value, defaultValue, minValue)
	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" then
		numberValue = defaultValue
	end
	if type(numberValue) ~= "number" then
		return nil
	end
	if type(minValue) == "number" then
		numberValue = math.max(minValue, numberValue)
	end
	return numberValue
end

local function normalizeRefillMode(value, fallbackValue)
	local fallbackMode = type(fallbackValue) == "string" and fallbackValue or "ReserveOnly"
	local rawMode = type(value) == "string" and value or fallbackMode
	local mode = string.lower(rawMode)

	if mode == "full" then
		return "Full"
	end
	if mode == "magazineonly" then
		return "MagazineOnly"
	end
	return "ReserveOnly"
end

local function createFallbackTemplate()
	if fallbackTemplate then
		return fallbackTemplate
	end

	local pickup = Instance.new("Part")
	pickup.Name = "AmmoBox"
	pickup.Size = Vector3.new(1.4, 0.8, 1.4)
	pickup.Color = Color3.fromRGB(95, 165, 95)
	pickup.Material = Enum.Material.Metal
	pickup.Anchored = true
	pickup.CanCollide = false
	pickup.CanTouch = true
	pickup.TopSurface = Enum.SurfaceType.Smooth
	pickup.BottomSurface = Enum.SurfaceType.Smooth
	fallbackTemplate = pickup

	return fallbackTemplate
end

local function isPickupTemplate(instance)
	if not instance then
		return false
	end

	return instance:IsA("Model") or instance:IsA("BasePart")
end

local function resolvePickupTemplate(templateFolderName, templateName)
	local templateFolder = ServerStorage:FindFirstChild(templateFolderName)
	if templateFolder then
		local template = templateFolder:FindFirstChild(templateName)
		if isPickupTemplate(template) then
			return template
		end
	end

	warn(string.format(
		"[AmmoPickupService] Missing pickup template ServerStorage/%s/%s. Using fallback box.",
		tostring(templateFolderName),
		tostring(templateName)
	))
	return createFallbackTemplate()
end

local function ensureModelPrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local hitbox = model:FindFirstChild("PickupHitbox", true)
	if hitbox and hitbox:IsA("BasePart") then
		model.PrimaryPart = hitbox
		return hitbox
	end

	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		model.PrimaryPart = firstPart
	end
	return firstPart
end

local function setPickupCFrame(pickup, targetCFrame)
	if pickup:IsA("BasePart") then
		pickup.CFrame = targetCFrame
		return true
	end

	if pickup:IsA("Model") then
		local primaryPart = ensureModelPrimaryPart(pickup)
		if not primaryPart then
			return false
		end
		pickup:PivotTo(targetCFrame)
		return true
	end

	return false
end

local function getPickupTouchPart(pickup)
	if pickup:IsA("BasePart") then
		return pickup
	end
	if pickup:IsA("Model") then
		local explicitHitbox = pickup:FindFirstChild("PickupHitbox", true)
		if explicitHitbox and explicitHitbox:IsA("BasePart") then
			return explicitHitbox
		end
		if pickup.PrimaryPart and pickup.PrimaryPart:IsA("BasePart") then
			return pickup.PrimaryPart
		end
		return pickup:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function configurePickupParts(pickup, touchPart)
	if pickup:IsA("BasePart") then
		pickup.Anchored = true
		pickup.CanCollide = false
		pickup.CanQuery = false
		pickup.CanTouch = true
		return
	end

	for _, descendant in ipairs(pickup:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = descendant == touchPart
		end
	end
end

local function resolvePlayerFromTouchPart(otherPart)
	if not otherPart or not otherPart.Parent then
		return nil
	end

	local character = otherPart.Parent
	if not character:IsA("Model") then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function isPointInsideVolume(pointPart, zoneVolume)
	local localPosition = zoneVolume.CFrame:PointToObjectSpace(pointPart.Position)
	local halfSize = zoneVolume.Size * 0.5
	local tolerance = 0.05

	return math.abs(localPosition.X) <= (halfSize.X + tolerance)
		and math.abs(localPosition.Y) <= (halfSize.Y + tolerance)
		and math.abs(localPosition.Z) <= (halfSize.Z + tolerance)
end

local function resolveZoneVolume(zoneRoot, zoneVolumeName)
	if zoneRoot:IsA("BasePart") then
		return zoneRoot
	end

	local explicit = zoneRoot:FindFirstChild(zoneVolumeName)
	if explicit and explicit:IsA("BasePart") then
		return explicit
	end

	return nil
end

local function collectSpawnPoints(zoneRoot, spawnPointsFolderName)
	local points = {}
	local pointsFolder = zoneRoot:FindFirstChild(spawnPointsFolderName)
	if not pointsFolder then
		return points
	end

	for _, descendant in ipairs(pointsFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(points, descendant)
		end
	end

	return points
end

local function countLivePickups(zoneState)
	local count = 0
	for pointPart, pickupInfo in pairs(zoneState.activeByPoint) do
		if
			type(pickupInfo) == "table"
			and pickupInfo.pickup
			and pickupInfo.pickup.Parent
			and pointPart
			and pointPart.Parent
		then
			count += 1
		else
			zoneState.activeByPoint[pointPart] = nil
		end
	end
	return count
end

local function getAvailablePoints(zoneState)
	local availablePoints = {}
	for _, pointPart in ipairs(zoneState.points) do
		if pointPart.Parent and not zoneState.activeByPoint[pointPart] and not zoneState.pendingRespawnByPoint[pointPart] then
			table.insert(availablePoints, pointPart)
		end
	end
	return availablePoints
end

local scheduleRespawnForPoint
local maintainZonePopulation

local function spawnPickupAtPoint(zoneState, pointPart)
	if not (zoneState and pointPart and pointPart.Parent) then
		return false
	end

	local template = zoneState.pickupTemplate
	if not isPickupTemplate(template) then
		template = createFallbackTemplate()
	end

	local pickup = template:Clone()
	pickup.Name = "AmmoBox"
	pickup:SetAttribute("AmmoZone", zoneState.name)
	pickup:SetAttribute("SpawnPoint", pointPart.Name)
	pickup.Parent = activePickupsFolder

	local targetCFrame = pointPart.CFrame + Vector3.new(0, zoneState.pickupYOffset, 0)
	if not setPickupCFrame(pickup, targetCFrame) then
		warn(string.format("[AmmoPickupService] Could not place pickup at %s", pointPart:GetFullName()))
		pickup:Destroy()
		return false
	end

	local touchPart = getPickupTouchPart(pickup)
	if not touchPart then
		warn(string.format("[AmmoPickupService] Pickup template has no BasePart: zone %s", zoneState.name))
		pickup:Destroy()
		return false
	end

	configurePickupParts(pickup, touchPart)

	local consumed = false
	local touchConnection = nil

	local function destroyAndRespawn()
		if consumed then
			return
		end
		consumed = true
		scheduleRespawnForPoint(zoneState, pointPart)
		if pickup and pickup.Parent then
			pickup:Destroy()
		end
	end

	touchConnection = touchPart.Touched:Connect(function(otherPart)
		if consumed then
			return
		end

		local player = resolvePlayerFromTouchPart(otherPart)
		if not player then
			return
		end

		local now = os.clock()
		local lastPickupAt = zoneState.lastPickupByUserId[player.UserId]
		if type(lastPickupAt) == "number" and now - lastPickupAt < zoneState.playerPickupCooldownSeconds then
			return
		end

		local didRefill = ShopService.refillPlayerAmmo(player, {
			mode = zoneState.refillMode,
			reserveAmount = zoneState.reserveAmmoPerPickup,
		})
		if not didRefill then
			return
		end

		zoneState.lastPickupByUserId[player.UserId] = now
		destroyAndRespawn()
	end)

	pickup.Destroying:Connect(function()
		local pickupInfo = zoneState.activeByPoint[pointPart]
		if pickupInfo and pickupInfo.pickup == pickup then
			zoneState.activeByPoint[pointPart] = nil
			if pickupInfo.touchConnection then
				pickupInfo.touchConnection:Disconnect()
				pickupInfo.touchConnection = nil
			end
			if not zoneState.pendingRespawnByPoint[pointPart] then
				scheduleRespawnForPoint(zoneState, pointPart)
			end
		elseif touchConnection then
			touchConnection:Disconnect()
			touchConnection = nil
		end
	end)

	zoneState.activeByPoint[pointPart] = {
		pickup = pickup,
		touchConnection = touchConnection,
	}

	return true
end

scheduleRespawnForPoint = function(zoneState, pointPart)
	if zoneState.pendingRespawnByPoint[pointPart] then
		return
	end

	zoneState.pendingRespawnByPoint[pointPart] = true
	task.delay(zoneState.respawnSeconds, function()
		zoneState.pendingRespawnByPoint[pointPart] = nil
		if not started then
			return
		end
		if not zoneStateByInstance[zoneState.instance] then
			return
		end
		maintainZonePopulation(zoneState)
	end)
end

maintainZonePopulation = function(zoneState)
	local targetCount = math.min(zoneState.maxBoxes, #zoneState.points)
	if targetCount <= 0 then
		return
	end

	local spawnAttempts = 0
	while countLivePickups(zoneState) < targetCount do
		local availablePoints = getAvailablePoints(zoneState)
		if #availablePoints <= 0 then
			break
		end

		spawnAttempts += 1
		if spawnAttempts > (#zoneState.points * 2) then
			break
		end

		local randomIndex = randomGenerator:NextInteger(1, #availablePoints)
		local pointPart = availablePoints[randomIndex]
		if not spawnPickupAtPoint(zoneState, pointPart) then
			scheduleRespawnForPoint(zoneState, pointPart)
		end
	end
end

local function createZoneState(zoneRoot, ammoConfig)
	local zoneVolume = resolveZoneVolume(zoneRoot, ammoConfig.ZoneVolumeName)
	if not zoneVolume then
		warn(string.format(
			"[AmmoPickupService] Zone '%s' is missing volume part '%s'.",
			zoneRoot.Name,
			tostring(ammoConfig.ZoneVolumeName)
		))
		return nil
	end

	local rawPoints = collectSpawnPoints(zoneRoot, ammoConfig.SpawnPointsFolderName)
	if #rawPoints <= 0 then
		warn(string.format(
			"[AmmoPickupService] Zone '%s' has no spawn points in '%s'.",
			zoneRoot.Name,
			tostring(ammoConfig.SpawnPointsFolderName)
		))
		return nil
	end

	local validPoints = {}
	for _, pointPart in ipairs(rawPoints) do
		if isPointInsideVolume(pointPart, zoneVolume) then
			table.insert(validPoints, pointPart)
		else
			warn(string.format(
				"[AmmoPickupService] Ignoring point '%s' because it is outside zone volume '%s'.",
				pointPart:GetFullName(),
				zoneVolume:GetFullName()
			))
		end
	end

	if #validPoints <= 0 then
		warn(string.format("[AmmoPickupService] Zone '%s' has no valid in-volume spawn points.", zoneRoot.Name))
		return nil
	end

	local maxBoxes = toWholeNumber(zoneRoot:GetAttribute("MaxBoxes"), ammoConfig.DefaultMaxBoxes, 1) or 1
	maxBoxes = math.clamp(maxBoxes, 1, #validPoints)

	local respawnSeconds = toNumber(zoneRoot:GetAttribute("RespawnSeconds"), ammoConfig.DefaultRespawnSeconds, 0.1)
		or ammoConfig.DefaultRespawnSeconds
	local refillMode = normalizeRefillMode(zoneRoot:GetAttribute("RefillMode"), ammoConfig.DefaultRefillMode)

	local reserveAmmoPerPickup = toWholeNumber(
		zoneRoot:GetAttribute("ReserveAmmoPerPickup"),
		ammoConfig.DefaultReserveAmmoPerPickup,
		0
	)
	if type(reserveAmmoPerPickup) == "number" and reserveAmmoPerPickup <= 0 then
		reserveAmmoPerPickup = nil
	end

	local pickupYOffset = toNumber(zoneRoot:GetAttribute("PickupYOffset"), ammoConfig.DefaultPickupYOffset, 0)
		or ammoConfig.DefaultPickupYOffset
	local playerPickupCooldownSeconds = toNumber(
		zoneRoot:GetAttribute("PlayerPickupCooldownSeconds"),
		ammoConfig.DefaultPlayerPickupCooldownSeconds,
		0
	) or ammoConfig.DefaultPlayerPickupCooldownSeconds

	local templateFolderName = zoneRoot:GetAttribute("TemplateFolderName")
	if type(templateFolderName) ~= "string" or templateFolderName == "" then
		templateFolderName = ammoConfig.TemplateFolderName
	end

	local templateName = zoneRoot:GetAttribute("TemplateName")
	if type(templateName) ~= "string" or templateName == "" then
		templateName = ammoConfig.TemplateName
	end

	local pickupTemplate = resolvePickupTemplate(templateFolderName, templateName)

	return {
		instance = zoneRoot,
		name = zoneRoot.Name,
		volume = zoneVolume,
		points = validPoints,
		maxBoxes = maxBoxes,
		respawnSeconds = respawnSeconds,
		refillMode = refillMode,
		reserveAmmoPerPickup = reserveAmmoPerPickup,
		pickupYOffset = pickupYOffset,
		playerPickupCooldownSeconds = playerPickupCooldownSeconds,
		pickupTemplate = pickupTemplate,
		activeByPoint = {},
		pendingRespawnByPoint = {},
		lastPickupByUserId = {},
	}
end

function AmmoPickupService.start()
	if started then
		return
	end
	started = true

	local ammoConfig = Config.AmmoPickup or {}
	ammoConfig.ZoneFolderName = tostring(ammoConfig.ZoneFolderName or "AmmoZones")
	ammoConfig.ZoneVolumeName = tostring(ammoConfig.ZoneVolumeName or "Zone")
	ammoConfig.SpawnPointsFolderName = tostring(ammoConfig.SpawnPointsFolderName or "SpawnPoints")
	ammoConfig.ActivePickupsFolderName = tostring(ammoConfig.ActivePickupsFolderName or "AmmoPickups")
	ammoConfig.TemplateFolderName = tostring(ammoConfig.TemplateFolderName or "Pickups")
	ammoConfig.TemplateName = tostring(ammoConfig.TemplateName or "AmmoBox")
	ammoConfig.DefaultMaxBoxes = toWholeNumber(ammoConfig.DefaultMaxBoxes, 2, 1) or 2
	ammoConfig.DefaultRespawnSeconds = toNumber(ammoConfig.DefaultRespawnSeconds, 18, 0.1) or 18
	ammoConfig.DefaultRefillMode = normalizeRefillMode(ammoConfig.DefaultRefillMode, "ReserveOnly")
	ammoConfig.DefaultReserveAmmoPerPickup = toWholeNumber(ammoConfig.DefaultReserveAmmoPerPickup, 60, 0) or 60
	ammoConfig.DefaultPickupYOffset = toNumber(ammoConfig.DefaultPickupYOffset, 0.6, 0) or 0.6
	ammoConfig.DefaultPlayerPickupCooldownSeconds =
		toNumber(ammoConfig.DefaultPlayerPickupCooldownSeconds, 0.35, 0) or 0.35

	activePickupsFolder = ensureFolder(Workspace, ammoConfig.ActivePickupsFolderName)
	if not activePickupsFolder then
		warn("[AmmoPickupService] Could not create pickup output folder.")
		return
	end

	local zoneFolder = Workspace:FindFirstChild(ammoConfig.ZoneFolderName)
	if not zoneFolder then
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = ammoConfig.ZoneFolderName
		zoneFolder.Parent = Workspace
		warn(string.format(
			"[AmmoPickupService] Created empty Workspace/%s. Add zones with '%s' part and '%s' folder.",
			ammoConfig.ZoneFolderName,
			ammoConfig.ZoneVolumeName,
			ammoConfig.SpawnPointsFolderName
		))
	end

	if not zoneFolder:IsA("Folder") then
		warn(string.format(
			"[AmmoPickupService] Workspace/%s must be a Folder, found %s.",
			ammoConfig.ZoneFolderName,
			zoneFolder.ClassName
		))
		return
	end

	for _, zoneRoot in ipairs(zoneFolder:GetChildren()) do
		if zoneRoot:IsA("Folder") or zoneRoot:IsA("Model") or zoneRoot:IsA("BasePart") then
			local zoneState = createZoneState(zoneRoot, ammoConfig)
			if zoneState then
				zoneStateByInstance[zoneRoot] = zoneState
				maintainZonePopulation(zoneState)
			end
		end
	end

	if next(zoneStateByInstance) == nil then
		warn("[AmmoPickupService] No valid ammo zones found. Check Workspace/AmmoZones setup.")
	end
end

return AmmoPickupService
