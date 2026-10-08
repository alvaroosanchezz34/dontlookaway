--[[
	Props
	Furniture, fixtures and set dressing built entirely from parts.

	Conventions:
		Every builder receives a CFrame at floor level (or on the wall face for
		wall-mounted props) whose LookVector is the prop's front. Front = -Z local.
		Builders return a Model. CollectionService tags mark props that anomalies
		and systems can find (Painting, Clock, Chair, Plant, Lamp, Mirror, Photo,
		Sign, RoomNumber, Phone, Locker, Movable, Window...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Art = require(script.Parent.Art)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)

local P = Build.part
local D = Build.detail
local at = Build.at

local M = Enum.Material

local C = {
	woodDark = Color3.fromRGB(56, 42, 32),
	wood = Color3.fromRGB(88, 66, 48),
	woodLight = Color3.fromRGB(122, 96, 70),
	metal = Color3.fromRGB(92, 94, 96),
	metalDark = Color3.fromRGB(52, 54, 56),
	rust = Color3.fromRGB(96, 62, 44),
	beige = Color3.fromRGB(150, 140, 120),
	cream = Color3.fromRGB(176, 168, 148),
	black = Color3.fromRGB(22, 22, 24),
	fabric = Color3.fromRGB(64, 62, 60),
	paper = Color3.fromRGB(196, 190, 172),
	cardboard = Color3.fromRGB(128, 100, 70),
	green = Color3.fromRGB(46, 60, 40),
	white = Color3.fromRGB(190, 192, 188),
	skin = Color3.fromRGB(176, 170, 162),
}
local Props = {}
Props.Colors = C

-- Footprints in studs (width along local X, depth along local Z) for placement.
Props.Footprints = {
	desk = Vector2.new(6, 3),
	filingCabinet = Vector2.new(1.8, 2.2),
	locker = Vector2.new(2, 1.8),
	metalShelf = Vector2.new(6, 2),
	archiveShelf = Vector2.new(7, 2),
	sofa = Vector2.new(6, 2.6),
	fridge = Vector2.new(2.6, 2.4),
	vending = Vector2.new(3.4, 2.6),
	counter = Vector2.new(8, 2.2),
	bed = Vector2.new(3.2, 7),
	serverRack = Vector2.new(2.6, 3),
	workbench = Vector2.new(7, 2.6),
	boiler = Vector2.new(7, 7),
	crate = Vector2.new(3, 3),
}

local function tagModel(model: Model, ...: string)
	for _, tag in { ... } do
		model:AddTag(tag)
	end
end

local function model(parent, name, cf)
	return Build.model(parent, name, cf)
end

------------------------------------------------------------------------------------
-- SEATING
------------------------------------------------------------------------------------

function Props.officeChair(parent, cf: CFrame, rng)
	local m = model(parent, "OfficeChair", cf)
	local fabric = Build.vary(C.fabric, rng)
	P(m, "Seat", Vector3.new(2, 0.4, 2), at(cf, 0, 1.9, 0), fabric, M.Fabric)
	P(m, "Back", Vector3.new(1.9, 2.2, 0.35), at(cf, 0, 3.3, 0.95, -8, 0, 0), fabric, M.Fabric)
	D(m, "Pole", Vector3.new(0.25, 1.4, 0.25), at(cf, 0, 1.0, 0), C.metalDark, M.Metal)
	for i = 0, 4 do
		local a = math.rad(i * 72)
		D(m, "Leg", Vector3.new(0.18, 0.15, 1.1), cf * CFrame.new(0, 0.32, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.55), C.metalDark, M.Metal)
		Build.ball(m, "Caster", 0.24, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.12, -1.0), C.black, M.Rubber, { CanCollide = false })
	end
	if rng:Chance(0.3) then
		m:PivotTo(cf * CFrame.Angles(0, math.rad(rng:Number(-35, 35)), 0))
	end
	tagModel(m, "Chair", "Movable")
	return m
end

function Props.woodChair(parent, cf: CFrame, rng)
	local m = model(parent, "Chair", cf)
	local wood = Build.vary(C.wood, rng)
	P(m, "Seat", Vector3.new(1.8, 0.25, 1.8), at(cf, 0, 1.9, 0), wood, M.Wood)
	P(m, "Back", Vector3.new(1.8, 2, 0.2), at(cf, 0, 3.0, 0.8), wood, M.Wood)
	for _, o in { { -0.75, -0.75 }, { 0.75, -0.75 }, { -0.75, 0.75 }, { 0.75, 0.75 } } do
		D(m, "Leg", Vector3.new(0.2, 1.8, 0.2), at(cf, o[1], 0.9, o[2]), wood:Lerp(C.black, 0.2), M.Wood)
	end
	tagModel(m, "Chair", "Movable")
	return m
end

function Props.sofa(parent, cf: CFrame, rng)
	local m = model(parent, "Sofa", cf)
	local col = Build.vary(rng:Pick({ Color3.fromRGB(70, 56, 46), Color3.fromRGB(56, 62, 60), Color3.fromRGB(78, 64, 62) }), rng)
	P(m, "Base", Vector3.new(6, 1.4, 2.6), at(cf, 0, 0.9, 0), col, M.Fabric)
	P(m, "Back", Vector3.new(6, 2, 0.6), at(cf, 0, 2.4, 1), col, M.Fabric)
	P(m, "ArmL", Vector3.new(0.6, 1, 2.6), at(cf, -2.7, 2, 0), col, M.Fabric)
	P(m, "ArmR", Vector3.new(0.6, 1, 2.6), at(cf, 2.7, 2, 0), col, M.Fabric)
	for i = -1, 1, 2 do
		D(m, "Cushion", Vector3.new(2.5, 0.45, 2), at(cf, i * 1.25, 1.8, -0.1, rng:Number(-3, 3), 0, 0), col:Lerp(C.black, 0.1), M.Fabric)
	end
	tagModel(m, "Movable")
	return m
end

function Props.bench(parent, cf: CFrame, rng)
	local m = model(parent, "Bench", cf)
	local wood = Build.vary(C.woodDark, rng)
	P(m, "Seat", Vector3.new(6, 0.3, 1.6), at(cf, 0, 1.8, 0), wood, M.WoodPlanks)
	D(m, "LegL", Vector3.new(0.3, 1.7, 1.4), at(cf, -2.5, 0.85, 0), C.metalDark, M.Metal)
	D(m, "LegR", Vector3.new(0.3, 1.7, 1.4), at(cf, 2.5, 0.85, 0), C.metalDark, M.Metal)
	return m
end

function Props.waitingChairs(parent, cf: CFrame, rng, count: number?)
	local m = model(parent, "WaitingChairs", cf)
	local n = count or 3
	local fabric = Build.vary(Color3.fromRGB(58, 64, 70), rng)
	D(m, "Rail", Vector3.new(n * 2.2, 0.3, 0.3), at(cf, 0, 1.4, 0.4), C.metalDark, M.Metal)
	for i = 1, n do
		local x = (i - (n + 1) / 2) * 2.2
		local seatCf = at(cf, x, 0, 0)
		if rng:Chance(0.15) then
			-- one chair knocked over
			P(m, "Seat", Vector3.new(1.9, 0.3, 1.8), at(seatCf, 0, 0.3, -1.4, 80, 0, 0), fabric, M.Fabric)
		else
			P(m, "Seat", Vector3.new(1.9, 0.3, 1.8), at(seatCf, 0, 1.8, 0), fabric, M.Fabric)
			P(m, "Back", Vector3.new(1.9, 2, 0.25), at(seatCf, 0, 2.9, 0.85, -6, 0, 0), fabric, M.Fabric)
		end
		D(m, "Leg", Vector3.new(0.2, 1.6, 0.2), at(seatCf, 0, 0.8, 0.4), C.metalDark, M.Metal)
	end
	tagModel(m, "Movable")
	return m
end

------------------------------------------------------------------------------------
-- DESKS & TABLES
------------------------------------------------------------------------------------

function Props.paperStack(parent, cf: CFrame, rng)
	local m = model(parent, "Papers", cf)
	local h = 0
	for _ = 1, rng:Int(2, 6) do
		local t = rng:Number(0.04, 0.12)
		D(m, "Paper", Vector3.new(0.85, t, 1.1), at(cf, rng:Number(-0.06, 0.06), h + t / 2, rng:Number(-0.06, 0.06), 0, rng:Number(-12, 12), 0), C.paper:Lerp(C.beige, rng:Number(0, 0.6)), M.Plastic)
		h += t
	end
	return m
end

function Props.crt(parent, cf: CFrame, rng)
	local m = model(parent, "Monitor", cf)
	local col = Build.vary(C.cream, rng, 0.04)
	P(m, "Body", Vector3.new(1.6, 1.4, 1.5), at(cf, 0, 0.9, 0.15), col, M.SmoothPlastic)
	local screen = D(m, "Screen", Vector3.new(1.3, 1.05, 0.05), at(cf, 0, 0.95, -0.62), Color3.fromRGB(18, 22, 20), M.Glass, { Reflectance = 0.15 })
	D(m, "Stand", Vector3.new(0.9, 0.2, 0.9), at(cf, 0, 0.1, 0.1), col, M.SmoothPlastic)
	screen:AddTag("Screen")
	return m
end

function Props.phone(parent, cf: CFrame, rng)
	local m = model(parent, "Phone", cf)
	local col = rng:Pick({ Color3.fromRGB(30, 30, 32), Color3.fromRGB(150, 140, 120), Color3.fromRGB(80, 40, 36) })
	P(m, "Base", Vector3.new(0.9, 0.35, 1.1), at(cf, 0, 0.18, 0), col, M.SmoothPlastic, { CanCollide = false })
	D(m, "Handset", Vector3.new(1.1, 0.22, 0.28), at(cf, 0, 0.45, -0.1), col, M.SmoothPlastic)
	D(m, "Dial", Vector3.new(0.5, 0.05, 0.5), at(cf, 0, 0.38, 0.25), C.paper, M.SmoothPlastic)
	tagModel(m, "Phone")
	return m
end

function Props.deskLamp(parent, cf: CFrame, rng)
	local m = model(parent, "DeskLamp", cf)
	local col = rng:Pick({ Color3.fromRGB(46, 70, 54), Color3.fromRGB(40, 40, 42), Color3.fromRGB(120, 100, 60) })
	D(m, "Base", Vector3.new(0.6, 0.12, 0.6), at(cf, 0, 0.06, 0), col, M.Metal)
	D(m, "Arm", Vector3.new(0.1, 1.2, 0.1), at(cf, 0, 0.6, 0.1, 15, 0, 0), C.metalDark, M.Metal)
	local shade = D(m, "Shade", Vector3.new(0.7, 0.35, 0.5), at(cf, 0, 1.2, -0.15, 20, 0, 0), col, M.Metal)
	local bulb = D(m, "Bulb", Vector3.new(0.25, 0.1, 0.25), at(cf, 0, 1.05, -0.2), Color3.fromRGB(255, 226, 170), M.Neon)
	local light = Build.light(bulb, "SpotLight", { Brightness = 1.2, Range = 10, Angle = 80, Face = Enum.NormalId.Bottom, Color = Color3.fromRGB(255, 214, 160), Shadows = false })
	light.Enabled = false
	bulb:SetAttribute("PoweredLight", true)
	shade:SetAttribute("Shade", true)
	tagModel(m, "Lamp", "Movable")
	return m
end

function Props.desk(parent, cf: CFrame, rng, opts)
	opts = opts or {}
	local m = model(parent, "Desk", cf)
	local wood = Build.vary(rng:Pick({ C.wood, C.woodDark, Color3.fromRGB(98, 84, 66) }), rng)
	P(m, "Top", Vector3.new(6, 0.3, 3), at(cf, 0, 3.15, 0), wood, M.Wood)
	P(m, "SideL", Vector3.new(0.25, 3, 2.8), at(cf, -2.85, 1.5, 0), wood, M.Wood)
	P(m, "Drawers", Vector3.new(1.8, 3, 2.8), at(cf, 1.95, 1.5, 0), wood, M.Wood)
	D(m, "Modesty", Vector3.new(5.6, 1.8, 0.15), at(cf, 0, 2.1, 1.3), wood:Lerp(C.black, 0.15), M.Wood)
	for i = 0, 2 do
		D(m, "DrawerFront", Vector3.new(1.6, 0.85, 0.06), at(cf, 1.95, 0.6 + i * 0.95, -1.42), wood:Lerp(C.black, 0.1), M.Wood)
		D(m, "Handle", Vector3.new(0.5, 0.08, 0.08), at(cf, 1.95, 0.75 + i * 0.95, -1.47), C.metal, M.Metal)
	end
	local top = at(cf, 0, 3.3, 0)
	m:SetAttribute("SurfaceHeight", 3.3)
	if opts.monitor ~= false and rng:Chance(0.7) then
		Props.crt(m, at(top, rng:Number(-1.2, 0.2), 0, 0.4, 0, 180 + rng:Number(-15, 15), 0), rng)
	end
	if opts.papers ~= false and rng:Chance(0.6) then
		Props.paperStack(m, at(top, rng:Number(-2.4, -1.2), 0, rng:Number(-0.6, 0.6)), rng)
	end
	if opts.phone ~= false and rng:Chance(0.45) then
		Props.phone(m, at(top, 2.2, 0, -0.4, 0, rng:Number(-30, 30), 0), rng)
	end
	if opts.lamp ~= false and rng:Chance(0.35) then
		Props.deskLamp(m, at(top, -2.4, 0, 0.7, 0, rng:Number(-30, 30), 0), rng)
	end
	-- item spot on the desk
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Top")
	spot.WorldCFrame = at(top, rng:Number(-1.5, 1), 0.05, rng:Number(-0.9, -0.3))
	spot:AddTag("ItemSpot")
	return m
end

function Props.table(parent, cf: CFrame, rng, width: number?, depth: number?)
	local m = model(parent, "Table", cf)
	local w, d = width or 5, depth or 3
	local wood = Build.vary(rng:Pick({ C.wood, C.woodLight, C.woodDark }), rng)
	P(m, "Top", Vector3.new(w, 0.25, d), at(cf, 0, 3, 0), wood, M.Wood)
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		D(m, "Leg", Vector3.new(0.25, 2.9, 0.25), at(cf, o[1] * (w / 2 - 0.3), 1.45, o[2] * (d / 2 - 0.3)), wood:Lerp(C.black, 0.25), M.Wood)
	end
	m:SetAttribute("SurfaceHeight", 3.12)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Top")
	spot.WorldCFrame = at(cf, rng:Number(-w / 3, w / 3), 3.15, rng:Number(-d / 4, d / 4))
	spot:AddTag("ItemSpot")
	tagModel(m, "Movable")
	return m
end

function Props.roundTable(parent, cf: CFrame, rng)
	local m = model(parent, "RoundTable", cf)
	local col = Build.vary(C.cream, rng)
	Build.cylinder(m, "Top", 0.2, 3.6, at(cf, 0, 3, 0, 0, 0, 90), col, M.SmoothPlastic)
	Build.cylinder(m, "Pole", 2.8, 0.3, at(cf, 0, 1.5, 0, 0, 0, 90), C.metalDark, M.Metal, { CanCollide = false })
	Build.cylinder(m, "Foot", 0.15, 1.6, at(cf, 0, 0.08, 0, 0, 0, 90), C.metalDark, M.Metal)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Top")
	spot.WorldCFrame = at(cf, rng:Number(-0.6, 0.6), 3.12, rng:Number(-0.6, 0.6))
	spot:AddTag("ItemSpot")
	tagModel(m, "Movable")
	return m
end

------------------------------------------------------------------------------------
-- STORAGE
------------------------------------------------------------------------------------

function Props.box(parent, cf: CFrame, rng, size: Vector3?)
	local s = size or Vector3.new(rng:Number(1.4, 2.4), rng:Number(1, 1.8), rng:Number(1.4, 2.2))
	local m = model(parent, "Box", cf)
	local col = Build.vary(C.cardboard, rng, 0.08)
	P(m, "Body", s, at(cf, 0, s.Y / 2, 0, 0, rng:Number(-12, 12), 0), col, M.Cardboard)
	D(m, "Tape", Vector3.new(0.3, 0.02, s.Z + 0.02), at(cf, 0, s.Y + 0.01, 0, 0, rng:Number(-12, 12), 0), Color3.fromRGB(150, 130, 100), M.SmoothPlastic)
	tagModel(m, "Movable")
	return m
end

function Props.crate(parent, cf: CFrame, rng)
	local m = model(parent, "Crate", cf)
	local col = Build.vary(C.woodLight, rng, 0.08)
	P(m, "Body", Vector3.new(3, 3, 3), at(cf, 0, 1.5, 0), col, M.WoodPlanks)
	for _, z in { -1.52, 1.52 } do
		D(m, "Slat", Vector3.new(0.3, 3, 0.06), at(cf, -1.3, 1.5, z), col:Lerp(C.black, 0.2), M.Wood)
		D(m, "Slat", Vector3.new(0.3, 3, 0.06), at(cf, 1.3, 1.5, z), col:Lerp(C.black, 0.2), M.Wood)
	end
	tagModel(m, "Movable")
	return m
end

function Props.pallet(parent, cf: CFrame, rng)
	local m = model(parent, "Pallet", cf)
	local col = Build.vary(C.woodLight, rng, 0.1)
	for i = -2, 2 do
		P(m, "Board", Vector3.new(0.7, 0.15, 4), at(cf, i * 0.95, 0.55, 0), col, M.Wood)
	end
	for i = -1, 1 do
		D(m, "Block", Vector3.new(4.4, 0.45, 0.6), at(cf, 0, 0.25, i * 1.6), col:Lerp(C.black, 0.2), M.Wood)
	end
	if rng:Chance(0.6) then
		for i = 1, rng:Int(1, 3) do
			Props.box(m, at(cf, rng:Number(-1, 1), 0.62 + (i - 1) * 1.5, rng:Number(-0.8, 0.8)), rng, Vector3.new(2, 1.4, 2))
		end
	end
	return m
end

function Props.barrel(parent, cf: CFrame, rng)
	local m = model(parent, "Barrel", cf)
	local col = Build.vary(rng:Pick({ Color3.fromRGB(60, 74, 90), C.rust, Color3.fromRGB(90, 86, 60) }), rng)
	Build.cylinder(m, "Body", 3.6, 2.4, at(cf, 0, 1.8, 0, 0, 0, 90), col, M.CorrodedMetal)
	for _, y in { 0.6, 3.0 } do
		Build.cylinder(m, "Ring", 0.15, 2.5, at(cf, 0, y, 0, 0, 0, 90), col:Lerp(C.black, 0.3), M.Metal, { CanCollide = false, CastShadow = false })
	end
	tagModel(m, "Movable")
	return m
end

function Props.metalShelf(parent, cf: CFrame, rng, opts)
	opts = opts or {}
	local m = model(parent, "MetalShelf", cf)
	local col = Build.vary(C.metal, rng)
	local width = opts.width or 6
	local hw = width / 2
	for _, x in { -(hw - 0.1), hw - 0.1 } do
		for _, z in { -0.85, 0.85 } do
			P(m, "Post", Vector3.new(0.2, 7, 0.2), at(cf, x, 3.5, z), col, M.Metal)
		end
	end
	for i = 0, 3 do
		local y = 0.5 + i * 2.1
		P(m, "Shelf", Vector3.new(width, 0.15, 2), at(cf, 0, y, 0), col, M.Metal)
		local x = -(hw - 0.6)
		while x < hw - 0.6 do
			if rng:Chance(opts.fill or 0.6) then
				local w = math.min(rng:Number(0.9, 1.6), hw - 0.6 - x)
				local h = rng:Number(0.7, 1.5)
				D(m, "Item", Vector3.new(w, h, rng:Number(1, 1.7)), at(cf, x + w / 2, y + 0.08 + h / 2, rng:Number(-0.15, 0.15), 0, rng:Number(-8, 8), 0), Build.vary(rng:Pick({ C.cardboard, C.beige, C.metalDark, C.paper }), rng, 0.1), rng:Pick({ M.Cardboard, M.Plastic }))
				x += w + 0.1
			else
				x += rng:Number(0.6, 1.4)
			end
		end
		if i >= 1 and i <= 2 then
			local spot = Instance.new("Attachment")
			spot.Name = "ItemSpot"
			spot.Parent = m:FindFirstChild("Shelf")
			spot.WorldCFrame = at(cf, rng:Number(-(hw - 1), hw - 1), y + 0.1, -0.4)
			spot:AddTag("ItemSpot")
		end
	end
	return m
end

function Props.archiveShelf(parent, cf: CFrame, rng)
	local m = model(parent, "ArchiveShelf", cf)
	local wood = Build.vary(C.woodDark, rng)
	P(m, "Back", Vector3.new(7, 9, 0.2), at(cf, 0, 4.5, 0.9), wood, M.Wood)
	P(m, "SideL", Vector3.new(0.3, 9, 2), at(cf, -3.35, 4.5, 0), wood, M.Wood)
	P(m, "SideR", Vector3.new(0.3, 9, 2), at(cf, 3.35, 4.5, 0), wood, M.Wood)
	for i = 0, 4 do
		local y = 0.3 + i * 1.95
		P(m, "Shelf", Vector3.new(6.4, 0.2, 2), at(cf, 0, y, 0), wood, M.Wood)
		local x = -3
		while x < 2.8 do
			local w = rng:Number(0.35, 0.9)
			if rng:Chance(0.85) then
				local h = rng:Number(1, 1.5)
				D(m, "File", Vector3.new(w, h, 1.4), at(cf, x + w / 2, y + 0.1 + h / 2, 0.1 + rng:Number(-0.08, 0.08), 0, 0, rng:Chance(0.1) and rng:Number(-15, 15) or 0), Build.vary(rng:Pick({ C.cardboard, C.beige, Color3.fromRGB(80, 70, 60), Color3.fromRGB(70, 74, 80) }), rng, 0.1), M.Cardboard)
			end
			x += w + 0.04
		end
	end
	return m
end

function Props.filingCabinet(parent, cf: CFrame, rng)
	local m = model(parent, "FilingCabinet", cf)
	local col = Build.vary(rng:Pick({ Color3.fromRGB(100, 104, 100), Color3.fromRGB(80, 84, 90), Color3.fromRGB(120, 112, 96) }), rng)
	P(m, "Body", Vector3.new(1.8, 4.4, 2.2), at(cf, 0, 2.2, 0), col, M.Metal)
	for i = 0, 2 do
		local open = rng:Chance(0.12)
		D(m, "Drawer", Vector3.new(1.6, 1.25, 0.08), at(cf, 0, 0.75 + i * 1.4, if open then -1.6 else -1.12), col:Lerp(C.black, 0.08), M.Metal)
		D(m, "Handle", Vector3.new(0.6, 0.1, 0.1), at(cf, 0, 1.0 + i * 1.4, if open then -1.68 else -1.2), C.metal, M.Metal)
	end
	m:SetAttribute("SurfaceHeight", 4.4)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Body")
	spot.WorldCFrame = at(cf, 0, 4.45, 0)
	spot:AddTag("ItemSpot")
	tagModel(m, "Movable")
	return m
end

function Props.locker(parent, cf: CFrame, rng)
	local m = model(parent, "Locker", cf)
	local col = Build.vary(rng:Pick({ Color3.fromRGB(70, 84, 92), Color3.fromRGB(96, 92, 80), Color3.fromRGB(84, 90, 84) }), rng)
	P(m, "Body", Vector3.new(2, 6.6, 1.8), at(cf, 0, 3.3, 0), col, M.Metal)
	D(m, "Door", Vector3.new(1.8, 6.2, 0.06), at(cf, 0, 3.3, -0.93), col:Lerp(C.black, 0.06), M.Metal)
	for i = 0, 3 do
		D(m, "Vent", Vector3.new(1, 0.08, 0.04), at(cf, 0, 5.6 + i * 0.22, -0.97), C.black, M.Metal)
	end
	D(m, "Handle", Vector3.new(0.12, 0.6, 0.12), at(cf, 0.65, 3.2, -1), C.metal, M.Metal)
	tagModel(m, "Locker")
	return m
end

------------------------------------------------------------------------------------
-- DECOR
------------------------------------------------------------------------------------

function Props.plant(parent, cf: CFrame, rng, tall: boolean?)
	local m = model(parent, "Plant", cf)
	local pot = Build.vary(rng:Pick({ Color3.fromRGB(110, 70, 50), Color3.fromRGB(70, 70, 70), Color3.fromRGB(140, 130, 110) }), rng)
	local h = if tall then 1.8 else 1.2
	Build.cylinder(m, "Pot", h, 1.6, at(cf, 0, h / 2, 0, 0, 0, 90), pot, M.Slate)
	Build.cylinder(m, "Soil", 0.1, 1.4, at(cf, 0, h, 0, 0, 0, 90), Color3.fromRGB(40, 30, 22), M.Ground, { CanCollide = false })
	local leaf = Build.vary(rng:Pick({ C.green, Color3.fromRGB(70, 66, 40), Color3.fromRGB(52, 48, 36) }), rng, 0.08)
	local stemH = if tall then rng:Number(2.5, 3.5) else rng:Number(1.2, 2)
	D(m, "Stem", Vector3.new(0.15, stemH, 0.15), at(cf, 0, h + stemH / 2, 0), Color3.fromRGB(60, 50, 34), M.Wood)
	for _ = 1, rng:Int(5, 8) do
		local a = rng:Number(0, 360)
		local y = h + rng:Number(stemH * 0.4, stemH)
		local droop = rng:Number(20, 70) -- dying plants droop
		D(m, "Leaf", Vector3.new(0.5, 0.06, 1.6), cf * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(a), 0) * CFrame.Angles(math.rad(-droop), 0, 0) * CFrame.new(0, 0, -0.7), leaf:Lerp(Color3.fromRGB(90, 76, 46), rng:Number(0, 0.5)), M.Grass)
	end
	-- soil ring left behind if the plant disappears
	local ring = Build.cylinder(m.Parent, "SoilRing", 0.04, 1.7, at(cf, 0, 0.03, 0, 0, 0, 90), Color3.fromRGB(46, 36, 28), M.Ground, { CanCollide = false, CastShadow = false })
	ring.Name = "PlantMark"
	Build.hideForReveal(ring)
	local markRef = Instance.new("ObjectValue")
	markRef.Name = "Mark"
	markRef.Value = ring
	markRef.Parent = m
	tagModel(m, "Plant", "Movable")
	return m
