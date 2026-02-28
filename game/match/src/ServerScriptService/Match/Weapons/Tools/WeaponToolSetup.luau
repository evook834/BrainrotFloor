--[[
	WeaponToolSetup — Tool creation from templates, dual-wield visuals/pose, and template lookup.
	Used by ShopService for createToolFromTemplate, createFallbackWeaponTool, and dual-wield setup.
]]

local WeaponToolSetup = {}
local WeaponTemplateResolver = require(script.Parent.WeaponTemplateResolver)

local function normalizeWeaponToken(value)
	if type(value) ~= "string" then
		return ""
	end
	local token = string.lower(value)
	token = string.gsub(token, "%s+", "")
	return token
end

local function isFlareGunDefinition(weaponDef)
	if type(weaponDef) ~= "table" then
		return false
	end

	for _, value in ipairs({ weaponDef.Id, weaponDef.DisplayName, weaponDef.TemplateName }) do
		local token = normalizeWeaponToken(value)
		local compactToken = string.gsub(token, "[^%w]", "")
		if compactToken ~= "" and string.find(compactToken, "flaregun", 1, true) then
			return true
		end
	end

	return false
end

local function resolveWeaponClass(weaponDef)
	if type(weaponDef) ~= "table" then
		return "Ranged"
	end
	if type(weaponDef.WeaponClass) == "string" and weaponDef.WeaponClass ~= "" then
		return weaponDef.WeaponClass
	end
	if isFlareGunDefinition(weaponDef) then
		return "FlareGun"
	end
	if (weaponDef.Range or 0) <= 12 then
		return "Melee"
	end
	return "Ranged"
end

local function isMeleeWeaponClass(weaponClass)
	local weaponClassToken = normalizeWeaponToken(weaponClass)
	return weaponClassToken == "melee" or weaponClassToken == "sword"
end

local function hasWeldBetween(partA, partB)
	for _, child in partA:GetChildren() do
		if child:IsA("WeldConstraint") then
			if (child.Part0 == partA and child.Part1 == partB) or (child.Part0 == partB and child.Part1 == partA) then
				return true
			end
		end
	end
	return false
end

function WeaponToolSetup.prepareToolParts(tool, handle)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= handle and not hasWeldBetween(handle, descendant) then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = handle
			end
		end
	end
end

function WeaponToolSetup.isDualWieldWeapon(weaponDef)
	if type(weaponDef.DualWield) == "boolean" then
		return weaponDef.DualWield
	end
	return false
end

function WeaponToolSetup.findHandPart(character, isLeft)
	local preferredNames = if isLeft then { "LeftHand", "Left Arm" } else { "RightHand", "Right Arm" }
	for _, name in ipairs(preferredNames) do
		local part = character:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

function WeaponToolSetup.buildOffhandGrip(weaponDef)
	local gripOffset = Vector3.new(-0.3, -0.8, 0)
	local gripRotationDeg = Vector3.new(0, 0, 0)

	if typeof(weaponDef.OffhandGripPositionOffset) == "Vector3" then
		gripOffset += weaponDef.OffhandGripPositionOffset
	elseif typeof(weaponDef.GripPositionOffset) == "Vector3" then
		gripOffset += Vector3.new(-weaponDef.GripPositionOffset.X, weaponDef.GripPositionOffset.Y, weaponDef.GripPositionOffset.Z)
	end

	if typeof(weaponDef.OffhandGripRotationDeg) == "Vector3" then
		gripRotationDeg = weaponDef.OffhandGripRotationDeg
	elseif typeof(weaponDef.GripRotationDeg) == "Vector3" then
		gripRotationDeg = Vector3.new(weaponDef.GripRotationDeg.X, -weaponDef.GripRotationDeg.Y, -weaponDef.GripRotationDeg.Z)
	end

	return CFrame.new(gripOffset)
		* CFrame.Angles(math.rad(gripRotationDeg.X), math.rad(gripRotationDeg.Y), math.rad(gripRotationDeg.Z))
end

function WeaponToolSetup.stopDualWieldArmPose(state)
	if state.offhandPoseConn then
		state.offhandPoseConn:Disconnect()
		state.offhandPoseConn = nil
	end

	if state.offhandLeftShoulder and state.offhandLeftShoulder.Parent then
		state.offhandLeftShoulder.Transform = CFrame.new()
		local leftState = state.offhandLeftShoulderState
		if leftState then
			if typeof(leftState.c0) == "CFrame" then
				state.offhandLeftShoulder.C0 = leftState.c0
			end
			pcall(function()
				if type(leftState.maxVelocity) == "number" then
					state.offhandLeftShoulder.MaxVelocity = leftState.maxVelocity
				end
				if type(leftState.desiredAngle) == "number" then
					state.offhandLeftShoulder.DesiredAngle = leftState.desiredAngle
				end
			end)
		end
	end

	if state.offhandRightShoulder and state.offhandRightShoulder.Parent then
		state.offhandRightShoulder.Transform = CFrame.new()
		local rightState = state.offhandRightShoulderState
		if rightState then
			if typeof(rightState.c0) == "CFrame" then
				state.offhandRightShoulder.C0 = rightState.c0
			end
			pcall(function()
				if type(rightState.maxVelocity) == "number" then
					state.offhandRightShoulder.MaxVelocity = rightState.maxVelocity
				end
				if type(rightState.desiredAngle) == "number" then
					state.offhandRightShoulder.DesiredAngle = rightState.desiredAngle
				end
			end)
		end
	end

	state.offhandLeftShoulder = nil
	state.offhandRightShoulder = nil
	state.offhandLeftShoulderState = nil
	state.offhandRightShoulderState = nil
