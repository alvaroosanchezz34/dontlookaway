--[[
	Furnisher
	Dresses every room according to its kind. Placement is grid based:
	  * door approaches and the shortest paths between doors are reserved, so
	    furniture can never block navigation (no impossible layouts);
	  * wall-backed furniture uses wall slots facing into the room;
	  * decor (paintings, clocks, photos, signs) uses wall faces at eye height.
	Each room also gets ambient dust, wear (stains, papers) and item spots used by
	the objective system for randomized item placement.
]]

local Layout = require(script.Parent.Layout)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local CELL = Layout.Cell
local CH = Layout.CeilingHeight
local M = Enum.Material

-- gap between wall-backed furniture and the wall finish: clears baseboards (0.15
-- proud of the wall) and dado rails (0.12 proud)
local WALL_GAP = 0.22
-- usable width of wall decor on a single cell: keeps clear of corner finishes
-- and door casings in the neighbouring cells
local DECOR_SINGLE = CELL - 1.2
local DECOR_DOUBLE = CELL * 2 - 1.2

local DIRS = {
	{ dx = 1, dz = 0 },
	{ dx = -1, dz = 0 },
	{ dx = 0, dz = 1 },
	{ dx = 0, dz = -1 },
}

local Furnisher = {}

------------------------------------------------------------------------------------
-- Room context
------------------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

local function key(x, z)
	return z * 10000 + x
end

local function newCtx(map, room, folder, rng)
	local floor = Layout.getFloor(room.floorId)
	local self = setmetatable({
		map = map,
		room = room,
		floor = floor,
		y = floor.y,
		folder = folder,
		rng = rng,
		reserved = {},
		used = {},
		decorUsed = {},
		tallWall = {},
		wallTop = {}, -- top of furniture standing against each wall slot (for decor above it)
		railY = nil,
	}, Ctx)
	local style = Layout.Styles[room.style]
	local lowerH = style and style.lower[3]
	if lowerH and lowerH > 1.5 and lowerH < 9 then
		self.railY = lowerH
	end
	self:reserveCirculation()
	return self
end

function Ctx:cellPos(x: number, z: number): Vector3
	return Layout.cellToWorld(self.y, x, z)
end

function Ctx:inRoom(x: number, z: number): boolean
	return self.room.cellSet[key(x, z)] == true
end

function Ctx:isFree(x: number, z: number): boolean
	local k = key(x, z)
	return self:inRoom(x, z) and not self.reserved[k] and not self.used[k]
end

function Ctx:use(x: number, z: number)
	self.used[key(x, z)] = true
end

function Ctx:reserveCirculation()
	local room = self.room
	local steps = {}
	for _, door in room.doors do
		for _, d in DIRS do
			local nx, nz = door.x + d.dx, door.z + d.dz
			if self:inRoom(nx, nz) then
				table.insert(steps, { x = nx, z = nz })
				self.reserved[key(nx, nz)] = true
				-- keep the cells beside the door step clear too
				for _, d2 in DIRS do
					if self:inRoom(nx + d2.dx, nz + d2.dz) and (d2.dx ~= d.dx or d2.dz ~= d.dz) then
						self.reserved[key(nx + d2.dx, nz + d2.dz)] = true
					end
				end
			end
		end
	end
	-- archway cells ('O') count as door steps for the reception
	for _, c in room.cells do
		local ch = Layout.charAt(self.floor, c.x, c.z - 1)
		if ch == "O" then
			self.reserved[key(c.x, c.z)] = true
			table.insert(steps, { x = c.x, z = c.z })
		end
	end
	-- keep the room's centre reachable from its first door
	local cx = math.floor((room.minX + room.maxX) / 2)
	local cz = math.floor((room.minZ + room.maxZ) / 2)
	if self:inRoom(cx, cz) then
		table.insert(steps, { x = cx, z = cz })
	end
	-- reserve shortest paths between every pair of steps (BFS on room cells)
	local function bfs(a, b)
		local prev = {}
		local queue = { a }
		local seen = { [key(a.x, a.z)] = true }
		local head = 1
		while head <= #queue do
			local cur = queue[head]
			head += 1
			if cur.x == b.x and cur.z == b.z then
				break
			end
			for _, d in DIRS do
				local nx, nz = cur.x + d.dx, cur.z + d.dz
				local k = key(nx, nz)
				if self:inRoom(nx, nz) and not seen[k] then
					seen[k] = true
					prev[k] = cur
					table.insert(queue, { x = nx, z = nz })
				end
			end
		end
		local node = b
		local guard = 0
		while node and guard < 400 do
			self.reserved[key(node.x, node.z)] = true
			node = prev[key(node.x, node.z)]
			guard += 1
		end
	end
	for i = 1, #steps do
		for j = i + 1, #steps do
			bfs(steps[i], steps[j])
		end
	end
	-- the shrinking office keeps its east strip empty
	if room.shrink then
		for _, c in room.cells do
			if c.x >= 7 then
				self.reserved[key(c.x, c.z)] = true
				self.decorUsed[key(c.x, c.z) .. "|1|0"] = true
			end
		end
	end
end

-- Wall slots: free room cells touching a plain wall. dir points toward the wall.
function Ctx:wallSlots(allowReserved: boolean?)
	local slots = {}
	for _, c in self.room.cells do
		if allowReserved or self:isFree(c.x, c.z) then
			for _, d in DIRS do
				local ch = Layout.charAt(self.floor, c.x + d.dx, c.z + d.dz)
				if ch == "#" then
					local center = self:cellPos(c.x, c.z)
					local dir = Vector3.new(d.dx, 0, d.dz)
					local face = center + dir * (CELL / 2 - 0.2)
					table.insert(slots, { x = c.x, z = c.z, dx = d.dx, dz = d.dz, dir = dir, face = face })
				end
			end
		end
	end
	return slots
end

-- Unit vector along the slot's wall, always pointing to increasing grid x/z.
-- (Wide props occupy the slot and the next cell in this direction.)
local function alongOf(slot): Vector3
	return Vector3.new(math.abs(slot.dz), 0, math.abs(slot.dx))
end

-- CFrame for a floor prop of the given depth backed against the slot's wall.
function Ctx:backedCF(slot, depth: number, offsetAlong: number?): CFrame
	local pos = slot.face - slot.dir * (depth / 2 + WALL_GAP) + alongOf(slot) * (offsetAlong or 0)
	return CFrame.lookAt(pos, pos - slot.dir)
end

-- CFrame on the wall face at height h (for decor).
function Ctx:wallCF(slot, h: number, offsetAlong: number?): CFrame
	local pos = slot.face + Vector3.new(0, h, 0) + alongOf(slot) * (offsetAlong or 0)
	return CFrame.lookAt(pos, pos - slot.dir)
end

local function slotKey(x: number, z: number, dx: number, dz: number): string
	return key(x, z) .. "|" .. dx .. "|" .. dz
end

-- Is the cell next to `slot` (step -1 or +1 along the wall) the same plain wall,
-- free for decoration?
function Ctx:decorNeighbourFree(slot, step: number, allowReserved: boolean?): boolean
	local a = alongOf(slot)
	local nx, nz = slot.x + a.X * step, slot.z + a.Z * step
	if not self:inRoom(nx, nz) then
		return false
	end
	if Layout.charAt(self.floor, nx + slot.dx, nz + slot.dz) ~= "#" then
		return false
	end
	if self.decorUsed[slotKey(nx, nz, slot.dx, slot.dz)] then
		return false
	end
	if allowReserved == false and self.reserved[key(nx, nz)] then
		return false
	end
	return true
end

-- Picks a centre height for a wall item of height h near `want`, never crossing the
-- dado rail and never sitting on top of furniture against that wall.
function Ctx:decorHeight(want: number, h: number, minBottom: number?): number?
	local top = CH - 0.45
	local floorMin = math.max(0.8, (minBottom or 0) + 0.3)
	local rail = self.railY
	if rail then
		local aboveLo = math.max(rail + 0.3, floorMin)
		local belowLo, belowHi = floorMin, rail - 0.25
		local preferBelow = want < rail and belowHi - belowLo >= h
		if preferBelow then
			return math.clamp(want, belowLo + h / 2, belowHi - h / 2)
		end
		if top - aboveLo >= h then
			return math.clamp(want, aboveLo + h / 2, top - h / 2)
		end
		return nil
	end
	if top - floorMin < h then
		return nil
	end
	return math.clamp(want, floorMin + h / 2, top - h / 2)
end