end

function Props.painting(parent, wallCf: CFrame, rng, width: number?, height: number?, kind: string?)
	local w = width or rng:Pick({ 3.5, 4, 5 })
	local h = height or (w * rng:Number(0.65, 0.85))
	local m = model(parent, "Painting", wallCf)
	local frameCol = rng:Pick({ Color3.fromRGB(90, 70, 40), Color3.fromRGB(40, 32, 26), Color3.fromRGB(120, 100, 64) })
	local tilt = if rng:Chance(0.25) then rng:Number(-4, 4) else 0
	local base = wallCf * CFrame.Angles(0, 0, math.rad(tilt))
	P(m, "Frame", Vector3.new(w + 0.5, h + 0.5, 0.2), at(base, 0, 0, -0.12), frameCol, M.Wood, { CanCollide = false })
	local canvas = P(m, "Canvas", Vector3.new(w, h, 0.05), at(base, 0, 0, -0.24), Color3.fromRGB(40, 40, 40), M.SmoothPlastic, { CanCollide = false })
	local gui = Build.surfaceGui(canvas, Enum.NormalId.Front, 36)
	gui.Name = "Art"
	Art.painting(gui, rng, kind)
	-- the paler rectangle left on the wall if the painting disappears
	local patch = D(parent, "PaintingMark", Vector3.new(w + 0.5, h + 0.5, 0.04), at(wallCf, 0, 0, -0.03), Color3.fromRGB(150, 146, 132), M.Plaster)
	D(patch, "Nail", Vector3.new(0.12, 0.12, 0.2), at(wallCf, 0, h / 2 + 0.6, -0.1), C.metalDark, M.Metal)
	Build.hideForReveal(patch)
	local markRef = Instance.new("ObjectValue")
	markRef.Name = "Mark"
	markRef.Value = patch
	markRef.Parent = m
	tagModel(m, "Painting")
	return m
