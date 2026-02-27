local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local REMOTE_WAIT_TIMEOUT_SECONDS = 15

type SettingsState = {
	musicVolume: number,
	musicMuted: boolean,
	sfxVolume: number,
	sfxMuted: boolean,
	hudScale: number,
	hudPositions: { [string]: any },
}

type View = {
	panel: Frame,
	returnToLobbyButton: TextButton,
	returnToLobbyStatusLabel: TextLabel,
}

type RunOptions = {
	canReturnToLobby: boolean?,
}

type InitOptions = {
	view: View,
	settingsState: SettingsState,
	options: RunOptions?,
}

type Controller = {
	view: View,
	settingsState: SettingsState,
	connections: { RBXScriptConnection },
	canReturnToLobby: boolean,
	returnToLobbyRemote: RemoteEvent?,
	returnToLobbyRequestInFlight: boolean,
	destroy: (self: Controller) -> (),
}

local SettingsReturnToLobbyController = {}
SettingsReturnToLobbyController.__index = SettingsReturnToLobbyController

local function resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	candidate = remotesFolder:WaitForChild(remoteName, REMOTE_WAIT_TIMEOUT_SECONDS)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

local function resolveOptionalRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

function SettingsReturnToLobbyController:updateReturnToLobbyControls()
	local buttonEnabled = self.canReturnToLobby and self.returnToLobbyRemote ~= nil and not self.returnToLobbyRequestInFlight
	self.view.returnToLobbyButton.Active = buttonEnabled
	self.view.returnToLobbyButton.AutoButtonColor = buttonEnabled

	if self.returnToLobbyRequestInFlight then
		self.view.returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(86, 72, 56)
		self.view.returnToLobbyButton.BackgroundTransparency = 0.12
		self.view.returnToLobbyButton.TextColor3 = Color3.fromRGB(244, 236, 228)
		self.view.returnToLobbyButton.Text = "Returning..."
		self.view.returnToLobbyStatusLabel.Text = "Teleport request sent."
		return
	end

	if self.canReturnToLobby and self.returnToLobbyRemote then
		self.view.returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(98, 64, 64)
		self.view.returnToLobbyButton.BackgroundTransparency = 0
		self.view.returnToLobbyButton.TextColor3 = Color3.fromRGB(246, 238, 238)
		self.view.returnToLobbyButton.Text = "Return to Lobby"
		self.view.returnToLobbyStatusLabel.Text = "Leave the current match and teleport back to lobby."
		return
	end

	self.view.returnToLobbyButton.BackgroundColor3 = Color3.fromRGB(68, 72, 80)
	self.view.returnToLobbyButton.BackgroundTransparency = 0.35
	self.view.returnToLobbyButton.TextColor3 = Color3.fromRGB(188, 194, 202)
	self.view.returnToLobbyButton.Text = "Return to Lobby"
	if self.canReturnToLobby then
		self.view.returnToLobbyStatusLabel.Text = "Return-to-lobby is unavailable right now."
	else
		self.view.returnToLobbyStatusLabel.Text = "You are already in the lobby."
	end
end

function SettingsReturnToLobbyController:resolveReturnToLobbyRemoteAsync(remotesFolder: Instance?, remoteName: string, className: string)
	if not self.canReturnToLobby then
		self.returnToLobbyRemote = nil
		self:updateReturnToLobbyControls()
		return
	end

	self.returnToLobbyRemote = resolveOptionalRemote(remotesFolder, remoteName, className)
	if self.returnToLobbyRemote then
		self:updateReturnToLobbyControls()
		return
	end

	task.spawn(function()
		local remote = resolveRemote(remotesFolder, remoteName, className)
		if not self.canReturnToLobby then
			return
		end

		self.returnToLobbyRemote = remote
		if player.Parent then
			self:updateReturnToLobbyControls()
		end
	end)
end

function SettingsReturnToLobbyController:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

function SettingsReturnToLobbyController.new(init: InitOptions): Controller
	local options = init.options or {}
	local canReturnToLobby = options.canReturnToLobby == true

	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local remotesFolder: Instance? = nil
	local returnToLobbyName: string? = nil

	if sharedFolder and sharedFolder:IsA("Folder") then
		local gameConfigModule = sharedFolder:FindFirstChild("GameConfig")
		if gameConfigModule and gameConfigModule:IsA("ModuleScript") then
			local okConfig, Config = pcall(require, gameConfigModule)
			if okConfig and type(Config) == "table" and Config.Remotes then
				remotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
				returnToLobbyName = Config.Remotes.ReturnToLobby
			end
		end
	end

	local self = setmetatable({
		view = init.view,
		settingsState = init.settingsState,
		connections = {},
		canReturnToLobby = canReturnToLobby,
		returnToLobbyRemote = nil,
		returnToLobbyRequestInFlight = false,
	}, SettingsReturnToLobbyController) :: Controller

	if remotesFolder and returnToLobbyName then
		self:resolveReturnToLobbyRemoteAsync(remotesFolder, returnToLobbyName, "RemoteEvent")
	else
		self:updateReturnToLobbyControls()
	end

	table.insert(self.connections, self.view.returnToLobbyButton.Activated:Connect(function()
		if not self.canReturnToLobby or not self.returnToLobbyRemote or self.returnToLobbyRequestInFlight then
			return
		end

		self.returnToLobbyRequestInFlight = true
		self.view.panel.Visible = false
		self:updateReturnToLobbyControls()
		self.returnToLobbyRemote:FireServer()

		task.delay(2, function()
			if not player.Parent then
				return
			end

			self.returnToLobbyRequestInFlight = false
			self:updateReturnToLobbyControls()
		end)
	end))

	self:updateReturnToLobbyControls()

	return self
end

return SettingsReturnToLobbyController

