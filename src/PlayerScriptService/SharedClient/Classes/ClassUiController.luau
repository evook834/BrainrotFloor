local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ViewModule = require(script.Parent:WaitForChild("ClassUiView"))
local ClassIconAssets = require(ReplicatedStorage.Shared.Classes.ClassIconAssets)

type ClassPayload = {
	success: boolean?,
	message: string?,
	canSwitch: boolean?,
	waveState: string?,
	maxLevel: number?,
	classes: { any }?,
	currentClassName: string?,
}

local REMOTE_WAIT = 15
local DEFAULT_MAX_LEVEL = 200
local CLASS_ICONS_FOLDER_NAME = "ClassIcons"
local CLASS_ICONS_ALT_FOLDER_NAME = "Class Icons"
local CLASS_ICON_GAME_ASSET_CATEGORY = "Images"

local function normalizeIconKey(value: string?): string
	local normalized = string.lower(tostring(value or ""))
	normalized = normalized:gsub("%.png$", "")
	normalized = normalized:gsub("[^%w]+", "")
	return normalized
end

local function buildGameAssetIconUri(value: string?): string?
	local assetName = tostring(value or "")
	assetName = assetName:gsub("%.png$", "")
	assetName = assetName:gsub("[^%w]+", "")
	if assetName == "" then
		return nil
	end

	return string.format("rbxgameasset://%s/%s", CLASS_ICON_GAME_ASSET_CATEGORY, assetName)
end

local function readImageContent(source: Instance): string?
	for _, propertyName in ipairs({ "Image", "Texture", "Value" }) do
		local ok, value = pcall(function()
			return source[propertyName]
		end)
		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

local function formatPercent(value: number?): string
	return string.format("%.1f%%", tonumber(value) or 0)
end

local function formatSignedPercent(value: number?): string
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
	{ key = "repairSpeedPct", label = "Repair Speed" },
	{ key = "turretDamagePct", label = "Turret Damage" },
	{ key = "bulletRangePct", label = "Weapon Range" },
	{ key = "bulletSpreadReductionPct", label = "Spread Reduction" },
	{ key = "burnChancePct", label = "Burn Chance" },
	{ key = "criticalHitChancePct", label = "Critical Hit Chance" },
	{ key = "superCriticalHitChancePct", label = "Super Critical Hit Chance" },
}

local knownBonusKeys: { [string]: boolean } = {}
for _, entry in ipairs(bonusKeyOrder) do
	knownBonusKeys[entry.key] = true
end

local function prettifyBonusKey(rawKey: string?): string
	local key = tostring(rawKey or "")
	key = key:gsub("Pct$", "")
	key = key:gsub("([a-z])([A-Z])", "%1 %2")
	if key == "" then
		return "Bonus"
	end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function buildBonusInfoText(classData: any): string
	if type(classData) ~= "table" then
		return "No bonus data available."
	end

	local currentBonuses = classData.currentBonuses or {}
	local perLevelBonuses = classData.perLevelBonuses or {}
	local lines = {}

	local function appendLine(label: string, totalValue: number?, perLevelValue: number?)
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

	local seenExtra: { [string]: boolean } = {}
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

local function getPayloadMaxLevel(payload: ClassPayload): number
	local maxLevel = tonumber(payload and payload.maxLevel)
	if type(maxLevel) ~= "number" then
		return DEFAULT_MAX_LEVEL
	end
	return math.max(1, math.floor(maxLevel))
end

local function formatXpProgressText(rawXp: number?, rawXpToNext: number?): string
	local xpToNext = tonumber(rawXpToNext)
	if type(xpToNext) == "number" and xpToNext > 0 then
		return string.format("XP %.0f / %.0f", tonumber(rawXp) or 0, xpToNext)
	end
	return "XP MAX"
end

