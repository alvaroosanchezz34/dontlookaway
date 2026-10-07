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
	}, Ctx)
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

-- CFrame for a floor prop of the given depth backed against the slot's wall.
function Ctx:backedCF(slot, depth: number, offsetAlong: number?): CFrame
	local side = Vector3.new(slot.dz, 0, slot.dx) -- along the wall
	local pos = slot.face - slot.dir * (depth / 2 + 0.05) + side * (offsetAlong or 0)
	return CFrame.lookAt(pos, pos - slot.dir)
end

-- CFrame on the wall face at height h (for decor).
function Ctx:wallCF(slot, h: number, offsetAlong: number?): CFrame
	local side = Vector3.new(slot.dz, 0, slot.dx)
	local pos = slot.face + Vector3.new(0, h, 0) + side * (offsetAlong or 0)
	return CFrame.lookAt(pos, pos - slot.dir)
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

function Ctx:placeAgainstWall(builder, depth: number, wide: boolean?, count: number?, filter: ((any) -> boolean)?, tall: boolean?)
	local placed = {}
	local slots = self.rng:Shuffle(self:wallSlots())
	for _, slot in slots do
		if #placed >= (count or 1) then
			break
		end
		local deepOk = true
		local deepCells = math.ceil(depth / CELL) - 1
		for k = 1, deepCells do
			if not self:isFree(slot.x - slot.dx * k, slot.z - slot.dz * k) then
				deepOk = false
			end
		end
		if deepOk and self:isFree(slot.x, slot.z) and (not filter or filter(slot)) then
			local cf
			if wide then
				local other = self:pairSlot(slot)
				if other then
					self:use(other.x, other.z)
					cf = self:backedCF(slot, depth, CELL / 2)
				end
			else
				cf = self:backedCF(slot, depth)
			end
			if cf then
				self:use(slot.x, slot.z)
				for k = 1, deepCells do
					self:use(slot.x - slot.dx * k, slot.z - slot.dz * k)
				end
				local m = builder(self.folder, cf, self.rng)
				table.insert(placed, m)
				table.insert(self.room.props, m)
				if tall then
					self.decorUsed[key(slot.x, slot.z) .. "|" .. slot.dx .. "|" .. slot.dz] = true
					if wide then
						local ax, az = math.abs(slot.dz), math.abs(slot.dx)
						self.decorUsed[key(slot.x + ax, slot.z + az) .. "|" .. slot.dx .. "|" .. slot.dz] = true
					end
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

function Ctx:placeCenter(builder, count: number, yaw: number?)
	local placed = {}
	for _, c in self:interiorCells() do
		if #placed >= count then
			break
		end
		if self:isFree(c.x, c.z) then
			self:use(c.x, c.z)
			local pos = self:cellPos(c.x, c.z)
			local angle = yaw or (self.rng:Int(0, 3) * 90 + self.rng:Number(-8, 8))
			local m = builder(self.folder, CFrame.new(pos) * CFrame.Angles(0, math.rad(angle), 0), self.rng)
			table.insert(placed, m)
			table.insert(self.room.props, m)
		end
	end
	return placed
end

-- Wall decor at eye height on slots not covered by tall furniture.
function Ctx:decor(builder, count: number, height: number?, allowReserved: boolean?)
	local placed = {}
	local slots = self.rng:Shuffle(self:wallSlots(true))
	for _, slot in slots do
		if #placed >= count then
			break
		end
		local k = key(slot.x, slot.z) .. "|" .. slot.dx .. "|" .. slot.dz
		local isReserved = self.reserved[key(slot.x, slot.z)]
		if not self.decorUsed[k] and (allowReserved ~= false or not isReserved) then
			self.decorUsed[k] = true
			local m = builder(self.folder, self:wallCF(slot, height or 6.5), self.rng)
			table.insert(placed, m)
			table.insert(self.room.props, m)
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
				table.insert(self.room.props, Props.box(self.folder, CFrame.new(pos), self.rng))
			end
		end
		count -= 1
	end
end

