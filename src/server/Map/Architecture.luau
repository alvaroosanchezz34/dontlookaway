--[[
	Architecture
	The building's services and hardware, added to every room after furnishing
	(Visual Overhaul V2). Real buildings read as real because of these small,
	repeated, functional things:

	  doors      three hinge barrels on the hinge jamb, lever handles on a rose,
	             an escutcheon with a keyhole, steel kick plates, plinth blocks
	             under the casings
	  walls      a light switch on the latch side of each room door, power
	             outlets on free wall, surface conduit with clamps and junction
	             boxes in the basement and service rooms
	  ceilings   supply / return grilles and sprinkler heads in the suspended
	             ceilings, a smoke detector per room, water-stained tiles and the
	             odd missing or hanging tile

	Rules
	  * Pure decoration: no collision, no queries, no touch, no shadows, so
	    interaction, perception rays, navigation and anomalies never see it.
	  * Nothing goes where furniture already is (oriented-box clearance test
	    against every furniture part), and every wall-mounted detail takes its
	    wall spot out of room.wallSpots, which anomalies and objectives use for
	    false doors, shadows and markings. A room always keeps at least
	    MIN_WALL_SPOTS of them, or the detail is skipped.
	  * Deterministic: one derived random stream, rooms visited in sorted order.
	  * Everything is grouped per room under Building/Detail/<roomId> (attribute
	    Center) so clients can hide it by distance (DetailLOD). Door hardware
	    lives in the door model and moves with it (Offset attributes).
	  * Every face sits at least VisualStandards.Proud off the surface it is
	    mounted on (no z-fighting, see tools/zfight.luau).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Layout)
local Build = require(script.Parent.Build)
local GeometryValidator = require(script.Parent.GeometryValidator)
local VisualStandards = require(ReplicatedStorage.Shared.VisualStandards)

local Architecture = {}

local CELL = Layout.Cell
local CH = Layout.CeilingHeight
local PROUD = VisualStandards.Proud
local SKIN = 0.2 -- wall finish thickness (MapBuilder skins)
local MIN_WALL_SPOTS = 3
local M = Enum.Material
local TRIM_COLOR = Color3.fromRGB(52, 40, 30) -- MapBuilder door casings

local DIRS = { { dx = 1, dz = 0 }, { dx = -1, dz = 0 }, { dx = 0, dz = 1 }, { dx = 0, dz = -1 } }

-- Room kinds that get each family of detail.
local NO_DETAIL = { secret = true, closet = true }
local OUTLET_KINDS = { office = true, mail = true, reception = true, breakroom = true, security = true, conference = true, openoffice = true, infirmary = true, server = true, archive = true, quiet = true, gallery = true, corridor = true, storage = true, maintenance = true, utility = true, dock = true, restroom = true }
local CONDUIT_STYLES = { basement = true, industrial = true, stairs = true }

Architecture.Stats = {}

------------------------------------------------------------------------------------
-- part helpers
------------------------------------------------------------------------------------

local function deco(parent: Instance, name: string, size: Vector3, cf: CFrame, surface: string, color: Color3?): Part
	local p = Build.part(parent, name, size, cf, nil, nil)
	VisualStandards.apply(p, surface, color)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function decoCyl(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, surface: string, color: Color3?): Part
	local p = deco(parent, name, Vector3.new(length, diameter, diameter), cf, surface, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

------------------------------------------------------------------------------------
-- clearance against furniture
------------------------------------------------------------------------------------

local GRID = 8

local function hashKey(x: number, y: number, z: number): number
	return (x + 512) * 1048576 + (y + 64) * 1024 + (z + 512)
end

local function newClearance(furniture: Instance?)
	local cells = {}
	if furniture then
		for _, d in furniture:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local box = GeometryValidator.boxFrom(d.CFrame, d.Size)
				for x = math.floor(box.min.X / GRID), math.floor(box.max.X / GRID) do
					for y = math.floor(box.min.Y / GRID), math.floor(box.max.Y / GRID) do
						for z = math.floor(box.min.Z / GRID), math.floor(box.max.Z / GRID) do
							local k = hashKey(x, y, z)
							cells[k] = cells[k] or {}
							table.insert(cells[k], box)
						end
					end
				end
			end
		end
	end
	-- true when a box of `size` at `cf` (grown by `margin`) touches no furniture
	return function(cf: CFrame, size: Vector3, margin: number?): boolean
		local m = margin or 0.08
		local box = GeometryValidator.boxFrom(cf, size + Vector3.new(m, m, m) * 2)
		for x = math.floor(box.min.X / GRID), math.floor(box.max.X / GRID) do
			for y = math.floor(box.min.Y / GRID), math.floor(box.max.Y / GRID) do
				for z = math.floor(box.min.Z / GRID), math.floor(box.max.Z / GRID) do
					local list = cells[hashKey(x, y, z)]
					if list then
						for _, other in list do
							if GeometryValidator.penetration(box, other) > 0 then
								return false
							end
						end
					end
				end
			end
		end
		return true
	end
end

------------------------------------------------------------------------------------
-- context
------------------------------------------------------------------------------------

local function sortedRooms(map)
	local list = {}
	for _, room in map.Rooms do
		table.insert(list, room)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function roomFolder(ctx, room): Folder
	local f = ctx.folders[room.id]
	if not f then
		f = Instance.new("Folder")
		f.Name = room.id
		f:SetAttribute("Room", room.id)
		f:SetAttribute("Center", room.center + Vector3.new(0, CH / 2, 0))
		f:SetAttribute("Radius", (room.max - room.min).Magnitude / 2)
		f:AddTag("DetailGroup")
		f.Parent = ctx.root
		ctx.folders[room.id] = f
	end
	return f
end

local function count(name: string, n: number?)
	Architecture.Stats[name] = (Architecture.Stats[name] or 0) + (n or 1)
end

local function capCell(floorId: string, x: number, z: number): boolean
	for _, exp in Layout.Expansions do
		if exp.floor == floorId and x == exp.capX and z >= exp.z0 and z <= exp.z1 then
			return true
		end
	end
	return false
end

-- The wall spot (anomaly / objective anchor) a wall detail at `pos` facing
-- `normal` would cover. Returns the index, or nil when none is near.
local function spotAt(room, pos: Vector3, normal: Vector3): number?
	for i, spot in room.wallSpots do
		local cf = spot.cframe
		local flat = (cf.Position - pos) * Vector3.new(1, 0, 1)
		-- spots face out of the wall into the room, like `normal`
		if flat.Magnitude < CELL * 0.75 and cf.LookVector:Dot(normal) > 0.9 then
			return i
		end
	end
	return nil
end

-- Takes the wall spot a detail needs. False when the room cannot spare it.
local function claimWall(room, pos: Vector3, normal: Vector3): boolean
	local i = spotAt(room, pos, normal)
	if not i then
		return true
	end
	if #room.wallSpots <= MIN_WALL_SPOTS then
		return false
	end
	table.remove(room.wallSpots, i)
	return true
end

------------------------------------------------------------------------------------
-- doors
------------------------------------------------------------------------------------

local function attachToDoor(panel: BasePart, part: BasePart)
	part:SetAttribute("Offset", panel.CFrame:ToObjectSpace(part.CFrame))
end

local function doorHardware(ctx, rec)
	local model = rec.model
	if not (model and model:IsA("Model") and model:HasTag("Door")) then
		return
	end
	local panel = model.PrimaryPart
	local hingeSide = model:GetAttribute("HingeSide")
	if not panel or type(hingeSide) ~= "number" then
		return
	end
	local room = ctx.map.Rooms[rec.roomA or ""] or ctx.map.Rooms[rec.roomB or ""]
	local w, h, t = panel.Size.X, panel.Size.Y, panel.Size.Z
	local closed = panel.CFrame
	local wooden = panel.Material == M.Wood
	local metalName = if wooden and rec.floor ~= "B" then "brass" else "hardware"
	local frameCF = CFrame.lookAt(rec.center, rec.center + rec.passageDir)

	-- hinge barrels on the hinge axis (the panel turns about them, so they stay put)
	if room then
		local folder = roomFolder(ctx, room)
		local hingeX = hingeSide * (w / 2 + 0.02)
		for _, y in { 1.0, h / 2 + 0.05, h - 0.6 } do
			local cf = frameCF * CFrame.new(hingeX, y + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90))
			if ctx.clear(cf, Vector3.new(0.62, t + 0.05, t + 0.05), 0.02) then
				decoCyl(folder, "Hinge", 0.62, t + 0.05, cf, metalName)
				count("Hinge")
			end
		end
		-- plinth blocks under the casings, both faces
		for _, s in { -1, 1 } do
			for _, face in { -1, 1 } do
				-- local +Z is against the passage: the room on that face is at -face
				local side = Layout.charAt(Layout.getFloor(rec.floor), rec.x - (if rec.passageDir.X ~= 0 then face else 0), rec.z - (if rec.passageDir.Z ~= 0 then face else 0))
				if Layout.isRoomChar(side) then
					local cf = frameCF * CFrame.new(s * (CELL / 2 + 0.1), 0.47, face * (CELL / 2 + 0.2))
					local size = Vector3.new(0.58, 0.9, 0.42)
					if ctx.clear(cf, size, 0.02) then
						deco(folder, "Plinth", size, cf, "agedWood", TRIM_COLOR:Lerp(Color3.new(), 0.08))
						count("Plinth")
					end
				end
			end
		end
	end

	-- reshape the box handles into levers on a rose, add an escutcheon and kick plates
	local handles = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Handle" then
			table.insert(handles, d)
		end
	end
	for _, handle in handles do
		local local0 = closed:ToObjectSpace(handle.CFrame)
		local face = if local0.Position.Z >= 0 then 1 else -1
		local hx, hy = local0.Position.X, local0.Position.Y
		local faceZ = face * t / 2
		-- rose: a disc on the face
		local rose = decoCyl(model, "Rose", 0.06, 0.38, closed * CFrame.new(hx, hy, faceZ + face * (0.03 + PROUD / 2)) * CFrame.Angles(0, math.rad(90), 0), metalName)
		attachToDoor(panel, rose)
		-- neck from the rose to the lever
		local neck = decoCyl(model, "Neck", 0.16, 0.11, closed * CFrame.new(hx, hy, faceZ + face * 0.14) * CFrame.Angles(0, math.rad(90), 0), metalName)
		attachToDoor(panel, neck)
		-- the lever itself points to the hinge side, ends rounded
		handle.Size = Vector3.new(0.56, 0.1, 0.12)
		handle.CFrame = closed * CFrame.new(hx + hingeSide * 0.24, hy, faceZ + face * 0.24)
		VisualStandards.apply(handle, metalName)
		attachToDoor(panel, handle)
		local tip = decoCyl(model, "LeverTip", 0.12, 0.14, closed * CFrame.new(hx + hingeSide * 0.52, hy, faceZ + face * 0.24) * CFrame.Angles(0, math.rad(90), 0), metalName)
		attachToDoor(panel, tip)
		-- escutcheon + keyhole under the lever
		local esc = deco(model, "Escutcheon", Vector3.new(0.2, 0.42, 0.03), closed * CFrame.new(hx, hy - 0.62, faceZ + face * (0.015 + PROUD)), metalName)
		attachToDoor(panel, esc)
		local key = deco(model, "Keyhole", Vector3.new(0.06, 0.16, 0.02), closed * CFrame.new(hx, hy - 0.6, faceZ + face * (0.035 + PROUD)), "rubber", Color3.fromRGB(8, 8, 8))
		attachToDoor(panel, key)
		-- kick plate along the bottom of this face
		local kick = deco(model, "KickPlate", Vector3.new(w - 0.34, 0.85, 0.03), closed * CFrame.new(0, -h / 2 + 0.52, faceZ + face * (0.015 + PROUD)), "hardware", Color3.fromRGB(132, 130, 124))
		attachToDoor(panel, kick)
		count("DoorHardwareSet")
	end
end

-- Switch beside the door, latch side, in every non-corridor room it opens into.
local function doorSwitches(ctx, rec)
	local model = rec.model
	if not (model and model:IsA("Model") and model:HasTag("Door")) or rec.char == "K" then
		return
	end
	local hingeSide = model:GetAttribute("HingeSide")
	if type(hingeSide) ~= "number" then
		return
	end
	local floor = Layout.getFloor(rec.floor)
	local frameCF = CFrame.lookAt(rec.center, rec.center + rec.passageDir)
	local latch = frameCF.RightVector * -hingeSide
	for _, side in { { rid = rec.roomA, sign = -1 }, { rid = rec.roomB, sign = 1 } } do
		local room = side.rid and ctx.map.Rooms[side.rid]
		if room and room.kind ~= "corridor" and room.kind ~= "stairs" and not NO_DETAIL[room.kind] then
			-- the wall next to the door on the latch side must be a plain wall cell
			local nx = rec.x + math.round(latch.X)
			local nz = rec.z + math.round(latch.Z)
			if Layout.charAt(floor, nx, nz) == "#" then
				local style = Layout.Styles[room.style]
				local lowerH = style.lower[3]
				local hgt = 4.4
				if lowerH > 1.5 and lowerH < 9 and math.abs(hgt - lowerH) < 0.75 then
					hgt = lowerH + 0.85
				end
				local normal = rec.passageDir * side.sign -- out of the wall, into this room (roomA lies at -passageDir)
				local plane = rec.center + rec.passageDir * side.sign * (CELL / 2)
				local base = plane + latch * (CELL / 2 + 0.8) + Vector3.new(0, hgt, 0)
				local plateCf = CFrame.lookAt(base + normal * (SKIN + PROUD + 0.025), base + normal * 10)
				local size = Vector3.new(0.46, 0.74, 0.05)
				if ctx.clear(plateCf, size + Vector3.new(0, 0, 0.2), 0.05) and claimWall(room, base, normal) then
					local folder = roomFolder(ctx, room)
					deco(folder, "SwitchPlate", size, plateCf, "plastic", Color3.fromRGB(196, 190, 172))
					deco(folder, "Switch", Vector3.new(0.12, 0.24, 0.09), plateCf * CFrame.new(0, 0, -0.06) * CFrame.Angles(math.rad(if ctx.rng:Chance(0.5) then 12 else -12), 0, 0), "plastic", Color3.fromRGB(210, 204, 188))
					count("Switch")
				end
			end
		end
	end
end

------------------------------------------------------------------------------------
-- walls
------------------------------------------------------------------------------------

-- Wall faces of a room grouped into straight runs of plain wall.
local function wallRuns(room)
	local floor = Layout.getFloor(room.floorId)
	local runs = {}
	for _, c in room.cells do
		for _, d in DIRS do
			local nx, nz = c.x + d.dx, c.z + d.dz
			if Layout.charAt(floor, nx, nz) == "#" and not capCell(room.floorId, nx, nz) then
				local plane = if d.dx ~= 0 then c.x + (if d.dx > 0 then 1 else 0) else c.z + (if d.dz > 0 then 1 else 0)
				local key = string.format("%d|%d|%d", d.dx, d.dz, plane)
				runs[key] = runs[key] or { d = d, plane = plane, along = {} }
				runs[key].along[if d.dx ~= 0 then c.z else c.x] = true
			end
		end
	end
	local segments = {}
	local keys = {}
	for k in runs do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		local run = runs[k]
		local idx = {}
		for a in run.along do
			table.insert(idx, a)
		end
		table.sort(idx)
		local cur = nil
		for _, a in idx do
			if cur and a == cur.last + 1 then
				cur.last = a
			else
				cur = { d = run.d, plane = run.plane, first = a, last = a }
				table.insert(segments, cur)
			end
		end
	end
	for _, seg in segments do
		local d = seg.d
		local normal = Vector3.new(-d.dx, 0, -d.dz)
		local mid = (seg.first + seg.last + 1) / 2 * CELL
		local planePos = seg.plane * CELL
		local base = if d.dx ~= 0 then Vector3.new(planePos, floor.y, mid) else Vector3.new(mid, floor.y, planePos)
		seg.base = Layout.Origin + base
		seg.normal = normal
		seg.length = (seg.last - seg.first + 1) * CELL
		-- X along the wall, LookVector into the room
		seg.cf = CFrame.lookAt(seg.base, seg.base + normal)
	end
	return segments
end

local function outlets(ctx, room, segments)
	if not OUTLET_KINDS[room.kind] then
		return
	end
	local placed = 0
	local budget = math.clamp(math.floor(#room.cells / 10), 1, 6)
	for _, seg in segments do
		if placed >= budget then
			break
		end
		if seg.length >= CELL * 2 then
			-- one outlet per 3 cells of wall, at a cell edge so it reads as wired
			for i = 1, math.floor(seg.length / (CELL * 3)) do
				if placed >= budget then
					break
				end
				local along = -seg.length / 2 + i * CELL * 3 - CELL * 1.5 + ctx.rng:Number(-0.8, 0.8)
				local base = seg.cf * CFrame.new(along, 1.15, 0)
				local cf = base * CFrame.new(0, 0, -(SKIN + PROUD + 0.025))
				local size = Vector3.new(0.42, 0.68, 0.05)
				if ctx.clear(cf, size + Vector3.new(0.1, 0.1, 0.3), 0.04) and claimWall(room, base.Position, seg.normal) then
					local folder = roomFolder(ctx, room)
					local plate = deco(folder, "OutletPlate", size, cf, "plastic", Color3.fromRGB(190, 184, 166))
					for _, y in { 0.15, -0.15 } do
						deco(folder, "Socket", Vector3.new(0.22, 0.2, 0.03), plate.CFrame * CFrame.new(0, y, -0.035), "plastic", Color3.fromRGB(150, 144, 128))
					end
					placed += 1
					count("Outlet")
				end
			end
		end
	end
end

local function conduit(ctx, room, segments)
	if not CONDUIT_STYLES[room.style] or room.kind == "stairs" or NO_DETAIL[room.kind] then
		return
	end
	-- the two longest walls carry the runs
	local list = table.clone(segments)
	table.sort(list, function(a, b)
		if a.length ~= b.length then
			return a.length > b.length
		end
		return a.base.X + a.base.Z * 0.001 < b.base.X + b.base.Z * 0.001
	end)
	local y = CH - 1.45
	local off = SKIN + PROUD + 0.1
	for i = 1, math.min(2, #list) do
		local seg = list[i]
		if seg.length >= CELL * 2 then
			local len = seg.length - 1.2
			local runCf = seg.cf * CFrame.new(0, y, -off)
			if ctx.clear(runCf, Vector3.new(len, 0.6, 0.4), 0.05) then
				local folder = roomFolder(ctx, room)
				decoCyl(folder, "Conduit", len, 0.18, runCf, "paintedMetal", Color3.fromRGB(110, 112, 108))
				-- a second, thinner run just below on long walls
				if seg.length >= CELL * 5 then
					decoCyl(folder, "Conduit", len, 0.12, runCf * CFrame.new(0, -0.32, 0), "paintedMetal", Color3.fromRGB(96, 98, 96))
				end
				for x = -len / 2 + 0.6, len / 2 - 0.4, 3 do
					deco(folder, "Clamp", Vector3.new(0.12, 0.34, 0.24), runCf * CFrame.new(x, 0, 0.04), "hardware")
				end
				for _, s in { -1, 1 } do
					deco(folder, "JunctionBox", Vector3.new(0.7, 0.7, 0.32), runCf * CFrame.new(s * (len / 2 + 0.05), 0, 0.02), "paintedMetal", Color3.fromRGB(88, 90, 88))
				end
				count("ConduitRun")
			end
		end
	end
end

------------------------------------------------------------------------------------
-- ceilings
------------------------------------------------------------------------------------

local function ceilingDetail(ctx, room)
	if room.kind == "stairs" or NO_DETAIL[room.kind] or room.noCeiling then
		return
	end
	local style = Layout.Styles[room.style]
	local floor = Layout.getFloor(room.floorId)
	local ceilY = floor.y + CH
	local suspended = style.light == "fluoro"
	local folder = roomFolder(ctx, room)
	local taken = {}
	for _, f in room.fixtures do
		table.insert(taken, f:GetPivot().Position)
	end
	local function free(pos: Vector3, dist: number): boolean
		for _, p in taken do
			if ((p - pos) * Vector3.new(1, 0, 1)).Magnitude < dist then
				return false
			end
		end
		return true
	end
	-- cell centres (= tile centres in the suspended ceiling), shuffled once
	local cells = {}
	for _, c in room.cells do
		table.insert(cells, Layout.cellToWorld(floor.y, c.x, c.z))
	end
	cells = ctx.rng:Shuffle(cells)
	local function under(pos: Vector3, drop: number): CFrame
		return CFrame.new(pos.X, ceilY - drop, pos.Z)
	end

	if suspended then
		-- air grilles: one per ~16 cells
		local vents = math.max(1, math.floor(#cells / 16))
		for _, pos in cells do
			if vents <= 0 then
				break
			end
			if free(pos, 6) then
				local cf = under(pos, 0)
				if ctx.clear(cf * CFrame.new(0, -0.15, 0), Vector3.new(3.5, 0.3, 3.5), 0.02) then
					deco(folder, "VentFrame", Vector3.new(3.3, 0.06, 3.3), cf * CFrame.new(0, -0.03 - PROUD, 0), "paintedMetal", Color3.fromRGB(176, 176, 170))
					deco(folder, "VentDark", Vector3.new(3.0, 0.02, 3.0), cf * CFrame.new(0, -0.02 - PROUD - 0.06, 0), "rubber", Color3.fromRGB(10, 10, 10))
					for k = -3, 3 do
						deco(folder, "VentSlat", Vector3.new(0.06, 0.2, 2.96), cf * CFrame.new(k * 0.4, -0.17 - PROUD, 0) * CFrame.Angles(0, 0, math.rad(35)), "paintedMetal", Color3.fromRGB(170, 170, 164))
					end
					table.insert(taken, pos)
					vents -= 1
					count("Vent")
				end
			end
		end
		-- sprinkler heads in a loose grid
		for _, c in room.cells do
			if (c.x + c.z * 2) % 5 == 0 then
				local pos = Layout.cellToWorld(floor.y, c.x, c.z) + Vector3.new(1, 0, -1)
				if free(pos, 2.2) and ctx.clear(under(pos, 0.2), Vector3.new(0.5, 0.4, 0.5), 0.05) then
					local cf = under(pos, 0)
					deco(folder, "SprinklerRose", Vector3.new(0.05, 0.42, 0.42), cf * CFrame.new(0, -0.025 - PROUD, 0) * CFrame.Angles(0, 0, math.rad(90)), "brass").Shape = Enum.PartType.Cylinder
					deco(folder, "SprinklerHead", Vector3.new(0.12, 0.3, 0.12), cf * CFrame.new(0, -0.22 - PROUD, 0), "brass")
					count("Sprinkler")
				end
			end
		end
		-- water damage: stained tiles, and sometimes a missing or hanging tile
		local stains = ctx.rng:Int(1, math.clamp(math.floor(#cells / 8), 1, 4))
		for _, pos in cells do
			if stains <= 0 then
				break
			end
			if free(pos, 2.6) and ctx.clear(under(pos, 0.05), Vector3.new(3.4, 0.1, 3.4), 0.02) then
				local cf = under(pos, 0)
				for k = 1, ctx.rng:Int(2, 3) do
					local dia = ctx.rng:Number(1.1, 2.4)
					local o = ctx.rng:Number(0, 1.5 - dia / 2)
					local a = ctx.rng:Number(0, math.pi * 2)
					local stain = deco(folder, "CeilingStain", Vector3.new(0.02, dia, dia * ctx.rng:Number(0.7, 1)), cf * CFrame.new(math.cos(a) * o, -PROUD - k * 0.016, math.sin(a) * o) * CFrame.Angles(0, ctx.rng:Number(0, math.pi), math.rad(90)), "grime", Color3.fromRGB(96, 76, 50))
					stain.Shape = Enum.PartType.Cylinder
					stain.Transparency = 0.62
				end
				table.insert(taken, pos)
				stains -= 1
				count("StainedTile")
			end
		end
		if ctx.rng:Chance(if room.kind == "corridor" then 0.6 else 0.25) then
			for _, pos in cells do
				if free(pos, 3.4) and ctx.clear(under(pos, 0.05), Vector3.new(3.9, 0.1, 3.9), 0.05) then
					local cf = under(pos, 0)
					-- the plenum above shows through as black
					deco(folder, "MissingTile", Vector3.new(3.84, 0.03, 3.84), cf * CFrame.new(0, -PROUD - 0.015, 0), "rubber", Color3.fromRGB(6, 6, 7))
					if ctx.rng:Chance(0.6) then
						-- the tile hangs from one edge
						local edge = cf * CFrame.new(-1.9, -0.05, 0)
						local tilt = math.rad(ctx.rng:Number(38, 62))
						if ctx.clear(edge * CFrame.Angles(0, 0, -tilt) * CFrame.new(1.85, 0, 0), Vector3.new(3.7, 0.12, 3.7), 0.1) then
							local tile = deco(folder, "HangingTile", Vector3.new(3.7, 0.12, 3.7), edge * CFrame.Angles(0, 0, -tilt) * CFrame.new(1.85, 0, 0), "plaster", style.ceiling[2])
							tile.MaterialVariant = "DLA_CeilingTile"
						end
					end
					table.insert(taken, pos)
					count("MissingTile")
					break
				end
			end
		end
	end
	-- a smoke detector in every room with a ceiling
	for _, pos in cells do
		local p = pos + Vector3.new(-1, 0, 1)
		if free(p, 2.4) and ctx.clear(under(p, 0.16), Vector3.new(0.85, 0.32, 0.85), 0.05) then
			local cf = under(p, 0)
			deco(folder, "SmokeDetector", Vector3.new(0.26, 0.8, 0.8), cf * CFrame.new(0, -0.13 - PROUD, 0) * CFrame.Angles(0, 0, math.rad(90)), "plastic", Color3.fromRGB(214, 210, 198)).Shape = Enum.PartType.Cylinder
			local led = deco(folder, "DetectorLED", Vector3.new(0.06, 0.03, 0.06), cf * CFrame.new(0.22, -0.275 - PROUD, 0), "plastic", Color3.fromRGB(255, 40, 30))
			led.Material = M.Neon
			table.insert(taken, p)
			count("SmokeDetector")
			break
		end
	end
end

------------------------------------------------------------------------------------
-- public
------------------------------------------------------------------------------------

function Architecture.dress(map, rng)
	table.clear(Architecture.Stats)
	local root = Instance.new("Folder")
	root.Name = "Detail"
	local ctx = {
		map = map,
		rng = rng,
		root = root,
		folders = {},
		clear = newClearance(map.Root:FindFirstChild("Furniture")),
	}
	for _, room in map.Rooms do
		room.wallSpotsBeforeDetail = #room.wallSpots
	end
	local doors = table.clone(map.Doors)
	table.sort(doors, function(a, b)
		return a.id < b.id
	end)
	for _, rec in doors do
		doorHardware(ctx, rec)
		doorSwitches(ctx, rec)
	end
	for _, room in sortedRooms(map) do
		if not NO_DETAIL[room.kind] then
			local segments = wallRuns(room)
			outlets(ctx, room, segments)
			conduit(ctx, room, segments)
			ceilingDetail(ctx, room)
		end
	end
	root.Parent = map.Root
	return root
end

return Architecture
