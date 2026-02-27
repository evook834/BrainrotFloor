local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyModelGeometry = require(ReplicatedStorage.Shared.Enemy.EnemyModelGeometry)

local ModelRootResolver = {}

function ModelRootResolver.resolveRootPart(model: Model?): BasePart?
	if not model then
		return nil
	end

	local rootPart = EnemyModelGeometry.findRootPart(model)
	if rootPart then
		model.PrimaryPart = rootPart
		return rootPart
	end

	return nil
end

return ModelRootResolver
