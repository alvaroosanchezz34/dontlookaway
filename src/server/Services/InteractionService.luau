--[[
	InteractionService
	Single validated entry point for every world interaction. The client only
	says "I want to interact with this instance" (begin / complete / cancel).
	The server checks:
	  * the player is in a state that allows interaction
	  * the target is a real interactable in the world (or an anomaly target the
	    AnomalyService vouches for, for player-scoped anomalies)
	  * distance from the head and line of sight
	  * hold duration for hold interactions (begin must precede complete)
	Then it dispatches to the handler registered for the target's InteractKind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local InteractionService = {}

local handlers: { [string]: (Player, Instance) -> boolean } = {}
local holds: { [Player]: { target: Instance, started: number } } = {}

-- Kinds allowed while in the lobby (not alive in a round).
local LOBBY_KINDS = { Kiosk = true }

function InteractionService:Register(kind: string, handler: (Player, Instance) -> boolean)
	handlers[kind] = handler
end

local function closestPoint(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(math.clamp(localPoint.X, -half.X, half.X), math.clamp(localPoint.Y, -half.Y, half.Y), math.clamp(localPoint.Z, -half.Z, half.Z))
	return part.CFrame:PointToWorldSpace(clamped)
end

local function getKind(player: Player, target: Instance): string?
	if target:HasTag("Interactable") then
		return target:GetAttribute("InteractKind")
	end
	if Registry.AnomalyService:IsInteractTarget(player, target) then
		return "Anomaly"
	end
	return nil
end

local function validate(player: Player, target: any): (boolean, string?)
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
		return false
	end
	if not target:IsDescendantOf(workspace) then
		return false
	end
	local kind = getKind(player, target)
	if not kind or not handlers[kind] then
		return false
	end
	local status = Registry.PlayerService:GetStatus(player)
	if status ~= Enums.PlayerStatus.Alive and not (LOBBY_KINDS[kind] and status == Enums.PlayerStatus.Lobby) then
		return false
	end
	local head = Util.getHead(player)
	if not head then
		return false
	end
	local point = closestPoint(target, head.Position)
	if (point - head.Position).Magnitude > GameConfig.Interaction.ServerMaxDistance then
		return false
	end
	-- line of sight: allow if the first thing hit belongs to the target's model
	local model = target:FindFirstAncestorWhichIsA("Model") or target
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local dir = target.Position - head.Position
	local hit = workspace:Raycast(head.Position, dir, params)
	if hit and not (hit.Instance == target or hit.Instance:IsDescendantOf(model)) then
		if (hit.Position - head.Position).Magnitude < dir.Magnitude - 2.5 then
			return false
		end
	end
	return true, kind
end

local function onInteract(player: Player, action: any, target: any)
	if type(action) ~= "string" then
		return
	end
	if action == "cancel" then
		holds[player] = nil
		return
	end
	local ok, kind = validate(player, target)
	if not ok then
		return
	end
	local holdTime = target:GetAttribute("HoldTime")
	if type(holdTime) == "number" and holdTime > 0 then
		if action == "begin" then
			holds[player] = { target = target, started = os.clock() }
			return
		elseif action == "complete" then
			local hold = holds[player]
			holds[player] = nil
			if not hold or hold.target ~= target or os.clock() - hold.started < holdTime * 0.8 then
				return
			end
		else
			return
		end
	elseif action ~= "complete" then
		return
	end
	local handler = handlers[kind :: string]
	local success, result = pcall(handler, player, target)
	if not success then
		warn("[InteractionService] handler error (" .. tostring(kind) .. "):", result)
	end
end

function InteractionService:Init()
	Net.on("Interact", onInteract)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		holds[player] = nil
	end)
end

return InteractionService
