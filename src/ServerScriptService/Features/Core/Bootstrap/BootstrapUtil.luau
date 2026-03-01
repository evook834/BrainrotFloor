--[[
	Shared utilities for match bootstrap: folder/remote creation, safe calls, number/time helpers.
]]

local BootstrapUtil = {}

BootstrapUtil.PLACEHOLDER_PLACE_ID = 1234567890

function BootstrapUtil.ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function BootstrapUtil.ensureRemote(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName == className then
			return existing
		end
		warn(("[Bootstrap] Replacing %s/%s: expected %s, got %s"):format(
			parent.Name, name, className, existing.ClassName))
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

function BootstrapUtil.ensureRemoteEvent(parent, name)
	return BootstrapUtil.ensureRemote(parent, "RemoteEvent", name)
end

function BootstrapUtil.ensureRemoteFunction(parent, name)
	return BootstrapUtil.ensureRemote(parent, "RemoteFunction", name)
end

function BootstrapUtil.toNumber(value, defaultValue)
	local n = tonumber(value)
	if n == nil then
		return defaultValue
	end
	return n
end

function BootstrapUtil.nowSeconds()
	return os.time()
end

function BootstrapUtil.safeCall(label, callback)
	local ok, resultA, resultB, resultC = pcall(callback)
	if not ok then
		warn(("[Bootstrap] %s failed: %s"):format(label, tostring(resultA)))
		return false, nil, nil, nil
	end
	return true, resultA, resultB, resultC
end

return BootstrapUtil
