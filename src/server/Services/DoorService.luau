--[[
	DoorService
	Doors are server-authoritative: the server decides open/closed/locked and sets
	the final CFrame instantly; clients animate the swing locally (DoorController)
	from the "Open" attribute so motion is smooth on every device.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local Items = require(ReplicatedStorage.Shared.Catalog.Items)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local DoorService = {}

DoorService.DoorToggled = Signal.new() -- (door, open, player?)

local lastToggle: { [Instance]: number } = {}

local function applyCFrame(model: Model, cf: CFrame)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	primary.CFrame = cf
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local offset = d:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				d.CFrame = cf * offset
			end
		end
	end
end

function DoorService:SetOpen(model: Model, open: boolean, opts: { [string]: any }?)
	opts = opts or {}
	if model:GetAttribute("Open") == open and not opts.force then
		return
	end
	local target = model:GetAttribute(if open then "OpenCFrame" else "ClosedCFrame")
	if typeof(target) ~= "CFrame" then
		return
	end
	model:SetAttribute("Open", open)
	model:SetAttribute("Slam", opts.slam == true)
	applyCFrame(model, target)
	local primary = model.PrimaryPart
	if primary and not opts.silent then
		local key = if opts.slam then "DoorSlam" elseif open then "DoorOpen" else "DoorClose"
		if model:GetAttribute("Slow") then
			key = "ShutterOpen"
		end
		Registry.AudioService:PlayAt(key, primary.Position)
	end
	if primary then
		primary:SetAttribute("Prompt", if open then "Close" else "Open")
	end
	DoorService.DoorToggled:Fire(model, open, opts.player)
end

function DoorService:IsOpen(model: Model): boolean
	return model:GetAttribute("Open") == true
end

function DoorService:Unlock(model: Model)
	model:SetAttribute("Locked", false)
	local primary = model.PrimaryPart
	if primary then
		Registry.AudioService:PlayAt("DoorUnlock", primary.Position)
		primary:SetAttribute("Prompt", "Open")
	end
end

function DoorService:GetDoorFromPart(part: Instance): Model?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model and not model:HasTag("Door") do
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
	end
	return model
end

-- The Observer (and some anomalies) open doors near a position.
function DoorService:OpenNear(position: Vector3, radius: number)
	local map = Registry.MapService:GetMap()
	if not map then
		return
	end
	for _, rec in map.Doors do
		local model = rec.model
		if model and model.Parent and model:HasTag("Door") and not model:GetAttribute("Locked") and not self:IsOpen(model) then
			if (rec.center - position).Magnitude < radius then
				self:SetOpen(model, true)
			end
		end
	end
end

function DoorService:SlamNear(position: Vector3, radius: number): boolean
	local map = Registry.MapService:GetMap()
	if not map then
		return false
	end
	for _, rec in map.Doors do
		local model = rec.model
		if model and model.Parent and model:HasTag("Door") and self:IsOpen(model) and (rec.center - position).Magnitude < radius then
			self:SetOpen(model, false, { slam = true })
			return true
		end
	end
	return false
end

local function onInteract(player: Player, target: Instance): boolean
	local model = DoorService:GetDoorFromPart(target)
	if not model then
		return false
	end
	local now = os.clock()
	if lastToggle[model] and now - lastToggle[model] < 0.6 then
		return false
	end
	lastToggle[model] = now
	local kind = model:GetAttribute("Kind")
	if kind == "closet" then
		return Registry.PuzzleService:OnClosetDoor(player, model)
	end
	if model:GetAttribute("Locked") then
		local keyId = model:GetAttribute("KeyId")
		if keyId and Registry.InventoryService:Has(player, keyId) then
			DoorService:Unlock(model)
			Net.fire(player, "Notify", { kind = "info", text = "Unlocked with " .. Items.get(keyId).name })
			DoorService:SetOpen(model, true, { player = player })
			return true
		end
		if model.PrimaryPart then
			Registry.AudioService:PlayAt("DoorLocked", model.PrimaryPart.Position)
		end
		local text = "Locked."
		if kind == "keypad" then
			text = "Locked. A keypad controls this door."
		elseif keyId then
			text = "Locked. Needs the " .. Items.get(keyId).name .. "."
		end
		Net.fire(player, "Notify", { kind = "info", text = text })
		return false
	end
	DoorService:SetOpen(model, not DoorService:IsOpen(model), { player = player })
	return true
end

function DoorService:Init()
	Registry.InteractionService:Register("Door", onInteract)
end

function DoorService:Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(function(model)
		if model.PrimaryPart then
			model.PrimaryPart:SetAttribute("Prompt", "Open")
		end
	end)
end

return DoorService
