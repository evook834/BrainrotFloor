local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "ClassSelectUi"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenClassPanel"
openButton.Size = UDim2.fromOffset(46, 126)
openButton.Position = UDim2.new(0, 12, 0.5, -63)
openButton.BackgroundColor3 = Color3.fromRGB(32, 37, 47)
openButton.BorderSizePixel = 0
openButton.Text = "CLASS"
openButton.TextColor3 = Color3.fromRGB(242, 246, 255)
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 16
openButton.Parent = gui

local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(0, 8)
openButtonCorner.Parent = openButton

local openButtonStroke = Instance.new("UIStroke")
openButtonStroke.Color = Color3.fromRGB(88, 104, 128)
openButtonStroke.Transparency = 0.2
openButtonStroke.Thickness = 1
openButtonStroke.Parent = openButton

local panel = Instance.new("Frame")
panel.Name = "ClassPanel"
panel.Size = UDim2.fromOffset(380, 500)
panel.Position = UDim2.new(0, 66, 0.5, -250)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(78, 95, 120)
panelStroke.Transparency = 0.14
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -62, 0, 34)
title.Position = UDim2.fromOffset(14, 8)
title.BackgroundTransparency = 1
title.Text = "Class Selection"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(245, 248, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, -24, 0, 22)
subtitle.Position = UDim2.fromOffset(14, 40)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Switch available between waves."
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextColor3 = Color3.fromRGB(168, 227, 188)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Position = UDim2.new(1, -42, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(240, 240, 245)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.Parent = panel

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 8)
closeButtonCorner.Parent = closeButton

local currentInfo = Instance.new("TextLabel")
currentInfo.Name = "CurrentInfo"
currentInfo.Size = UDim2.new(1, -24, 0, 92)
currentInfo.Position = UDim2.fromOffset(12, 66)
currentInfo.BackgroundColor3 = Color3.fromRGB(24, 29, 37)
currentInfo.BackgroundTransparency = 0.12
currentInfo.BorderSizePixel = 0
currentInfo.Text = ""
currentInfo.TextWrapped = true
currentInfo.TextXAlignment = Enum.TextXAlignment.Left
currentInfo.TextYAlignment = Enum.TextYAlignment.Top
currentInfo.TextColor3 = Color3.fromRGB(224, 232, 242)
currentInfo.Font = Enum.Font.GothamSemibold
currentInfo.TextSize = 14
currentInfo.Parent = panel

local currentInfoCorner = Instance.new("UICorner")
currentInfoCorner.CornerRadius = UDim.new(0, 8)
currentInfoCorner.Parent = currentInfo

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "ClassList"
listFrame.Size = UDim2.new(1, -24, 1, -234)
listFrame.Position = UDim2.fromOffset(12, 166)
listFrame.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
listFrame.BackgroundTransparency = 0.15
listFrame.BorderSizePixel = 0
listFrame.ScrollBarImageColor3 = Color3.fromRGB(95, 115, 140)
listFrame.ScrollBarThickness = 6
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.new()
listFrame.Parent = panel

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 8)
listCorner.Parent = listFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 8)
listPadding.PaddingBottom = UDim.new(0, 8)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.Parent = listFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, -24, 0, 52)
statusLabel.Position = UDim2.new(0, 12, 1, -58)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
statusLabel.Font = Enum.Font.GothamSemibold
statusLabel.TextSize = 14
statusLabel.Parent = panel

local bonusInfoMenu = Instance.new("Frame")
bonusInfoMenu.Name = "BonusInfoMenu"
bonusInfoMenu.Size = UDim2.fromOffset(228, 154)
bonusInfoMenu.Position = UDim2.fromOffset(12, 170)
bonusInfoMenu.BackgroundColor3 = Color3.fromRGB(20, 25, 32)
bonusInfoMenu.BackgroundTransparency = 0.06
bonusInfoMenu.BorderSizePixel = 0
bonusInfoMenu.Visible = false
bonusInfoMenu.ZIndex = 20
bonusInfoMenu.Parent = panel

local bonusInfoMenuCorner = Instance.new("UICorner")
bonusInfoMenuCorner.CornerRadius = UDim.new(0, 8)
bonusInfoMenuCorner.Parent = bonusInfoMenu

