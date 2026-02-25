--[[
	EnemyDamageService — Apply damage + feedback + DOT pipeline.
	Money/kill rewards, damage blink, damage indicators, crits, burn-on-hit.
	Core entry: applyDamageToEnemy, applyBlastDamage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local Match = script.Parent.Parent
local ClassService = require(Match.Classes.ClassService)
local EnemyVfxService = require(Match.Enemies.EnemyVfxService)
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)
local ShopConstants = require(script.Parent.ShopConstants)

local BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS = ShopConstants.BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS

local damageIndicatorRemote = nil
local enemyDamageBlinkState = setmetatable({}, { __mode = "k" })
local enemyBurnState = setmetatable({}, { __mode = "k" })
local randomGenerator = Random.new()

function init(options)
	if type(options) == "table" and options.damageIndicatorRemote ~= nil then
		damageIndicatorRemote = options.damageIndicatorRemote
	end
end

local function getEnemyContainer()
	return Workspace:FindFirstChild(Config.Enemy.ContainerName)
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

	moneyValue.Value += math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
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

local function getOrCreateEnemyBlinkHighlight(enemyModel)
	local highlight = enemyModel:FindFirstChild("DamageBlinkHighlight")
	if highlight and not highlight:IsA("Highlight") then
		highlight:Destroy()
		highlight = nil
	end

	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "DamageBlinkHighlight"
		highlight.Adornee = enemyModel
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = Color3.fromRGB(255, 35, 35)
		highlight.FillTransparency = 0.22
		highlight.OutlineColor = Color3.fromRGB(255, 35, 35)
		highlight.OutlineTransparency = 0.65
		highlight.Enabled = false
		highlight.Parent = enemyModel
	end

	return highlight
end

local function blinkEnemyDamage(enemyModel)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local state = enemyDamageBlinkState[enemyModel]
	if not state then
		state = {
			token = 0,
		}
		enemyDamageBlinkState[enemyModel] = state
	end

	local highlight = getOrCreateEnemyBlinkHighlight(enemyModel)
	if not highlight then
		return
	end

	state.token += 1
	local currentToken = state.token
	highlight.Adornee = enemyModel
	highlight.Enabled = true

	task.delay(0.12, function()
		if not enemyModel.Parent then
			return
		end

		local liveState = enemyDamageBlinkState[enemyModel]
		if liveState ~= state or liveState.token ~= currentToken then
			return
		end

		if highlight.Parent == enemyModel then
			highlight.Enabled = false
		end
	end)
end

local function getDamageIndicatorStyleTag(weaponDef)
	if type(weaponDef) ~= "table" then
		return nil
	end

	-- Set this to "crit" to force the crit damage indicator style.
	local explicitStyle = weaponDef.DamageIndicatorStyle or weaponDef.DamageTextStyle
	if type(explicitStyle) == "string" and explicitStyle ~= "" then
		return string.lower(explicitStyle)
	end

	if weaponDef.Crit == true or weaponDef.IsCrit == true then
		return "crit"
	end

	return nil
end

local function resolveCriticalHitOutcome(player, weaponDef, damageContext)
	if damageContext and damageContext.allowCriticalHits == false then
		return 1, nil
	end
	if not player or not player:IsA("Player") then
		return 1, nil
	end
	if type(weaponDef) ~= "table" then
		return 1, nil
	end

	local critConfig = ClassService.getCriticalHitConfig(player, weaponDef)
	if type(critConfig) ~= "table" then
		return 1, nil
	end

	local superCriticalChance = math.clamp(tonumber(critConfig.superCriticalChance) or 0, 0, 1)
	local criticalChance = math.clamp(tonumber(critConfig.criticalChance) or 0, 0, 1)
	local totalChance = math.clamp(superCriticalChance + criticalChance, 0, 1)
	if totalChance <= 0 then
		return 1, nil
	end

	local roll = randomGenerator:NextNumber()
	if roll <= superCriticalChance then
		return math.max(1, tonumber(critConfig.superCriticalMultiplier) or 3), "supercrit"
	end
	if roll <= totalChance then
		return math.max(1, tonumber(critConfig.criticalMultiplier) or 2), "crit"
	end

	return 1, nil
end

local function emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
	if not damageIndicatorRemote then
		return
	end
	if not player or not player:IsA("Player") then
		return
	end
	if not enemyModel or not enemyModel.Parent then
		return
	end
	if type(dealtDamage) ~= "number" or dealtDamage <= 0 then
		return
	end
	local normalizedStyleTag = nil
	if type(indicatorStyleTag) == "string" and indicatorStyleTag ~= "" then
		normalizedStyleTag = string.lower(indicatorStyleTag)
	end

	local worldPosition = nil
	local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
	if enemyRoot then
		worldPosition = enemyRoot.Position
	else
		local ok, pivot = pcall(function()
			return enemyModel:GetPivot()
		end)
		if ok then
			worldPosition = pivot.Position
		end
	end

	damageIndicatorRemote:FireClient(player, enemyModel, dealtDamage, worldPosition, normalizedStyleTag)
end

local function isEnemyAliveForBurn(enemyModel)
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

local function applyDamageToEnemy(player, enemyModel, damage, weaponDef, damageContext)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	local context = damageContext or {}
	local applyClassMultiplier = context.applyClassMultiplier ~= false
	local allowBurnOnHit = context.allowBurnOnHit ~= false
	local explicitIndicatorStyleTag = nil
	if type(context.indicatorStyleTag) == "string" and context.indicatorStyleTag ~= "" then
		explicitIndicatorStyleTag = string.lower(context.indicatorStyleTag)
	end

	local appliedDamage = math.max(0, tonumber(damage) or 0)
	if appliedDamage <= 0 then
		return
	end

	local classMultiplier = 1
	if player and player:IsA("Player") and weaponDef then
		local computedMultiplier = ClassService.getWeaponDamageMultiplier(player, weaponDef)
		if computedMultiplier <= 0 then
			if applyClassMultiplier then
				return
			end
		else
			classMultiplier = computedMultiplier
			if applyClassMultiplier then
				appliedDamage *= classMultiplier
			end
		end
	end

	local criticalDamageMultiplier, criticalIndicatorStyleTag = resolveCriticalHitOutcome(player, weaponDef, context)
	appliedDamage *= math.max(1, tonumber(criticalDamageMultiplier) or 1)

	local indicatorStyleTag = criticalIndicatorStyleTag or explicitIndicatorStyleTag or getDamageIndicatorStyleTag(weaponDef)

	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local previousHealth = humanoid.Health
		if previousHealth <= 0 then
			return
		end

		humanoid:TakeDamage(appliedDamage)
		local currentHealth = humanoid.Health
		local dealtDamage = math.max(0, previousHealth - currentHealth)
		if dealtDamage > 0 then
			blinkEnemyDamage(enemyModel)
			if player and player:IsA("Player") then
				ClassService.recordDamage(player, dealtDamage, weaponDef)
				emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
			end
			if allowBurnOnHit and currentHealth > 0 then
				tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
			end
		end
		if previousHealth > 0 and currentHealth <= 0 then
			EnemyVfxService.playDeathCloud(enemyModel)
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

	local previousHealth = health
	health -= appliedDamage
	enemyModel:SetAttribute("EnemyMaxHealth", maxHealth)
	enemyModel:SetAttribute("EnemyHealth", health)
	local dealtDamage = math.max(0, previousHealth - health)
	if dealtDamage > 0 then
		blinkEnemyDamage(enemyModel)
		if player and player:IsA("Player") then
			ClassService.recordDamage(player, dealtDamage, weaponDef)
			emitDamageIndicator(player, enemyModel, dealtDamage, indicatorStyleTag)
		end
		if allowBurnOnHit and health > 0 then
			tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
		end
	end

	if health <= 0 then
		rewardEnemyKill(player, enemyModel)
		EnemyVfxService.playDeathCloud(enemyModel)
		enemyModel:Destroy()
	end
end

local function tryApplyBurnOnHit(player, enemyModel, weaponDef, classMultiplier)
	if not player or not player:IsA("Player") then
		return
	end
	if not enemyModel or not enemyModel.Parent then
		return
	end
	if type(weaponDef) ~= "table" then
		return
	end

	local burnConfig = ClassService.getBurnOnHitConfig(player, weaponDef)
	if type(burnConfig) ~= "table" then
		return
	end

	local chance = math.clamp(tonumber(burnConfig.chance) or 0, 0, 1)
	if chance <= 0 or randomGenerator:NextNumber() > chance then
		return
	end

	local durationSeconds = math.max(0.1, tonumber(burnConfig.durationSeconds) or 3)
	local tickIntervalSeconds = math.max(
		0.1,
		tonumber(burnConfig.tickIntervalSeconds) or BURN_DOT_FALLBACK_TICK_INTERVAL_SECONDS
	)
	local damageFractionPerSecond = math.max(0, tonumber(burnConfig.damageFractionPerSecond) or 0)
	if damageFractionPerSecond <= 0 then
		return
	end

	local baseWeaponDamage = math.max(0, tonumber(weaponDef.Damage) or 0)
	if baseWeaponDamage <= 0 then
		return
	end

	local effectiveWeaponDamage = baseWeaponDamage * math.max(0, tonumber(classMultiplier) or 1)
	local damagePerTick = effectiveWeaponDamage * damageFractionPerSecond * tickIntervalSeconds
	if damagePerTick <= 0 then
		return
	end

	local ticksRemaining = math.max(1, math.floor((durationSeconds / tickIntervalSeconds) + 0.5))
	local state = enemyBurnState[enemyModel]
	if not state then
		state = {
			token = 0,
		}
		enemyBurnState[enemyModel] = state
	end

	state.token += 1
	local currentToken = state.token
	state.ownerPlayer = player
	state.damagePerTick = damagePerTick
	state.tickIntervalSeconds = tickIntervalSeconds
	state.ticksRemaining = ticksRemaining

	task.spawn(function()
		while true do
			local liveState = enemyBurnState[enemyModel]
			if liveState ~= state or state.token ~= currentToken then
				return
			end
			if state.ticksRemaining <= 0 then
				break
			end

			task.wait(state.tickIntervalSeconds)

			liveState = enemyBurnState[enemyModel]
			if liveState ~= state or state.token ~= currentToken then
				return
			end
			if not isEnemyAliveForBurn(enemyModel) then
				enemyBurnState[enemyModel] = nil
				return
			end

			local ownerPlayer = state.ownerPlayer
			if not ownerPlayer or not ownerPlayer:IsA("Player") or ownerPlayer.Parent ~= Players then
				enemyBurnState[enemyModel] = nil
				return
			end

			applyDamageToEnemy(ownerPlayer, enemyModel, state.damagePerTick, nil, {
				applyClassMultiplier = false,
				allowBurnOnHit = false,
				allowCriticalHits = false,
			})
			state.ticksRemaining -= 1
		end

		local liveState = enemyBurnState[enemyModel]
		if liveState == state and state.token == currentToken then
			enemyBurnState[enemyModel] = nil
		end
	end)
end

local function applyBlastDamage(player, centerPosition, radius, maxDamage, weaponDef, damageContext)
	local enemyContainer = getEnemyContainer()
	if not enemyContainer then
		return
	end

	for _, enemyModel in enemyContainer:GetChildren() do
		if enemyModel:IsA("Model") then
			local enemyRoot = ModelRootResolver.resolveRootPart(enemyModel)
			if enemyRoot then
				local distance = (enemyRoot.Position - centerPosition).Magnitude
				if distance <= radius then
					local falloff = 1 - (distance / math.max(radius, 0.01))
					local damageScale = math.clamp(0.3 + falloff * 0.7, 0.3, 1)
					applyDamageToEnemy(player, enemyModel, maxDamage * damageScale, weaponDef, damageContext)
				end
			end
		end
	end
end

return {
	init = init,
	getMoneyValue = getMoneyValue,
	addMoney = addMoney,
	applyDamageToEnemy = applyDamageToEnemy,
	applyBlastDamage = applyBlastDamage,
	tryApplyBurnOnHit = tryApplyBurnOnHit,
}
