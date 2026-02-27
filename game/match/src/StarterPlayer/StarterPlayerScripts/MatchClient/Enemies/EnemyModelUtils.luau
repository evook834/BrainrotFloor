local EnemyModelUtils = {}

local DEFAULT_HEALTH_BAR_SIZE = Vector3.new(4, 4, 4)
local DEFAULT_EFFECT_SIZE = Vector3.new(3, 3, 3)

function EnemyModelUtils.resolveRootPart(enemyModel: Model): BasePart?
	if enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") then
		return enemyModel.PrimaryPart
	end

	local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local anyPart = enemyModel:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
	end

	return nil
end

function EnemyModelUtils.getExtentsSize(enemyModel: Model, fallbackSize: Vector3?): Vector3
	local ok, size = pcall(function()
		return enemyModel:GetExtentsSize()
	end)
	if ok and size then
		return size
	end

	return fallbackSize or DEFAULT_HEALTH_BAR_SIZE
end

function EnemyModelUtils.getHealthBarOffset(enemyModel: Model): number
	local height = EnemyModelUtils.getExtentsSize(enemyModel, DEFAULT_HEALTH_BAR_SIZE).Y
	return math.clamp((height * 0.55) + 1, 2.2, 12)
end

function EnemyModelUtils.resolveEffectPosition(enemyModel: Model): (Vector3?, Vector3?)
	local rootPart = EnemyModelUtils.resolveRootPart(enemyModel)
	if rootPart then
		return rootPart.Position + Vector3.new(0, math.max(0.4, rootPart.Size.Y * 0.35), 0), rootPart.Size
	end

	local okPivot, pivot = pcall(function()
		return enemyModel:GetPivot()
	end)
	if okPivot and pivot then
		local size = EnemyModelUtils.getExtentsSize(enemyModel, DEFAULT_EFFECT_SIZE)
		return pivot.Position + Vector3.new(0, math.max(0.6, size.Y * 0.35), 0), size
	end

	return nil, nil
end

return EnemyModelUtils