end

function Props.photo(parent, wallCf: CFrame, rng)
	local m = model(parent, "Photograph", wallCf)
	P(m, "Frame", Vector3.new(2.4, 1.8, 0.15), at(wallCf, 0, 0, -0.08), Color3.fromRGB(30, 26, 22), M.Wood, { CanCollide = false })
	local canvas = P(m, "Canvas", Vector3.new(2.1, 1.5, 0.04), at(wallCf, 0, 0, -0.17), Color3.fromRGB(140, 120, 90), M.SmoothPlastic, { CanCollide = false })
	local gui = Build.surfaceGui(canvas, Enum.NormalId.Front, 48)
	gui.Name = "Art"
	Art.photo(gui, rng)
	tagModel(m, "Photo")
	return m
end

function Props.clock(parent, wallCf: CFrame, rng)
	local m = model(parent, "Clock", wallCf)
	local rim = rng:Pick({ Color3.fromRGB(40, 36, 32), Color3.fromRGB(110, 90, 50), Color3.fromRGB(80, 80, 84) })
	Build.cylinder(m, "Body", 0.3, 2.2, at(wallCf, 0, 0, -0.16, 0, 90, 0), rim, M.Metal, { CanCollide = false })
	local face = P(m, "Face", Vector3.new(1.9, 1.9, 0.04), at(wallCf, 0, 0, -0.33), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local gui = Build.surfaceGui(face, Enum.NormalId.Front, 60)
	gui.Name = "Dial"
	local dial = Build.frame(gui, { Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(214, 208, 190) })
	Build.corner(dial, 0.5)
	for i = 1, 12 do
		local a = math.rad(i * 30)
		local tick = Build.frame(dial, {
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(if i % 3 == 0 then 0.04 else 0.025, if i % 3 == 0 then 0.12 else 0.07),
			Position = UDim2.fromScale(0.5 + math.sin(a) * 0.4, 0.5 - math.cos(a) * 0.4),
			Rotation = i * 30,
			BackgroundColor3 = Color3.fromRGB(30, 28, 26),
		})
		tick.ZIndex = 2
	end
	local function hand(name, length, thickness, color, z)
		local pivot = Build.frame(dial, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		pivot.ZIndex = z
		local bar = Build.frame(pivot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(thickness, length), BackgroundColor3 = color })
		bar.ZIndex = z
		return pivot
	end
	hand("Hour", 0.26, 0.035, Color3.fromRGB(20, 20, 20), 3)
	hand("Minute", 0.38, 0.025, Color3.fromRGB(20, 20, 20), 4)
	hand("Second", 0.4, 0.01, Color3.fromRGB(120, 30, 30), 5)
	local cap = Build.frame(dial, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.06, 0.06), BackgroundColor3 = Color3.fromRGB(20, 20, 20) })
	cap.ZIndex = 6
	Build.corner(cap, 0.5)
	m:SetAttribute("ClockMode", "normal")
	m:SetAttribute("ClockOffset", 0)
	tagModel(m, "Clock")
	return m
end

