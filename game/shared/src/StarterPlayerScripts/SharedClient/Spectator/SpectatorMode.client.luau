local Camera = game:GetService("Camera")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local DEFAULT_CAMERA_TYPE = Enum.CameraType.Custom

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
local spectatorRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.SpectatorState)

local isSpectating = false
local livingPlayerUserIds = {}
local targetIndex = 1
local renderConnection = nil
local spectatorGui = nil
local spectatorLabel = nil

local SPECTATE_OFFSET = Vector3.new(0, 2, 8)
local SPECTATE_SMOOTHNESS = 0.15

local function getTargetCharacter()
	if #livingPlayerUserIds == 0 then
		return nil
	end
	local idx = ((targetIndex - 1) % #livingPlayerUserIds) + 1
	local userId = livingPlayerUserIds[idx]
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then
		return nil
	end
	local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return targetPlayer.Character
end

local function getTargetRootPart(character)
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function updateSpectatorCamera()
	if not isSpectating or not camera then
		return
	end
	local character = getTargetCharacter()
	local rootPart = getTargetRootPart(character)
	if not rootPart then
		return
	end
	local targetCf = rootPart.CFrame * CFrame.new(SPECTATE_OFFSET)
	local currentCf = camera.CFrame
	camera.CFrame = currentCf:Lerp(targetCf, 1 - SPECTATE_SMOOTHNESS)
end

local function updateSpectatorLabel()
	if not spectatorLabel then
		return
	end
	local character = getTargetCharacter()
	local name = character and Players:GetPlayerFromCharacter(character)
	name = name and name.Name or "—"
	spectatorLabel.Text = ("Spectating: %s  |  Q / E to switch"):format(name)
end

local function ensureSpectatorGui()
	if spectatorGui and spectatorGui.Parent then
		return
	end
	spectatorGui = Instance.new("ScreenGui")
	spectatorGui.Name = "SpectatorUi"
	spectatorGui.ResetOnSpawn = false
	spectatorGui.DisplayOrder = 20
	spectatorGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "SpectatorFrame"
	frame.Size = UDim2.fromScale(1, 0.08)
	frame.Position = UDim2.fromScale(0, 0.92)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.Parent = spectatorGui

	spectatorLabel = Instance.new("TextLabel")
	spectatorLabel.Name = "Label"
	spectatorLabel.Size = UDim2.fromScale(1, 1)
	spectatorLabel.Position = UDim2.fromScale(0, 0)
	spectatorLabel.BackgroundTransparency = 1
	spectatorLabel.Font = Enum.Font.GothamMedium
	spectatorLabel.TextSize = 18
	spectatorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	spectatorLabel.Text = "Spectating  |  Q / E to switch"
	spectatorLabel.Parent = frame
end

local function startSpectating()
	isSpectating = true
	targetIndex = 1
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	renderConnection = RunService.RenderStepped:Connect(function()
		updateSpectatorCamera()
		updateSpectatorLabel()
	end)
	ensureSpectatorGui()
	spectatorGui.Enabled = true
	updateSpectatorLabel()
end

local function stopSpectating()
	isSpectating = false
	livingPlayerUserIds = {}
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	camera.CameraType = DEFAULT_CAMERA_TYPE
	if spectatorGui then
		spectatorGui.Enabled = false
	end
end

local function cycleTarget(direction)
	if #livingPlayerUserIds <= 1 then
		return
	end
	targetIndex = targetIndex + direction
	if targetIndex < 1 then
		targetIndex = #livingPlayerUserIds
	elseif targetIndex > #livingPlayerUserIds then
		targetIndex = 1
	end
end

local function onSpectatorState(payload)
	if type(payload) ~= "table" then
		return
	end
	local newSpectating = payload.isSpectating == true
	local newLiving = payload.livingPlayerUserIds
	if type(newLiving) == "table" then
		livingPlayerUserIds = newLiving
	end

	if newSpectating then
		if #livingPlayerUserIds > 0 then
			if not isSpectating then
				targetIndex = 1
				startSpectating()
			else
				if targetIndex > #livingPlayerUserIds then
					targetIndex = math.max(1, #livingPlayerUserIds)
				end
			end
		else
			stopSpectating()
		end
	else
		stopSpectating()
	end
end

if spectatorRemote and spectatorRemote:IsA("RemoteEvent") then
	spectatorRemote.OnClientEvent:Connect(onSpectatorState)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not isSpectating or gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		cycleTarget(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleTarget(1)
	end
end)
