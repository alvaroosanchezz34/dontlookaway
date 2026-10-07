--[[
	GeometryValidator
	Development / admin tool that audits a built map for placement mistakes. It is
	pure geometry (oriented-box separating axis tests on part CFrames and sizes),
	so it runs identically in a live server (admin debug mode) and in the offline
	Lune test harness, where it gates every build.

	Checks
	  INTERSECT   a prop part penetrates a wall, floor, ceiling, door or window
	  FLOATING    a prop has nothing under it (and is not wall or ceiling mounted)
	  NO_SUPPORT  a prop touches nothing at all
	  WALKWAY     a solid prop blocks a reserved walkway cell (door approaches and
	              the paths between doors): blocked doors, too-narrow passages
	  DOORWAY     a solid prop stands inside a door cell
	  OVERLAP     two props interpenetrate (chairs through desks, stacked shelves)
	  BOUNDS      a prop sits outside every room
	  SPAWN       a prop crowds a spawn point
	  REPEAT      the same wall decoration twice side by side

	Severities (debug colours)
	  RED     intersections, blocked walkways/doorways, out of bounds
	  YELLOW  suspicious: overlaps, crowded spawns, repetition
	  BLUE    floating / unsupported
	  GREEN   everything else (correct)
]]

local GeometryValidator = {}

GeometryValidator.Colors = {
	RED = Color3.fromRGB(255, 60, 50),
	YELLOW = Color3.fromRGB(255, 210, 60),
	BLUE = Color3.fromRGB(70, 150, 255),
	GREEN = Color3.fromRGB(80, 220, 120),
}

local SEVERITY = {
	INTERSECT = "RED",
	WALKWAY = "RED",
	DOORWAY = "RED",
	BOUNDS = "RED",
	FLOATING = "BLUE",
	NO_SUPPORT = "BLUE",
	OVERLAP = "YELLOW",
	SPAWN = "YELLOW",
	REPEAT = "YELLOW",
}

local GRID = 8
local CELL = 4

-- Structure parts that are not physical surfaces.
local IGNORE_STRUCTURE = {
	Moon = true,
	MoonTarget = true,
	Rain = true,
	EscapeZone = true,
	Ramp = true, -- invisible stair ramp, props never go near stairs
	Boundary = true,
}

-- Props hung from the ceiling or mounted on walls by design.
local CEILING_PROPS = { Fixture = true, EmergencyBeacon = true, ExitSign = true, PipeRun = true, Curtain = true, MeatHook = true, Strips = true }
local WALL_TAGS = { "Painting", "Photo", "Clock", "Mirror", "Sign", "RoomNumber", "Window", "NoticeBoard" }
local WALL_NAMES = {
	HandDryer = true,
	FuseBox = true,
	BreakerPanel = true,
	Keypad = true,
	ClosetLamp = true,
	ExitPanel = true,
	NoticeBoard = true,
	Marking = true,
	RoomPlate = true,
	Radiator = true,
	FireExtinguisher = true,
	Sink = true,
	ValveWheel = true,
	Valve = true,
	Extinguisher = true,
	Elevator = true,
	SecurityOverride = true,
	EvidenceBoard = true,
	Photograph = true,
}
-- Pairs that overlap on purpose (someone sitting in a chair, a figure at a table).
local SITTERS = { Resident = true, Mannequin = true, PaleFigure = true }

------------------------------------------------------------------------------------
-- Oriented box math
------------------------------------------------------------------------------------

type Box = { c: Vector3, ax: { Vector3 }, h: Vector3, min: Vector3, max: Vector3, part: BasePart? }

local function boxFrom(cf: CFrame, size: Vector3, part: BasePart?): Box
	local h = size / 2
	local ax = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local ext = Vector3.new(
		math.abs(ax[1].X) * h.X + math.abs(ax[2].X) * h.Y + math.abs(ax[3].X) * h.Z,
		math.abs(ax[1].Y) * h.X + math.abs(ax[2].Y) * h.Y + math.abs(ax[3].Y) * h.Z,
		math.abs(ax[1].Z) * h.X + math.abs(ax[2].Z) * h.Y + math.abs(ax[3].Z) * h.Z
	)
	local c = cf.Position
	return { c = c, ax = ax, h = h, min = c - ext, max = c + ext, part = part }
end

local function grow(b: Box, m: number): Box
	local e = Vector3.new(m, m, m)
	return { c = b.c, ax = b.ax, h = b.h + e, min = b.min - e, max = b.max + e, part = b.part }
