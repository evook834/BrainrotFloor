local Workspace = game:GetService("Workspace")

local AmmoZoneLayoutGenerator = {}

local GENERATED_BY = "AmmoZoneLayoutGeneratorV1"
-- Studio Command Bar:
-- require(game.ServerScriptService.Match.Tools.AmmoZoneLayoutGenerator).createDefaults()

local DEFAULT_LAYOUTS = {
	{
		name = "AmmoZone_Default_Small",
		center = Vector3.new(0, 6, 0),
		size = Vector3.new(18, 6, 18),
		pointPattern = "grid",
		gridRows = 2,
		gridColumns = 2,
		pointInset = 2.5,
		maxBoxes = 2,
		respawnSeconds = 14,
		refillMode = "ReserveOnly",
		reserveAmmoPerPickup = 60,
	},
	{
		name = "AmmoZone_Default_Corridor",
		center = Vector3.new(32, 6, 0),
		size = Vector3.new(32, 6, 12),
		pointPattern = "line",
		lineAxis = "X",
		lineCount = 6,
		pointInset = 3,
		maxBoxes = 3,
		respawnSeconds = 16,
		refillMode = "ReserveOnly",
		reserveAmmoPerPickup = 80,
	},
	{
		name = "AmmoZone_Default_Arena",
		center = Vector3.new(-32, 6, 0),
		size = Vector3.new(30, 6, 30),
		pointPattern = "ring",
		ringCount = 8,
		pointInset = 3,
		maxBoxes = 4,
		respawnSeconds = 20,
		refillMode = "ReserveOnly",
		reserveAmmoPerPickup = 100,
	},
}

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		if folder:IsA("Folder") then
			return folder
		end

		error(string.format("Expected Folder at %s/%s but found %s", parent:GetFullName(), name, folder.ClassName))
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function clearIfNeeded(parent, name, replaceExisting)
	local existing = parent:FindFirstChild(name)
	if not existing then
		return nil
	end

	if replaceExisting then
		existing:Destroy()
		return nil
	end

	return existing
end

local function createSpawnPoint(spawnPointsFolder, index, worldPosition)
	local pointPart = Instance.new("Part")
	pointPart.Name = string.format("Point_%02d", index)
	pointPart.Size = Vector3.new(0.8, 0.8, 0.8)
	pointPart.Anchored = true
	pointPart.CanCollide = false
	pointPart.CanTouch = false
	pointPart.CanQuery = false
	pointPart.Transparency = 1
	pointPart.CFrame = CFrame.new(worldPosition)
	pointPart.Parent = spawnPointsFolder
	return pointPart
end

local function buildGridPoints(center, size, rows, columns, inset)
	local points = {}
	local xMin = center.X - (size.X * 0.5) + inset
	local xMax = center.X + (size.X * 0.5) - inset
	local zMin = center.Z - (size.Z * 0.5) + inset
	local zMax = center.Z + (size.Z * 0.5) - inset

	local safeRows = math.max(1, math.floor(rows + 0.5))
	local safeColumns = math.max(1, math.floor(columns + 0.5))

	for row = 1, safeRows do
		local zAlpha = 0.5
		if safeRows > 1 then
			zAlpha = (row - 1) / (safeRows - 1)
		end
		local z = zMin + ((zMax - zMin) * zAlpha)
		for column = 1, safeColumns do
			local xAlpha = 0.5
			if safeColumns > 1 then
				xAlpha = (column - 1) / (safeColumns - 1)
			end
			local x = xMin + ((xMax - xMin) * xAlpha)
			table.insert(points, Vector3.new(x, center.Y, z))
		end
	end

	return points
end

local function buildLinePoints(center, size, count, inset, axis)
	local points = {}
	local safeCount = math.max(1, math.floor(count + 0.5))
	local normalizedAxis = string.upper(tostring(axis or "X"))

	for i = 1, safeCount do
		local alpha = 0.5
		if safeCount > 1 then
			alpha = (i - 1) / (safeCount - 1)
		end
		if normalizedAxis == "Z" then
			local zMin = center.Z - (size.Z * 0.5) + inset
			local zMax = center.Z + (size.Z * 0.5) - inset
			local z = zMin + ((zMax - zMin) * alpha)
			table.insert(points, Vector3.new(center.X, center.Y, z))
		else
			local xMin = center.X - (size.X * 0.5) + inset
			local xMax = center.X + (size.X * 0.5) - inset
			local x = xMin + ((xMax - xMin) * alpha)
			table.insert(points, Vector3.new(x, center.Y, center.Z))
		end
	end

	return points