local bonusInfoMenuStroke = Instance.new("UIStroke")
bonusInfoMenuStroke.Color = Color3.fromRGB(90, 124, 160)
bonusInfoMenuStroke.Transparency = 0.1
bonusInfoMenuStroke.Thickness = 1
bonusInfoMenuStroke.Parent = bonusInfoMenu

local bonusInfoTitle = Instance.new("TextLabel")
bonusInfoTitle.Name = "Title"
bonusInfoTitle.Size = UDim2.new(1, -30, 0, 24)
bonusInfoTitle.Position = UDim2.fromOffset(8, 6)
bonusInfoTitle.BackgroundTransparency = 1
bonusInfoTitle.Text = "Class Bonuses"
bonusInfoTitle.TextXAlignment = Enum.TextXAlignment.Left
bonusInfoTitle.TextYAlignment = Enum.TextYAlignment.Center
bonusInfoTitle.TextColor3 = Color3.fromRGB(232, 238, 245)
bonusInfoTitle.Font = Enum.Font.GothamBold
bonusInfoTitle.TextSize = 13
bonusInfoTitle.ZIndex = 21
bonusInfoTitle.Parent = bonusInfoMenu

local bonusInfoCloseButton = Instance.new("TextButton")
bonusInfoCloseButton.Name = "Close"
bonusInfoCloseButton.Size = UDim2.fromOffset(18, 18)
bonusInfoCloseButton.Position = UDim2.new(1, -24, 0, 8)
bonusInfoCloseButton.BackgroundColor3 = Color3.fromRGB(62, 67, 78)
bonusInfoCloseButton.BorderSizePixel = 0
bonusInfoCloseButton.Text = "X"
bonusInfoCloseButton.TextColor3 = Color3.fromRGB(235, 238, 242)
bonusInfoCloseButton.Font = Enum.Font.GothamBold
bonusInfoCloseButton.TextSize = 11
bonusInfoCloseButton.ZIndex = 21
bonusInfoCloseButton.Parent = bonusInfoMenu

local bonusInfoCloseCorner = Instance.new("UICorner")
bonusInfoCloseCorner.CornerRadius = UDim.new(0, 5)
bonusInfoCloseCorner.Parent = bonusInfoCloseButton

local bonusInfoScroll = Instance.new("ScrollingFrame")
bonusInfoScroll.Name = "Scroll"
bonusInfoScroll.Size = UDim2.new(1, -16, 1, -38)
bonusInfoScroll.Position = UDim2.fromOffset(8, 30)
bonusInfoScroll.BackgroundTransparency = 1
bonusInfoScroll.BorderSizePixel = 0
bonusInfoScroll.CanvasSize = UDim2.new()
bonusInfoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
bonusInfoScroll.ScrollBarThickness = 5
bonusInfoScroll.ScrollBarImageColor3 = Color3.fromRGB(112, 142, 172)
bonusInfoScroll.ZIndex = 21
bonusInfoScroll.Parent = bonusInfoMenu

local bonusInfoText = Instance.new("TextLabel")
bonusInfoText.Name = "Text"
bonusInfoText.Size = UDim2.new(1, -4, 0, 0)
bonusInfoText.Position = UDim2.fromOffset(0, 0)
bonusInfoText.AutomaticSize = Enum.AutomaticSize.Y
bonusInfoText.BackgroundTransparency = 1
bonusInfoText.TextWrapped = true
bonusInfoText.TextXAlignment = Enum.TextXAlignment.Left
bonusInfoText.TextYAlignment = Enum.TextYAlignment.Top
bonusInfoText.TextColor3 = Color3.fromRGB(208, 221, 236)
bonusInfoText.Font = Enum.Font.Gotham
bonusInfoText.TextSize = 12
bonusInfoText.Text = ""
bonusInfoText.ZIndex = 21
bonusInfoText.Parent = bonusInfoScroll

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
if not remotesFolder then
	warn("ClassUi could not find ReplicatedStorage/Remotes")
	return
end

