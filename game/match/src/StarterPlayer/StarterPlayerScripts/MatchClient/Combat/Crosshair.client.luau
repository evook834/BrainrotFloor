local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local DOT_CURSOR_ICON = "rbxasset://textures/MouseLockedCursor.png"
local DEFAULT_SCOPE_ZOOM_FOV = 18
local HIDE_WEAPON_MODEL_WHILE_SCOPED_IDS = {
	awp = true,
}
local SENTRY_DEPLOYER_CLASS_TOKEN = "sentrydeployer"
local SENTRY_TURRET_FOLDER_NAME = SentryConstants.SENTRY_TURRET_FOLDER_NAME
local WEAPON_EFFECTS_FOLDER_NAME = "WeaponEffects"
local SENTRY_PREVIEW_VALID_COLOR = Color3.fromRGB(90, 240, 135)
local SENTRY_PREVIEW_INVALID_COLOR = Color3.fromRGB(235, 95, 95)
local SENTRY_PREVIEW_PADDING = Vector3.new(0.25, 0.25, 0.25)
local SCOPE_UI_EXEMPT_GUI_NAMES = {
	AmmoHud = true,
}
local SCOPE_CIRCLE_MASK_SEGMENTS = 128
local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local weaponAimRemote = nil
local weaponFireRemote = nil
local weaponReloadRemote = nil
if remotesFolder then
	weaponAimRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponAim)
	weaponFireRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponFire)
	weaponReloadRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponReload)
end

if mouse then
	mouse.Icon = DOT_CURSOR_ICON
end

local gui = Instance.new("ScreenGui")
gui.Name = "CombatCrosshairUi"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 30
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "CrosshairRoot"
root.Size = UDim2.fromOffset(0, 0)
root.Position = UDim2.fromScale(0.5, 0.5)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.BackgroundTransparency = 1
root.Parent = gui

local scopeOverlay = Instance.new("Frame")
scopeOverlay.Name = "ScopeOverlay"
scopeOverlay.Size = UDim2.fromScale(1, 1)
scopeOverlay.Position = UDim2.fromScale(0, 0)
scopeOverlay.BackgroundTransparency = 1
scopeOverlay.Visible = false
scopeOverlay.ZIndex = 5
scopeOverlay.Parent = gui

local scopeMaskTop = Instance.new("Frame")
scopeMaskTop.Name = "MaskTop"
scopeMaskTop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scopeMaskTop.BorderSizePixel = 0
scopeMaskTop.ZIndex = 5
scopeMaskTop.Parent = scopeOverlay

local scopeMaskBottom = Instance.new("Frame")
scopeMaskBottom.Name = "MaskBottom"
scopeMaskBottom.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scopeMaskBottom.BorderSizePixel = 0
scopeMaskBottom.ZIndex = 5
scopeMaskBottom.Parent = scopeOverlay

local scopeMaskLeft = Instance.new("Frame")
scopeMaskLeft.Name = "MaskLeft"
scopeMaskLeft.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scopeMaskLeft.BorderSizePixel = 0
scopeMaskLeft.ZIndex = 5
scopeMaskLeft.Parent = scopeOverlay

local scopeMaskRight = Instance.new("Frame")
scopeMaskRight.Name = "MaskRight"
scopeMaskRight.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scopeMaskRight.BorderSizePixel = 0
scopeMaskRight.ZIndex = 5
scopeMaskRight.Parent = scopeOverlay

local scopeCircleMaskLeftSlices = table.create(SCOPE_CIRCLE_MASK_SEGMENTS)
local scopeCircleMaskRightSlices = table.create(SCOPE_CIRCLE_MASK_SEGMENTS)
for index = 1, SCOPE_CIRCLE_MASK_SEGMENTS do
	local leftSlice = Instance.new("Frame")
	leftSlice.Name = string.format("CircleMaskLeft_%02d", index)
	leftSlice.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	leftSlice.BorderSizePixel = 0
	leftSlice.ZIndex = 5
	leftSlice.Parent = scopeOverlay
	scopeCircleMaskLeftSlices[index] = leftSlice

	local rightSlice = Instance.new("Frame")
	rightSlice.Name = string.format("CircleMaskRight_%02d", index)
	rightSlice.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	rightSlice.BorderSizePixel = 0
	rightSlice.ZIndex = 5
	rightSlice.Parent = scopeOverlay
	scopeCircleMaskRightSlices[index] = rightSlice
end

local scopeCircle = Instance.new("Frame")
scopeCircle.Name = "Circle"
scopeCircle.AnchorPoint = Vector2.new(0.5, 0.5)
scopeCircle.Position = UDim2.fromScale(0.5, 0.5)
scopeCircle.Size = UDim2.fromOffset(360, 360)
scopeCircle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scopeCircle.BackgroundTransparency = 1
scopeCircle.BorderSizePixel = 0
scopeCircle.ZIndex = 6
scopeCircle.Parent = scopeOverlay

local scopeCircleCorner = Instance.new("UICorner")
scopeCircleCorner.CornerRadius = UDim.new(1, 0)
scopeCircleCorner.Parent = scopeCircle

