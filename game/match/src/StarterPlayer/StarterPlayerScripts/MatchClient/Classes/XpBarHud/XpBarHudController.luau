--[[
	XpBarHudController — Class XP bar HUD logic: ClassGetData/ClassState remotes, payload application,
	spectator visibility, HUD move mode, scale. Updates XpBarHudView refs. No UI construction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudLayoutConfig = require(ReplicatedStorage.Shared.Settings.HudLayoutConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Settings.SettingsConfig)
local XpBarHudPayloadUtil = require(script.Parent.XpBarHudPayloadUtil)
local XpBarHudRemotes = require(script.Parent.XpBarHudRemotes)
local XpBarHudView = require(script.Parent.XpBarHudView)

local HUD_SCALE_MIN = SettingsConfig.Hud.Scale.Min
local HUD_SCALE_MAX = SettingsConfig.Hud.Scale.Max

local function getHudScaleMultiplier(container: Frame): number
	local attributeScale = container:GetAttribute("HudScaleMultiplier")
	if type(attributeScale) == "number" then
		return math.clamp(attributeScale, HUD_SCALE_MIN, HUD_SCALE_MAX)
	end
	return 1
end

local function run(playerGui: PlayerGui)
	local existingGui = playerGui:FindFirstChild("ClassXpBarHud")
	if existingGui then
		existingGui:Destroy()
	end

	local refs = XpBarHudView.build(playerGui)
	local remotes = XpBarHudRemotes.resolve()

	local classGetData = remotes.classGetData
	if not classGetData then
		return
	end

	local lastPayload: XpBarHudPayloadUtil.ClassPayload? = nil

	local function applyDisplay(refs: XpBarHudView.ViewRefs, d: { string | number })
		XpBarHudView.setHudDisplay(refs, d[1] :: string, d[2] :: string, d[3] :: string, d[4] :: string, d[5] :: number)
	end

	local function updateSpectatorVisibility()
		local inSpectator = playerGui:GetAttribute(HudLayoutConfig.SPECTATOR_MODE_ATTRIBUTE) == true
		refs.gui.Enabled = not inSpectator
	end
	playerGui:GetAttributeChangedSignal(HudLayoutConfig.SPECTATOR_MODE_ATTRIBUTE):Connect(updateSpectatorVisibility)
	updateSpectatorVisibility()

	local function refreshHudScaleMultiplier()
		local scale = getHudScaleMultiplier(refs.container)
		refs.containerScale.Scale = scale
		return scale
	end
	refs.container:GetAttributeChangedSignal("HudScaleMultiplier"):Connect(refreshHudScaleMultiplier)
	local hudScaleMultiplier = refreshHudScaleMultiplier()

	local function applyClassPayload(payload: XpBarHudPayloadUtil.ClassPayload?)
		if playerGui:GetAttribute(HudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE) == true then
			applyDisplay(refs, XpBarHudPayloadUtil.LOBBY_PREVIEW_DISPLAY)
			return
		end

		if type(payload) ~= "table" or payload.success ~= true then
			return
		end

		lastPayload = payload
		local currentClassData = XpBarHudPayloadUtil.getCurrentClassData(payload)
		if not currentClassData then
			applyDisplay(refs, XpBarHudPayloadUtil.EMPTY_STATE_DISPLAY)
			return
		end

		local level = math.max(1, math.floor(tonumber(currentClassData.level) or 1))
		local perkName = tostring(currentClassData.name or payload.currentClassName or "Unknown")
		local xp = math.max(0, tonumber(currentClassData.xp) or 0)
		local xpToNext = tonumber(currentClassData.xpToNext)

		local levelText = string.format("Lv %d", level)
		local perkText = string.format("Perk: %s", perkName)
		local activeBonusText = XpBarHudPayloadUtil.getActivePerkText(currentClassData)
		local xpText, progress = XpBarHudPayloadUtil.formatXpProgressAndPercent(xp, xpToNext)

		XpBarHudView.setHudDisplay(refs, levelText, perkText, activeBonusText, xpText, progress)

		if payload.reason == XpBarHudPayloadUtil.REASON_LEVEL_UP then
			hudScaleMultiplier = getHudScaleMultiplier(refs.container)
			XpBarHudView.playLevelUpPulse(refs, hudScaleMultiplier)
		end
	end

	task.spawn(function()
		local ok, payload = pcall(function()
			return classGetData:InvokeServer()
		end)
		if ok then
			applyClassPayload(payload)
		else
			warn("XpBarHud failed to fetch class data")
		end
	end)

	if remotes.classState and remotes.classState:IsA("RemoteEvent") then
		remotes.classState.OnClientEvent:Connect(applyClassPayload)
	end

	playerGui:GetAttributeChangedSignal(HudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE):Connect(function()
		if lastPayload then
			applyClassPayload(lastPayload)
		else
			applyClassPayload({})
		end
	end)
end

return {
	run = run,
}
