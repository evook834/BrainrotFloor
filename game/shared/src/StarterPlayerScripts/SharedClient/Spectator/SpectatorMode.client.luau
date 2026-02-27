-- SpectatorMode - Client-side spectator system for dead players
-- Enters spectating mode when player dies, allows cycling between living players
-- Usage: Automatically activated when player dies (via SpectatorState remote)

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
local spectatorRequestRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.SpectatorRequest)
local waveRemote = remotesFolder and remotesFolder:FindFirstChild(Config.Remotes.WaveState)

-- Internal state
local isSpectating = false
local livingPlayerUserIds = {}
local targetIndex = 1
local renderConnection = nil
local spectatorGui = nil
local spectatorLabel = nil

-- Config constants
local SPECTATE_OFFSET = Config.Spectator.CameraOffset
local SPECTATE_SMOOTHNESS = Config.Spectator.Smoothness

-- Respawn timing
local respawnTime = 0
local countdownConnection = nil

--============================================================================================--
-- Target Management --------------------------------------------------------------------------
--============================================================================================--

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

local function findValidTarget()
	if #livingPlayerUserIds == 0 then
		return nil
	end
	local originalIndex = targetIndex
	local attempts = 0
	while attempts < #livingPlayerUserIds do
		attempts = attempts + 1
		local character = getTargetCharacter()
		if character then
			return character
		end
		cycleTarget(1)
	end
	return nil
end

local function getTargetRootPart(character)
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

--============================================================================================--
-- Camera Control -----------------------------------------------------------------------------
--============================================================================================--

local function updateSpectatorCamera()
	if not isSpectating or not camera then
		return
	end

	-- Get current target
	local character = getTargetCharacter()
	local rootPart = getTargetRootPart(character)

	-- If current target is invalid, find a valid one
	if not rootPart then
		character = findValidTarget()
		rootPart = getTargetRootPart(character)
		if not rootPart then
			return
		end
	end

	-- Calculate new camera position with offset
	local targetCf = rootPart.CFrame * CFrame.new(SPECTATE_OFFSET)
	local currentCf = camera.CFrame

	-- Smooth interpolation - use higher smoothness for faster target switching
	-- This prevents camera from getting "stuck" when target changes
	local smoothness = SPECTATE_SMOOTHNESS
	if rootPart ~= getTargetRootPart(getTargetCharacter()) then
		-- Target just changed, use faster interpolation
		smoothness = math.min(smoothness + 0.2, 0.5)
	end

	camera.CFrame = currentCf:Lerp(targetCf, smoothness)
end

--============================================================================================--
-- UI Management ------------------------------------------------------------------------------
--============================================================================================--

local function updateSpectatorLabel()
	if not spectatorLabel then
		return
	end

	-- Get current target name
	local character = getTargetCharacter()
	local name = character and Players:GetPlayerFromCharacter(character)
	name = name and name.Name or "---"

	spectatorLabel.Text = string.format("Spectating: %s  |  Q/E switch, T toggle", name)
end

local function ensureSpectatorGui()
	if spectatorGui and spectatorGui.Parent then
		return
	end

	-- Create ScreenGui
	spectatorGui = Instance.new("ScreenGui")
	spectatorGui.Name = "SpectatorUi"
	spectatorGui.ResetOnSpawn = false
	spectatorGui.DisplayOrder = 20
	spectatorGui.Parent = playerGui

	-- Create main frame
	local frame = Instance.new("Frame")
	frame.Name = "SpectatorFrame"
	frame.Size = UDim2.fromScale(1, 0.08)
	frame.Position = UDim2.fromScale(0, 0.92)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.Parent = spectatorGui

	-- Create label
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

local function destroySpectatorGui()
	if spectatorGui then
		spectatorGui:Destroy()
		spectatorGui = nil
		spectatorLabel = nil
	end
end

--============================================================================================--
-- State Management ---------------------------------------------------------------------------
--============================================================================================--

local function updateSpectatorState()
	updateSpectatorCamera()
	updateSpectatorLabel()
end

