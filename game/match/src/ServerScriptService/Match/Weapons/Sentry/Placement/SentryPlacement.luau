--[[
	SentryPlacement — Placement and orientation helpers for sentry models.
	Reference part, pivot CFrame, upright orientation, facing yaw, and rotation offset from weapon def.
]]

local Match = script.Parent.Parent.Parent.Parent
local ModelRootResolver = require(Match.Enemies.ModelRootResolver)

local SentryPlacement = {}

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

function SentryPlacement.alignPivotYawToDirection(pivotCFrame, desiredLookDirection, desiredPosition)
	local pivotPosition = desiredPosition
	if typeof(pivotPosition) ~= "Vector3" then
		pivotPosition = pivotCFrame.Position
	end

	local targetForward = getHorizontalUnitDirection(desiredLookDirection)
	local currentForward = getHorizontalUnitDirection(pivotCFrame.LookVector)
	if not currentForward then
		currentForward = getHorizontalUnitDirection(pivotCFrame.RightVector)
	end

	if not targetForward then
		targetForward = currentForward or Vector3.new(0, 0, -1)
	end

	if not currentForward then
		return CFrame.lookAt(pivotPosition, pivotPosition + targetForward)
	end

	local yawDot = math.clamp(currentForward:Dot(targetForward), -1, 1)
	local yawRadians = math.acos(yawDot)
	if currentForward:Cross(targetForward).Y < 0 then
		yawRadians = -yawRadians
	end

	local baseRotation = pivotCFrame - pivotCFrame.Position
	local yawRotation = CFrame.fromAxisAngle(Vector3.yAxis, yawRadians)
	return CFrame.new(pivotPosition) * yawRotation * baseRotation
end

function SentryPlacement.resolveSentryPlacementReferencePart(sentryModel)
	if not sentryModel or not sentryModel:IsA("Model") then
		return nil
	end

	local handle = sentryModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return ModelRootResolver.resolveRootPart(sentryModel)
end

function SentryPlacement.resolveSentryPlacementPivotCFrame(sentryModel, referencePlacementCFrame)
	local referencePart = SentryPlacement.resolveSentryPlacementReferencePart(sentryModel)
	if not referencePart then
		return referencePlacementCFrame
	end

	local currentPivot = sentryModel:GetPivot()
	local referenceToPivot = referencePart.CFrame:ToObjectSpace(currentPivot)
	return referencePlacementCFrame * referenceToPivot
end

local function resolveSentryPlacementRotationOffsetCFrame(weaponDef)
	if type(weaponDef) ~= "table" then
		return CFrame.new()
	end

	local rotationDeg = weaponDef.TurretPlacementRotationDeg
	if typeof(rotationDeg) ~= "Vector3" then
		return CFrame.new()
	end

	-- Apply yaw first so large flip corrections (for upside-down templates) do not introduce
	-- an unintended sideways lean when creators tune the placement angles by hand.
	local yaw = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(rotationDeg.Y))
	local pitch = CFrame.fromAxisAngle(Vector3.xAxis, math.rad(rotationDeg.X))
	local roll = CFrame.fromAxisAngle(Vector3.zAxis, math.rad(rotationDeg.Z))
	return yaw * pitch * roll
end

local function resolveSentryPlacementFacingOffsetCFrame(weaponDef)
	if type(weaponDef) ~= "table" then
		return CFrame.new()
	end

	local facingYawDeg = tonumber(weaponDef.TurretPlacementFacingYawDeg)
	if type(facingYawDeg) ~= "number" then
		return CFrame.new()
	end

	return CFrame.fromAxisAngle(Vector3.yAxis, math.rad(facingYawDeg))
end

local function resolveSentryPlacementPositionOffsetCFrame(weaponDef)
	if type(weaponDef) ~= "table" then
		return CFrame.new()
	end

	local positionOffset = weaponDef.TurretPlacementPositionOffset
	if typeof(positionOffset) ~= "Vector3" then
		return CFrame.new()
	end

	return CFrame.new(positionOffset)
end

function SentryPlacement.applySentryPlacementRotationOffset(referencePlacementCFrame, weaponDef)
	return referencePlacementCFrame * resolveSentryPlacementRotationOffsetCFrame(weaponDef)
end

function SentryPlacement.applySentryPlacementFacingOffset(referencePlacementCFrame, weaponDef)
	return referencePlacementCFrame * resolveSentryPlacementFacingOffsetCFrame(weaponDef)
end

function SentryPlacement.applySentryPlacementPositionOffset(referencePlacementCFrame, weaponDef)
	return referencePlacementCFrame * resolveSentryPlacementPositionOffsetCFrame(weaponDef)
end

function SentryPlacement.resolveUprightSentryReferencePlacementCFrame(
	sentryModel,
	referencePlacementCFrame,
	desiredLookDirection,
	weaponDef
)
	local desiredFlatLook = getHorizontalUnitDirection(desiredLookDirection)
	local forwardAxis = referencePlacementCFrame.LookVector
	local rightAxis = referencePlacementCFrame.RightVector

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
		candidateReferencePlacementCFrame =
			SentryPlacement.applySentryPlacementFacingOffset(candidateReferencePlacementCFrame, weaponDef)
		local candidatePivotCFrame =
			SentryPlacement.resolveSentryPlacementPivotCFrame(sentryModel, candidateReferencePlacementCFrame)
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

return SentryPlacement
