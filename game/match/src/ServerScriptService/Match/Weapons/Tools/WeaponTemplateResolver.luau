--[[
	WeaponTemplateResolver — Resolves and clones weapon/sentry templates from ServerStorage.ShopItems.
	Uses a lightweight cache so repeated template lookups do not re-scan the full folder tree.
]]

local ServerStorage = game:GetService("ServerStorage")

local WeaponTemplateResolver = {}

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

local function matchesTemplateCandidate(candidate, templateNameLower, templateNameKey, idLower, nameLower, idKey, nameKey)
	local candidateNameLower = string.lower(candidate.Name)
	local candidateKey = normalizeTemplateKey(candidate.Name)

	if templateNameLower ~= "" and candidateNameLower == templateNameLower then
		return true
	end
	if keyMatches(candidateKey, templateNameKey) then
		return true
	end
	if candidateNameLower == idLower or candidateNameLower == nameLower then
		return true
	end
	if keyMatches(candidateKey, idKey) then
		return true
	end
	if keyMatches(candidateKey, nameKey) then
		return true
	end
	local attributeKey = normalizeTemplateKey(
		candidate:GetAttribute("WeaponId")
			or candidate:GetAttribute("ShopWeaponId")
			or candidate:GetAttribute("TemplateId")
	)
	if attributeKey ~= "" and (attributeKey == idKey or attributeKey == nameKey or attributeKey == templateNameKey) then
		return true
	end
	return false
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

	for _, candidate in ipairs(getTemplateCandidates(shopItemsFolder)) do
		if candidate.Parent and matchesTemplateCandidate(candidate, templateNameLower, templateNameKey, idLower, nameLower, idKey, nameKey) then
			return candidate
		end
	end
	return nil
end

function WeaponTemplateResolver.buildSentryModelFromTemplate(weaponDef)
	local template = WeaponTemplateResolver.findShopItemTemplate(weaponDef)
	if not template then
		return nil
	end

	if template:IsA("Model") then
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
		return template:Clone()
	end

	local tool = Instance.new("Tool")
	local cloned = template:Clone()

	if template:IsA("Model") then
		cloned.Parent = tool
		local handle = createCenterHandleForModel(cloned, tool)
		if not (handle and handle:IsA("BasePart")) then
			tool:Destroy()
			warn(string.format("Shop item template '%s' could not create centered handle", template.Name))
			return nil
		end
		return tool
	end
	if template:IsA("BasePart") then
		cloned.Name = "Handle"
		cloned.Parent = tool
		return tool
	end

	tool:Destroy()
	warn(string.format("Shop item template '%s' is unsupported type %s", template.Name, template.ClassName))
	return nil
end

return WeaponTemplateResolver
