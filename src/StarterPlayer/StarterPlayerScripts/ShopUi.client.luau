local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponShopUi"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.Size = UDim2.fromOffset(520, 430)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(75, 95, 120)
panelStroke.Transparency = 0.18
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -54, 0, 36)
title.Position = UDim2.fromOffset(18, 10)
title.BackgroundTransparency = 1
title.Text = "Weapon Trader"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(245, 248, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, -24, 0, 22)
subtitle.Position = UDim2.fromOffset(18, 46)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Buy only between waves"
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextColor3 = Color3.fromRGB(175, 190, 205)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Position = UDim2.new(1, -42, 0, 10)
closeButton.BackgroundColor3 = Color3.fromRGB(52, 56, 70)
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(240, 240, 245)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.Parent = panel

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 8)
closeButtonCorner.Parent = closeButton

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "ItemList"
listFrame.Size = UDim2.new(1, -24, 1, -128)
listFrame.Position = UDim2.fromOffset(12, 76)
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
statusLabel.Size = UDim2.new(1, -24, 0, 28)
statusLabel.Position = UDim2.new(0, 12, 1, -34)
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
statusLabel.Font = Enum.Font.GothamSemibold
statusLabel.TextSize = 14
statusLabel.Parent = panel

local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, 15)
if not remotesFolder then
	warn("ShopUi could not find ReplicatedStorage/Remotes")
	return
end

local shopOpenRemote = remotesFolder:WaitForChild(Config.Remotes.ShopOpen, 15)
local shopGetCatalogFunction = remotesFolder:WaitForChild(Config.Remotes.ShopGetCatalog, 15)
local shopBuyWeaponFunction = remotesFolder:WaitForChild(Config.Remotes.ShopBuyWeapon, 15)
local waveStateRemote = remotesFolder:FindFirstChild(Config.Remotes.WaveState)

if not shopOpenRemote or not shopGetCatalogFunction or not shopBuyWeaponFunction then
	warn("ShopUi is missing one or more shop remotes")
	return
end

local isRefreshing = false
local refreshCatalog

local function setStatus(text, color)
	statusLabel.Text = text or ""
	if color then
		statusLabel.TextColor3 = color
	else
		statusLabel.TextColor3 = Color3.fromRGB(225, 235, 245)
	end
end

local function clearItems()
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function renderCatalog(catalog)
	clearItems()

	local canPurchase = catalog.canPurchase == true
	local waveState = catalog.waveState or "Unknown"
	if canPurchase then
		subtitle.Text = "Buy only between waves | Store OPEN"
		subtitle.TextColor3 = Color3.fromRGB(165, 230, 185)
	else
		subtitle.Text = string.format("Store CLOSED while wave is active (%s)", waveState)
		subtitle.TextColor3 = Color3.fromRGB(245, 155, 155)
	end

	for index, weapon in ipairs(catalog.weapons or {}) do
		local row = Instance.new("Frame")
		row.Name = "WeaponRow_" .. tostring(index)
		row.Size = UDim2.new(1, -4, 0, 64)
		row.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = listFrame

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.Size = UDim2.new(1, -146, 1, 0)
		info.Position = UDim2.fromOffset(10, 0)
		info.BackgroundTransparency = 1
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.TextYAlignment = Enum.TextYAlignment.Center
		info.TextWrapped = true
		info.Font = Enum.Font.GothamSemibold
		info.TextSize = 14
		info.TextColor3 = Color3.fromRGB(228, 233, 240)
		info.Text = string.format(
			"%s  |  $%d\nDMG %d  RANGE %d  CD %.2fs",
			weapon.name or weapon.id or "?",
			weapon.cost or 0,
			weapon.damage or 0,
			weapon.range or 0,
			weapon.cooldown or 0
		)
		info.Parent = row

		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.fromOffset(118, 40)
		buyButton.Position = UDim2.new(1, -126, 0.5, -20)
		buyButton.BackgroundColor3 = Color3.fromRGB(52, 96, 68)
		buyButton.BorderSizePixel = 0
		buyButton.TextColor3 = Color3.fromRGB(240, 245, 240)
		buyButton.Font = Enum.Font.GothamBold
		buyButton.TextSize = 14
		buyButton.Text = "Buy"
		buyButton.Parent = row

		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0, 8)
		buyCorner.Parent = buyButton

		local disabled = false
		if weapon.owned then
			disabled = true
			buyButton.Text = "Owned"
			buyButton.BackgroundColor3 = Color3.fromRGB(62, 64, 72)
		elseif not canPurchase then
			disabled = true
			buyButton.Text = "Wave Active"
			buyButton.BackgroundColor3 = Color3.fromRGB(78, 52, 52)
		end

		if disabled then
			buyButton.AutoButtonColor = false
		else
			buyButton.Activated:Connect(function()
				local ok, result = pcall(function()
					return shopBuyWeaponFunction:InvokeServer(weapon.id)
				end)

				if not ok then
					setStatus("Purchase failed: remote error.", Color3.fromRGB(245, 150, 150))
					return
				end

				if result and result.success then
					setStatus(result.message or "Purchase successful.", Color3.fromRGB(165, 230, 185))
				else
					setStatus((result and result.message) or "Purchase denied.", Color3.fromRGB(245, 150, 150))
				end

				if panel.Visible then
					task.defer(function()
						if panel.Visible then
							refreshCatalog()
						end
					end)
				end
			end)
		end
	end
end

refreshCatalog = function()
	if isRefreshing then
		return
	end

	isRefreshing = true
	local ok, catalog = pcall(function()
		return shopGetCatalogFunction:InvokeServer()
	end)
	isRefreshing = false

	if not ok or not catalog or not catalog.success then
		setStatus("Could not load shop data.", Color3.fromRGB(245, 150, 150))
		return
	end

	renderCatalog(catalog)
end

local function openShop()
	panel.Visible = true
	setStatus("Choose your weapon.", Color3.fromRGB(210, 225, 240))
	refreshCatalog()
end

local function closeShop()
	panel.Visible = false
	setStatus("")
end

closeButton.Activated:Connect(closeShop)

shopOpenRemote.OnClientEvent:Connect(function()
	openShop()
end)

if waveStateRemote and waveStateRemote:IsA("RemoteEvent") then
	waveStateRemote.OnClientEvent:Connect(function()
		if panel.Visible then
			refreshCatalog()
		end
	end)
end
