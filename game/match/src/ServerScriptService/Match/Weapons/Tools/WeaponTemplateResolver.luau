--[[
	WeaponTemplateResolver — Resolves and clones weapon/sentry templates from ServerStorage.ShopItems.
	Uses a lightweight cache so repeated template lookups do not re-scan the full folder tree.
]]

local ServerStorage = game:GetService("ServerStorage")

local WeaponTemplateResolver = {}
local SENTRY_TEMPLATE_PREPARED_ATTR = "SentryTemplatePrepared"
local SENTRY_TEMPLATE_PREPARING_ATTR = "SentryTemplatePreparing"
local TOOL_SKIP_PREPARE_PARTS_ATTR = "SkipPrepareToolParts"
local PREVIEW_TRANSPARENCY_ATTR = "PreviewTransparency"

local templateCache = {
	folder = nil,
	candidates = {},
	isDirty = true,
	connections = {},
}

local function clearCacheConnections()
	for _, connection in ipairs(templateCache.connections) do
		connection:Disconnect()
	end
	table.clear(templateCache.connections)
end

local function markCacheDirty()
	templateCache.isDirty = true
end

local function bindCacheFolder(folder)
	if templateCache.folder == folder then
		return
	end

	clearCacheConnections()
	templateCache.folder = folder
	templateCache.isDirty = true
	table.clear(templateCache.candidates)

	if not folder then
		return
	end

	table.insert(templateCache.connections, folder.DescendantAdded:Connect(markCacheDirty))
	table.insert(templateCache.connections, folder.DescendantRemoving:Connect(markCacheDirty))
	table.insert(templateCache.connections, folder.AncestryChanged:Connect(markCacheDirty))
end

