--[[
	InteractController
	Look-to-interact: whatever interactable is under the crosshair (within reach)
	gets a contextual prompt. Press, or hold for hold-interactions. The server
	re-validates distance, line of sight, state and hold time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local InteractController = {}

local player = Players.LocalPlayer
local target: BasePart? = nil
local holding = false
local holdStart = 0
local lastScan = 0

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function findInteractable(inst: Instance): BasePart?
	if inst:IsA("BasePart") and inst:HasTag("Interactable") then
		return inst
	end
	local model = inst:FindFirstAncestorWhichIsA("Model")
	local depth = 0
	while model and depth < 3 do
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child:HasTag("Interactable") then
				-- prefer the child closest to what we hit
				return child
			end
		end
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
		depth += 1
	end
	return nil
end

local function canInteract(): boolean
	return (State.status == "ALIVE" or State.status == "LOBBY") and not State.uiOpen
end

local function scan()
	if not canInteract() then
		target = nil
		return
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector * GameConfig.Interaction.MaxDistance
	local hit = Workspace:Raycast(origin, dir, params)
	local found = hit and findInteractable(hit.Instance)
	if not found then
		-- generous fallback: a slightly fatter probe for small items
		local probe = Workspace:Spherecast(origin, 0.6, dir, params)
		found = probe and findInteractable(probe.Instance)
	end
	if found and State.status == "LOBBY" and found:GetAttribute("InteractKind") ~= "Kiosk" then
		found = nil
	end
	if found ~= target then
		if holding then
			holding = false
			Net.event("Interact"):FireServer("cancel")
		end
		target = found
	end
end

local function holdTimeOf(part: BasePart): number
	local t = part:GetAttribute("HoldTime")
	return if type(t) == "number" then t else 0
end

function InteractController:GetTarget(): BasePart?
	return target
end

function InteractController:Press(began: boolean)
	if not canInteract() then
		return
	end
	local t = target
	if began then
		if not t then
			return
		end
		local hold = holdTimeOf(t)
		if hold > 0 then
			holding = true
			holdStart = os.clock()
			Net.event("Interact"):FireServer("begin", t)
		else
			Net.event("Interact"):FireServer("complete", t)
		end
	else
		if holding then
			holding = false
			Net.event("Interact"):FireServer("cancel")
		end
	end
end

local function update()
	local now = os.clock()
	if now - lastScan > 0.08 then
		lastScan = now
		scan()
	end
	local t = target
	local progress = nil
	if holding and t then
		local hold = holdTimeOf(t)
		progress = math.clamp((now - holdStart) / hold, 0, 1)
		if progress >= 1 then
			holding = false
			Net.event("Interact"):FireServer("complete", t)
		end
	end
	local hud = Registry.HUDController
	if hud then
		if t then
			local text = t:GetAttribute("Prompt") or "Use"
			hud:SetPrompt(Registry.InputController:Label("Interact"), text, holdTimeOf(t) > 0, progress)
		else
			hud:SetPrompt(nil)
		end
	end
end

function InteractController:Start()
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Interact" then
			self:Press(began)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return InteractController
