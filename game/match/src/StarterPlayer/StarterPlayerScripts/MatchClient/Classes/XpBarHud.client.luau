local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local HudLayoutConfig = require(ReplicatedStorage.Shared.Settings.HudLayoutConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD_MOVE_MODE_ATTRIBUTE = "LobbyHudMoveModeEnabled"

local existingGui = playerGui:FindFirstChild("ClassXpBarHud")
if existingGui then
	existingGui:Destroy()
end

local function formatWholeNumber(value)
	local numericValue = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	local text = tostring(numericValue)
	while true do
		local updated, substitutions = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = updated
		if substitutions == 0 then
			break
		end
	end
	return text
end

local function getCurrentClassData(payload)
	if type(payload) ~= "table" then
		return nil
	end

	for _, classData in ipairs(payload.classes or {}) do
		if classData.isCurrent then
			return classData
		end
	end

	return nil
end

local function getActivePerkText(classData)
	if type(classData) ~= "table" then
		return "Active: None"
	end

	local bonuses = classData.currentBonuses or {}
	local candidates = {
		{ label = "DMG", value = tonumber(bonuses.damagePct) or 0 },
		{ label = "HP", value = tonumber(bonuses.maxHealthPct) or 0 },
		{ label = "Move", value = tonumber(bonuses.moveSpeedPct) or 0 },
		{ label = "DR", value = tonumber(bonuses.damageReductionPct) or 0 },
		{ label = "Melee", value = tonumber(bonuses.meleeRangePct) or 0 },
		{ label = "Shop", value = tonumber(bonuses.shopDiscountPct) or 0 },
		{ label = "Reload", value = tonumber(bonuses.reloadSpeedPct) or 0 },
		{ label = "Mag", value = tonumber(bonuses.magazineSizePct) or 0 },
		{ label = "Range", value = tonumber(bonuses.bulletRangePct) or 0 },
		{ label = "Spread", value = tonumber(bonuses.bulletSpreadReductionPct) or 0 },
		{ label = "Burn", value = tonumber(bonuses.burnChancePct) or 0 },
		{ label = "Crit", value = tonumber(bonuses.criticalHitChancePct) or 0 },
		{ label = "Super Crit", value = tonumber(bonuses.superCriticalHitChancePct) or 0 },
	}

	local bestLabel = nil
	local bestValue = 0
	for _, candidate in ipairs(candidates) do
		if candidate.value > bestValue then
			bestValue = candidate.value
			bestLabel = candidate.label
		end
	end

	if not bestLabel or bestValue <= 0 then
		return "Active: No perk bonus yet"
	end

	return string.format("Active: %s +%.1f%%", bestLabel, bestValue)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ClassXpBarHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 25
gui.Parent = playerGui

local function updateSpectatorVisibility()
	local inSpectator = playerGui:GetAttribute(HudLayoutConfig.SPECTATOR_MODE_ATTRIBUTE) == true
	gui.Enabled = not inSpectator
end
playerGui:GetAttributeChangedSignal(HudLayoutConfig.SPECTATOR_MODE_ATTRIBUTE):Connect(updateSpectatorVisibility)
updateSpectatorVisibility()

local container = Instance.new("Frame")
container.Name = "XpContainer"
container.Size = UDim2.new(0.62, 0, 0, 76)
container.Position = UDim2.new(0.5, 0, 1, -84)
container.AnchorPoint = Vector2.new(0.5, 1)
container.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
container.BackgroundTransparency = 0.1
container.BorderSizePixel = 0
container.Parent = gui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 10)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Color = Color3.fromRGB(70, 94, 126)
containerStroke.Transparency = 0.18
containerStroke.Thickness = 1
containerStroke.Parent = container

local containerSizeConstraint = Instance.new("UISizeConstraint")
containerSizeConstraint.MinSize = Vector2.new(320, 68)
containerSizeConstraint.MaxSize = Vector2.new(760, 86)
containerSizeConstraint.Parent = container

local leftPanel = Instance.new("Frame")
leftPanel.Name = "LevelPanel"
leftPanel.Size = UDim2.new(0, 176, 1, 0)
leftPanel.BackgroundTransparency = 1
leftPanel.Parent = container

local leftPadding = Instance.new("UIPadding")
leftPadding.PaddingTop = UDim.new(0, 8)
leftPadding.PaddingBottom = UDim.new(0, 8)
leftPadding.PaddingLeft = UDim.new(0, 12)
leftPadding.PaddingRight = UDim.new(0, 8)
leftPadding.Parent = leftPanel

local leftLayout = Instance.new("UIListLayout")
leftLayout.FillDirection = Enum.FillDirection.Vertical
leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
leftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
leftLayout.Padding = UDim.new(0, 2)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftPanel

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.LayoutOrder = 1
levelLabel.Size = UDim2.new(1, 0, 0, 30)
levelLabel.BackgroundTransparency = 1
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.TextColor3 = Color3.fromRGB(244, 248, 255)
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextSize = 23
levelLabel.Text = "Lv 1"
levelLabel.Parent = leftPanel

