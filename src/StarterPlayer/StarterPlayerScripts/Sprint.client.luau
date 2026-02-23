local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local sprintKey = Enum.KeyCode.LeftShift
local sprintMultiplier = math.max(1, tonumber(Config.Player and Config.Player.SprintSpeedMultiplier) or 2.5)

local isSprintHeld = false
local humanoid = nil
local normalWalkSpeed = 16
local isApplyingSprintSpeed = false
local walkSpeedConnection = nil

local function applySpeed()
	if not humanoid then
		return
	end

	local targetSpeed = normalWalkSpeed
	if isSprintHeld then
		targetSpeed *= sprintMultiplier
	end

	if math.abs(humanoid.WalkSpeed - targetSpeed) < 0.01 then
		return
	end

	isApplyingSprintSpeed = true
	humanoid.WalkSpeed = targetSpeed
	isApplyingSprintSpeed = false
end

local function onWalkSpeedChanged()
	if not humanoid then
		return
	end
	if isApplyingSprintSpeed then
		return
	end

	local currentWalkSpeed = humanoid.WalkSpeed
	if isSprintHeld then
		local expectedSprintSpeed = normalWalkSpeed * sprintMultiplier
		if math.abs(currentWalkSpeed - expectedSprintSpeed) < 0.01 then
			return
		end
	end

	normalWalkSpeed = currentWalkSpeed
	applySpeed()
end

local function bindCharacter(character)
	if walkSpeedConnection then
		walkSpeedConnection:Disconnect()
		walkSpeedConnection = nil
	end

	humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	normalWalkSpeed = humanoid.WalkSpeed
	walkSpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(onWalkSpeedChanged)
	applySpeed()
end

local function setSprintHeld(held)
	if isSprintHeld == held then
		return
	end

	isSprintHeld = held
	applySpeed()
end

UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	if inputObject.KeyCode ~= sprintKey then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end

	setSprintHeld(true)
end)

UserInputService.InputEnded:Connect(function(inputObject)
	if inputObject.KeyCode ~= sprintKey then
		return
	end

	setSprintHeld(false)
end)

UserInputService.WindowFocusReleased:Connect(function()
	setSprintHeld(false)
end)

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(bindCharacter)