function Props.mirror(parent, wallCf: CFrame, rng, width: number?, height: number?)
	local w, h = width or 3, height or 3.6
	local m = model(parent, "Mirror", wallCf)
	P(m, "Frame", Vector3.new(w + 0.3, h + 0.3, 0.12), at(wallCf, 0, 0, -0.06), Color3.fromRGB(60, 60, 62), M.Metal, { CanCollide = false })
	local glass = P(m, "Glass", Vector3.new(w, h, 0.05), at(wallCf, 0, 0, -0.14), Color3.fromRGB(44, 52, 56), M.Glass, { Reflectance = 0.45, CanCollide = false })
	local gui = Build.surfaceGui(glass, Enum.NormalId.Front, 30)
	gui.Name = "Overlay"
	gui.LightInfluence = 0.6
	-- crack variant
	local crack = Build.frame(gui, { Name = "Crack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	local r = SeededRandom.new(rng:Int(1, 1e6))
	local cx, cy = r:Number(0.3, 0.7), r:Number(0.3, 0.6)
	for _ = 1, 9 do
		local len = r:Number(0.2, 0.6)
		local line = Build.frame(crack, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.new(len, 0, 0, 2), Rotation = r:Number(0, 360), BackgroundColor3 = Color3.fromRGB(220, 226, 230), BackgroundTransparency = 0.25 })
		line.ZIndex = 2
	end
	-- wrong reflection variant: a tall figure standing behind the viewer
	local figure = Build.frame(gui, { Name = "Figure", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	local fx = r:Number(0.25, 0.65)
	local body = Build.frame(figure, { Position = UDim2.fromScale(fx, 0.22), Size = UDim2.fromScale(0.12, 0.9), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 0.15 })
	Build.corner(body, 0.4)
	local head = Build.frame(figure, { Position = UDim2.fromScale(fx + 0.015, 0.08), Size = UDim2.fromScale(0.09, 0.14), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 0.15 })
	Build.corner(head, 0.5)
	tagModel(m, "Mirror")
	return m
end

function Props.sign(parent, wallCf: CFrame, text: string, width: number?, height: number?, style: string?)
	local w, h = width or 3, height or 0.8
	local m = model(parent, "Sign", wallCf)
	local bg, fg = Color3.fromRGB(30, 30, 30), Color3.fromRGB(220, 216, 204)
	if style == "exit" then
		bg, fg = Color3.fromRGB(16, 30, 22), Color3.fromRGB(150, 220, 170)
	elseif style == "paper" then
		bg, fg = Color3.fromRGB(196, 190, 170), Color3.fromRGB(30, 30, 30)
	elseif style == "brass" then
		bg, fg = Color3.fromRGB(120, 100, 60), Color3.fromRGB(30, 24, 16)
	end
	local plate = P(m, "Plate", Vector3.new(w, h, 0.1), at(wallCf, 0, 0, -0.06), bg, M.SmoothPlastic, { CanCollide = false })
	local gui = Build.surfaceGui(plate, Enum.NormalId.Front, 50)
	gui.Name = "SignGui"
	if style == "exit" then
		gui.LightInfluence = 0.2
		gui.Brightness = 1.6
	end
	local label = Build.text(gui, {
		Name = "Label",
		Size = UDim2.fromScale(0.92, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		Text = text,
		TextColor3 = fg,
		Font = if style == "paper" then Enum.Font.SpecialElite else Enum.Font.GothamBold,
	})
	label:SetAttribute("Original", text)
	tagModel(m, "Sign")
	return m, label
end

function Props.roomPlate(parent, wallCf: CFrame, number: string)
	local m, label = Props.sign(parent, wallCf, number, 1.4, 0.6, "brass")
	m.Name = "RoomPlate"
	m:RemoveTag("Sign")
	m:AddTag("RoomNumber")
	return m, label
end

-- Battery-backed exit sign: it stays lit through every power failure, a fixed
-- point of reference when everything else is dark.
function Props.exitSign(parent, cf: CFrame)
	local m = model(parent, "ExitSign", cf)
	D(m, "Rod", Vector3.new(0.1, 1, 0.1), at(cf, 0, 0.5, 0), C.metalDark, M.Metal)
	local box = D(m, "Box", Vector3.new(2.2, 0.8, 0.3), at(cf, 0, -0.3, 0), Color3.fromRGB(26, 30, 28), M.SmoothPlastic)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Build.surfaceGui(box, face, 50)
		gui.LightInfluence = 0
		gui.Brightness = 2.2
		local bg = Build.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 40, 24), BackgroundTransparency = 0.1 })
		bg.Name = "Panel"
		local label = Build.text(gui, { Name = "Label", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), Text = "EXIT", TextColor3 = Color3.fromRGB(150, 236, 170) })
		label:SetAttribute("Original", "EXIT")
	end
	local glow = Build.light(box, "PointLight", { Brightness = 0.6, Range = 9, Color = Color3.fromRGB(110, 210, 140), Shadows = false })
	glow.Name = "Glow"
	tagModel(m, "Sign", "ExitSign")
	return m
end

-- Ceiling emergency beacon: a caged red lamp with a slowly rotating reflector.
-- Dormant while the building has power; clients spin it during failures.
function Props.emergencyBeacon(parent, cf: CFrame)
	local m = model(parent, "EmergencyBeacon", cf)
	D(m, "Mount", Vector3.new(0.9, 0.25, 0.9), at(cf, 0, -0.12, 0), C.metalDark, M.Metal)
	local dome = Build.ball(m, "Dome", 0.75, at(cf, 0, -0.45, 0), Color3.fromRGB(90, 20, 18), M.Glass, { Transparency = 0.25, CanCollide = false, CastShadow = false })
	local rotor = D(m, "Rotor", Vector3.new(0.2, 0.2, 0.2), at(cf, 0, -0.45, 0), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false, CanQuery = false })
	for i, dir in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local spot = Build.light(rotor, "SpotLight", { Brightness = 0, Range = 22, Angle = 55, Face = dir, Color = Color3.fromRGB(255, 52, 40), Shadows = false })
		spot.Name = "Beam" .. i
	end
	local glow = Build.light(dome, "PointLight", { Brightness = 0, Range = 8, Color = Color3.fromRGB(255, 60, 48), Shadows = false })
	glow.Name = "Glow"
	tagModel(m, "EmergencyBeacon")
	return m
end

function Props.radiator(parent, cf: CFrame, rng)
	local m = model(parent, "Radiator", cf)
	local col = Build.vary(Color3.fromRGB(150, 146, 136), rng)
	for i = -4, 4 do
		D(m, "Fin", Vector3.new(0.25, 2.4, 0.6), at(cf, i * 0.38, 1.6, 0), col, M.Metal)
	end
	D(m, "Pipe", Vector3.new(3.6, 0.2, 0.2), at(cf, 0, 0.53, 0.03), col:Lerp(C.black, 0.2), M.Metal)
	return m
end

function Props.fireExtinguisher(parent, cf: CFrame)
	local m = model(parent, "Extinguisher", cf)
	-- cf stands 0.42 off the wall finish (backed placement); the bracket reaches back to it
	Build.cylinder(m, "Body", 1.8, 0.6, at(cf, 0, 2.4, -0.15, 0, 0, 90), Color3.fromRGB(120, 36, 32), M.SmoothPlastic, { CanCollide = false })
	D(m, "Top", Vector3.new(0.3, 0.4, 0.3), at(cf, 0, 3.45, -0.15), C.black, M.Metal)
	D(m, "Bracket", Vector3.new(0.7, 0.2, 0.55), at(cf, 0, 2, 0.12), C.metalDark, M.Metal)
	D(m, "Plate", Vector3.new(0.9, 1.8, 0.06), at(cf, 0, 2.6, 0.38), C.metalDark, M.Metal)
	return m
end

function Props.noticeBoard(parent, wallCf: CFrame, rng, lines)
	local m = model(parent, "NoticeBoard", wallCf)
	P(m, "Board", Vector3.new(5, 3.2, 0.2), at(wallCf, 0, 0, -0.1), Color3.fromRGB(110, 86, 60), M.Fabric, { CanCollide = false })
	for i = 1, rng:Int(4, 7) do
		D(m, "Note", Vector3.new(rng:Number(0.8, 1.3), rng:Number(1, 1.4), 0.03), at(wallCf, rng:Number(-1.8, 1.8), rng:Number(-0.9, 0.9), -0.22 - i * 0.034, 0, 0, rng:Number(-10, 10)), C.paper:Lerp(C.beige, rng:Number()), M.SmoothPlastic)
		if i == 1 and lines then
			local note = m:FindFirstChild("Note") :: BasePart
			local gui = Build.surfaceGui(note, Enum.NormalId.Front, 60)
			Build.text(gui, { Name = "Label", Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Text = lines, Font = Enum.Font.SpecialElite, TextColor3 = Color3.fromRGB(30, 30, 30) })
		end
	end
	return m
end

function Props.trashBin(parent, cf: CFrame, rng)
	local m = model(parent, "Trash", cf)
	Build.cylinder(m, "Bin", 1.6, 1.3, at(cf, 0, 0.8, 0, 0, 0, 90), Build.vary(C.metalDark, rng), M.Metal)
	if rng:Chance(0.5) then
		D(m, "Paper", Vector3.new(0.5, 0.5, 0.5), at(cf, 0.2, 1.7, 0, 20, 30, 0), C.paper, M.SmoothPlastic)
	end
	tagModel(m, "Movable")
	return m
end

function Props.wetFloorSign(parent, cf: CFrame)
	local m = model(parent, "WetFloor", cf)
	local col = Color3.fromRGB(170, 150, 60)
	D(m, "A", Vector3.new(1.4, 2.6, 0.1), at(cf, 0, 1.25, -0.35, 15, 0, 0), col, M.SmoothPlastic)
	D(m, "B", Vector3.new(1.4, 2.6, 0.1), at(cf, 0, 1.25, 0.35, -15, 0, 0), col, M.SmoothPlastic)
	return m
end

function Props.stain(parent, cf: CFrame, rng, size: number?)
	local s = size or rng:Number(2, 5)
	local p = D(parent, "Stain", Vector3.new(s, 0.02, s * rng:Number(0.5, 1)), cf * CFrame.new(0, 0.01, 0) * CFrame.Angles(0, math.rad(rng:Number(0, 180)), 0), Color3.fromRGB(30, 28, 22), M.SmoothPlastic, { Transparency = rng:Number(0.55, 0.8), CanQuery = false })
	return p
end

function Props.puddle(parent, cf: CFrame, rng, size: number?)
	local s = size or rng:Number(2, 4)
	local p = Build.cylinder(parent, "Puddle", 0.03, s, cf * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 24, 26), M.Glass, { Transparency = 0.35, Reflectance = 0.35, CanCollide = false, CastShadow = false, CanQuery = false })
	return p
end

function Props.scatterPapers(parent, cf: CFrame, rng, count: number?)
	for i = 1, count or rng:Int(2, 5) do
		-- each sheet a little higher than the last so overlapping sheets never flicker
		D(parent, "LoosePaper", Vector3.new(0.85, 0.02, 1.1), cf * CFrame.new(rng:Number(-1.6, 1.6), 0.02 + i * 0.007, rng:Number(-1.6, 1.6)) * CFrame.Angles(0, math.rad(rng:Number(0, 360)), 0), C.paper:Lerp(C.beige, rng:Number()), M.SmoothPlastic, { CanQuery = false })
	end
end

function Props.cable(parent, a: Vector3, b: Vector3, rng)
	local mid = (a + b) / 2 - Vector3.new(0, rng:Number(0.3, 1.2), 0)
	local function seg(p1, p2)
		local len = (p2 - p1).Magnitude
		if len < 0.05 then
			return
		end
		D(parent, "Cable", Vector3.new(0.1, 0.1, len), CFrame.lookAt((p1 + p2) / 2, p2), C.black, M.Rubber, { CanQuery = false })
	end
	seg(a, mid)
	seg(mid, b)
end

function Props.pipe(parent, a: Vector3, b: Vector3, diameter: number, color: Color3?)
	local len = (b - a).Magnitude
	local p = Build.cylinder(parent, "Pipe", len, diameter, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), color or Color3.fromRGB(80, 70, 60), M.CorrodedMetal, { CanCollide = false, CanQuery = false })
	return p
