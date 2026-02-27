--[[
	SentryHealthBar — Turret health bar UI and fill colors.
	Builds BillboardGui with fill + ammo label; used by SentryTurretController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SentryConstants = require(ReplicatedStorage.Shared.SentryConstants)

local SentryHealthBar = {}

-- Health ratio thresholds for color (low / medium / high)
local HEALTH_LOW_THRESHOLD = 0.2
local HEALTH_MED_THRESHOLD = 0.5
local COLOR_LOW = Color3.fromRGB(220, 65, 60)
local COLOR_MED = Color3.fromRGB(230, 165, 60)
local COLOR_HIGH = Color3.fromRGB(70, 220, 105)

-- Billboard layout (names from shared so Runtime can find elements)
local BILLBOARD_NAME = SentryConstants.TURRET_BILLBOARD_NAME
local AMMO_LABEL_NAME = SentryConstants.TURRET_AMMO_LABEL_NAME
local BILLBOARD_MAX_DISTANCE = 220
local BILLBOARD_SIZE_X = 96
local BILLBOARD_SIZE_Y = 26
local BILLBOARD_STUDS_OFFSET_Y = 3.5
local BAR_HEIGHT_PX = 8
local AMMO_LABEL_OFFSET_Y = 10
local AMMO_LABEL_HEIGHT_PX = 14
local CORNER_RADIUS = 6
local BG_COLOR = Color3.fromRGB(28, 32, 36)
local BG_TRANSPARENCY = 0.2
local AMMO_TEXT_COLOR = Color3.fromRGB(195, 220, 255)
local FONT_SIZE = 11

function SentryHealthBar.getTurretFillColor(healthRatio)
	if healthRatio <= HEALTH_LOW_THRESHOLD then
		return COLOR_LOW
	end
	if healthRatio <= HEALTH_MED_THRESHOLD then
		return COLOR_MED
	end
	return COLOR_HIGH
end

function SentryHealthBar.attachTurretHealthBar(model, rootPart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = BILLBOARD_NAME
	billboard.Adornee = rootPart
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = BILLBOARD_MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(BILLBOARD_SIZE_X, BILLBOARD_SIZE_Y)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, BILLBOARD_STUDS_OFFSET_Y, 0)
	billboard.Parent = model

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 0, BAR_HEIGHT_PX)
	background.Position = UDim2.fromOffset(0, 0)
	background.BackgroundColor3 = BG_COLOR
	background.BackgroundTransparency = BG_TRANSPARENCY
	background.BorderSizePixel = 0
	background.Parent = billboard

	local backgroundCorner = Instance.new("UICorner")
	backgroundCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	backgroundCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_HIGH
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	fillCorner.Parent = fill

	local ammoText = Instance.new("TextLabel")
	ammoText.Name = AMMO_LABEL_NAME
	ammoText.BackgroundTransparency = 1
	ammoText.Size = UDim2.new(1, 0, 0, AMMO_LABEL_HEIGHT_PX)
	ammoText.Position = UDim2.fromOffset(0, AMMO_LABEL_OFFSET_Y)
	ammoText.Font = Enum.Font.GothamSemibold
	ammoText.TextSize = FONT_SIZE
	ammoText.TextXAlignment = Enum.TextXAlignment.Center
	ammoText.TextYAlignment = Enum.TextYAlignment.Center
	ammoText.TextColor3 = AMMO_TEXT_COLOR
	ammoText.TextStrokeTransparency = 0.35
	ammoText.Text = "Ammo 0/0"
	ammoText.Parent = billboard

	return fill, ammoText
end

return SentryHealthBar
