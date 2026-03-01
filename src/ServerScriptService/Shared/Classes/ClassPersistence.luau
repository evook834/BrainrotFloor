local ClassPersistence = {}

function ClassPersistence.new(config)
	local persistenceConfig = config or {}
	local dataStoreService = persistenceConfig.dataStoreService
	local dataStoreName = persistenceConfig.dataStoreName
	local schemaVersion = persistenceConfig.schemaVersion
	local normalizeToken = persistenceConfig.normalizeToken
	local getDefaultClassId = persistenceConfig.getDefaultClassId
	local getMaxLevel = persistenceConfig.getMaxLevel
	local isKnownClassId = persistenceConfig.isKnownClassId

	local classSelectionStore = nil
	local classSelectionStoreUnavailable = false
	local persistedStateSignatureByUserId = {}
	local dirtyStateByUserId = {}

	local function getClassSelectionStore()
		if classSelectionStore then
			return classSelectionStore
		end
		if classSelectionStoreUnavailable then
			return nil
		end

		local ok, store = pcall(function()
			return dataStoreService:GetDataStore(dataStoreName)
		end)
		if not ok or not store then
			classSelectionStoreUnavailable = true
			warn(string.format("ClassService could not get class selection DataStore: %s", tostring(store)))
			return nil
		end

		classSelectionStore = store
		return classSelectionStore
	end

	local function getClassSelectionStoreKey(userId)
		return string.format("u:%d", math.max(0, math.floor(tonumber(userId) or 0)))
	end

	local function buildPersistableStateData(state)
		local maxLevel = getMaxLevel()
		local selectedClassId = normalizeToken(state and state.selectedClassId)
		if selectedClassId == "" or not isKnownClassId(selectedClassId) then
			selectedClassId = getDefaultClassId()
		end

		local progressByClassId = {}
		if type(state) == "table" and type(state.progressByClassId) == "table" then
			for classId, rawProgress in pairs(state.progressByClassId) do
				local normalizedClassId = normalizeToken(classId)
				if normalizedClassId ~= "" and isKnownClassId(normalizedClassId) and type(rawProgress) == "table" then
					local level = math.clamp(math.floor(tonumber(rawProgress.level) or 1), 1, maxLevel)
					local xp = math.max(0, tonumber(rawProgress.xp) or 0)
					if level >= maxLevel then
						xp = 0
					end
					progressByClassId[normalizedClassId] = {
						level = level,
						xp = xp,
					}
				end
			end
		end

		if selectedClassId ~= "" and not progressByClassId[selectedClassId] then
			progressByClassId[selectedClassId] = {
				level = 1,
				xp = 0,
			}
		end

		return {
			schemaVersion = schemaVersion,
			selectedClassId = selectedClassId,
			progressByClassId = progressByClassId,
		}
	end

	local function buildStateSignature(stateData)
		local parts = { tostring(stateData.selectedClassId or "") }
		local classIds = {}
		for classId in pairs(stateData.progressByClassId or {}) do
			table.insert(classIds, classId)
		end
		table.sort(classIds)

		for _, classId in ipairs(classIds) do
			local progress = stateData.progressByClassId[classId] or {}
			local level = math.floor(tonumber(progress.level) or 1)
			local xpMillis = math.max(0, math.floor(((tonumber(progress.xp) or 0) * 1000) + 0.5))
			table.insert(parts, string.format("%s:%d:%d", classId, level, xpMillis))
		end

		return table.concat(parts, "|")
	end

	local api = {}

	function api.loadPersistedState(userId)
		local store = getClassSelectionStore()
		if not store then
			return nil
		end

		local key = getClassSelectionStoreKey(userId)
		local ok, value = pcall(function()
			return store:GetAsync(key)
		end)
		if not ok then
			warn(string.format("ClassService failed to load class state for userId %s: %s", tostring(userId), tostring(value)))
			return nil
		end

		local loadedState = {
			selectedClassId = getDefaultClassId(),
			progressByClassId = {},
		}

		if type(value) == "string" then
			loadedState.selectedClassId = value
		elseif type(value) == "table" then
			loadedState.selectedClassId = value.selectedClassId or value.classId or loadedState.selectedClassId

			local progressByClassId = value.progressByClassId
			if type(progressByClassId) ~= "table" then
				progressByClassId = value.progress
			end

			if type(progressByClassId) == "table" then
				for classId, rawProgress in pairs(progressByClassId) do
					local normalizedClassId = normalizeToken(classId)
					if normalizedClassId ~= "" and isKnownClassId(normalizedClassId) and type(rawProgress) == "table" then
						loadedState.progressByClassId[normalizedClassId] = {
							level = tonumber(rawProgress.level) or 1,
							xp = tonumber(rawProgress.xp) or 0,
						}
					end
				end
			end
		else
			return nil
		end

		local normalizedSelectedClassId = normalizeToken(loadedState.selectedClassId)
		if normalizedSelectedClassId == "" or not isKnownClassId(normalizedSelectedClassId) then
			normalizedSelectedClassId = getDefaultClassId()
		end
		loadedState.selectedClassId = normalizedSelectedClassId
		if loadedState.selectedClassId == "" then
			return nil
		end

		return loadedState
	end

	function api.markDirty(userId)
		if type(userId) ~= "number" or userId <= 0 then
			return
		end

		dirtyStateByUserId[userId] = true
	end

	function api.savePersistedState(userId, state, force)
		if type(userId) ~= "number" or userId <= 0 then
			return false
		end

		local stateData = buildPersistableStateData(state)
		if stateData.selectedClassId == "" then
			return false
		end

		local signature = buildStateSignature(stateData)
		if persistedStateSignatureByUserId[userId] == signature and (not force or dirtyStateByUserId[userId] ~= true) then
			dirtyStateByUserId[userId] = nil
			return true
		end

		local store = getClassSelectionStore()
		if not store then
			return false
		end

		local key = getClassSelectionStoreKey(userId)
		local ok, errOrResult = pcall(function()
			store:SetAsync(key, stateData)
		end)
		if not ok then
			warn(
				string.format(
					"ClassService failed to save class state for userId %s (class %s): %s",
					tostring(userId),
					stateData.selectedClassId,
					tostring(errOrResult)
				)
			)
			return false
		end

		persistedStateSignatureByUserId[userId] = signature
		dirtyStateByUserId[userId] = nil
		return true
	end

	function api.isDirty(userId)
		return dirtyStateByUserId[userId] == true
	end

	function api.resetUserStateTracking(userId, state)
		if type(userId) ~= "number" or userId <= 0 then
			return
		end

		persistedStateSignatureByUserId[userId] = buildStateSignature(buildPersistableStateData(state))
		dirtyStateByUserId[userId] = nil
	end

	function api.clearUser(userId)
		if type(userId) ~= "number" or userId <= 0 then
			return
		end

		persistedStateSignatureByUserId[userId] = nil
		dirtyStateByUserId[userId] = nil
	end

	return api
end

return ClassPersistence

