-- SpectatorView - Client-side spectator UI management
-- Builds and manages the spectator HUD
--
-- Usage:
--   1. Call SpectatorView.build() to create the UI
--   2. Call SpectatorView.update(targetName, respawnTime?) to update display
--   3. Call SpectatorView.destroy() to clean up

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local spectateOffset = Config.Spectator.CameraOffset
local spectateSmoothness = Config.Spectator.Smoothness

-- Internal state
local spectatorGui = nil
local spectatorLabel = nil
local enabled = false

--============================================================================================--
-- UI Building --------------------------------------------------------------------------------
--============================================================================================--

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
-- UI Updates ---------------------------------------------------------------------------------
--============================================================================================--

local function updateLabel(targetName)
	if not spectatorLabel then
		return
	end
	spectatorLabel.Text = string.format("Spectating: %s  |  Q/E switch, T toggle", targetName)
end

--============================================================================================--
-- Public API ---------------------------------------------------------------------------------
--============================================================================================--

-- Build the spectator UI
function SpectatorView.build()
	ensureSpectatorGui()
	if spectatorGui then
		spectatorGui.Enabled = true
	end
	enabled = true
end

-- Update the spectator label with current target
function SpectatorView.update(targetName, _respawnTime)
	if not enabled then
		return
	end
	updateLabel(targetName)
end

-- Update the camera offset
function SpectatorView.updateCameraOffset(offset)
	if offset then
		spectateOffset = offset
	end
end

-- Get camera settings for use by SpectatorController
function SpectatorView.getCameraSettings()
	return {
		offset = spectateOffset,
		smoothness = spectateSmoothness,
	}
end

-- Cleanup the spectator UI
function SpectatorView.destroy()
	enabled = false
	if spectatorGui then
		spectatorGui.Enabled = false
	end
	-- Don't destroy immediately to avoid flickering
	-- destroySpectatorGui() is called by the controller after mode change
end

-- Completely clean up UI (called when exiting spectator mode)
function SpectatorView.cleanup()
	destroySpectatorGui()
	enabled = false
end

return SpectatorView
