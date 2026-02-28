--[[
	Player lifecycle during match: leaderstats (and sync with PlayerDataService), disable health regen,
	character death/respawn (via SpectatorService), game-over when all dead, late-join spawn.
	Used by GameBootstrap; exposes bindPlayerSystems and hasAnyLivingPlayers.
]]

local Players = game:GetService("Players")

local PlayerLifecycleBootstrap = {}

function PlayerLifecycleBootstrap.hasAnyLivingPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
				return true
			end
		end
	end
	return false
end

local function disableHumanoidRegen(humanoid)
	local lastHealth = humanoid.Health
	local adjusting = false

	humanoid.HealthChanged:Connect(function(newHealth)
		if adjusting then return end
		if newHealth > lastHealth then
			adjusting = true
			humanoid.Health = lastHealth
			adjusting = false
			return
		end
		lastHealth = newHealth
	end)
end

local function ensureLeaderstats(player, configPlayer, playerDataService, startingMoney)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = 0
		money.Parent = leaderstats
	end

	money.Value = startingMoney

	if playerDataService and playerDataService.isReady and playerDataService.isReady() then
		task.spawn(function()
			local ok = pcall(function()
				playerDataService.waitForData(player)
			end)
			if not ok or not player.Parent or not leaderstats.Parent then return end
			local syncedMoney = startingMoney
			local moneyValue = leaderstats:FindFirstChild("Money")
			if moneyValue then
				syncedMoney = math.max(0, math.floor((tonumber(moneyValue.Value) or startingMoney) + 0.5))
			end
			playerDataService.set(player, { "money" }, syncedMoney, true)
			if moneyValue then
				moneyValue.Value = syncedMoney
			end
			local changedSignal = playerDataService.getChangedSignal(player, { "money" })
			if changedSignal then
				changedSignal:Connect(function(newVal)
					if leaderstats.Parent and leaderstats:FindFirstChild("Money") then
						leaderstats.Money.Value = math.floor((tonumber(newVal) or 0) + 0.5)
					end
				end)
			end
		end)
	end
end

function PlayerLifecycleBootstrap.createBindPlayerSystems(options)
	local configPlayer = options.configPlayer
	local playerDataService = options.playerDataService
	local spectatorService = options.spectatorService
	local getIsGameOver = options.getIsGameOver
	local triggerGameOver = options.triggerGameOver
	local sendMapVoteSnapshot = options.sendMapVoteSnapshot
	local startingMoney = math.max(0, (configPlayer and configPlayer.StartingMoney) or 0)

	return function(player)
		ensureLeaderstats(player, configPlayer, playerDataService, startingMoney)

		if sendMapVoteSnapshot then
			sendMapVoteSnapshot(player)
		end

		local function onCharacter(character)
			spectatorService.onPlayerRespawn(player, character)

			local humanoid = character:WaitForChild("Humanoid", 10)
			if not humanoid then return end

			if configPlayer and configPlayer.DisableHealthRegen then
				disableHumanoidRegen(humanoid)
			end

			humanoid.Died:Connect(function()
				task.defer(function()
					if getIsGameOver and getIsGameOver() then return end

					if PlayerLifecycleBootstrap.hasAnyLivingPlayers() then
						spectatorService.onPlayerDeath(player)
						return
					end

					triggerGameOver()
				end)
			end)
		end

		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		elseif not (getIsGameOver and getIsGameOver()) then
			if options.isMatchRunningForLateJoin and options.isMatchRunningForLateJoin() then
				spectatorService.onPlayerJoinDuringMatch(player)
			else
				player:LoadCharacter()
			end
		end
	end
end

return PlayerLifecycleBootstrap