-- Finds a slot plus its neighbour along the same wall (for 2-cell wide props).
function Ctx:pairSlot(slot)
	local ax, az = math.abs(slot.dz), math.abs(slot.dx)
	local nx, nz = slot.x + ax, slot.z + az
	if not self:isFree(nx, nz) then
		return nil
	end
	local ch = Layout.charAt(self.floor, nx + slot.dx, nz + slot.dz)
	if ch ~= "#" then
		return nil
	end
	return { x = nx, z = nz }
end

--[[
	Furniture backed against a wall.
	depth      physical depth of the prop (it stands WALL_GAP off the wall)
	wide       spans the slot cell and the next cell along the wall (props up to 7.2 wide)
	clearance  extra free depth kept in front of it (a chair, a door that opens)
	tall       covers the wall above it (no decor there)
]]
function Ctx:placeAgainstWall(builder, depth: number, wide: boolean?, count: number?, filter: ((any) -> boolean)?, tall: boolean?, clearance: number?)
	local placed = {}
	local slots = self.rng:Shuffle(self:wallSlots())
	local deepCells = math.max(0, math.ceil((depth + WALL_GAP + (clearance or 0)) / CELL) - 1)
	for _, slot in slots do
		if #placed >= (count or 1) then
			break
		end
		local columns = { { x = slot.x, z = slot.z } }
		if wide then
			local other = self:pairSlot(slot)
			if other then
				table.insert(columns, other)
			else
				columns = nil
			end
		end
		local ok = columns ~= nil and self:isFree(slot.x, slot.z) and (not filter or filter(slot))
		if ok then
			for _, col in columns do
				for k = 0, deepCells do
					if not self:isFree(col.x - slot.dx * k, col.z - slot.dz * k) then
						ok = false
					end
				end
			end
		end
		if ok then
			for _, col in columns do
				for k = 0, deepCells do
					self:use(col.x - slot.dx * k, col.z - slot.dz * k)
				end
			end
			local cf = if wide then self:backedCF(slot, depth, CELL / 2) else self:backedCF(slot, depth)
			local m = builder(self.folder, cf, self.rng)
			table.insert(placed, m)
			table.insert(self.room.props, m)
			-- remember how tall the furniture is, so decor goes above it
			local okBox, bcf, bsize = pcall(function()
				return m:GetBoundingBox()
			end)
			for _, col in columns do
				local k = slotKey(col.x, col.z, slot.dx, slot.dz)
				if okBox and bcf then
					self.wallTop[k] = math.max(self.wallTop[k] or 0, bcf.Position.Y + bsize.Y / 2 - self.y)
				end
				if tall then
					self.decorUsed[k] = true
				end
			end
		end
	end
	return placed
end

function Ctx:areaFree(x0: number, z0: number, x1: number, z1: number): boolean
	for x = x0, x1 do
		for z = z0, z1 do
			if not self:isFree(x, z) then
				return false
			end
		end
	end
	return true
end

function Ctx:useArea(x0: number, z0: number, x1: number, z1: number)
	for x = x0, x1 do
		for z = z0, z1 do
			self:use(x, z)
		end
	end
end

function Ctx:interiorCells()
	local list = {}
	for _, c in self.room.cells do
		if self:isFree(c.x, c.z) then
			local nearWall = false
			for _, d in DIRS do
				if not self:inRoom(c.x + d.dx, c.z + d.dz) then
					nearWall = true
				end
			end
			if not nearWall then
				table.insert(list, c)
			end
		end
	end
	return self.rng:Shuffle(list)
end

function Ctx:freeCells()
	local list = {}
	for _, c in self.room.cells do
		if self:isFree(c.x, c.z) then
			table.insert(list, c)
		end
	end
	return self.rng:Shuffle(list)
end

--[[
	Free-standing furniture in the room's interior.
	footprint: Vector2(width, depth) of everything placed (a table and its chairs);
	every cell under it must be free, so nothing spills into walkways or walls.
	The prop is rotated in quarter turns (with a few degrees of life).
]]
function Ctx:placeCenter(builder, count: number, yaw: number?, footprint: Vector2?)
	local placed = {}
	local fp = footprint or Vector2.new(CELL - 0.8, CELL - 0.8)
	for _, c in self:interiorCells() do
		if #placed >= count then
			break
		end
		local quarter = if yaw then math.floor((yaw % 360) / 90 + 0.5) % 4 else self.rng:Int(0, 3)
		local w, d = fp.X, fp.Y
		if quarter % 2 == 1 then
			w, d = d, w
		end
		local rx = math.max(0, math.ceil((w / 2 - CELL / 2 + 0.05) / CELL))
		local rz = math.max(0, math.ceil((d / 2 - CELL / 2 + 0.05) / CELL))
		if self:areaFree(c.x - rx, c.z - rz, c.x + rx, c.z + rz) then
			self:useArea(c.x - rx, c.z - rz, c.x + rx, c.z + rz)
			local pos = self:cellPos(c.x, c.z)
			local angle = if yaw then yaw else quarter * 90 + self.rng:Number(-5, 5)
			local m = builder(self.folder, CFrame.new(pos) * CFrame.Angles(0, math.rad(angle), 0), self.rng)
			table.insert(placed, m)
			table.insert(self.room.props, m)
		end
	end
	return placed
end

--[[
	A clean stretch of wall for a fixed fitting (fuse box, breaker panel, switch)
	of the given size, centred near height `want`. The floor in front of it is kept
	free so it can always be reached. Optional `order` sorts candidate slots.
	Returns { slot, offset, y } or nil.
]]
function Ctx:findWallSpot(width: number, height: number, want: number?, order: ((any, any) -> boolean)?)
	local slots = self:wallSlots()
	if order then
		table.sort(slots, order)
	else
		self.rng:Shuffle(slots)
	end
	for _, slot in slots do
		local k = slotKey(slot.x, slot.z, slot.dx, slot.dz)
		if self:isFree(slot.x, slot.z) and not self.decorUsed[k] then
			local offset, other = 0, nil
			local ok = true
			if width > DECOR_SINGLE then
				if self:decorNeighbourFree(slot, 1, false) then
					offset, other = CELL / 2, 1
				elseif self:decorNeighbourFree(slot, -1, false) then
					offset, other = -CELL / 2, -1
				else
					ok = false
				end
				if width > DECOR_DOUBLE then
					ok = false
				end
			end
			local y = if ok then self:decorHeight(want or 5, height, self.wallTop[k]) else nil
			if y then
				self:use(slot.x, slot.z)
				self.decorUsed[k] = true
				if other then
					local a = alongOf(slot)
					self.decorUsed[slotKey(slot.x + a.X * other, slot.z + a.Z * other, slot.dx, slot.dz)] = true
				end
				return { slot = slot, offset = offset, y = y }
			end
		end
	end
	return nil
end