function Ctx:pipesAlongCeiling(count: number, color: Color3?)
	local room = self.room
	local y = self.y + CH - 0.8
	for i = 1, count do
		local offset = (i - 1) * 0.9 + 1
		if (room.maxX - room.minX) >= (room.maxZ - room.minZ) then
			local z = room.minZ * CELL + offset
			Props.pipe(self.folder, Layout.Origin + Vector3.new(room.minX * CELL, y - i * 0.3, z), Layout.Origin + Vector3.new((room.maxX + 1) * CELL, y - i * 0.3, z), 0.5 + (i % 2) * 0.3, color)
		else
			local x = room.minX * CELL + offset
			Props.pipe(self.folder, Layout.Origin + Vector3.new(x, y - i * 0.3, room.minZ * CELL), Layout.Origin + Vector3.new(x, y - i * 0.3, (room.maxZ + 1) * CELL), 0.5 + (i % 2) * 0.3, color)
		end
	end
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
	for _, c in self.room.cells do
		if not self.used[key(c.x, c.z)] then
			table.insert(self.room.floorSpots, self:cellPos(c.x, c.z))
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
	for _, d in self.folder:GetDescendants() do
		if d:IsA("Attachment") and d:HasTag("ItemSpot") then
			table.insert(itemSpots, d.WorldCFrame)
		end
	end
	for _, slot in self:wallSlots() do
		table.insert(itemSpots, CFrame.new(slot.face - slot.dir * 1.2 + Vector3.new(0, 0.05, 0)))
	end
	self.room.itemSpots = itemSpots
end

------------------------------------------------------------------------------------
-- Shared dressing
------------------------------------------------------------------------------------

local function painting(folder, cf, rng)
	return Props.painting(folder, cf, rng)
end
local function photo(folder, cf, rng)
	return Props.photo(folder, cf, rng)
end
local function clock(folder, cf, rng)
	return Props.clock(folder, cf, rng)
end

local function deskWithChair(ctx)
	return function(folder, cf, rng)
		local desk = Props.desk(folder, cf, rng)
		if rng:Chance(0.8) then
			Props.officeChair(folder, cf * CFrame.new(rng:Number(-0.6, 0.6), 0, -2.6) * CFrame.Angles(0, math.rad(180 + rng:Number(-30, 30)), 0), rng)
		end
		return desk
	end
end

local KINDS = {}

function KINDS.office(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(Props.filingCabinet, 2.2, false, rng:Int(2, 3), nil, false)
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, rng:Int(1, 2))
	ctx:placeCenter(deskWithChair(ctx), rng:Int(1, 2))
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, 1.6, false, 1)
	ctx:placeAgainstWall(Props.trashBin, 1.3, false, 1)
	ctx:decor(painting, 1)
	ctx:decor(clock, 1, 8.5)
	ctx:decor(photo, rng:Int(0, 1), 6)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, nil)
	end, 1, 6)
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
		for i = 1, r:Int(1, 3) do
			Props.box(f, cf * CFrame.new(r:Number(-2, 2), 3.12, r:Number(-0.6, 0.6)), r, Vector3.new(1.4, 0.9 + i * 0.1, 1.2))
		end
		return t
	end, 1)
	ctx:scatter("box", rng:Int(2, 4))
	ctx:scatter("papers", 4)
	ctx:decor(clock, 1, 8.5)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "OUTGOING", 2.6, 0.7, "paper")
	end, 1, 6)
	ctx:dust()
end