end

local function partBox(p: BasePart, exact: boolean?): Box
	local size = p.Size
	local ok, shape = pcall(function()
		return (p :: any).Shape
	end)
	if exact then
		return boxFrom(p.CFrame, size, p)
	end
	if ok and shape == Enum.PartType.Cylinder then
		-- the axis is local X; the round section is Y/Z
		size = Vector3.new(size.X, size.Y * 0.82, size.Z * 0.82)
	elseif ok and shape == Enum.PartType.Ball then
		size = size * 0.8
	end
	return boxFrom(p.CFrame, size, p)
end

local function aabbOverlap(a: Box, b: Box, margin: number): boolean
	return a.min.X - margin < b.max.X and a.max.X + margin > b.min.X and a.min.Y - margin < b.max.Y and a.max.Y + margin > b.min.Y and a.min.Z - margin < b.max.Z and a.max.Z + margin > b.min.Z
end

local function hx(b: Box, i: number): number
	return if i == 1 then b.h.X elseif i == 2 then b.h.Y else b.h.Z
end

-- Penetration depth between two oriented boxes (separating axis theorem).
-- > 0: they interpenetrate by that much along the easiest axis to separate them.
-- <= 0: separated (the magnitude is a lower bound of the gap).
local function penetration(a: Box, b: Box): number
	local d = b.c - a.c
	local best = math.huge
	local function test(L: Vector3)
		local len = L.Magnitude
		if len < 1e-6 then
			return
		end
		L = L / len
		local ra = 0
		local rb = 0
		for i = 1, 3 do
			ra += math.abs(a.ax[i]:Dot(L)) * hx(a, i)
			rb += math.abs(b.ax[i]:Dot(L)) * hx(b, i)
		end
		local overlap = ra + rb - math.abs(d:Dot(L))
		if overlap < best then
			best = overlap
		end
	end
	for i = 1, 3 do
		test(a.ax[i])
		test(b.ax[i])
	end
	for i = 1, 3 do
		for j = 1, 3 do
			test(a.ax[i]:Cross(b.ax[j]))
		end
	end
	return best
end

GeometryValidator.penetration = penetration
GeometryValidator.boxFrom = boxFrom

------------------------------------------------------------------------------------
-- Spatial hash
------------------------------------------------------------------------------------

local Hash = {}
Hash.__index = Hash

local function newHash()
	return setmetatable({ cells = {} }, Hash)
end

local function hkey(x: number, y: number, z: number): number
	return (x + 512) * 1048576 + (y + 64) * 1024 + (z + 512)
end

function Hash:insert(box: Box)
	for x = math.floor(box.min.X / GRID), math.floor(box.max.X / GRID) do
		for y = math.floor(box.min.Y / GRID), math.floor(box.max.Y / GRID) do
			for z = math.floor(box.min.Z / GRID), math.floor(box.max.Z / GRID) do
				local k = hkey(x, y, z)
				local list = self.cells[k]
				if not list then
					list = {}
					self.cells[k] = list
				end
				table.insert(list, box)
			end
		end
	end
end

function Hash:query(box: Box, margin: number): { Box }
	local out = {}
	local seen = {}
	for x = math.floor((box.min.X - margin) / GRID), math.floor((box.max.X + margin) / GRID) do
		for y = math.floor((box.min.Y - margin) / GRID), math.floor((box.max.Y + margin) / GRID) do
			for z = math.floor((box.min.Z - margin) / GRID), math.floor((box.max.Z + margin) / GRID) do
				local list = self.cells[hkey(x, y, z)]
				if list then
					for _, b in list do
						if not seen[b] then
							seen[b] = true
							if aabbOverlap(box, b, margin) then
								table.insert(out, b)
							end
						end
					end
				end
			end
		end
	end
	return out
end

------------------------------------------------------------------------------------
-- Collection
------------------------------------------------------------------------------------

local function relevant(p: BasePart): boolean
	if p.Transparency >= 0.99 and not p.CanCollide then
		return false
	end
	local s = p.Size
	return s.X > 0.02 and s.Y > 0.02 and s.Z > 0.02
end

local function hasAnyTag(inst: Instance, tags: { string }): boolean
	for _, t in tags do
		if inst:HasTag(t) then
			return true
		end
	end
	return false
end

local function mountOf(model: Instance): string
	if CEILING_PROPS[model.Name] then
		return "ceiling"
	end
	if WALL_NAMES[model.Name] or hasAnyTag(model, WALL_TAGS) then
		return "wall"
	end
	return "floor"