local function run(options: { isLobby: boolean? }?)
	options = options or {}
	local isLobby = options.isLobby == true

	local view = ViewModule.build()
	local statusLabel = view.statusLabel
	local bonusInfoMenu = view.bonusInfoMenu
	local bonusInfoCloseButton = view.bonusInfoCloseButton
	local bonusInfoText = view.bonusInfoText
	local bonusInfoScroll = view.bonusInfoScroll
	local currentIcon = view.currentIcon
	local currentInfo = view.currentInfo
	local listFrame = view.listFrame
	local panel = view.panel

	local isRefreshing = false
	local isSwitching = false
	local activeInfoClassId: string? = nil

	local classGetDataFunction: RemoteFunction? = nil
	local classSelectFunction: RemoteFunction? = nil
	local classStateRemote: RemoteEvent? = nil
	local waveStateRemote: RemoteEvent? = nil
	local classIconContentByKey: { [string]: string } = {}

	local function getClassIconsFolder(): Instance?
		return ReplicatedStorage:FindFirstChild(CLASS_ICONS_FOLDER_NAME)
			or ReplicatedStorage:FindFirstChild(CLASS_ICONS_ALT_FOLDER_NAME)
	end

	local function refreshClassIconCache()
		local classIconsFolder = getClassIconsFolder()
		if not classIconsFolder then
			return
		end

		table.clear(classIconContentByKey)
		for _, child in ipairs(classIconsFolder:GetChildren()) do
			local normalizedKey = normalizeIconKey(child.Name)
			local content = readImageContent(child)
			if normalizedKey ~= "" and content then
				classIconContentByKey[normalizedKey] = content
			end
		end
	end

	local function getClassIconContent(classData: any): string?
		if type(classData) ~= "table" then
			return nil
		end

		refreshClassIconCache()

		local candidates = {
			classData.name,
			classData.weaponTag,
			classData.id,
		}

		for _, candidate in ipairs(candidates) do
			local normalizedKey = normalizeIconKey(candidate)
			local content = classIconContentByKey[normalizedKey]
			if normalizedKey ~= "" and content then
				return content
			end
		end

		-- Fallback: ReplicatedStorage ClassIconAssets (e.g. when Rojo doesn't sync PNGs into the ClassIcons folder)
		local classId = type(classData.id) == "string" and normalizeIconKey(classData.id) or ""
		if classId ~= "" then
			local asset = ClassIconAssets[classId]
			if type(asset) == "number" and asset > 0 then
				return "rbxassetid://" .. tostring(asset)
			end
			if type(asset) == "string" and asset ~= "" then
				if asset:find("^rbxassetid://") or asset:find("^rbxthumb://") then
					return asset
				end
				return "rbxassetid://" .. tostring(asset):gsub("%D", "")
			end
		end

		for _, candidate in ipairs(candidates) do
			local gameAssetUri = buildGameAssetIconUri(candidate)
			if gameAssetUri then
				return gameAssetUri
			end
		end

		return nil
	end

	local function setStatus(text: string?, color: Color3?)
		statusLabel.Text = text or ""
		if color then
			statusLabel.TextColor3 = color
		else
			statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
		end
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

	local function applySubtitleFromPayload(payload: ClassPayload)
		local subtitle = panel:FindFirstChild("Subtitle")
		if not subtitle or not subtitle:IsA("TextLabel") then
			return
		end

		if isLobby then
			subtitle.Text = "Your selection will apply in the next match."
			subtitle.TextColor3 = Color3.fromRGB(168, 227, 188)
			return
		end

		local canSwitch = payload.canSwitch == true
		local waveState = payload.waveState or "Unknown"
		if canSwitch then
			subtitle.Text = string.format("Switch available now (%s).", waveState)
			subtitle.TextColor3 = Color3.fromRGB(168, 227, 188)
		else
			subtitle.Text = string.format("Switch locked during active wave (%s).", waveState)
			subtitle.TextColor3 = Color3.fromRGB(245, 155, 155)
		end
	end

	local function renderPayload(payload: ClassPayload)
		if type(payload) ~= "table" then
			return
		end
		if not payload.success then
			setStatus(payload.message or "Could not load class data.", Color3.fromRGB(245, 150, 150))
			return
		end

		clearRows()
		applySubtitleFromPayload(payload)

		local canSwitch = isLobby or (payload.canSwitch == true)
		local maxLevel = getPayloadMaxLevel(payload)
		local currentClassData = nil
		for _, classData in ipairs(payload.classes or {}) do
			if classData.isCurrent then
				currentClassData = classData
				break
			end
		end

		if currentClassData then
			local levelText = string.format("Lv %d/%d", currentClassData.level or 1, maxLevel)
			local xpText = formatXpProgressText(currentClassData.xp, currentClassData.xpToNext)
			currentIcon.Image = getClassIconContent(currentClassData) or ""
			currentInfo.Text = string.format(
				"Current: %s\n%s | %s\nUse the i button next to a class to view bonuses.",
				currentClassData.name or payload.currentClassName or "?",
				levelText,
				xpText
			)
		else
			currentIcon.Image = ""
			currentInfo.Text = "Current class data unavailable."
		end

		for index, classData in ipairs(payload.classes or {}) do
			local row = Instance.new("Frame")
			row.Name = "ClassRow_" .. tostring(index)
			row.Size = UDim2.new(1, -4, 0, 92)
			row.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
			row.BorderSizePixel = 0
			row.LayoutOrder = index
			row.Parent = listFrame

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 8)
			rowCorner.Parent = row

			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.fromOffset(60, 60)
			icon.Position = UDim2.fromOffset(10, 16)
			icon.BackgroundColor3 = Color3.fromRGB(20, 24, 31)
			icon.BackgroundTransparency = 0.06
			icon.BorderSizePixel = 0
			icon.Image = getClassIconContent(classData) or ""
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Parent = row

			local iconCorner = Instance.new("UICorner")
			iconCorner.CornerRadius = UDim.new(0, 8)
			iconCorner.Parent = icon

			local iconStroke = Instance.new("UIStroke")
			iconStroke.Color = Color3.fromRGB(70, 84, 108)
			iconStroke.Transparency = 0.22
			iconStroke.Thickness = 1
			iconStroke.Parent = icon

			local info = Instance.new("TextLabel")
			info.Name = "Info"
			info.Size = UDim2.new(1, -214, 0, 46)
			info.Position = UDim2.fromOffset(80, 6)
			info.BackgroundTransparency = 1
			info.TextWrapped = true
			info.TextXAlignment = Enum.TextXAlignment.Left
			info.TextYAlignment = Enum.TextYAlignment.Top
			info.Font = Enum.Font.GothamSemibold
			info.TextSize = 14
			info.TextColor3 = Color3.fromRGB(228, 233, 240)

			local xpLine = formatXpProgressText(classData.xp, classData.xpToNext)
			info.Text = string.format(
				"%s\nLv %d/%d  |  %s",
				classData.name or classData.id or "?",
				classData.level or 1,
				maxLevel,
				xpLine
			)
			info.Parent = row

			local infoButton = Instance.new("TextButton")
			infoButton.Name = "InfoButton"
			infoButton.Size = UDim2.fromOffset(54, 22)
			infoButton.Position = UDim2.fromOffset(80, 62)
			infoButton.BackgroundColor3 = Color3.fromRGB(46, 70, 98)
			infoButton.BorderSizePixel = 0
			infoButton.TextColor3 = Color3.fromRGB(230, 238, 248)
			infoButton.Font = Enum.Font.GothamSemibold
			infoButton.TextSize = 11
			infoButton.Text = "Info"
			infoButton.Parent = row

			local infoButtonCorner = Instance.new("UICorner")
			infoButtonCorner.CornerRadius = UDim.new(0, 6)
			infoButtonCorner.Parent = infoButton

			local infoButtonStroke = Instance.new("UIStroke")
			infoButtonStroke.Color = Color3.fromRGB(88, 114, 146)
			infoButtonStroke.Transparency = 0.18
			infoButtonStroke.Thickness = 1
			infoButtonStroke.Parent = infoButton

			infoButton.Activated:Connect(function()
				if activeInfoClassId == classData.id and bonusInfoMenu.Visible then
					hideBonusInfoMenu()
					return
				end

				activeInfoClassId = classData.id
				local titleLabel = bonusInfoMenu:FindFirstChild("Title")
				if titleLabel and titleLabel:IsA("TextLabel") then
					titleLabel.Text = string.format("%s Bonuses", classData.name or classData.id or "Class")
				end
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
			elseif classSelectFunction then
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
		if isRefreshing or not classGetDataFunction then
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

	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT)
	if not remotesFolder then
		warn("ClassUi could not find ReplicatedStorage/Remotes")
		return
	end

	if not getClassIconsFolder() then
		-- Wait for icons folder with longer timeout (may not be mounted yet by Rojo)
		local iconsFolder = ReplicatedStorage:FindFirstChild(CLASS_ICONS_FOLDER_NAME)
			or ReplicatedStorage:FindFirstChild(CLASS_ICONS_ALT_FOLDER_NAME)
		if not iconsFolder then
			iconsFolder = ReplicatedStorage:WaitForChild(CLASS_ICONS_FOLDER_NAME, 5)
				or ReplicatedStorage:WaitForChild(CLASS_ICONS_ALT_FOLDER_NAME, 5)
		end
		refreshClassIconCache()
	end

	classGetDataFunction = remotesFolder:WaitForChild(Config.Remotes.ClassGetData, REMOTE_WAIT)
	classSelectFunction = remotesFolder:WaitForChild(Config.Remotes.ClassSelect, REMOTE_WAIT)
	if not classGetDataFunction or not classSelectFunction then
		warn("ClassUi is missing ClassGetData or ClassSelect remote")
		return
	end

	if not isLobby then
		classStateRemote = remotesFolder:FindFirstChild(Config.Remotes.ClassState)
		waveStateRemote = remotesFolder:FindFirstChild(Config.Remotes.WaveState)
	end

	view.openButton.Activated:Connect(function()
		if panel.Visible then
			closePanel()
		else
			openPanel()
		end
	end)

	view.closeButton.Activated:Connect(closePanel)
	bonusInfoCloseButton.Activated:Connect(hideBonusInfoMenu)

	if classStateRemote and classStateRemote:IsA("RemoteEvent") then
		classStateRemote.OnClientEvent:Connect(function(payload: ClassPayload)
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

	task.defer(refreshPayload)
end

return {
	run = run,
}