--[[
	Wall decor at eye height on slots not covered by tall furniture.
	size: Vector2(width, height) of a fixed-size item. Without it the builder is
	"flexible" and receives (folder, cf, rng, maxWidth, maxHeight) so it can size
	itself to the wall it gets (paintings).
	Items wider than one cell take the neighbouring wall cell too; nothing ever
	crosses a corner, a door casing, the dado rail or furniture below.
]]
function Ctx:decor(builder, count: number, height: number?, allowReserved: boolean?, size: Vector2?)
	local placed = {}
	local slots = self.rng:Shuffle(self:wallSlots(true))
	local want = height or 6.5
	for _, slot in slots do
		if #placed >= count then
			break
		end
		local k = slotKey(slot.x, slot.z, slot.dx, slot.dz)
		local isReserved = self.reserved[key(slot.x, slot.z)]
		if not self.decorUsed[k] and (allowReserved ~= false or not isReserved) then
			local width = if size then size.X else nil
			local plus = self:decorNeighbourFree(slot, 1, allowReserved)
			local minus = self:decorNeighbourFree(slot, -1, allowReserved)
			-- flexible items take two cells when the wall allows it (and sometimes don't)
			local double = false
			if width then
				double = width > DECOR_SINGLE
			else
				double = (plus or minus) and self.rng:Chance(0.6)
			end
			local offset, other = 0, nil
			local fits = true
			if double then
				if plus then
					offset, other = CELL / 2, 1
				elseif minus then
					offset, other = -CELL / 2, -1
				elseif width then
					fits = false
				else
					double = false
				end
			end
			local maxW = if double then DECOR_DOUBLE else DECOR_SINGLE
			if width and width > maxW then
				fits = false
			end
			if fits then
				local a = alongOf(slot)
				local below = self.wallTop[k] or 0
				if other then
					below = math.max(below, self.wallTop[slotKey(slot.x + a.X * other, slot.z + a.Z * other, slot.dx, slot.dz)] or 0)
				end
				local h = if size then size.Y else nil
				local maxH = nil
				if not h then
					-- flexible: as tall as the band above the rail allows (up to 4.4)
					local lo = math.max(0.8, below + 0.3, if self.railY then self.railY + 0.3 else 0)
					maxH = math.min(4.4, CH - 0.45 - lo)
					h = math.min(maxW * 0.8, maxH)
				end
				local centreY = if h and h > 0 then self:decorHeight(want, h, below) else nil
				if centreY then
					self.decorUsed[k] = true
					if other then
						self.decorUsed[slotKey(slot.x + a.X * other, slot.z + a.Z * other, slot.dx, slot.dz)] = true
					end
					local cf = self:wallCF(slot, centreY, offset)
					local m = if size then builder(self.folder, cf, self.rng) else builder(self.folder, cf, self.rng, maxW, maxH or h)
					table.insert(placed, m)
					table.insert(self.room.props, m)
				end
			end
		end
	end
	return placed
end

function Ctx:scatter(kind: string, count: number)
	for _, c in self:freeCells() do
		if count <= 0 then
			break
		end
		local pos = self:cellPos(c.x, c.z) + Vector3.new(self.rng:Number(-1, 1), 0, self.rng:Number(-1, 1))
		if kind == "papers" then
			Props.scatterPapers(self.folder, CFrame.new(pos), self.rng)
		elseif kind == "stain" then
			Props.stain(self.folder, CFrame.new(pos), self.rng)
		elseif kind == "puddle" then
			Props.puddle(self.folder, CFrame.new(pos), self.rng)
		elseif kind == "box" then
			if self:isFree(c.x, c.z) then
				self:use(c.x, c.z)
				-- small enough to stay inside its own cell whatever the rotation
				local size = Vector3.new(self.rng:Number(1.2, 2), self.rng:Number(1, 1.6), self.rng:Number(1.2, 1.9))
				table.insert(self.room.props, Props.box(self.folder, CFrame.new(self:cellPos(c.x, c.z) + Vector3.new(self.rng:Number(-0.4, 0.4), 0, self.rng:Number(-0.4, 0.4))), self.rng, size))
			end
		end
		count -= 1
	end
end

-- Pipe runs under the ceiling, hung on rods, stopping short of the end walls.
function Ctx:pipesAlongCeiling(count: number, color: Color3?)
	local room = self.room
	local ceiling = self.y + CH
	local alongX = (room.maxX - room.minX) >= (room.maxZ - room.minZ)
	local run = Build.model(self.folder, "PipeRun", CFrame.new(room.center))
	for i = 1, count do
		local offset = (i - 1) * 0.9 + 1.1
		local diameter = 0.5 + (i % 2) * 0.3
		local y = ceiling - 0.8 - i * 0.3
		local a, b
		if alongX then
			local z = room.minZ * CELL + offset
			a = Layout.Origin + Vector3.new(room.minX * CELL + 0.45, y, z)
			b = Layout.Origin + Vector3.new((room.maxX + 1) * CELL - 0.45, y, z)
		else
			local x = room.minX * CELL + offset
			a = Layout.Origin + Vector3.new(x, y, room.minZ * CELL + 0.45)
			b = Layout.Origin + Vector3.new(x, y, (room.maxZ + 1) * CELL - 0.45)
		end
		Props.pipe(run, a, b, diameter, color)
		-- hanger rods every ~6 studs
		local len = (b - a).Magnitude
		local steps = math.max(1, math.floor(len / 6))
		for k = 0, steps do
			local p = a:Lerp(b, k / steps)
			local top = ceiling
			local rodLen = top - (p.Y + diameter / 2)
			if rodLen > 0.05 then
				Build.detail(run, "Hanger", Vector3.new(0.08, rodLen, 0.08), CFrame.new(p + Vector3.new(0, diameter / 2 + rodLen / 2, 0)), Props.Colors.metalDark, M.Metal)
			end
		end
	end
	run:SetAttribute("Room", room.id)
	return run
end

function Ctx:dust(rate: number?)
	local room = self.room
	local size = room.max - room.min
	local holder = Build.part(self.folder, "Dust", Vector3.new(math.max(4, size.X - 2), 1, math.max(4, size.Z - 2)), CFrame.new(Vector3.new(room.center.X, self.y + 6, room.center.Z)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Rate = rate or math.clamp(room.area / 160, 1, 5)
	e.Lifetime = NumberRange.new(8, 14)
	e.Speed = NumberRange.new(0.1, 0.4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.07)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(220, 214, 200))
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Drag = 1
	e.Acceleration = Vector3.new(0, -0.05, 0)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Parent = holder
	holder:SetAttribute("Room", room.id)
	holder:AddTag("RoomDust")
	return holder
end

-- Free floor cells after furnishing become spawn spots (NPCs, mannequins, items).
function Ctx:finalize()
	-- walkways kept clear (checked by the GeometryValidator)
	local circulation = {}
	for _, c in self.room.cells do
		if self.reserved[key(c.x, c.z)] then
			table.insert(circulation, { x = c.x, z = c.z })
		end
	end
	self.room.circulation = circulation
	for _, c in self.room.cells do
		if not self.used[key(c.x, c.z)] then
			table.insert(self.room.floorSpots, self:cellPos(c.x, c.z))
			if not self.reserved[key(c.x, c.z)] then
				self.room.restSpots = self.room.restSpots or {}
				table.insert(self.room.restSpots, self:cellPos(c.x, c.z))
			end
		end
	end
	-- remaining decor-free wall spots (for extra doors, shadows, etc.)
	local wallSpots = {}
	for _, slot in self:wallSlots(true) do
		local k = key(slot.x, slot.z) .. "|" .. slot.dx .. "|" .. slot.dz
		if not self.decorUsed[k] and not self.used[key(slot.x, slot.z)] then
			table.insert(wallSpots, { cframe = CFrame.lookAt(slot.face, slot.face - slot.dir), x = slot.x, z = slot.z })
		end
	end
	self.room.wallSpots = wallSpots
	-- item spots: attachments on furniture tops, and floor fallbacks near walls
	local itemSpots = {}
	local solids = {}
	for _, d in self.folder:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			table.insert(solids, d)
		end
	end
	-- a spot is only usable if nothing else already stands on it
	local function clear(spot: Attachment): boolean
		local p = spot.WorldCFrame.Position
		for _, part in solids do
			if part ~= spot.Parent then
				local rel = part.CFrame:PointToObjectSpace(p)
				local half = part.Size / 2
				if math.abs(rel.X) < half.X + 0.7 and math.abs(rel.Z) < half.Z + 0.7 and rel.Y > -half.Y - 1.5 and rel.Y < half.Y + 0.2 then
					return false
				end
			end
		end
		return true
	end
	for _, d in self.folder:GetDescendants() do
		if d:IsA("Attachment") and d:HasTag("ItemSpot") and clear(d) then
			table.insert(itemSpots, d.WorldCFrame)
		end
	end
	for _, slot in self:wallSlots() do
		table.insert(itemSpots, CFrame.new(slot.face - slot.dir * 1.8 + Vector3.new(0, 0.05, 0)))
	end
	self.room.itemSpots = itemSpots
end

------------------------------------------------------------------------------------
-- Shared dressing
------------------------------------------------------------------------------------

local function painting(folder, cf, rng, maxW, maxH)
	-- frame adds 0.5 around the canvas
	local w = math.min(rng:Pick({ 3.5, 4, 5, 6 }), (maxW or 4) - 0.5)
	local h = math.min(w * rng:Number(0.65, 0.85), (maxH or 4) - 0.5)
	return Props.painting(folder, cf, rng, w, h)
end
local function photo(folder, cf, rng)
	return Props.photo(folder, cf, rng)
end
local function clock(folder, cf, rng)
	return Props.clock(folder, cf, rng)
end

local CLOCK = Vector2.new(2.4, 2.4)
local PHOTO = Vector2.new(2.4, 1.8)
local NOTICE = Vector2.new(5, 3.2)

local function deskWithChair(ctx)
	return function(folder, cf, rng)
		local desk = Props.desk(folder, cf, rng)
		if rng:Chance(0.8) then
			-- pushed back from the desk, turned a little: someone stood up in a hurry
			Props.officeChair(folder, cf * CFrame.new(rng:Number(-0.5, 0.5), 0, -2.9 - rng:Number(0, 0.4)) * CFrame.Angles(0, math.rad(180 + rng:Number(-25, 25)), 0), rng)
		end
		return desk
	end
end

-- desk (6 x 3) with its chair in front of it
local DESK_CLEARANCE = 3.2
-- potted plants: the leaves reach well past the pot
local PLANT_DEPTH = 3
local DESK_FOOTPRINT = Vector2.new(6.6, 2 * (1.5 + 3.3 + 1.2))

-- Wayfinding: what is on each floor, by room number.
local DIRECTORY = {
	U = "1F  ARCHIVE 1-01 · CONFERENCE 1-02 · QUIET ROOM 1-03\n     GALLERY 1-05 · INFIRMARY 1-06 · OPEN OFFICE 1-07\n     SERVER ROOM 1-08 · UTILITY 1-09",
	G = "G   OFFICES G-01 G-02 · MAIL G-03 · STORAGE G-05\n     SECURITY G-07 · BREAK ROOM G-08 · LOADING DOCK",
	B = "B1  MAINTENANCE B-04 · CLOSETS B-09 · COLD STORAGE B-11\n     BOILER ROOM",
}

local function directoryText(floorId: string?): string
	if floorId then
		return "THIS FLOOR\n" .. DIRECTORY[floorId]
	end
	return "THE ASHGROVE BUILDING\n\n" .. DIRECTORY.U .. "\n" .. DIRECTORY.G .. "\n" .. DIRECTORY.B
end

-- A corridor sign pointing toward a room (arrow chosen from where it hangs).
local function directionSign(target: Vector3, label: string)
	return function(folder, cf, rng)
		local rel = cf:PointToObjectSpace(target)
		-- the reader faces the wall: the sign's +X is their left
		local arrow = if rel.X > 0 then "<  " .. label else label .. "  >"
		return Props.sign(folder, cf, arrow, 3.2, 0.7, nil)
	end
end

local KINDS = {}

function KINDS.office(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(Props.filingCabinet, 2.2, false, rng:Int(2, 3), nil, false)
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, rng:Int(1, 2), nil, false, DESK_CLEARANCE)
	ctx:placeCenter(deskWithChair(ctx), rng:Int(1, 2), nil, DESK_FOOTPRINT)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, PLANT_DEPTH, false, 1)
	ctx:placeAgainstWall(Props.trashBin, 1.3, false, 1)
	ctx:decor(painting, 1)
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:decor(photo, rng:Int(0, 1), 6, nil, PHOTO)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, nil)
	end, 1, 6, nil, NOTICE)
	ctx:scatter("papers", rng:Int(2, 4))
	ctx:scatter("stain", rng:Int(1, 2))
	ctx:dust()
