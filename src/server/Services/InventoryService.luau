--[[
	InventoryService
	Server-owned inventory (4 slots, stacking) plus the flashlight and its battery.
	World pickups are server instances tagged Interactable (InteractKind=Pickup).
	The client only ever asks: pick up this, use/drop slot N, select slot N,
	flashlight on/off. Everything is validated here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Items = require(ReplicatedStorage.Shared.Catalog.Items)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local InventoryService = {}

InventoryService.ItemPicked = Signal.new() -- (player, itemId, pickupInstance)
InventoryService.ItemRemoved = Signal.new() -- (player, itemId)

type Slot = { id: string, count: number }
type Inv = { slots: { Slot? }, selected: number, battery: number, light: boolean, lightSeconds: number, minBattery: number }

local inventories: { [Player]: Inv } = {}
local FL_REST_CAP = 12 -- percent a dead battery recovers to while switched off
local FL_REST_RATE = 0.2 -- percent per second
local pickupsFolder: Folder? = nil

local function newInv(): Inv
	return { slots = {}, selected = 1, battery = GameConfig.Flashlight.MaxBattery, light = false, lightSeconds = 0, minBattery = GameConfig.Flashlight.MaxBattery }
end

local function get(player: Player): Inv
	local inv = inventories[player]
	if not inv then
		inv = newInv()
		inventories[player] = inv
	end
	return inv
end

function InventoryService:Push(player: Player)
	local inv = get(player)
	local slots = {}
	for i = 1, GameConfig.Inventory.Slots do
		local s = inv.slots[i]
		slots[i] = if s then { id = s.id, count = s.count } else false
	end
	player:SetAttribute("Battery", math.floor(inv.battery * 10) / 10)
	player:SetAttribute("Flashlight", inv.light)
	Net.fire(player, "InventoryState", { slots = slots, selected = inv.selected, battery = inv.battery, light = inv.light })
end

function InventoryService:Has(player: Player, id: string, count: number?): boolean
	return self:Count(player, id) >= (count or 1)
end

function InventoryService:Count(player: Player, id: string): number
	local n = 0
	for _, s in get(player).slots do
		if s and s.id == id then
			n += s.count
		end
	end
	return n
end

function InventoryService:CanAdd(player: Player, id: string): boolean
	local def = Items.get(id)
	if not def then
		return false
	end
	local inv = get(player)
	for i = 1, GameConfig.Inventory.Slots do
		local s = inv.slots[i]
		if s and s.id == id and s.count < def.stack then
			return true
		end
	end
	for i = 1, GameConfig.Inventory.Slots do
		if not inv.slots[i] then
			return true
		end
	end
	return false
end

function InventoryService:Add(player: Player, id: string): boolean
	if not self:CanAdd(player, id) then
		return false
	end
	local def = Items.get(id)
	local inv = get(player)
	for i = 1, GameConfig.Inventory.Slots do
		local s = inv.slots[i]
		if s and s.id == id and s.count < def.stack then
			s.count += 1
			self:Push(player)
			return true
		end
	end
	for i = 1, GameConfig.Inventory.Slots do
		if not inv.slots[i] then
			inv.slots[i] = { id = id, count = 1 }
			self:Push(player)
			return true
		end
	end
	return false
end

function InventoryService:Remove(player: Player, id: string, count: number?): boolean
	local need = count or 1
	if self:Count(player, id) < need then
		return false
	end
	local inv = get(player)
	for i = GameConfig.Inventory.Slots, 1, -1 do
		local s = inv.slots[i]
		if s and s.id == id and need > 0 then
			local take = math.min(need, s.count)
			s.count -= take
			need -= take
			if s.count <= 0 then
				inv.slots[i] = nil
			end
		end
	end
	InventoryService.ItemRemoved:Fire(player, id)
	self:Push(player)
	return true
end

function InventoryService:GetSlots(player: Player)
	return get(player).slots
end

------------------------------------------------------------------------------------
-- World pickups
------------------------------------------------------------------------------------

local ITEM_SHAPES = {
	fuse = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(0.5, 1.3, 0.5)
		body.CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
		body.Color = color
		body.Material = Enum.Material.Marble
		body.Parent = model
		for _, s in { -1, 1 } do
			local cap = Instance.new("Part")
			cap.Name = "Cap"
			cap.Size = Vector3.new(0.56, 0.2, 0.56)
			cap.CFrame = body.CFrame * CFrame.new(0, s * 0.65, 0)
			cap.Color = Color3.fromRGB(150, 150, 150)
			cap.Material = Enum.Material.Metal
			cap.Parent = model
		end
		return body
	end,
	battery = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(1.1, 0.5, 0.5)
		body.CFrame = cf * CFrame.new(0, 0.25, 0)
		body.Color = color
		body.Material = Enum.Material.Metal
		body.Parent = model
		return body
	end,
	key = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(0.9, 0.08, 0.3)
		body.CFrame = cf * CFrame.new(0, 0.05, 0)
		body.Color = color
		body.Material = Enum.Material.Metal
		body.Parent = model
		local tag = Instance.new("Part")
		tag.Name = "Tag"
		tag.Size = Vector3.new(0.4, 0.04, 0.6)
		tag.CFrame = cf * CFrame.new(0.6, 0.03, 0.15)
		tag.Color = Color3.fromRGB(140, 40, 34)
		tag.Material = Enum.Material.Fabric
		tag.Parent = model
		return body
	end,
	tape = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(1, 0.2, 0.65)
		body.CFrame = cf * CFrame.new(0, 0.1, 0)
		body.Color = color
		body.Material = Enum.Material.SmoothPlastic
		body.Parent = model
		local label = Instance.new("Part")
		label.Name = "Label"
		label.Size = Vector3.new(0.8, 0.02, 0.3)
		label.CFrame = cf * CFrame.new(0, 0.21, 0)
		label.Color = Color3.fromRGB(200, 196, 180)
		label.Material = Enum.Material.SmoothPlastic
		label.Parent = model
		return body
	end,
	tool = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2.6, 0.2, 0.2)
		body.CFrame = cf * CFrame.new(0, 0.1, 0)
		body.Color = color
		body.Material = Enum.Material.Metal
		body.Parent = model
		local hook = Instance.new("Part")
		hook.Name = "Hook"
		hook.Size = Vector3.new(0.2, 0.2, 0.5)
		hook.CFrame = cf * CFrame.new(1.3, 0.1, 0.2)
		hook.Color = color
		hook.Material = Enum.Material.Metal
		hook.Parent = model
		return body
	end,
	box = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(0.8, 0.6, 0.6)
		body.CFrame = cf * CFrame.new(0, 0.3, 0)
		body.Color = color
		body.Material = Enum.Material.Wood
		body.Parent = model
		return body
	end,
	doll = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(0.5, 0.8, 0.35)
		body.CFrame = cf * CFrame.new(0, 0.4, 0)
		body.Color = color
		body.Material = Enum.Material.Fabric
		body.Parent = model
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(0.45, 0.45, 0.45)
		head.CFrame = cf * CFrame.new(0, 1.0, 0)
		head.Color = Color3.fromRGB(190, 176, 160)
		head.Material = Enum.Material.Fabric
		head.Parent = model
		return body
	end,
	candle = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(0.8, 0.35, 0.35)
		body.CFrame = cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
		body.Color = color
		body.Material = Enum.Material.SmoothPlastic
		body.Parent = model
		local flame = Instance.new("Part")
		flame.Name = "Flame"
		flame.Size = Vector3.new(0.1, 0.18, 0.1)
		flame.CFrame = cf * CFrame.new(0, 0.9, 0)
		flame.Color = Color3.fromRGB(255, 190, 110)
		flame.Material = Enum.Material.Neon
		flame.Parent = model
		local light = Instance.new("PointLight")
		light.Brightness = 0.6
		light.Range = 6
		light.Color = Color3.fromRGB(255, 180, 110)
		light.Parent = flame
		return body
	end,
	ward = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(0.5, 0.5, 0.5)
		body.CFrame = cf * CFrame.new(0, 0.25, 0)
		body.Color = color
		body.Material = Enum.Material.Fabric
		body.Parent = model
		local thread = Instance.new("Part")
		thread.Name = "Thread"
		thread.Size = Vector3.new(0.05, 0.05, 1.2)
		thread.CFrame = cf * CFrame.new(0, 0.05, 0.4)
		thread.Color = Color3.fromRGB(150, 30, 30)
		thread.Material = Enum.Material.Fabric
		thread.Parent = model
		return body
	end,
	photo = function(model, cf, color)
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(0.8, 0.03, 1)
		body.CFrame = cf * CFrame.new(0, 0.03, 0)
		body.Color = color
		body.Material = Enum.Material.SmoothPlastic
		body.Reflectance = 0.2
		body.Parent = model
		local border = Instance.new("Part")
		border.Name = "Border"
		border.Size = Vector3.new(0.9, 0.02, 1.1)
		border.CFrame = cf * CFrame.new(0, 0.015, 0)
		border.Color = Color3.fromRGB(220, 218, 210)
		border.Material = Enum.Material.SmoothPlastic
		border.Parent = model
		return body
	end,
}

-- Creates a pickup in the world. opts.falseItem marks dangerous duplicates.
function InventoryService:SpawnPickup(id: string, cf: CFrame, opts: { [string]: any }?): Model?
	local def = Items.get(id)
	if not def then
		return nil
	end
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = "Pickup_" .. id
	local shape = ITEM_SHAPES[def.icon] or ITEM_SHAPES.box
	local color = opts.color or def.color
	local body = shape(model, cf, color)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CastShadow = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
		end
	end
	-- a generous invisible hitbox makes small items easy to target on every device
	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Size = Vector3.new(1.6, 1.4, 1.6)
	hit.CFrame = cf * CFrame.new(0, 0.6, 0)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanCollide = false
	hit.CastShadow = false
	hit.Parent = model
	hit:AddTag("Interactable")
	hit:SetAttribute("InteractKind", "Pickup")
	hit:SetAttribute("ItemId", id)
	hit:SetAttribute("Prompt", "Take " .. def.name)
	if opts.falseItem then
		hit:SetAttribute("FalseItem", true)
	end
	model.PrimaryPart = body
	model:SetAttribute("ItemId", id)
	model:AddTag("Pickup")
	model.Parent = opts.parent or pickupsFolder or workspace
	return model
end

function InventoryService:ClearPickups()
	if pickupsFolder then
		pickupsFolder:ClearAllChildren()
	end
end

local function onPickup(player: Player, target: Instance): boolean
	local id = target:GetAttribute("ItemId")
	if type(id) ~= "string" or not Items.get(id) then
		return false
	end
	local model = target:FindFirstAncestorWhichIsA("Model")
	if not model or not model:HasTag("Pickup") then
		return false
	end
	if target:GetAttribute("FalseItem") then
		Registry.AnomalyService:OnFalseItemTaken(player, model)
		return true
	end
	if not InventoryService:Add(player, id) then
		Net.fire(player, "Notify", { kind = "info", text = "Your hands are full." })
		Registry.AudioService:Play2D({ player }, "UIError")
		return false
	end
	model:Destroy()
	Registry.AudioService:Play2D({ player }, "Pickup")
	Net.fire(player, "Notify", { kind = "item", text = Items.get(id).name, item = id })
	InventoryService.ItemPicked:Fire(player, id, model)
	return true
end

local function dropSlot(player: Player, index: number)
	local inv = get(player)
	local slot = inv.slots[index]
	if not slot then
		return
	end
	local root = Util.getRoot(player)
	if not root then
		return
	end
	local id = slot.id
	local look = Util.flat(root.CFrame.LookVector)
	local origin = root.Position + (if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1)) * 2.5
	local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), (function()
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { player.Character :: Instance }
		return p
	end)())
	local ground = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
	slot.count -= 1
	if slot.count <= 0 then
		inv.slots[index] = nil
	end
	InventoryService:SpawnPickup(id, CFrame.new(ground) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0))
	Registry.AudioService:PlayAt("Drop", ground)
	InventoryService.ItemRemoved:Fire(player, id)
	InventoryService:Push(player)
