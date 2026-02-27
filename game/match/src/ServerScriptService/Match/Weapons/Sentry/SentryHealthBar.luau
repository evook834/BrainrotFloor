local SentryHealthBar = {}

function SentryHealthBar.getTurretFillColor(healthRatio)
	if healthRatio <= 0.2 then
		return Color3.fromRGB(220, 65, 60)
	end
	if healthRatio <= 0.5 then
		return Color3.fromRGB(230, 165, 60)
	end
	return Color3.fromRGB(70, 220, 105)
end

function SentryHealthBar.attachTurretHealthBar(model, rootPart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TurretHealthBar"
	billboard.Adornee = rootPart
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Size = UDim2.fromOffset(96, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	billboard.Parent = model

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 0, 8)
	background.Position = UDim2.fromOffset(0, 0)
	background.BackgroundColor3 = Color3.fromRGB(28, 32, 36)
	background.BackgroundTransparency = 0.2
	background.BorderSizePixel = 0
	background.Parent = billboard

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, 6)
	backgroundCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 220, 105)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local ammoText = Instance.new("TextLabel")
	ammoText.Name = "AmmoText"
	ammoText.BackgroundTransparency = 1
	ammoText.Size = UDim2.new(1, 0, 0, 14)
	ammoText.Position = UDim2.fromOffset(0, 10)
	ammoText.Font = Enum.Font.GothamSemibold
	ammoText.TextSize = 11
	ammoText.TextXAlignment = Enum.TextXAlignment.Center
	ammoText.TextYAlignment = Enum.TextYAlignment.Center
	ammoText.TextColor3 = Color3.fromRGB(195, 220, 255)
	ammoText.TextStrokeTransparency = 0.35
	ammoText.Text = "Ammo 0/0"
	ammoText.Parent = billboard

	return fill, ammoText
end

return SentryHealthBar
