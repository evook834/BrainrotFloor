--[[
	CrosshairView — Builds the crosshair UI tree (ScreenGui, root, scope overlay and masks).
	No remotes or game logic; only instance creation and layout updates.
]]

local Constants = require(script.Parent.CrosshairConstants)

local SCOPE_CIRCLE_MASK_SEGMENTS = Constants.SCOPE_CIRCLE_MASK_SEGMENTS

local function buildScopeOverlay(parentGui)
	local scopeOverlay = Instance.new("Frame")
	scopeOverlay.Name = "ScopeOverlay"
	scopeOverlay.Size = UDim2.fromScale(1, 1)
	scopeOverlay.Position = UDim2.fromScale(0, 0)
	scopeOverlay.BackgroundTransparency = 1
	scopeOverlay.Visible = false
	scopeOverlay.ZIndex = 5
	scopeOverlay.Parent = parentGui

	local function createMaskFrame(name)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		f.BorderSizePixel = 0
		f.ZIndex = 5
		f.Parent = scopeOverlay
		return f
	end

	local scopeMaskTop = createMaskFrame("MaskTop")
	local scopeMaskBottom = createMaskFrame("MaskBottom")
	local scopeMaskLeft = createMaskFrame("MaskLeft")
	local scopeMaskRight = createMaskFrame("MaskRight")

	local circleMaskLeftSlices = table.create(SCOPE_CIRCLE_MASK_SEGMENTS)
	local circleMaskRightSlices = table.create(SCOPE_CIRCLE_MASK_SEGMENTS)
	for index = 1, SCOPE_CIRCLE_MASK_SEGMENTS do
		local leftSlice = createMaskFrame(string.format("CircleMaskLeft_%02d", index))
		circleMaskLeftSlices[index] = leftSlice
		local rightSlice = createMaskFrame(string.format("CircleMaskRight_%02d", index))
		circleMaskRightSlices[index] = rightSlice
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

	return {
		overlay = scopeOverlay,
		maskTop = scopeMaskTop,
		maskBottom = scopeMaskBottom,
		maskLeft = scopeMaskLeft,
		maskRight = scopeMaskRight,
		circleMaskLeftSlices = circleMaskLeftSlices,
		circleMaskRightSlices = circleMaskRightSlices,
		circle = scopeCircle,
		horizontalLine = scopeHorizontalLine,
		verticalLine = scopeVerticalLine,
		centerDot = scopeCenterDot,
	}
end

local function applyScopeLayout(scope, viewportX, viewportY)
	if viewportX <= 0 or viewportY <= 0 then
		return
	end

	local centerX = viewportX * 0.5
	local centerY = viewportY * 0.5
	local diameter = math.floor(math.clamp(math.min(viewportX, viewportY) * 0.76, 240, 980) + 0.5)
	local radius = diameter * 0.5
	local circleTop = centerY - radius
	local circleBottom = centerY + radius
	local circleLeft = centerX - radius
	local circleRight = centerX + radius

	scope.circle.Size = UDim2.fromOffset(diameter, diameter)
	scope.circle.Position = UDim2.fromOffset(centerX, centerY)

	scope.maskTop.Size = UDim2.fromOffset(viewportX, math.max(0, circleTop))
	scope.maskTop.Position = UDim2.fromOffset(0, 0)

	scope.maskBottom.Size = UDim2.fromOffset(viewportX, math.max(0, viewportY - circleBottom))
	scope.maskBottom.Position = UDim2.fromOffset(0, circleBottom)

	scope.maskLeft.Size = UDim2.fromOffset(math.max(0, circleLeft), math.max(0, diameter))
	scope.maskLeft.Position = UDim2.fromOffset(0, circleTop)

	scope.maskRight.Size = UDim2.fromOffset(math.max(0, viewportX - circleRight), math.max(0, diameter))
	scope.maskRight.Position = UDim2.fromOffset(circleRight, circleTop)

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
		local rightWidth = math.max(0, viewportX - rightX)

		local leftSlice = scope.circleMaskLeftSlices[index]
		leftSlice.Size = UDim2.fromOffset(leftWidth, sliceHeight)
		leftSlice.Position = UDim2.fromOffset(0, sliceTop)

		local rightSlice = scope.circleMaskRightSlices[index]
		rightSlice.Size = UDim2.fromOffset(rightWidth, sliceHeight)
		rightSlice.Position = UDim2.fromOffset(rightX, sliceTop)
	end

	scope.horizontalLine.Size = UDim2.fromOffset(diameter, 2)
	scope.horizontalLine.Position = UDim2.fromOffset(circleLeft, centerY - 1)

	scope.verticalLine.Size = UDim2.fromOffset(2, diameter)
	scope.verticalLine.Position = UDim2.fromOffset(centerX - 1, circleTop)

	scope.centerDot.Size = UDim2.fromOffset(6, 6)
	scope.centerDot.Position = UDim2.fromOffset(centerX, centerY)
end

local function build(playerGui)
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

	local scope = buildScopeOverlay(gui)

	return {
		gui = gui,
		root = root,
		scope = scope,

		setRootPosition = function(x, y)
			root.Position = UDim2.fromOffset(x, y)
		end,

		setRootVisible = function(visible)
			root.Visible = visible
		end,

		setScopeOverlayVisible = function(visible)
			scope.overlay.Visible = visible
		end,

		setGuiIgnoreInset = function(ignore)
			gui.IgnoreGuiInset = ignore
		end,

		updateScopeLayout = function()
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local viewport = camera.ViewportSize
			applyScopeLayout(scope, viewport.X, viewport.Y)
		end,
	}
end

return {
	build = build,
}