end

local function useSlot(player: Player, index: number)
	local inv = get(player)
	local slot = inv.slots[index]
	if not slot then
		return
	end
	if slot.id == "BATTERY" then
		if inv.battery >= GameConfig.Flashlight.MaxBattery - 1 then
			Net.fire(player, "Notify", { kind = "info", text = "The flashlight is already full." })
			return
		end
		inv.battery = math.min(GameConfig.Flashlight.MaxBattery, inv.battery + GameConfig.Flashlight.BatteryItemRestore)
		InventoryService:Remove(player, "BATTERY", 1)
		Registry.AudioService:Play2D({ player }, "FlashlightOn", { speed = 0.7 })
		Net.fire(player, "Notify", { kind = "info", text = "Flashlight recharged." })
	else
		local def = Items.get(slot.id)
		Net.fire(player, "Notify", { kind = "info", text = def.description })
	end
end

function InventoryService:SetFlashlight(player: Player, on: boolean)
	local inv = get(player)
	if on and inv.battery <= 0 then
		Registry.AudioService:Play2D({ player }, "FlashlightDead")
		on = false
	end
	if inv.light == on then
		self:Push(player)
		return
	end
	inv.light = on
	self:Push(player)
end

function InventoryService:IsLightOn(player: Player): boolean
	return get(player).light
