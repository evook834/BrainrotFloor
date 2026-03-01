--[[
	SentryTargeting — Enemy targeting for sentries: visibility, range, health/distance priority.
	Factory .new(options) returns isEnemyModelAlive, getEnemyModelHealth, pickTurretTargetCandidate, findTurretTarget.
]]

local Workspace = game:GetService("Workspace")

local SentryTargeting = {}

function SentryTargeting.new(options)
	local opts = options or {}
	local modelRootResolver = opts.modelRootResolver
	local getEffectsFolder = opts.getEffectsFolder
	local getEnemyContainer = opts.getEnemyContainer
	local enemyContainerName = tostring(opts.enemyContainerName or "")

	if type(modelRootResolver) ~= "table" or type(modelRootResolver.resolveRootPart) ~= "function" then
		error("SentryTargeting.new requires options.modelRootResolver.resolveRootPart", 2)
	end

	local function resolveEnemyContainer()
		if type(getEnemyContainer) == "function" then
			return getEnemyContainer()
		end
		if enemyContainerName == "" then
			return nil
		end
		return Workspace:FindFirstChild(enemyContainerName)
	end

	local function isEnemyModelAlive(enemyModel)
		if not enemyModel or not enemyModel.Parent then
			return false
		end

		local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid.Health > 0
		end

		local health = enemyModel:GetAttribute("EnemyHealth")
		if type(health) ~= "number" then
			return true
		end

		return health > 0
	end

	local function getEnemyModelHealth(enemyModel)
		if not enemyModel or not enemyModel.Parent then
			return nil, nil
		end

		local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local currentHealth = tonumber(humanoid.Health)
			local maxHealth = tonumber(humanoid.MaxHealth)
			if type(maxHealth) ~= "number" or maxHealth <= 0 then
				maxHealth = 1
			end
			return currentHealth, maxHealth
		end

		local currentHealth = enemyModel:GetAttribute("EnemyHealth")
		if type(currentHealth) ~= "number" then
			return nil, nil
		end

		local maxHealth = enemyModel:GetAttribute("EnemyMaxHealth")
		if type(maxHealth) ~= "number" or maxHealth <= 0 then
			maxHealth = math.max(1, currentHealth)
		end

		return currentHealth, maxHealth
	end

	local function pickTurretTargetCandidate(bestCandidate, candidate, preferredModel)
		if not bestCandidate then
			return candidate
		end

		if candidate.health < bestCandidate.health then
			return candidate
		end
		if candidate.health > bestCandidate.health then
			return bestCandidate
		end

		if candidate.distance < bestCandidate.distance then
			return candidate
		end
		if candidate.distance > bestCandidate.distance then
			return bestCandidate
		end

		if preferredModel then
			if candidate.model == preferredModel and bestCandidate.model ~= preferredModel then
				return candidate
			end
			if bestCandidate.model == preferredModel and candidate.model ~= preferredModel then
				return bestCandidate
			end
		end

		return bestCandidate
	end

	local function findTurretTarget(record, muzzleOrigin)
		local enemyContainer = resolveEnemyContainer()
		if not enemyContainer then
			record.currentTarget = nil
			return nil, nil
		end

		local maxRange = math.max(100, tonumber(record.acquireRange) or 100000)
		local preferredModel = record.currentTarget
		local bestCandidate = nil

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { record.model, if type(getEffectsFolder) == "function" then getEffectsFolder() else nil }
		raycastParams.IgnoreWater = true

		local function buildCandidate(enemyModel)
			if not enemyModel:IsA("Model") or not isEnemyModelAlive(enemyModel) then
				return nil
			end

			local enemyRoot = modelRootResolver.resolveRootPart(enemyModel)
			if not enemyRoot then
				return nil
			end

			local delta = enemyRoot.Position - muzzleOrigin
			local distance = delta.Magnitude
			if distance <= 0.01 or distance > maxRange then
				return nil
			end

			local hitResult = Workspace:Raycast(muzzleOrigin, delta, raycastParams)
			local isVisible = false
			if not hitResult then
				isVisible = true
			else
				isVisible = hitResult.Instance and hitResult.Instance:IsDescendantOf(enemyModel)
			end
			if not isVisible then
				return nil
			end

			local currentHealth = getEnemyModelHealth(enemyModel)
			local resolvedHealth = math.huge
			if type(currentHealth) == "number" then
				resolvedHealth = math.max(0, currentHealth)
			end

			return {
				model = enemyModel,
				root = enemyRoot,
				distance = distance,
				health = resolvedHealth,
			}
		end

		-- Hard target lock: keep current target until dead or out of range.
		if preferredModel and preferredModel.Parent then
			local preferredRoot = modelRootResolver.resolveRootPart(preferredModel)
			if preferredRoot and isEnemyModelAlive(preferredModel) then
				local preferredDelta = preferredRoot.Position - muzzleOrigin
				local preferredDistance = preferredDelta.Magnitude
				if preferredDistance > 0.01 and preferredDistance <= maxRange then
					record.currentTarget = preferredModel
					return preferredModel, preferredRoot
				end
			end
		end

		for _, enemyModel in ipairs(enemyContainer:GetChildren()) do
			local candidate = buildCandidate(enemyModel)
			if candidate then
				bestCandidate = pickTurretTargetCandidate(bestCandidate, candidate, preferredModel)
			end
		end

		if bestCandidate then
			record.currentTarget = bestCandidate.model
			return bestCandidate.model, bestCandidate.root
		end

		record.currentTarget = nil
		return nil, nil
	end

	return {
		isEnemyModelAlive = isEnemyModelAlive,
		getEnemyModelHealth = getEnemyModelHealth,
		pickTurretTargetCandidate = pickTurretTargetCandidate,
		findTurretTarget = findTurretTarget,
	}
end

return SentryTargeting
