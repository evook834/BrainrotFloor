--[[
	HudLayoutConfig - Configuration for HUD layout and drag behavior.
	Used by SettingsHudLayoutController and SettingsMenuUi.
]]

local SettingsConfig = require(script.Parent:WaitForChild("SettingsConfig"))

local function isHudScreenGui(viewGui: ScreenGui, instance: Instance): boolean
	if not instance:IsA("ScreenGui") then
		return false
	end
	if instance == viewGui then
		return false
	end
	return SettingsConfig.HudScreenGuiNames[instance.Name] == true
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

	-- Special HUD roots that have specific mappings
	local specialRootKey = string.format("%s/%s", screenGui.Name, instance.Name)
	if SettingsConfig.SpecialHudRoots[specialRootKey] then
		return true
	end

	-- Default: all children of HUD ScreenGuis are draggable HUD roots
	return true
end

return {
	HUD_SCREEN_GUI_NAMES = SettingsConfig.HudScreenGuiNames,
	NON_DRAGGABLE_HUD_ROOTS = SettingsConfig.NonDraggableHudRoots,
	HUD_MOVE_MODE_ATTRIBUTE = SettingsConfig.HudMoveMode.Attribute,
	HUD_ROOTS = SettingsConfig.SpecialHudRoots,
	isHudScreenGui = isHudScreenGui,
	isHudRoot = isHudRoot,
}