end

function WeaponToolSetup.startDualWieldArmPose(character, state)
	WeaponToolSetup.stopDualWieldArmPose(state)
	-- Client handles the dual-wield arm pose locally to avoid server/client joint conflicts.
	return
end

function WeaponToolSetup.clearDualWieldOffhand(state)
	WeaponToolSetup.stopDualWieldArmPose(state)

	if state.offhandModel and state.offhandModel.Parent then
		state.offhandModel:Destroy()
	end
	state.offhandModel = nil
	state.offhandRoot = nil
end

function WeaponToolSetup.createDualWieldOffhandVisual(tool, character, handle, weaponDef, state)
	WeaponToolSetup.clearDualWieldOffhand(state)

	if not (tool and tool.Parent == character and character and character:IsA("Model")) then
		return
	end
	if not (handle and handle:IsA("BasePart")) then
		return
	end

	local leftHand = WeaponToolSetup.findHandPart(character, true)
	if not leftHand then
		return
	end
	WeaponToolSetup.startDualWieldArmPose(character, state)

	local sourceParts = {}
	local seen = {}
	local function addSourcePart(part)
		if part and part:IsA("BasePart") and not seen[part] then
			seen[part] = true
			table.insert(sourceParts, part)
		end
	end

	addSourcePart(handle)
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= handle then
			if descendant.Transparency < 0.995 then
				addSourcePart(descendant)
			end
		end
	end

	if #sourceParts == 0 then
		return
	end

	local sourceRoot = handle
	local sourceRootCFrame = sourceRoot.CFrame
	local relativeCFrames = {}
	for _, sourcePart in ipairs(sourceParts) do
		relativeCFrames[sourcePart] = sourceRootCFrame:ToObjectSpace(sourcePart.CFrame)
	end

	local offhandModel = Instance.new("Model")
	offhandModel.Name = "DualWieldOffhand"
	offhandModel.Parent = character

	local sourceToClone = {}
	local offhandRoot = nil
	for _, sourcePart in ipairs(sourceParts) do
		local clonePart = sourcePart:Clone()
		for _, cloneDescendant in clonePart:GetDescendants() do
			if cloneDescendant:IsA("JointInstance") or cloneDescendant:IsA("WeldConstraint") then
				cloneDescendant:Destroy()
			end
		end
		clonePart.Anchored = false
		clonePart.CanCollide = false
		clonePart.CanTouch = false
		clonePart.CanQuery = false
		clonePart.Massless = true
		clonePart.Parent = offhandModel

		sourceToClone[sourcePart] = clonePart
		if sourcePart == sourceRoot then
			offhandRoot = clonePart
		end
	end

	if not offhandRoot then
		offhandModel:Destroy()
		return
	end

	local offhandGrip = WeaponToolSetup.buildOffhandGrip(weaponDef)
	offhandRoot.CFrame = leftHand.CFrame * offhandGrip

	for _, sourcePart in ipairs(sourceParts) do
		if sourcePart ~= sourceRoot then
			local clonePart = sourceToClone[sourcePart]
			clonePart.CFrame = offhandRoot.CFrame * relativeCFrames[sourcePart]

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = offhandRoot
			weld.Part1 = clonePart
			weld.Parent = offhandRoot
		end
	end

	local handWeld = Instance.new("WeldConstraint")
	handWeld.Name = "DualWieldHandWeld"
	handWeld.Part0 = leftHand
	handWeld.Part1 = offhandRoot
	handWeld.Parent = offhandRoot

	state.offhandModel = offhandModel
	state.offhandRoot = offhandRoot
end

function WeaponToolSetup.findShopItemTemplate(weaponDef)
	return WeaponTemplateResolver.findShopItemTemplate(weaponDef)
end

function WeaponToolSetup.buildSentryModelFromTemplate(weaponDef)
	return WeaponTemplateResolver.buildSentryModelFromTemplate(weaponDef)
end

function WeaponToolSetup.createFallbackWeaponTool(weaponDef)
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 2.2)
	handle.Color = weaponDef.Color or Color3.fromRGB(180, 180, 180)
	handle.Material = Enum.Material.Metal
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Parent = tool

	local weaponClass = resolveWeaponClass(weaponDef)
	if isMeleeWeaponClass(weaponClass) then
		handle.Size = Vector3.new(0.7, 0.7, 2.8)
	elseif weaponClass == "FlareGun" then
		handle.Size = Vector3.new(0.85, 0.85, 2.6)
	elseif weaponClass == "Flamethrower" then
		handle.Size = Vector3.new(1.2, 1, 3.4)
	elseif weaponClass == "RPG" then
		handle.Size = Vector3.new(1.3, 1.3, 4.2)
	elseif weaponClass == "GrenadeLauncher" then
		handle.Size = Vector3.new(1.2, 1.2, 3.8)
	elseif (weaponDef.Range or 0) >= 50 then
		handle.Size = Vector3.new(1, 1, 3.2)
	end
	return tool
end

function WeaponToolSetup.createToolFromTemplate(weaponDef)
	return WeaponTemplateResolver.createToolFromTemplate(weaponDef)
end

function WeaponToolSetup.resolveWeaponClass(weaponDef)
	return resolveWeaponClass(weaponDef)
end

function WeaponToolSetup.normalizeWeaponToken(value)
	return normalizeWeaponToken(value)
end

function WeaponToolSetup.isMeleeWeaponClass(weaponClass)
	return isMeleeWeaponClass(weaponClass)
end

return WeaponToolSetup
