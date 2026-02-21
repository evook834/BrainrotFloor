local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local waveStateRemote = remotesFolder:WaitForChild(Config.Remotes.WaveState)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WaveHud"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "WaveLabel"
label.Size = UDim2.fromOffset(380, 56)
label.Position = UDim2.fromScale(0.5, 0.06)
label.AnchorPoint = Vector2.new(0.5, 0)
label.BackgroundTransparency = 0.25
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.TextColor3 = Color3.fromRGB(235, 235, 235)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = "Waiting for wave..."
label.Parent = gui

local function formatWaveState(payload)
	local wave = payload.wave or 0
	local state = payload.state or "Unknown"

	if state == "Preparing" then
		return string.format("Wave %d starts in %ds", wave, payload.intermission or 0)
	end

	if state == "InProgress" then
		return string.format("Wave %d in progress | Enemies: %d", wave, payload.enemies or 0)
	end

	if state == "Cleared" then
		return string.format("Wave %d cleared", wave)
	end

	if state == "Blocked" then
		return "Setup required: add enemy models + spawn points"
	end

	return string.format("Wave %d | %s", wave, state)
end

waveStateRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	label.Text = formatWaveState(payload)
end)