function KINDS.storage(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(Props.metalShelf, 2, true, rng:Int(3, 4), nil, true)
	ctx:placeCenter(Props.crate, rng:Int(1, 2))
	ctx:placeCenter(Props.pallet, 1)
	ctx:placeAgainstWall(Props.barrel, 2.4, false, rng:Int(1, 2))
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.ladder(f, cf * CFrame.new(0, 0, 0.2))
	end, 1.5, false, 1, nil, true)
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
	ctx:decor(painting, math.max(2, length // 8), 6.5, true)
	ctx:decor(photo, math.max(1, length // 12), 6, true)
	ctx:decor(clock, 1, 9, true)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, if room.floorId == "G" then "NOTICE\nThe building will be\nclosed for renovation.\nDo not use the\nbasement stairs\nafter 9 PM." else nil)
	end, 1, 6, true)
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
		local back = cf.Position - cf.LookVector * 0.9
		local mirrorCF = CFrame.lookAt(back + Vector3.new(0, 6.6, 0), back + Vector3.new(0, 6.6, 0) + cf.LookVector)
		local mirror = Props.mirror(ctx.folder, mirrorCF, rng, 2.6, 3.4)
		table.insert(room.props, mirror)
	end
	ctx:decor(function(f, cf, r)
		return Props.handDryer(f, cf)
	end, 1, 4.5)
	ctx:scatter("puddle", rng:Int(1, 2))
	ctx:scatter("stain", 1)
	ctx:dust(1.5)
end

function KINDS.breakroom(ctx)
	ctx:placeAgainstWall(function(f, cf, r)
		local counter = Props.counter(f, cf, r, 8)
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
			local a = math.rad(i * 90 + r:Number(-20, 20))
			Props.woodChair(f, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.6) * CFrame.Angles(0, math.rad(180), 0), r)
		end
		return t
	end, 2)
	ctx:decor(clock, 1, 8.5)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, "KITCHEN RULES\n1. Label your food\n2. Clean the microwave\n3. Do not leave anyone\nalone in the basement")
	end, 1, 6)
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
	end, 1)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, 1.6, false, 3)
	ctx:placeAgainstWall(Props.sofa, 2.6, true, 1)
	ctx:decor(painting, 3, 7)
	ctx:decor(clock, 1, 9.5)
	ctx:decor(photo, 1, 6)
	-- a rug
	Build.detail(ctx.folder, "Rug", Vector3.new(18, 0.05, 12), CFrame.new(room.center + Vector3.new(0, 0.03, 6)), Color3.fromRGB(70, 46, 40), M.Fabric)
	-- the elevator: out of order forever
	local slots = ctx:wallSlots(true)
	for _, slot in slots do
		if slot.dx == -1 and slot.z == room.minZ + 6 then
			local cf = ctx:wallCF(slot, 0)
			local elev = Build.model(ctx.folder, "Elevator", cf)
			Build.part(elev, "Frame", Vector3.new(6, 10, 0.4), cf * CFrame.new(0, 5, -0.2), Color3.fromRGB(90, 84, 70), M.Metal)
			Build.part(elev, "DoorL", Vector3.new(2.6, 9, 0.3), cf * CFrame.new(-1.32, 4.6, -0.45), Color3.fromRGB(110, 108, 100), M.Metal)
			Build.part(elev, "DoorR", Vector3.new(2.6, 9, 0.3), cf * CFrame.new(1.32, 4.6, -0.45), Color3.fromRGB(110, 108, 100), M.Metal)
			Props.sign(elev, cf * CFrame.new(0, 3.6, -0.65), "OUT OF ORDER", 2.6, 0.9, "paper")
			ctx.decorUsed[(slot.z * 10000 + slot.x) .. "|" .. slot.dx .. "|" .. slot.dz] = true
			break
		end
	end
	ctx:scatter("papers", 3)
	ctx:scatter("stain", 2)
	ctx:dust(5)
end

function KINDS.vestibule(ctx)
	Build.detail(ctx.folder, "Mat", Vector3.new(8, 0.06, 4), CFrame.new(ctx.room.center + Vector3.new(0, 0.03, 2)), Color3.fromRGB(40, 36, 32), M.Fabric)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "VISITORS MUST SIGN IN AT RECEPTION", 5, 0.9, "brass")
	end, 1, 7.5)
	ctx:placeAgainstWall(Props.trashBin, 1.3, false, 1)
	ctx:scatter("papers", 2)
	ctx:dust(1)
end

