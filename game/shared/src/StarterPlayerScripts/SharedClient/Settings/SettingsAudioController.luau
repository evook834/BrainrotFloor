local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Config = require(sharedFolder:WaitForChild("GameConfig"))

local MUSIC_CHANNEL = "Music"
local SFX_CHANNEL = "Sfx"
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
	musicSliderBackground: Frame,
	musicSliderFill: Frame,
	musicSliderKnob: Frame,
	musicValueLabel: TextLabel,
	musicMinusButton: TextButton,
	musicPlusButton: TextButton,
	musicMuteButton: TextButton,

	sfxSliderBackground: Frame,
	sfxSliderFill: Frame,
	sfxSliderKnob: Frame,
	sfxValueLabel: TextLabel,
	sfxMinusButton: TextButton,
	sfxPlusButton: TextButton,
	sfxMuteButton: TextButton,
}

type InitOptions = {
	view: View,
	settingsState: SettingsState,
}

type SoundState = {
	channel: string,
	baseVolume: number,
	isApplying: boolean,
	connections: { RBXScriptConnection },
}

type SliderController = {
	setValue: (number, boolean?) -> (),
	getValue: () -> number,
}

type Controller = {
	settingsState: SettingsState,
	view: View,
	connections: { RBXScriptConnection },
	trackedSounds: { [Sound]: SoundState },
	settingsSaveToken: number,
	settingsSaveRemote: RemoteEvent?,
	musicSlider: SliderController?,
	sfxSlider: SliderController?,
}

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

local function createSliderController(
	controller: Controller,
	sliderBackground: Frame,
	sliderFill: Frame,
	sliderKnob: Frame,
	valueLabel: TextLabel,
	minusButton: TextButton,
	plusButton: TextButton,
	initialValue: number,
	onChanged: (number) -> ()
): SliderController
	local currentValue = math.clamp(initialValue, 0, 1)
	local isDragging = false

	local function setValue(newValue: number, fireChanged: boolean?)
		currentValue = math.clamp(newValue, 0, 1)
		sliderFill.Size = UDim2.fromScale(currentValue, 1)
		sliderKnob.Position = UDim2.new(currentValue, -6, 0, 0)
		valueLabel.Text = string.format("%d%%", math.floor((currentValue * 100) + 0.5))
		if fireChanged and onChanged then
			onChanged(currentValue)
		end
	end

	local function setFromInputPosition(positionX: number)
		local width = math.max(1, sliderBackground.AbsoluteSize.X)
		local relative = (positionX - sliderBackground.AbsolutePosition.X) / width
		setValue(relative, true)
	end

	table.insert(controller.connections, sliderBackground.InputBegan:Connect(function(inputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		isDragging = true
		setFromInputPosition(inputObject.Position.X)
	end))

	table.insert(controller.connections, UserInputService.InputChanged:Connect(function(inputObject)
		if not isDragging then
			return
		end
		if inputObject.UserInputType ~= Enum.UserInputType.MouseMovement and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setFromInputPosition(inputObject.Position.X)
	end))

	table.insert(controller.connections, UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 and inputObject.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		isDragging = false
	end))

	table.insert(controller.connections, minusButton.Activated:Connect(function()
		setValue(currentValue - 0.05, true)
	end))

	table.insert(controller.connections, plusButton.Activated:Connect(function()
		setValue(currentValue + 0.05, true)
	end))

	setValue(currentValue, false)

	return {
		setValue = setValue,
		getValue = function()
			return currentValue
		end,
	}
end

local SettingsAudioController = {}
SettingsAudioController.__index = SettingsAudioController

function SettingsAudioController:classifySound(sound: Sound): string
	local channel = sound:GetAttribute("AudioChannel")
	if type(channel) == "string" then
		local normalized = string.lower(channel)
		if normalized == "music" then
			return MUSIC_CHANNEL
		end
		if normalized == "sfx" or normalized == "effect" or normalized == "effects" then
			return SFX_CHANNEL
		end
	end

	local group = sound.SoundGroup
	if group then
		local groupName = string.lower(group.Name)
		if string.find(groupName, "music", 1, true) then
			return MUSIC_CHANNEL
		end
		if string.find(groupName, "sfx", 1, true) or string.find(groupName, "effect", 1, true) then
			return SFX_CHANNEL
		end
	end

	local soundName = string.lower(sound.Name)
	if
		string.find(soundName, "music", 1, true)
		or string.find(soundName, "bgm", 1, true)
		or string.find(soundName, "theme", 1, true)
		or string.find(soundName, "song", 1, true)
		or string.find(soundName, "ambient", 1, true)
	then
		return MUSIC_CHANNEL
	end

	return SFX_CHANNEL
