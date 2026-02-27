local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.GameConfig)
local ViewModule = require(script.Parent:WaitForChild("ShopUiView"))

local REMOTE_WAIT = 15

local STATUS_SUCCESS = Color3.fromRGB(165, 230, 185)
local STATUS_ERROR = Color3.fromRGB(245, 150, 150)
local STATUS_INFO = Color3.fromRGB(210, 225, 240)
local STATUS_EMPTY = Color3.fromRGB(235, 195, 140)
local SUBTITLE_OPEN = Color3.fromRGB(165, 230, 185)
local SUBTITLE_CLOSED = Color3.fromRGB(245, 155, 155)
local BUTTON_ENABLED = Color3.fromRGB(52, 96, 68)
local BUTTON_DISABLED = Color3.fromRGB(62, 64, 72)
local BUTTON_CLOSED = Color3.fromRGB(78, 52, 52)
local BUTTON_LOCKED = Color3.fromRGB(76, 70, 52)
local started = false

local function run()
	if started then
		return
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Remotes.Folder, REMOTE_WAIT)
	if not remotesFolder then
		warn("ShopUi could not find ReplicatedStorage/Remotes")
		return
	end

	local shopOpenRemote = remotesFolder:WaitForChild(Config.Remotes.ShopOpen, REMOTE_WAIT)
	local shopGetCatalogFunction = remotesFolder:WaitForChild(Config.Remotes.ShopGetCatalog, REMOTE_WAIT)
	local shopBuyWeaponFunction = remotesFolder:WaitForChild(Config.Remotes.ShopBuyWeapon, REMOTE_WAIT)
	local shopBuyAmmoFunction = remotesFolder:WaitForChild(Config.Remotes.ShopBuyAmmo, REMOTE_WAIT)
	local waveStateRemote = remotesFolder:FindFirstChild(Config.Remotes.WaveState)
	local classStateRemote = remotesFolder:FindFirstChild(Config.Remotes.ClassState)

	if not shopOpenRemote or not shopGetCatalogFunction or not shopBuyWeaponFunction or not shopBuyAmmoFunction then
		warn("ShopUi is missing one or more shop remotes")
		return
	end

	local view = ViewModule.build()
	started = true
	local panel = view.panel
	local listFrame = view.listFrame
	local refillAllButton = view.refillAllButton

	local isRefreshing = false
	local refillAllPurchaseEnabled = false
	local refreshCatalog

	local function resetRefillAllButton()
		refillAllPurchaseEnabled = false
		refillAllButton.AutoButtonColor = false
		refillAllButton.Text = "Refill All Owned"
		refillAllButton.BackgroundColor3 = BUTTON_DISABLED
	end

	local function refreshVisibleCatalog()
		if panel.Visible then
			task.defer(function()
				if panel.Visible then
					refreshCatalog()
				end
			end)
		end
	end

	local function applyShopAction(callback)
		local ok, result = pcall(callback)
		if not ok then
			view.setStatus("Shop action failed: remote error.", STATUS_ERROR)
			return nil
		end

		if result and result.success then
			view.setStatus(result.message or "Shop action successful.", STATUS_SUCCESS)
		else
			view.setStatus((result and result.message) or "Shop action denied.", STATUS_ERROR)
		end

		refreshVisibleCatalog()
		return result
	end

	local function renderCatalog(catalog)
		view.clearRows()

		local canPurchase = catalog.canPurchase == true
		local waveState = catalog.waveState or "Unknown"
		if canPurchase then
			view.setSubtitle("Buy only between waves | Store OPEN", SUBTITLE_OPEN)
		else
			view.setSubtitle(string.format("Store CLOSED while wave is active (%s)", waveState), SUBTITLE_CLOSED)
		end

		local refillAllCost = math.max(0, math.floor((tonumber(catalog.refillAllCost) or 0) + 0.5))
		local canRefillAll = catalog.canRefillAll == true and refillAllCost > 0
		resetRefillAllButton()
		if not canPurchase then
			refillAllButton.Text = "Refill All (Wave Active)"
			refillAllButton.BackgroundColor3 = BUTTON_CLOSED
		elseif canRefillAll then
			refillAllPurchaseEnabled = true
			refillAllButton.AutoButtonColor = true
			refillAllButton.Text = string.format("Refill All Owned ($%d)", refillAllCost)
			refillAllButton.BackgroundColor3 = BUTTON_ENABLED
		else
			local ownedRefillable = math.max(0, math.floor((tonumber(catalog.ownedRefillableWeapons) or 0) + 0.5))
			if ownedRefillable <= 0 then
				refillAllButton.Text = "No Owned Ammo Weapons"
			else
				refillAllButton.Text = "All Owned Ammo Full"
			end
		end

		local renderedCount = 0
		for index, weapon in ipairs(catalog.weapons or {}) do
			renderedCount += 1

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

			local ammoLine = ""
			if type(weapon.magazineSize) == "number" and weapon.magazineSize > 0 then
				local reloadSeconds = tonumber(weapon.reloadSeconds) or 0
				ammoLine = string.format("  MAG %d  RELOAD %.1fs", weapon.magazineSize, reloadSeconds)
			end

			local displayedRange = math.max(0, math.floor((tonumber(weapon.effectiveRange) or tonumber(weapon.range) or 0) + 0.5))
			local rangeText = string.format("RANGE %d", displayedRange)
			local rangeBonusPct = tonumber(weapon.rangeBonusPct) or 0
			if rangeBonusPct >= 0.05 then
				rangeText = string.format("RANGE %d (+%.1f%% class)", displayedRange, rangeBonusPct)
			end

			local ownedAmmoLine = ""
			if weapon.owned and type(weapon.currentAmmoTotal) == "number" and type(weapon.maxAmmoTotal) == "number" and weapon.maxAmmoTotal > 0 then
				local currentTotal = math.max(0, math.floor((tonumber(weapon.currentAmmoTotal) or 0) + 0.5))
				local maxTotal = math.max(0, math.floor((tonumber(weapon.maxAmmoTotal) or 0) + 0.5))
				ownedAmmoLine = string.format("  AMMO %d/%d", currentTotal, maxTotal)
			end

			local upgradeLine = ""
			if not weapon.owned and type(weapon.requiresWeaponName) == "string" and weapon.requiresWeaponName ~= "" then
				if weapon.upgradeLocked == true then
					upgradeLine = string.format("  REQUIRES %s", string.upper(weapon.requiresWeaponName))
				else
					upgradeLine = string.format("  UPGRADE FROM %s", string.upper(weapon.requiresWeaponName))
				end
			end

			info.Text = string.format(
				"%s (%s)  |  $%d\nDMG %d  %s  CD %.2fs%s%s%s",
				weapon.name or weapon.id or "?",
				weapon.weaponClass or "Weapon",
				weapon.cost or 0,
				weapon.damage or 0,
				rangeText,
				weapon.cooldown or 0,
				ammoLine,
				ownedAmmoLine,
				upgradeLine
			)
			info.Parent = row

			local buyButton = Instance.new("TextButton")
			buyButton.Name = "BuyButton"
			buyButton.Size = UDim2.fromOffset(118, 40)
			buyButton.Position = UDim2.new(1, -126, 0.5, -20)
			buyButton.BackgroundColor3 = BUTTON_ENABLED
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
			local isAmmoPurchase = false
			local refillCost = math.max(0, math.floor((tonumber(weapon.refillCost) or 0) + 0.5))
			if weapon.owned then
				if weapon.isRefillable ~= true then
					disabled = true
					buyButton.Text = "No Ammo"
					buyButton.BackgroundColor3 = BUTTON_DISABLED
				elseif not canPurchase then
					disabled = true
					buyButton.Text = "Wave Active"
					buyButton.BackgroundColor3 = BUTTON_CLOSED
				elseif weapon.canRefill == true and refillCost > 0 then
					isAmmoPurchase = true
					buyButton.Text = string.format("Refill $%d", refillCost)
				else
					disabled = true
					buyButton.Text = "Full Ammo"
					buyButton.BackgroundColor3 = BUTTON_DISABLED
				end
			elseif not canPurchase then
				disabled = true
				buyButton.Text = "Wave Active"
				buyButton.BackgroundColor3 = BUTTON_CLOSED
			elseif weapon.upgradeLocked == true then
				disabled = true
				local requiredName = tostring(weapon.requiresWeaponName or weapon.requiresWeaponId or "Upgrade")
				buyButton.Text = string.format("Needs %s", requiredName)
				buyButton.BackgroundColor3 = BUTTON_LOCKED
			end

			if disabled then
				buyButton.AutoButtonColor = false
			else
				buyButton.AutoButtonColor = true
				buyButton.Activated:Connect(function()
					if isAmmoPurchase then
						applyShopAction(function()
							return shopBuyAmmoFunction:InvokeServer({
								weaponId = weapon.id,
							})
						end)
						return
					end

					applyShopAction(function()
						return shopBuyWeaponFunction:InvokeServer(weapon.id)
					end)
				end)
			end
		end

		if renderedCount == 0 then
			view.setStatus("No weapons available for your current class.", STATUS_EMPTY)
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

		if ok and type(catalog) == "table" and catalog.success then
			renderCatalog(catalog)
			return
		end

		view.clearRows()
		resetRefillAllButton()

		local failureMessage = "Could not load shop data."
		local waveState = "Unknown"
		if type(catalog) == "table" then
			if type(catalog.message) == "string" and catalog.message ~= "" then
				failureMessage = catalog.message
			end
			if type(catalog.waveState) == "string" and catalog.waveState ~= "" then
				waveState = catalog.waveState
			end
		end

		view.setSubtitle(string.format("Store unavailable (%s)", waveState), SUBTITLE_CLOSED)
		view.setStatus(failureMessage, STATUS_ERROR)
	end

	local function openShop()
		panel.Visible = true
		view.setStatus("Buy weapons or refill owned ammo.", STATUS_INFO)
		refreshCatalog()
	end

	local function closeShop()
		panel.Visible = false
		view.setStatus(nil)
	end

	view.closeButton.Activated:Connect(closeShop)

	refillAllButton.Activated:Connect(function()
		if not refillAllPurchaseEnabled then
			return
		end

		applyShopAction(function()
			return shopBuyAmmoFunction:InvokeServer({
				allOwned = true,
			})
		end)
	end)

	shopOpenRemote.OnClientEvent:Connect(function()
		openShop()
	end)

	if waveStateRemote and waveStateRemote:IsA("RemoteEvent") then
		waveStateRemote.OnClientEvent:Connect(function(payload)
			local stateName = nil
			if type(payload) == "table" then
				stateName = payload.state
			end
			if type(stateName) ~= "string" then
				stateName = remotesFolder:GetAttribute("CurrentWaveState")
			end

			if stateName == "InProgress" and panel.Visible then
				closeShop()
				return
			end

			if panel.Visible then
				refreshCatalog()
			end
		end)
	end

	if classStateRemote and classStateRemote:IsA("RemoteEvent") then
		classStateRemote.OnClientEvent:Connect(function()
			if panel.Visible then
				refreshCatalog()
			end
		end)
	end
end

return {
	run = run,
}
