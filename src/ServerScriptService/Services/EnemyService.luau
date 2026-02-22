local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyAIService = require(script.Parent.EnemyAIService)
local DifficultyService = require(script.Parent.DifficultyService)
local EnemyVfxService = require(script.Parent.EnemyVfxService)
local ModelRootResolver = require(script.Parent.ModelRootResolver)

local EnemyService = {}

local function getEnemyTemplates()
	local folder = ServerStorage:FindFirstChild(Config.Enemy.TemplateFolderName)
	if not folder then
		return {}
	end

	local templates = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and ModelRootResolver.resolveRootPart(child) then
			table.insert(templates, child)
		end
	end

	return templates
end

local function getSpawnPoints()
	local spawnFolder = Workspace:FindFirstChild(Config.Enemy.SpawnFolderName)
	if not spawnFolder then
		return {}
	end

	local points = {}
	for _, child in spawnFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end

	return points
end

local function getEnemyContainer()
	local container = Workspace:FindFirstChild(Config.Enemy.ContainerName)
	if container then
		return container
	end

	container = Instance.new("Folder")
	container.Name = Config.Enemy.ContainerName
	container.Parent = Workspace
	return container
end

local function chooseRandom(list)
	return list[math.random(1, #list)]
end

local function getTemplateProfile(templateName)
	local templateProfile = (Config.Enemy.TemplateProfiles or {})[templateName]
	if type(templateProfile) == "table" then
		return templateProfile
	end

	return nil
end

local function getSpawnOffsetY(enemyModel, templateName, spawnPoint)
	local halfHeight = 2
	local ok, _, size = pcall(function()
		return enemyModel:GetBoundingBox()
	end)
	if ok and size then
		halfHeight = size.Y * 0.5
	end

	local templateProfile = getTemplateProfile(templateName)
	local profileOffsetY = 0
	if type(templateProfile) == "table" and type(templateProfile.SpawnOffsetY) == "number" then
		profileOffsetY = templateProfile.SpawnOffsetY
	end

	local spawnPartHalfHeight = 0
	if spawnPoint and spawnPoint:IsA("BasePart") then
		spawnPartHalfHeight = spawnPoint.Size.Y * 0.5
	end

	return spawnPartHalfHeight + halfHeight + (Config.Enemy.SpawnPaddingY or 0.1) + profileOffsetY
end

local function addTemplateHitboxProxy(enemyModel, templateName, rootPart)
	local templateProfile = getTemplateProfile(templateName)
	if not templateProfile then
		return
	end

	local hitboxScale = tonumber(templateProfile.HitboxScale) or 1
	local hitboxPadding = tonumber(templateProfile.HitboxPadding) or 0
	if hitboxScale <= 1 and hitboxPadding <= 0 then
		return
	end

	local scaledSize = rootPart.Size * math.max(0.1, hitboxScale)
	local totalPadding = math.max(0, hitboxPadding) * 2
	local proxySize = Vector3.new(
		math.max(0.2, scaledSize.X + totalPadding),
		math.max(0.2, scaledSize.Y + totalPadding),
		math.max(0.2, scaledSize.Z + totalPadding)
	)

	local existingProxy = enemyModel:FindFirstChild("HitboxProxy")
	if existingProxy and existingProxy:IsA("BasePart") then
		existingProxy:Destroy()
	end

	local proxy = Instance.new("Part")
	proxy.Name = "HitboxProxy"
	proxy.Size = proxySize
	proxy.CFrame = rootPart.CFrame
	proxy.Transparency = 1
	proxy.Anchored = false
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = true
	proxy.CastShadow = false
	proxy.Massless = true
	proxy.Parent = enemyModel

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HitboxProxyWeld"
	weld.Part0 = proxy
	weld.Part1 = rootPart
	weld.Parent = proxy
end

local function getSpawnCadence()
	local configuredCadence = Config.Wave.SpawnCadence or {}
	local playerScaling = configuredCadence.PlayerScaling or {}
	return {
		InitialDelaySeconds = configuredCadence.InitialDelaySeconds or 2,
		BaseIntervalSeconds = configuredCadence.BaseIntervalSeconds or 3,
		MinIntervalSeconds = configuredCadence.MinIntervalSeconds or 1.2,
		WaveAccelerationPerWave = configuredCadence.WaveAccelerationPerWave or 0.12,
		IntraWaveAcceleration = configuredCadence.IntraWaveAcceleration or 0.6,
		GroupSize = configuredCadence.GroupSize or 4,
		GroupPauseSeconds = configuredCadence.GroupPauseSeconds or 1.0,
		IntraBurstDelaySeconds = configuredCadence.IntraBurstDelaySeconds or 0.08,
		PlayerScaling = {
			Enabled = playerScaling.Enabled ~= false,
			BasePlayers = playerScaling.BasePlayers or 1,
			BurstSizeBase = playerScaling.BurstSizeBase or 1,
			BurstSizePerExtraPlayer = playerScaling.BurstSizePerExtraPlayer or 1,
			MaxBurstSize = playerScaling.MaxBurstSize or 4,
			IntervalMultiplierPerExtraPlayer = playerScaling.IntervalMultiplierPerExtraPlayer or 0.12,
			MinIntervalMultiplier = playerScaling.MinIntervalMultiplier or 0.45,
			GroupPauseMultiplierPerExtraPlayer = playerScaling.GroupPauseMultiplierPerExtraPlayer or 0.08,
			MinGroupPauseMultiplier = playerScaling.MinGroupPauseMultiplier or 0.5,
		},
	}
end

local function getPlayerSpawnModifiers(playerCount, cadence)
	local scaling = cadence.PlayerScaling
	if not scaling.Enabled then
		return 1, 1, 1
	end

	local basePlayers = math.max(1, scaling.BasePlayers)
	local extraPlayers = math.max(0, playerCount - basePlayers)

	local burstSize = scaling.BurstSizeBase + extraPlayers * scaling.BurstSizePerExtraPlayer
	burstSize = math.clamp(burstSize, 1, math.max(1, scaling.MaxBurstSize))
	burstSize = math.max(1, math.floor(burstSize + 0.5))

	local intervalMultiplier = 1 - extraPlayers * scaling.IntervalMultiplierPerExtraPlayer
	intervalMultiplier = math.max(scaling.MinIntervalMultiplier, intervalMultiplier)

	local groupPauseMultiplier = 1 - extraPlayers * scaling.GroupPauseMultiplierPerExtraPlayer
	groupPauseMultiplier = math.max(scaling.MinGroupPauseMultiplier, groupPauseMultiplier)

	return burstSize, intervalMultiplier, groupPauseMultiplier
end

local function getDelayUntilNextBurst(spawnedCount, enemyCount, waveNumber, cadence, intervalMultiplier, groupPauseMultiplier)
	if spawnedCount >= enemyCount then
		return 0
	end

	local waveAcceleration = math.max(0, waveNumber - 1) * cadence.WaveAccelerationPerWave
	local progress = 0
	if enemyCount > 1 then
		progress = (spawnedCount - 1) / (enemyCount - 1)
	end
	local intraWaveAcceleration = cadence.IntraWaveAcceleration * progress

	local interval = (cadence.BaseIntervalSeconds - waveAcceleration - intraWaveAcceleration) * intervalMultiplier
	interval = math.max(cadence.MinIntervalSeconds, interval)

	if cadence.GroupSize > 0 and spawnedCount % cadence.GroupSize == 0 then
		interval += cadence.GroupPauseSeconds * groupPauseMultiplier
	end

	return interval
end

local function getEnemyHealthMultiplierForDifficulty(difficulty)
	local multiplier = tonumber(DifficultyService.getNumberSetting("EnemyHealthMultiplier", 1, difficulty)) or 1
	if multiplier <= 0 then
		return 1
	end

	return multiplier
end

local function getEnemyDamageMultiplierForDifficulty(difficulty)
	local multiplier = tonumber(DifficultyService.getNumberSetting("EnemyDamageMultiplier", 1, difficulty)) or 1
	if multiplier < 0 then
		return 0
	end

	return multiplier
end

function EnemyService.spawnWave(enemyCount, waveNumber)
	local templates = getEnemyTemplates()
	local spawnPoints = getSpawnPoints()

	if #templates == 0 then
		warn("No enemy templates found in ServerStorage/EnemyTemplates")
		return 0
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in Workspace/SpawnPoints")
		return 0
	end

	local container = getEnemyContainer()
	local spawned = 0
	local cadence = getSpawnCadence()
	local activeWaveNumber = waveNumber or 1
	local activeDifficulty = DifficultyService.getCurrentDifficulty()
	local enemyHealthMultiplier = getEnemyHealthMultiplierForDifficulty(activeDifficulty)
	local enemyDamageMultiplier = getEnemyDamageMultiplierForDifficulty(activeDifficulty)

	if enemyCount > 0 and cadence.InitialDelaySeconds > 0 then
		task.wait(cadence.InitialDelaySeconds)
	end

	local spawnIndex = 0
	while spawnIndex < enemyCount do
		local playerCount = math.max(1, #Players:GetPlayers())
		local burstSize, intervalMultiplier, groupPauseMultiplier = getPlayerSpawnModifiers(playerCount, cadence)
		local toSpawnNow = math.min(burstSize, enemyCount - spawnIndex)

		for burstIndex = 1, toSpawnNow do
			spawnIndex += 1
			local template = chooseRandom(templates)
			local templateName = template.Name
			local spawnPoint = chooseRandom(spawnPoints)
			local enemy = template:Clone()
			enemy.Name = string.format("Brainrot_%d", spawnIndex)

			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			local root = ModelRootResolver.resolveRootPart(enemy)

			if root then
				addTemplateHitboxProxy(enemy, templateName, root)
				local spawnOffsetY = getSpawnOffsetY(enemy, templateName, spawnPoint)
				enemy:PivotTo(spawnPoint.CFrame + Vector3.new(0, spawnOffsetY, 0))
				enemy.Parent = container
				enemy:SetAttribute("IsEnemy", true)
				enemy:SetAttribute("Difficulty", activeDifficulty)
				enemy:SetAttribute("EnemyHealthMultiplier", enemyHealthMultiplier)
				enemy:SetAttribute("EnemyDamageMultiplier", enemyDamageMultiplier)
				enemy:SetAttribute("EnemyType", templateName)
				enemy:SetAttribute(
					"Bounty",
					(Config.Enemy.BaseBounty or 25) + math.max(0, activeWaveNumber - 1) * (Config.Enemy.BountyPerWave or 4)
				)
				spawned += 1
				EnemyAIService.start(enemy, templateName)

				if humanoid then
					local baseMaxHealth = math.max(1, humanoid.MaxHealth)
					local healthRatio = math.clamp(humanoid.Health / baseMaxHealth, 0, 1)
					local scaledMaxHealth = math.max(1, baseMaxHealth * enemyHealthMultiplier)
					humanoid.MaxHealth = scaledMaxHealth
					humanoid.Health = scaledMaxHealth * healthRatio
					enemy:SetAttribute("EnemyMaxHealth", humanoid.MaxHealth)
					enemy:SetAttribute("EnemyHealth", humanoid.Health)
					humanoid.HealthChanged:Connect(function(newHealth)
						enemy:SetAttribute("EnemyHealth", newHealth)
					end)

					humanoid.Died:Once(function()
						EnemyVfxService.playDeathCloud(enemy)
						task.delay(2, function()
							if enemy and enemy.Parent then
								enemy:Destroy()
							end
						end)
					end)
				else
					local nonHumanoidHealth = math.max(1, (Config.Enemy.NonHumanoidMaxHealth or 120) * enemyHealthMultiplier)
					enemy:SetAttribute("EnemyMaxHealth", nonHumanoidHealth)
					enemy:SetAttribute("EnemyHealth", nonHumanoidHealth)
				end
			else
				warn(string.format("Template %s has no BasePart to spawn from", template:GetFullName()))
				enemy:Destroy()
			end

			if burstIndex < toSpawnNow and cadence.IntraBurstDelaySeconds > 0 then
				task.wait(cadence.IntraBurstDelaySeconds)
			end
		end

		local nextDelay = getDelayUntilNextBurst(
			spawnIndex,
			enemyCount,
			activeWaveNumber,
			cadence,
			intervalMultiplier,
			groupPauseMultiplier
		)
		if nextDelay > 0 then
			task.wait(nextDelay)
		end
	end

	return spawned
end

return EnemyService