function KINDS.security(ctx)
	ctx:placeAgainstWall(function(f, cf, r)
		local desk = Props.desk(f, cf, r, { monitor = false, lamp = false })
		for i = -1, 1 do
			Props.crt(f, cf * CFrame.new(i * 1.7, 3.3, 0.3) * CFrame.Angles(0, math.rad(180), 0), r)
		end
		Props.officeChair(f, cf * CFrame.new(0, 0, -2.6) * CFrame.Angles(0, math.rad(180), 0), r)
		return desk
	end, 3, true, 1)
	ctx:placeAgainstWall(Props.locker, 1.8, false, 3, nil, true)
	-- the override switch released by the code puzzle
	local slots = ctx:wallSlots()
	for _, slot in slots do
		if ctx:isFree(slot.x, slot.z) then
			ctx:use(slot.x, slot.z)
			local cf = ctx:wallCF(slot, 4.5)
			local m = Build.model(ctx.folder, "SecurityOverride", cf)
			Build.part(m, "Plate", Vector3.new(2.4, 3, 0.3), cf * CFrame.new(0, 0, -0.15), Color3.fromRGB(60, 62, 64), M.Metal, { CanCollide = false })
			local lever = Build.part(m, "Lever", Vector3.new(0.35, 1.4, 0.35), cf * CFrame.new(0, 0.1, -0.5) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(150, 40, 34), M.SmoothPlastic, { CanCollide = false })
			lever:AddTag("Interactable")
			lever:SetAttribute("InteractKind", "Override")
			lever:SetAttribute("Prompt", "Pull override")
			lever:SetAttribute("HoldTime", 1)
			Props.sign(m, cf * CFrame.new(0, 2.1, 0), "EXIT OVERRIDE", 2.4, 0.5, nil)
			m:AddTag("SecurityOverride")
			break
		end
	end
	ctx:decor(clock, 1, 8.5)
	ctx:decor(function(f, cf, r)
		return Props.noticeBoard(f, cf, r, "SHIFT LOG\n03:12 - nothing\n03:14 - nothing\n03:15 - it is standing\nin camera 4 again")
	end, 1, 6)
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
	ctx:placeCenter(Props.forklift, 1)
	ctx:placeCenter(Props.pallet, rng:Int(2, 3))
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
		ctx:placeCenter(Props.symbolCabinet, 1, 0)
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
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, 1)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.ladder(f, cf * CFrame.new(0, 0, 0.2))
	end, 1.5, false, 1, nil, true)
	ctx:scatter("box", 3)
	ctx:scatter("papers", 4)
	ctx:decor(clock, 1, 8.5)
	ctx:dust(5)
end

function KINDS.conference(ctx)
	local rng = ctx.rng
	local room = ctx.room
	local center = room.center
	local len = (room.maxX - room.minX - 2) * CELL
	local t = Props.table(ctx.folder, CFrame.new(center), rng, len, 5)
	table.insert(room.props, t)
	for x = room.minX + 1, room.maxX - 1 do
		for z = room.minZ + 3, room.maxZ - 3 do
			ctx:use(x, z)
		end
	end
	local chairs = math.floor(len / 3.2)
	for i = 0, chairs - 1 do
		local x = -len / 2 + 1.6 + i * 3.2
		for _, side in { -1, 1 } do
			if rng:Chance(0.85) then
				local cf = CFrame.new(center + Vector3.new(x, 0, side * 4)) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
				Props.officeChair(ctx.folder, cf, rng)
			end
		end
	end
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "Q3 REVIEW\n- occupancy: 0\n- incidents: 14\n- missing: ?", 6, 3.4, "paper")
	end, 1, 7)
	ctx:decor(painting, 1)
	ctx:decor(clock, 1, 9)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.plant(f, cf, r, true)
	end, 1.6, false, 2)
	ctx:scatter("papers", 3)
	ctx:dust()
end

function KINDS.quiet(ctx)
	local tableModels = ctx:placeAgainstWall(Props.offeringTable, 2.4, true, 1)
	if #tableModels == 0 then
		ctx:placeCenter(Props.offeringTable, 1, 0)
	end
	ctx:placeCenter(Props.rockingChair, 1)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.bed(f, cf * CFrame.new(0, 0, 0), r)
	end, 7, false, 1)
	for _ = 1, 3 do
		ctx:decor(function(f, cf, r)
			local lines = r:Pick({ "MOMMY\nDADDY\nTHE TALL MAN", "WE PLAY\nDON'T LOOK", "ITS NICE\nWHEN YOU\nWATCH", "1 2 3 4\nCLOSE YOUR EYES" })
			return Props.sign(f, cf, lines, 2.2, 2.2, "paper")
		end, 1, 4.8)
	end
	ctx:decor(clock, 1, 8.5)
	ctx:scatter("papers", 2)
	ctx:dust(2)