end

------------------------------------------------------------------------------------
-- ROOM-SPECIFIC FURNITURE
------------------------------------------------------------------------------------

function Props.receptionDesk(parent, cf: CFrame, rng)
	local m = model(parent, "ReceptionDesk", cf)
	local wood = Build.vary(C.woodDark, rng)
	P(m, "Front", Vector3.new(12, 4.2, 0.6), at(cf, 0, 2.1, -1.5), wood, M.Wood)
	P(m, "Counter", Vector3.new(12.4, 0.3, 1.6), at(cf, 0, 4.35, -1.3), Build.vary(Color3.fromRGB(70, 66, 60), rng), M.Marble)
	P(m, "Work", Vector3.new(11.4, 0.25, 2.2), at(cf, 0, 3, 0), wood, M.Wood)
	P(m, "SideL", Vector3.new(0.6, 4.2, 3.6), at(cf, -6, 2.1, 0), wood, M.Wood)
	P(m, "SideR", Vector3.new(0.6, 4.2, 3.6), at(cf, 6, 2.1, 0), wood, M.Wood)
	D(m, "Brand", Vector3.new(5, 0.6, 0.05), at(cf, 0, 3, -1.83), Color3.fromRGB(120, 100, 60), M.Metal)
	Props.crt(m, at(cf, -3, 3.12, 0.3, 0, 180, 0), rng)
	Props.phone(m, at(cf, 2, 3.12, 0, 0, 160, 0), rng)
	Props.paperStack(m, at(cf, 4, 3.12, 0.2), rng)
	local bell = Build.ball(m, "Bell", 0.5, at(cf, 1, 4.6, -1.3), Color3.fromRGB(150, 130, 70), M.Metal, { CanCollide = false })
	bell.CastShadow = false
	m:SetAttribute("SurfaceHeight", 3.12)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Work")
	spot.WorldCFrame = at(cf, rng:Number(-4, 4), 3.15, 0.2)
	spot:AddTag("ItemSpot")
	return m
end

function Props.counter(parent, cf: CFrame, rng, length: number?)
	local len = length or 8
	local m = model(parent, "Counter", cf)
	local cab = Build.vary(Color3.fromRGB(150, 140, 120), rng)
	P(m, "Cabinets", Vector3.new(len, 3, 2.2), at(cf, 0, 1.5, 0), cab, M.Wood)
	P(m, "Top", Vector3.new(len + 0.2, 0.25, 2.4), at(cf, 0, 3.12, -0.05), Color3.fromRGB(80, 78, 72), M.Granite)
	for i = 0, math.floor(len / 2) - 1 do
		D(m, "Door", Vector3.new(1.8, 2.5, 0.06), at(cf, -len / 2 + 1 + i * 2, 1.45, -1.12), cab:Lerp(C.black, 0.08), M.Wood)
		D(m, "Knob", Vector3.new(0.15, 0.15, 0.15), at(cf, -len / 2 + 1.7 + i * 2, 2.2, -1.2), C.metal, M.Metal)
	end
	m:SetAttribute("SurfaceHeight", 3.25)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Top")
	spot.WorldCFrame = at(cf, rng:Number(-len / 3, len / 3), 3.28, -0.2)
	spot:AddTag("ItemSpot")
	return m
end

function Props.sink(parent, cf: CFrame, rng)
	local m = model(parent, "Sink", cf)
	local white = Build.vary(C.white, rng, 0.04)
	P(m, "Basin", Vector3.new(2.4, 0.8, 1.8), at(cf, 0, 3, -0.2), white, M.Marble)
	D(m, "Bowl", Vector3.new(1.8, 0.1, 1.2), at(cf, 0, 3.39, -0.25), Color3.fromRGB(70, 74, 72), M.Marble)
	D(m, "Pedestal", Vector3.new(0.8, 2.6, 0.8), at(cf, 0, 1.3, 0.2), white, M.Marble)
	D(m, "Tap", Vector3.new(0.15, 0.6, 0.15), at(cf, 0, 3.7, 0.5), C.metal, M.Metal)
	D(m, "Spout", Vector3.new(0.15, 0.15, 0.6), at(cf, 0, 3.95, 0.25), C.metal, M.Metal)
	return m
end

function Props.toiletStall(parent, cf: CFrame, rng, doorOpen: boolean?)
	-- stall depth 6 (local -Z is the stall door side), width 4
	local m = model(parent, "Stall", cf)
	local panel = Build.vary(rng:Pick({ Color3.fromRGB(110, 120, 116), Color3.fromRGB(130, 120, 100) }), rng, 0.04)
	-- the right side sits 2 cm in so a neighbouring stall's left side never shares its plane
	P(m, "SideL", Vector3.new(0.15, 6.4, 5.6), at(cf, -2, 3.7, 0), panel, M.SmoothPlastic)
	P(m, "SideR", Vector3.new(0.15, 6.4, 5.6), at(cf, 1.98, 3.7, 0), panel, M.SmoothPlastic)
	local door = P(m, "StallDoor", Vector3.new(3.4, 5.8, 0.12), at(cf, 0, 3.6, -2.8), panel:Lerp(C.black, 0.1), M.SmoothPlastic)
	if doorOpen then
		door.CFrame = at(cf, -1.75, 3.6, -2.8) * CFrame.Angles(0, math.rad(-80), 0) * CFrame.new(1.7, 0, 0)
	end
	-- toilet
	local white = C.white
	P(m, "Bowl", Vector3.new(1.4, 1.4, 2), at(cf, 0, 0.7, 1.4), white, M.Marble)
	D(m, "Tank", Vector3.new(1.8, 1.6, 0.7), at(cf, 0, 2, 2.5), white, M.Marble)
	D(m, "Seat", Vector3.new(1.5, 0.12, 1.9), at(cf, 0, 1.45, 1.35), Color3.fromRGB(170, 166, 150), M.SmoothPlastic)
	return m
end

function Props.handDryer(parent, wallCf: CFrame)
	local m = model(parent, "HandDryer", wallCf)
	D(m, "Body", Vector3.new(1.2, 1.4, 0.8), at(wallCf, 0, 0, -0.4), Color3.fromRGB(170, 172, 170), M.Metal)
	D(m, "Nozzle", Vector3.new(0.3, 0.4, 0.3), at(wallCf, 0, -0.8, -0.5), C.metalDark, M.Metal)
	return m
end

function Props.fridge(parent, cf: CFrame, rng)
	local m = model(parent, "Fridge", cf)
	local col = Build.vary(Color3.fromRGB(176, 172, 160), rng)
	P(m, "Body", Vector3.new(2.6, 6.2, 2.4), at(cf, 0, 3.1, 0), col, M.SmoothPlastic)
	D(m, "Split", Vector3.new(2.5, 0.06, 0.04), at(cf, 0, 4.4, -1.21), C.black, M.SmoothPlastic)
	D(m, "Handle", Vector3.new(0.1, 1.2, 0.15), at(cf, 1.05, 5.1, -1.3), C.metal, M.Metal)
	D(m, "Handle", Vector3.new(0.1, 1.6, 0.15), at(cf, 1.05, 3.2, -1.3), C.metal, M.Metal)
	return m
end

function Props.vendingMachine(parent, cf: CFrame, rng)
	local m = model(parent, "Vending", cf)
	local col = Build.vary(rng:Pick({ Color3.fromRGB(80, 30, 30), Color3.fromRGB(40, 50, 70), Color3.fromRGB(50, 50, 52) }), rng)
	P(m, "Body", Vector3.new(3.4, 7, 2.6), at(cf, 0, 3.5, 0), col, M.Metal)
	local glass = D(m, "Window", Vector3.new(2.2, 4.6, 0.05), at(cf, -0.4, 4.2, -1.32), Color3.fromRGB(26, 30, 32), M.Glass, { Transparency = 0.2, Reflectance = 0.2 })
	for r = 0, 4 do
		for c = 0, 3 do
			if rng:Chance(0.6) then
				D(m, "Snack", Vector3.new(0.35, 0.6, 0.2), at(cf, -1.2 + c * 0.55, 2.4 + r * 0.9, -1.15), Build.vary(rng:Pick({ Color3.fromRGB(150, 60, 40), Color3.fromRGB(60, 90, 120), Color3.fromRGB(160, 140, 60) }), rng, 0.1), M.SmoothPlastic)
			end
		end
	end
	local panel = D(m, "Panel", Vector3.new(0.7, 1.6, 0.05), at(cf, 1.15, 4.4, -1.32), Color3.fromRGB(30, 30, 32), M.SmoothPlastic)
	local light = Build.light(glass, "SurfaceLight", { Brightness = 0.4, Range = 6, Face = Enum.NormalId.Front, Color = Color3.fromRGB(200, 220, 255), Shadows = false })
	light:SetAttribute("PoweredLight", true)
	light.Enabled = false
	panel:AddTag("Screen")
	return m
end

function Props.coffeeMachine(parent, cf: CFrame, rng)
	local m = model(parent, "CoffeeMachine", cf)
	D(m, "Body", Vector3.new(1.2, 1.6, 1.2), at(cf, 0, 0.8, 0), Build.vary(C.black, rng), M.SmoothPlastic)
	D(m, "Pot", Vector3.new(0.7, 0.7, 0.7), at(cf, 0, 0.4, -0.5), Color3.fromRGB(40, 30, 24), M.Glass, { Transparency = 0.3 })
	return m
end

function Props.waterCooler(parent, cf: CFrame, rng)
	local m = model(parent, "WaterCooler", cf)
	P(m, "Body", Vector3.new(1.4, 3.6, 1.4), at(cf, 0, 1.8, 0), Color3.fromRGB(180, 178, 170), M.SmoothPlastic)
	Build.cylinder(m, "Bottle", 1.6, 1.2, at(cf, 0, 4.4, 0, 0, 0, 90), Color3.fromRGB(150, 180, 190), M.Glass, { Transparency = 0.45, CanCollide = false })
	return m
end

function Props.bed(parent, cf: CFrame, rng)
	local m = model(parent, "Bed", cf)
	local metal = Build.vary(Color3.fromRGB(150, 156, 156), rng)
	P(m, "Frame", Vector3.new(3.2, 0.3, 7), at(cf, 0, 1.9, 0), metal, M.Metal)
	P(m, "Mattress", Vector3.new(3, 0.6, 6.6), at(cf, 0, 2.35, 0), Color3.fromRGB(176, 176, 170), M.Fabric)
	D(m, "Sheet", Vector3.new(3.1, 0.1, 3.8), at(cf, 0, 2.7, -1.2, rng:Number(-3, 3), rng:Number(-6, 6), 0), Color3.fromRGB(150, 160, 160), M.Fabric)
	D(m, "Pillow", Vector3.new(2.2, 0.4, 1), at(cf, 0, 2.85, 2.6), Color3.fromRGB(190, 190, 184), M.Fabric)
	P(m, "Head", Vector3.new(3.2, 2.4, 0.2), at(cf, 0, 3, 3.45), metal, M.Metal)
	for _, o in { { -1.4, -3.3 }, { 1.4, -3.3 }, { -1.4, 3.3 }, { 1.4, 3.3 } } do
		D(m, "Leg", Vector3.new(0.2, 1.8, 0.2), at(cf, o[1], 0.9, o[2]), metal, M.Metal)
	end
	m:SetAttribute("SurfaceHeight", 2.7)
	return m