end

function KINDS.mail(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.metalShelf(f, cf, r, { fill = 0.8 })
	end, 2, true, rng:Int(2, 3), nil, true)
	ctx:placeCenter(function(f, cf, r)
		local t = Props.table(f, cf, r, 6, 3)
		local slots = r:Shuffle({ -1.9, 0, 1.9 })
		for i = 1, r:Int(1, 3) do
			Props.box(f, cf * CFrame.new(slots[i] + r:Number(-0.15, 0.15), 3.12, r:Number(-0.4, 0.4)), r, Vector3.new(1.4, 0.9 + i * 0.1, 1.2))
		end
		return t
	end, 1, nil, Vector2.new(6.6, 3.6))
	ctx:scatter("box", rng:Int(2, 4))
	ctx:scatter("papers", 4)
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "OUTGOING", 2.6, 0.7, "paper")
	end, 1, 6, nil, Vector2.new(2.6, 0.7))
	ctx:dust()
end

function KINDS.storage(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(Props.metalShelf, 2, true, rng:Int(3, 4), nil, true)
	ctx:placeCenter(Props.crate, rng:Int(1, 2), nil, Vector2.new(3.6, 3.6))
	ctx:placeCenter(Props.pallet, 1, nil, Vector2.new(4.8, 4.6))
	ctx:placeAgainstWall(Props.barrel, 2.4, false, rng:Int(1, 2))
	ctx:placeAgainstWall(Props.ladder, 1.7, false, 1, nil, true)
	ctx:scatter("box", rng:Int(2, 3))
	ctx:scatter("stain", 2)
	ctx:dust(4)
end

function KINDS.corridor(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- corridors: never put floor props in the middle lane; wall props only
	local length = room.maxX - room.minX + 1
	ctx:placeAgainstWall(Props.bench, 1.6, true, math.max(1, length // 14))
	ctx:placeAgainstWall(Props.radiator, 0.6, false, math.max(2, length // 8))
	ctx:placeAgainstWall(Props.fireExtinguisher, 0.4, false, 2)
	ctx:placeAgainstWall(Props.trashBin, 1.3, false, 1)
	if room.floorId == "G" then
		ctx:placeAgainstWall(Props.vendingMachine, 2.6, false, 1, nil, true)
		ctx:placeAgainstWall(Props.waterCooler, 1.4, false, 1, nil, true)
		ctx:placeAgainstWall(function(f, cf, r)
			return Props.plant(f, cf, r, true)
		end, 1.6, false, 2)
	elseif room.floorId == "U" then
		ctx:placeAgainstWall(Props.waterCooler, 1.4, false, 1, nil, true)
		ctx:placeAgainstWall(function(f, cf, r)
			return Props.plant(f, cf, r, true)
		end, 1.6, false, 2)
	end
	local stairs = ctx.map.Rooms[room.floorId .. "_s"]
	if stairs then
		ctx:decor(directionSign(stairs.center, "STAIRS"), math.max(1, length // 16), 8.2, true, Vector2.new(3.2, 0.7))
	end
	if room.floorId == "G" and ctx.map.Rooms.G_y then
		ctx:decor(directionSign(ctx.map.Rooms.G_y.center, "LOADING DOCK"), 1, 8.2, true, Vector2.new(3.2, 0.7))
	end
	ctx:decor(painting, math.max(2, length // 8), 6.5, true)
	ctx:decor(photo, math.max(1, length // 12), 6, true, PHOTO)
	ctx:decor(clock, 1, 9, true, CLOCK)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, if room.floorId == "G" then "NOTICE\nThe building will be\nclosed for renovation.\nDo not use the\nbasement stairs\nafter 9 PM." else nil)
	end, 1, 6, true, NOTICE)
	if room.floorId == "B" then
		ctx:pipesAlongCeiling(3)
		ctx:scatter("puddle", rng:Int(2, 4))
		ctx:placeAgainstWall(Props.wetFloorSign, 1.2, false, 1)
	else
		ctx:pipesAlongCeiling(1, Color3.fromRGB(110, 106, 98))
	end
	ctx:scatter("stain", rng:Int(2, 4))
	ctx:scatter("papers", rng:Int(1, 3))
	ctx:dust()
end

function KINDS.restroom(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- stalls along the wall farthest from the door
	local doorZ = room.doors[1] and room.doors[1].z or room.minZ
	local farZ = if math.abs(doorZ - room.minZ) > math.abs(doorZ - room.maxZ) then room.minZ else room.maxZ
	local wallDz = if farZ == room.maxZ then 1 else -1
	for x = room.minX, room.maxX do
		if ctx:isFree(x, farZ) and ctx:isFree(x, farZ - wallDz) then
			ctx:use(x, farZ)
			ctx:use(x, farZ - wallDz)
			local face = ctx:cellPos(x, farZ) + Vector3.new(0, 0, wallDz * (CELL / 2 - 0.2))
			local pos = face - Vector3.new(0, 0, wallDz * 2.9)
			local stall = Props.toiletStall(ctx.folder, CFrame.lookAt(pos, pos - Vector3.new(0, 0, wallDz)), rng, rng:Chance(0.5))
			table.insert(room.props, stall)
			ctx.decorUsed[(farZ * 10000 + x) .. "|0|" .. wallDz] = true
		end
	end
	-- sinks + mirrors along a side wall
	local sinks = ctx:placeAgainstWall(Props.sink, 1.8, false, 2, function(slot)
		return slot.dx ~= 0
	end)
	for _, sink in sinks do
		local cf = sink:GetPivot()
		local back = cf.Position - cf.LookVector * (0.9 + WALL_GAP)
		local mirrorCF = CFrame.lookAt(back + Vector3.new(0, 6.6, 0), back + Vector3.new(0, 6.6, 0) + cf.LookVector)
		local mirror = Props.mirror(ctx.folder, mirrorCF, rng, 2.6, 3.4)
		table.insert(room.props, mirror)
	end
	ctx:decor(function(f, cf, r)
		return Props.handDryer(f, cf)
	end, 1, 4.5, nil, Vector2.new(1.4, 2.0))
	ctx:scatter("puddle", rng:Int(1, 2))
	ctx:scatter("stain", 1)
	ctx:dust(1.5)
end

function KINDS.breakroom(ctx)
	ctx:placeAgainstWall(function(f, cf, r)
		local counter = Props.counter(f, cf, r, 7.2)
		Props.coffeeMachine(f, cf * CFrame.new(-2.5, 3.25, 0.2), r)
		Props.box(f, cf * CFrame.new(1.8, 3.25, 0.3), r, Vector3.new(1.8, 1.1, 1.3))
		return counter
	end, 2.2, true, 1)
	ctx:placeAgainstWall(Props.fridge, 2.4, false, 1, nil, true)
	ctx:placeAgainstWall(Props.vendingMachine, 2.6, false, 1, nil, true)
	ctx:placeAgainstWall(Props.sofa, 2.6, true, 1)
	ctx:placeCenter(function(f, cf, r)
		local t = Props.roundTable(f, cf, r)
		for i = 0, r:Int(1, 3) do
			local a = math.rad(i * 90 + r:Number(-15, 15))
			Props.woodChair(f, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.9) * CFrame.Angles(0, math.rad(180), 0), r)
		end
		return t
	end, 2, nil, Vector2.new(8, 8))
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, "KITCHEN RULES\n1. Label your food\n2. Clean the microwave\n3. Do not leave anyone\nalone in the basement")
	end, 1, 6, nil, NOTICE)
	ctx:decor(painting, 1)
	ctx:scatter("stain", 2)
	ctx:scatter("papers", 1)
	ctx:dust()
end

function KINDS.reception(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- reception desk in the northern half, facing the entrance (south)
	-- find a 4x2 block of free cells in the northern half (never across the walkway)
	local deskX, deskZ = nil, nil
	for ox = room.minX, room.maxX - 3 do
		if ctx:areaFree(ox, room.minZ + 2, ox + 3, room.minZ + 3) then
			ctx:useArea(ox, room.minZ + 1, ox + 3, room.minZ + 3)
			deskX = (ox + 2) * CELL
			deskZ = (room.minZ + 3) * CELL
			break
		end
	end
	deskX = deskX or room.center.X - Layout.Origin.X
	deskZ = deskZ or (room.minZ + 3) * CELL
	local deskPos = Layout.Origin + Vector3.new(deskX, ctx.y, deskZ)
	local desk = Props.receptionDesk(ctx.folder, CFrame.lookAt(deskPos, deskPos + Vector3.new(0, 0, 1)), rng)
	table.insert(room.props, desk)
	-- the big painting behind the desk is the tutorial anomaly anchor
	local wallPos = Layout.Origin + Vector3.new(deskX, ctx.y + 7.5, (room.minZ) * CELL + 0.2)
	local big = Props.painting(ctx.folder, CFrame.lookAt(wallPos, wallPos + Vector3.new(0, 0, 1)), rng, 8, 5, "portrait")
	big:SetAttribute("Tutorial", true)
	table.insert(room.props, big)
	-- nothing else hangs on that stretch of wall
	for x = room.minX, room.maxX do
		local cx = Layout.Origin.X + x * CELL + CELL / 2
		if math.abs(cx - (Layout.Origin.X + deskX)) < 4.5 + CELL / 2 then
			ctx.decorUsed[slotKey(x, room.minZ, 0, -1)] = true
		end
	end
	-- clock above the archway side
	-- waiting area: rows of chairs facing each other
	local waitingZ = room.maxZ - 3
	for i, x in { room.minX + 2, room.maxX - 2 } do
		if ctx:isFree(x, waitingZ) and ctx:isFree(x, waitingZ + 1) then
			ctx:use(x, waitingZ)
			ctx:use(x, waitingZ + 1)
			local p = ctx:cellPos(x, waitingZ) + Vector3.new(0, 0, 2)
			local face = if i == 1 then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0)
			table.insert(room.props, Props.waitingChairs(ctx.folder, CFrame.lookAt(p, p + face), rng, 3))
		end
	end
	ctx:placeCenter(function(f, cf, r)
		return Props.table(f, cf, r, 4, 2.4)
	end, 1, nil, Vector2.new(4.6, 3))
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, PLANT_DEPTH, false, 3)
	ctx:placeAgainstWall(Props.sofa, 2.6, true, 1)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, directoryText(nil), 2.8, 3.4, "brass")
	end, 1, 6.5, true, Vector2.new(2.8, 3.4))
	ctx:decor(painting, 3, 7)
	ctx:decor(clock, 1, 9.5, nil, CLOCK)
	ctx:decor(photo, 1, 6, nil, PHOTO)
	-- a rug
	Build.detail(ctx.folder, "Rug", Vector3.new(18, 0.05, 12), CFrame.new(room.center + Vector3.new(0, 0.03, 6)), Color3.fromRGB(70, 46, 40), M.Fabric)
	-- the elevator: out of order forever (set into the west wall, clear of the baseboard)
	local slots = ctx:wallSlots(true)
	for _, slot in slots do
		if slot.dx == -1 and slot.z == room.minZ + 6 then
			local cf = ctx:wallCF(slot, 0)
			local elev = Build.model(ctx.folder, "Elevator", cf)
			Build.part(elev, "Frame", Vector3.new(3.4, 10, 0.3), cf * CFrame.new(0, 5, -0.33), Color3.fromRGB(90, 84, 70), M.Metal)
			Build.part(elev, "DoorL", Vector3.new(1.3, 9, 0.2), cf * CFrame.new(-0.66, 4.6, -0.58), Color3.fromRGB(110, 108, 100), M.Metal)
			Build.part(elev, "DoorR", Vector3.new(1.3, 9, 0.2), cf * CFrame.new(0.66, 4.6, -0.58), Color3.fromRGB(110, 108, 100), M.Metal)
			Props.sign(elev, cf * CFrame.new(0, 3.6, -0.66), "OUT OF ORDER", 2.2, 0.8, "paper")
			ctx.decorUsed[slotKey(slot.x, slot.z, slot.dx, slot.dz)] = true
			table.insert(room.props, elev)
			break
		end
	end
	ctx:scatter("papers", 3)
	ctx:scatter("stain", 2)
	ctx:dust(5)
end

function KINDS.vestibule(ctx)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, directoryText(nil), 2.8, 3.4, "brass")
	end, 1, 6.2, true, Vector2.new(2.8, 3.4))
	Build.detail(ctx.folder, "Mat", Vector3.new(8, 0.06, 4), CFrame.new(ctx.room.center + Vector3.new(0, 0.03, 2)), Color3.fromRGB(40, 36, 32), M.Fabric)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "VISITORS MUST SIGN IN AT RECEPTION", 5, 0.9, "brass")
	end, 1, 7.5, nil, Vector2.new(5, 0.9))
	ctx:placeAgainstWall(Props.trashBin, 1.3, false, 1)
	ctx:scatter("papers", 2)
	ctx:dust(1)
end

function KINDS.security(ctx)
	-- the override switch released by the code puzzle
	local spot = ctx:findWallSpot(2.6, 3.6)
	if spot then
		local cf = ctx:wallCF(spot.slot, spot.y, spot.offset)
		local m = Build.model(ctx.folder, "SecurityOverride", cf)
		Build.part(m, "Plate", Vector3.new(2.4, 3, 0.3), cf * CFrame.new(0, 0, -0.17), Color3.fromRGB(60, 62, 64), M.Metal, { CanCollide = false })
		local lever = Build.part(m, "Lever", Vector3.new(0.35, 1.4, 0.35), cf * CFrame.new(0, 0.1, -0.6) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(150, 40, 34), M.SmoothPlastic, { CanCollide = false })
		lever:AddTag("Interactable")
		lever:SetAttribute("InteractKind", "Override")
		lever:SetAttribute("Prompt", "Pull override")
		lever:SetAttribute("HoldTime", 1)
		Props.sign(m, cf * CFrame.new(0, 2.05, -0.02), "EXIT OVERRIDE", 2.4, 0.5, nil)
		m:AddTag("SecurityOverride")
		table.insert(ctx.room.props, m)
	end
	ctx:placeAgainstWall(function(f, cf, r)
		local desk = Props.desk(f, cf, r, { monitor = false, lamp = false, phone = false, papers = false })
		for i = -1, 1 do
			Props.crt(f, cf * CFrame.new(i * 1.7, 3.3, 0.3) * CFrame.Angles(0, math.rad(180), 0), r)
		end
		Props.officeChair(f, cf * CFrame.new(0, 0, -3) * CFrame.Angles(0, math.rad(180), 0), r)
		return desk
	end, 3, true, 1, nil, false, DESK_CLEARANCE)
	ctx:placeAgainstWall(Props.locker, 1.8, false, 3, nil, true)
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, "SHIFT LOG\n03:12 - nothing\n03:14 - nothing\n03:15 - it is standing\nin camera 4 again")
	end, 1, 6, nil, NOTICE)
	ctx:scatter("papers", 2)
	ctx:dust()
