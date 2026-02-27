--[[
	AmmoHudConstants — Names, display order, layout, preview/status copy, and colors for the ammo HUD.
]]

return {
	GUI_NAME = "AmmoHud",
	DISPLAY_ORDER = 35,
	CONTAINER_NAME = "AmmoContainer",

	-- Tool attributes read for ammo display; Controller subscribes to these.
	TOOL_AMMO_ATTRIBUTES = { "CurrentAmmo", "MaxAmmo", "ReserveAmmo", "TotalAmmo", "IsReloading" },

	-- Layout (container and labels); View builds from these for easy reskin/scale.
	Layout = {
		Container = {
			Size = UDim2.fromOffset(250, 106),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -18, 1, -18),
			BackgroundColor3 = Color3.fromRGB(18, 23, 34),
			BackgroundTransparency = 0.12,
			CornerRadius = 10,
			StrokeColor = Color3.fromRGB(92, 110, 136),
			StrokeTransparency = 0.2,
			StrokeThickness = 1,
			GradientColor0 = Color3.fromRGB(28, 35, 48),
			GradientColor1 = Color3.fromRGB(14, 18, 26),
			GradientRotation = 90,
		},
		WeaponName = {
			Offset = UDim2.fromOffset(8, 6),
			Size = UDim2.new(1, -16, 0, 22),
			TextColor3 = Color3.fromRGB(206, 219, 242),
			Font = Enum.Font.GothamSemibold,
			TextSize = 14,
		},
		AmmoValue = {
			Offset = UDim2.fromOffset(8, 28),
			Size = UDim2.new(1, -16, 0, 44),
			TextColor3 = Color3.fromRGB(245, 250, 255),
			Font = Enum.Font.GothamBlack,
			TextSize = 36,
		},
		Details = {
			Offset = UDim2.fromOffset(8, 74),
			Size = UDim2.new(1, -16, 0, 18),
			TextColor3 = Color3.fromRGB(157, 176, 208),
			Font = Enum.Font.Gotham,
			TextSize = 13,
		},
		Status = {
			Offset = UDim2.fromOffset(8, 90),
			Size = UDim2.new(1, -16, 0, 16),
			TextColor3 = Color3.fromRGB(255, 206, 111),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
		},
	},

	-- HUD move mode preview (lobby placeholder text)
	PREVIEW_WEAPON_NAME = "WEAPON PREVIEW",
	PREVIEW_AMMO_TEXT = "30 / 120",
	PREVIEW_DETAILS_TEXT = "MAG 30   RESERVE 90",

	-- Status line
	STATUS_OUT_OF_AMMO = "OUT OF AMMO",
	STATUS_RELOADING = "RELOADING",
	COLOR_STATUS_OUT_OF_AMMO = Color3.fromRGB(255, 136, 136),
	COLOR_STATUS_RELOADING = Color3.fromRGB(255, 206, 111),
}