end

function Props.ivStand(parent, cf: CFrame)
	local m = model(parent, "IVStand", cf)
	D(m, "Pole", Vector3.new(0.12, 6, 0.12), at(cf, 0, 3, 0), C.metal, M.Metal)
	D(m, "Bag", Vector3.new(0.6, 0.9, 0.2), at(cf, 0.3, 5.6, 0), Color3.fromRGB(190, 200, 200), M.Glass, { Transparency = 0.4 })
	D(m, "Base", Vector3.new(1.2, 0.12, 1.2), at(cf, 0, 0.06, 0), C.metal, M.Metal)
	return m
end

function Props.wheelchair(parent, cf: CFrame, rng)
	local m = model(parent, "Wheelchair", cf)
	local frameCol = C.metal
	P(m, "Seat", Vector3.new(1.8, 0.2, 1.8), at(cf, 0, 1.8, 0), Color3.fromRGB(40, 40, 44), M.Fabric)
	P(m, "Back", Vector3.new(1.8, 1.8, 0.15), at(cf, 0, 2.8, 0.9, -10, 0, 0), Color3.fromRGB(40, 40, 44), M.Fabric)
	for _, x in { -1.05, 1.05 } do
		Build.cylinder(m, "Wheel", 0.15, 2.6, at(cf, x, 1.3, 0.2), frameCol, M.Metal, { CanCollide = false })
	end
	m:PivotTo(cf * CFrame.Angles(0, math.rad(rng:Number(-30, 30)), 0))
	tagModel(m, "Movable", "Chair")
	return m
end

-- A privacy curtain on a track hung from the ceiling (ceilingH above cf).
function Props.curtain(parent, cf: CFrame, width: number, rng, ceilingH: number?)
	local m = model(parent, "Curtain", cf)
	local railY = 8.5
	D(m, "Rail", Vector3.new(width, 0.12, 0.12), at(cf, 0, railY, 0), C.metal, M.Metal)
	local top = ceilingH or 13
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		D(m, "Hanger", Vector3.new(0.08, top - railY, 0.08), at(cf, x, (railY + top) / 2, 0), C.metal, M.Metal)
	end
	local folds = math.floor(width / 0.8)
	for i = 0, folds - 1 do
		D(m, "Fold", Vector3.new(0.85, 7, 0.08), at(cf, -width / 2 + 0.4 + i * 0.8, 4.9, (i % 2) * 0.12, 0, (i % 2 == 0) and 12 or -12, 0), Build.vary(Color3.fromRGB(150, 168, 164), rng, 0.04), M.Fabric, { Transparency = 0.1 })
	end
	return m
end

function Props.serverRack(parent, cf: CFrame, rng)
	local m = model(parent, "ServerRack", cf)
	P(m, "Body", Vector3.new(2.6, 7.5, 3), at(cf, 0, 3.75, 0), Color3.fromRGB(26, 28, 30), M.Metal)
	for i = 0, 9 do
		D(m, "Unit", Vector3.new(2.3, 0.55, 0.05), at(cf, 0, 0.9 + i * 0.65, -1.52), Color3.fromRGB(40, 42, 46), M.Metal)
		if rng:Chance(0.6) then
			local led = D(m, "LED", Vector3.new(0.1, 0.1, 0.04), at(cf, 0.9, 0.9 + i * 0.65, -1.56), rng:Pick({ Color3.fromRGB(120, 220, 140), Color3.fromRGB(220, 170, 90) }), M.Neon)
			led:AddTag("BlinkLED")
		end
	end
	return m
end

function Props.cubicle(parent, cf: CFrame, rng)
	local m = model(parent, "Cubicle", cf)
	local col = Build.vary(Color3.fromRGB(96, 98, 100), rng, 0.04)
	P(m, "WallBack", Vector3.new(7.6, 4.6, 0.25), at(cf, 0, 2.3, 3.7), col, M.Fabric)
	P(m, "WallSide", Vector3.new(0.25, 4.6, 7.4), at(cf, -3.7, 2.3, 0), col, M.Fabric)
	Props.desk(m, at(cf, 0.2, 0, 2.1, 0, 180, 0), rng, { lamp = false })
	if rng:Chance(0.75) then
		Props.officeChair(m, at(cf, 0.4, 0, 0, 0, rng:Number(-40, 40), 0), rng)
	end
	return m
end

function Props.workbench(parent, cf: CFrame, rng)
	local m = model(parent, "Workbench", cf)
	local wood = Build.vary(C.woodLight, rng)
	P(m, "Top", Vector3.new(7, 0.4, 2.6), at(cf, 0, 3.2, 0), wood, M.WoodPlanks)
	for _, o in { { -3.2, -1 }, { 3.2, -1 }, { -3.2, 1 }, { 3.2, 1 } } do
		P(m, "Leg", Vector3.new(0.4, 3, 0.4), at(cf, o[1], 1.5, o[2]), C.metalDark, M.Metal)
	end
	P(m, "Pegboard", Vector3.new(7, 4, 0.2), at(cf, 0, 5.6, 1.2), Color3.fromRGB(150, 130, 100), M.Wood)
	for i = 1, 6 do
		D(m, "Tool", Vector3.new(0.2, rng:Number(0.8, 1.6), 0.15), at(cf, rng:Number(-3, 3), rng:Number(4.8, 6.6), 1.07 - i * 0.025, 0, 0, rng:Number(-20, 20)), Build.vary(rng:Pick({ C.metal, C.rust, C.black }), rng), M.Metal)
	end
	m:SetAttribute("SurfaceHeight", 3.4)
	local spot = Instance.new("Attachment")
	spot.Name = "ItemSpot"
	spot.Parent = m:FindFirstChild("Top")
	spot.WorldCFrame = at(cf, rng:Number(-2.5, 2.5), 3.42, -0.3)
	spot:AddTag("ItemSpot")
	return m
end

function Props.boiler(parent, cf: CFrame, rng)
	local m = model(parent, "Boiler", cf)
	local col = Build.vary(Color3.fromRGB(70, 62, 54), rng)
	Build.cylinder(m, "Tank", 7, 5.5, at(cf, 0, 3.6, 0, 0, 90, 0), col, M.CorrodedMetal)
	Build.cylinder(m, "CapA", 0.4, 5.9, at(cf, 0, 3.6, -3.5, 0, 90, 0), col:Lerp(C.black, 0.3), M.Metal)
	Build.cylinder(m, "CapB", 0.4, 5.9, at(cf, 0, 3.6, 3.5, 0, 90, 0), col:Lerp(C.black, 0.3), M.Metal)
	P(m, "Stand", Vector3.new(4, 1, 6), at(cf, 0, 0.5, 0), C.metalDark, M.Metal)
	Build.cylinder(m, "Flue", 6, 1.2, at(cf, 0, 9, 1.5, 0, 0, 90), C.metalDark, M.CorrodedMetal, { CanCollide = false })
	local gauge = Build.cylinder(m, "Gauge", 0.2, 1, at(cf, 0, 4.5, -3.75, 0, 90, 0), Color3.fromRGB(200, 196, 180), M.SmoothPlastic, { CanCollide = false })
	local glow = D(m, "Firebox", Vector3.new(1.6, 0.8, 0.1), at(cf, 0, 1.8, -3.6), Color3.fromRGB(255, 120, 50), M.Neon, { Transparency = 0.2 })
	local light = Build.light(glow, "PointLight", { Brightness = 0.8, Range = 12, Color = Color3.fromRGB(255, 120, 60), Shadows = false })
	light:AddTag("FireGlow")
	gauge:AddTag("Gauge")
	return m
end

