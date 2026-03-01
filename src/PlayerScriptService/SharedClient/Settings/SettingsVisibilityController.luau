local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SettingsTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("SettingsTypes"))

local UI_HIDDEN_NOTICE_DELAY_SECONDS = 3

type SettingsState = SettingsTypes.SettingsState

type View = {
	gui: ScreenGui,
	panel: Frame,
	fullHideButton: TextButton,
	fullHideStatusLabel: TextLabel,
}

type InitOptions = {
	view: View,
	settingsState: SettingsState,
}

type Controller = {
	view: View,
	settingsState: SettingsState,
	connections: { RBXScriptConnection },
	uiHidden: boolean,
	uiHiddenNoticeToken: number,
	hiddenScreenGuiEnabledStates: { [ScreenGui]: boolean },
	destroy: (self: Controller) -> (),
}

local SettingsVisibilityController = {}
SettingsVisibilityController.__index = SettingsVisibilityController

local function showUiHiddenHintNotification()
	local payload = {
		Title = "UI Hidden",
		Text = "Press F10 to show UI + HUD.",
		Duration = 5,
	}

	for _ = 1, 3 do
		local ok = pcall(function()
			StarterGui:SetCore("SendNotification", payload)
		end)
		if ok then
			return
		end
		task.wait(0.35)
	end
end

function SettingsVisibilityController:setUiHidden(enabled: boolean)
	if self.uiHidden == enabled then
		return
	end

	self.uiHiddenNoticeToken += 1
	local noticeToken = self.uiHiddenNoticeToken
	self.uiHidden = enabled

	if self.uiHidden then
		self.view.panel.Visible = false
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and self.hiddenScreenGuiEnabledStates[child] == nil then
				self.hiddenScreenGuiEnabledStates[child] = child.Enabled
				child.Enabled = false
			end
		end
	else
		for screenGui, wasEnabled in pairs(self.hiddenScreenGuiEnabledStates) do
			if screenGui.Parent and screenGui:IsDescendantOf(playerGui) then
				screenGui.Enabled = wasEnabled == true
			end
			self.hiddenScreenGuiEnabledStates[screenGui] = nil
		end
	end

	if self.uiHidden then
		task.delay(UI_HIDDEN_NOTICE_DELAY_SECONDS, function()
			if noticeToken ~= self.uiHiddenNoticeToken then
				return
			end
			if not self.uiHidden then
				return
			end
			showUiHiddenHintNotification()
		end)
	end

	if self.uiHidden then
		self.view.fullHideButton.BackgroundColor3 = Color3.fromRGB(120, 78, 52)
		self.view.fullHideButton.Text = "Show All UI + HUD"
		self.view.fullHideStatusLabel.Text = "UI hidden. Press F10 to restore."
	else
		self.view.fullHideButton.BackgroundColor3 = Color3.fromRGB(62, 94, 54)
		self.view.fullHideButton.Text = "Hide All UI + HUD"
		self.view.fullHideStatusLabel.Text = "Tip: Press F10 to toggle full UI visibility."
	end
end

function SettingsVisibilityController:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

function SettingsVisibilityController.new(init: InitOptions): Controller
	local self = setmetatable({
		view = init.view,
		settingsState = init.settingsState,
		connections = {},
		uiHidden = false,
		uiHiddenNoticeToken = 0,
		hiddenScreenGuiEnabledStates = {},
	}, SettingsVisibilityController)

	table.insert(self.connections, self.view.fullHideButton.Activated:Connect(function()
		self:setUiHidden(not self.uiHidden)
	end))

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(inputObject, _gameProcessed)
		if inputObject.UserInputType == Enum.UserInputType.Keyboard and inputObject.KeyCode == Enum.KeyCode.F10 then
			self:setUiHidden(not self.uiHidden)
		end
	end))

	-- Initial label/button text
	self:setUiHidden(false)

	return self
end

return SettingsVisibilityController

