--[[
	CrosshairController — Orchestrates crosshair UI, scope overlay, aim/fire/reload remotes,
	dual-wield pose, and sentry placement preview. No UI tree building; delegates to CrosshairView and subsystems.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Constants = require(script.Parent.CrosshairConstants)
local Remotes = require(script.Parent.CrosshairRemotes)
local CrosshairView = require(script.Parent.CrosshairView)
local CrosshairWeaponConfig = require(script.Parent.CrosshairWeaponConfig)
local DualWieldPose = require(script.Parent.DualWieldPose)
local SentryPlacementPreview = require(script.Parent.SentryPlacementPreview)

local DOT_CURSOR_ICON = Constants.DOT_CURSOR_ICON
local DEFAULT_SCOPE_ZOOM_FOV = Constants.DEFAULT_SCOPE_ZOOM_FOV
local SCOPE_ZOOM_FOV_MIN = Constants.SCOPE_ZOOM_FOV_MIN
local SCOPE_ZOOM_FOV_MAX = Constants.SCOPE_ZOOM_FOV_MAX
local SCOPE_UI_EXEMPT_GUI_NAMES = Constants.SCOPE_UI_EXEMPT_GUI_NAMES
local HIDE_WEAPON_MODEL_WHILE_SCOPED_IDS = Constants.HIDE_WEAPON_MODEL_WHILE_SCOPED_IDS
local SENTRY_DEPLOYER_CLASS_TOKEN = Constants.SENTRY_DEPLOYER_CLASS_TOKEN
local AIM_UPDATE_INTERVAL = Constants.AIM_UPDATE_INTERVAL
local AIM_RAYCAST_MAX_DISTANCE = Constants.AIM_RAYCAST_MAX_DISTANCE

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local weaponConfig = CrosshairWeaponConfig.buildFromConfig()
local dualWieldWeaponIds = weaponConfig.dualWieldWeaponIds
local scopedWeaponSettingsById = weaponConfig.scopedWeaponSettingsById
local remotes = Remotes.getRemotes()

local view = CrosshairView.build(playerGui)
local dualWieldPose = DualWieldPose.create(dualWieldWeaponIds)
local sentryPreview = SentryPlacementPreview.create()

local currentCharacter = nil
local currentTool = nil
local characterConns = {}
local toolConns = {}
local lastAimSentAt = 0
local lastAutoFireAt = -math.huge
local isPrimaryFireHeld = false
local isSecondaryAimHeld = false
local isScopeActive = false
local defaultCameraFov = nil
local hiddenHudGuiStates = setmetatable({}, { __mode = "k" })
local hiddenScopedToolPartStates = setmetatable({}, { __mode = "k" })

local dualPoseRenderStepName = string.format("DualWieldPose_%d", player.UserId)

local function disconnectAll(list)
	for _, conn in ipairs(list) do
		conn:Disconnect()
	end
	table.clear(list)
end

local function getCurrentWeaponId()
	if not currentTool then
		return nil
	end
	local weaponId = currentTool:GetAttribute("WeaponId")
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	return weaponId
end

local function getCurrentScopedWeaponSettings()
	local weaponId = getCurrentWeaponId()
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	return scopedWeaponSettingsById[weaponId]
end

local function getCrosshairViewportPoint()
	local camera = workspace.CurrentCamera
	if not camera then
		return 0, 0
	end
	local viewportSize = camera.ViewportSize
	local x = viewportSize.X * 0.5
	local y = viewportSize.Y * 0.5
	if not isScopeActive and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		local mousePos = UserInputService:GetMouseLocation()
		local insetTopLeft = GuiService:GetGuiInset()
		x = mousePos.X - insetTopLeft.X
		y = mousePos.Y - insetTopLeft.Y
	end
	x = math.clamp(x, 0, viewportSize.X)
	y = math.clamp(y, 0, viewportSize.Y)
	return x, y
end

local function isCharacterAlive()
	if not currentCharacter then
		return false
	end
	local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function isCharacterInFirstPerson()
	if not currentCharacter then
		return false
	end
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local head = currentCharacter:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	return (camera.CFrame.Position - head.Position).Magnitude <= 1.15
end

local function setHudVisibleForScope(scopeActive)
	if scopeActive == true then
		for _, child in ipairs(playerGui:GetChildren()) do
			local exempt = child:IsA("ScreenGui") and SCOPE_UI_EXEMPT_GUI_NAMES[child.Name] == true
			if child:IsA("ScreenGui") and child ~= view.gui and not exempt then
				if hiddenHudGuiStates[child] == nil then
					hiddenHudGuiStates[child] = child.Enabled == true
				end
				if child.Enabled then
					child.Enabled = false
				end
			end
		end
		return
	end
	for screenGui, wasEnabled in pairs(hiddenHudGuiStates) do
		if screenGui and screenGui.Parent == playerGui then
			screenGui.Enabled = wasEnabled == true
		end
		hiddenHudGuiStates[screenGui] = nil
	end
end

local function shouldHideCurrentScopedWeaponModel()
	if not currentTool then
		return false
	end
	local weaponId = getCurrentWeaponId()
	if type(weaponId) ~= "string" then
		return false
	end
	return HIDE_WEAPON_MODEL_WHILE_SCOPED_IDS[string.lower(weaponId)] == true
end

local function setScopedWeaponModelHidden(hidden)
	if hidden == true then
		if not currentTool then
			return
		end
		for _, descendant in ipairs(currentTool:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if hiddenScopedToolPartStates[descendant] == nil then
					hiddenScopedToolPartStates[descendant] = true
				end
				descendant.LocalTransparencyModifier = 1
			end
		end
		return
	end
	for part in pairs(hiddenScopedToolPartStates) do
		if part and part.Parent then
			part.LocalTransparencyModifier = 0
		end
		hiddenScopedToolPartStates[part] = nil
	end
end

local function setScopeActive(active, zoomFov)
	active = active == true
	if active == isScopeActive then
		if active then
			view.setGuiIgnoreInset(true)
			local camera = workspace.CurrentCamera
			if camera then
				camera.FieldOfView = zoomFov
			end
			setHudVisibleForScope(true)
			setScopedWeaponModelHidden(shouldHideCurrentScopedWeaponModel())
		end
		return
	end

	local camera = workspace.CurrentCamera
	if active then
		if camera then
			defaultCameraFov = camera.FieldOfView
			camera.FieldOfView = zoomFov
		end
	else
		if camera and type(defaultCameraFov) == "number" then
			camera.FieldOfView = defaultCameraFov
		end
		defaultCameraFov = nil
	end

	isScopeActive = active
	view.setGuiIgnoreInset(active)
	view.setScopeOverlayVisible(active)
	setHudVisibleForScope(active)
	setScopedWeaponModelHidden(active and shouldHideCurrentScopedWeaponModel())
end

local function isShopOpen()
	local shopGui = playerGui:FindFirstChild("WeaponShopUi")
	if not shopGui then
		return false
	end
	local shopPanel = shopGui:FindFirstChild("ShopPanel")
	return shopPanel ~= nil and shopPanel:IsA("GuiObject") and shopPanel.Visible
end

local function getCurrentAimData()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil, nil
	end
	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil, nil, nil, nil
	end

	local viewportX, viewportY = getCrosshairViewportPoint()
	local cameraRay = camera:ViewportPointToRay(viewportX, viewportY)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { currentCharacter }
	raycastParams.IgnoreWater = true

	local raycastResult = workspace:Raycast(cameraRay.Origin, cameraRay.Direction * AIM_RAYCAST_MAX_DISTANCE, raycastParams)
	local hitPosition = cameraRay.Origin + cameraRay.Direction * AIM_RAYCAST_MAX_DISTANCE
	local hitNormal = nil
	if raycastResult then
		hitPosition = raycastResult.Position
		hitNormal = raycastResult.Normal
	end

	return hitPosition, cameraRay.Direction.Unit, cameraRay.Origin, hitNormal
end

local function isHoldingSentryDeployerTool()
	if not currentTool or not currentCharacter or currentTool.Parent ~= currentCharacter then
		return false
	end
	local weaponClass = currentTool:GetAttribute("WeaponClass")
	if type(weaponClass) ~= "string" then
		return false
	end
	local token = string.lower(weaponClass):gsub("%s+", "")
	return token == SENTRY_DEPLOYER_CLASS_TOKEN
end

local function sendAimUpdate(forceSend)
	if not remotes.weaponAim or not currentTool or not currentCharacter then
		return
	end
	local now = os.clock()
	if not forceSend and now - lastAimSentAt < AIM_UPDATE_INTERVAL then
		return
	end
	local hitPosition, lookDirection, cameraOrigin = getCurrentAimData()
	if not hitPosition or not lookDirection or not cameraOrigin then
		return
	end
	remotes.weaponAim:FireServer(hitPosition, lookDirection, cameraOrigin)
	lastAimSentAt = now
end

local function sendFireRequest()
	if not remotes.weaponFire or not currentTool or not currentCharacter then
		return
	end
	local weaponId = currentTool:GetAttribute("WeaponId")
	if type(weaponId) ~= "string" or weaponId == "" then
		return
	end
	local hitPosition, lookDirection, cameraOrigin = getCurrentAimData()
	if not hitPosition or not lookDirection or not cameraOrigin then
		return
	end
	if remotes.weaponAim then
		remotes.weaponAim:FireServer(hitPosition, lookDirection, cameraOrigin)
	end
	remotes.weaponFire:FireServer(weaponId, hitPosition, lookDirection, cameraOrigin)
end

local function sendReloadRequest()
	if not remotes.weaponReload or not currentTool or not currentCharacter then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if isShopOpen() then
		return
	end
	local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if currentTool:GetAttribute("IsReloading") == true then
		return
	end
	local weaponId = currentTool:GetAttribute("WeaponId")
	if type(weaponId) ~= "string" or weaponId == "" then
		return
	end
	remotes.weaponReload:FireServer(weaponId)
end

local function isCurrentWeaponAutoFireEnabled()
	if not currentTool then
		return false
	end
	return currentTool:GetAttribute("AutoFire") == true
end

local function tryAutoFire()
	if not isPrimaryFireHeld then
		return
	end
	if not isCurrentWeaponAutoFireEnabled() then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if isShopOpen() then
		return
	end
	if not currentCharacter then
		return
	end
	local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local cooldown = math.max(0.03, tonumber(currentTool:GetAttribute("Cooldown")) or 0.1)
	local now = os.clock()
	if now - lastAutoFireAt < cooldown then
		return
	end
	lastAutoFireAt = now
	sendAimUpdate(true)
	sendFireRequest()
end

local function updateToolConnections(tool)
	disconnectAll(toolConns)
	setScopeActive(false, DEFAULT_SCOPE_ZOOM_FOV)
	currentTool = tool
	lastAutoFireAt = -math.huge
	if not currentTool then
		dualWieldPose.clear()
		sentryPreview.clear()
		return
	end

	table.insert(toolConns, currentTool.Activated:Connect(function()
		lastAutoFireAt = os.clock()
		sendAimUpdate(true)
		sendFireRequest()
	end))

	table.insert(toolConns, currentTool.Destroying:Connect(function()
		if currentTool == tool then
			updateToolConnections(nil)
		end
	end))
end

local function bindCharacter(character)
	disconnectAll(characterConns)
	updateToolConnections(nil)
	currentCharacter = character
	setScopeActive(false, DEFAULT_SCOPE_ZOOM_FOV)
	dualWieldPose.clear()

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			updateToolConnections(child)
			break
		end
	end

	table.insert(characterConns, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			updateToolConnections(child)
		end
	end))

	table.insert(characterConns, character.ChildRemoved:Connect(function(child)
		if child == currentTool then
			updateToolConnections(nil)
		end
	end))
end

local function run()
	if mouse then
		mouse.Icon = DOT_CURSOR_ICON
	end

	if player.Character then
		bindCharacter(player.Character)
	end

	player.CharacterAdded:Connect(bindCharacter)

	UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if gameProcessed then
			return
		end
		if inputObject.KeyCode == Enum.KeyCode.R then
			sendReloadRequest()
			return
		end
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			isPrimaryFireHeld = true
		elseif inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
			isSecondaryAimHeld = true
		end
	end)

	UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			isPrimaryFireHeld = false
		elseif inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
			isSecondaryAimHeld = false
		end
	end)

	RunService:BindToRenderStep(dualPoseRenderStepName, Enum.RenderPriority.Last.Value, function()
		dualWieldPose.apply(currentCharacter, currentTool)
	end)

	RunService.RenderStepped:Connect(function()
		sendAimUpdate(false)
		tryAutoFire()

		local crosshairX, crosshairY = getCrosshairViewportPoint()
		view.setRootPosition(crosshairX, crosshairY)
		view.updateScopeLayout()

		local showCrosshair = true
		local shopOpen = isShopOpen()

		if not isCharacterAlive() then
			showCrosshair = false
		end

		if showCrosshair and not shopOpen and isHoldingSentryDeployerTool() then
			local viewportX, viewportY = getCrosshairViewportPoint()
			local hitPosition, hitNormal, lookDirection = sentryPreview.getPlacementData(viewportX, viewportY, currentCharacter, currentTool)
			sentryPreview.updatePreview(true, hitPosition, hitNormal, lookDirection, currentCharacter, currentTool)
		else
			sentryPreview.updatePreview(false, nil, nil, nil, currentCharacter, currentTool)
		end

		local shouldScope = false
		local targetScopeZoomFov = DEFAULT_SCOPE_ZOOM_FOV
		local scopedSettings = getCurrentScopedWeaponSettings()
		if scopedSettings and currentTool and currentCharacter and currentTool.Parent == currentCharacter then
			local inFirstPerson = isCharacterInFirstPerson()
			local meetsViewRequirement = inFirstPerson or scopedSettings.requiresFirstPerson ~= true
			local wantsScope = isSecondaryAimHeld
			if not wantsScope and scopedSettings.autoScopeInFirstPerson == true and inFirstPerson then
				wantsScope = true
			end

			if
				wantsScope
				and meetsViewRequirement
				and not shopOpen
				and not UserInputService:GetFocusedTextBox()
				and isCharacterAlive()
			then
				shouldScope = true
				targetScopeZoomFov = math.clamp(tonumber(scopedSettings.zoomFov) or DEFAULT_SCOPE_ZOOM_FOV, SCOPE_ZOOM_FOV_MIN, SCOPE_ZOOM_FOV_MAX)
			end
		end

		setScopeActive(shouldScope, targetScopeZoomFov)

		local shouldShowMouseIcon = not isScopeActive
		UserInputService.MouseIconEnabled = shouldShowMouseIcon
		if mouse then
			local desiredCursor = if shouldShowMouseIcon then DOT_CURSOR_ICON else ""
			if mouse.Icon ~= desiredCursor then
				mouse.Icon = desiredCursor
			end
		end

		view.setRootVisible(showCrosshair and not shopOpen and not isScopeActive)
	end)
end

return {
	run = run,
}
