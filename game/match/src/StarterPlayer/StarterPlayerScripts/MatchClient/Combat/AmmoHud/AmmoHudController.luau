--[[
	AmmoHudController — Ammo HUD logic: character/tool binding, tool attribute updates,
	HUD move mode preview. Uses AmmoHudPayloadUtil for display data and AmmoHudView helpers to apply it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudLayoutConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"):WaitForChild("HudLayoutConfig"))
local AmmoHudConstants = require(script.Parent.AmmoHudConstants)
local AmmoHudPayloadUtil = require(script.Parent.AmmoHudPayloadUtil)
local AmmoHudView = require(script.Parent.AmmoHudView)

local function disconnectAll(connections: { RBXScriptConnection })
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

local function findAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function findEquippedTool(character: Model?): Tool?
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

local function run(playerGui: PlayerGui)
	local existingGui = playerGui:FindFirstChild(AmmoHudConstants.GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local refs = AmmoHudView.build(playerGui)
	local currentCharacter: Model? = nil
	local currentTool: Tool? = nil
	local characterConnections: { RBXScriptConnection } = {}
	local toolConnections: { RBXScriptConnection } = {}
	local player = Players.LocalPlayer

	-- Forward-declare so refreshHud can call them when needed
	local bindCharacter: (character: Model?) -> ()
	local bindTool: (tool: Tool?) -> ()
	local refreshing = false

	local function refreshHud()
		-- Derive from current state so HUD shows even if bindings ran in wrong order or tool was already equipped
		local character = player.Character
		local tool = character and findEquippedTool(character) or nil

		-- Sync bindings only when not already inside a sync (avoids refreshHud -> bindCharacter -> bindTool -> refreshHud spam)
		if not refreshing then
			if character and character ~= currentCharacter and bindCharacter then
				refreshing = true
				bindCharacter(character)
				refreshing = false
				return
			end
			if character and tool and tool.Parent == character and tool ~= currentTool and bindTool then
				refreshing = true
				bindTool(tool)
				refreshing = false
				return
			end
		end

		local display = nil
		local visible = false

		if playerGui:GetAttribute(HudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE) == true then
			display = AmmoHudPayloadUtil.PREVIEW_DISPLAY
			visible = true
		elseif character and tool and tool.Parent == character and findAliveHumanoid(character) then
			local snapshot = AmmoHudPayloadUtil.readAmmoSnapshot(tool)
			if snapshot then
				display = AmmoHudPayloadUtil.buildDisplayFromSnapshot(snapshot)
				visible = true
			else
				display = AmmoHudPayloadUtil.buildFallbackDisplay(tool)
				visible = true
			end
		end

		if display then
			AmmoHudView.setDisplay(refs, display)
		end
		AmmoHudView.setRootVisible(refs, visible)
	end

	function bindTool(tool: Tool?)
		disconnectAll(toolConnections)
		currentTool = tool
		if not currentTool then
			refreshHud()
			return
		end
		for _, attr in ipairs(AmmoHudConstants.TOOL_AMMO_ATTRIBUTES) do
			table.insert(toolConnections, currentTool:GetAttributeChangedSignal(attr):Connect(refreshHud))
		end
		table.insert(toolConnections, currentTool:GetPropertyChangedSignal("Name"):Connect(refreshHud))
		table.insert(toolConnections, currentTool.AncestryChanged:Connect(refreshHud))
		refreshHud()
	end

	function bindCharacter(character: Model?)
		disconnectAll(characterConnections)
		bindTool(nil)
		currentCharacter = character
		if not currentCharacter then
			refreshHud()
			return
		end

		local equipped = findEquippedTool(currentCharacter)
		if equipped then
			bindTool(equipped)
		end

		local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			table.insert(characterConnections, humanoid:GetPropertyChangedSignal("Health"):Connect(refreshHud))
			table.insert(characterConnections, humanoid.Died:Connect(refreshHud))
		end

		table.insert(characterConnections, currentCharacter.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				bindTool(child)
			end
			refreshHud()
		end))
		table.insert(characterConnections, currentCharacter.ChildRemoved:Connect(function(child)
			if child == currentTool then
				bindTool(findEquippedTool(currentCharacter))
			end
			refreshHud()
		end))
		refreshHud()
	end

	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function(character)
		if character == currentCharacter then
			bindCharacter(nil)
		end
	end)
	playerGui:GetAttributeChangedSignal(HudLayoutConfig.HUD_MOVE_MODE_ATTRIBUTE):Connect(refreshHud)
end

return {
	run = run,
}
