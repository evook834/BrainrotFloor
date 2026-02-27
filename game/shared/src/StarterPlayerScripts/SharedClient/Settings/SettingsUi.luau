local SettingsMenuController = require(script.Parent:WaitForChild("SettingsMenuController"))

export type RunOptions = {
	hudMoveModeAttribute: string?,
	canReturnToLobby: boolean?,
}

local function run(options: RunOptions?)
	SettingsMenuController.run(options)
end

return {
	run = run,
}

