local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local EnemyAIService = require(script.Parent.EnemyAIService)
local EnemyRegistry = require(script.Parent.EnemyRegistry)
local EnemySpawnResolver = require(script.Parent.EnemySpawnResolver)
local EnemyVfxService = require(script.Parent.EnemyVfxService)
local ModelRootResolver = require(script.Parent.ModelRootResolver)

local EnemyFactory = {}

local function getPivotToRootOffset(enemyModel, rootPart)
	if not enemyModel or not rootPart then
		return CFrame.new()
	end

	local modelPivot = enemyModel:GetPivot()
	return modelPivot:ToObjectSpace(rootPart.CFrame)
end

local function getDesiredPivotFromRoot(desiredRootCFrame, pivotToRootOffset)
	return desiredRootCFrame * pivotToRootOffset:Inverse()
end

function EnemyFactory.spawnFromTemplate(template, spawnPoint, container, waveContext, options)
	if not template or not template:IsA("Model") then
		return nil
	end
	if not spawnPoint or not spawnPoint:IsA("BasePart") then
		return nil
	end

	local resolvedOptions = type(options) == "table" and options or {}
	local templateName = template.Name
	local enemy = template:Clone()
	enemy.Name = resolvedOptions.enemyName or string.format("Brainrot_%s_%s", templateName, tostring(os.clock()):gsub("%.", "_"))

	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	local root = ModelRootResolver.resolveRootPart(enemy)
	if not root then
		warn(string.format("Template %s has no BasePart to spawn from", template:GetFullName()))
		enemy:Destroy()
		return nil
	end

	EnemySpawnResolver.addTemplateHitboxProxy(enemy, templateName, root)
	local spawnOffsetY = EnemySpawnResolver.getSpawnOffsetY(enemy, templateName, spawnPoint)
	local pivotToRootOffset = getPivotToRootOffset(enemy, root)
	local desiredRootCFrame = spawnPoint.CFrame + Vector3.new(0, spawnOffsetY, 0)
	enemy:PivotTo(getDesiredPivotFromRoot(desiredRootCFrame, pivotToRootOffset))
	enemy.Parent = container

	local resolvedWaveContext = waveContext or {}
	local activeWaveNumber = math.max(1, tonumber(resolvedWaveContext.activeWaveNumber) or 1)
	local activeDifficulty = resolvedWaveContext.activeDifficulty
	local playerCountForWave = math.max(1, tonumber(resolvedWaveContext.playerCountForWave) or 1)
	local enemyPlayerHealthMultiplier = tonumber(resolvedWaveContext.enemyPlayerHealthMultiplier) or 1
	local enemyHealthMultiplier = tonumber(resolvedWaveContext.enemyHealthMultiplier) or 1
	local enemyDamageMultiplier = tonumber(resolvedWaveContext.enemyDamageMultiplier) or 1

	enemy:SetAttribute("IsEnemy", true)
	enemy:SetAttribute("Difficulty", activeDifficulty)
	enemy:SetAttribute("EnemyPlayerCountForScaling", playerCountForWave)
	enemy:SetAttribute("EnemyPlayerHealthMultiplier", enemyPlayerHealthMultiplier)
	enemy:SetAttribute("EnemyHealthMultiplier", enemyHealthMultiplier)
	enemy:SetAttribute("EnemyDamageMultiplier", enemyDamageMultiplier)
	enemy:SetAttribute("EnemyType", templateName)

	local enemyTier = resolvedOptions.enemyTier
	if type(enemyTier) == "string" and enemyTier ~= "" then
		enemy:SetAttribute("EnemyTier", enemyTier)
	end

	enemy:SetAttribute(
		"Bounty",
		(Config.Enemy.BaseBounty or 25) + math.max(0, activeWaveNumber - 1) * (Config.Enemy.BountyPerWave or 4)
	)

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
			if type(resolvedOptions.onEnemyDied) == "function" then
				resolvedOptions.onEnemyDied()
			end
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

	EnemyRegistry.registerEnemy(enemy)

	return enemy
end

return EnemyFactory