local scopeCircleStroke = Instance.new("UIStroke")
scopeCircleStroke.Color = Color3.fromRGB(28, 28, 28)
scopeCircleStroke.Transparency = 1
scopeCircleStroke.Thickness = 2
scopeCircleStroke.Parent = scopeCircle

local scopeHorizontalLine = Instance.new("Frame")
scopeHorizontalLine.Name = "HorizontalLine"
scopeHorizontalLine.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
scopeHorizontalLine.BorderSizePixel = 0
scopeHorizontalLine.ZIndex = 7
scopeHorizontalLine.Parent = scopeOverlay

local scopeVerticalLine = Instance.new("Frame")
scopeVerticalLine.Name = "VerticalLine"
scopeVerticalLine.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
scopeVerticalLine.BorderSizePixel = 0
scopeVerticalLine.ZIndex = 7
scopeVerticalLine.Parent = scopeOverlay

local scopeCenterDot = Instance.new("Frame")
scopeCenterDot.Name = "CenterDot"
scopeCenterDot.AnchorPoint = Vector2.new(0.5, 0.5)
scopeCenterDot.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
scopeCenterDot.BorderSizePixel = 0
scopeCenterDot.ZIndex = 8
scopeCenterDot.Parent = scopeOverlay

local scopeCenterDotCorner = Instance.new("UICorner")
scopeCenterDotCorner.CornerRadius = UDim.new(1, 0)
scopeCenterDotCorner.Parent = scopeCenterDot

local currentCharacter = nil
local currentTool = nil
local characterConns = {}
local toolConns = {}
local lastAimSentAt = 0
local lastAutoFireAt = -math.huge
local aimUpdateInterval = 0.03
local isPrimaryFireHeld = false
local isSecondaryAimHeld = false
local isScopeActive = false
local defaultCameraFov = nil
local scopedWeaponSettingsById = {}
local hiddenHudGuiStates = setmetatable({}, { __mode = "k" })
local hiddenScopedToolPartStates = setmetatable({}, { __mode = "k" })
local dualPoseCharacter = nil
local dualPoseLeftShoulder = nil
local dualPoseRightShoulder = nil
local dualPoseLeftShoulders = {}
local dualPoseLeftShoulderState = {}
local dualPoseRightShoulderState = {}
local dualPoseWeaponKey = nil
local dualPoseRenderStepName = string.format("DualWieldPose_%d", player.UserId)
local dualWieldWeaponIds = {}
local sentryPlacementPreviewModel = nil
local sentryPlacementPreviewParts = {}
local sentryPlacementPreviewSourceTool = nil
local sentryPlacementPreviewBoundsSize = nil
local sentryPlacementPreviewHighlight = nil

for _, weaponDef in ipairs((Config.Shop and Config.Shop.Weapons) or {}) do
	if type(weaponDef) == "table" and type(weaponDef.Id) == "string" and weaponDef.Id ~= "" then
		if weaponDef.DualWield == true then
			dualWieldWeaponIds[weaponDef.Id] = true
		end

		local isScopedWeapon = weaponDef.Scoped == true
			or weaponDef.Scope == true
			or type(weaponDef.ScopeZoomFov) == "number"
			or type(weaponDef.ScopeOverlayStyle) == "string"
		if isScopedWeapon then
			scopedWeaponSettingsById[weaponDef.Id] = {
				zoomFov = math.clamp(
					tonumber(weaponDef.ScopeZoomFov) or tonumber(weaponDef.ZoomFov) or DEFAULT_SCOPE_ZOOM_FOV,
					8,
					70
				),
				requiresFirstPerson = weaponDef.ScopeRequiresFirstPerson ~= false,
				autoScopeInFirstPerson = weaponDef.AutoScopeInFirstPerson == true,
			}
		end
	end
end

local function disconnectAll(list)
	for _, conn in ipairs(list) do
		conn:Disconnect()
	end
	table.clear(list)
end

local function isRightShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	if motor.Name == "RightShoulder" or motor.Name == "Right Shoulder" then
		return true
	end

	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	local part0Name = string.lower(part0.Name)
	local part1Name = string.lower(part1.Name)
	if not string.find(part1Name, "right", 1, true) then
		return false
	end

	return part0Name == "torso" or part0Name == "uppertorso"
end

local function isLeftShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	if motor.Name == "LeftShoulder" or motor.Name == "Left Shoulder" then
		return true
	end

	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	local part0Name = string.lower(part0.Name)
	local part1Name = string.lower(part1.Name)
	if not string.find(part1Name, "left", 1, true) then
		return false
	end

	return part0Name == "torso" or part0Name == "uppertorso"
end

local function findShoulderMotor(character, wantLeft)
	if not character then
		return nil
	end

	local directName = wantLeft and "LeftShoulder" or "RightShoulder"
	local direct = character:FindFirstChild(directName, true)
	if direct and direct:IsA("Motor6D") then
		return direct
	end

	local legacyName = wantLeft and "Left Shoulder" or "Right Shoulder"
	local legacy = character:FindFirstChild(legacyName, true)
	if legacy and legacy:IsA("Motor6D") then
		return legacy
	end

	for _, descendant in character:GetDescendants() do
		if wantLeft then
			if isLeftShoulderMotor(descendant) then
				return descendant
			end
		elseif isRightShoulderMotor(descendant) then
			return descendant
		end
	end

	return nil
