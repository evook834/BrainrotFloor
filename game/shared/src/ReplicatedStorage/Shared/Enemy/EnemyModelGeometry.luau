local EnemyModelGeometry = {}

function EnemyModelGeometry.findRootPart(model: Model?): BasePart?
	if not model then
		return nil
	end

	local primary = model.PrimaryPart
	if primary and not primary:IsA("BasePart") then
		primary = nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and not humanoidRootPart:IsA("BasePart") then
		humanoidRootPart = nil
	end

	for _, name in ipairs({ "RootPart", "Root", "UpperTorso", "LowerTorso", "Torso" }) do
		local candidate = model:FindFirstChild(name, true)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end

	local largestVisiblePart = nil
	local largestVisibleVolume = -1
	local largestPart = nil
	local largestVolume = -1
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if descendant.Transparency < 1 and volume > largestVisibleVolume then
				largestVisibleVolume = volume
				largestVisiblePart = descendant
			end
			if volume > largestVolume then
				largestVolume = volume
				largestPart = descendant
			end
		end
	end

	if largestVisiblePart then
		largestPart = largestVisiblePart
		largestVolume = largestVisibleVolume
	end

	if primary then
		local size = primary.Size
		local primaryVolume = size.X * size.Y * size.Z
		if largestPart == nil or (primary.Transparency < 1 and primaryVolume >= largestVolume * 0.4) then
			return primary
		end
	end

	if humanoidRootPart then
		local size = humanoidRootPart.Size
		local humanoidRootVolume = size.X * size.Y * size.Z
		if largestPart == nil or humanoidRootVolume >= largestVolume * 0.4 then
			return humanoidRootPart
		end
	end

	if largestPart then
		return largestPart
	end

	if primary then
		return primary
	end

	if humanoidRootPart then
		return humanoidRootPart
	end

	return nil
end

function EnemyModelGeometry.getExtentsSize(model: Model, fallbackSize: Vector3?): Vector3
	local ok, size = pcall(function()
		return model:GetExtentsSize()
	end)
	if ok and size then
		return size
	end

	return fallbackSize or Vector3.new(4, 4, 4)
end

return EnemyModelGeometry