local perkLabel = Instance.new("TextLabel")
perkLabel.Name = "PerkLabel"
perkLabel.LayoutOrder = 2
perkLabel.Size = UDim2.new(1, 0, 0, 18)
perkLabel.BackgroundTransparency = 1
perkLabel.TextXAlignment = Enum.TextXAlignment.Left
perkLabel.TextColor3 = Color3.fromRGB(182, 213, 241)
perkLabel.Font = Enum.Font.GothamSemibold
perkLabel.TextSize = 13
perkLabel.Text = "Perk: Unknown"
perkLabel.Parent = leftPanel

local bonusLabel = Instance.new("TextLabel")
bonusLabel.Name = "BonusLabel"
bonusLabel.LayoutOrder = 3
bonusLabel.Size = UDim2.new(1, 0, 0, 16)
bonusLabel.BackgroundTransparency = 1
bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
bonusLabel.TextColor3 = Color3.fromRGB(150, 199, 240)
bonusLabel.Font = Enum.Font.Gotham
bonusLabel.TextSize = 12
bonusLabel.Text = "Active: None"
bonusLabel.Parent = leftPanel

local xpPanel = Instance.new("Frame")
xpPanel.Name = "XpPanel"
xpPanel.Size = UDim2.new(1, -188, 1, 0)
xpPanel.Position = UDim2.new(0, 188, 0, 0)
xpPanel.BackgroundTransparency = 1
xpPanel.Parent = container

local xpPadding = Instance.new("UIPadding")
xpPadding.PaddingTop = UDim.new(0, 10)
xpPadding.PaddingBottom = UDim.new(0, 10)
xpPadding.PaddingLeft = UDim.new(0, 4)
xpPadding.PaddingRight = UDim.new(0, 12)
xpPadding.Parent = xpPanel

local xpLayout = Instance.new("UIListLayout")
xpLayout.FillDirection = Enum.FillDirection.Vertical
xpLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
xpLayout.VerticalAlignment = Enum.VerticalAlignment.Center
xpLayout.Padding = UDim.new(0, 6)
xpLayout.SortOrder = Enum.SortOrder.LayoutOrder
xpLayout.Parent = xpPanel

local xpNumberLabel = Instance.new("TextLabel")
xpNumberLabel.Name = "XpNumberLabel"
xpNumberLabel.LayoutOrder = 1
xpNumberLabel.Size = UDim2.new(1, 0, 0, 18)
xpNumberLabel.BackgroundTransparency = 1
xpNumberLabel.TextXAlignment = Enum.TextXAlignment.Left
xpNumberLabel.TextColor3 = Color3.fromRGB(231, 240, 250)
xpNumberLabel.Font = Enum.Font.GothamSemibold
xpNumberLabel.TextSize = 14
xpNumberLabel.Text = "XP 0 / 100"
xpNumberLabel.Parent = xpPanel

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.LayoutOrder = 2
barBackground.Size = UDim2.new(1, 0, 0, 20)
barBackground.BackgroundColor3 = Color3.fromRGB(32, 42, 55)
barBackground.BorderSizePixel = 0
barBackground.Parent = xpPanel

local barBackgroundCorner = Instance.new("UICorner")
barBackgroundCorner.CornerRadius = UDim.new(0, 6)
barBackgroundCorner.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "BarFill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(78, 176, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0, 6)
barFillCorner.Parent = barFill

local barPercentLabel = Instance.new("TextLabel")
barPercentLabel.Name = "BarPercent"
barPercentLabel.Size = UDim2.fromScale(1, 1)
barPercentLabel.BackgroundTransparency = 1
barPercentLabel.TextColor3 = Color3.fromRGB(10, 16, 24)
barPercentLabel.Font = Enum.Font.GothamBold
barPercentLabel.TextSize = 12
barPercentLabel.Text = "0%"
barPercentLabel.Parent = barBackground

local containerScale = Instance.new("UIScale")
containerScale.Scale = 1
containerScale.Parent = container

local baseContainerBackgroundTransparency = 0.1
local baseStrokeColor = Color3.fromRGB(70, 94, 126)
local baseStrokeTransparency = 0.18
local baseStrokeThickness = 1
local baseBarFillColor = Color3.fromRGB(78, 176, 255)
local pulseStrokeColor = Color3.fromRGB(132, 206, 255)
local pulseBarFillColor = Color3.fromRGB(140, 221, 255)
local levelUpPulseToken = 0
local hudScaleMultiplier = 1
local lastPayload = nil