end

local function buildRingPoints(center, size, count, inset)
	local points = {}
	local safeCount = math.max(3, math.floor(count + 0.5))
	local maxRadius = math.max(1, (math.min(size.X, size.Z) * 0.5) - inset)

	for i = 1, safeCount do
		local theta = ((i - 1) / safeCount) * (math.pi * 2)
		local x = center.X + (math.cos(theta) * maxRadius)
		local z = center.Z + (math.sin(theta) * maxRadius)
		table.insert(points, Vector3.new(x, center.Y, z))
	end

	return points
end

local function createZoneLayout(ammoZonesFolder, layout, replaceExisting)
	local zoneName = tostring(layout.name or "AmmoZone")
	local existing = clearIfNeeded(ammoZonesFolder, zoneName, replaceExisting)
	if existing then
		return false, 0
	end

	local center = layout.center or Vector3.new(0, 6, 0)
	local size = layout.size or Vector3.new(16, 6, 16)
	local pointInset = tonumber(layout.pointInset) or 2

	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = zoneName
	zoneFolder.Parent = ammoZonesFolder
	zoneFolder:SetAttribute("GeneratedBy", GENERATED_BY)
	zoneFolder:SetAttribute("MaxBoxes", math.max(1, math.floor((tonumber(layout.maxBoxes) or 2) + 0.5)))
	zoneFolder:SetAttribute("RespawnSeconds", tonumber(layout.respawnSeconds) or 16)
	zoneFolder:SetAttribute("RefillMode", tostring(layout.refillMode or "ReserveOnly"))
	zoneFolder:SetAttribute("ReserveAmmoPerPickup", math.max(1, math.floor((tonumber(layout.reserveAmmoPerPickup) or 60) + 0.5)))

	local zonePart = Instance.new("Part")
	zonePart.Name = "Zone"
	zonePart.Size = size
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CanTouch = false
	zonePart.CanQuery = false
	zonePart.Transparency = 1
	zonePart.CFrame = CFrame.new(center)
	zonePart.Parent = zoneFolder

	local spawnPointsFolder = Instance.new("Folder")
	spawnPointsFolder.Name = "SpawnPoints"
	spawnPointsFolder.Parent = zoneFolder

	local pattern = string.lower(tostring(layout.pointPattern or "grid"))
	local points
	if pattern == "line" then
		points = buildLinePoints(center, size, tonumber(layout.lineCount) or 5, pointInset, layout.lineAxis)
	elseif pattern == "ring" then
		points = buildRingPoints(center, size, tonumber(layout.ringCount) or 8, pointInset)
	else
		points = buildGridPoints(center, size, tonumber(layout.gridRows) or 2, tonumber(layout.gridColumns) or 2, pointInset)
	end

	for index, pointPosition in ipairs(points) do
		createSpawnPoint(spawnPointsFolder, index, pointPosition)
	end

	return true, #points
end

function AmmoZoneLayoutGenerator.createLayouts(layouts, options)
	local replaceExisting = true
	if type(options) == "table" and options.replaceExisting == false then
		replaceExisting = false
	end

	local ammoZonesFolder = ensureFolder(Workspace, "AmmoZones")
	local summary = {
		createdZones = 0,
		skippedZones = 0,
		createdPoints = 0,
	}

	for _, layout in ipairs(layouts) do
		local created, pointCount = createZoneLayout(ammoZonesFolder, layout, replaceExisting)
		if created then
			summary.createdZones = summary.createdZones + 1
			summary.createdPoints = summary.createdPoints + pointCount
		else
			summary.skippedZones = summary.skippedZones + 1
		end
	end

	print(string.format(
		"[AmmoZoneLayoutGenerator] Created %d zone(s), skipped %d, created %d spawn point(s).",
		summary.createdZones,
		summary.skippedZones,
		summary.createdPoints
	))

	return summary
end

function AmmoZoneLayoutGenerator.createDefaults(options)
	return AmmoZoneLayoutGenerator.createLayouts(DEFAULT_LAYOUTS, options)
end

return AmmoZoneLayoutGenerator
