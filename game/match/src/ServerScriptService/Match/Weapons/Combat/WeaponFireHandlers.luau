--[[
	WeaponFireHandlers — Facade for weapon fire APIs and class-based handler registry.
	Implementation is split by mode under Weapons/Combat/Handlers.
	To add a new weapon class: implement a handler in Handlers/, then register it in
	getClassFireHandlers() below. WeaponToolFactory uses this registry for fire dispatch.
]]

local WeaponBulletHandler = require(script.Parent.Handlers.WeaponBulletHandler)
local WeaponMeleeHandler = require(script.Parent.Handlers.WeaponMeleeHandler)
local WeaponFlamethrowerHandler = require(script.Parent.Handlers.WeaponFlamethrowerHandler)
local WeaponProjectileHandler = require(script.Parent.Handlers.WeaponProjectileHandler)

--[[
	Returns a map of weapon class name -> fire handler.
	Each handler has signature (owner, character, rootPart, origin, direction, shotOrigin, shotDirection, context).
	context = { weaponDef, state, handle }. Used by WeaponToolFactory; add new classes here for scalability.
]]
local function getClassFireHandlers()
	return {
		Flamethrower = function(owner, character, _rootPart, _origin, _direction, _shotOrigin, _shotDirection, context)
			WeaponFlamethrowerHandler.fireFlamethrower(owner, character, context.weaponDef, context.state, context.handle)
		end,
		RPG = function(owner, character, _rootPart, origin, direction, shotOrigin, shotDirection, context)
			WeaponProjectileHandler.fireRocket(owner, character, origin, direction, context.weaponDef, shotOrigin, shotDirection)
		end,
		GrenadeLauncher = function(owner, character, _rootPart, origin, direction, shotOrigin, shotDirection, context)
			WeaponProjectileHandler.fireGrenadeLauncher(owner, character, origin, direction, context.weaponDef, shotOrigin, shotDirection)
		end,
	}
end

return {
	getClassFireHandlers = getClassFireHandlers,
	applyBulletSpread = WeaponBulletHandler.applyBulletSpread,
	playMeleeSwing = WeaponMeleeHandler.playMeleeSwing,
	findLeftShoulderMotor = WeaponMeleeHandler.findLeftShoulderMotor,
	findRightShoulderMotor = WeaponMeleeHandler.findRightShoulderMotor,
	createFlameEmitterBurst = WeaponFlamethrowerHandler.createFlameEmitterBurst,
	createFlamethrowerVisuals = WeaponFlamethrowerHandler.createFlamethrowerVisuals,
	spawnFlamethrowerGroundFire = WeaponFlamethrowerHandler.spawnFlamethrowerGroundFire,
	fireBulletShot = WeaponBulletHandler.fireBulletShot,
	fireMeleeAttack = WeaponMeleeHandler.fireMeleeAttack,
	fireFlamethrower = WeaponFlamethrowerHandler.fireFlamethrower,
	fireRocket = WeaponProjectileHandler.fireRocket,
	fireGrenadeLauncher = WeaponProjectileHandler.fireGrenadeLauncher,
}