end

function SettingsAudioController:getChannelMultiplier(channel: string): number
	if channel == MUSIC_CHANNEL then
		if self.settingsState.musicMuted then
			return 0
		end
		return self.settingsState.musicVolume
	end

	if self.settingsState.sfxMuted then
		return 0
	end
	return self.settingsState.sfxVolume
end

function SettingsAudioController:applySoundState(sound: Sound, soundState: SoundState)
	if not sound.Parent then
		return
	end

	local multiplier = self:getChannelMultiplier(soundState.channel)
	local targetVolume = math.clamp(soundState.baseVolume * multiplier, 0, 10)
	soundState.isApplying = true
	sound.Volume = targetVolume
	soundState.isApplying = false
end

function SettingsAudioController:refreshAllSounds()
	for sound, soundState in pairs(self.trackedSounds) do
		if sound.Parent then
			self:applySoundState(sound, soundState)
		else
			self.trackedSounds[sound] = nil
		end
	end
end

function SettingsAudioController:trackSound(sound: Sound)
	if self.trackedSounds[sound] then
		return
	end

	local soundState: SoundState = {
		channel = self:classifySound(sound),
		baseVolume = math.clamp(sound.Volume, 0, 10),
		isApplying = false,
		connections = {},
	}
	self.trackedSounds[sound] = soundState

	table.insert(soundState.connections, sound:GetPropertyChangedSignal("SoundGroup"):Connect(function()
		soundState.channel = self:classifySound(sound)
		self:applySoundState(sound, soundState)
	end))

	table.insert(soundState.connections, sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if soundState.isApplying then
			return
		end

		local multiplier = self:getChannelMultiplier(soundState.channel)
		if multiplier > 0 then
			soundState.baseVolume = math.clamp(sound.Volume / multiplier, 0, 10)
		else
			soundState.baseVolume = math.clamp(sound.Volume, 0, 10)
		end
		self:applySoundState(sound, soundState)
	end))

	table.insert(soundState.connections, sound.AttributeChanged:Connect(function(attributeName)
		if attributeName ~= "AudioChannel" then
			return
		end
		soundState.channel = self:classifySound(sound)
		self:applySoundState(sound, soundState)
	end))

	table.insert(soundState.connections, sound.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		for _, connection in ipairs(soundState.connections) do
			connection:Disconnect()
		end
		self.trackedSounds[sound] = nil
	end))

	self:applySoundState(sound, soundState)
end

function SettingsAudioController:updateAudioButtons()
	if self.settingsState.musicMuted then
		self.view.musicMuteButton.BackgroundColor3 = Color3.fromRGB(128, 66, 66)
		self.view.musicMuteButton.Text = "Unmute Music"
	else
		self.view.musicMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
		self.view.musicMuteButton.Text = "Mute Music"
	end

	if self.settingsState.sfxMuted then
		self.view.sfxMuteButton.BackgroundColor3 = Color3.fromRGB(128, 66, 66)
		self.view.sfxMuteButton.Text = "Unmute SFX"
	else
		self.view.sfxMuteButton.BackgroundColor3 = Color3.fromRGB(56, 61, 72)
		self.view.sfxMuteButton.Text = "Mute SFX"
	end
end

function SettingsAudioController:queueSettingsSave()
	if not self.settingsSaveRemote then
		return
	end

	self.settingsSaveToken += 1
	local activeToken = self.settingsSaveToken
	task.delay(0.8, function()
		if activeToken ~= self.settingsSaveToken then
			return
		end

		self.settingsSaveRemote:FireServer({
			audio = {
				musicVolume = self.settingsState.musicVolume,
				musicMuted = self.settingsState.musicMuted,
				sfxVolume = self.settingsState.sfxVolume,
				sfxMuted = self.settingsState.sfxMuted,
			},
			hud = {
				scale = self.settingsState.hudScale,
				positions = self.settingsState.hudPositions,
			},
		})
	end)
