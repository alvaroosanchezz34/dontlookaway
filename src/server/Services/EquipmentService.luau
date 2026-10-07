--[[
	EquipmentService
	Investigation gear: buying, equipping, the loadout and the tool belt during a
	round. Everything is decided here; clients only ask.

	Lobby (Net "Gear")
	  buy <id>              spend Echoes on a piece of equipment
	  upgrade <id>          buy the next level of an upgrade
	  equip <id>            choose the flashlight / battery you carry
	  loadout <{ids}>       choose the tools on your belt (owned, unique, fits)
	Round (Net "Tool")
	  select <index>        hold a tool from the belt
	  use <index> <data>    use it (validated: alive, charges, cooldowns, range)

	Tools
	  GLOW STICKS       drop a light that stays for the night
	  SPARE CELL        an extra battery in your pocket from the start
	  FIELD RADIO       (client) teammates' positions while held
	  TRIPWIRE SENSOR   placed on the floor; warns the team when something passes
	  INSTANT CAMERA    a long-range report; photographs pay an evidence bonus
	  RESONANCE METER   bars that rise near active anomalies (server-fed)
	  SIGNAL TRACKER    points to the nearest item the night still needs
	  THERMAL VIEWER    things that are not alive show cold (limited charge)
	  ANOMALY LENS      nearby changes shimmer for a moment (cooldown)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Equipment = require(ReplicatedStorage.Shared.Catalog.Equipment)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local EquipmentService = {}

type Tool = { id: string, charges: number?, charge: number?, readyAt: number }
type Belt = { tools: { Tool }, selected: number, thermalOn: boolean, sensors: { { part: BasePart, alertAt: number } }, evidence: number }

local belts: { [Player]: Belt } = {}
local glowFolder: Folder? = nil

------------------------------------------------------------------------------------
-- Ownership & catalog
------------------------------------------------------------------------------------

local function data(player: Player)
	return Registry.DataService:Get(player)
end

function EquipmentService:Owns(player: Player, id: string): boolean
	local item = Equipment.get(id)
	local d = data(player)
	return item ~= nil and (item.default == true or (d ~= nil and d.gear.owned[id] == true))
end

function EquipmentService:Upgrades(player: Player): { [string]: number }
	local d = data(player)
	return if d then d.upgrades else {}
end

-- Shop + loadout state for one player (sent to the client).
function EquipmentService:GetGear(player: Player)
	local d = data(player)
	if not d then
		return nil
	end
	local level = Progression.fromTotal(d.xp)
	local items = {}
	for _, item in Equipment.List do
		local owned = self:Owns(player, item.id)
		table.insert(items, {
			id = item.id,
			kind = item.kind,
			owned = owned,
			price = item.price,
			level = item.level,
			locked = not owned and item.level ~= nil and level < item.level,
			equipped = (item.kind == "FLASHLIGHT" and d.gear.flashlight == item.id) or (item.kind == "BATTERY" and d.gear.battery == item.id) or (item.kind == "TOOL" and table.find(d.gear.loadout, item.id) ~= nil),
		})
	end
	local upgrades = {}
	for _, u in Equipment.Upgrades do
		local current = d.upgrades[u.id] or 0
		local nextLevel = u.levels[current + 1]
		table.insert(upgrades, {
			id = u.id,
			level = current,
			max = #u.levels,
			price = nextLevel and nextLevel.price,
			needLevel = nextLevel and nextLevel.level,
			locked = nextLevel ~= nil and nextLevel.level ~= nil and level < nextLevel.level,
		})
	end
	return {
		echoes = d.echoes,
		level = level,
		items = items,
		upgrades = upgrades,
		loadout = d.gear.loadout,
		slots = Equipment.loadoutSlots(d.upgrades),
		flashlight = d.gear.flashlight,
		battery = d.gear.battery,
	}
end

local function refreshClient(player: Player)
	Registry.ProgressionService:Push(player)
	Net.fire(player, "ToolEvent", { kind = "gear", gear = EquipmentService:GetGear(player) })
end

local function deny(player: Player, text: string)
	Net.fire(player, "Notify", { kind = "info", text = text })
	Registry.AudioService:Play2D({ player }, "UIError")
end

------------------------------------------------------------------------------------
-- Lobby actions
------------------------------------------------------------------------------------

local function inLobby(player: Player): boolean
	local status = Registry.PlayerService:GetStatus(player)
	return status == "LOBBY" or status == "MENU" or status == "WAITING" or status == "DEAD" or status == "ESCAPED"
end

local function buy(player: Player, id: string)
	local item = Equipment.get(id)
	local d = data(player)
	if not item or not d or item.default or not item.price then
		return
	end
	if d.gear.owned[id] then
		return
	end
	if item.level and Progression.fromTotal(d.xp) < item.level then
		deny(player, "Reach level " .. item.level .. " to buy the " .. item.name .. ".")
		return
	end
	if d.echoes < item.price then
		deny(player, "Not enough Echoes.")
		return
	end
	-- one atomic update: the check and the charge happen together
	local bought = false
	Registry.DataService:Update(player, function(dd)
		if dd.gear.owned[id] or dd.echoes < item.price then
			return
		end
		dd.echoes -= item.price
		dd.gear.owned[id] = true
		bought = true
		-- new flashlights / batteries are equipped straight away
		if item.kind == "FLASHLIGHT" then
			dd.gear.flashlight = id
		elseif item.kind == "BATTERY" then
			dd.gear.battery = id
		elseif item.kind == "TOOL" and #dd.gear.loadout < Equipment.loadoutSlots(dd.upgrades) then
			table.insert(dd.gear.loadout, id)
		end
	end)
	if not bought then
		return
	end
	Registry.AudioService:Play2D({ player }, "UIPurchase")
	Net.fire(player, "ToolEvent", { kind = "purchased", id = id })
	Registry.AnalyticsService:Event(player, "EquipmentPurchased", item.price, { id = id })
	-- every tool owned
	local all = true
	for _, e in Equipment.List do
		if e.kind == "TOOL" and not EquipmentService:Owns(player, e.id) then
			all = false
		end
	end
	if all then
		Registry.ProgressionService:Award(player, "WELL_EQUIPPED")
	end
	refreshClient(player)
end

local function upgrade(player: Player, id: string)
	local def = Equipment.UpgradesById[id]
	local d = data(player)
	if not def or not d then
		return
	end
	local current = d.upgrades[id] or 0
	local nextLevel = def.levels[current + 1]
	if not nextLevel then
		return
	end
	if nextLevel.level and Progression.fromTotal(d.xp) < nextLevel.level then
		deny(player, "Reach level " .. nextLevel.level .. " for this upgrade.")
		return
	end
	if d.echoes < nextLevel.price then
		deny(player, "Not enough Echoes.")
		return
	end
	local done = false
	Registry.DataService:Update(player, function(dd)
		local cur = dd.upgrades[id] or 0
		if cur ~= current or dd.echoes < nextLevel.price then
			return
		end
		dd.echoes -= nextLevel.price
		dd.upgrades[id] = cur + 1
		done = true
	end)
	if done then
		Registry.AudioService:Play2D({ player }, "UIPurchase")
		Net.fire(player, "ToolEvent", { kind = "upgraded", id = id, level = current + 1 })
		Registry.AnalyticsService:Event(player, "UpgradePurchased", nextLevel.price, { id = id, level = current + 1 })
		EquipmentService:ApplyPassive(player)
		refreshClient(player)
	end
end

local function equip(player: Player, id: string)
	local item = Equipment.get(id)
	if not item or not EquipmentService:Owns(player, id) then
		return
	end
	Registry.DataService:Update(player, function(dd)
		if item.kind == "FLASHLIGHT" then
			dd.gear.flashlight = id
		elseif item.kind == "BATTERY" then
			dd.gear.battery = id
		end
	end)
	Registry.AudioService:Play2D({ player }, "UIEquip")
	refreshClient(player)
end

local function setLoadout(player: Player, list: any)
	if type(list) ~= "table" then
		return
	end
	local d = data(player)
	if not d then
		return
	end
	local slots = Equipment.loadoutSlots(d.upgrades)
	local clean, seen = {}, {}
	local count = 0
	for _, id in list do
		count += 1
		if count > 10 then
			break
		end
		local item = type(id) == "string" and Equipment.get(id)
		if item and item.kind == "TOOL" and not seen[id] and #clean < slots and EquipmentService:Owns(player, id) then
			seen[id] = true
			table.insert(clean, id)
		end
	end
	Registry.DataService:Update(player, function(dd)
		dd.gear.loadout = clean
	end)
	Registry.AudioService:Play2D({ player }, "UIEquip")
	refreshClient(player)
end

------------------------------------------------------------------------------------
-- Round: stats, belt and tools
------------------------------------------------------------------------------------

-- Flashlight stats and upgrade effects published as attributes (read everywhere).
function EquipmentService:ApplyPassive(player: Player)
	local d = data(player)
	if not d then
		return
	end
	local fl = Equipment.get(d.gear.flashlight) or Equipment.get(Equipment.Defaults.FLASHLIGHT)
	player:SetAttribute("FlashlightRange", fl.range)
	player:SetAttribute("FlashlightAngle", fl.angle)
	player:SetAttribute("FlashlightPower", fl.power)
	player:SetAttribute("FlashlightSteady", fl.steady == true)
	player:SetAttribute("HoldMultiplier", Equipment.holdMultiplier(d.upgrades))
	player:SetAttribute("SignalRange", Equipment.rangeMultiplier(d.upgrades))
	player:SetAttribute("FieldNotes", (d.upgrades.FIELD_NOTES or 0) > 0)
end

-- Called by RoundService for each participant. Returns the inventory gear settings.
function EquipmentService:PrepareRound(player: Player)
	self:ApplyPassive(player)
	local d = data(player)
	local belt: Belt = { tools = {}, selected = 0, thermalOn = false, sensors = {}, evidence = 0 }
	local spare = 0
	local gear = { capacity = 100, drainMult = 1, spareCells = 0 }
	if d then
		local fl = Equipment.get(d.gear.flashlight) or Equipment.get(Equipment.Defaults.FLASHLIGHT)
		local bat = Equipment.get(d.gear.battery) or Equipment.get(Equipment.Defaults.BATTERY)
		gear.capacity = bat.capacity or 100
		gear.drainMult = (fl.drain or 1) * Equipment.drainMultiplier(d.upgrades)
		for _, id in d.gear.loadout do
			local item = Equipment.get(id)
			if item then
				if id == "SPARE_CELL" then
					spare += item.charges or 1
				end
				table.insert(belt.tools, { id = id, charges = item.charges, charge = item.charge, readyAt = 0 })
			end
		end
	end
	gear.spareCells = spare
	belts[player] = belt
	self:Push(player)
	return gear
end

function EquipmentService:EndRound()
	for player, belt in belts do
		for _, s in belt.sensors do
			if s.part.Parent then
				s.part:Destroy()
			end
		end
		belt.sensors = {}
		belt.thermalOn = false
		player:SetAttribute("Tool", nil)
		player:SetAttribute("Thermal", false)
	end
	if glowFolder then
		glowFolder:ClearAllChildren()
	end
end

function EquipmentService:Push(player: Player)
	local belt = belts[player]
	if not belt then
		return
	end
	local list = {}
	for i, t in belt.tools do
		list[i] = { id = t.id, charges = t.charges, charge = if t.charge then math.floor(t.charge * 10) / 10 else nil, ready = math.max(0, t.readyAt - os.clock()) }
	end
	Net.fire(player, "ToolState", { tools = list, selected = belt.selected, thermal = belt.thermalOn })
end

function EquipmentService:GetEvidence(player: Player): number
	local belt = belts[player]
	return if belt then belt.evidence else 0
end

local function lookRay(player: Player, origin: any, dir: any): (Vector3?, Vector3?)
	local head = Util.getHead(player)
	if not head or not Util.isFiniteVector(dir) or dir.Magnitude < 0.5 then
		return nil, nil
	end
	local o = if Util.isFiniteVector(origin) and (origin - head.Position).Magnitude < 4 then origin else head.Position
	return o, dir.Unit
end

local USE = {}

USE.GLOWSTICKS = function(player: Player, tool: Tool)
	local root = Util.getRoot(player)
	if not root or (tool.charges or 0) <= 0 then
		return false
	end
	local look = Util.flat(root.CFrame.LookVector)
	local at = root.Position + (if look.Magnitude > 0.01 then look.Unit else Vector3.zero) * 1.6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(at + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), params)
	local ground = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
	local stick = Instance.new("Part")
	stick.Name = "GlowStick"
	stick.Size = Vector3.new(0.18, 0.18, 0.9)
	stick.CFrame = CFrame.new(ground + Vector3.new(0, 0.09, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	stick.Color = Color3.fromRGB(150, 255, 170)
	stick.Material = Enum.Material.Neon
	stick.Anchored = true
	stick.CanCollide = false
	stick.CanQuery = false
	stick.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(130, 255, 160)
	light.Brightness = 1.1
	light.Range = 13
	light.Shadows = false
	light.Parent = stick
	stick:SetAttribute("PlacedBy", player.UserId)
	stick.Parent = glowFolder
	Registry.AudioService:PlayAt("Drop", ground, { volume = 0.6, speed = 1.4 })
	tool.charges = (tool.charges or 1) - 1
	return true
end

USE.MOTION_SENSOR = function(player: Player, tool: Tool)
	local root = Util.getRoot(player)
	local belt = belts[player]
	if not root or not belt or (tool.charges or 0) <= 0 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local ground = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
	local part = Instance.new("Part")
	part.Name = "TripwireSensor"
	part.Size = Vector3.new(0.7, 0.25, 0.7)
	part.CFrame = CFrame.new(ground + Vector3.new(0, 0.13, 0))
	part.Color = Color3.fromRGB(40, 44, 46)
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	local led = Instance.new("Part")
	led.Name = "LED"
	led.Size = Vector3.new(0.12, 0.06, 0.12)
	led.CFrame = part.CFrame * CFrame.new(0, 0.15, 0)
	led.Color = Color3.fromRGB(90, 220, 120)
	led.Material = Enum.Material.Neon
	led.Anchored = true
	led.CanCollide = false
	led.CanQuery = false
	led.Parent = part
	part:SetAttribute("PlacedBy", player.UserId)
	part.Parent = glowFolder
	table.insert(belt.sensors, { part = part, alertAt = 0 })
	Registry.AudioService:PlayAt("DeviceBeep", ground)
	tool.charges = (tool.charges or 1) - 1
	return true
end

USE.INSTANT_CAMERA = function(player: Player, tool: Tool, origin: any, dir: any)
	if (tool.charges or 0) <= 0 then
		return false
	end
	local o, d = lookRay(player, origin, dir)
	if not o or not d then
		return false
	end
	tool.charges = (tool.charges or 1) - 1
	Registry.AudioService:PlayAt("CameraShutter", o)
	Net.fireAll("ToolEvent", { kind = "flash", at = o + d * 2, by = player.UserId })
	-- the Observer, caught on film
	local obs = Registry.ObserverService:GetPosition()
	if obs then
		local to = (obs + Vector3.new(0, 4, 0)) - o
		if to.Magnitude < 70 and math.deg(math.acos(math.clamp(to.Unit:Dot(d), -1, 1))) < 10 and Registry.PlayerService:HasLineOfSight(o, obs + Vector3.new(0, 4, 0), Registry.ObserverService:GetModel()) then
			Registry.ProgressionService:Award(player, "SHUTTERBUG")
			Net.fire(player, "Notify", { kind = "info", text = "The photograph is completely black." })
			return true
		end
	end
	-- evidence: a long-range report
	local before = (Registry.ObjectiveService:GetState() or { found = 0 }).found
	Registry.AnomalyService:Report(player, o, d, { range = 120 * (player:GetAttribute("SignalRange") or 1), photo = true })
	local after = (Registry.ObjectiveService:GetState() or { found = 0 }).found
	if after > before then
		local belt = belts[player]
		if belt then
			belt.evidence += 1
		end
		Net.fire(player, "Notify", { kind = "info", text = "Evidence developed. +bonus" })
	end
	return true
end

USE.SIGNAL_TRACKER = function(player: Player, tool: Tool)
	if (tool.charges or 0) <= 0 then
		return false
	end
	local target = Registry.GuidanceService:NextTarget()
	if not target then
		Net.fire(player, "Notify", { kind = "info", text = "No signal." })
		return false
	end
	tool.charges = (tool.charges or 1) - 1
	-- point at the item itself when the target is a pickup room, else the room
	Net.fire(player, "ToolEvent", { kind = "track", at = target.room.center + Vector3.new(0, 3, 0), label = target.room.name, duration = 20 })
	Registry.AudioService:Play2D({ player }, "DeviceBeep")
	return true
end

USE.THERMAL_VIEWER = function(player: Player, tool: Tool)
	local belt = belts[player]
	if not belt then
		return false
	end
	if belt.thermalOn then
		belt.thermalOn = false
	elseif (tool.charge or 0) > 0 then
		belt.thermalOn = true
	else
		Net.fire(player, "Notify", { kind = "info", text = "The thermal viewer is out of charge." })
		return false
	end
	player:SetAttribute("Thermal", belt.thermalOn)
	return true
end

USE.ANOMALY_LENS = function(player: Player, tool: Tool)
	local now = os.clock()
	if now < tool.readyAt then
		return false
	end
	local root = Util.getRoot(player)
	if not root then
		return false
	end
	local def = Equipment.get("ANOMALY_LENS")
	tool.readyAt = now + (def.cooldown or 30)
	local range = 25 * (player:GetAttribute("SignalRange") or 1)
	local spots = {}
	for _, inst in Registry.AnomalyService:GetActive() do
		if table.find(inst.players, player) or inst.scope == "GLOBAL" then
			for _, anchor in inst.spec.anchors or {} do
				local pos = if typeof(anchor.pos) == "Vector3" then anchor.pos elseif typeof(anchor.pos) == "Instance" and anchor.pos.Parent then Util.boundingSphere(anchor.pos) else nil
				if pos and (pos - root.Position).Magnitude <= range then
					table.insert(spots, pos)
				end
			end
		end
	end
	Net.fire(player, "ToolEvent", { kind = "lens", spots = spots })
	Registry.AudioService:Play2D({ player }, "RealityShift", { volume = 0.4 })
	return true
end

local function onTool(player: Player, action: any, index: any, a: any, b: any)
	if type(action) ~= "string" or type(index) ~= "number" or index ~= index or math.abs(index) > 16 then
		return
	end
	local belt = belts[player]
	if not belt or not Registry.PlayerService:IsAlive(player) then
		return
	end
	index = math.floor(index)
	if action == "select" then
		if index < 0 or index > #belt.tools then
			return
		end
		belt.selected = if belt.selected == index then 0 else index
		local tool = belt.tools[belt.selected]
		player:SetAttribute("Tool", tool and tool.id or nil)
		if tool and tool.id ~= "THERMAL_VIEWER" and belt.thermalOn then
			belt.thermalOn = false
			player:SetAttribute("Thermal", false)
		end
		Registry.AudioService:Play2D({ player }, "Equip")
		EquipmentService:Push(player)
	elseif action == "use" then
		local tool = belt.tools[index]
		if not tool or index ~= belt.selected then
			return
		end
		local fn = USE[tool.id]
		if fn then
			local ok, used = pcall(fn, player, tool, a, b)
			if not ok then
				warn("[EquipmentService] tool error:", used)
			end
			EquipmentService:Push(player)
		end
	end
end

-- Passive tools: sensors, the resonance meter, thermal charge and its secret.
local function passiveStep(dt: number)
	local observerPos = Registry.ObserverService:GetPosition()
	local mimic = Registry.ObserverService:GetMimic()
	for player, belt in belts do
		if player.Parent and Registry.PlayerService:IsAlive(player) then
			local range = player:GetAttribute("SignalRange") or 1
			-- tripwire sensors
			for _, s in belt.sensors do
				if s.part.Parent and os.clock() > s.alertAt then
					local p = s.part.Position
					local tripped = (observerPos and (observerPos - p).Magnitude < 14 * range) or (mimic and mimic.PrimaryPart and (mimic.PrimaryPart.Position - p).Magnitude < 14 * range)
					if tripped then
						s.alertAt = os.clock() + 10
						Registry.AudioService:PlayAt("MotionAlert", p, { volume = 1 })
						Net.fireList(Registry.PlayerService:GetAlive(), "ToolEvent", { kind = "sensor", at = p + Vector3.new(0, 1, 0), owner = player.DisplayName })
					end
				end
			end
			local tool = belt.tools[belt.selected]
			-- resonance meter: 0-5 bars from the nearest active anomaly in reach
			if tool and tool.id == "RESONANCE_METER" then
				local root = Util.getRoot(player)
				local best = math.huge
				if root then
					for _, inst in Registry.AnomalyService:GetActive() do
						if table.find(inst.players, player) or inst.scope == "GLOBAL" then
							for _, anchor in inst.spec.anchors or {} do
								local pos = if typeof(anchor.pos) == "Vector3" then anchor.pos elseif typeof(anchor.pos) == "Instance" and anchor.pos.Parent then Util.boundingSphere(anchor.pos) else nil
								if pos then
									best = math.min(best, (pos - root.Position).Magnitude)
								end
							end
						end
					end
				end
				local reach = 40 * range
				local bars = if best < reach then math.clamp(math.ceil((1 - best / reach) * 5), 1, 5) else 0
				Net.fire(player, "ToolEvent", { kind = "meter", bars = bars, observer = observerPos ~= nil and root ~= nil and (observerPos - root.Position).Magnitude < 30 })
			end
			-- thermal viewer drains while on; a mimic in view gives itself away
			if belt.thermalOn then
				local thermal = nil
				for _, t in belt.tools do
					if t.id == "THERMAL_VIEWER" then
						thermal = t
					end
				end
				if thermal then
					thermal.charge = math.max(0, (thermal.charge or 0) - dt)
					if thermal.charge <= 0 then
						belt.thermalOn = false
						player:SetAttribute("Thermal", false)
						EquipmentService:Push(player)
					end
				end
				if mimic and mimic.PrimaryPart then
					local head = Util.getHead(player)
					if head and (mimic.PrimaryPart.Position - head.Position).Magnitude < 35 and Registry.PlayerService:IsLookingAt(player, mimic.PrimaryPart.Position, 30, 35, mimic) then
						Registry.ProgressionService:Award(player, "COLD_SPOT")
					end
				end
			end
		end
	end
end

function EquipmentService:Init()
	Net.on("Gear", function(player, action, arg)
		if type(action) ~= "string" or not inLobby(player) then
			return
		end
		if action == "buy" and type(arg) == "string" then
			buy(player, arg)
		elseif action == "upgrade" and type(arg) == "string" then
			upgrade(player, arg)
		elseif action == "equip" and type(arg) == "string" then
			equip(player, arg)
		elseif action == "loadout" then
			setLoadout(player, arg)
		end
	end)
	Net.on("Tool", onTool)
	Net.handle("GetGear", function(player)
		return EquipmentService:GetGear(player)
	end)
end

function EquipmentService:Start()
	local folder = Instance.new("Folder")
	folder.Name = "PlacedGear"
	folder.Parent = workspace
	glowFolder = folder
	Registry.DataService.Loaded:Connect(function(player)
		self:ApplyPassive(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local belt = belts[player]
		if belt then
			for _, s in belt.sensors do
				if s.part.Parent then
					s.part:Destroy()
				end
			end
		end
		belts[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(passiveStep, 0.5)
			if not ok then
				warn("[EquipmentService] passive error:", err)
			end
		end
	end)
end

return EquipmentService
