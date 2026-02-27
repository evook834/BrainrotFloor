local HUD_SCREEN_GUI_NAMES = {
	BrainrotHud = true,
	ClassXpBarHud = true,
	SprintStaminaHud = true,
	CombatCrosshairUi = true,
	AmmoHud = true,
}

local HUD_MOVE_MODE_ATTRIBUTE = "LobbyHudMoveModeEnabled"

local HUD_ROOTS = {
	BrainrotHud = {
		NextWaveTimer = true,
	},
	ClassXpBarHud = {
		XpContainer = true,
	},
	AmmoHud = {
		AmmoContainer = true,
	},
}

local NON_DRAGGABLE_HUD_ROOTS = {
	["CombatCrosshairUi/CrosshairRoot"] = true,
	["BrainrotHud/RespawnTimer"] = true,
	["BrainrotHud/GameOverOverlay"] = true,
}

local function isHudScreenGui(viewGui: ScreenGui, instance: Instance): boolean
	if not instance:IsA("ScreenGui") then
		return false
	end
	if instance == viewGui then
		return false
	end
	return HUD_SCREEN_GUI_NAMES[instance.Name] == true
end

local function isHudRoot(viewGui: ScreenGui, instance: Instance): boolean
	if not instance:IsA("GuiObject") then
		return false
	end

	local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
	if not screenGui then
		return false
	end
	if not isHudScreenGui(viewGui, screenGui) then
		return false
	end

	local screenRoots = HUD_ROOTS[screenGui.Name]
	if screenRoots then
		return screenRoots[instance.Name] == true
	end

	return true
end

return {
	HUD_SCREEN_GUI_NAMES = HUD_SCREEN_GUI_NAMES,
	NON_DRAGGABLE_HUD_ROOTS = NON_DRAGGABLE_HUD_ROOTS,
	HUD_MOVE_MODE_ATTRIBUTE = HUD_MOVE_MODE_ATTRIBUTE,
	HUD_ROOTS = HUD_ROOTS,
	isHudScreenGui = isHudScreenGui,
	isHudRoot = isHudRoot,
}

