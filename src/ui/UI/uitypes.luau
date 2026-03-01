--[[
	Shared UI Types for Brainrot Floor

	This file defines type aliases used across UI components.
	Import this where needed for type checking.
]]

export type Point = {
	x: number,
	y: number,
}

export type Size = {
	width: number,
	height: number,
}

export type Color = {
	r: number,
	g: number,
	b: number,
}

export type UIData = {
	id: string,
	type: string,
	properties: { [string]: any },
	children: { UIData }?,
}

export type UIComponentProps = {
	key: string?,
	style: { [string]: any }?,
	-- Add more as needed
}

export type UIComponent = {
	props: UIComponentProps,
	children: { UIComponent }?,
	render: (self: UIComponent) -> any,
}

return {}