end

function KINDS.gallery(ctx)
	ctx:decor(painting, 10, 6.8, true)
	ctx:decor(photo, 2, 5.2, true)
	ctx:placeCenter(Props.bench, 2)
	ctx:placeCenter(function(f, cf, r)
		local m = Build.model(f, "Pedestal", cf)
		Build.part(m, "Base", Vector3.new(1.8, 3.6, 1.8), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(150, 146, 136), M.Marble)
		Build.ball(m, "Bust", 1.4, cf * CFrame.new(0, 4.3, 0), Color3.fromRGB(176, 172, 164), M.Marble)
		m:AddTag("Movable")
		return m
	end, 2)
	ctx:dust(3)
end

function KINDS.infirmary(ctx)
	local rng = ctx.rng
	ctx:placeAgainstWall(function(f, cf, r)
		local bed = Props.bed(f, cf, r)
		Props.curtain(f, cf * CFrame.new(-2.4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 6, r)
		return bed
	end, 7, false, rng:Int(2, 3), function(slot)
		return slot.dz ~= 0
	end)
	ctx:placeAgainstWall(function(f, cf, r)
		return Props.ivStand(f, cf)
	end, 1, false, 2)
	ctx:placeAgainstWall(Props.filingCabinet, 2.2, false, 2)
	ctx:placeCenter(Props.wheelchair, 1)
	ctx:placeAgainstWall(Props.sink, 1.8, false, 1)
	ctx:decor(clock, 1, 8.5)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "PLEASE KEEP YOUR EYES OPEN", 4.2, 0.8, "paper")
	end, 1, 7)
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
	end, 1.6, false, 2)
	ctx:decor(clock, 1, 9)
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
	ctx:placeAgainstWall(deskWithChair(ctx), 3, true, 1)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "AUTHORIZED PERSONNEL ONLY", 4, 0.8, nil)
	end, 1, 7)
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
			return Props.valveWheel(f, cf * CFrame.new(0, 0, -0.4))
		end, 1, rng:Number(4.5, 6))
	end
	ctx:scatter("puddle", rng:Int(3, 5))
	ctx:scatter("stain", 3)
	ctx:dust(4)
end

function KINDS.maintenance(ctx)
	local room = ctx.room
	-- fuse box and breaker panel side by side on the wall facing the door
	local door = room.doors[1]
	local placedFuse, placedBreaker = false, false
	local slots = ctx:wallSlots()
	table.sort(slots, function(a, b)
		local da = door and math.abs(a.x - door.x) + math.abs(a.z - door.z) or 0
		local db = door and math.abs(b.x - door.x) + math.abs(b.z - door.z) or 0
		return da > db
	end)
	for _, slot in slots do
		if not placedFuse and ctx:isFree(slot.x, slot.z) then
			ctx:use(slot.x, slot.z)
			table.insert(room.props, Props.fuseBox(ctx.folder, ctx:wallCF(slot, 5)))
			ctx.decorUsed[(slot.z * 10000 + slot.x) .. "|" .. slot.dx .. "|" .. slot.dz] = true
			placedFuse = true
		elseif placedFuse and not placedBreaker and ctx:isFree(slot.x, slot.z) then
			ctx:use(slot.x, slot.z)
			table.insert(room.props, Props.breakerPanel(ctx.folder, ctx:wallCF(slot, 4.6)))
			ctx.decorUsed[(slot.z * 10000 + slot.x) .. "|" .. slot.dx .. "|" .. slot.dz] = true
			placedBreaker = true
			break
		end
	end
	ctx:placeAgainstWall(Props.workbench, 2.6, true, 1)
	ctx:placeAgainstWall(Props.locker, 1.8, false, 2, nil, true)
	ctx:placeAgainstWall(Props.metalShelf, 2, true, 1, nil, true)
	ctx:placeCenter(Props.crate, 1)
	ctx:pipesAlongCeiling(2)
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "DANGER  HIGH VOLTAGE", 3.6, 0.8, nil)
	end, 1, 8)
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
			local face = door.center - door.passageDir * (CELL / 2 + 0.2) + Vector3.new(0, 11.2, 0)
			local cf = CFrame.lookAt(face, face - door.passageDir)
			table.insert(room.props, Props.closetLamp(ctx.folder, cf, lampColors[index], index))
			local plate = door.center - door.passageDir * (CELL / 2 + 0.2) + Vector3.new(0, 0, 0)
			Props.sign(ctx.folder, CFrame.lookAt(plate + Vector3.new(CELL / 2 + 1.2, 6.5, 0), plate + Vector3.new(CELL / 2 + 1.2, 6.5, 0) - door.passageDir), ({ "I", "II", "III", "IV" })[index], 1, 0.8, "brass")
			ctx.decorUsed[((door.z - 1) * 10000 + door.x) .. "|0|1"] = true
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
	end, 1, 7, true)
	ctx:pipesAlongCeiling(2)
	ctx:scatter("puddle", 2)
	ctx:dust(2)