end

function KINDS.dock(ctx)
	local rng = ctx.rng
	-- keep the approach to the shutter clear
	for _, rec in ctx.map.ExitCells do
		for dx = -3, -1 do
			for dz = -1, 1 do
				ctx.reserved[(rec.z + dz) * 10000 + (rec.x + dx)] = true
			end
		end
	end
	ctx:placeCenter(Props.forklift, 1, nil, Vector2.new(4.6, 12))
	ctx:placeCenter(Props.pallet, rng:Int(2, 3), nil, Vector2.new(4.8, 4.6))
	ctx:placeAgainstWall(Props.crate, 3, false, rng:Int(3, 4))
	ctx:placeAgainstWall(Props.barrel, 2.4, false, rng:Int(2, 3))
	ctx:placeAgainstWall(Props.metalShelf, 2, true, 1, nil, true)
	ctx:scatter("stain", 3)
	ctx:scatter("puddle", 1)
	-- painted safety stripe in front of the exit
	if ctx.map.ExitCenter then
		Build.detail(ctx.folder, "Stripe", Vector3.new(4, 0.05, 8), CFrame.new(ctx.map.ExitCenter + Vector3.new(-5, -ctx.map.ExitCenter.Y + ctx.y + 0.03, 0)), Color3.fromRGB(150, 130, 60), M.SmoothPlastic, { Transparency = 0.4 })
	end
	ctx:dust(4)