local function refreshHudScaleMultiplier()
	local attributeScale = container:GetAttribute("HudScaleMultiplier")
	if type(attributeScale) == "number" then
		hudScaleMultiplier = math.clamp(attributeScale, 0.6, 1.45)
	else
		hudScaleMultiplier = 1
	end
	containerScale.Scale = hudScaleMultiplier
end

container:GetAttributeChangedSignal("HudScaleMultiplier"):Connect(refreshHudScaleMultiplier)
refreshHudScaleMultiplier()

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
if not remotesFolder then
	warn("XpBarHud could not find ReplicatedStorage/Remotes")
	return
end

local classGetDataFunction = remotesFolder:WaitForChild(Config.Remotes.ClassGetData, 15)
local classStateRemote = remotesFolder:FindFirstChild(Config.Remotes.ClassState)

if not classGetDataFunction then
	warn("XpBarHud could not find ReplicatedStorage/Remotes/ClassGetData")
	return
end

local function setHudDisplay(levelText, perkText, activeBonusText, xpText, progress)
	levelLabel.Text = levelText
	perkLabel.Text = perkText
	bonusLabel.Text = activeBonusText
	xpNumberLabel.Text = xpText
	barFill.Size = UDim2.fromScale(progress, 1)
	barPercentLabel.Text = string.format("%d%%", math.floor((progress * 100) + 0.5))
end

local function formatXpProgressAndPercent(xp, xpToNext)
	if type(xpToNext) == "number" and xpToNext > 0 then
		local progress = math.clamp(xp / xpToNext, 0, 1)
		local text = string.format("XP %s / %s", formatWholeNumber(xp), formatWholeNumber(xpToNext))
		return text, progress
	end

	return string.format("XP %s / MAX", formatWholeNumber(xp)), 1
end

local function playLevelUpPulse()
	levelUpPulseToken += 1
	local activeToken = levelUpPulseToken

	TweenService:Create(
		containerScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = hudScaleMultiplier * 1.03 }
	):Play()
	TweenService:Create(
		container,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.02 }
	):Play()
	TweenService:Create(
		containerStroke,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Color = pulseStrokeColor,
			Transparency = 0.03,
			Thickness = 2,
		}
	):Play()
	TweenService:Create(
		barFill,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = pulseBarFillColor }
	):Play()

	task.delay(0.14, function()
		if activeToken ~= levelUpPulseToken then
			return
		end

		TweenService:Create(
			containerScale,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = hudScaleMultiplier }
		):Play()
		TweenService:Create(
			container,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = baseContainerBackgroundTransparency }
		):Play()
		TweenService:Create(
			containerStroke,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Color = baseStrokeColor,
				Transparency = baseStrokeTransparency,
				Thickness = baseStrokeThickness,
			}
		):Play()
		TweenService:Create(
			barFill,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = baseBarFillColor }
		):Play()
	end)
end

local function applyClassPayload(payload)
	if playerGui:GetAttribute(HUD_MOVE_MODE_ATTRIBUTE) == true then
		setHudDisplay("Lv 1", "Perk: Lobby preview", "Active: No perk bonus yet", "XP 0 / 100", 0.4)
		return
	end

	if type(payload) ~= "table" or payload.success ~= true then
		return
	end

	lastPayload = payload

	local currentClassData = getCurrentClassData(payload)
	if not currentClassData then
		setHudDisplay("Lv 1", "Perk: Unknown", "Active: None", "XP 0 / 100", 0)
		return
	end

	local level = math.max(1, math.floor(tonumber(currentClassData.level) or 1))
	local perkName = tostring(currentClassData.name or payload.currentClassName or "Unknown")
	local xp = math.max(0, tonumber(currentClassData.xp) or 0)
	local xpToNext = tonumber(currentClassData.xpToNext)

	levelLabel.Text = string.format("Lv %d", level)
	perkLabel.Text = string.format("Perk: %s", perkName)
	bonusLabel.Text = getActivePerkText(currentClassData)

	local xpText, progress = formatXpProgressAndPercent(xp, xpToNext)
	xpNumberLabel.Text = xpText
	barFill.Size = UDim2.fromScale(progress, 1)
	barPercentLabel.Text = string.format("%d%%", math.floor((progress * 100) + 0.5))

	if payload.reason == "LevelUp" then
		playLevelUpPulse()
	end
end

task.spawn(function()
	local ok, payload = pcall(function()
		return classGetDataFunction:InvokeServer()
	end)
	if ok then
		applyClassPayload(payload)
	else
		warn("XpBarHud failed to fetch class data")
	end
end)

if classStateRemote and classStateRemote:IsA("RemoteEvent") then
	classStateRemote.OnClientEvent:Connect(function(payload)
		applyClassPayload(payload)
	end)
end

playerGui:GetAttributeChangedSignal(HUD_MOVE_MODE_ATTRIBUTE):Connect(function()
	if lastPayload then
		applyClassPayload(lastPayload)
	else
		applyClassPayload({})
	end
end)
