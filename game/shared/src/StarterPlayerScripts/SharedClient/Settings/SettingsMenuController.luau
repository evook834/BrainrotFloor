local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local SharedClient = script.Parent.Parent
local FriendSystem = require(SharedClient:WaitForChild("Friends"):WaitForChild("FriendSystem"))
local PlayerNameplates = require(SharedClient:WaitForChild("Friends"):WaitForChild("PlayerNameplates"))
local SettingsMenuUi = require(script.Parent:WaitForChild("SettingsMenuUi"))

type View = any

type SettingsState = {
	musicVolume: number,
	musicMuted: boolean,
	sfxVolume: number,
	sfxMuted: boolean,
	hudScale: number,
	hudPositions: { [string]: any },
}

type RunOptions = {
	hudMoveModeAttribute: string?,
	canReturnToLobby: boolean?,
}

type Subcontroller = {
	destroy: ((self: Subcontroller) -> ())?,
}

type Session = {
	view: View,
	connections: { RBXScriptConnection },
	subcontrollers: { [string]: Subcontroller },
	settingsState: SettingsState,
}

local activeSession: Session? = nil

local function openFriendSystem(view: View)
	view.panel.Visible = false
	FriendSystem.open()
end

local function setActiveTab(view: View, tabName: "Audio" | "Gameplay")
	local audioActive = tabName == "Audio"
	view.audioPage.Visible = audioActive
	view.gameplayPage.Visible = not audioActive

	if audioActive then
		view.audioTabButton.BackgroundColor3 = Color3.fromRGB(52, 70, 96)
		view.audioTabButton.TextColor3 = Color3.fromRGB(240, 246, 255)
		view.gameplayTabButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
		view.gameplayTabButton.TextColor3 = Color3.fromRGB(225, 233, 245)
	else
		view.audioTabButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
		view.audioTabButton.TextColor3 = Color3.fromRGB(225, 233, 245)
		view.gameplayTabButton.BackgroundColor3 = Color3.fromRGB(52, 70, 96)
		view.gameplayTabButton.TextColor3 = Color3.fromRGB(240, 246, 255)
	end
end

local function togglePanel(session: Session)
	local panel = session.view.panel
	panel.Visible = not panel.Visible
	if panel.Visible then
		setActiveTab(session.view, "Audio")
	end
end

local function tryCreateSubcontroller(
	moduleName: string,
	view: View,
	options: RunOptions,
	settingsState: SettingsState
): Subcontroller?
	local moduleScript = script.Parent:FindFirstChild(moduleName)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end

	local ok, loadedModule = pcall(require, moduleScript)
	if not ok or type(loadedModule) ~= "table" or type(loadedModule.new) ~= "function" then
		return nil
	end

	local createdOk, createdController = pcall(function()
		return loadedModule.new({
			view = view,
			options = options,
			settingsState = settingsState,
		})
	end)
	if not createdOk or type(createdController) ~= "table" then
		return nil
	end

	return createdController
end

local function constructSubcontrollers(view: View, options: RunOptions): (SettingsState, { [string]: Subcontroller })
	local settingsState: SettingsState = {
		musicVolume = 1,
		musicMuted = false,
		sfxVolume = 1,
		sfxMuted = false,
		hudScale = 1,
		hudPositions = {},
	}

	return settingsState, {
		audio = tryCreateSubcontroller("SettingsAudioController", view, options, settingsState),
		hudLayout = tryCreateSubcontroller("SettingsHudLayoutController", view, options, settingsState),
		visibility = tryCreateSubcontroller("SettingsVisibilityController", view, options, settingsState),
		returnToLobby = tryCreateSubcontroller("SettingsReturnToLobbyController", view, options, settingsState),
	}
end

local function resolveRemote(remotesFolder: Instance?, remoteName: string, className: string)
	if not remotesFolder then
		return nil
	end

	local candidate = remotesFolder:FindFirstChild(remoteName)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	candidate = remotesFolder:WaitForChild(remoteName, 15)
	if candidate and candidate:IsA(className) then
		return candidate
	end

	return nil
end

