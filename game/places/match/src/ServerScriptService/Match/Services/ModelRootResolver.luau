local ModelRootResolver = {}

function ModelRootResolver.resolveRootPart(model)
	if not model then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		model.PrimaryPart = humanoidRootPart
		return humanoidRootPart
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		model.PrimaryPart = anyPart
		return anyPart
	end

	return nil
end

return ModelRootResolver
