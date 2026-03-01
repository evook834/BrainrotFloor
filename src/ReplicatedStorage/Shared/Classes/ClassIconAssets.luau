--[[
	Class icon asset IDs for the Class Menu (ClassUi).
	Used when ReplicatedStorage.ClassIcons has no instances (e.g. Rojo doesn't sync PNG files).
	Upload your Class Icons folder images to Roblox (Create → Decals & Images), then set each
	entry to the asset ID (number) or full URL (e.g. "rbxassetid://123456789").
	Keys must match class Id from ClassCatalog (lowercase, no spaces).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassIconAssets = {
	PRIMARY_FOLDER_NAME = "ClassIcons",
	ALT_FOLDER_NAME = "Class Icons",
	GAME_ASSET_CATEGORY = "Images",
	berserker = nil,
	commander = nil,
	pyromaniac = nil,
	sentrytech = nil,
	sniper = nil,
}

local classIconContentByKey: { [string]: string } = {}

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

	return string.format("rbxgameasset://%s/%s", ClassIconAssets.GAME_ASSET_CATEGORY, assetName)
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

function ClassIconAssets.findRuntimeIconFolder(): Instance?
	return ReplicatedStorage:FindFirstChild(ClassIconAssets.PRIMARY_FOLDER_NAME)
		or ReplicatedStorage:FindFirstChild(ClassIconAssets.ALT_FOLDER_NAME)
end

local function refreshClassIconCache()
	local classIconsFolder = ClassIconAssets.findRuntimeIconFolder()
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

function ClassIconAssets.normalizeIconKey(value: string?): string
	return normalizeIconKey(value)
end

function ClassIconAssets.getClassIconContent(classData: any): string?
	if type(classData) == "string" then
		classData = {
			id = classData,
		}
	end

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

	local classId = normalizeIconKey(classData.id)
	if classId ~= "" then
		local asset = rawget(ClassIconAssets, classId)
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

return ClassIconAssets