end

function KINDS.archive(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- symbol cabinet against a wall, clearly visible
	local cab = ctx:placeAgainstWall(Props.symbolCabinet, 2.2, true, 1)
	if #cab == 0 then
		-- fall back to the room centre
		ctx:placeCenter(Props.symbolCabinet, 1, 0, Vector2.new(5.6, 2.8))
	end
	-- rows of archive shelves
	for z = room.minZ + 1, room.maxZ - 2, 3 do
		for x = room.minX + 1, room.maxX - 2, 3 do
			if ctx:isFree(x, z) and ctx:isFree(x + 1, z) then
				ctx:use(x, z)
				ctx:use(x + 1, z)
				local p = ctx:cellPos(x, z) + Vector3.new(CELL / 2, 0, 0)
				table.insert(room.props, Props.archiveShelf(ctx.folder, CFrame.lookAt(p, p + Vector3.new(0, 0, 1)), rng))
			end
		end
	end
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, 1, nil, false, DESK_CLEARANCE)
	ctx:placeAgainstWall(Props.ladder, 1.7, false, 1, nil, true)
	ctx:scatter("box", 3)
	ctx:scatter("papers", 4)
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:dust(5)
end

function KINDS.conference(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- the longest free band of three rows (table + a row of chairs each side),
	-- never across the walkways between the doors
	local best = nil
	for z = room.minZ + 1, room.maxZ - 1 do
		local runStart = nil
		for x = room.minX, room.maxX + 1 do
			local ok = x <= room.maxX and ctx:areaFree(x, z - 1, x, z + 1)
			if ok then
				runStart = runStart or x
			elseif runStart then
				local len = x - runStart
				if not best or len > best.len then
					best = { x0 = runStart, x1 = x - 1, z = z, len = len }
				end
				runStart = nil
			end
		end
	end
	if best and best.len >= 2 then
		ctx:useArea(best.x0, best.z - 1, best.x1, best.z + 1)
		local a = ctx:cellPos(best.x0, best.z)
		local b = ctx:cellPos(best.x1, best.z)
		local center = (a + b) / 2
		local len = best.len * CELL - 1.6
		local t = Props.table(ctx.folder, CFrame.new(center), rng, len, 4)
		table.insert(room.props, t)
		local chairs = math.floor(len / 3.2)
		for i = 0, chairs - 1 do
			local x = -len / 2 + 1.6 + i * 3.2
			for _, side in { -1, 1 } do
				if rng:Chance(0.85) then
					local cf = CFrame.new(center + Vector3.new(x, 0, side * 3.4)) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
					Props.officeChair(ctx.folder, cf, rng)
				end
			end
		end
	end
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "Q3 REVIEW\n- occupancy: 0\n- incidents: 14\n- missing: ?", 6, 3.4, "paper")
	end, 1, 7, nil, Vector2.new(6, 3.4))
	ctx:decor(painting, 1)
	ctx:decor(clock, 1, 9, nil, CLOCK)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, PLANT_DEPTH, false, 2)
	ctx:scatter("papers", 3)
	ctx:dust()
end

function KINDS.quiet(ctx)
	local tableModels = ctx:placeAgainstWall(Props.offeringTable, 2.4, true, 1)
	if #tableModels == 0 then
		ctx:placeCenter(Props.offeringTable, 1, 0, Vector2.new(5.6, 3))
	end
	ctx:placeCenter(Props.rockingChair, 1, nil, Vector2.new(2.8, 3.4))
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.bed(f, cf * CFrame.new(0, 0, 0), r)
	end, 7, false, 1)
	for _ = 1, 3 do
		ctx:decor(function(f, cf, r)
			local lines = r:Pick({ "MOMMY\nDADDY\nTHE TALL MAN", "WE PLAY\nDON'T LOOK", "ITS NICE\nWHEN YOU\nWATCH", "1 2 3 4\nCLOSE YOUR EYES" })
			return Props.sign(f, cf, lines, 2.2, 2.2, "paper")
		end, 1, 4.8, nil, Vector2.new(2.2, 2.2))
	end
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:scatter("papers", 2)
	ctx:dust(2)
end

function KINDS.gallery(ctx)
	ctx:decor(painting, 10, 6.8, true)
	ctx:decor(photo, 2, 5.2, true, PHOTO)
	ctx:placeCenter(Props.bench, 2, nil, Vector2.new(6.4, 2))
	ctx:placeCenter(function(f, cf, r)
		local m = Build.model(f, "Pedestal", cf)
		Build.part(m, "Base", Vector3.new(1.8, 3.6, 1.8), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(150, 146, 136), M.Marble)
		Build.ball(m, "Bust", 1.4, cf * CFrame.new(0, 4.3, 0), Color3.fromRGB(176, 172, 164), M.Marble)
		m:AddTag("Movable")
		return m
	end, 2, nil, Vector2.new(2.4, 2.4))
	ctx:dust(3)
end

function KINDS.infirmary(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(function(f, cf, r)
		local bed = Props.bed(f, cf, r)
		-- the privacy curtain hangs on whichever side of the bed has room
		for _, side in { -1, 1 } do
			local probe = (cf * CFrame.new(side * 3.2, 0, 0)).Position
			local cx = math.floor((probe.X - Layout.Origin.X) / CELL)
			local cz = math.floor((probe.Z - Layout.Origin.Z) / CELL)
			if ctx:inRoom(cx, cz) then
				Props.curtain(f, cf * CFrame.new(side * 2.3, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 5.6, r, CH)
				break
			end
		end
		return bed
	end, 7, false, rng:Int(2, 3), function(slot)
		return slot.dz ~= 0
	end)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.ivStand(f, cf)
	end, 1, false, 2)
	ctx:placeAgainstWall(Props.filingCabinet, 2.2, false, 2)
	ctx:placeCenter(Props.wheelchair, 1, nil, Vector2.new(3.2, 3.2))
	ctx:placeAgainstWall(Props.sink, 1.8, false, 1)
	ctx:decor(clock, 1, 8.5, nil, CLOCK)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "PLEASE KEEP YOUR EYES OPEN", 4.2, 0.8, "paper")
	end, 1, 7, nil, Vector2.new(4.2, 0.8))
	ctx:scatter("stain", 2)
	ctx:dust()
end

function KINDS.openoffice(ctx)
	local rng = ctx.rng
	local room = ctx.room
	for z = room.minZ + 1, room.maxZ - 1, 3 do
		for x = room.minX + 1, room.maxX - 1, 3 do
			if ctx:isFree(x, z) and ctx:isFree(x + 1, z) and ctx:isFree(x, z + 1) and ctx:isFree(x + 1, z + 1) then
				ctx:use(x, z)
				ctx:use(x + 1, z)
				ctx:use(x, z + 1)
				ctx:use(x + 1, z + 1)
				local p = ctx:cellPos(x, z) + Vector3.new(CELL / 2, 0, CELL / 2)
				table.insert(room.props, Props.cubicle(ctx.folder, CFrame.lookAt(p, p - Vector3.new(0, 0, 1)), rng))
			end
		end
	end
	ctx:placeAgainstWall(Props.waterCooler, 1.4, false, 1, nil, true)
	ctx:placeAgainstWall(Props.filingCabinet, 2.2, false, 2)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, PLANT_DEPTH, false, 2)
	ctx:decor(clock, 1, 9, nil, CLOCK)
	ctx:decor(painting, 2)
	ctx:scatter("papers", 5)
	ctx:dust(4)
end