local function onRenderStepped()
	updateSpectatorState()

	-- Handle respawn countdown
	if respawnTime > 0 then
		local timeLeft = respawnTime - workspace:GetServerTimeNow()
		if timeLeft <= 0 then
			respawnTime = 0
			if countdownConnection then
				countdownConnection:Disconnect()
				countdownConnection = nil
			end
		end
	end
end

local function startCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
	countdownConnection = RunService.RenderStepped:Connect(onRenderStepped)
end

local function stopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
	respawnTime = 0
end

local function startSpectating()
	if isSpectating then
		return
	end
	isSpectating = true
	targetIndex = 1

	-- Disconnect any existing connection
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	-- Setup camera
	camera.CameraType = Enum.CameraType.Scriptable

	-- Start updates
	startCountdown()
	ensureSpectatorGui()
	if spectatorGui then
		spectatorGui.Enabled = true
	end
	updateSpectatorLabel()
end

local function stopSpectating()
	if not isSpectating then
		return
	end
	isSpectating = false
	livingPlayerUserIds = {}
	targetIndex = 1

	-- Cleanup connections
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	stopCountdown()

	-- Reset camera
	camera.CameraType = DEFAULT_CAMERA_TYPE

	-- Cleanup UI
	if spectatorGui then
		spectatorGui.Enabled = false
	end
end

--============================================================================================--
-- Target Cycling -----------------------------------------------------------------------------
--============================================================================================--

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

	-- Force immediate camera update when target changes
	updateSpectatorCamera()
end

--============================================================================================--
-- Remote Communication -----------------------------------------------------------------------
--============================================================================================--

local function requestSpectatorAction(request)
	if not spectatorRequestRemote or not spectatorRequestRemote:IsA("RemoteFunction") then
		return false, "SpectatorRequest remote not available", nil
	end
	local success, response = pcall(function()
		return spectatorRequestRemote:InvokeServer(request)
	end)
	if not success then
		return false, ("InvokeServer failed: %s"):format(tostring(response)), nil
	end
	if type(response) ~= "table" then
		return false, "Invalid response from server", nil
	end
	return response.success, response.message, response.isSpectating
end

--============================================================================================--
-- Event Handlers -----------------------------------------------------------------------------
--============================================================================================--

local function onSpectatorState(payload)
	if type(payload) ~= "table" then
		return
	end

	-- Parse state
	local newSpectating = payload.isSpectating == true
	local newLiving = payload.livingPlayerUserIds
	if type(newLiving) == "table" then
		livingPlayerUserIds = newLiving
	end

	-- Parse respawn time
	if payload.respawnsAt ~= nil and payload.respawnsAt > 0 then
		respawnTime = payload.respawnsAt
	else
		respawnTime = 0
	end

	-- Apply state changes
	if newSpectating then
		if #livingPlayerUserIds > 0 then
			if not isSpectating then
				targetIndex = 1
				startSpectating()
			else
				-- Adjust target index if needed
				if targetIndex > #livingPlayerUserIds then
					targetIndex = math.max(1, #livingPlayerUserIds)
				end
				startCountdown()
				-- Verify current target is valid
				if not getTargetCharacter() then
					findValidTarget()
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
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		cycleTarget(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycleTarget(1)
	elseif input.KeyCode == Enum.KeyCode.T then
		if isSpectating then
			local success, message = requestSpectatorAction("exitSpectate")
			if not success then
				warn(("Spectator request failed: %s"):format(message or "unknown error"))
			end
		else
			local success, message, isSpectatingResp = requestSpectatorAction("toggleSpectate")
			if not success then
				warn(("Spectator request failed: %s"):format(message or "unknown error"))
			elseif isSpectatingResp == true then
				startSpectating()
			end
		end
	end
end)

local function onWaveState(payload)
	if type(payload) ~= "table" then
		return
	end
	local state = payload.state
	if state == "GameOver" or state == "Won" then
		stopSpectating()
		destroySpectatorGui()
	end
end

if waveRemote and waveRemote:IsA("RemoteEvent") then
	waveRemote.OnClientEvent:Connect(onWaveState)
end