local classGetDataFunction = remotesFolder:WaitForChild(Config.Remotes.ClassGetData, 15)
local classSelectFunction = remotesFolder:WaitForChild(Config.Remotes.ClassSelect, 15)
local classStateRemote = remotesFolder:FindFirstChild(Config.Remotes.ClassState)
local waveStateRemote = remotesFolder:FindFirstChild(Config.Remotes.WaveState)

if not classGetDataFunction or not classSelectFunction then
	warn("ClassUi is missing one or more class remotes")
	return
end

local isRefreshing = false
local isSwitching = false
local activeInfoClassId = nil

local function setStatus(text, color)
	statusLabel.Text = text or ""
	if color then
		statusLabel.TextColor3 = color
	else
		statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
	end
end

local function formatPercent(value)
	return string.format("%.1f%%", tonumber(value) or 0)
end

local function formatSignedPercent(value)
	local number = tonumber(value) or 0
	if number >= 0 then
		return "+" .. formatPercent(number)
	end
	return formatPercent(number)
end

local bonusKeyOrder = {
	{ key = "damagePct", label = "Damage" },
	{ key = "maxHealthPct", label = "Max Health" },
	{ key = "moveSpeedPct", label = "Move Speed" },
	{ key = "damageReductionPct", label = "Damage Reduction" },
	{ key = "meleeRangePct", label = "Melee Range" },
	{ key = "shopDiscountPct", label = "Shop Discount" },
	{ key = "magazineSizePct", label = "Magazine Size" },
	{ key = "reloadSpeedPct", label = "Reload Speed" },
	{ key = "bulletRangePct", label = "Weapon Range" },
	{ key = "bulletSpreadReductionPct", label = "Spread Reduction" },
	{ key = "burnChancePct", label = "Burn Chance" },
	{ key = "criticalHitChancePct", label = "Critical Hit Chance" },
	{ key = "superCriticalHitChancePct", label = "Super Critical Hit Chance" },
}

local knownBonusKeys = {}
for _, entry in ipairs(bonusKeyOrder) do
	knownBonusKeys[entry.key] = true
end

local function prettifyBonusKey(rawKey)
	local key = tostring(rawKey or "")
	key = key:gsub("Pct$", "")
	key = key:gsub("([a-z])([A-Z])", "%1 %2")
	if key == "" then
		return "Bonus"
	end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function buildBonusInfoText(classData)
	if type(classData) ~= "table" then
		return "No bonus data available."
	end

	local currentBonuses = classData.currentBonuses or {}
	local perLevelBonuses = classData.perLevelBonuses or {}
	local lines = {}

	local function appendLine(label, totalValue, perLevelValue)
		local hasTotal = type(totalValue) == "number"
		local hasPerLevel = type(perLevelValue) == "number"
		if not hasTotal and not hasPerLevel then
			return
		end

		local total = tonumber(totalValue) or 0
		local perLevel = tonumber(perLevelValue) or 0
		if math.abs(total) < 0.005 and math.abs(perLevel) < 0.005 then
			return
		end

		if hasPerLevel then
			table.insert(
				lines,
				string.format("%s: %s total (%s/lv)", label, formatSignedPercent(total), formatSignedPercent(perLevel))
			)
		else
			table.insert(lines, string.format("%s: %s", label, formatSignedPercent(total)))
		end
	end

	for _, entry in ipairs(bonusKeyOrder) do
		appendLine(entry.label, currentBonuses[entry.key], perLevelBonuses[entry.key])
	end

	local extraKeys = {}
	for key, value in pairs(currentBonuses) do
		if type(value) == "number" and string.sub(key, -3) == "Pct" and not knownBonusKeys[key] then
			table.insert(extraKeys, key)
		end
	end
	for key, value in pairs(perLevelBonuses) do
		if type(value) == "number" and string.sub(key, -3) == "Pct" and not knownBonusKeys[key] then
			table.insert(extraKeys, key)
		end
	end
	table.sort(extraKeys)

	local seenExtra = {}
	for _, key in ipairs(extraKeys) do
		if seenExtra[key] then
			continue
		end
		seenExtra[key] = true
		appendLine(prettifyBonusKey(key), currentBonuses[key], perLevelBonuses[key])
	end

	if #lines == 0 then
		return "No active bonus yet.\nLevel this class to unlock bonuses."
	end

	return table.concat(lines, "\n")
