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

	local function ensurePlayerModelIndex(player, model)
		if not (player and player:IsA("Player")) then
			return
		end
		if not (model and model:IsA("Model")) then
			return
		end

		local records = sentryTurretsByPlayer[player]
		if not records then
			records = {}
			sentryTurretsByPlayer[player] = records
		end

		for _, existingModel in ipairs(records) do
			if existingModel == model then
				return
			end
		end

		table.insert(records, model)
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

	local syncSentryAmmoAttributes

	local function resolveRecordAmmoState(record, fallbackMaxAmmo)
		if type(record) ~= "table" then
			return 0, math.max(1, math.floor((tonumber(fallbackMaxAmmo) or 1) + 0.5))
		end

		local model = record.model
		local ammoLabel = record.ammoLabel
		local labelAmmo = nil
		local labelMaxAmmo = nil
		if not (ammoLabel and ammoLabel:IsA("TextLabel") and ammoLabel.Parent) then
			local billboard = model and model:IsA("Model") and model:FindFirstChild(SentryConstants.TURRET_BILLBOARD_NAME) or nil
			local resolvedLabel = billboard and billboard:IsA("BillboardGui")
					and billboard:FindFirstChild(SentryConstants.TURRET_AMMO_LABEL_NAME)
				or nil
			if resolvedLabel and resolvedLabel:IsA("TextLabel") then
				ammoLabel = resolvedLabel
				record.ammoLabel = ammoLabel
			end
		end
		if ammoLabel and ammoLabel:IsA("TextLabel") then
			local parsedAmmo, parsedMaxAmmo = string.match(ammoLabel.Text or "", "Ammo%s+(%d+)%s*/%s*(%d+)")
			labelAmmo = tonumber(parsedAmmo)
			labelMaxAmmo = tonumber(parsedMaxAmmo)
		end

		local modelMaxAmmo = nil
		local modelAmmo = nil
		if model and model:IsA("Model") then
			modelMaxAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO)
			modelAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO)
		end

		local maxAmmo = math.max(1, math.floor((tonumber(fallbackMaxAmmo) or 1) + 0.5))
		for _, candidate in ipairs({ labelMaxAmmo, modelMaxAmmo, record.maxAmmo }) do
			local candidateNumber = tonumber(candidate)
			if type(candidateNumber) == "number" then
				maxAmmo = math.max(maxAmmo, math.floor(candidateNumber + 0.5))
			end
		end

		local ammo = nil
		for _, candidate in ipairs({ labelAmmo, modelAmmo, record.ammo }) do
			local candidateNumber = tonumber(candidate)
			if type(candidateNumber) == "number" then
				local clampedAmmo = math.clamp(math.floor(candidateNumber + 0.5), 0, maxAmmo)
				if ammo == nil or clampedAmmo < ammo then
					ammo = clampedAmmo
				end
			end
		end
		if ammo == nil then
			ammo = maxAmmo
		end

		record.maxAmmo = maxAmmo
		record.ammo = ammo
		return ammo, maxAmmo
	end

	local function hydrateLiveOwnedSentryRecord(player, model)
		if not (player and player:IsA("Player")) then
			return nil, nil
		end
		if not (model and model:IsA("Model") and model.Parent) then
			return nil, nil
		end

		local ownerUserId = tonumber(model:GetAttribute(SentryConstants.ATTR_SENTRY_OWNER_USER_ID))
		if ownerUserId ~= player.UserId then
			return nil, nil
		end

		local record = sentryRecordByModel[model]
		local humanoid = if record and record.humanoid then record.humanoid else model:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid:IsA("Humanoid") and humanoid.Health > 0) then
			if record then
				removeRecord(model)
			end
			return nil, nil
		end

		local weaponId = if record and type(record.kindId) == "string" and record.kindId ~= "" then record.kindId else nil
		if not weaponId then
			local attrWeaponId = model:GetAttribute(SentryConstants.ATTR_SENTRY_WEAPON_ID)
			if type(attrWeaponId) == "string" and attrWeaponId ~= "" then
				weaponId = attrWeaponId
			end
		end
		if not weaponId then
			return nil, nil
		end

		if not record then
			record = {
				owner = player,
				kindId = weaponId,
				model = model,
				humanoid = humanoid,
				maxAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO),
				ammo = model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO),
				connections = {},
			}
			sentryRecordByModel[model] = record
		else
			record.owner = player
			record.kindId = weaponId
			record.model = model
			record.humanoid = humanoid
			if model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO) ~= nil then
				record.maxAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO)
			end
			if model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO) ~= nil then
				record.ammo = model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO)
			end
		end

		ensurePlayerModelIndex(player, model)
		resolveRecordAmmoState(record, defaultSentryMaxAmmo)
		syncSentryAmmoAttributes(record)
		return weaponId, record
	end

	syncSentryAmmoAttributes = function(record)
		if type(record) ~= "table" then
			return
		end

		local ammo, maxAmmo = SentryStatResolver.resolveAmmoState(record.ammo, record.maxAmmo, 1)
		record.maxAmmo = maxAmmo
		record.ammo = ammo

		local model = record.model
		if model and model:IsA("Model") then
			if type(record.kindId) == "string" and record.kindId ~= "" then
				model:SetAttribute(SentryConstants.ATTR_SENTRY_WEAPON_ID, record.kindId)
			end
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

	local function forEachLiveOwnedSentryRecord(player, callback)
		if not (player and player:IsA("Player")) then
			return
		end
		if type(callback) ~= "function" then
			return
		end

		local folder = getSentryTurretFolder()
		for _, child in ipairs(folder:GetChildren()) do
			if child and child:IsA("Model") then
				local weaponId, record = hydrateLiveOwnedSentryRecord(player, child)
				if weaponId and record then
					callback(weaponId, record)
				end
			end
		end
	end

	local function collectOwnedSentryRecordsByWeaponId(player)
		local recordsByWeaponId = {}
		forEachLiveOwnedSentryRecord(player, function(weaponId, record)
			local weaponRecords = recordsByWeaponId[weaponId]
			if not weaponRecords then
				weaponRecords = {}
				recordsByWeaponId[weaponId] = weaponRecords
			end
			table.insert(weaponRecords, record)
		end)

		return recordsByWeaponId
	end

	local function playerOwnsWeaponId(player, weaponId)
		local normalizedWeaponId = tostring(weaponId or "")
		if normalizedWeaponId == "" then
			return false
		end

		local ownsWeapon = false
		forEachLiveOwnedSentryRecord(player, function(liveWeaponId, _record)
			if liveWeaponId == normalizedWeaponId then
				ownsWeapon = true
			end
		end)
		if ownsWeapon then
			return true
		end

		return false
	end

	local function registerRecord(player, model, record)
		sentryRecordByModel[model] = record
		ensurePlayerModelIndex(player, model)
	end

	local function getRecord(model)
		return sentryRecordByModel[model]
	end

	local function getPlayerSentryModels(player)
		return sentryTurretsByPlayer[player]
	end

	local function resolveLiveAmmoRecord(candidateRecord)
		if type(candidateRecord) ~= "table" then
			return nil
		end

		local model = candidateRecord.model
		if not (model and model:IsA("Model") and model.Parent) then
			return nil
		end

		local liveRecord = sentryRecordByModel[model] or candidateRecord
		liveRecord.model = model

		local humanoid = liveRecord.humanoid
		if not (humanoid and humanoid:IsA("Humanoid") and humanoid.Parent) then
			humanoid = model:FindFirstChildOfClass("Humanoid")
		end
		if not (humanoid and humanoid:IsA("Humanoid") and humanoid.Health > 0) then
			if sentryRecordByModel[model] then
				removeRecord(model)
			end
			return nil
		end

		liveRecord.humanoid = humanoid

		local modelMaxAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_MAX_AMMO)
		if modelMaxAmmo ~= nil then
			liveRecord.maxAmmo = modelMaxAmmo
		end

		local modelAmmo = model:GetAttribute(SentryConstants.ATTR_TURRET_AMMO)
		if modelAmmo ~= nil then
			liveRecord.ammo = modelAmmo
		end

		local ammoLabel = liveRecord.ammoLabel
		if not (ammoLabel and ammoLabel:IsA("TextLabel") and ammoLabel.Parent) then
			local billboard = model:FindFirstChild(SentryConstants.TURRET_BILLBOARD_NAME)
			if billboard and billboard:IsA("BillboardGui") then
				local resolvedLabel = billboard:FindFirstChild(SentryConstants.TURRET_AMMO_LABEL_NAME)
				if resolvedLabel and resolvedLabel:IsA("TextLabel") then
					ammoLabel = resolvedLabel
					liveRecord.ammoLabel = ammoLabel
				end
			end
		end

		if liveRecord ~= candidateRecord then
			candidateRecord.humanoid = humanoid
			candidateRecord.maxAmmo = liveRecord.maxAmmo
			candidateRecord.ammo = liveRecord.ammo
			candidateRecord.ammoLabel = liveRecord.ammoLabel
		end

		return liveRecord
	end

	local function refillAmmoForSentryRecords(sentryRecords, weaponDef)
		if type(sentryRecords) ~= "table" then
			return false
		end
		local didRefill = false
		local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)
		for _, record in ipairs(sentryRecords) do
			local liveRecord = resolveLiveAmmoRecord(record)
			if liveRecord then
				local ammoBefore, turretMaxAmmo = resolveRecordAmmoState(liveRecord, fallbackMaxAmmo)
				liveRecord.ammo = turretMaxAmmo
				syncSentryAmmoAttributes(liveRecord)
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
		local liveRecordCount = 0
		local fallbackMaxAmmo = resolveTurretMaxAmmo(weaponDef)
		for _, record in ipairs(sentryRecords) do
			local liveRecord = resolveLiveAmmoRecord(record)
			if liveRecord then
				liveRecordCount += 1
				local turretAmmo, turretMaxAmmo = resolveRecordAmmoState(liveRecord, fallbackMaxAmmo)
				syncSentryAmmoAttributes(liveRecord)
				totalCurrentAmmo += turretAmmo
				totalMaxAmmo += turretMaxAmmo
			end
		end
		if liveRecordCount <= 0 then
			return nil
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
		resolveRecordAmmoState = resolveRecordAmmoState,
		syncSentryAmmoAttributes = syncSentryAmmoAttributes,
		collectOwnedSentryRecordsByWeaponId = collectOwnedSentryRecordsByWeaponId,
		playerOwnsWeaponId = playerOwnsWeaponId,
		refillAmmoForSentryRecords = refillAmmoForSentryRecords,
		getSentryAmmoSnapshot = getSentryAmmoSnapshot,
	}
end

return SentryRuntime
