--[[
	SentryRuntime — Registry and lifecycle for sentry turrets.
	Owns the Workspace sentry folder, player→records index, death cleanup, ammo sync, and destroy VFX.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)
local SentryStatResolver = require(script.Parent.Parent.Stats.SentryStatResolver)

local SentryRuntime = {}

local DEFAULT_FOLDER_NAME = "SentryTurrets"
local DEFAULT_MAX_AMMO = 300

function SentryRuntime.new(options)
	local opts = options or {}
	local modelRootResolver = opts.modelRootResolver
	local createExplosionEffect = opts.createExplosionEffect
	local createMuzzleFlash = opts.createMuzzleFlash
	local createTracerSegment = opts.createTracerSegment
	local createFlamePuff = opts.createFlamePuff
	local randomGenerator = opts.randomGenerator or Random.new()
	local sentryTurretFolderName = tostring(opts.sentryTurretFolderName or DEFAULT_FOLDER_NAME)
	local defaultSentryMaxAmmo = math.max(1, math.floor((tonumber(opts.defaultSentryMaxAmmo) or DEFAULT_MAX_AMMO) + 0.5))

	if type(modelRootResolver) ~= "table" then
		error("SentryRuntime.new requires options.modelRootResolver", 2)
	end
	if type(createExplosionEffect) ~= "function" then
		error("SentryRuntime.new requires options.createExplosionEffect", 2)
	end
	if type(createMuzzleFlash) ~= "function" then
		error("SentryRuntime.new requires options.createMuzzleFlash", 2)
	end
	if type(createTracerSegment) ~= "function" then
		error("SentryRuntime.new requires options.createTracerSegment", 2)
	end
	if type(createFlamePuff) ~= "function" then
		error("SentryRuntime.new requires options.createFlamePuff", 2)
	end

	local sentryTurretFolder = nil
	local sentryTurretsByPlayer = {}
	local sentryRecordByModel = setmetatable({}, { __mode = "k" })
	local sentryCharacterConnectionByPlayer = {}
	local sentryCharacterDeathConnectionByPlayer = {}

	local function getSentryTurretFolder()
		if sentryTurretFolder and sentryTurretFolder.Parent == Workspace then
			return sentryTurretFolder
		end

		sentryTurretFolder = Workspace:FindFirstChild(sentryTurretFolderName)
		if sentryTurretFolder and sentryTurretFolder:IsA("Folder") then
			return sentryTurretFolder
		end

		if sentryTurretFolder then
			sentryTurretFolder:Destroy()
		end

		sentryTurretFolder = Instance.new("Folder")
		sentryTurretFolder.Name = sentryTurretFolderName
		sentryTurretFolder.Parent = Workspace
		return sentryTurretFolder
	end

	local function disconnectConnections(connections)
		if type(connections) ~= "table" then
			return
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local function removeRecord(model)
		local record = sentryRecordByModel[model]
		if not record then
			return
		end

		sentryRecordByModel[model] = nil
		disconnectConnections(record.connections)

		local owner = record.owner
		local records = owner and sentryTurretsByPlayer[owner]
		if records then
			for index = #records, 1, -1 do
				if records[index] == model then
					table.remove(records, index)
				end
			end
			if #records == 0 then
				sentryTurretsByPlayer[owner] = nil
			end
		end
	end

	local function playSentryDestroyedEffect(model)
		if not (model and model:IsA("Model")) then
			return
		end

		local root = modelRootResolver.resolveRootPart(model)
		local position = root and root.Position or model:GetPivot().Position
		createExplosionEffect(position, 4.25)
		createMuzzleFlash(position, Color3.fromRGB(255, 205, 120), 2.6, 0.14)
		createMuzzleFlash(position, Color3.fromRGB(255, 130, 85), 1.9, 0.18)

		for _ = 1, 8 do
			local direction = Vector3.new(
				randomGenerator:NextNumber(-1, 1),
				randomGenerator:NextNumber(0.15, 1),
				randomGenerator:NextNumber(-1, 1)
			)
			if direction.Magnitude > 0.01 then
				direction = direction.Unit
				local endPosition = position + direction * randomGenerator:NextNumber(2.5, 6)
				createTracerSegment(position, endPosition, Color3.fromRGB(255, 170, 90), 0.16, 0.08)
				createFlamePuff(endPosition, randomGenerator:NextNumber(0.3, 0.65), randomGenerator:NextNumber(0.08, 0.16))
			end
		end

		task.delay(0.06, function()
			createExplosionEffect(position, 3.2)
			createMuzzleFlash(position, Color3.fromRGB(255, 175, 95), 1.7, 0.1)
		end)

		task.delay(0.13, function()
			createExplosionEffect(position, 2.25)
		end)
	end

	local clearPlayerSentries

	local function disconnectPlayerSentryDeathBindings(player)
		local characterConnection = sentryCharacterConnectionByPlayer[player]
		if characterConnection then
			characterConnection:Disconnect()
			sentryCharacterConnectionByPlayer[player] = nil
		end

		local deathConnection = sentryCharacterDeathConnectionByPlayer[player]
		if deathConnection then
			deathConnection:Disconnect()
			sentryCharacterDeathConnectionByPlayer[player] = nil
		end
	end

	local function bindPlayerSentryDeathCleanup(player)
		disconnectPlayerSentryDeathBindings(player)

		local function bindCharacter(character)
			local existingDeathConnection = sentryCharacterDeathConnectionByPlayer[player]
			if existingDeathConnection then
				existingDeathConnection:Disconnect()
				sentryCharacterDeathConnectionByPlayer[player] = nil
			end

			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid and character then
				local awaited = character:WaitForChild("Humanoid", 5)
				if awaited and awaited:IsA("Humanoid") then
					humanoid = awaited
				end
			end
			if not humanoid then
				return
			end

			sentryCharacterDeathConnectionByPlayer[player] = humanoid.Died:Connect(function()
				clearPlayerSentries(player, {
					playDestroyEffect = true,
				})
			end)
		end

		sentryCharacterConnectionByPlayer[player] = player.CharacterAdded:Connect(function(character)
			task.defer(function()
				bindCharacter(character)
			end)
		end)

		if player.Character then
			task.defer(function()
				bindCharacter(player.Character)
			end)
		end
	end

	clearPlayerSentries = function(player, clearOptions)
		local playDestroyEffect = type(clearOptions) == "table" and clearOptions.playDestroyEffect == true
		local records = sentryTurretsByPlayer[player]
		if not records then
			return
		end

		local copy = table.clone(records)
		sentryTurretsByPlayer[player] = nil
		for _, model in ipairs(copy) do
			if playDestroyEffect and model and model.Parent then
				playSentryDestroyedEffect(model)
			end
			removeRecord(model)
			if model and model.Parent then
				model:Destroy()
			end
		end
	end

	local function prunePlayerSentries(player)
		local records = sentryTurretsByPlayer[player]
		if not records then
			return 0
		end

		for index = #records, 1, -1 do
			local model = records[index]
			local record = model and sentryRecordByModel[model]
			if not model or not record then
				table.remove(records, index)
			elseif not model.Parent or not record.humanoid or record.humanoid.Health <= 0 then
				removeRecord(model)
			end
		end

		if #records == 0 then
			sentryTurretsByPlayer[player] = nil
			return 0
		end
		return #records
	end

	local function countPlayerSentriesByKind(player, kindId)
		local records = sentryTurretsByPlayer[player]
		if not records or #records == 0 then
			return 0
		end

		local normalizedKindId = tostring(kindId or "")
		if normalizedKindId == "" then
			return 0
		end

		local count = 0
		for _, model in ipairs(records) do
			local record = sentryRecordByModel[model]
			if record and record.kindId == normalizedKindId and model and model.Parent and record.humanoid and record.humanoid.Health > 0 then
				count += 1
			end
		end
		return count
	end

	local function resolveTurretMaxAmmo(weaponDef)
		return SentryStatResolver.resolveTurretMaxAmmo(weaponDef, defaultSentryMaxAmmo)
	end

	local function resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)
		return SentryStatResolver.resolveTurretInitialAmmo(weaponDef, turretMaxAmmo)
	end

	local function syncSentryAmmoAttributes(record)
		if type(record) ~= "table" then
			return
		end

		local ammo, maxAmmo = SentryStatResolver.resolveAmmoState(record.ammo, record.maxAmmo, 1)
		record.maxAmmo = maxAmmo
		record.ammo = ammo

		local model = record.model
		if model and model:IsA("Model") then
			model:SetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO, maxAmmo)
			model:SetAttribute(SentryConstants.ATTR_TURRET_AMMO, ammo)
			model:SetAttribute(SentryConstants.ATTR_TURRET_OUT_OF_AMMO, ammo <= 0)
		end

		local ammoLabel = record.ammoLabel
		if not (ammoLabel and ammoLabel.Parent) then
			local billboard = model and model:FindFirstChild(SentryConstants.TURRET_BILLBOARD_NAME)
			if billboard and billboard:IsA("BillboardGui") then
				local resolvedLabel = billboard:FindFirstChild(SentryConstants.TURRET_AMMO_LABEL_NAME)
				if resolvedLabel and resolvedLabel:IsA("TextLabel") then
					ammoLabel = resolvedLabel
					record.ammoLabel = ammoLabel
				end
			end
		end

		if ammoLabel and ammoLabel:IsA("TextLabel") then
			ammoLabel.Text = string.format("Ammo %d/%d", ammo, maxAmmo)
			ammoLabel.TextColor3 = if ammo > 0 then Color3.fromRGB(195, 220, 255) else Color3.fromRGB(245, 125, 125)
		end
	end

	local function collectOwnedSentryRecordsByWeaponId(player)
		local recordsByWeaponId = {}
		local records = sentryTurretsByPlayer[player]
		if not records or #records == 0 then
			return recordsByWeaponId
		end

		for _, model in ipairs(records) do
			local record = model and sentryRecordByModel[model]
			local weaponId = if record and type(record.kindId) == "string" then record.kindId else nil
			if weaponId and weaponId ~= "" and model and model.Parent and record.humanoid and record.humanoid.Health > 0 then
				local weaponRecords = recordsByWeaponId[weaponId]
				if not weaponRecords then
					weaponRecords = {}
					recordsByWeaponId[weaponId] = weaponRecords
				end
				table.insert(weaponRecords, record)
			end
		end

		return recordsByWeaponId
	end

	local function playerOwnsWeaponId(player, weaponId)
		local normalizedWeaponId = tostring(weaponId or "")
		if normalizedWeaponId == "" then
			return false
		end
		local records = sentryTurretsByPlayer[player]
		if not records then
			return false
		end
		for _, model in ipairs(records) do
			local record = model and sentryRecordByModel[model]
			if record and record.kindId == normalizedWeaponId and model and model.Parent and record.humanoid and record.humanoid.Health > 0 then
				return true
			end
		end
		return false
	end

	local function registerRecord(player, model, record)
		sentryRecordByModel[model] = record
		local records = sentryTurretsByPlayer[player]
		if not records then
			records = {}
			sentryTurretsByPlayer[player] = records
		end
		table.insert(records, model)
	end

	local function getRecord(model)
		return sentryRecordByModel[model]
	end

	local function getPlayerSentryModels(player)
		return sentryTurretsByPlayer[player]
	end

	local function refillAmmoForSentryRecords(sentryRecords, weaponDef)
		if type(sentryRecords) ~= "table" then
			return false
		end
		local didRefill = false
		local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)
		for _, record in ipairs(sentryRecords) do
			if record and record.model and record.model.Parent and record.humanoid and record.humanoid.Health > 0 then
				local ammoBefore, turretMaxAmmo = SentryStatResolver.resolveAmmoStateFromCandidates(
					{ record.maxAmmo, record.model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO), fallbackMaxAmmo },
					{ record.ammo, record.model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO) },
					fallbackMaxAmmo
				)
				record.maxAmmo = turretMaxAmmo
				record.ammo = turretMaxAmmo
				syncSentryAmmoAttributes(record)
				if ammoBefore < turretMaxAmmo then
					didRefill = true
				end
			end
		end
		return didRefill
	end

	local function getSentryAmmoSnapshot(sentryRecords, weaponDef)
		if type(sentryRecords) ~= "table" or #sentryRecords == 0 then
			return nil
		end
		local totalCurrentAmmo = 0
		local totalMaxAmmo = 0
		local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)
		for _, record in ipairs(sentryRecords) do
			if type(record) == "table" and record.humanoid and record.humanoid.Health > 0 then
				local model = record.model
				local modelMaxAmmo = if model and model:IsA("Model") then model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO) else nil
				local modelAmmo = if model and model:IsA("Model") then model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO) else nil
				local turretAmmo, turretMaxAmmo = SentryStatResolver.resolveAmmoStateFromCandidates(
					{ record.maxAmmo, modelMaxAmmo, fallbackMaxAmmo },
					{ record.ammo, modelAmmo },
					fallbackMaxAmmo
				)
				record.maxAmmo = turretMaxAmmo
				record.ammo = turretAmmo
				syncSentryAmmoAttributes(record)
				totalCurrentAmmo += turretAmmo
				totalMaxAmmo += turretMaxAmmo
			end
		end
		local missingAmmo = math.max(0, totalMaxAmmo - totalCurrentAmmo)
		return {
			currentTotalAmmo = totalCurrentAmmo,
			maxTotalAmmo = totalMaxAmmo,
			missingAmmo = missingAmmo,
		}
	end

	return {
		getSentryTurretFolder = getSentryTurretFolder,
		removeRecord = removeRecord,
		registerRecord = registerRecord,
		getRecord = getRecord,
		getPlayerSentryModels = getPlayerSentryModels,
		clearPlayerSentries = clearPlayerSentries,
		disconnectPlayerSentryDeathBindings = disconnectPlayerSentryDeathBindings,
		bindPlayerSentryDeathCleanup = bindPlayerSentryDeathCleanup,
		prunePlayerSentries = prunePlayerSentries,
		countPlayerSentriesByKind = countPlayerSentriesByKind,
		resolveTurretMaxAmmo = resolveTurretMaxAmmo,
		resolveTurretInitialAmmo = resolveTurretInitialAmmo,
		syncSentryAmmoAttributes = syncSentryAmmoAttributes,
		collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
		playerOwnsWeaponId = playerOwnsWeaponId,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
		getSentryAmmoSnapshot = getSentryAmmoSnapshot,
	}
end

return SentryRuntime