local function loadSettingsFromServer(session: Session)
	local remotesFolder = ReplicatedStorage:FindFirstChild("Shared")
	if not remotesFolder or not remotesFolder:IsA("Folder") then
		return
	end

	local gameConfigModule = remotesFolder:FindFirstChild("GameConfig")
	if not gameConfigModule or not gameConfigModule:IsA("ModuleScript") then
		return
	end

	local okConfig, Config = pcall(require, gameConfigModule)
	if not okConfig or type(Config) ~= "table" or not Config.Remotes then
		return
	end

	local sharedRemotesFolder = ReplicatedStorage:FindFirstChild(Config.Remotes.Folder)
	if not sharedRemotesFolder or not sharedRemotesFolder:IsA("Folder") then
		return
	end

	local settingsGetFunction = resolveRemote(sharedRemotesFolder, Config.Remotes.SettingsGet, "RemoteFunction")
	if not settingsGetFunction then
		return
	end

	local ok, response = pcall(function()
		return settingsGetFunction:InvokeServer()
	end)
	if not ok or type(response) ~= "table" or response.success ~= true then
		return
	end

	local loadedSettings = response.settings
	if type(loadedSettings) ~= "table" then
		return
	end

	local audioController = session.subcontrollers.audio
	local hudController = session.subcontrollers.hudLayout

	local loadedAudio = loadedSettings.audio
	if loadedAudio then
		if audioController and type((audioController :: any).applyLoadedAudioSettings) == "function" then
			(audioController :: any).applyLoadedAudioSettings(loadedAudio)
		else
			session.settingsState.musicVolume = math.clamp(tonumber(loadedAudio.musicVolume) or session.settingsState.musicVolume, 0, 1)
			session.settingsState.musicMuted = loadedAudio.musicMuted == true
			session.settingsState.sfxVolume = math.clamp(tonumber(loadedAudio.sfxVolume) or session.settingsState.sfxVolume, 0, 1)
			session.settingsState.sfxMuted = loadedAudio.sfxMuted == true
		end
	end

	local loadedHud = loadedSettings.hud
	if loadedHud then
		if hudController and type((hudController :: any).applyLoadedHudSettings) == "function" then
			(hudController :: any).applyLoadedHudSettings(loadedHud)
		else
			session.settingsState.hudScale = math.clamp(tonumber(loadedHud.scale) or session.settingsState.hudScale, 0.6, 1.45)
			if type(loadedHud.positions) == "table" then
				session.settingsState.hudPositions = loadedHud.positions
			end
		end
	end
end

local function teardownSession(session: Session)
	for _, connection in ipairs(session.connections) do
		connection:Disconnect()
	end

	for _, controller in pairs(session.subcontrollers) do
		if controller and type(controller.destroy) == "function" then
			controller:destroy()
		end
	end
end

local function run(options: RunOptions?)
	local resolvedOptions: RunOptions = (options or {}) :: any

	if activeSession then
		teardownSession(activeSession)
		activeSession = nil
	end

	local view = SettingsMenuUi.build()
	local settingsState, subcontrollers = constructSubcontrollers(view, resolvedOptions)
	local session: Session = {
		view = view,
		connections = {},
		subcontrollers = subcontrollers,
		settingsState = settingsState,
	}
	activeSession = session

	FriendSystem.start()
	PlayerNameplates.run({
		interactive = true,
	})

	table.insert(session.connections, view.launcherGear.Activated:Connect(function()
		togglePanel(session)
	end))

	table.insert(session.connections, view.friendLauncherButton.Activated:Connect(function()
		openFriendSystem(view)
	end))

	table.insert(session.connections, view.panelClose.Activated:Connect(function()
		view.panel.Visible = false
	end))

	table.insert(session.connections, view.audioTabButton.Activated:Connect(function()
		setActiveTab(view, "Audio")
	end))

	table.insert(session.connections, view.gameplayTabButton.Activated:Connect(function()
		setActiveTab(view, "Gameplay")
	end))

	-- Load settings from server (audio + HUD) and let subcontrollers apply them
	loadSettingsFromServer(session)

	view.panel.Visible = false
	setActiveTab(view, "Audio")
end

return {
	run = run,
}