end

function SettingsAudioController:applyLoadedAudioSettings(loadedAudio: any)
	if type(loadedAudio) ~= "table" then
		return
	end

	self.settingsState.musicVolume = math.clamp(tonumber(loadedAudio.musicVolume) or self.settingsState.musicVolume, 0, 1)
	self.settingsState.musicMuted = loadedAudio.musicMuted == true
	self.settingsState.sfxVolume = math.clamp(tonumber(loadedAudio.sfxVolume) or self.settingsState.sfxVolume, 0, 1)
	self.settingsState.sfxMuted = loadedAudio.sfxMuted == true

	if self.musicSlider then
		self.musicSlider.setValue(self.settingsState.musicVolume, false)
	end
	if self.sfxSlider then
		self.sfxSlider.setValue(self.settingsState.sfxVolume, false)
	end
	self:updateAudioButtons()
	self:refreshAllSounds()
end

function SettingsAudioController:destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	for sound, soundState in pairs(self.trackedSounds) do
		for _, soundConnection in ipairs(soundState.connections) do
			soundConnection:Disconnect()
		end
		self.trackedSounds[sound] = nil
	end
end

local function ensureDefaults(settingsState: SettingsState)
	settingsState.musicVolume = math.clamp(tonumber(settingsState.musicVolume) or 1, 0, 1)
	settingsState.musicMuted = settingsState.musicMuted == true
	settingsState.sfxVolume = math.clamp(tonumber(settingsState.sfxVolume) or 1, 0, 1)
	settingsState.sfxMuted = settingsState.sfxMuted == true
end

function SettingsAudioController.new(init: InitOptions): Controller
	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT_TIMEOUT_SECONDS)
	local settingsSaveRemote = nil
	if remotesFolder then
		settingsSaveRemote = resolveRemote(remotesFolder, Config.Remotes.SettingsSave, "RemoteEvent")
	end

	local self: Controller = setmetatable({
		settingsState = init.settingsState,
		view = init.view,
		connections = {},
		trackedSounds = {},
		settingsSaveToken = 0,
		settingsSaveRemote = settingsSaveRemote,
		musicSlider = nil,
		sfxSlider = nil,
	}, SettingsAudioController)

	ensureDefaults(self.settingsState)

	self.musicSlider = createSliderController(
		self,
		self.view.musicSliderBackground,
		self.view.musicSliderFill,
		self.view.musicSliderKnob,
		self.view.musicValueLabel,
		self.view.musicMinusButton,
		self.view.musicPlusButton,
		self.settingsState.musicVolume,
		function(value)
			self.settingsState.musicVolume = value
			self:refreshAllSounds()
			self:queueSettingsSave()
		end
	)

	self.sfxSlider = createSliderController(
		self,
		self.view.sfxSliderBackground,
		self.view.sfxSliderFill,
		self.view.sfxSliderKnob,
		self.view.sfxValueLabel,
		self.view.sfxMinusButton,
		self.view.sfxPlusButton,
		self.settingsState.sfxVolume,
		function(value)
			self.settingsState.sfxVolume = value
			self:refreshAllSounds()
			self:queueSettingsSave()
		end
	)

	table.insert(self.connections, self.view.musicMuteButton.Activated:Connect(function()
		self.settingsState.musicMuted = not self.settingsState.musicMuted
		self:refreshAllSounds()
		self:updateAudioButtons()
		self:queueSettingsSave()
	end))

	table.insert(self.connections, self.view.sfxMuteButton.Activated:Connect(function()
		self.settingsState.sfxMuted = not self.settingsState.sfxMuted
		self:refreshAllSounds()
		self:updateAudioButtons()
		self:queueSettingsSave()
	end))

	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:trackSound(descendant)
		end
	end

	table.insert(self.connections, game.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			self:trackSound(descendant)
		end
	end))

	self:updateAudioButtons()
	self:refreshAllSounds()

	return self
end

return SettingsAudioController