function KINDS.server(ctx)
	local rng = ctx.rng
	local room = ctx.room
	for x = room.minX + 1, room.maxX - 1, 2 do
		for z = room.minZ + 1, room.maxZ - 1 do
			if ctx:isFree(x, z) and (z - room.minZ) % 3 ~= 0 then
				ctx:use(x, z)
				local p = ctx:cellPos(x, z)
				table.insert(room.props, Props.serverRack(ctx.folder, CFrame.lookAt(p, p + Vector3.new(1, 0, 0)), rng))
			end
		end
	end
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, 1, nil, false, DESK_CLEARANCE)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "AUTHORIZED PERSONNEL ONLY", 4, 0.8, nil)
	end, 1, 7, nil, Vector2.new(4, 0.8))
	ctx:dust(2)
end

function KINDS.utility(ctx)
	ctx:placeAgainstWall(Props.metalShelf, 2, true, 1, nil, true)
	ctx:placeAgainstWall(Props.barrel, 2.4, false, 1)
	ctx:placeAgainstWall(Props.wetFloorSign, 1.2, false, 1)
	ctx:scatter("box", 2)
	ctx:scatter("puddle", 1)
	ctx:dust(2)
end

function KINDS.boiler(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- two boilers in the middle of the room
	for i, x in { room.minX + 4, room.maxX - 4 } do
		local z = math.floor((room.minZ + room.maxZ) / 2)
		local ok = true
		for dx = -1, 1 do
			for dz = -1, 1 do
				if not ctx:isFree(x + dx, z + dz) then
					ok = false
				end
			end
		end
		if ok then
			for dx = -1, 1 do
				for dz = -1, 1 do
					ctx:use(x + dx, z + dz)
				end
			end
			local p = ctx:cellPos(x, z) + Vector3.new(0, 0, CELL / 2)
			local b = Props.boiler(ctx.folder, CFrame.lookAt(p, p + Vector3.new(0, 0, 1)), rng)
			b:SetAttribute("Index", i)
			table.insert(room.props, b)
			-- steam leak
			local steamHolder = Build.part(ctx.folder, "Steam", Vector3.new(0.4, 0.4, 0.4), CFrame.new(p + Vector3.new(1.8, 8.6, 1)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
			local steam = Instance.new("ParticleEmitter")
			steam.Rate = 6
			steam.Lifetime = NumberRange.new(2, 3)
			steam.Speed = NumberRange.new(2, 4)
			steam.SpreadAngle = Vector2.new(15, 15)
			steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.4) })
			steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
			steam.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
			steam.LightInfluence = 1
			steam.Parent = steamHolder
			steamHolder:AddTag("SteamSource")
		end
	end
	ctx:placeAgainstWall(Props.workbench, 2.6, true, 1)
	ctx:placeAgainstWall(Props.barrel, 2.4, false, 2)
	ctx:pipesAlongCeiling(5)
	for _ = 1, 3 do
		ctx:decor(function(f, cf, r)
			return Props.valveWheel(f, cf)
		end, 1, rng:Number(4.5, 6), nil, Vector2.new(1.4, 1.4))
	end
	ctx:scatter("puddle", rng:Int(3, 5))
	ctx:scatter("stain", 3)
	ctx:dust(4)
end

function KINDS.maintenance(ctx)
	local room = ctx.room
	-- fuse box and breaker panel on the walls furthest from the door
	local door = room.doors[1]
	local function farFirst(a, b)
		local da = door and math.abs(a.x - door.x) + math.abs(a.z - door.z) or 0
		local db = door and math.abs(b.x - door.x) + math.abs(b.z - door.z) or 0
		if da == db then
			return a.x * 1000 + a.z < b.x * 1000 + b.z
		end
		return da > db
	end
	-- the power puzzle needs both fittings: relax the constraints if the room is crowded
	local fuseSpot = ctx:findWallSpot(3.6, 4.2, 5, farFirst) or ctx:findWallSpot(2.6, 4.2, 5, farFirst)
	if fuseSpot then
		table.insert(room.props, Props.fuseBox(ctx.folder, ctx:wallCF(fuseSpot.slot, fuseSpot.y, fuseSpot.offset)))
	end
	local breakerSpot = ctx:findWallSpot(5.2, 3.8, 4.6, farFirst) or ctx:findWallSpot(2.6, 3.8, 4.6, farFirst)
	if breakerSpot then
		table.insert(room.props, Props.breakerPanel(ctx.folder, ctx:wallCF(breakerSpot.slot, breakerSpot.y, breakerSpot.offset)))
	end
	ctx:placeAgainstWall(Props.workbench, 2.6, true, 1)
	ctx:placeAgainstWall(Props.locker, 1.8, false, 2, nil, true)
	ctx:placeAgainstWall(Props.metalShelf, 2, true, 1, nil, true)
	ctx:placeCenter(Props.crate, 1, nil, Vector2.new(3.6, 3.6))
	ctx:pipesAlongCeiling(2)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "DANGER  HIGH VOLTAGE", 3.6, 0.8, nil)
	end, 1, 8, nil, Vector2.new(3.6, 0.8))
	ctx:scatter("stain", 2)
	ctx:dust(3)
end

function KINDS.closets(ctx)
	local room = ctx.room
	-- the closet lamps above each puzzle door
	local lampColors = {
		Color3.fromRGB(255, 190, 110),
		Color3.fromRGB(230, 236, 255),
		Color3.fromRGB(150, 220, 160),
		Color3.fromRGB(140, 170, 255),
	}
	for _, door in room.doors do
		if door.char == "P" then
			local closetRoom = ctx.map.Rooms[door.roomB] or ctx.map.Rooms[door.roomA]
			local index = closetRoom and closetRoom.closet or 1
			-- which side of the door is this room on?
			local pd = door.passageDir
			local inward = if ctx:inRoom(door.x - math.round(pd.X), door.z - math.round(pd.Z)) then -pd else pd
			-- the wall finish over the door sits 0.2 into the room from the cell boundary
			local face = door.center + inward * (CELL / 2 + 0.2)
			local lampAt = face + Vector3.new(0, 11.4, 0)
			table.insert(room.props, Props.closetLamp(ctx.folder, CFrame.lookAt(lampAt, lampAt + inward), lampColors[index], index))
			-- the roman numeral plate goes on the plain wall beside the door
			local along = Vector3.new(math.abs(pd.Z), 0, math.abs(pd.X))
			for _, side in { 1, -1 } do
				local nx, nz = door.x + math.round(along.X) * side, door.z + math.round(along.Z) * side
				if Layout.charAt(ctx.floor, nx, nz) == "#" then
					local plateAt = face + along * side * (CELL / 2 + 1.1) + Vector3.new(0, 6.5, 0)
					local plate = Props.sign(ctx.folder, CFrame.lookAt(plateAt, plateAt + inward), ({ "I", "II", "III", "IV" })[index], 1, 0.8, "brass")
					table.insert(room.props, plate)
					local cx, cz = nx + math.round(inward.X), nz + math.round(inward.Z)
					ctx.decorUsed[slotKey(cx, cz, -math.round(inward.X), -math.round(inward.Z))] = true
					break
				end
			end
		end
	end
	ctx:placeAgainstWall(function(f, cf, r)
		local t = Props.table(f, cf, r, 3, 2)
		Props.tapeRecorder(f, cf * CFrame.new(0, 3.12, 0) * CFrame.Angles(0, math.rad(180), 0))
		return t
	end, 2, false, 1, function(slot)
		return slot.dz == -1
	end)
	ctx:placeAgainstWall(Props.bench, 1.6, true, 1, function(slot)
		return slot.dz == -1
	end)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "OPEN THEM IN THE ORDER YOU HEARD", 4.6, 0.8, "paper")
	end, 1, 7, true, Vector2.new(4.6, 0.8))
	ctx:pipesAlongCeiling(2)
	ctx:scatter("puddle", 2)
	ctx:dust(2)
end

function KINDS.closet(ctx)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.metalShelf(f, cf, r, { width = 3.2, fill = 0.7 })
	end, 2, false, 1, nil, true)
	ctx:scatter("box", 1)
end