function Props.valveWheel(parent, cf: CFrame)
	local m = model(parent, "Valve", cf)
	-- a wall flange, a short stem and the wheel standing off the wall
	Build.cylinder(m, "Flange", 0.1, 0.6, cf * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, math.rad(90), 0), C.metalDark, M.Metal, { CanCollide = false })
	D(m, "Stem", Vector3.new(0.15, 0.15, 0.5), at(cf, 0, 0, -0.3), C.metalDark, M.Metal)
	Build.cylinder(m, "Wheel", 0.15, 1.2, cf * CFrame.new(0, 0, -0.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(110, 30, 28), M.Metal, { CanCollide = false })
	return m
end

function Props.freezer(parent, cf: CFrame, rng)
	local m = model(parent, "Freezer", cf)
	local col = Build.vary(Color3.fromRGB(170, 176, 178), rng, 0.03)
	P(m, "Body", Vector3.new(3.2, 3.4, 2.4), at(cf, 0, 1.7, 0), col, M.Metal)
	P(m, "Lid", Vector3.new(3.2, 0.3, 2.4), at(cf, 0, 3.55, 0), col:Lerp(C.black, 0.05), M.Metal)
	D(m, "Frost", Vector3.new(3, 0.05, 2.2), at(cf, 0, 3.72, 0), Color3.fromRGB(220, 230, 240), M.Ice, { Transparency = 0.3 })
	tagModel(m, "Locker")
	return m
end

function Props.plasticStrips(parent, cf: CFrame, width: number)
	local m = model(parent, "Strips", cf)
	local n = math.floor(width / 0.5)
	for i = 0, n - 1 do
		D(m, "Strip", Vector3.new(0.45, 8.5, 0.05), at(cf, -width / 2 + 0.25 + i * 0.5, 5.25, 0), Color3.fromRGB(200, 210, 210), M.Glass, { Transparency = 0.55 })
	end
	return m
end

function Props.forklift(parent, cf: CFrame, rng)
	local m = model(parent, "Forklift", cf)
	local col = Build.vary(Color3.fromRGB(150, 120, 40), rng)
	P(m, "Body", Vector3.new(4, 3, 6), at(cf, 0, 2.2, 0), col, M.Metal)
	P(m, "Cage", Vector3.new(3.8, 3.5, 0.2), at(cf, 0, 5.5, 1), C.metalDark, M.Metal)
	D(m, "Roof", Vector3.new(4, 0.2, 3.6), at(cf, 0, 7.3, 0.4), C.metalDark, M.Metal)
	P(m, "Mast", Vector3.new(3, 7, 0.4), at(cf, 0, 3.5, -3.2), C.metalDark, M.Metal)
	D(m, "ForkL", Vector3.new(0.4, 0.2, 4), at(cf, -0.8, 0.3, -5.2), C.metalDark, M.Metal)
	D(m, "ForkR", Vector3.new(0.4, 0.2, 4), at(cf, 0.8, 0.3, -5.2), C.metalDark, M.Metal)
	for _, o in { { -2, 1.8 }, { 2, 1.8 }, { -2, -1.8 }, { 2, -1.8 } } do
		Build.cylinder(m, "Wheel", 0.8, 1.8, at(cf, o[1], 0.9, o[2]), C.black, M.Rubber, { CanCollide = false })
	end
	return m
end

-- A step ladder leaning against the wall behind it (+Z local is the wall side).
function Props.ladder(parent, cf: CFrame)
	local m = model(parent, "Ladder", cf)
	local col = Color3.fromRGB(150, 140, 110)
	local lean = math.rad(12)
	local length = 8
	-- rails: feet 0.8 out from the wall, tops resting against it
	local axis = Vector3.new(0, math.cos(lean), math.sin(lean))
	local mid = Vector3.new(0, length / 2 * math.cos(lean), 0)
	for _, x in { -0.8, 0.8 } do
		D(m, "Rail", Vector3.new(0.2, length, 0.2), cf * CFrame.new(x, mid.Y, 0) * CFrame.Angles(-lean, 0, 0), col, M.Wood)
	end
	for i = 0, 6 do
		local y = 0.9 + i * 1.05
		local t = y / axis.Y - length / 2
		D(m, "Rung", Vector3.new(1.6, 0.12, 0.12), cf * CFrame.new(0, y, axis.Z * t), col, M.Wood)
	end
	return m
end

function Props.rockingChair(parent, cf: CFrame, rng)
	local m = model(parent, "RockingChair", cf)
	local wood = Build.vary(C.woodDark, rng)
	P(m, "Seat", Vector3.new(2, 0.25, 2), at(cf, 0, 1.9, 0), wood, M.Wood)
	P(m, "Back", Vector3.new(2, 3, 0.2), at(cf, 0, 3.4, 1, -12, 0, 0), wood, M.Wood)
	for _, x in { -0.9, 0.9 } do
		D(m, "Rocker", Vector3.new(0.2, 0.25, 3), at(cf, x, 0.2, 0), wood, M.Wood)
		D(m, "Leg", Vector3.new(0.2, 1.7, 0.2), at(cf, x, 1.05, -0.8), wood, M.Wood)
		D(m, "Leg", Vector3.new(0.2, 1.7, 0.2), at(cf, x, 1.05, 0.8), wood, M.Wood)
	end
	m:SetAttribute("Rocking", true)
	tagModel(m, "Chair", "Movable")
	return m
end

function Props.window(parent, cf: CFrame, rng, boarded: boolean?)
	-- cf: centre of the window opening on the interior face, LookVector into the room
	local m = model(parent, "Window", cf)
	P(m, "Glass", Vector3.new(3.8, 6, 0.1), at(cf, 0, 0, 1.6), Color3.fromRGB(60, 70, 80), M.Glass, { Transparency = 0.55, Reflectance = 0.1, CanCollide = true })
	local frameCol = Color3.fromRGB(70, 62, 52)
	D(m, "SillIn", Vector3.new(4, 0.25, 0.8), at(cf, 0, -3.05, -0.3), frameCol, M.Wood)
	D(m, "MullionV", Vector3.new(0.15, 6, 0.15), at(cf, 0, 0, 1.5), frameCol, M.Wood)
	D(m, "MullionH", Vector3.new(3.8, 0.15, 0.15), at(cf, 0, 0, 1.5), frameCol, M.Wood)
	local boards = model(m, "Boards", cf)
	if boarded ~= false then
		local count = rng:Int(3, 5)
		for i = 1, count do
			local y = -2.4 + (i - 1) * (4.8 / math.max(1, count - 1)) + rng:Number(-0.25, 0.25)
			P(boards, "Board", Vector3.new(4.4, rng:Number(0.6, 0.9), 0.2), at(cf, 0, y, -0.15 - (i % 2) * 0.05, 0, 0, rng:Number(-12, 12)), Build.vary(C.woodLight, rng, 0.1), M.WoodPlanks, { CanCollide = false })
		end
	end
	-- handprints on the inside of the glass for the altered variant (hidden)
	local prints = model(m, "Handprints", cf)
	for i = 1, 4 do
		local hp = D(prints, "Print", Vector3.new(0.5, 0.7, 0.02), at(cf, rng:Number(-1.4, 1.4), rng:Number(-1.5, 1.8), 1.5, 0, 0, rng:Number(-20, 20)), Color3.fromRGB(200, 200, 200), M.SmoothPlastic, { Transparency = 0.6 })
		hp.Name = "Print" .. i
	end
	Build.hideForReveal(prints)
	tagModel(m, "Window")
	return m
end

------------------------------------------------------------------------------------
-- FIGURES
------------------------------------------------------------------------------------

-- A "resident": a faceless, unmoving occupant of the building. Harmless.
function Props.resident(parent, cf: CFrame, rng, pose: string?)
	local m = model(parent, "Resident", cf)
	local skin = Color3.fromRGB(168, 166, 160)
	local suit = rng:Pick({ Color3.fromRGB(36, 36, 40), Color3.fromRGB(56, 52, 46), Color3.fromRGB(40, 46, 52) })
	local shirt = Color3.fromRGB(176, 174, 166)
	local seated = pose == "seated"
	local hipY = if seated then 1.9 else 3
	if seated then
		P(m, "LegL", Vector3.new(0.9, 0.9, 2.2), at(cf, -0.5, hipY, -0.7), suit, M.Fabric, { CanCollide = false })
		P(m, "LegR", Vector3.new(0.9, 0.9, 2.2), at(cf, 0.5, hipY, -0.7), suit, M.Fabric, { CanCollide = false })
		P(m, "ShinL", Vector3.new(0.85, 1.9, 0.85), at(cf, -0.5, 0.95, -1.6), suit, M.Fabric, { CanCollide = false })
		P(m, "ShinR", Vector3.new(0.85, 1.9, 0.85), at(cf, 0.5, 0.95, -1.6), suit, M.Fabric, { CanCollide = false })
	else
		P(m, "LegL", Vector3.new(0.9, 3, 0.9), at(cf, -0.5, 1.5, 0), suit, M.Fabric)
		P(m, "LegR", Vector3.new(0.9, 3, 0.9), at(cf, 0.5, 1.5, 0), suit, M.Fabric)
	end
	P(m, "Torso", Vector3.new(2, 2.6, 1.05), at(cf, 0, hipY + 1.3, 0), suit, M.Fabric, { CanCollide = not seated })
	D(m, "Shirt", Vector3.new(0.6, 1.2, 0.05), at(cf, 0, hipY + 1.9, -0.53), shirt, M.Fabric)
	P(m, "ArmL", Vector3.new(0.8, 2.6, 0.8), at(cf, -1.42, hipY + 1.3, 0), suit, M.Fabric, { CanCollide = false })
	P(m, "ArmR", Vector3.new(0.8, 2.6, 0.8), at(cf, 1.42, hipY + 1.3, 0), suit, M.Fabric, { CanCollide = false })
	local head = P(m, "Head", Vector3.new(1.15, 1.35, 1.15), at(cf, 0, hipY + 3.3, 0), skin, M.SmoothPlastic, { CanCollide = false })
	head:SetAttribute("BaseCFrame", head.CFrame)
	m:SetAttribute("OriginPivot", cf)
	tagModel(m, "Resident")
	return m
end

-- A pale, very still figure used by the "DON'T STARE" anomaly.
function Props.paleFigure(parent, cf: CFrame)
	local m = model(parent, "PaleFigure", cf)
	local pale = Color3.fromRGB(196, 196, 192)
	P(m, "Body", Vector3.new(1.4, 6.4, 0.8), at(cf, 0, 3.2, 0), pale, M.SmoothPlastic, { CanCollide = false })
	P(m, "Head", Vector3.new(1, 1.3, 1), at(cf, 0, 7.1, 0, 0, 0, 12), pale, M.SmoothPlastic, { CanCollide = false })
	D(m, "ArmL", Vector3.new(0.4, 4.6, 0.4), at(cf, -0.95, 3.8, 0), pale, M.SmoothPlastic)
	D(m, "ArmR", Vector3.new(0.4, 4.6, 0.4), at(cf, 0.95, 3.8, 0), pale, M.SmoothPlastic)
	return m
end

function Props.mannequin(parent, cf: CFrame)
	local m = model(parent, "Mannequin", cf)
	local col = Color3.fromRGB(198, 190, 176)
	D(m, "Stand", Vector3.new(1.4, 0.15, 1.4), at(cf, 0, 0.08, 0), C.metalDark, M.Metal)
	D(m, "Pole", Vector3.new(0.15, 2.4, 0.15), at(cf, 0, 1.2, 0), C.metal, M.Metal)
	P(m, "Hips", Vector3.new(1.6, 1, 0.9), at(cf, 0, 2.9, 0), col, M.SmoothPlastic)
	P(m, "Torso", Vector3.new(1.8, 2.4, 1), at(cf, 0, 4.6, 0), col, M.SmoothPlastic)
	D(m, "Neck", Vector3.new(0.4, 0.5, 0.4), at(cf, 0, 6, 0), col, M.SmoothPlastic)
	Build.ball(m, "Head", 1.2, at(cf, 0, 6.8, 0), col, M.SmoothPlastic, { CanCollide = false })
	D(m, "ArmL", Vector3.new(0.45, 2.6, 0.45), at(cf, -1.15, 4.5, 0, 0, 0, -8), col, M.SmoothPlastic)
	D(m, "ArmR", Vector3.new(0.45, 2.6, 0.45), at(cf, 1.15, 4.5, 0, 0, 0, 8), col, M.SmoothPlastic)
	local badge = D(m, "Badge", Vector3.new(0.5, 0.3, 0.05), at(cf, 0.5, 5.2, -0.52), Color3.fromRGB(210, 206, 190), M.SmoothPlastic)
	badge.Name = "Badge"
	return m
end

------------------------------------------------------------------------------------
-- PUZZLE FIXTURES
------------------------------------------------------------------------------------

function Props.fuseBox(parent, wallCf: CFrame)
	local m = model(parent, "FuseBox", wallCf)
	P(m, "Box", Vector3.new(3.4, 4, 0.8), at(wallCf, 0, 0, -0.4), Color3.fromRGB(70, 76, 72), M.Metal)
	D(m, "Label", Vector3.new(2.2, 0.4, 0.05), at(wallCf, 0, 1.6, -0.83), Color3.fromRGB(170, 150, 60), M.SmoothPlastic)
	for i = 1, 3 do
		local x = (i - 2) * 0.95
		local socket = D(m, "Socket" .. i, Vector3.new(0.7, 1.6, 0.1), at(wallCf, x, -0.2, -0.85), Color3.fromRGB(26, 26, 26), M.SmoothPlastic)
		local fuse = D(m, "Fuse" .. i, Vector3.new(0.45, 1.3, 0.35), at(wallCf, x, -0.2, -0.98), Color3.fromRGB(196, 170, 120), M.Marble)
		Build.hideForReveal(fuse)
		local lamp = D(m, "Lamp" .. i, Vector3.new(0.25, 0.25, 0.08), at(wallCf, x, 1.0, -0.85), Color3.fromRGB(60, 20, 20), M.Neon)
		lamp:SetAttribute("Index", i)
		socket:SetAttribute("Index", i)
	end
	local hit = P(m, "Interact", Vector3.new(3.6, 4.2, 1.2), at(wallCf, 0, 0, -0.6), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	hit:AddTag("Interactable")
	hit:SetAttribute("InteractKind", "FuseBox")
	hit:SetAttribute("Prompt", "Insert fuse")
	hit:SetAttribute("HoldTime", 1)
	m:AddTag("FuseBox")
	return m
end

function Props.breakerPanel(parent, wallCf: CFrame)
	local m = model(parent, "BreakerPanel", wallCf)
	P(m, "Panel", Vector3.new(5, 3.6, 0.6), at(wallCf, 0, 0, -0.3), Color3.fromRGB(84, 88, 90), M.DiamondPlate)
	for i = 1, 5 do
		local x = (i - 3) * 0.9
		D(m, "Slot" .. i, Vector3.new(0.5, 1.6, 0.08), at(wallCf, x, -0.2, -0.62), Color3.fromRGB(20, 20, 20), M.SmoothPlastic)
		local lever = P(m, "Lever" .. i, Vector3.new(0.3, 0.8, 0.3), at(wallCf, x, -0.6, -0.75, 20, 0, 0), Color3.fromRGB(150, 40, 34), M.SmoothPlastic, { CanCollide = false })
		lever:SetAttribute("Index", i)
		lever:AddTag("Interactable")
		lever:SetAttribute("InteractKind", "Breaker")
		lever:SetAttribute("Index", i)
		lever:SetAttribute("Prompt", "Flip breaker " .. i)
		local label = D(m, "Num" .. i, Vector3.new(0.4, 0.3, 0.04), at(wallCf, x, 0.9, -0.62), Color3.fromRGB(200, 196, 180), M.SmoothPlastic)
		local gui = Build.surfaceGui(label, Enum.NormalId.Front, 80)
		Build.text(gui, { Size = UDim2.fromScale(1, 1), Text = tostring(i), TextColor3 = Color3.fromRGB(20, 20, 20), Font = Enum.Font.Code })
	end
	local status = D(m, "Status", Vector3.new(0.4, 0.4, 0.08), at(wallCf, 2.1, 1.4, -0.62), Color3.fromRGB(60, 20, 20), M.Neon)
	status:SetAttribute("Status", true)
	m:AddTag("BreakerPanel")
	return m
end

function Props.keypad(parent, wallCf: CFrame)
	local m = model(parent, "Keypad", wallCf)
	local body = P(m, "Body", Vector3.new(1, 1.5, 0.3), at(wallCf, 0, 0, -0.15), Color3.fromRGB(40, 42, 44), M.Metal, { CanCollide = false })
	local screen = D(m, "Screen", Vector3.new(0.8, 0.3, 0.04), at(wallCf, 0, 0.5, -0.32), Color3.fromRGB(30, 50, 40), M.Neon)
	local gui = Build.surfaceGui(screen, Enum.NormalId.Front, 80)
	Build.text(gui, { Name = "Readout", Size = UDim2.fromScale(1, 1), Text = "----", Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(150, 230, 170) })
	for r = 0, 3 do
		for c = 0, 2 do
			D(m, "Key", Vector3.new(0.2, 0.18, 0.05), at(wallCf, (c - 1) * 0.26, 0.15 - r * 0.24, -0.32), Color3.fromRGB(150, 150, 146), M.SmoothPlastic)
		end
	end
	body:AddTag("Interactable")
	body:SetAttribute("InteractKind", "Keypad")
	body:SetAttribute("Prompt", "Use keypad")
	m:AddTag("Keypad")
	return m
end

function Props.symbolCabinet(parent, cf: CFrame)
	local m = model(parent, "SymbolCabinet", cf)
	local wood = Color3.fromRGB(52, 40, 32)
	P(m, "Body", Vector3.new(5, 4, 2.2), at(cf, 0, 2, 0), wood, M.Wood)
	P(m, "Top", Vector3.new(5.3, 0.3, 2.4), at(cf, 0, 4.15, 0), wood:Lerp(C.black, 0.2), M.Wood)
	local drawer = P(m, "Drawer", Vector3.new(4.4, 1.2, 0.1), at(cf, 0, 1.2, -1.12), wood:Lerp(C.black, 0.1), M.Wood, { CanCollide = false })
	drawer:SetAttribute("ClosedCFrame", drawer.CFrame)
	for i = 1, 4 do
		local x = (i - 2.5) * 1.05
		local dial = Build.cylinder(m, "Dial" .. i, 0.25, 0.9, at(cf, x, 2.9, -1.2, 0, 90, 0), Color3.fromRGB(150, 130, 90), M.Metal, { CanCollide = false })
		dial:SetAttribute("Index", i)
		local face = D(m, "DialFace" .. i, Vector3.new(0.75, 0.75, 0.02), at(cf, x, 2.9, -1.34), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1 })
		local gui = Build.surfaceGui(face, Enum.NormalId.Front, 80)
		gui.Name = "Face"
		local plate = Build.frame(gui, { Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(196, 186, 160) })
		Build.corner(plate, 0.5)
		local hit = P(m, "DialHit" .. i, Vector3.new(0.95, 0.95, 0.6), at(cf, x, 2.9, -1.3), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
		hit:AddTag("Interactable")
		hit:SetAttribute("InteractKind", "SymbolDial")
		hit:SetAttribute("Index", i)
		hit:SetAttribute("Prompt", "Turn dial " .. i)
		-- dot markers above each dial indicate its order
		for d = 1, i do
			D(m, "Dot", Vector3.new(0.12, 0.12, 0.04), at(cf, x + (d - (i + 1) / 2) * 0.2, 3.55, -1.13), Color3.fromRGB(200, 196, 180), M.SmoothPlastic)
		end
	end
	m:AddTag("SymbolCabinet")
	return m
end

function Props.offeringTable(parent, cf: CFrame)
	local m = model(parent, "OfferingTable", cf)
	local wood = Color3.fromRGB(70, 52, 40)
	P(m, "Top", Vector3.new(5, 0.3, 2.4), at(cf, 0, 2.8, 0), wood, M.Wood)
	for _, o in { { -2.2, -1 }, { 2.2, -1 }, { -2.2, 1 }, { 2.2, 1 } } do
		P(m, "Leg", Vector3.new(0.3, 2.7, 0.3), at(cf, o[1], 1.35, o[2]), wood:Lerp(C.black, 0.2), M.Wood)
	end
	D(m, "Cloth", Vector3.new(4.6, 0.05, 2), at(cf, 0, 2.97, 0), Color3.fromRGB(170, 160, 150), M.Fabric)
	local items = { "MUSIC_BOX", "DOLL", "CANDLE" }
	for i, itemId in items do
		local x = (i - 2) * 1.5
		local outline = D(m, "Outline" .. i, Vector3.new(1, 0.02, 1), at(cf, x, 3.0, 0), Color3.fromRGB(60, 50, 44), M.SmoothPlastic, { Transparency = 0.3 })
		outline:SetAttribute("ItemId", itemId)
		local hit = P(m, "Slot" .. i, Vector3.new(1.3, 1.6, 1.3), at(cf, x, 3.7, 0), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
		hit:AddTag("Interactable")
		hit:SetAttribute("InteractKind", "Offering")
		hit:SetAttribute("ItemId", itemId)
		hit:SetAttribute("Index", i)
		hit:SetAttribute("Prompt", "Place")
	end
	m:AddTag("OfferingTable")
	return m
end

function Props.tapeRecorder(parent, cf: CFrame)
	local m = model(parent, "TapeRecorder", cf)
	local body = P(m, "Body", Vector3.new(2, 0.7, 1.3), at(cf, 0, 0.35, 0), Color3.fromRGB(40, 38, 36), M.SmoothPlastic, { CanCollide = false })
	D(m, "Deck", Vector3.new(1, 0.05, 0.6), at(cf, -0.3, 0.72, 0), Color3.fromRGB(20, 20, 20), M.Glass)
	for i = 0, 3 do
		D(m, "Btn", Vector3.new(0.2, 0.12, 0.2), at(cf, 0.45 + (i % 2) * 0.28, 0.75, -0.2 + (i // 2) * 0.3), Color3.fromRGB(150, 146, 140), M.SmoothPlastic)
	end
	body:AddTag("Interactable")
	body:SetAttribute("InteractKind", "TapeRecorder")
	body:SetAttribute("Prompt", "Insert cassette")
	m:AddTag("TapeRecorder")
	return m
end

function Props.closetLamp(parent, wallCf: CFrame, color: Color3, index: number)
	local m = model(parent, "ClosetLamp", wallCf)
	D(m, "Housing", Vector3.new(0.8, 0.6, 0.5), at(wallCf, 0, 0, -0.25), C.metalDark, M.Metal)
	local bulb = D(m, "Bulb", Vector3.new(0.5, 0.35, 0.2), at(wallCf, 0, 0, -0.55), color:Lerp(Color3.new(0, 0, 0), 0.6), M.Neon)
	bulb:SetAttribute("LitColor", color)
	local light = Build.light(bulb, "PointLight", { Brightness = 0.9, Range = 8, Color = color, Shadows = false })
	light.Enabled = false
	m:SetAttribute("Index", index)
	m:AddTag("ClosetLamp")
	return m
end

function Props.exitPanel(parent, wallCf: CFrame)
	local m = model(parent, "ExitPanel", wallCf)
	P(m, "Panel", Vector3.new(3, 3.6, 0.3), at(wallCf, 0, 0, -0.15), Color3.fromRGB(46, 48, 50), M.Metal, { CanCollide = false })
	for i = 1, 4 do
		local lamp = D(m, "Lock" .. i, Vector3.new(0.5, 0.5, 0.08), at(wallCf, -0.9 + ((i - 1) % 2) * 1.8, 0.9 - ((i - 1) // 2) * 1.2, -0.33), Color3.fromRGB(70, 20, 20), M.Neon)
		lamp:SetAttribute("Index", i)
	end
	local screen = D(m, "Screen", Vector3.new(2.4, 0.6, 0.05), at(wallCf, 0, -1.3, -0.33), Color3.fromRGB(20, 24, 22), M.SmoothPlastic)
	local gui = Build.surfaceGui(screen, Enum.NormalId.Front, 70)
	gui.LightInfluence = 0.2
	Build.text(gui, { Name = "Readout", Size = UDim2.fromScale(0.95, 0.8), Position = UDim2.fromScale(0.025, 0.1), Text = "LOCKED", Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(200, 120, 110) })
	m:AddTag("ExitPanel")
	return m
end

return Props
