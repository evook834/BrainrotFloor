local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local TeleportLoadingView = require(script.Parent:WaitForChild("TeleportLoadingView"))

local TeleportLoading = {}

local timeoutTokens = {}

function TeleportLoading.show(options)
	options = options or {}

	local title = options.title or "Loading"
	local subtitle = options.subtitle or "Teleporting..."

	TeleportLoadingView.showGui(title, subtitle)

	if options.timeoutSeconds and options.timeoutSeconds > 0 then
		local token = {}
		timeoutTokens[token] = true
		task.delay(options.timeoutSeconds, function()
			if not timeoutTokens[token] then
				return
			end
			timeoutTokens[token] = nil

			local message = options.timeoutMessage or "Teleport did not complete. Please try again."
			TeleportLoading.showFailure(message)
		end)
	end
end

function TeleportLoading.showFailure(message)
	TeleportLoadingView.showFailure(message)
end

function TeleportLoading.hide()
	TeleportLoadingView.destroyGui()
end

function TeleportLoading.init()
	TeleportLoadingView.initRemote()
	TeleportLoadingView.initTeleportService()
end

return TeleportLoading

