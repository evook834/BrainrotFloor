local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local DOT_CURSOR_ICON = "rbxasset://textures/MouseLockedCursor.png"
local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder)
local weaponAimRemote = nil
local weaponFireRemote = nil
if remotesFolder then
	weaponAimRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponAim)
	weaponFireRemote = remotesFolder:WaitForChild(Config.Remotes.WeaponFire)
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

local currentCharacter = nil
local currentTool = nil
local characterConns = {}
local toolConns = {}
local lastAimSentAt = 0
local lastAutoFireAt = -math.huge
local aimUpdateInterval = 0.03
local isPrimaryFireHeld = false
local dualPoseCharacter = nil
local dualPoseLeftShoulder = nil
local dualPoseRightShoulder = nil
local dualPoseLeftShoulders = {}
local dualPoseLeftShoulderState = {}
local dualPoseRightShoulderState = {}
local dualPoseWeaponKey = nil
local dualPoseRenderStepName = string.format("DualWieldPose_%d", player.UserId)
local dualWieldWeaponIds = {}

for _, weaponDef in ipairs((Config.Shop and Config.Shop.Weapons) or {}) do
	if type(weaponDef) == "table" and type(weaponDef.Id) == "string" and weaponDef.Id ~= "" and weaponDef.DualWield == true then
		dualWieldWeaponIds[weaponDef.Id] = true
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
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
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
		return nil, nil, nil
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return nil, nil, nil
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
	if raycastResult then
		hitPosition = raycastResult.Position
	end

	return hitPosition, cameraRay.Direction.Unit, cameraRay.Origin
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
	currentTool = tool
	lastAutoFireAt = -math.huge
	if not currentTool then
		clearDualWieldPose()
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
	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		isPrimaryFireHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		isPrimaryFireHeld = false
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

	local showCrosshair = true
	local shopOpen = isShopOpen()

	if currentCharacter then
		local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health <= 0 then
				showCrosshair = false
			end
		end
	end

	UserInputService.MouseIconEnabled = true
	if mouse and mouse.Icon ~= DOT_CURSOR_ICON then
		mouse.Icon = DOT_CURSOR_ICON
	end

	root.Visible = showCrosshair and not shopOpen
end)
