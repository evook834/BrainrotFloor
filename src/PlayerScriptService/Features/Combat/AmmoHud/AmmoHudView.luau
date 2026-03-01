--[[
	AmmoHudView — Builds the ammo HUD UI tree (container, weapon name, ammo value, details, status).
	No remotes or game logic; exposes build, setDisplay, and setRootVisible for the controller.
]]

local AmmoHudConstants = require(script.Parent.AmmoHudConstants)

export type ViewRefs = {
	gui: ScreenGui,
	root: Frame,
	weaponNameLabel: TextLabel,
	ammoLabel: TextLabel,
	detailsLabel: TextLabel,
	statusLabel: TextLabel,
}

export type AmmoDisplay = {
	weaponName: string,
	ammoText: string,
	detailsText: string,
	statusText: string?,
	statusColor: Color3?,
}

type LabelLayout = {
	Offset: UDim2,
	Size: UDim2,
	TextColor3: Color3,
	Font: Enum.Font,
	TextSize: number,
}

local function createLabel(parent: Frame, name: string, layout: LabelLayout): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = layout.Size
	label.Position = layout.Offset
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = layout.TextColor3
	label.Font = layout.Font
	label.TextSize = layout.TextSize
	label.Parent = parent
	return label
end

local function build(parent: PlayerGui): ViewRefs
	local L = AmmoHudConstants.Layout
	local C = L.Container

	local gui = Instance.new("ScreenGui")
	gui.Name = AmmoHudConstants.GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = AmmoHudConstants.DISPLAY_ORDER
	gui.Parent = parent

	local root = Instance.new("Frame")
	root.Name = AmmoHudConstants.CONTAINER_NAME
	root.Size = C.Size
	root.AnchorPoint = C.AnchorPoint
	root.Position = C.Position
	root.BackgroundColor3 = C.BackgroundColor3
	root.BackgroundTransparency = C.BackgroundTransparency
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, C.CornerRadius)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = C.StrokeColor
	rootStroke.Transparency = C.StrokeTransparency
	rootStroke.Thickness = C.StrokeThickness
	rootStroke.Parent = root

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.GradientColor0),
		ColorSequenceKeypoint.new(1, C.GradientColor1),
	})
	gradient.Rotation = C.GradientRotation
	gradient.Parent = root

	local weaponNameLabel = createLabel(root, "WeaponName", L.WeaponName)
	local ammoLabel = createLabel(root, "AmmoValue", L.AmmoValue)
	local detailsLabel = createLabel(root, "AmmoDetails", L.Details)
	local statusLabel = createLabel(root, "AmmoStatus", L.Status)
	statusLabel.Visible = false

	return {
		gui = gui,
		root = root,
		weaponNameLabel = weaponNameLabel,
		ammoLabel = ammoLabel,
		detailsLabel = detailsLabel,
		statusLabel = statusLabel,
	}
end

local function setDisplay(refs: ViewRefs, display: AmmoDisplay)
	refs.weaponNameLabel.Text = display.weaponName
	refs.ammoLabel.Text = display.ammoText
	refs.detailsLabel.Text = display.detailsText
	if display.statusText and display.statusColor then
		refs.statusLabel.Text = display.statusText
		refs.statusLabel.TextColor3 = display.statusColor
		refs.statusLabel.Visible = true
	else
		refs.statusLabel.Visible = false
	end
end

local function setRootVisible(refs: ViewRefs, visible: boolean)
	refs.root.Visible = visible
end

return {
	build = build,
	setDisplay = setDisplay,
	setRootVisible = setRootVisible,
}