local function normalizeTemplateKey(value)
	if type(value) ~= "string" then
		return ""
	end
	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function keyMatches(candidateKey, queryKey)
	if queryKey == "" then
		return false
	end
	if candidateKey == queryKey then
		return true
	end
	if not string.find(candidateKey, queryKey, 1, true) then
		return false
	end
	if #queryKey <= 2 then
		return string.sub(candidateKey, 1, #queryKey) == queryKey
	end
	return true
end

local function isTemplateCandidate(instance)
	return instance:IsA("Tool") or instance:IsA("Model") or instance:IsA("BasePart")
end

local function collectTemplateCandidates(container, out)
	for _, child in ipairs(container:GetChildren()) do
		if isTemplateCandidate(child) then
			table.insert(out, child)
		elseif child:IsA("Folder") then
			collectTemplateCandidates(child, out)
		end
	end
end

local function getTemplateCandidates(folder)
	if not folder then
		return {}
	end

	bindCacheFolder(folder)
	if templateCache.isDirty then
		table.clear(templateCache.candidates)
		collectTemplateCandidates(folder, templateCache.candidates)
		templateCache.isDirty = false
	end
	return templateCache.candidates
end

local function getTemplateCandidateMatchScore(candidate, weaponDef, templateNameLower, templateNameKey, idLower, nameLower, idKey, nameKey)
	local candidateNameLower = string.lower(candidate.Name)
	local candidateKey = normalizeTemplateKey(candidate.Name)
	local bestScore = nil

	local function considerScore(score)
		if type(score) ~= "number" then
			return
		end
		if bestScore == nil or score > bestScore then
			bestScore = score
		end
	end

	if templateNameLower ~= "" and candidateNameLower == templateNameLower then
		considerScore(900)
	end
	if templateNameKey ~= "" and candidateKey == templateNameKey then
		considerScore(880)
	elseif keyMatches(candidateKey, templateNameKey) then
		considerScore(620)
	end
	if candidateNameLower == idLower or candidateNameLower == nameLower then
		considerScore(860)
	end
	if idKey ~= "" and candidateKey == idKey then
		considerScore(840)
	elseif keyMatches(candidateKey, idKey) then
		considerScore(580)
	end
	if nameKey ~= "" and candidateKey == nameKey then
		considerScore(820)
	elseif keyMatches(candidateKey, nameKey) then
		considerScore(560)
	end

	local attributeKey = normalizeTemplateKey(
		candidate:GetAttribute("WeaponId")
			or candidate:GetAttribute("ShopWeaponId")
			or candidate:GetAttribute("TemplateId")
	)
	if attributeKey ~= "" then
		if attributeKey == templateNameKey then
			considerScore(980)
		end
		if attributeKey == idKey or attributeKey == nameKey then
			considerScore(960)
		end
	end

	if bestScore == nil then
		return nil
	end

	local weaponClassKey = normalizeTemplateKey(weaponDef and weaponDef.WeaponClass)
	if weaponClassKey == "sentrydeployer" then
		if candidate:IsA("Model") then
			bestScore += 250
		end
		if string.find(candidateKey, "sentry", 1, true) then
			bestScore += 400
		end
	end

	return bestScore
end

local function createCenterHandleForModel(model, tool)
	local ok, bboxCFrame, bboxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not bboxCFrame then
		return nil
	end

	local oldHandle = model:FindFirstChild("Handle", true)
	if oldHandle and oldHandle:IsA("BasePart") then
		oldHandle.Name = "VisualHandle"
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(
		math.clamp((bboxSize and bboxSize.X or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Y or 1) * 0.15, 0.2, 1),
		math.clamp((bboxSize and bboxSize.Z or 1) * 0.15, 0.2, 1)
	)
	handle.CFrame = bboxCFrame
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Anchored = false
	handle.Parent = tool
	return handle
end

local function prepareSentryPreviewModelForTool(model)
	if not model or not model:IsA("Model") then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant:GetAttribute(PREVIEW_TRANSPARENCY_ATTR) == nil then
				descendant:SetAttribute(PREVIEW_TRANSPARENCY_ATTR, descendant.Transparency)
			end
			descendant.Transparency = 1
		end
	end
end

local function stripLegacyToolScripts(tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function ensureDirectToolHandle(tool)
	stripLegacyToolScripts(tool)

	local directHandle = tool:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end
	if directHandle then
		directHandle.Name = "VisualHandle"
	end

	local nestedHandle = tool:FindFirstChild("Handle", true)
	if nestedHandle and nestedHandle:IsA("BasePart") then
		nestedHandle.Parent = tool
		return nestedHandle
	end

	local firstPart = tool:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		firstPart.Name = "Handle"
		firstPart.Parent = tool
		return firstPart
	end

	return nil
end

local function isSentryDeployerDefinition(weaponDef)
	return normalizeTemplateKey(weaponDef and weaponDef.WeaponClass) == "sentrydeployer"
end

local function prepareSentryTemplateModel(template)
	if not template or not template:IsA("Model") then
		return
	end
	if template:GetAttribute(SENTRY_TEMPLATE_PREPARED_ATTR) == true then
		return
	end

	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = true
			descendant.CanQuery = true
		end
	end

	template:SetAttribute(SENTRY_TEMPLATE_PREPARED_ATTR, true)
end

local function scheduleSentryTemplatePreparation(template)
	if not template or not template:IsA("Model") then
		return
	end
	if template:GetAttribute(SENTRY_TEMPLATE_PREPARED_ATTR) == true then
		return
	end
	if template:GetAttribute(SENTRY_TEMPLATE_PREPARING_ATTR) == true then
		return
	end

	template:SetAttribute(SENTRY_TEMPLATE_PREPARING_ATTR, true)
	task.defer(function()
		if template.Parent then
			prepareSentryTemplateModel(template)
		end
		if template.Parent then
			template:SetAttribute(SENTRY_TEMPLATE_PREPARING_ATTR, nil)
		end
	end)
end

function WeaponTemplateResolver.findShopItemTemplate(weaponDef)
	local shopItemsFolder = ServerStorage:FindFirstChild("ShopItems")
	if not shopItemsFolder then
		bindCacheFolder(nil)
		return nil
	end

	local templateName = weaponDef.TemplateName
	local templateNameLower = string.lower(templateName or "")
	local templateNameKey = normalizeTemplateKey(templateName)
	local idLower = string.lower(weaponDef.Id or "")
	local nameLower = string.lower(weaponDef.DisplayName or "")
	local idKey = normalizeTemplateKey(weaponDef.Id)
	local nameKey = normalizeTemplateKey(weaponDef.DisplayName)
	local bestCandidate = nil
	local bestScore = nil

	for _, candidate in ipairs(getTemplateCandidates(shopItemsFolder)) do
		if candidate.Parent then
			local score = getTemplateCandidateMatchScore(
				candidate,
				weaponDef,
				templateNameLower,
				templateNameKey,
				idLower,
				nameLower,
				idKey,
				nameKey
			)
			if score ~= nil and (bestScore == nil or score > bestScore) then
				bestCandidate = candidate
				bestScore = score
			end
		end
	end

	if bestCandidate and isSentryDeployerDefinition(weaponDef) and bestCandidate:IsA("Model") then
		scheduleSentryTemplatePreparation(bestCandidate)
	end
	return bestCandidate
end

function WeaponTemplateResolver.buildSentryModelFromTemplate(weaponDef)
	local template = WeaponTemplateResolver.findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Model") then
		if isSentryDeployerDefinition(weaponDef) then
			prepareSentryTemplateModel(template)
		end
		return template:Clone()
	end
	if template:IsA("Tool") then
		local clonedTool = template:Clone()
		local model = Instance.new("Model")
		model.Name = clonedTool.Name
		for _, child in ipairs(clonedTool:GetChildren()) do
			child.Parent = model
		end
		clonedTool:Destroy()
		if not model:FindFirstChildWhichIsA("BasePart", true) then
			model:Destroy()
			return nil
		end
		return model
	end
	if template:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = template.Name
		local part = template:Clone()
		part.Parent = model
		return model
	end
	return nil
end

function WeaponTemplateResolver.createToolFromTemplate(weaponDef)
	local template = WeaponTemplateResolver.findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Tool") then
		local tool = template:Clone()
		if ensureDirectToolHandle(tool) then
			return tool
		end

		tool:Destroy()
		warn(string.format("Shop item template '%s' has no usable BasePart handle", template.Name))
		return nil
	end

	local tool = Instance.new("Tool")

	if template:IsA("Model") then
		local cloned = template:Clone()
		cloned.Parent = tool
		local handle = createCenterHandleForModel(cloned, tool)
		if not (handle and handle:IsA("BasePart")) then
			tool:Destroy()
			warn(string.format("Shop item template '%s' could not create centered handle", template.Name))
			return nil
		end
		if isSentryDeployerDefinition(weaponDef) then
			prepareSentryPreviewModelForTool(cloned)
			tool:SetAttribute(TOOL_SKIP_PREPARE_PARTS_ATTR, true)
		end
		tool:SetAttribute("TurretPlacementReferenceMode", "BoundsCenter")
		return tool
	end
	if template:IsA("BasePart") then
		local cloned = template:Clone()
		cloned.Name = "Handle"
		cloned.Parent = tool
		return tool
	end

	tool:Destroy()
	warn(string.format("Shop item template '%s' is unsupported type %s", template.Name, template.ClassName))
	return nil
end

return WeaponTemplateResolver
