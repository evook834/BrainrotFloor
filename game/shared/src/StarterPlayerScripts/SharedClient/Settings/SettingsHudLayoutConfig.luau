local HUD_SCREEN_GUI_NAMES = {
	BrainrotHud = true,
	ClassXpBarHud = true,
	SprintStaminaHud = true,
	CombatCrosshairUi = true,
	AmmoHud = true,
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

return {
	HUD_SCREEN_GUI_NAMES = HUD_SCREEN_GUI_NAMES,
	NON_DRAGGABLE_HUD_ROOTS = NON_DRAGGABLE_HUD_ROOTS,
	isHudScreenGui = isHudScreenGui,
}

