--[[
	SentryPlacementPreview — Builds and updates the sentry placement preview model (ghost + highlight).
	Used when holding the sentry deployer tool; validates placement and shows valid/invalid color.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)

local Constants = require(script.Parent.CrosshairConstants)

local SENTRY_TURRET_FOLDER_NAME = SentryConstants.SENTRY_TURRET_FOLDER_NAME
local WEAPON_EFFECTS_FOLDER_NAME = Constants.WEAPON_EFFECTS_FOLDER_NAME
local SENTRY_PREVIEW_VALID_COLOR = Constants.SENTRY_PREVIEW_VALID_COLOR
local SENTRY_PREVIEW_INVALID_COLOR = Constants.SENTRY_PREVIEW_INVALID_COLOR
local SENTRY_PREVIEW_PADDING = Constants.SENTRY_PREVIEW_PADDING
local SENTRY_PLACEMENT_DEFAULT_MAX_DISTANCE = Constants.SENTRY_PLACEMENT_DEFAULT_MAX_DISTANCE
local AIM_RAYCAST_MAX_DISTANCE = Constants.AIM_RAYCAST_MAX_DISTANCE
local PREVIEW_TRANSPARENCY_ATTR = "PreviewTransparency"

local function getPlacementMaxDistance(tool)
	if not tool then
		return SENTRY_PLACEMENT_DEFAULT_MAX_DISTANCE
	end
	local placementDistance = tonumber(tool:GetAttribute("TurretPlacementDistance"))
	if type(placementDistance) == "number" and placementDistance > 0 then
		return placementDistance
	end
	local range = tonumber(tool:GetAttribute("Range"))
	if type(range) == "number" and range > 0 then
		return range
	end
	return SENTRY_PLACEMENT_DEFAULT_MAX_DISTANCE
end

local function isSentryPreviewSourcePart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end
	if part.Name == "Handle" then
		return false
	end
	if type(part:GetAttribute(PREVIEW_TRANSPARENCY_ATTR)) == "number" then
		return true
	end
	return part.Transparency < 0.995
end

local function resolvePreviewPartTransparency(part)
	local storedTransparency = part and part:GetAttribute(PREVIEW_TRANSPARENCY_ATTR)
	if type(storedTransparency) == "number" then
		return storedTransparency
	end
	return tonumber(part and part.Transparency) or 0
end

local function buildExclusionList(character, previewModel)
	local exclusions = {}
	if character then
		table.insert(exclusions, character)
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
	if previewModel then
		table.insert(exclusions, previewModel)
	end
	return exclusions
end

local function create()
	local previewModel = nil
	local previewParts = {}
	local previewHighlight = nil
	local sourceTool = nil
	local boundsSize = nil
	local referenceToPivot = nil

	local function clear()
		if previewModel then
			previewModel:Destroy()
		end
		previewModel = nil
		previewHighlight = nil
		sourceTool = nil
		boundsSize = nil
		referenceToPivot = nil
		table.clear(previewParts)
	end

	local function setVisible(visible)
		local shouldShow = visible == true
		for _, entry in ipairs(previewParts) do
			local part = entry.part
			if part and part.Parent then
				part.Transparency = if shouldShow then entry.displayTransparency else 1
			end
		end
		if previewHighlight then
			previewHighlight.Enabled = shouldShow
		end
	end

	local function setColor(color)
		for _, entry in ipairs(previewParts) do
			local part = entry.part
			if part and part.Parent then
				part.Color = color
			end
		end
		if previewHighlight then
			previewHighlight.FillColor = color
			previewHighlight.OutlineColor = color
		end
	end

	local function ensurePreviewModel(tool)
		if not tool then
			clear()
			return false
		end
		if previewModel and previewModel.Parent and sourceTool == tool then
			return true
		end

		clear()

		local sourceParts = {}
		local fallbackPart = nil
		local useBoundsCenterReference = tool:GetAttribute("TurretPlacementReferenceMode") == "BoundsCenter"
		local handle = tool:FindFirstChild("Handle", true)
		if handle and handle:IsA("BasePart") then
			fallbackPart = handle
		end

		for _, descendant in ipairs(tool:GetDescendants()) do
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

		local model = Instance.new("Model")
		model.Name = "SentryPlacementPreview"
		model.Parent = workspace

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
			clonePart.Transparency = math.clamp(resolvePreviewPartTransparency(sourcePart), 0.2, 0.85)
			clonePart.Parent = model

			table.insert(previewParts, {
				part = clonePart,
				relativeCFrame = sourceRoot.CFrame:ToObjectSpace(sourcePart.CFrame),
				displayTransparency = clonePart.Transparency,
			})
		end

		local ok, boundsCFrame, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and boundsCFrame and size then
			boundsSize = Vector3.new(
				math.max(0.2, size.X),
				math.max(0.2, size.Y),
				math.max(0.2, size.Z)
			)
			if useBoundsCenterReference then
				for _, entry in ipairs(previewParts) do
					local part = entry.part
					if part and part.Parent then
						entry.relativeCFrame = boundsCFrame:ToObjectSpace(part.CFrame)
					end
				end
			end
		else
			boundsSize = Vector3.new(3, 3, 3)
		end

		local pivotOk, currentPivot = pcall(function()
			return model:GetPivot()
		end)
		if pivotOk and currentPivot then
			if useBoundsCenterReference and ok and boundsCFrame then
				referenceToPivot = boundsCFrame:ToObjectSpace(currentPivot)
			else
				referenceToPivot = sourceRoot.CFrame:ToObjectSpace(currentPivot)
			end
		else
			referenceToPivot = nil
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "PlacementHighlight"
		highlight.Adornee = model
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.62
		highlight.OutlineTransparency = 0.22
		highlight.Enabled = false
		highlight.Parent = model

		previewModel = model
		previewHighlight = highlight
		sourceTool = tool
		return true
	end

	local function getPlacementRotationOffset(tool)
		if not tool then
			return CFrame.new()
		end
		local rotationDeg = tool:GetAttribute("TurretPlacementRotationDeg")
		if typeof(rotationDeg) ~= "Vector3" then
			return CFrame.new()
		end
		local yaw = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(rotationDeg.Y))
		local pitch = CFrame.fromAxisAngle(Vector3.xAxis, math.rad(rotationDeg.X))
		local roll = CFrame.fromAxisAngle(Vector3.zAxis, math.rad(rotationDeg.Z))
		return yaw * pitch * roll
	end

	local function getPlacementFacingOffset(tool)
		if not tool then
			return CFrame.new()
		end
		local facingYawDeg = tonumber(tool:GetAttribute("TurretPlacementFacingYawDeg"))
		if type(facingYawDeg) ~= "number" then
			return CFrame.new()
		end
		return CFrame.fromAxisAngle(Vector3.yAxis, math.rad(facingYawDeg))
	end

	local function getPlacementPositionOffset(tool)
		if not tool then
			return CFrame.new()
		end
		local positionOffset = tool:GetAttribute("TurretPlacementPositionOffset")
		if typeof(positionOffset) ~= "Vector3" then
			return CFrame.new()
		end
		return CFrame.new(positionOffset)
	end

	local function getHorizontalUnitDirection(vector)
		if typeof(vector) ~= "Vector3" then
			return nil
		end

		local horizontal = Vector3.new(vector.X, 0, vector.Z)
		if horizontal.Magnitude <= 0.001 then
			return nil
		end

		return horizontal.Unit
	end

	local function resolveUprightReferencePlacementCFrame(referencePlacementCFrame, desiredLookDirection, tool)
		local forwardAxis = referencePlacementCFrame.LookVector
		local rightAxis = referencePlacementCFrame.RightVector
		local desiredFlatLook = getHorizontalUnitDirection(desiredLookDirection)

		local candidateRotations = {
			CFrame.new(),
			CFrame.fromAxisAngle(forwardAxis, math.pi),
			CFrame.fromAxisAngle(forwardAxis, math.pi * 0.5),
			CFrame.fromAxisAngle(forwardAxis, -math.pi * 0.5),
			CFrame.fromAxisAngle(rightAxis, math.pi * 0.5),
			CFrame.fromAxisAngle(rightAxis, -math.pi * 0.5),
			CFrame.fromAxisAngle(rightAxis, math.pi),
		}

		local bestReferencePlacementCFrame = referencePlacementCFrame
		local bestScore = -math.huge

		for _, rotation in ipairs(candidateRotations) do
			local candidateReferencePlacementCFrame = referencePlacementCFrame * rotation
			candidateReferencePlacementCFrame *= getPlacementFacingOffset(tool)

			local candidatePivotCFrame = candidateReferencePlacementCFrame
			if referenceToPivot then
				candidatePivotCFrame = candidateReferencePlacementCFrame * referenceToPivot
			end

			local upScore = candidatePivotCFrame.UpVector.Y
			local facingScore = 0
			if desiredFlatLook then
				local candidateFlatLook = getHorizontalUnitDirection(candidatePivotCFrame.LookVector)
				if candidateFlatLook then
					facingScore = desiredFlatLook:Dot(candidateFlatLook)
				end
			end

			local totalScore = upScore * 10 + facingScore
			if totalScore > bestScore then
				bestScore = totalScore
				bestReferencePlacementCFrame = candidateReferencePlacementCFrame
			end
		end

		return bestReferencePlacementCFrame
	end

	-- Returns hitPosition, hitNormal, placementDirection (or nils)
	function getPlacementData(viewportX, viewportY, character, tool)
		local camera = workspace.CurrentCamera
		if not camera then
			return nil, nil, nil
		end
		local viewportSize = camera.ViewportSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then
			return nil, nil, nil
		end

		local cameraRay = camera:ViewportPointToRay(viewportX, viewportY)
		local cameraDirection = cameraRay.Direction.Unit
		local maxDistance = getPlacementMaxDistance(tool)
		local exclusions = buildExclusionList(character, previewModel)

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = exclusions
		raycastParams.IgnoreWater = true

		local cameraHitResult = workspace:Raycast(cameraRay.Origin, cameraDirection * AIM_RAYCAST_MAX_DISTANCE, raycastParams)
		local targetPosition = cameraRay.Origin + cameraDirection * AIM_RAYCAST_MAX_DISTANCE
		if cameraHitResult then
			targetPosition = cameraHitResult.Position
		end

		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
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

	function updatePreview(show, hitPosition, hitNormal, lookDirection, character, tool)
		if not show then
			setVisible(false)
			return
		end

		if not ensurePreviewModel(tool) then
			return
		end

		if typeof(hitPosition) ~= "Vector3" or typeof(hitNormal) ~= "Vector3" then
			setVisible(false)
			return
		end

		local flatLook = nil
		if typeof(lookDirection) == "Vector3" and lookDirection.Magnitude > 0.001 then
			flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
		end
		if not flatLook or flatLook.Magnitude <= 0.001 then
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				flatLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
			else
				flatLook = Vector3.new(0, 0, -1)
			end
		end
		if flatLook.Magnitude <= 0.001 then
			flatLook = Vector3.new(0, 0, -1)
		end

		local size = boundsSize or Vector3.new(3, 3, 3)
		local placementPosition = hitPosition + Vector3.new(0, (size.Y * 0.5) + 0.05, 0)
		local placementCFrame = CFrame.lookAt(placementPosition, placementPosition + flatLook.Unit)
		local hasManualPlacementRotation = tool and typeof(tool:GetAttribute("TurretPlacementRotationDeg")) == "Vector3"
		if hasManualPlacementRotation then
			placementCFrame *= getPlacementFacingOffset(tool)
		else
			placementCFrame = resolveUprightReferencePlacementCFrame(placementCFrame, flatLook, tool)
		end
		placementCFrame *= getPlacementRotationOffset(tool)

		for _, entry in ipairs(previewParts) do
			local part = entry.part
			if part and part.Parent then
				part.CFrame = placementCFrame * entry.relativeCFrame
			end
		end

		local positionOffsetCFrame = getPlacementPositionOffset(tool)
		if previewModel and positionOffsetCFrame ~= CFrame.new() then
			local previewPivot = previewModel:GetPivot()
			local pivotSpaceOffset = previewPivot * positionOffsetCFrame * previewPivot:Inverse()
			for _, entry in ipairs(previewParts) do
				local part = entry.part
				if part and part.Parent then
					part.CFrame = pivotSpaceOffset * part.CFrame
				end
			end
		end

		local overlapExclusions = buildExclusionList(character, previewModel)
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = overlapExclusions
		local overlapCFrame = placementCFrame
		local overlapSize = size
		if previewModel then
			local ok, previewBoundsCFrame, previewBoundsSize = pcall(function()
				return previewModel:GetBoundingBox()
			end)
			if ok and previewBoundsCFrame and previewBoundsSize then
				overlapCFrame = previewBoundsCFrame
				overlapSize = previewBoundsSize
			end
		end
		local overlaps = workspace:GetPartBoundsInBox(overlapCFrame, overlapSize + SENTRY_PREVIEW_PADDING, overlapParams)

		local blocked = false
		for _, part in ipairs(overlaps) do
			if part and part.Parent and part.CanCollide then
				blocked = true
				break
			end
		end

		local isPlaceable = hitNormal.Y >= 0.55 and not blocked
		setColor(if isPlaceable then SENTRY_PREVIEW_VALID_COLOR else SENTRY_PREVIEW_INVALID_COLOR)
		setVisible(true)
	end

	return {
		getPlacementData = getPlacementData,
		updatePreview = updatePreview,
		clear = clear,
	}
end

return {
	create = create,
}
