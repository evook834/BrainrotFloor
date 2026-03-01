--[[
	ShopUiConstants — UI colors and display constants for the weapon shop.
	Single source for theme values; used by View (layout + defaults) and Controller/CatalogDisplay (state colors).
]]

local ShopUiConstants = {
	-- View defaults (status/subtitle when no override)
	DefaultStatusColor = Color3.fromRGB(225, 235, 245),
	DefaultSubtitleColor = Color3.fromRGB(175, 190, 205),

	-- Panel and layout (View)
	PanelBackground = Color3.fromRGB(18, 20, 24),
	PanelStroke = Color3.fromRGB(75, 95, 120),
	TitleColor = Color3.fromRGB(245, 248, 255),
	CloseButtonBackground = Color3.fromRGB(52, 56, 70),
	CloseButtonText = Color3.fromRGB(240, 240, 245),
	ListBackground = Color3.fromRGB(12, 13, 16),
	ListScrollBar = Color3.fromRGB(95, 115, 140),
	RowBackground = Color3.fromRGB(28, 32, 40),
	InfoText = Color3.fromRGB(228, 233, 240),
	RefillAllButtonDefault = Color3.fromRGB(62, 64, 72),
	ButtonText = Color3.fromRGB(240, 245, 240),

	-- Status message colors
	StatusSuccess = Color3.fromRGB(165, 230, 185),
	StatusError = Color3.fromRGB(245, 150, 150),
	StatusInfo = Color3.fromRGB(210, 225, 240),
	StatusEmpty = Color3.fromRGB(235, 195, 140),

	-- Subtitle colors
	SubtitleOpen = Color3.fromRGB(165, 230, 185),
	SubtitleClosed = Color3.fromRGB(245, 155, 155),

	-- Button colors
	ButtonEnabled = Color3.fromRGB(52, 96, 68),
	ButtonDisabled = Color3.fromRGB(62, 64, 72),
	ButtonClosed = Color3.fromRGB(78, 52, 52),
	ButtonLocked = Color3.fromRGB(76, 70, 52),
}

return ShopUiConstants