end

function InventoryService:GetBattery(player: Player): number
	return get(player).battery
end

function InventoryService:GetRoundStats(player: Player)
	local inv = get(player)
	return { lightSeconds = inv.lightSeconds, battery = inv.battery, minBattery = inv.minBattery }
end

-- Resets everything for a new round.
function InventoryService:Reset(player: Player)
	inventories[player] = newInv()
	self:Push(player)
end

function InventoryService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = workspace
	pickupsFolder = folder
	Registry.InteractionService:Register("Pickup", onPickup)
	Net.on("Inventory", function(player, action, index)
		if type(action) ~= "string" or type(index) ~= "number" then
			return
		end
		index = math.floor(index)
		if index < 1 or index > GameConfig.Inventory.Slots then
			return
		end
		if not Registry.PlayerService:IsAlive(player) then
			return
		end
		if action == "select" then
			get(player).selected = index
			InventoryService:Push(player)
		elseif action == "use" then
			useSlot(player, index)
		elseif action == "drop" then
			dropSlot(player, index)
		end
	end)
	Net.on("Flashlight", function(player, on)
		if type(on) ~= "boolean" then
			return
		end
		if not Registry.PlayerService:IsAlive(player) then
			return
		end
		InventoryService:SetFlashlight(player, on)
		Registry.AudioService:PlayAtFor({ player }, if on then "FlashlightOn" else "FlashlightOff", player.Character and player.Character:FindFirstChild("Head") or Vector3.zero)
		Registry.AnomalyService:OnFlashlight(player, on)
	end)