end

function KINDS.closet(ctx)
	ctx:placeAgainstWall(Props.metalShelf, 2, false, 1, nil, true)
	ctx:scatter("box", 1)
end

function KINDS.secret(ctx)
	local rng = ctx.rng
	local room = ctx.room
	-- a single chair facing the far wall, covered in photographs joined by string
	local center = room.center
	local chairCF = CFrame.lookAt(center, center + Vector3.new(0, 0, 1))
	table.insert(room.props, Props.woodChair(ctx.folder, chairCF, rng))
	local wallZ = (room.maxZ + 1) * CELL - 0.25
	local pins = {}
	for i = 1, 14 do
		local p = Layout.Origin + Vector3.new(rng:Number(room.minX * CELL + 3, (room.maxX + 1) * CELL - 3), ctx.y + rng:Number(3.5, 10), wallZ)
		Build.detail(ctx.folder, "Pinned", Vector3.new(1.4, 1, 0.03), CFrame.lookAt(p, p - Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, math.rad(rng:Number(-15, 15))), Color3.fromRGB(30, 28, 26), M.SmoothPlastic)
		table.insert(pins, p - Vector3.new(0, 0, 0.1))
		if i > 1 and rng:Chance(0.7) then
			local a, b = pins[i - 1], p - Vector3.new(0, 0, 0.1)
			Build.detail(ctx.folder, "String", Vector3.new(0.05, 0.05, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(120, 30, 28), M.Fabric)
		end
	end
	-- the photograph spot (secret item)
	local tablePos = center + Vector3.new(4, 0, -2)
	local t = Props.table(ctx.folder, CFrame.new(tablePos), rng, 3, 2)
	t:SetAttribute("SecretSpot", true)
	table.insert(room.props, t)
	room.secretSpot = CFrame.new(tablePos + Vector3.new(0, 3.2, 0))
	ctx:decor(function(f, cf, r)
		return Props.sign(f, cf, "YOU WERE ALWAYS HERE", 4, 0.8, "paper")
	end, 1, 11.5, true)
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
			Build.detail(ctx.folder, "Chain", Vector3.new(0.1, 2, 0.1), CFrame.new(p), Props.Colors.metal, M.Metal)
			Build.detail(ctx.folder, "Hook", Vector3.new(0.5, 0.15, 0.15), CFrame.new(p - Vector3.new(0, 1.1, 0)), Props.Colors.metal, M.Metal)
		end
	end
	for _, door in room.doors do
		local pos = door.center + Vector3.new(0, -door.center.Y + ctx.y, 0)
		Props.plasticStrips(ctx.folder, CFrame.lookAt(pos, pos + door.passageDir), CELL - 0.4)
	end
	ctx:scatter("puddle", 2)
	ctx:dust(1.5)
end

function KINDS.stairs(ctx)
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
		local spot = room.floorSpots[rng:Int(1, math.max(1, #room.floorSpots))]
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
	placeResidents(map, parent, rng:Derive("residents"))
end

return Furnisher
