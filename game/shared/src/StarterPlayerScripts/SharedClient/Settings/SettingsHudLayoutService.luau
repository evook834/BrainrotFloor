local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudLayoutService = {}

function HudLayoutService.serializePosition(position: UDim2)
	if typeof(position) ~= "UDim2" then
		return nil
	end

	return {
		xScale = position.X.Scale,
		xOffset = math.floor(position.X.Offset + 0.5),
		yScale = position.Y.Scale,
		yOffset = math.floor(position.Y.Offset + 0.5),
	}
end

function HudLayoutService.deserializePosition(rawPosition: any): UDim2?
	if type(rawPosition) ~= "table" then
		return nil
	end

	local xScale = tonumber(rawPosition.xScale)
	local xOffset = tonumber(rawPosition.xOffset)
	local yScale = tonumber(rawPosition.yScale)
	local yOffset = tonumber(rawPosition.yOffset)
	if xScale == nil or xOffset == nil or yScale == nil or yOffset == nil then
		return nil
	end

	return UDim2.new(xScale, math.floor(xOffset + 0.5), yScale, math.floor(yOffset + 0.5))
end

local function getRootHitBox(root: GuiObject): (number, number, number, number)
	local size = root.AbsoluteSize
	local position = root.AbsolutePosition
	if size.X >= 20 and size.Y >= 20 then
		return position.X, position.Y, size.X, size.Y
	end

	local fallbackSize = Vector2.new(28, 28)
	return position.X - (fallbackSize.X * 0.5), position.Y - (fallbackSize.Y * 0.5), fallbackSize.X, fallbackSize.Y
end

local function clampRootPositionToScreen(rawPosition: UDim2, root: GuiObject): UDim2
	local screenSize = playerGui:GetScreenResolution()
	local size = root.AbsoluteSize

	local xScale = rawPosition.X.Scale
	local yScale = rawPosition.Y.Scale
	local xOffset = rawPosition.X.Offset
	local yOffset = rawPosition.Y.Offset

	if xScale == 0 then
		local minX = -size.X + 20
		local maxX = screenSize.X - 20
		xOffset = math.clamp(xOffset, minX, maxX)
	end

	if yScale == 0 then
		local minY = -size.Y + 20
		local maxY = screenSize.Y - 20
		yOffset = math.clamp(yOffset, minY, maxY)
	end

	return UDim2.new(xScale, xOffset, yScale, yOffset)
end

local function isRootActuallyVisible(root: GuiObject): boolean
	if not root.Visible then
		return false
	end

	local current: Instance? = root
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("ScreenGui") then
			return current.Enabled
		end

		current = current.Parent
	end

	return true
end

function HudLayoutService.clampRootPosition(rawPosition: UDim2, root: GuiObject): UDim2
	return clampRootPositionToScreen(rawPosition, root)
end

function HudLayoutService.applyHudRootTransform(root: GuiObject, rootState: any, settingsState: any)
	rootState.applying = true
	root.Position = rootState.rawPosition

	if rootState.useAttributeScale then
		root:SetAttribute("HudScaleMultiplier", settingsState.hudScale)
	elseif rootState.scaleObject then
		rootState.scaleObject.Scale = settingsState.hudScale
	end

	rootState.applying = false
end

function HudLayoutService.applyHudTransforms(trackedHudRoots: { [GuiObject]: any }, settingsState: any)
	for root, rootState in pairs(trackedHudRoots) do
		if root.Parent then
			HudLayoutService.applyHudRootTransform(root, rootState, settingsState)
		else
			trackedHudRoots[root] = nil
		end
	end
end

function HudLayoutService.getTopHudRootAtPosition(trackedHudRoots: { [GuiObject]: any }, screenPos: Vector2): GuiObject?
	local bestRoot = nil
	local bestScore = -math.huge

	for root, rootState in pairs(trackedHudRoots) do
		if not rootState.canDrag then
			continue
		end
		if not root.Parent or not isRootActuallyVisible(root) then
			continue
		end
		local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
		local x, y, width, height = getRootHitBox(root)
		local isInside = screenPos.X >= x and screenPos.X <= (x + width) and screenPos.Y >= y and screenPos.Y <= (y + height)
		if not isInside then
			continue
		end

		local score = (screenGui and screenGui.DisplayOrder or 0) * 1000 + root.ZIndex
		if score > bestScore then
			bestScore = score
			bestRoot = root
		end
	end

	return bestRoot
end

function HudLayoutService.ensureDefaults(settingsState: any, hudScaleMin: number, hudScaleMax: number)
	settingsState.hudScale = math.clamp(tonumber(settingsState.hudScale) or 1, hudScaleMin, hudScaleMax)
	if type(settingsState.hudPositions) ~= "table" then
		settingsState.hudPositions = {}
	end
end

return HudLayoutService