end

local function collectLeftShoulderMotors(character)
	local motors = {}
	if not character then
		return motors
	end

	for _, descendant in character:GetDescendants() do
		if isLeftShoulderMotor(descendant) then
			table.insert(motors, descendant)
		end
	end

	return motors
end

local function findPartByNames(character, names)
	if not character then
		return nil
	end

	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return nil
end

local function getTorsoPart(character)
	return findPartByNames(character, { "UpperTorso", "Torso" })
end

local function isArmLikePartName(nameLower)
	return string.find(nameLower, "arm", 1, true) ~= nil
		or string.find(nameLower, "hand", 1, true) ~= nil
		or string.find(nameLower, "shoulder", 1, true) ~= nil
end

local function isLikelyShoulderBySide(character, motor, wantLeft)
	if not character or not motor or not motor:IsA("Motor6D") then
		return false
	end

	local torso = getTorsoPart(character)
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not torso or not part0 or not part1 then
		return false
	end
	if part0 ~= torso then
		return false
	end

	local p1Local = torso.CFrame:PointToObjectSpace(part1.Position)
	local onWantedSide = wantLeft and p1Local.X < -0.05 or ((not wantLeft) and p1Local.X > 0.05)
	if not onWantedSide then
		return false
	end

	local part1Name = string.lower(part1.Name)
	local motorName = string.lower(motor.Name)
	local armLike = isArmLikePartName(part1Name) or isArmLikePartName(motorName)
	local notLegLike = not string.find(part1Name, "leg", 1, true)
	local notHipLike = not string.find(motorName, "hip", 1, true)
	local upperBodyEnough = p1Local.Y > -0.35
	return armLike and notLegLike and notHipLike and upperBodyEnough
end

local function isR6ShoulderMotor(motor)
	if not motor or not motor:IsA("Motor6D") then
		return false
	end

	if motor.Name == "Left Shoulder" or motor.Name == "Right Shoulder" then
		return true
	end

	local part1 = motor.Part1
	if not part1 then
		return false
	end

	local part1Name = string.lower(part1.Name)
	return part1Name == "left arm" or part1Name == "right arm"
end