end

function InventoryService:Start()
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
	end)
	-- battery drain
	task.spawn(function()
		while true do
			task.wait(1)
			local drain = Registry.RoundService:GetDifficultyConfig().BatteryDrain
			for player, inv in inventories do
				if not inv.light and inv.battery < FL_REST_CAP and Registry.PlayerService:IsAlive(player) then
					-- a rested battery recovers a little charge: never stuck without light for good
					inv.battery = math.min(FL_REST_CAP, inv.battery + FL_REST_RATE)
					player:SetAttribute("Battery", math.floor(inv.battery * 10) / 10)
				end
				if inv.light and Registry.PlayerService:IsAlive(player) then
					inv.lightSeconds += 1
					inv.battery = math.max(0, inv.battery - drain)
					inv.minBattery = math.min(inv.minBattery, inv.battery)
					if inv.battery <= 0 then
						inv.light = false
						Registry.AudioService:Play2D({ player }, "FlashlightDead")
						Net.fire(player, "Notify", { kind = "warning", text = "The flashlight died." })
						Registry.AnomalyService:OnFlashlight(player, false)
					end
					player:SetAttribute("Battery", math.floor(inv.battery * 10) / 10)
					player:SetAttribute("Flashlight", inv.light)
				end
			end
		end
	end)
end

return InventoryService
