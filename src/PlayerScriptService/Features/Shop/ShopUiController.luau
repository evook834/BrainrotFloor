--[[
	ShopUiController — Orchestrates shop UI: remotes, catalog fetch, render, and purchase flow.
	Uses ShopUiRemotes (resolution), ShopUiConstants (colors), ShopUiCatalogDisplay (catalog/row state),
	and ShopUiView (UI tree and row structure).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ViewModule = require(script.Parent:WaitForChild("ShopUiView"))
local ShopUiRemotes = require(script.Parent:WaitForChild("ShopUiRemotes"))
local ShopUiConstants = require(script.Parent:WaitForChild("ShopUiConstants"))
local ShopUiCatalogDisplay = require(script.Parent:WaitForChild("ShopUiCatalogDisplay"))
local ShopUiMessages = require(script.Parent:WaitForChild("ShopUiMessages"))
local Config = require(ReplicatedStorage.Shared.GameConfig)
local ClassChangedClientEvent = require(ReplicatedStorage.Shared.Classes.ClassChangedClientEvent)

local started = false
local PROMINENT_STATUS_MESSAGE = "Not enough money."

local function run()
	if started then
		return
	end

	local remotesResult = ShopUiRemotes.resolve()
	if not remotesResult.allRequiredPresent then
		return
	end

	local shopOpenRemote = remotesResult.shopOpen
	local shopGetCatalogFunction = remotesResult.shopGetCatalog
	local shopBuyWeaponFunction = remotesResult.shopBuyWeapon
	local shopBuyAmmoFunction = remotesResult.shopBuyAmmo
	local waveStateRemote = remotesResult.waveState
	local classStateRemote = remotesResult.classState
	local remotesFolder = remotesResult.remotesFolder

	local view = ViewModule.build()
	started = true
	local panel = view.panel
	local listFrame = view.listFrame
	local refillAllButton = view.refillAllButton

	local isRefreshing = false
	local pendingRefreshAfterCurrent = false -- when a refresh is skipped due to isRefreshing, re-request after current completes
	local refillAllPurchaseEnabled = false
	local refreshCatalog
	local openSessionToken = 0

	local function applyShopAction(callback)
		local ok, result = pcall(callback)
		if not ok then
			view.setStatus(ShopUiMessages.ShopActionFailedRemote, ShopUiConstants.StatusError)
			return nil
		end

		if result and result.success then
			view.setStatus(result.message or ShopUiMessages.ShopActionSuccessDefault, ShopUiConstants.StatusSuccess)
		else
			local deniedMessage = (result and result.message) or ShopUiMessages.ShopActionDeniedDefault
			view.setStatus(deniedMessage, ShopUiConstants.StatusError, {
				prominent = deniedMessage == PROMINENT_STATUS_MESSAGE,
			})
		end

		if panel.Visible then
				task.defer(function()
					if panel.Visible then
						refreshCatalog()
					end
				end)
			end
		return result
	end

	local function renderCatalog(catalog)
		view.clearRows()

		local subtitle = ShopUiCatalogDisplay.getSubtitleForCatalog(catalog)
		view.setSubtitle(subtitle.text, subtitle.color)

		local canPurchase = catalog.canPurchase == true
		local refillState = ShopUiCatalogDisplay.getRefillAllButtonState(catalog)
		refillAllPurchaseEnabled = refillState.enabled
		refillAllButton.AutoButtonColor = refillState.autoButtonColor
		refillAllButton.Text = refillState.text
		refillAllButton.BackgroundColor3 = refillState.backgroundColor

		local weapons = catalog.weapons or {}
		for index, weapon in ipairs(weapons) do
			local rowRefs = view.buildWeaponRow(listFrame, index)
			rowRefs.infoLabel.Text = ShopUiCatalogDisplay.buildWeaponInfoText(weapon)

			local rowState = ShopUiCatalogDisplay.getWeaponRowButtonState(weapon, canPurchase)
			rowRefs.buyButton.Text = rowState.text
			rowRefs.buyButton.BackgroundColor3 = rowState.backgroundColor
			rowRefs.buyButton.AutoButtonColor = not rowState.disabled

			if not rowState.disabled then
				local weaponId = weapon.id
				local isAmmoPurchase = rowState.isAmmoPurchase
				rowRefs.buyButton.Activated:Connect(function()
					if isAmmoPurchase then
						applyShopAction(function()
							return shopBuyAmmoFunction:InvokeServer({ weaponId = weaponId })
						end)
					else
						applyShopAction(function()
							return shopBuyWeaponFunction:InvokeServer(weaponId)
						end)
					end
				end)
			end
		end

		if #weapons == 0 then
			view.setStatus(ShopUiMessages.EmptyCatalogStatus, ShopUiConstants.StatusEmpty)
		end
	end

	refreshCatalog = function()
		if isRefreshing then
			pendingRefreshAfterCurrent = true
			return
		end
		isRefreshing = true
		local ok, catalog = pcall(function()
			return shopGetCatalogFunction:InvokeServer()
		end)
		isRefreshing = false

		if ok and type(catalog) == "table" and catalog.success then
			renderCatalog(catalog)
		end

		-- If a class-change (or other) refresh was skipped while we were loading, run one now.
		if pendingRefreshAfterCurrent then
			pendingRefreshAfterCurrent = false
			task.defer(function()
				if panel.Visible then
					refreshCatalog()
				end
			end)
			return
		end
		if ok and type(catalog) == "table" and catalog.success then
			return
		end

		local failure = ShopUiCatalogDisplay.getCatalogFailureDisplay(catalog)
		view.clearRows()
		refillAllPurchaseEnabled = false
		refillAllButton.AutoButtonColor = false
		refillAllButton.Text = failure.refillText
		refillAllButton.BackgroundColor3 = failure.refillColor
		view.setSubtitle(failure.subtitleText, failure.subtitleColor)
		view.setStatus(failure.statusMessage, failure.statusColor)
	end

	local function openShop()
		openSessionToken += 1
		panel.Visible = true
		view.setStatus(ShopUiMessages.OpenStatusHint, ShopUiConstants.StatusInfo)
		refreshCatalog()
		-- Deferred second refresh so catalog reflects server state after any replication/ordering delay.
		task.defer(function()
			if panel.Visible then
				refreshCatalog()
			end
		end)

		local sessionToken = openSessionToken
		task.spawn(function()
			while panel.Visible and openSessionToken == sessionToken do
				task.wait(1)
				if not panel.Visible or openSessionToken ~= sessionToken then
					break
				end
				refreshCatalog()
			end
		end)
	end

	local function closeShop()
		openSessionToken += 1
		panel.Visible = false
		view.setStatus(nil)
	end

	view.closeButton.Activated:Connect(closeShop)

	refillAllButton.Activated:Connect(function()
		if not refillAllPurchaseEnabled then
			return
		end
		applyShopAction(function()
			return shopBuyAmmoFunction:InvokeServer({ allOwned = true })
		end)
	end)

	shopOpenRemote.OnClientEvent:Connect(openShop)

	if waveStateRemote then
		waveStateRemote.OnClientEvent:Connect(function(payload)
			local stateName = nil
			if type(payload) == "table" then
				stateName = payload.state
			end
			if type(stateName) ~= "string" and remotesFolder then
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

	local function connectClassStateRefresh(remote)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function()
				if panel.Visible then
					refreshCatalog()
				end
			end)
		end
	end

	if classStateRemote then
		connectClassStateRefresh(classStateRemote)
	elseif remotesFolder then
		-- ClassState may not exist yet (e.g. Match remotes still replicating). Subscribe when it appears.
		task.spawn(function()
			local r = remotesFolder:WaitForChild(Config.Remotes.ClassState, 5)
			connectClassStateRefresh(r)
		end)
	end

	-- Refresh shop when class is changed in UI (does not rely on ClassState replication).
	ClassChangedClientEvent.connect(function()
		if panel.Visible then
			refreshCatalog()
		end
	end)
end

return {
	run = run,
}