end

local function hideBonusInfoMenu()
	activeInfoClassId = nil
	bonusInfoMenu.Visible = false
end

local function clearRows()
	hideBonusInfoMenu()
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function renderPayload(payload)
	if type(payload) ~= "table" then
		return
	end
	if not payload.success then
		setStatus(payload.message or "Could not load class data.", Color3.fromRGB(245, 150, 150))
		return
	end

	clearRows()

	local canSwitch = payload.canSwitch == true
	local waveState = payload.waveState or "Unknown"
	if canSwitch then
		subtitle.Text = string.format("Switch available now (%s).", waveState)
		subtitle.TextColor3 = Color3.fromRGB(168, 227, 188)
	else
		subtitle.Text = string.format("Switch locked during active wave (%s).", waveState)
		subtitle.TextColor3 = Color3.fromRGB(245, 155, 155)
	end

	local currentClassData = nil
	for _, classData in ipairs(payload.classes or {}) do
		if classData.isCurrent then
			currentClassData = classData
			break
		end
	end

	if currentClassData then
		local levelText = string.format("Lv %d/%d", currentClassData.level or 1, payload.maxLevel or 200)
		local xpToNext = currentClassData.xpToNext
		local xpText = "XP MAX"
		if type(xpToNext) == "number" and xpToNext > 0 then
			xpText = string.format("XP %.0f / %.0f", currentClassData.xp or 0, xpToNext)
		end
		currentInfo.Text = string.format(
			"Current: %s (%s)\n%s | %s\nUse the i button next to a class to view bonuses.",
			currentClassData.name or payload.currentClassName or "?",
			currentClassData.weaponTag or "NoTag",
			levelText,
			xpText
		)
	else
		currentInfo.Text = "Current class data unavailable."
	end

	for index, classData in ipairs(payload.classes or {}) do
		local row = Instance.new("Frame")
		row.Name = "ClassRow_" .. tostring(index)
		row.Size = UDim2.new(1, -4, 0, 84)
		row.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = listFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.Size = UDim2.new(1, -168, 1, -8)
		info.Position = UDim2.fromOffset(10, 6)
		info.BackgroundTransparency = 1
		info.TextWrapped = true
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Top
		info.Font = Enum.Font.GothamSemibold
		info.TextSize = 14
		info.TextColor3 = Color3.fromRGB(228, 233, 240)

		local xpToNext = classData.xpToNext
		local xpLine = "XP MAX"
		if type(xpToNext) == "number" and xpToNext > 0 then
			xpLine = string.format("XP %.0f / %.0f", classData.xp or 0, xpToNext)
		end
		info.Text = string.format(
			"%s (%s)\nLv %d/%d  |  %s",
			classData.name or classData.id or "?",
			classData.weaponTag or "NoTag",
			classData.level or 1,
			payload.maxLevel or 200,
			xpLine
		)
		info.Parent = row

		local infoButton = Instance.new("TextButton")
		infoButton.Name = "InfoButton"
		infoButton.Size = UDim2.fromOffset(24, 24)
		infoButton.Position = UDim2.new(1, -142, 0, 8)
		infoButton.BackgroundColor3 = Color3.fromRGB(54, 79, 109)
		infoButton.BorderSizePixel = 0
		infoButton.TextColor3 = Color3.fromRGB(235, 242, 250)
		infoButton.Font = Enum.Font.GothamBold
		infoButton.TextSize = 12
		infoButton.Text = "i"
		infoButton.Parent = row

		local infoButtonCorner = Instance.new("UICorner")
		infoButtonCorner.CornerRadius = UDim.new(0, 12)
		infoButtonCorner.Parent = infoButton

		infoButton.Activated:Connect(function()
			if activeInfoClassId == classData.id and bonusInfoMenu.Visible then
				hideBonusInfoMenu()
				return
			end

			activeInfoClassId = classData.id
			bonusInfoTitle.Text = string.format("%s Bonuses", classData.name or classData.id or "Class")
			bonusInfoText.Text = buildBonusInfoText(classData)
			bonusInfoScroll.CanvasPosition = Vector2.new()
			bonusInfoMenu.Visible = true

			local panelPos = panel.AbsolutePosition
			local panelSize = panel.AbsoluteSize
			local anchorPos = infoButton.AbsolutePosition
			local menuSize = bonusInfoMenu.AbsoluteSize
			local x = anchorPos.X - panelPos.X - menuSize.X - 8
			local y = anchorPos.Y - panelPos.Y - 4
			local clampedX = math.clamp(x, 12, math.max(12, panelSize.X - menuSize.X - 12))
			local clampedY = math.clamp(y, 66, math.max(66, panelSize.Y - menuSize.Y - 12))
			bonusInfoMenu.Position = UDim2.fromOffset(clampedX, clampedY)
		end)

		local chooseButton = Instance.new("TextButton")
		chooseButton.Name = "ChooseButton"
		chooseButton.Size = UDim2.fromOffset(106, 38)
		chooseButton.Position = UDim2.new(1, -114, 0, 24)
		chooseButton.BackgroundColor3 = Color3.fromRGB(52, 96, 68)
		chooseButton.BorderSizePixel = 0
		chooseButton.TextColor3 = Color3.fromRGB(240, 245, 240)
		chooseButton.Font = Enum.Font.GothamBold
		chooseButton.TextSize = 14
		chooseButton.Text = "Select"
		chooseButton.Parent = row

		local chooseCorner = Instance.new("UICorner")
		chooseCorner.CornerRadius = UDim.new(0, 8)
		chooseCorner.Parent = chooseButton

		local disabled = false
		if classData.isCurrent then
			disabled = true
			chooseButton.Text = "Selected"
			chooseButton.BackgroundColor3 = Color3.fromRGB(62, 64, 72)
		elseif not canSwitch then
			disabled = true
			chooseButton.Text = "Wave Active"
			chooseButton.BackgroundColor3 = Color3.fromRGB(78, 52, 52)
		end

		if disabled then
			chooseButton.AutoButtonColor = false
		else
			chooseButton.Activated:Connect(function()
				if isSwitching then
					return
				end
				isSwitching = true

				local ok, result = pcall(function()
					return classSelectFunction:InvokeServer(classData.id)
				end)

				isSwitching = false
				if not ok then
					setStatus("Class selection failed: remote error.", Color3.fromRGB(245, 150, 150))
					return
				end

				if result and result.success then
					setStatus(result.message or "Class selected.", Color3.fromRGB(165, 230, 185))
					local statePayload = result.state
					if type(statePayload) == "table" then
						renderPayload(statePayload)
					end
				else
					setStatus((result and result.message) or "Class switch denied.", Color3.fromRGB(245, 150, 150))
				end
			end)
		end
	end