function KINDS.secret(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- a single chair facing the far wall, covered in photographs joined by string
	local center = room.center
	local chairCell = nil
	for z = room.maxZ - 1, room.minZ, -1 do
		for _, x in { math.floor((room.minX + room.maxX) / 2), room.minX + 1, room.maxX - 1 } do
			if not chairCell and ctx:isFree(x, z) then
				chairCell = { x = x, z = z }
			end
		end
	end
	if chairCell then
		ctx:use(chairCell.x, chairCell.z)
		local p = ctx:cellPos(chairCell.x, chairCell.z)
		table.insert(room.props, Props.woodChair(ctx.folder, CFrame.lookAt(p, p + Vector3.new(0, 0, 1)), rng))
	end
	-- skin face of the far wall, photographs pinned flat against it
	local wallZ = (room.maxZ + 1) * CELL - 0.2 - 0.03
	local board = Build.model(ctx.folder, "EvidenceBoard", CFrame.new(Layout.Origin + Vector3.new(room.center.X - Layout.Origin.X, ctx.y + 7, wallZ)))
	local pins = {}
	for i = 1, 14 do
		local p = Layout.Origin + Vector3.new(rng:Number(room.minX * CELL + 3, (room.maxX + 1) * CELL - 3), ctx.y + rng:Number(3.5, 10), 0)
		p = Vector3.new(p.X, p.Y, Layout.Origin.Z + wallZ)
		Build.detail(board, "Pinned", Vector3.new(1.4, 1, 0.03), CFrame.lookAt(p, p - Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(rng:Number(-15, 15))), Color3.fromRGB(30, 28, 26), M.SmoothPlastic)
		local pin = p - Vector3.new(0, 0, 0.08)
		table.insert(pins, pin)
		if i > 1 and rng:Chance(0.7) then
			local a, b = pins[i - 1], pin
			Build.detail(board, "String", Vector3.new(0.05, 0.05, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(120, 30, 28), M.Fabric)
		end
	end
	table.insert(room.props, board)
	-- the photograph spot (secret item)
	local tablePos = center + Vector3.new(4, 0, -2)
	local t = Props.table(ctx.folder, CFrame.new(tablePos), rng, 3, 2)
	t:SetAttribute("SecretSpot", true)
	table.insert(room.props, t)
	room.secretSpot = CFrame.new(tablePos + Vector3.new(0, 3.2, 0))
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "YOU WERE ALWAYS HERE", 4, 0.8, "paper")
	end, 1, 11.5, true, Vector2.new(4, 0.8))
	ctx:dust(2)
end

function KINDS.cold(ctx)
	local rng = ctx.rng
	local room = ctx.room
	ctx:placeAgainstWall(Props.freezer, 2.4, false, rng:Int(2, 3))
	-- hanging hooks
	for _, c in ctx:interiorCells() do
		if rng:Chance(0.35) then
			local p = ctx:cellPos(c.x, c.z) + Vector3.new(0, CH - 1, 0)
			local hook = Build.model(ctx.folder, "MeatHook", CFrame.new(p))
			Build.detail(hook, "Chain", Vector3.new(0.1, 2, 0.1), CFrame.new(p), Props.Colors.metal, M.Metal)
			Build.detail(hook, "Hook", Vector3.new(0.5, 0.15, 0.15), CFrame.new(p - Vector3.new(0, 1.1, 0)), Props.Colors.metal, M.Metal)
		end
	end
	for _, door in room.doors do
		local pos = door.center + Vector3.new(0, -door.center.Y + ctx.y, 0)
		Props.plasticStrips(ctx.folder, CFrame.lookAt(pos, pos + door.passageDir), CELL - 0.75)
	end
	ctx:scatter("puddle", 2)
	ctx:dust(1.5)
end

function KINDS.stairs(ctx)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, directoryText(ctx.room.floorId), 4.2, 2, "brass")
	end, 1, 6.2, true, Vector2.new(4.2, 2))
	ctx:dust(1)
end

------------------------------------------------------------------------------------
-- Door dressing: room numbers and exit signs
------------------------------------------------------------------------------------

local function dressDoors(map, folder)
	for _, door in map.Doors do
		local roomA = door.roomA and map.Rooms[door.roomA]
		local roomB = door.roomB and map.Rooms[door.roomB]
		local corridorSide, other = nil, nil
		if roomA and roomA.kind == "corridor" then
			corridorSide, other = -1, roomB
		elseif roomB and roomB.kind == "corridor" then
			corridorSide, other = 1, roomA
		end
		if corridorSide and other and other.number and door.char ~= "H" then
			local floor = Layout.getFloor(door.floor)
			local side = Vector3.new(door.passageDir.Z, 0, door.passageDir.X)
			for _, s in { 1, -1 } do
				local nx = door.x + s * math.round(side.X)
				local nz = door.z + s * math.round(side.Z)
				if Layout.charAt(floor, nx, nz) == "#" then
					local face = door.center + door.passageDir * corridorSide * (CELL / 2 + 0.2) + side * s * (CELL / 2 + 1.2) + Vector3.new(0, 6.5, 0)
					local m, label = Props.roomPlate(folder, CFrame.lookAt(face, face + door.passageDir * corridorSide), other.number)
					m:SetAttribute("Room", other.id)
					label:SetAttribute("Room", other.id)
					other.plate = m
					break
				end
			end
			if other.kind == "stairs" or other.kind == "dock" then
				local hang = door.center + door.passageDir * corridorSide * (CELL / 2 + 2) + Vector3.new(0, Layout.CeilingHeight - 1.2, 0)
				local sign = Props.exitSign(folder, CFrame.lookAt(hang, hang + door.passageDir * corridorSide))
				sign:SetAttribute("Room", door.roomA)
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Emergency beacons: red ceiling lamps along corridors and in stairwells that
-- wake up when the power fails, so a dark building still has a pulse to follow.
------------------------------------------------------------------------------------

local function placeBeacons(map, folder)
	map.Beacons = {}
	local ids = {}
	for id in map.Rooms do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local room = map.Rooms[id]
		-- (not in stairwells: their ceiling is the open shaft)
		if (room.kind == "corridor" or room.kind == "dock" or room.kind == "reception") and not room.secret then
			local floor = Layout.getFloor(room.floorId)
			local cells = table.clone(room.cells)
			table.sort(cells, function(a, b)
				return a.x * 1000 + a.z < b.x * 1000 + b.z
			end)
			local placed = 0
			local maxCount = if room.kind == "corridor" then math.clamp(math.floor(#cells / 10), 1, 4) else 1
			local last: Vector3? = nil
			for _, c in cells do
				if placed >= maxCount then
					break
				end
				-- away from light fixtures (they sit on x % 4 == 1/2 cells) and from each other
				if (c.x + c.z) % 5 == 3 then
					local pos = Layout.cellToWorld(floor.y, c.x, c.z) + Vector3.new(0, Layout.CeilingHeight, 0)
					if not last or (pos - (last :: Vector3)).Magnitude > 22 then
						local beacon = Props.emergencyBeacon(folder, CFrame.new(pos))
						beacon:SetAttribute("Room", room.id)
						table.insert(map.Beacons, beacon)
						placed += 1
						last = pos
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Residents: unmoving occupants used by NPC anomalies
------------------------------------------------------------------------------------

local function placeResidents(map, folder, rng)
	map.Residents = {}
	local candidates = {}
	for _, room in map.Rooms do
		if (room.kind == "office" or room.kind == "openoffice" or room.kind == "gallery" or room.kind == "infirmary" or room.kind == "conference") and not room.lockKey then
			table.insert(candidates, room)
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	rng:Shuffle(candidates)
	for i = 1, math.min(2, #candidates) do
		local room = candidates[i]
		-- residents sit or stand out of the way, never on a walkway
		local spots = room.restSpots or {}
		local spot = spots[rng:Int(1, math.max(1, #spots))]
		if spot then
			local seated = room.kind == "office" or room.kind == "openoffice" or room.kind == "conference"
			local face = room.center - spot
			face = if face.Magnitude > 0.1 then Vector3.new(face.X, 0, face.Z).Unit else Vector3.new(0, 0, 1)
			local cf = CFrame.lookAt(spot, spot + face)
			if seated then
				Props.woodChair(folder, cf, rng)
			end
			local npc = Props.resident(folder, cf, rng, if seated then "seated" else "standing")
			npc:SetAttribute("Room", room.id)
			table.insert(map.Residents, npc)
		end
	end
end

------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------

function Furnisher.furnishAll(map, parent: Instance, rng)
	local roomIds = {}
	for id in map.Rooms do
		table.insert(roomIds, id)
	end
	table.sort(roomIds) -- deterministic order for the seed
	for i, id in roomIds do
		local room = map.Rooms[id]
		local folder = Instance.new("Folder")
		folder.Name = id
		folder.Parent = parent
		room.folder = folder
		local ctx = newCtx(map, room, folder, rng:Derive(id))
		local fn = KINDS[room.kind]
		if fn then
			fn(ctx)
		end
		ctx:finalize()
		for _, prop in room.props do
			if typeof(prop) == "Instance" then
				prop:SetAttribute("Room", room.id)
			end
		end
		if i % 4 == 0 then
			task.wait()
		end
	end
	dressDoors(map, parent)
	placeBeacons(map, parent)
	placeResidents(map, parent, rng:Derive("residents"))
end

return Furnisher