end

type Prop = { inst: Instance, name: string, room: string?, boxes: { Box }, solid: { Box }, min: Vector3, max: Vector3, mount: string, collides: boolean }

local function makeProp(inst: Instance, room: string?): Prop?
	local parts = {}
	if inst:IsA("BasePart") then
		parts = { inst }
	else
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	local boxes, solid = {}, {}
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local collides = false
	for _, p in parts do
		if relevant(p) then
			-- exact boxes decide contact and support; rounded parts are slimmed for penetration
			local b = partBox(p, true)
			table.insert(boxes, b)
			if p.Transparency < 0.95 then
				local sb = partBox(p)
				sb.owner = nil
				table.insert(solid, sb)
			end
			if p.CanCollide then
				collides = true
			end
			minV = minV:Min(b.min)
			maxV = maxV:Max(b.max)
		end
	end
	if #boxes == 0 then
		return nil
	end
	local attrRoom = inst:GetAttribute("Room")
	return {
		inst = inst,
		name = inst.Name,
		room = if type(attrRoom) == "string" then attrRoom else room,
		boxes = boxes,
		solid = solid,
		min = minV,
		max = maxV,
		mount = mountOf(inst),
		collides = collides,
	}
end

------------------------------------------------------------------------------------
-- Run
------------------------------------------------------------------------------------

