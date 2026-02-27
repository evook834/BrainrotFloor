--[[
	WeaponFireHandlers — Backward-compatible facade for weapon fire APIs.
	Implementation is split by mode under Weapons/Combat/Handlers.
]]

local WeaponBulletHandler = require(script.Parent.Handlers.WeaponBulletHandler)
local WeaponMeleeHandler = require(script.Parent.Handlers.WeaponMeleeHandler)
local WeaponFlamethrowerHandler = require(script.Parent.Handlers.WeaponFlamethrowerHandler)
local WeaponProjectileHandler = require(script.Parent.Handlers.WeaponProjectileHandler)

return {
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