local function tryGetNumberProperty(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if not ok or type(value) ~= "number" then
		return nil
	end
	return value
end

local function tryGetCFrameProperty(instance, propertyName)
	local ok, value = pcall(function()
		return instance[propertyName]
	end)
	if not ok or typeof(value) ~= "CFrame" then
		return nil
	end
	return value
end

local function trySetProperty(instance, propertyName, value)
	pcall(function()
		instance[propertyName] = value
	end)
end

local function clearDualWieldPose()
	for _, shoulder in ipairs(dualPoseLeftShoulders) do
		if shoulder and shoulder.Parent then
			trySetProperty(shoulder, "Transform", CFrame.new())

			local saved = dualPoseLeftShoulderState[shoulder]
			if saved then
				if type(saved.desiredAngle) == "number" then
					trySetProperty(shoulder, "DesiredAngle", saved.desiredAngle)
				end
				if type(saved.maxVelocity) == "number" then
					trySetProperty(shoulder, "MaxVelocity", saved.maxVelocity)
				end
				if typeof(saved.c0) == "CFrame" then
					trySetProperty(shoulder, "C0", saved.c0)
				end
			end
		end
	end

	if dualPoseRightShoulder and dualPoseRightShoulder.Parent then
		trySetProperty(dualPoseRightShoulder, "Transform", CFrame.new())

		if dualPoseRightShoulderState then
			if type(dualPoseRightShoulderState.desiredAngle) == "number" then
				trySetProperty(dualPoseRightShoulder, "DesiredAngle", dualPoseRightShoulderState.desiredAngle)
			end
			if type(dualPoseRightShoulderState.maxVelocity) == "number" then
				trySetProperty(dualPoseRightShoulder, "MaxVelocity", dualPoseRightShoulderState.maxVelocity)
			end
			if typeof(dualPoseRightShoulderState.c0) == "CFrame" then
				trySetProperty(dualPoseRightShoulder, "C0", dualPoseRightShoulderState.c0)
			end
		end
	end

	dualPoseCharacter = nil
	dualPoseWeaponKey = nil
	dualPoseLeftShoulder = nil
	dualPoseRightShoulder = nil
	table.clear(dualPoseLeftShoulders)
	table.clear(dualPoseLeftShoulderState)
	table.clear(dualPoseRightShoulderState)
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

local function updateScopeOverlayLayout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local centerX = viewport.X * 0.5
	local centerY = viewport.Y * 0.5
	local diameter = math.floor(math.clamp(math.min(viewport.X, viewport.Y) * 0.76, 240, 980) + 0.5)
	local radius = diameter * 0.5
	local circleTop = centerY - radius
	local circleBottom = centerY + radius
	local circleLeft = centerX - radius
	local circleRight = centerX + radius

	scopeCircle.Size = UDim2.fromOffset(diameter, diameter)
	scopeCircle.Position = UDim2.fromOffset(centerX, centerY)

	scopeMaskTop.Size = UDim2.fromOffset(viewport.X, math.max(0, circleTop))
	scopeMaskTop.Position = UDim2.fromOffset(0, 0)

	scopeMaskBottom.Size = UDim2.fromOffset(viewport.X, math.max(0, viewport.Y - circleBottom))
	scopeMaskBottom.Position = UDim2.fromOffset(0, circleBottom)

	scopeMaskLeft.Size = UDim2.fromOffset(math.max(0, circleLeft), math.max(0, diameter))
	scopeMaskLeft.Position = UDim2.fromOffset(0, circleTop)

	scopeMaskRight.Size = UDim2.fromOffset(math.max(0, viewport.X - circleRight), math.max(0, diameter))
	scopeMaskRight.Position = UDim2.fromOffset(circleRight, circleTop)

	local segmentHeight = diameter / SCOPE_CIRCLE_MASK_SEGMENTS
	for index = 1, SCOPE_CIRCLE_MASK_SEGMENTS do
		local sliceTop = math.floor(circleTop + ((index - 1) * segmentHeight))
		local sliceBottom = math.floor(circleTop + (index * segmentHeight))
		if index == SCOPE_CIRCLE_MASK_SEGMENTS then
			sliceBottom = math.ceil(circleBottom)
		end
		if sliceBottom <= sliceTop then
			sliceBottom = sliceTop + 1
		end

		local sliceHeight = sliceBottom - sliceTop
		local sliceCenterY = sliceTop + (sliceHeight * 0.5)
		local dy = sliceCenterY - centerY
		local visibleHalfWidth = math.sqrt(math.max(0, (radius * radius) - (dy * dy)))
		local leftEdge = centerX - visibleHalfWidth
		local rightEdge = centerX + visibleHalfWidth

		local leftWidth = math.max(0, math.floor(leftEdge))
		local rightX = math.ceil(rightEdge)
		local rightWidth = math.max(0, viewport.X - rightX)

		local leftSlice = scopeCircleMaskLeftSlices[index]
		leftSlice.Size = UDim2.fromOffset(leftWidth, sliceHeight)
		leftSlice.Position = UDim2.fromOffset(0, sliceTop)

		local rightSlice = scopeCircleMaskRightSlices[index]
		rightSlice.Size = UDim2.fromOffset(rightWidth, sliceHeight)
		rightSlice.Position = UDim2.fromOffset(rightX, sliceTop)
	end

	scopeHorizontalLine.Size = UDim2.fromOffset(diameter, 2)
	scopeHorizontalLine.Position = UDim2.fromOffset(circleLeft, centerY - 1)

	scopeVerticalLine.Size = UDim2.fromOffset(2, diameter)
	scopeVerticalLine.Position = UDim2.fromOffset(centerX - 1, circleTop)

	scopeCenterDot.Size = UDim2.fromOffset(6, 6)
	scopeCenterDot.Position = UDim2.fromOffset(centerX, centerY)
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
			if child:IsA("ScreenGui") and child ~= gui and not exempt then
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
			gui.IgnoreGuiInset = true
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
	gui.IgnoreGuiInset = active
	scopeOverlay.Visible = active
	setHudVisibleForScope(active)
	setScopedWeaponModelHidden(active and shouldHideCurrentScopedWeaponModel())
end

local function isCurrentToolDualWield(weaponId)
	if not currentTool then
		return false
	end

	local dualWield = currentTool:GetAttribute("DualWield")
	if type(dualWield) == "boolean" then
		return dualWield
	end

	return type(weaponId) == "string" and dualWieldWeaponIds[weaponId] == true
end

local function shouldApplyDualWieldPose()
	if not currentTool or not currentCharacter then
		return false
	end
	if currentTool.Parent ~= currentCharacter then
		return false
	end

	local weaponId = getCurrentWeaponId()
	if isCurrentToolDualWield(weaponId) then
		return true
	end

	return false
end

local function findShoulderMotorBySide(character, wantLeft)
	if not character then
		return nil
	end

	local bestMotor = nil
	local bestScore = -math.huge
	local torso = getTorsoPart(character)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and isLikelyShoulderBySide(character, descendant, wantLeft) then
			local score = 0
			local motorName = string.lower(descendant.Name)
			local part1Name = descendant.Part1 and string.lower(descendant.Part1.Name) or ""
			if string.find(motorName, "shoulder", 1, true) then
				score += 20
			end
			if string.find(part1Name, "upperarm", 1, true) then
				score += 12
			end
			if string.find(part1Name, "arm", 1, true) then
				score += 8
			end
			if string.find(part1Name, "hand", 1, true) then
				score += 4
			end
			if torso and descendant.Part1 then
				local localPos = torso.CFrame:PointToObjectSpace(descendant.Part1.Position)
				score += localPos.Y * 2
			end

			if score > bestScore then
				bestScore = score
				bestMotor = descendant
			end
		end
	end

	return bestMotor
end

local function collectLeftShoulderMotorsBySide(character)
	local motors = {}
	if not character then
		return motors
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and isLikelyShoulderBySide(character, descendant, true) then
			table.insert(motors, descendant)
		end
	end

	return motors
end

local function collectLeftShoulderMotorsByOppositeSide(character, rightShoulder)
	local motors = {}
	if not character then
		return motors
	end

	local torso = getTorsoPart(character)
	if not torso then
		return motors
	end

	local leftSign = -1
	if rightShoulder and rightShoulder.Part1 then
		local rightLocal = torso.CFrame:PointToObjectSpace(rightShoulder.Part1.Position)
		if math.abs(rightLocal.X) > 0.05 then
			leftSign = if rightLocal.X >= 0 then -1 else 1
		end
	end

	local candidates = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant ~= rightShoulder then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 == torso and part1 then
				local motorName = string.lower(descendant.Name)
				local part1Name = string.lower(part1.Name)
				local armLike = isArmLikePartName(motorName) or isArmLikePartName(part1Name)
				local notLegLike = not string.find(part1Name, "leg", 1, true)
				local notHipLike = not string.find(motorName, "hip", 1, true)
				if armLike and notLegLike and notHipLike then
					local localPos = torso.CFrame:PointToObjectSpace(part1.Position)
					if localPos.Y > -0.45 then
						local sideScore = if (leftSign * localPos.X) > 0.05 then 8 else 0
						local score = sideScore + (math.abs(localPos.X) * 2.5) + localPos.Y
						table.insert(candidates, { motor = descendant, score = score })
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	for index, entry in ipairs(candidates) do
		table.insert(motors, entry.motor)
		if index >= 2 then
			break
		end
	end

	return motors
end

local function applyDualWieldPose()
	if not shouldApplyDualWieldPose() then
		clearDualWieldPose()
		return
	end

	local weaponId = getCurrentWeaponId()
	local isDualWield = isCurrentToolDualWield(weaponId)
	local poseWeaponKey = string.format("%s:%s", if isDualWield then "dual" else "single", weaponId or "")

	if
		dualPoseCharacter ~= currentCharacter
		or dualPoseWeaponKey ~= poseWeaponKey
		or not dualPoseLeftShoulder
		or not dualPoseLeftShoulder.Parent
	then
		clearDualWieldPose()
		dualPoseCharacter = currentCharacter
		dualPoseWeaponKey = poseWeaponKey
		dualPoseRightShoulder = findShoulderMotorBySide(currentCharacter, false) or findShoulderMotor(currentCharacter, false)
		dualPoseLeftShoulder = findShoulderMotorBySide(currentCharacter, true) or findShoulderMotor(currentCharacter, true)
		if not dualPoseLeftShoulder then
			local bySide = collectLeftShoulderMotorsBySide(currentCharacter)
			if #bySide > 0 then
				dualPoseLeftShoulder = bySide[1]
			end
		end
		if not dualPoseLeftShoulder then
			local byName = collectLeftShoulderMotors(currentCharacter)
			if #byName > 0 then
				dualPoseLeftShoulder = byName[1]
			end
		end
		if not dualPoseLeftShoulder then
			local byOpposite = collectLeftShoulderMotorsByOppositeSide(currentCharacter, dualPoseRightShoulder)
			if #byOpposite > 0 then
				dualPoseLeftShoulder = byOpposite[1]
			end
		end

		if dualPoseLeftShoulder then
			dualPoseLeftShoulders = { dualPoseLeftShoulder }
		end
	end

	if #dualPoseLeftShoulders == 0 then
		return
	end

	if not (dualPoseRightShoulder and dualPoseRightShoulder.Parent) then
		dualPoseRightShoulder = findShoulderMotor(currentCharacter, false)
	end

	if dualPoseRightShoulder and dualPoseRightShoulder.Parent and not dualPoseRightShoulderState.c0 then
		dualPoseRightShoulderState = {
			desiredAngle = tryGetNumberProperty(dualPoseRightShoulder, "DesiredAngle"),
			maxVelocity = tryGetNumberProperty(dualPoseRightShoulder, "MaxVelocity"),
			c0 = tryGetCFrameProperty(dualPoseRightShoulder, "C0"),
		}
	end

	local function chooseForwardFallbackTransform(shoulder, baseC0, isR6)
		if not (shoulder and shoulder.Part0 and typeof(baseC0) == "CFrame") then
			return CFrame.Angles(if isR6 then math.rad(-95) else math.rad(-62), 0, 0)
		end

		local candidates = if isR6
			then {
				CFrame.Angles(math.rad(-95), math.rad(-8), math.rad(12)),
				CFrame.Angles(math.rad(-95), math.rad(8), math.rad(-12)),
				CFrame.Angles(math.rad(95), math.rad(-8), math.rad(12)),
				CFrame.Angles(math.rad(95), math.rad(8), math.rad(-12)),
				CFrame.Angles(math.rad(-70), 0, 0),
				CFrame.Angles(math.rad(70), 0, 0),
			}
			else {
				CFrame.Angles(math.rad(-62), math.rad(-14), math.rad(24)),
				CFrame.Angles(math.rad(-62), math.rad(14), math.rad(-24)),
				CFrame.Angles(math.rad(62), math.rad(-14), math.rad(24)),
				CFrame.Angles(math.rad(62), math.rad(14), math.rad(-24)),
				CFrame.Angles(math.rad(-35), 0, 0),
				CFrame.Angles(math.rad(35), 0, 0),
			}

		local part0 = shoulder.Part0
		local c1Inverse = shoulder.C1:Inverse()
		local forward = part0.CFrame.LookVector
		local right = part0.CFrame.RightVector

		local bestTransform = candidates[1]
		local bestScore = -math.huge
		for _, candidate in ipairs(candidates) do
			local predicted = part0.CFrame * (baseC0 * candidate) * c1Inverse
			local forwardScore = predicted.LookVector:Dot(forward) * 2
			local localPos = part0.CFrame:PointToObjectSpace(predicted.Position)
			local sideScore = -localPos.X * 0.6
			local rightPenalty = predicted.LookVector:Dot(right) * 0.3
			local score = forwardScore + sideScore - math.abs(rightPenalty)
			if score > bestScore then
				bestScore = score
				bestTransform = candidate
			end
		end

		return bestTransform
	end

	for _, shoulder in ipairs(dualPoseLeftShoulders) do
		if shoulder and shoulder.Parent then
			if not dualPoseLeftShoulderState[shoulder] then
				dualPoseLeftShoulderState[shoulder] = {
					desiredAngle = tryGetNumberProperty(shoulder, "DesiredAngle"),
					maxVelocity = tryGetNumberProperty(shoulder, "MaxVelocity"),
					c0 = tryGetCFrameProperty(shoulder, "C0"),
				}
			end

			local isR6 = isR6ShoulderMotor(shoulder)
			local saved = dualPoseLeftShoulderState[shoulder]

			if saved and typeof(saved.c0) == "CFrame" then
				if typeof(saved.fallbackTransform) ~= "CFrame" or saved.poseWeaponKey ~= poseWeaponKey then
					saved.poseWeaponKey = poseWeaponKey
					saved.fallbackTransform = chooseForwardFallbackTransform(shoulder, saved.c0, isR6)
				end

				trySetProperty(shoulder, "C0", saved.c0)
				trySetProperty(shoulder, "Transform", saved.fallbackTransform)
			else
				trySetProperty(shoulder, "Transform", CFrame.new())
			end
		end
	end
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

	local maxDistance = 1800
	local raycastResult = workspace:Raycast(cameraRay.Origin, cameraRay.Direction * maxDistance, raycastParams)
	local hitPosition = cameraRay.Origin + cameraRay.Direction * maxDistance
	local hitNormal = nil
	if raycastResult then
		hitPosition = raycastResult.Position
		hitNormal = raycastResult.Normal
	end

	return hitPosition, cameraRay.Direction.Unit, cameraRay.Origin, hitNormal
end

local function getSentryPlacementMaxDistance()
	if not currentTool then
		return 180
	end

	local placementDistance = tonumber(currentTool:GetAttribute("TurretPlacementDistance"))
	if type(placementDistance) == "number" and placementDistance > 0 then
		return placementDistance
	end

	local range = tonumber(currentTool:GetAttribute("Range"))
	if type(range) == "number" and range > 0 then
		return range
	end

	return 180
end

local function getCurrentSentryPlacementData()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil, nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil, nil, nil
	end

	local viewportX, viewportY = getCrosshairViewportPoint()
	local cameraRay = camera:ViewportPointToRay(viewportX, viewportY)
	local cameraDirection = cameraRay.Direction.Unit
	local maxDistance = getSentryPlacementMaxDistance()

	local exclusions = {}
	if currentCharacter then
		table.insert(exclusions, currentCharacter)
	end

	local enemyContainerName = Config.Enemy and Config.Enemy.ContainerName
	if type(enemyContainerName) == "string" and enemyContainerName ~= "" then
		local enemyContainer = workspace:FindFirstChild(enemyContainerName)
		if enemyContainer then
			table.insert(exclusions, enemyContainer)
		end
	end

	local sentryFolder = workspace:FindFirstChild(SENTRY_TURRET_FOLDER_NAME)
	if sentryFolder then
		table.insert(exclusions, sentryFolder)
	end

	local effectsFolder = workspace:FindFirstChild(WEAPON_EFFECTS_FOLDER_NAME)
	if effectsFolder then
		table.insert(exclusions, effectsFolder)
	end
	if sentryPlacementPreviewModel then
		table.insert(exclusions, sentryPlacementPreviewModel)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = exclusions
	raycastParams.IgnoreWater = true

	local longRange = 1800
	local cameraHitResult = workspace:Raycast(cameraRay.Origin, cameraDirection * longRange, raycastParams)
	local targetPosition = cameraRay.Origin + cameraDirection * longRange
	if cameraHitResult then
		targetPosition = cameraHitResult.Position
	end

	local rootPart = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
	local placementOrigin = if rootPart and rootPart:IsA("BasePart")
		then (rootPart.Position + Vector3.new(0, 1.5, 0))
		else cameraRay.Origin
	local toTarget = targetPosition - placementOrigin
	local placementDirection = cameraDirection
	if toTarget.Magnitude > 0.01 then
		placementDirection = toTarget.Unit
	end

	local raycastResult = workspace:Raycast(placementOrigin, placementDirection * maxDistance, raycastParams)
	if not raycastResult then
		return nil, nil, placementDirection
	end

	return raycastResult.Position, raycastResult.Normal, placementDirection
end

local function clearSentryPlacementPreview()
	if sentryPlacementPreviewModel then
		sentryPlacementPreviewModel:Destroy()
	end

	sentryPlacementPreviewModel = nil
	sentryPlacementPreviewHighlight = nil
	sentryPlacementPreviewSourceTool = nil
	sentryPlacementPreviewBoundsSize = nil
	table.clear(sentryPlacementPreviewParts)
end

local function setSentryPlacementPreviewVisible(visible)
	local shouldShow = visible == true
	for _, entry in ipairs(sentryPlacementPreviewParts) do
		local part = entry.part
		if part and part.Parent then
			part.Transparency = if shouldShow then entry.displayTransparency else 1
		end
	end

	if sentryPlacementPreviewHighlight then
		sentryPlacementPreviewHighlight.Enabled = shouldShow
	end
end

local function setSentryPlacementPreviewColor(color)
	for _, entry in ipairs(sentryPlacementPreviewParts) do
		local part = entry.part
		if part and part.Parent then
			part.Color = color
		end
	end

	if sentryPlacementPreviewHighlight then
		sentryPlacementPreviewHighlight.FillColor = color
		sentryPlacementPreviewHighlight.OutlineColor = color
	end
end

local function isSentryPreviewSourcePart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if part.Name == "Handle" then
		return false
	end

	return part.Transparency < 0.995
end

local function resolveCurrentSentryPlacementRotationOffsetCFrame()
	if not currentTool then
		return CFrame.new()
	end

	local rotationDeg = currentTool:GetAttribute("TurretPlacementRotationDeg")
	if typeof(rotationDeg) ~= "Vector3" then
		return CFrame.new()
	end

	return CFrame.Angles(
		math.rad(rotationDeg.X),
		math.rad(rotationDeg.Y),
		math.rad(rotationDeg.Z)
	)
end

local function ensureSentryPlacementPreviewModel()
	if not currentTool then
		clearSentryPlacementPreview()
		return false
	end

	if sentryPlacementPreviewModel and sentryPlacementPreviewModel.Parent and sentryPlacementPreviewSourceTool == currentTool then
		return true
	end

	clearSentryPlacementPreview()

	local sourceParts = {}
	local fallbackPart = nil
	local handle = currentTool:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		fallbackPart = handle
	end

	for _, descendant in ipairs(currentTool:GetDescendants()) do
		if isSentryPreviewSourcePart(descendant) then
			table.insert(sourceParts, descendant)
		elseif not fallbackPart and descendant:IsA("BasePart") then
			fallbackPart = descendant
		end
	end

	if #sourceParts == 0 then
		if not fallbackPart then
			return false
		end
		table.insert(sourceParts, fallbackPart)
	end

	local sourceRoot = fallbackPart or sourceParts[1]
	if not sourceRoot then
		return false
	end

	local previewModel = Instance.new("Model")
	previewModel.Name = "SentryPlacementPreview"
	previewModel.Parent = workspace

	for _, sourcePart in ipairs(sourceParts) do
		local clonePart = sourcePart:Clone()
		for _, descendant in ipairs(clonePart:GetDescendants()) do
			if descendant:IsA("JointInstance") or descendant:IsA("Constraint") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end

		clonePart.Anchored = true
		clonePart.CanCollide = false
		clonePart.CanTouch = false
		clonePart.CanQuery = false
		clonePart.CastShadow = false
		clonePart.Transparency = math.clamp(tonumber(sourcePart.Transparency) or 0, 0.2, 0.85)
		clonePart.Parent = previewModel

		table.insert(sentryPlacementPreviewParts, {
			part = clonePart,
			relativeCFrame = sourceRoot.CFrame:ToObjectSpace(sourcePart.CFrame),
			displayTransparency = clonePart.Transparency,
		})
	end

	local ok, _, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok and size then
		sentryPlacementPreviewBoundsSize = Vector3.new(
			math.max(0.2, size.X),
			math.max(0.2, size.Y),
			math.max(0.2, size.Z)
		)
	else
		sentryPlacementPreviewBoundsSize = Vector3.new(3, 3, 3)
	end

	local previewHighlight = Instance.new("Highlight")
	previewHighlight.Name = "PlacementHighlight"
	previewHighlight.Adornee = previewModel
	previewHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	previewHighlight.FillTransparency = 0.62
	previewHighlight.OutlineTransparency = 0.22
	previewHighlight.Enabled = false
	previewHighlight.Parent = previewModel

	sentryPlacementPreviewModel = previewModel
	sentryPlacementPreviewHighlight = previewHighlight
	sentryPlacementPreviewSourceTool = currentTool
	return true
end

local function updateSentryPlacementPreview(show, hitPosition, hitNormal, lookDirection)
	if not show then
		setSentryPlacementPreviewVisible(false)
		return
	end

	if not ensureSentryPlacementPreviewModel() then
		return
	end

	if typeof(hitPosition) ~= "Vector3" or typeof(hitNormal) ~= "Vector3" then
		setSentryPlacementPreviewVisible(false)
		return
	end

	local flatLook = nil
	if typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
		flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	end
	if not flatLook or flatLook.Magnitude <= 0.001 then
		local rootPart = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
		if rootPart then
			flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		else
			flatLook = Vector3.new(0, 0, -1)
		end
	end
	if flatLook.Magnitude <= 0.001 then
		flatLook = Vector3.new(0, 0, -1)
	end

	local boundsSize = sentryPlacementPreviewBoundsSize or Vector3.new(3, 3, 3)
	local placementPosition = hitPosition + Vector3.new(0, (boundsSize.Y * 0.5) + 0.05, 0)
	local placementCFrame = CFrame.lookAt(placementPosition, placementPosition + flatLook.Unit)
	placementCFrame *= resolveCurrentSentryPlacementRotationOffsetCFrame()

	for _, entry in ipairs(sentryPlacementPreviewParts) do
		local part = entry.part
		if part and part.Parent then
			part.CFrame = placementCFrame * entry.relativeCFrame
		end
	end

	local overlaps = {}
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local overlapExclusions = {}
	if currentCharacter then
		table.insert(overlapExclusions, currentCharacter)
	end
	if sentryPlacementPreviewModel then
		table.insert(overlapExclusions, sentryPlacementPreviewModel)
	end
	local effectsFolder = workspace:FindFirstChild(WEAPON_EFFECTS_FOLDER_NAME)
	if effectsFolder then
		table.insert(overlapExclusions, effectsFolder)
	end
	local enemyContainerName = Config.Enemy and Config.Enemy.ContainerName
	if type(enemyContainerName) == "string" and enemyContainerName ~= "" then
		local enemyContainer = workspace:FindFirstChild(enemyContainerName)
		if enemyContainer then
			table.insert(overlapExclusions, enemyContainer)
		end
	end
	overlapParams.FilterDescendantsInstances = overlapExclusions
	overlaps = workspace:GetPartBoundsInBox(placementCFrame, boundsSize + SENTRY_PREVIEW_PADDING, overlapParams)

	local blocked = false
	for _, part in ipairs(overlaps) do
		if part and part.Parent and part.CanCollide then
			blocked = true
			break
		end
	end

	local isPlaceable = hitNormal.Y >= 0.55 and not blocked
	setSentryPlacementPreviewColor(if isPlaceable then SENTRY_PREVIEW_VALID_COLOR else SENTRY_PREVIEW_INVALID_COLOR)
	setSentryPlacementPreviewVisible(true)
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
	if not weaponAimRemote or not currentTool or not currentCharacter then
		return
	end

	local now = os.clock()
	if not forceSend and now - lastAimSentAt < aimUpdateInterval then
		return
	end

	local hitPosition, lookDirection, cameraOrigin = getCurrentAimData()
	if not hitPosition or not lookDirection or not cameraOrigin then
		return
	end

	weaponAimRemote:FireServer(hitPosition, lookDirection, cameraOrigin)
	lastAimSentAt = now
end

local function sendFireRequest()
	if not weaponFireRemote or not currentTool or not currentCharacter then
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

	if weaponAimRemote then
		weaponAimRemote:FireServer(hitPosition, lookDirection, cameraOrigin)
	end
	weaponFireRemote:FireServer(weaponId, hitPosition, lookDirection, cameraOrigin)
end

local function sendReloadRequest()
	if not weaponReloadRemote or not currentTool or not currentCharacter then
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

	weaponReloadRemote:FireServer(weaponId)
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
		clearDualWieldPose()
		clearSentryPlacementPreview()
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
	clearDualWieldPose()

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
	applyDualWieldPose()
end)

RunService.RenderStepped:Connect(function()
	sendAimUpdate(false)
	tryAutoFire()

	local crosshairX, crosshairY = getCrosshairViewportPoint()
	root.Position = UDim2.fromOffset(crosshairX, crosshairY)
	updateScopeOverlayLayout()

	local showCrosshair = true
	local shopOpen = isShopOpen()

	if not isCharacterAlive() then
		showCrosshair = false
	end

	if showCrosshair and not shopOpen and isHoldingSentryDeployerTool() then
		local hitPosition, hitNormal, lookDirection = getCurrentSentryPlacementData()
		updateSentryPlacementPreview(true, hitPosition, hitNormal, lookDirection)
	else
		updateSentryPlacementPreview(false)
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
			targetScopeZoomFov = math.clamp(tonumber(scopedSettings.zoomFov) or DEFAULT_SCOPE_ZOOM_FOV, 8, 70)
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

	root.Visible = showCrosshair and not shopOpen and not isScopeActive
end)
