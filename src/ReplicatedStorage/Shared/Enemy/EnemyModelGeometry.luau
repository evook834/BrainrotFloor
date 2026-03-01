local EnemyModelGeometry = {}

function EnemyModelGeometry.findRootPart(model: Model?): BasePart?
	if not model then
		return nil
	end

	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
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