--[[
	Audits `map` (as returned by MapBuilder.build). Returns
	{ issues = { { severity, kind, inst, name, room, detail, position } },
	  props = { inst }, counts = { [kind] = n }, worst = { [inst] = severity } }
]]
function GeometryValidator.run(map, opts: { extra: { Instance }? }?): any
	local root = map.Root
	local structure = newHash()
	local structureCount = 0
	for _, folderName in { "Structure", "Extras" } do
		local folder = root:FindFirstChild(folderName)
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") and relevant(d) and not IGNORE_STRUCTURE[d.Name] and d.Transparency < 0.99 then
					local model = d:FindFirstAncestorWhichIsA("Model")
					-- light fixtures and windows are dressing, not surfaces
					if not (model and (model.Name == "Fixture" or model:HasTag("Window"))) then
						structure:insert(partBox(d))
						structureCount += 1
					end
				end
			end
		end
	end

	-- props: models (and loose parts) inside the furniture folders
	local props: { Prop } = {}
	local furniture = root:FindFirstChild("Furniture")
	local function collect(folder: Instance, room: string?)
		for _, child in folder:GetChildren() do
			if child:IsA("Folder") then
				collect(child, child.Name)
			elseif child:IsA("Model") or child:IsA("BasePart") then
				local prop = makeProp(child, room)
				if prop then
					table.insert(props, prop)
				end
			end
		end
	end
	if furniture then
		collect(furniture, nil)
	end
	-- extra folders (world pickups, documents) are audited like furniture
	for _, folder in (opts and opts.extra) or {} do
		collect(folder, nil)
	end
	local propHash = newHash()
	for _, prop in props do
		for _, b in prop.boxes do
			b.owner = prop
			propHash:insert(b)
		end
		for _, b in prop.solid do
			b.owner = prop
		end
	end

	local issues = {}
	local counts = {}
	local worst: { [Instance]: string } = {}
	local rank = { GREEN = 0, YELLOW = 1, BLUE = 2, RED = 3 }
	local function report(prop: Prop, kind: string, detail: string, position: Vector3?)
		local severity = SEVERITY[kind]
		counts[kind] = (counts[kind] or 0) + 1
		table.insert(issues, {
			severity = severity,
			kind = kind,
			inst = prop.inst,
			name = prop.name,
			room = prop.room,
			detail = detail,
			position = position or (prop.min + prop.max) / 2,
		})
		local cur = worst[prop.inst]
		if not cur or rank[severity] > rank[cur] then
			worst[prop.inst] = severity
		end
	end

	-- 1. intersections with the building
	for _, prop in props do
		local deepest, deepestName, deepestPart, deepestAt = 0, "", "", Vector3.zero
		local tol = if prop.mount == "wall" then 0.16 elseif prop.mount == "ceiling" then 0.3 else 0.12
		for _, b in prop.solid do
			for _, s in structure:query(b, 0) do
				local pen = penetration(b, s)
				if pen > deepest then
					deepest = pen
					deepestName = if s.part then s.part.Name else "?"
					deepestPart = if b.part then b.part.Name else "?"
					deepestAt = s.c
				end
			end
		end
		if deepest > tol then
			report(prop, "INTERSECT", string.format("%s into %s by %.2f (%s @ %.1f,%.1f,%.1f)", deepestPart, deepestName, deepest, deepestName, deepestAt.X, deepestAt.Y, deepestAt.Z))
		end
	end

	-- 2. support
	local function supportedBelow(prop: Prop): (boolean, number)
		-- distance from the prop's lowest point down to the nearest surface under its centre
		local centre = (prop.min + prop.max) / 2
		local probe = boxFrom(CFrame.new(centre.X, prop.min.Y - 1.6, centre.Z), Vector3.new(math.max(0.6, (prop.max.X - prop.min.X) * 0.6), 3.2, math.max(0.6, (prop.max.Z - prop.min.Z) * 0.6)))
		local bestGap = math.huge
		local function consider(s: Box)
			if s.owner == prop then
				return
			end
			local top = s.max.Y
			if top <= prop.min.Y + 0.15 then
				-- the surface must actually be under the footprint
				local gap = prop.min.Y - top
				if gap < bestGap and penetration(probe, s) > 0 then
					bestGap = gap
				end
			end
		end
		for _, s in structure:query(probe, 0) do
			consider(s)
		end
		for _, s in propHash:query(probe, 0) do
			consider(s)
		end
		return bestGap <= 0.2, bestGap
	end
	local function touchesAnything(prop: Prop, margin: number): boolean
		for _, b in prop.boxes do
			local grown = grow(b, margin)
			for _, s in structure:query(grown, 0) do
				if penetration(grown, s) > 0 then
					return true
				end
			end
			for _, s in propHash:query(grown, 0) do
				if s.owner ~= prop and penetration(grown, s) > 0 then
					return true
				end
			end
		end
		return false
	end
	for _, prop in props do
		if prop.mount == "floor" then
			local ok, gap = supportedBelow(prop)
			if not ok then
				if gap < 6 then
					report(prop, "FLOATING", string.format("%.2f above the surface below", gap))
				elseif not touchesAnything(prop, 0.2) then
					report(prop, "NO_SUPPORT", "touches nothing")
				end
			end
		elseif not touchesAnything(prop, 0.3) then
			report(prop, "NO_SUPPORT", "not attached to a " .. prop.mount)
		end
	end

	-- 3. walkways and doorways stay clear of solid props
	local function cellBox(floorY: number, x: number, z: number, inset: number): Box
		local origin = map.LayoutOrigin or Vector3.zero
		local c = origin + Vector3.new(x * CELL + CELL / 2, floorY + 3.4, z * CELL + CELL / 2)
		return boxFrom(CFrame.new(c), Vector3.new(CELL - inset * 2, 5.6, CELL - inset * 2))
	end
	for _, room in map.Rooms do
		for _, c in room.circulation or {} do
			local box = cellBox(room.floorY, c.x, c.z, 0.7)
			for _, s in propHash:query(box, 0) do
				local prop = s.owner
				if prop.collides and prop.mount == "floor" and s.part and s.part.CanCollide and penetration(box, s) > 0.05 then
					report(prop, "WALKWAY", string.format("blocks walkway cell %d,%d in %s", c.x, c.z, room.id))
					break
				end
			end
		end
	end
	for _, door in map.Doors do
		local floorY = 0
		local rA = door.roomA and map.Rooms[door.roomA]
		local rB = door.roomB and map.Rooms[door.roomB]
		floorY = (rA or rB or { floorY = door.center.Y }).floorY
		local box = cellBox(floorY, door.x, door.z, 0.3)
		for _, s in propHash:query(box, 0) do
			local prop = s.owner
			if prop.mount == "floor" and s.part and s.part.CanCollide and penetration(box, s) > 0.05 then
				report(prop, "DOORWAY", "inside door " .. door.id)
			end
		end
	end

	-- 4. props interpenetrating each other
	for _, prop in props do
		if prop.mount == "floor" and #prop.solid > 0 then
			local hitBy = nil
			local deepest = 0
			local pair = ""
			for _, b in prop.solid do
				for _, s in propHash:query(b, 0) do
					local other = s.owner
					if other ~= prop and other.mount == "floor" and not (SITTERS[prop.name] or SITTERS[other.name]) and s.part and s.part.Transparency < 0.95 then
						local pen = penetration(b, s)
						if pen > deepest then
							deepest = pen
							hitBy = other
							pair = (if b.part then b.part.Name else "?") .. "/" .. s.part.Name
						end
					end
				end
			end
			-- report each pair once
			if hitBy and deepest > 0.25 and tostring(prop.inst) .. tostring(prop.min) < tostring(hitBy.inst) .. tostring(hitBy.min) then
				report(prop, "OVERLAP", string.format("overlaps %s by %.2f (%s)", hitBy.name, deepest, pair))
			end
		end
	end

	-- 5. bounds
	local roomBoxes = {}
	for _, room in map.Rooms do
		if room.min and room.max then
			table.insert(roomBoxes, { min = room.min - Vector3.new(0.8, 1, 0.8), max = room.max + Vector3.new(0.8, 2, 0.8) })
		end
	end
	for _, door in map.Doors do
		local c = door.center
		table.insert(roomBoxes, { min = c - Vector3.new(CELL / 2, 1, CELL / 2), max = c + Vector3.new(CELL / 2, 14, CELL / 2) })
	end
	for _, prop in props do
		local c = (prop.min + prop.max) / 2
		local inside = false
		for _, rb in roomBoxes do
			if c.X >= rb.min.X and c.X <= rb.max.X and c.Y >= rb.min.Y and c.Y <= rb.max.Y and c.Z >= rb.min.Z and c.Z <= rb.max.Z then
				inside = true
				break
			end
		end
		if not inside then
			report(prop, "BOUNDS", "outside every room")
		end
	end

	-- 6. spawns
	local spawns = {}
	for _, cf in map.CourtyardSpawns or {} do
		table.insert(spawns, cf.Position)
	end
	local vestibule = map.Rooms and map.Rooms.G_e
	if vestibule then
		table.insert(spawns, vestibule.center + Vector3.new(0, 3, 0))
	end
	for _, prop in props do
		if prop.collides and prop.mount == "floor" then
			for _, sp in spawns do
				local flat = Vector3.new(math.clamp(sp.X, prop.min.X, prop.max.X), 0, math.clamp(sp.Z, prop.min.Z, prop.max.Z))
				if (Vector3.new(sp.X, 0, sp.Z) - flat).Magnitude < 2.5 and math.abs(sp.Y - 3 - prop.min.Y) < 4 then
					report(prop, "SPAWN", "crowds a spawn point")
					break
				end
			end
		end
	end

	-- 7. repeated wall decoration side by side
	local decor = {}
	for _, prop in props do
		if prop.mount == "wall" and prop.name ~= "RoomPlate" then
			table.insert(decor, prop)
		end
	end
	for i, a in decor do
		for j = i + 1, #decor do
			local b = decor[j]
			local sameWall = false
			local okA, pa = pcall(function()
				return (a.inst :: any):GetPivot()
			end)
			local okB, pb = pcall(function()
				return (b.inst :: any):GetPivot()
			end)
			if okA and okB then
				sameWall = pa.LookVector:Dot(pb.LookVector) > 0.9
			end
			if sameWall and a.name == b.name and ((a.min + a.max) / 2 - (b.min + b.max) / 2).Magnitude < 3 then
				report(b, "REPEAT", "same " .. a.name .. " right next to another")
			end
		end
	end

	local propList = {}
	for _, prop in props do
		table.insert(propList, prop.inst)
	end
	return { issues = issues, counts = counts, worst = worst, props = propList, structureCount = structureCount }
end

------------------------------------------------------------------------------------
-- Debug visualisation (admin only)
------------------------------------------------------------------------------------

-- Outlines every prop in its severity colour. Returns the folder holding the adorns.
function GeometryValidator.visualize(report, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "GeometryDebug"
	for _, inst in report.props do
		if inst.Parent then
			local severity = report.worst[inst] or "GREEN"
			local box = Instance.new("SelectionBox")
			box.Adornee = inst
			box.Color3 = GeometryValidator.Colors[severity]
			box.LineThickness = if severity == "GREEN" then 0.02 else 0.06
			box.SurfaceColor3 = GeometryValidator.Colors[severity]
			box.SurfaceTransparency = if severity == "GREEN" then 1 else 0.75
			box.Parent = folder
		end
	end
	folder.Parent = parent
	return folder
end

function GeometryValidator.summary(report): string
	local parts = {}
	for kind, n in report.counts do
		table.insert(parts, kind .. "=" .. n)
	end
	table.sort(parts)
	return string.format("%d props, %d issues%s", #report.props, #report.issues, if #parts > 0 then " (" .. table.concat(parts, ", ") .. ")" else "")
end

return GeometryValidator