end

local function refreshPayload()
	if isRefreshing then
		return
	end

	isRefreshing = true
	local ok, payload = pcall(function()
		return classGetDataFunction:InvokeServer()
	end)
	isRefreshing = false

	if not ok then
		setStatus("Could not load class data.", Color3.fromRGB(245, 150, 150))
		return
	end

	renderPayload(payload)
end

local function openPanel()
	panel.Visible = true
	setStatus("Choose your class.", Color3.fromRGB(210, 225, 240))
	refreshPayload()
end

local function closePanel()
	panel.Visible = false
	setStatus("")
	hideBonusInfoMenu()
end

openButton.Activated:Connect(function()
	if panel.Visible then
		closePanel()
	else
		openPanel()
	end
end)

closeButton.Activated:Connect(closePanel)
bonusInfoCloseButton.Activated:Connect(hideBonusInfoMenu)

if classStateRemote and classStateRemote:IsA("RemoteEvent") then
	classStateRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		if panel.Visible then
			renderPayload(payload)
		end
	end)
end

if waveStateRemote and waveStateRemote:IsA("RemoteEvent") then
	waveStateRemote.OnClientEvent:Connect(function()
		if panel.Visible then
			refreshPayload()
		end
	end)
end

task.defer(function()
	refreshPayload()
end)
