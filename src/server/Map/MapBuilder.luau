--[[
	MapBuilder
	Turns the authored Layout into geometry: structural walls, floors, ceilings,
	wall finishes, doors, windows, stairs, light fixtures, exterior areas and the
	pre-built hidden geometry used by environment anomalies. Furnishing is delegated
	to Furnisher. Rebuilt every round from the round seed so each round starts from
	a perfectly clean reality with small deterministic variations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Layout)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local Furnisher = require(script.Parent.Furnisher)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)

local CELL = Layout.Cell
local LH = Layout.LevelHeight
local CH = Layout.CeilingHeight
local DH = Layout.DoorHeight

local M = Enum.Material

local WALL_COLOR = Color3.fromRGB(78, 66, 58)
local STRUCT_COLOR = Color3.fromRGB(60, 60, 60)
local TRIM_COLOR = Color3.fromRGB(52, 40, 30)

local DIRS = {
	{ dx = 1, dz = 0 },
	{ dx = -1, dz = 0 },
	{ dx = 0, dz = 1 },
	{ dx = 0, dz = -1 },
}

local DOOR_CHARS = { D = true, L = true, K = true, P = true, H = true, E = true, X = true }

local MapBuilder = {}

local Map = {}
Map.__index = Map

------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------

local function isRoom(ch: string): boolean
	return Layout.isRoomChar(ch)
end

local function roomIdAt(floor, x: number, z: number): string?
	local ch = Layout.charAt(floor, x, z)
	if isRoom(ch) then
		return floor.id .. "_" .. ch
	elseif ch == "O" then
		return roomIdAt(floor, x, z - 1)
	end
	return nil
end

local function isWalkable(ch: string): boolean
	return isRoom(ch) or ch == "O" or DOOR_CHARS[ch] == true
end

-- Greedy rectangle merge. cells: { [z] = { [x] = key } }. Returns { {x0,z0,x1,z1,key} }.
local function greedy(cells, width: number, height: number)
	local visited = {}
	local rects = {}
	local function get(x, z)
		local row = cells[z]
		return row and row[x]
	end
	local function seen(x, z)
		return visited[z * 10000 + x]
	end
	for z = 0, height - 1 do
		for x = 0, width - 1 do
			local key = get(x, z)
			if key ~= nil and not seen(x, z) then
				local x1 = x
				while x1 + 1 < width and get(x1 + 1, z) == key and not seen(x1 + 1, z) do
					x1 += 1
				end
				local z1 = z
				local canGrow = true
				while canGrow and z1 + 1 < height do
					for xx = x, x1 do
						if get(xx, z1 + 1) ~= key or seen(xx, z1 + 1) then
							canGrow = false
							break
						end
					end
					if canGrow then
						z1 += 1
					end
				end
				for zz = z, z1 do
					for xx = x, x1 do
						visited[zz * 10000 + xx] = true
					end
				end
				table.insert(rects, { x, z, x1, z1, key })
			end
		end
	end
	return rects
end

local function rectCFrame(r, yCenter: number): (CFrame, Vector3)
	local x0, z0, x1, z1 = r[1], r[2], r[3], r[4]
	local sx = (x1 - x0 + 1) * CELL
	local sz = (z1 - z0 + 1) * CELL
	local cx = x0 * CELL + sx / 2
	local cz = z0 * CELL + sz / 2
	return CFrame.new(Layout.Origin + Vector3.new(cx, yCenter, cz)), Vector3.new(sx, 0, sz)
end

local function gridSize(floor)
	local w = 0
	for _, row in floor.grid do
		w = math.max(w, #row)
	end
	return w, #floor.grid
end

------------------------------------------------------------------------------------
-- Map object API
------------------------------------------------------------------------------------

function Map:floorAtY(y: number)
	local best, bestD = nil, math.huge
	for _, floor in Layout.Floors do
		if y >= floor.y - 2 and y <= floor.y + LH - 1 then
			local d = math.abs(y - (floor.y + 3))
			if d < bestD then
				best, bestD = floor, d
			end
		end
	end
	return best
end

function Map:roomAt(position: Vector3)
	local floor = self:floorAtY(position.Y)
	if not floor then
		return nil
	end
	local local_ = position - Layout.Origin
	local x = math.floor(local_.X / CELL)
	local z = math.floor(local_.Z / CELL)
	local id = roomIdAt(floor, x, z)
	if id then
		return self.Rooms[id]
	end
	-- standing in a doorway: pick an adjacent room
	local ch = Layout.charAt(floor, x, z)
	if DOOR_CHARS[ch] then
		for _, d in DIRS do
			local nid = roomIdAt(floor, x + d.dx, z + d.dz)
			if nid then
				return self.Rooms[nid]
			end
		end
	end
	return nil
end

function Map:getRoom(id: string)
	return self.Rooms[id]
end

function Map:roomsInZone(zone: string)
	local list = {}
	for _, room in self.Rooms do
		if room.zone == zone then
			table.insert(list, room)
		end
	end
	return list
end

function Map:isInsideBuilding(position: Vector3): boolean
	return self:roomAt(position) ~= nil
end

------------------------------------------------------------------------------------
-- Build steps
------------------------------------------------------------------------------------

local function buildSlabs(map, floor, folder, belowFloor)
	local width, height = gridSize(floor)
	local sw = Layout.Stairwell
	local cells = {}
	for z = 0, height - 1 do
		cells[z] = {}
		for x = 0, width - 1 do
			local ch = Layout.charAt(floor, x, z)
			if ch ~= " " then
				local key = "_struct"
				local rid = roomIdAt(floor, x, z)
				if rid then
					key = rid
				end
				-- stairwell hole above the flights of the level below
				local inStair = x >= sw.x0 and x <= sw.x1 and z >= sw.z0 and z <= sw.z1
				local isLanding = z > sw.z1 - sw.landingRows
				if inStair and belowFloor and not isLanding then
					key = nil
				end
				cells[z][x] = key
			end
		end
	end
	for _, r in greedy(cells, width, height) do
		local key = r[5]
		local cf, size = rectCFrame(r, floor.y - 0.5)
		local material, color = M.Concrete, STRUCT_COLOR
		local room = map.Rooms[key]
		if room then
			local style = Layout.Styles[room.style]
			material, color = style.floor[1], style.floor[2]
		end
		local part = Build.part(folder, "Floor", Vector3.new(size.X, 1, size.Z), cf, color, material)
		if room then
			part:SetAttribute("Room", key)
			table.insert(room.floorParts, part)
		end
	end
end

local function buildCeilings(map, floor, folder, isTop)
	local width, height = gridSize(floor)
	local sw = Layout.Stairwell
	local cells = {}
	for z = 0, height - 1 do
		cells[z] = {}
		for x = 0, width - 1 do
			local rid = roomIdAt(floor, x, z)
			if rid then
				local room = map.Rooms[rid]
				local inStair = x >= sw.x0 and x <= sw.x1 and z >= sw.z0 and z <= sw.z1
				if not (inStair and not isTop) and not (room and room.noCeiling) then
					cells[z][x] = rid
				end
			end
		end
	end
	for _, r in greedy(cells, width, height) do
		local room = map.Rooms[r[5]]
		local style = Layout.Styles[room.style]
		local cf, size = rectCFrame(r, floor.y + CH + 0.5)
		local part = Build.part(folder, "Ceiling", Vector3.new(size.X, 1, size.Z), cf, style.ceiling[2], style.ceiling[1])
		part:SetAttribute("Room", room.id)
		table.insert(room.ceilingParts, part)
	end
end

local function buildWalls(map, floor, folder, capCells)
	local width, height = gridSize(floor)
	local cells = {}
	for z = 0, height - 1 do
		cells[z] = {}
		for x = 0, width - 1 do
			local ch = Layout.charAt(floor, x, z)
			if ch == "#" and not capCells[z * 10000 + x] then
				cells[z][x] = "#"
			end
		end
	end
	local wallMat = if floor.id == "B" then M.Concrete else M.Brick
	local wallCol = if floor.id == "B" then Color3.fromRGB(66, 66, 64) else WALL_COLOR
	for _, r in greedy(cells, width, height) do
		local cf, size = rectCFrame(r, floor.y + LH / 2)
		Build.part(folder, "Wall", Vector3.new(size.X, LH, size.Z), cf, wallCol, wallMat)
	end
end

-- Interior wall finishes: baseboard + wainscot + upper wall, merged along straight runs.
local function buildSkins(map, floor, folder, rng, capCells)
	local width, height = gridSize(floor)
	local runs = {}
	for z = 0, height - 1 do
		for x = 0, width - 1 do
			local rid = roomIdAt(floor, x, z)
			if rid then
				for _, d in DIRS do
					local nch = Layout.charAt(floor, x + d.dx, z + d.dz)
					local cls = nil
					if capCells[(z + d.dz) * 10000 + (x + d.dx)] then
						nch = " "
					end
					if nch == "#" then
						cls = "wall"
					elseif nch == "W" then
						cls = "window"
					elseif DOOR_CHARS[nch] then
						cls = "door"
					end
					if cls then
						local planeKey, along
						if d.dx ~= 0 then
							planeKey = string.format("%s|x|%d|%d", rid, d.dx, x + (if d.dx > 0 then 1 else 0))
							along = z
						else
							planeKey = string.format("%s|z|%d|%d", rid, d.dz, z + (if d.dz > 0 then 1 else 0))
							along = x
						end
						runs[planeKey] = runs[planeKey] or { rid = rid, d = d, cells = {} }
						runs[planeKey].cells[along] = cls
						runs[planeKey].plane = if d.dx ~= 0 then x + (if d.dx > 0 then 1 else 0) else z + (if d.dz > 0 then 1 else 0)
					end
				end
			end
		end
	end

	for _, run in runs do
		local room = map.Rooms[run.rid]
		local style = Layout.Styles[room.style]
		local lowerH = style.lower[3]
		local d = run.d
		-- sort along indices
		local idx = {}
		for a in run.cells do
			table.insert(idx, a)
		end
		table.sort(idx)
		-- split into segments of identical class & contiguous index
		local segments = {}
		local cur = nil
		for _, a in idx do
			local cls = run.cells[a]
			if cur and cur.cls == cls and cls == "wall" and a == cur.last + 1 then
				cur.last = a
			else
				cur = { cls = cls, first = a, last = a }
				table.insert(segments, cur)
			end
		end
		local normal = Vector3.new(-d.dx, 0, -d.dz) -- into the room
		for _, seg in segments do
			local len = (seg.last - seg.first + 1) * CELL
			local mid = (seg.first + seg.last + 1) / 2 * CELL
			local planePos = run.plane * CELL
			local base: Vector3
			if d.dx ~= 0 then
				base = Layout.Origin + Vector3.new(planePos, floor.y, mid)
			else
				base = Layout.Origin + Vector3.new(mid, floor.y, planePos)
			end
			-- frame: X along the wall, Y up, Z = -normal (so LookVector = normal into the room)
			local look = normal
			local cfBase = CFrame.lookAt(base, base + look)
			local function band(y0, y1, mat, col, thick, name)
				if y1 - y0 <= 0.01 then
					return
				end
				local t = thick or 0.2
				local p = Build.part(folder, name or "Skin", Vector3.new(len, y1 - y0, t), cfBase * CFrame.new(0, (y0 + y1) / 2, -t / 2), col, mat)
				p.CastShadow = false
				p:SetAttribute("Room", room.id)
				table.insert(room.wallParts, p)
				return p
			end
			local upperMat, upperCol = style.upper[1], Build.vary(style.upper[2], rng, 0.025)
			local lowerMat, lowerCol = style.lower[1], style.lower[2]
			if seg.cls == "wall" then
				band(0, lowerH, lowerMat, lowerCol)
				band(lowerH, CH, upperMat, upperCol)
				local bb = band(0, 0.5, M.Wood, TRIM_COLOR, 0.35, "Baseboard")
				if bb then
					bb.CanCollide = false
				end
				if lowerH > 1.5 and lowerH < 9 then
					local rail = band(lowerH - 0.08, lowerH + 0.12, M.Wood, TRIM_COLOR, 0.32, "Rail")
					if rail then
						rail.CanCollide = false
					end
				end
				-- record a blank wall spot for anomalies (extra doors, shadows...)
				if len >= CELL * 2 then
					for a = seg.first, seg.last do
						local along = (a + 0.5) * CELL
						local p = if d.dx ~= 0 then Layout.Origin + Vector3.new(planePos, floor.y, along) else Layout.Origin + Vector3.new(along, floor.y, planePos)
						table.insert(room.wallSpots, { cframe = CFrame.lookAt(p, p + look), length = len })
					end
				end
			elseif seg.cls == "window" then
				band(0, math.min(lowerH, Layout.WindowSill), lowerMat, lowerCol)
				if lowerH < Layout.WindowSill then
					band(lowerH, Layout.WindowSill, upperMat, upperCol)
				end
				band(Layout.WindowTop, CH, upperMat, upperCol)
				-- window side reveals are handled by the window prop
			elseif seg.cls == "door" then
				band(DH, CH, upperMat, upperCol)
			end
		end
	end
end

local function makeDoorModel(map, floor, folder, x: number, z: number, ch: string, rng)
	local center = Layout.cellToWorld(floor.y, x, z)
	local leftOpen = isWalkable(Layout.charAt(floor, x - 1, z)) and isWalkable(Layout.charAt(floor, x + 1, z))
	-- passage axis: along X if both X neighbours are walkable
	local passageX = leftOpen and not DOOR_CHARS[Layout.charAt(floor, x - 1, z)]
	if ch == "E" or ch == "X" then
		passageX = isRoom(Layout.charAt(floor, x - 1, z)) or isRoom(Layout.charAt(floor, x + 1, z))
	end
	local passageDir = if passageX then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local sideDir = if passageX then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)

	local roomA = roomIdAt(floor, x - (if passageX then 1 else 0), z - (if passageX then 0 else 1))
	local roomB = roomIdAt(floor, x + (if passageX then 1 else 0), z + (if passageX then 0 else 1))

	-- lintel above the opening
	Build.part(folder, "Lintel", Vector3.new(CELL, LH - DH, CELL), CFrame.new(center + Vector3.new(0, DH + (LH - DH) / 2, 0)), if floor.id == "B" then Color3.fromRGB(66, 66, 64) else WALL_COLOR, if floor.id == "B" then M.Concrete else M.Brick)

	if ch == "E" or ch == "X" then
		-- exterior openings are built as part of the entrance / exit set pieces
		return nil, center, passageDir, roomA, roomB
	end

	-- jamb liners & casings
	local frameCF = CFrame.lookAt(center, center + passageDir) -- -Z = passage direction
	local trim = TRIM_COLOR
	for _, s in { -1, 1 } do
		Build.part(folder, "Jamb", Vector3.new(0.3, DH, CELL), frameCF * CFrame.new(s * (CELL / 2 - 0.15), DH / 2, 0), trim, M.Wood, { CanCollide = true })
		for _, face in { -1, 1 } do
			Build.detail(folder, "Casing", Vector3.new(0.45, DH + 0.4, 0.3), frameCF * CFrame.new(s * (CELL / 2 + 0.1), (DH + 0.4) / 2, face * (CELL / 2 + 0.12)), trim, M.Wood)
		end
	end
	Build.part(folder, "Head", Vector3.new(CELL, 0.3, CELL), frameCF * CFrame.new(0, DH - 0.15, 0), trim, M.Wood)
	for _, face in { -1, 1 } do
		Build.detail(folder, "Casing", Vector3.new(CELL + 0.6, 0.45, 0.3), frameCF * CFrame.new(0, DH + 0.2, face * (CELL / 2 + 0.12)), trim, M.Wood)
	end
	Build.detail(folder, "Threshold", Vector3.new(CELL - 0.6, 0.08, CELL), frameCF * CFrame.new(0, 0.04, 0), Color3.fromRGB(70, 56, 42), M.Wood)

	if ch == "H" then
		-- boarded passage: a wall of planks that a crowbar can pry loose
		local boards = Build.model(folder, "BoardedPassage", frameCF)
		local blocker = Build.part(boards, "Blocker", Vector3.new(CELL - 0.6, DH - 0.3, 0.6), frameCF * CFrame.new(0, (DH - 0.3) / 2, -1.2), Color3.fromRGB(50, 40, 32), M.WoodPlanks)
		for i = 0, 5 do
			Build.part(boards, "Plank", Vector3.new(CELL + 0.2, 0.9, 0.25), frameCF * CFrame.new(0, 0.9 + i * 1.5, -1.6) * CFrame.Angles(0, 0, math.rad(rng:Number(-14, 14))), Build.vary(Props.Colors.woodLight, rng, 0.1), M.WoodPlanks, { CanCollide = false })
		end
		blocker:AddTag("Interactable")
		blocker:SetAttribute("InteractKind", "Boards")
		blocker:SetAttribute("Prompt", "Pry boards")
		blocker:SetAttribute("HoldTime", 2)
		boards:AddTag("BoardedPassage")
		return boards, center, passageDir, roomA, roomB
	end

	-- the door itself
	local doorModel = Build.model(folder, "Door")
	-- choose the side the door swings to: into the non-corridor room
	-- +1 swings into roomA, -1 into roomB. Doors never swing out into corridors.
	local swingSign = 1
	local roomARec = roomA and map.Rooms[roomA]
	if roomARec and roomARec.kind == "corridor" and roomB then
		swingSign = -1
	end
	local hingeSide = if rng:Chance(0.5) then 1 else -1
	local panelW, panelH = CELL - 0.7, DH - 0.4
	local closedCF = frameCF * CFrame.new(0, panelH / 2 + 0.05, 0)
	local hinge = frameCF * CFrame.new(hingeSide * panelW / 2, 0, 0)
	-- open: rotate around hinge so panel swings toward the swing side
	local angle = math.rad(92) * hingeSide * swingSign
	local openCF = hinge * CFrame.Angles(0, angle, 0) * CFrame.new(-hingeSide * panelW / 2, panelH / 2 + 0.05, 0)

	local woodCol = Build.vary(rng:Pick({ Color3.fromRGB(72, 54, 40), Color3.fromRGB(96, 80, 62), Color3.fromRGB(64, 58, 52) }), rng, 0.04)
	local mat = M.Wood
	if ch == "P" then
		woodCol = Color3.fromRGB(70, 72, 70)
		mat = M.Metal
	elseif floor.id == "B" then
		woodCol = Build.vary(Color3.fromRGB(78, 80, 78), rng, 0.04)
		mat = M.Metal
	end
	local panel = Build.part(doorModel, "Panel", Vector3.new(panelW, panelH, 0.3), closedCF, woodCol, mat)
	panel.CastShadow = true
	-- details move with the panel (welded via relative offsets in DoorService)
	local handle1 = Build.detail(doorModel, "Handle", Vector3.new(0.5, 0.15, 0.15), closedCF * CFrame.new(-hingeSide * (panelW / 2 - 0.45), -0.6, -0.25), Props.Colors.metal, M.Metal)
	local handle2 = Build.detail(doorModel, "Handle", Vector3.new(0.5, 0.15, 0.15), closedCF * CFrame.new(-hingeSide * (panelW / 2 - 0.45), -0.6, 0.25), Props.Colors.metal, M.Metal)
	local inset = Build.detail(doorModel, "Inset", Vector3.new(panelW - 1, panelH * 0.4, 0.34), closedCF * CFrame.new(0, panelH * 0.18, 0), woodCol:Lerp(Color3.new(0, 0, 0), 0.12), mat)
	local inset2 = Build.detail(doorModel, "Inset", Vector3.new(panelW - 1, panelH * 0.3, 0.34), closedCF * CFrame.new(0, -panelH * 0.25, 0), woodCol:Lerp(Color3.new(0, 0, 0), 0.12), mat)
	if ch == "K" then
		Props.keypad(folder, CFrame.lookAt(center + sideDir * (CELL / 2 + 0.9) - passageDir * (CELL / 2) + Vector3.new(0, 4.5, 0), center + sideDir * (CELL / 2 + 0.9) - passageDir * (CELL / 2 + 1) + Vector3.new(0, 4.5, 0)))
	end
	doorModel.PrimaryPart = panel
	-- offsets of child parts relative to the panel for client animation
	for _, p in { handle1, handle2, inset, inset2 } do
		p:SetAttribute("Offset", panel.CFrame:ToObjectSpace(p.CFrame))
	end
	doorModel:SetAttribute("ClosedCFrame", closedCF)
	doorModel:SetAttribute("OpenCFrame", openCF)
	doorModel:SetAttribute("Open", false)
	doorModel:SetAttribute("RoomA", roomA or "")
	doorModel:SetAttribute("RoomB", roomB or "")
	doorModel:SetAttribute("Floor", floor.id)
	local kind = "normal"
	local key = nil
	if ch == "L" then
		kind = "locked"
		local lockRoom = (roomA and map.Rooms[roomA] and map.Rooms[roomA].lockKey and roomA) or roomB
		key = lockRoom and map.Rooms[lockRoom] and map.Rooms[lockRoom].lockKey
	elseif ch == "K" then
		kind = "keypad"
	elseif ch == "P" then
		kind = "closet"
		local closetRoom = (roomB and map.Rooms[roomB] and map.Rooms[roomB].closet and roomB) or roomA
		doorModel:SetAttribute("Closet", closetRoom and map.Rooms[closetRoom].closet or 0)
	end
	doorModel:SetAttribute("Kind", kind)
	doorModel:SetAttribute("Locked", kind == "locked" or kind == "keypad" or kind == "closet")
	if key then
		doorModel:SetAttribute("KeyId", key)
	end
	panel:AddTag("Interactable")
	panel:SetAttribute("InteractKind", "Door")
	panel:SetAttribute("Prompt", "Open")
	doorModel:AddTag("Door")
	return doorModel, center, passageDir, roomA, roomB
end

local function buildDoorsAndWindows(map, floor, folder, rng)
	local width, height = gridSize(floor)
	for z = 0, height - 1 do
		for x = 0, width - 1 do
			local ch = Layout.charAt(floor, x, z)
			if DOOR_CHARS[ch] then
				local model, center, passageDir, roomA, roomB = makeDoorModel(map, floor, folder, x, z, ch, rng)
				local record = {
					id = string.format("%s_%d_%d", floor.id, x, z),
					floor = floor.id,
					x = x,
					z = z,
					char = ch,
					model = model,
					center = center,
					passageDir = passageDir,
					roomA = roomA,
					roomB = roomB,
				}
				if model then
					model:SetAttribute("DoorId", record.id)
				end
				table.insert(map.Doors, record)
				map.DoorsById[record.id] = record
				for _, rid in { roomA, roomB } do
					if rid and map.Rooms[rid] then
						table.insert(map.Rooms[rid].doors, record)
					end
				end
				if ch == "E" then
					table.insert(map.EntranceCells, record)
				elseif ch == "X" then
					table.insert(map.ExitCells, record)
				end
			elseif ch == "W" then
				-- sill + head blocks
				local center = Layout.cellToWorld(floor.y, x, z)
				local wallMat = if floor.id == "B" then M.Concrete else M.Brick
				Build.part(folder, "Sill", Vector3.new(CELL, Layout.WindowSill, CELL), CFrame.new(center + Vector3.new(0, Layout.WindowSill / 2, 0)), WALL_COLOR, wallMat)
				Build.part(folder, "WindowHead", Vector3.new(CELL, LH - Layout.WindowTop, CELL), CFrame.new(center + Vector3.new(0, Layout.WindowTop + (LH - Layout.WindowTop) / 2, 0)), WALL_COLOR, wallMat)
				-- find the room side
				for _, d in DIRS do
					local rid = roomIdAt(floor, x + d.dx, z + d.dz)
					if rid then
						local inward = Vector3.new(d.dx, 0, d.dz)
						local facePos = center + inward * (CELL / 2) + Vector3.new(0, (Layout.WindowSill + Layout.WindowTop) / 2, 0)
						local cf = CFrame.lookAt(facePos, facePos + inward)
						local win = Props.window(folder, cf, rng, true)
						win:SetAttribute("Room", rid)
						table.insert(map.Rooms[rid].windows, win)
						-- side reveals inside the opening
						local revealCF = CFrame.lookAt(center + Vector3.new(0, (Layout.WindowSill + Layout.WindowTop) / 2, 0), center + Vector3.new(0, (Layout.WindowSill + Layout.WindowTop) / 2, 0) + inward)
						for _, s in { -1, 1 } do
							Build.detail(folder, "Reveal", Vector3.new(0.3, Layout.WindowTop - Layout.WindowSill, CELL), revealCF * CFrame.new(s * (CELL / 2 - 0.15), 0, 0), Color3.fromRGB(80, 72, 62), M.Wood)
						end
						-- moonlight from outside through the gaps between the boards
						-- every window lets some of the night in: a soft wash, and on some a
						-- sharp shaft through the boards (only those cast shadows, for speed)
						map.WindowCount = (map.WindowCount or 0) + 1
						local shaft = rng:Chance(0.5)
						do
							local outside = center - inward * (CELL / 2 + 7) + Vector3.new(0, 9, 0)
							local holder = Build.part(folder, "Moon", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(outside, facePos - Vector3.new(0, 4, 0) + inward * 6), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
							local spot = Build.light(holder, "SpotLight", { Brightness = if shaft then 1.9 else 1.1, Range = if shaft then 36 else 28, Angle = if shaft then 30 else 60, Face = Enum.NormalId.Front, Color = Color3.fromRGB(150, 172, 210), Shadows = shaft and map.WindowCount % 2 == 0 })
							spot:AddTag("Moonlight")
							-- soft visible shaft
							if not shaft then
								spot:SetAttribute("Wash", true)
							end
							local a0 = Instance.new("Attachment")
							a0.Parent = holder
							local target = Build.part(folder, "MoonTarget", Vector3.new(0.2, 0.2, 0.2), CFrame.new(facePos + inward * 9 - Vector3.new(0, (Layout.WindowSill + Layout.WindowTop) / 2 - 0.2, 0)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
							local a1 = Instance.new("Attachment")
							a1.Parent = target
							local beam = Instance.new("Beam")
							beam.Attachment0 = a0
							beam.Attachment1 = a1
							beam.Width0 = 3
							beam.Width1 = 6
							beam.FaceCamera = true
							beam.LightEmission = 0.6
							beam.LightInfluence = 0
							beam.Color = ColorSequence.new(Color3.fromRGB(170, 190, 220))
							beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.93), NumberSequenceKeypoint.new(1, 1) })
							beam.Segments = 1
							beam.Enabled = shaft
							beam.Parent = holder
						end
						break
					end
				end
			end
		end
	end
end

local function buildStairs(map, floor, folder, hasAbove: boolean)
	local sw = Layout.Stairwell
	local y = floor.y
	local x0 = sw.x0 * CELL
	local xMid = (sw.x0 + 2) * CELL
	local x1 = (sw.x1 + 1) * CELL
	local zMidTop = sw.z0 * CELL -- north edge
	local zMidBottom = (sw.z0 + sw.midRows) * CELL
	local zLanding = (sw.z1 + 1 - sw.landingRows) * CELL
	local style = Layout.Styles.stairs
	local O = Layout.Origin
	local stepCol, stepMat = Color3.fromRGB(88, 88, 86), M.Concrete
	local noseCol = Color3.fromRGB(60, 60, 58)

	if hasAbove then
		local rise = LH / 2
		local run = zLanding - zMidBottom
		local steps = 12
		local stepRise = rise / steps
		local stepRun = run / steps
		local function flight(xa, xb, zStart, zEnd, yStart)
			local dirZ = if zEnd < zStart then -1 else 1
			local w = xb - xa
			local cx = (xa + xb) / 2
			for i = 0, steps - 1 do
				local top = yStart + (i + 1) * stepRise
				local zc = zStart + dirZ * (i + 0.5) * stepRun
				local h = math.max(stepRise, 1)
				local p = Build.part(folder, "Step", Vector3.new(w - 0.4, h, stepRun), CFrame.new(O + Vector3.new(cx, top - h / 2, zc)), stepCol, stepMat, { CanCollide = false })
				p.CastShadow = true
				Build.detail(folder, "Nosing", Vector3.new(w - 0.4, 0.08, 0.3), CFrame.new(O + Vector3.new(cx, top + 0.02, zc - dirZ * (stepRun / 2 - 0.15))), noseCol, M.Metal)
			end
			-- smooth invisible ramp for walking
			local len = math.sqrt(run * run + rise * rise)
			local midY = yStart + rise / 2
			local midZ = (zStart + zEnd) / 2
			local slope = math.atan2(rise, run)
			local rampCF
			if dirZ > 0 then
				rampCF = CFrame.new(O + Vector3.new(cx, midY, midZ)) * CFrame.Angles(-slope, 0, 0)
			else
				rampCF = CFrame.new(O + Vector3.new(cx, midY, midZ)) * CFrame.Angles(slope, 0, 0)
			end
			local ramp = Build.part(folder, "Ramp", Vector3.new(w - 0.4, 0.4, len), rampCF * CFrame.new(0, stepRise / 2 - 0.2, 0), Color3.new(), M.SmoothPlastic, { Transparency = 1, CastShadow = false })
			ramp:AddTag("StairRamp")
			-- solid underside
			Build.part(folder, "Stringer", Vector3.new(w - 0.4, 0.8, len), rampCF * CFrame.new(0, -1.1, 0), Color3.fromRGB(70, 70, 68), M.Concrete, { CanCollide = false })
		end
		-- flight 1 (west half): landing -> mid landing, heading north
		flight(x0, xMid, zLanding, zMidBottom, y)
		-- mid landing
		Build.part(folder, "MidLanding", Vector3.new(x1 - x0, 1, zMidBottom - zMidTop), CFrame.new(O + Vector3.new((x0 + x1) / 2, y + rise - 0.5, (zMidTop + zMidBottom) / 2)), stepCol, stepMat)
		-- flight 2 (east half): mid landing -> next floor landing, heading south
		flight(xMid, x1, zMidBottom, zLanding, y + rise)
		-- centre divider wall between the flights
		Build.part(folder, "Divider", Vector3.new(0.8, LH, zLanding - zMidBottom), CFrame.new(O + Vector3.new(xMid, y + LH / 2, (zMidBottom + zLanding) / 2)), style.upper[2], style.upper[1])
		-- handrails along the divider
		for _, s in { -1, 1 } do
			local rx = xMid + s * 0.6
			local rail = Build.detail(folder, "Handrail", Vector3.new(0.15, 0.15, math.sqrt((zLanding - zMidBottom) ^ 2 + rise ^ 2)), CFrame.new(O + Vector3.new(rx, y + (if s < 0 then rise / 2 + 3 else rise * 1.5 + 3), (zMidBottom + zLanding) / 2)) * CFrame.Angles(if s < 0 then math.atan2(rise, zLanding - zMidBottom) else -math.atan2(rise, zLanding - zMidBottom), 0, 0), Props.Colors.metal, M.Metal)
			rail.CanCollide = false
		end
		-- level sign on the mid landing wall
		local signPos = O + Vector3.new((x0 + x1) / 2, y + rise + 6, zMidTop + 0.05)
		Props.sign(folder, CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)), "STAIRS", 4, 0.9, "paper")
	end
	if not hasAbove and floor.level > -1 then
		-- top floor: the west half of the landing looks down into the shaft
		Build.part(folder, "GuardRail", Vector3.new(xMid - x0, 3.4, 0.25), CFrame.new(O + Vector3.new((x0 + xMid) / 2, y + 1.7, zLanding + 0.15)), Props.Colors.metalDark, M.Metal)
		Build.part(folder, "GuardRail", Vector3.new(0.25, 3.4, zLanding - zMidTop), CFrame.new(O + Vector3.new(xMid + 0.5, y + 1.7, (zMidTop + zLanding) / 2)), Props.Colors.metalDark, M.Metal)
	end
	-- floor number painted on the landing wall
	local plate = O + Vector3.new(x0 + 0.05, y + 7, (zLanding + (sw.z1 + 1) * CELL) / 2)
	Props.sign(folder, CFrame.lookAt(plate, plate + Vector3.new(1, 0, 0)), map.Rooms[floor.id .. "_s"].number or floor.id, 2.6, 2, nil)
end

-- Fixtures: lights are controlled client-side through attributes (Mode, Tint, Circuit)
local function addFixture(map, room, folder, position: Vector3, styleName: string, color: Color3, rng, opts)
	opts = opts or {}
	local fixture = Build.model(folder, "Fixture", CFrame.new(position))
	local O = position
	local lampPart
	if styleName == "fluoro" then
		Build.detail(fixture, "Housing", Vector3.new(1.6, 0.35, 4.2), CFrame.new(O + Vector3.new(0, -0.18, 0)), Color3.fromRGB(170, 170, 164), M.Metal)
		lampPart = Build.detail(fixture, "Tube", Vector3.new(0.35, 0.2, 3.8), CFrame.new(O + Vector3.new(0.35, -0.42, 0)), color, M.Neon)
		Build.detail(fixture, "Tube2", Vector3.new(0.35, 0.2, 3.8), CFrame.new(O + Vector3.new(-0.35, -0.42, 0)), color, M.Neon)
		if opts.hanging then
			fixture:PivotTo(CFrame.new(O) * CFrame.Angles(0, 0, math.rad(rng:Number(-12, 12))) * CFrame.new(0, -0.6, 0))
		end
	elseif styleName == "pendant" then
		Build.detail(fixture, "Cord", Vector3.new(0.08, 3, 0.08), CFrame.new(O + Vector3.new(0, -1.5, 0)), Props.Colors.black, M.Rubber)
		Build.detail(fixture, "Shade", Vector3.new(1.8, 0.8, 1.8), CFrame.new(O + Vector3.new(0, -3.2, 0)), Color3.fromRGB(60, 50, 40), M.Metal)
		lampPart = Build.ball(fixture, "Bulb", 0.6, CFrame.new(O + Vector3.new(0, -3.6, 0)), color, M.Neon, { CanCollide = false, CastShadow = false })
	elseif styleName == "cage" then
		Build.detail(fixture, "Mount", Vector3.new(0.8, 0.4, 0.8), CFrame.new(O + Vector3.new(0, -0.2, 0)), Props.Colors.metalDark, M.Metal)
		Build.detail(fixture, "Cage", Vector3.new(0.9, 0.9, 0.9), CFrame.new(O + Vector3.new(0, -0.85, 0)), Props.Colors.metalDark, M.DiamondPlate, { Transparency = 0.5 })
		lampPart = Build.ball(fixture, "Bulb", 0.55, CFrame.new(O + Vector3.new(0, -0.85, 0)), color, M.Neon, { CanCollide = false, CastShadow = false })
	else -- bare bulb
		Build.detail(fixture, "Cord", Vector3.new(0.06, 2, 0.06), CFrame.new(O + Vector3.new(0, -1, 0)), Props.Colors.black, M.Rubber)
		lampPart = Build.ball(fixture, "Bulb", 0.5, CFrame.new(O + Vector3.new(0, -2.2, 0)), color, M.Neon, { CanCollide = false, CastShadow = false })
	end
	local light = Build.light(lampPart, "PointLight", {
		Brightness = opts.brightness or 1.05,
		Range = opts.range or 20,
		Color = color,
		Shadows = opts.shadows == true,
		Enabled = false,
	})
	light.Name = "Light"
	fixture:SetAttribute("Room", room.id)
	fixture:SetAttribute("BaseColor", color)
	fixture:SetAttribute("BaseBrightness", light.Brightness)
	fixture:SetAttribute("Circuit", opts.circuit or "MAIN")
	-- persistent personality of each fixture
	local roll = rng:Number()
	local mode = "on"
	if opts.circuit ~= "EMERGENCY" then
		if roll < 0.16 then
			mode = "dead"
		elseif roll < 0.3 then
			mode = "flicker"
		end
	end
	fixture:SetAttribute("Mode", mode)
	fixture:SetAttribute("Seed", rng:Int(1, 100000))
	fixture:AddTag("Fixture")
	table.insert(room.fixtures, fixture)
	if mode == "dead" then
		lampPart.Color = Color3.fromRGB(40, 40, 38)
		lampPart.Material = M.Glass
	end
	return fixture
end

local function buildRoomLights(map, floor, folder, rng)
	local ceilY = floor.y + CH
	for _, room in map.Rooms do
		if room.floorId == floor.id then
			local style = Layout.Styles[room.style]
			if room.kind == "stairs" then
				local sw = Layout.Stairwell
				local landing = Layout.Origin + Vector3.new((sw.x0 + 2) * CELL, ceilY, (sw.z1 + 1 - sw.landingRows / 2) * CELL)
				addFixture(map, room, folder, landing, "cage", style.lightColor, rng, { circuit = "EMERGENCY", shadows = true, range = 18 })
				if floor.level < 1 then
					local mid = Layout.Origin + Vector3.new((sw.x0 + 2) * CELL, floor.y + LH / 2 + 7, (sw.z0 + 1) * CELL)
					addFixture(map, room, folder, mid, "cage", style.lightColor, rng, { circuit = "MAIN", range = 18 })
				end
			elseif room.kind == "corridor" then
				-- a line of fixtures down the middle of the corridor, every 16 studs
				local index = 0
				for _, c in room.cells do
					if c.z == room.minZ and c.x % 4 == 1 then
						local pos = Layout.cellToWorld(floor.y, c.x, c.z)
						addFixture(map, room, folder, Vector3.new(pos.X, ceilY, pos.Z + CELL / 2), style.light, style.lightColor, rng, {
							circuit = if index % 3 == 0 then "EMERGENCY" else "MAIN",
							shadows = index % 3 == 1,
							hanging = rng:Chance(0.1),
						})
						index += 1
					end
				end
			else
				local placed = 0
				for _, c in room.cells do
					if c.x % 4 == 2 and c.z % 4 == 2 then
						local pos = Layout.cellToWorld(floor.y, c.x, c.z)
						addFixture(map, room, folder, Vector3.new(pos.X, ceilY, pos.Z), style.light, style.lightColor, rng, {
							shadows = placed == 0,
							hanging = rng:Chance(0.08),
						})
						placed += 1
					end
				end
				if placed == 0 then
					local center = room.center
					addFixture(map, room, folder, Vector3.new(center.X, ceilY, center.Z), style.light, style.lightColor, rng, { shadows = true })
				end
			end
		end
	end
end

local function buildRoof(map, folder)
	-- roof slabs where no floor exists above
	for i, floor in Layout.Floors do
		local above = Layout.Floors[i + 1]
		local width, height = gridSize(floor)
		local cells = {}
		for z = 0, height - 1 do
			cells[z] = {}
			for x = 0, width - 1 do
				local ch = Layout.charAt(floor, x, z)
				local aboveCh = if above then Layout.charAt(above, x, z) else " "
				if ch ~= " " and aboveCh == " " then
					cells[z][x] = "roof"
				end
			end
		end
		for _, r in greedy(cells, width, height) do
			local cf, size = rectCFrame(r, floor.y + LH + 0.5)
			Build.part(folder, "Roof", Vector3.new(size.X, 1, size.Z), cf, Color3.fromRGB(40, 40, 42), M.Slate)
		end
	end
end

local function buildExpansions(map, folder, rng)
	local O = Layout.Origin
	for name, exp in Layout.Expansions do
		local floor = Layout.getFloor(exp.floor)
		local y = floor.y
		local group = Build.model(folder, name)
		local capGroup = Build.model(folder, name .. "Cap")
		local style = Layout.Styles.basement
		local sx = (exp.x1 - exp.x0 + 1) * CELL
		local sz = (exp.z1 - exp.z0 + 1) * CELL
		local cx = exp.x0 * CELL + sx / 2
		local cz = exp.z0 * CELL + sz / 2
		Build.part(group, "Floor", Vector3.new(sx, 1, sz), CFrame.new(O + Vector3.new(cx, y - 0.5, cz)), style.floor[2], style.floor[1])
		Build.part(group, "Ceiling", Vector3.new(sx + CELL, 1, sz), CFrame.new(O + Vector3.new(cx + CELL / 2, y + CH + 0.5, cz)), style.ceiling[2], style.ceiling[1])
		-- surrounding walls
		Build.part(group, "WallN", Vector3.new(sx + CELL, LH, CELL), CFrame.new(O + Vector3.new(cx - CELL / 2, y + LH / 2, exp.z0 * CELL - CELL / 2)), Color3.fromRGB(66, 66, 64), M.Concrete)
		Build.part(group, "WallS", Vector3.new(sx + CELL, LH, CELL), CFrame.new(O + Vector3.new(cx - CELL / 2, y + LH / 2, (exp.z1 + 1) * CELL + CELL / 2)), Color3.fromRGB(66, 66, 64), M.Concrete)
		Build.part(group, "WallW", Vector3.new(CELL, LH, sz), CFrame.new(O + Vector3.new(exp.x0 * CELL - CELL / 2, y + LH / 2, cz)), Color3.fromRGB(66, 66, 64), M.Concrete)
		-- interior skins
		for _, side in { { "N", exp.z0 * CELL, 1 }, { "S", (exp.z1 + 1) * CELL, -1 } } do
			Build.part(group, "Skin", Vector3.new(sx + CELL, CH, 0.2), CFrame.new(O + Vector3.new(cx + CELL / 2, y + CH / 2, side[2] + side[3] * 0.1)), style.upper[2], style.upper[1])
		end
		Build.part(group, "Skin", Vector3.new(0.2, CH, sz), CFrame.new(O + Vector3.new(exp.x0 * CELL + 0.1, y + CH / 2, cz)), style.upper[2], style.upper[1])
		-- a dim lamp at the far end, and a lot of nothing
		local lamp = Build.ball(group, "Bulb", 0.5, CFrame.new(O + Vector3.new(exp.x0 * CELL + 3, y + CH - 2, cz)), Color3.fromRGB(255, 200, 150), M.Neon, { CanCollide = false })
		Build.light(lamp, "PointLight", { Brightness = 0.7, Range = 16, Color = Color3.fromRGB(255, 190, 140), Shadows = false })
		for _ = 1, 3 do
			Props.stain(group, CFrame.new(O + Vector3.new(cx + rng:Number(-sx / 3, sx / 3), y, cz + rng:Number(-sz / 3, sz / 3))), rng)
		end
		if name == "CorridorStretch" then
			-- the same door, again, at the far end. It does not open.
			local doorPos = O + Vector3.new(exp.x0 * CELL + 0.3, y, cz)
			local f = CFrame.lookAt(doorPos, doorPos + Vector3.new(1, 0, 0))
			Build.part(group, "FalseDoor", Vector3.new(3.4, 9.6, 0.25), f * CFrame.new(0, 4.85, -0.2), Color3.fromRGB(78, 80, 78), M.Metal)
			Props.roomPlate(group, f * CFrame.new(2.8, 6.5, 0), "B-0")
		end
		Build.hideForReveal(group)
		-- the cap: the wall that is normally there
		local capX = exp.capX
		Build.part(capGroup, "Cap", Vector3.new(CELL, CH, sz), CFrame.new(O + Vector3.new(capX * CELL + CELL / 2, y + CH / 2, cz)), Color3.fromRGB(66, 66, 64), M.Concrete)
		-- the top of the wall stays when the cap opens
		Build.part(folder, "CapTop", Vector3.new(CELL, LH - CH, sz), CFrame.new(O + Vector3.new(capX * CELL + CELL / 2, y + CH + (LH - CH) / 2, cz)), Color3.fromRGB(66, 66, 64), M.Concrete)
		-- the cap's room-facing skin
		Build.part(capGroup, "CapSkin", Vector3.new(0.2, CH, sz), CFrame.new(O + Vector3.new((capX + 1) * CELL + 0.1, y + CH / 2, cz)), style.upper[2], style.upper[1])
		map.Expansions[name] = { group = group, cap = capGroup, def = exp }
	end
end

local function buildShrinkWall(map, folder)
	local room = map.Rooms.G_a
	if not room then
		return
	end
	local style = Layout.Styles[room.style]
	local O = Layout.Origin
	local floor = Layout.getFloor("G")
	local x = 7 * CELL -- wall plane between columns 6 and 7
	local z0, z1 = 1 * CELL, 9 * CELL
	local group = Build.model(folder, "ShrinkWall")
	Build.part(group, "Wall", Vector3.new(1.2, CH, z1 - z0), CFrame.new(O + Vector3.new(x + 0.6, floor.y + CH / 2, (z0 + z1) / 2)), style.upper[2], style.upper[1])
	Build.part(group, "Base", Vector3.new(0.35, 0.5, z1 - z0), CFrame.new(O + Vector3.new(x - 0.15, floor.y + 0.25, (z0 + z1) / 2)), TRIM_COLOR, M.Wood)
	Build.hideForReveal(group)
	map.ShrinkWall = group
end

------------------------------------------------------------------------------------
-- Exterior: courtyard (entrance) and loading yard (exit)
------------------------------------------------------------------------------------

local function buildExterior(map, folder, rng)
	local O = Layout.Origin
	local c = Layout.Courtyard
	local cx0, cz0, cx1, cz1 = c.x0 * CELL, c.z0 * CELL, (c.x1 + 1) * CELL, (c.z1 + 1) * CELL
	-- wide ground plane around the building so the menu camera never sees the void
	-- (four strips that leave the building footprint free so the stairwell shaft stays open)
	local fx0, fz0, fx1, fz1 = 0, 0, 40 * CELL, 30 * CELL
	local gx0, gz0, gx1, gz1 = -140, -150, 300, 280
	local groundCol = Color3.fromRGB(34, 36, 32)
	local function groundStrip(ax, az, bx, bz)
		Build.part(folder, "Ground", Vector3.new(bx - ax, 2, bz - az), CFrame.new(O + Vector3.new((ax + bx) / 2, -1.07, (az + bz) / 2)), groundCol, M.Ground)
	end
	groundStrip(gx0, gz0, gx1, fz0)
	groundStrip(gx0, fz1, gx1, gz1)
	groundStrip(gx0, fz0, fx0, fz1)
	groundStrip(fx1, fz0, gx1, fz1)
	-- courtyard paving
	Build.part(folder, "Courtyard", Vector3.new(cx1 - cx0, 0.4, cz1 - cz0), CFrame.new(O + Vector3.new((cx0 + cx1) / 2, -0.2 + 0.01, (cz0 + cz1) / 2)), Color3.fromRGB(62, 62, 60), M.Pavement)
	-- entrance steps and canopy
	local doorX = 20 * CELL
	local frontZ = 30 * CELL
	for i = 1, 3 do
		Build.part(folder, "Step", Vector3.new(14 - i, 0.25, 1.5), CFrame.new(O + Vector3.new(doorX, -0.125 + 0.25 * (3 - i) + 0.02, frontZ + 1.5 * i - 0.75)), Color3.fromRGB(86, 84, 80), M.Concrete)
	end
	Build.part(folder, "Canopy", Vector3.new(14, 0.6, 7), CFrame.new(O + Vector3.new(doorX, 12, frontZ + 3.5)), Color3.fromRGB(40, 38, 36), M.Metal)
	for _, s in { -1, 1 } do
		Build.part(folder, "Column", Vector3.new(0.8, 12, 0.8), CFrame.new(O + Vector3.new(doorX + s * 6, 6, frontZ + 6.5)), Color3.fromRGB(70, 68, 64), M.Concrete)
	end
	local lampHolder = Build.ball(folder, "EntranceLamp", 0.8, CFrame.new(O + Vector3.new(doorX, 11.2, frontZ + 3)), Color3.fromRGB(255, 220, 170), M.Neon, { CanCollide = false })
	local entLight = Build.light(lampHolder, "PointLight", { Brightness = 1.2, Range = 22, Color = Color3.fromRGB(255, 210, 160), Shadows = true })
	entLight:AddTag("ExteriorLight")
	-- building name over the entrance
	local signPos = O + Vector3.new(doorX, 15.5, frontZ + 0.05)
	local sign = Build.part(folder, "BuildingSign", Vector3.new(22, 2.2, 0.3), CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)) * CFrame.new(0, 0, -0.15), Color3.fromRGB(30, 28, 26), M.Metal)
	local gui = Build.surfaceGui(sign, Enum.NormalId.Front, 30)
	Build.text(gui, { Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1), Text = "THE ASHGROVE BUILDING", Font = Enum.Font.Garamond, TextColor3 = Color3.fromRGB(176, 160, 120) })
	-- entrance doors (double doors, open until the round begins)
	map.EntranceDoors = {}
	for i, rec in map.EntranceCells do
		local center = rec.center
		local side = if i == 1 then -1 else 1
		local door = Build.model(folder, "EntranceDoor" .. i)
		local closed = CFrame.new(center + Vector3.new(0, 4.85, 0))
		local panel = Build.part(door, "Panel", Vector3.new(3.8, 9.7, 0.3), closed, Color3.fromRGB(40, 36, 32), M.Wood)
		local glass = Build.detail(door, "Glass", Vector3.new(2.4, 4, 0.34), closed * CFrame.new(0, 1.8, 0), Color3.fromRGB(40, 50, 56), M.Glass, { Transparency = 0.4 })
		local handle = Build.detail(door, "Handle", Vector3.new(0.2, 2, 0.4), closed * CFrame.new(-side * 1.4, -0.6, 0), Props.Colors.metal, M.Metal)
		for _, d in { glass, handle } do
			d:SetAttribute("Offset", closed:ToObjectSpace(d.CFrame))
		end
		door.PrimaryPart = panel
		local hinge = CFrame.new(center + Vector3.new(side * 1.9, 0, 0))
		local openCF = hinge * CFrame.Angles(0, math.rad(-side * 100), 0) * CFrame.new(-side * 1.9, 4.85, 0)
		door:SetAttribute("ClosedCFrame", closed)
		door:SetAttribute("OpenCFrame", openCF)
		door:SetAttribute("Open", false)
		door:AddTag("SetPieceDoor")
		Build.part(folder, "EntranceHead", Vector3.new(CELL, 0.4, CELL), CFrame.new(center + Vector3.new(0, DH - 0.2, 0)), TRIM_COLOR, M.Wood)
		table.insert(map.EntranceDoors, door)
	end
	-- fence, dead trees and a street lamp
	for x = cx0, cx1, 4 do
		Build.detail(folder, "FencePost", Vector3.new(0.3, 6, 0.3), CFrame.new(O + Vector3.new(x, 3, cz1)), Color3.fromRGB(30, 30, 30), M.Metal)
	end
	Build.detail(folder, "FenceRail", Vector3.new(cx1 - cx0, 0.25, 0.25), CFrame.new(O + Vector3.new((cx0 + cx1) / 2, 5.6, cz1)), Color3.fromRGB(30, 30, 30), M.Metal)
	Build.detail(folder, "FenceRail", Vector3.new(cx1 - cx0, 0.25, 0.25), CFrame.new(O + Vector3.new((cx0 + cx1) / 2, 1.2, cz1)), Color3.fromRGB(30, 30, 30), M.Metal)
	for i = 1, 4 do
		local tx = if i <= 2 then cx0 + 8 + (i - 1) * 14 else cx1 - 8 - (i - 3) * 14
		local tz = cz0 + rng:Number(14, 30)
		local tree = Build.model(folder, "DeadTree")
		local h = rng:Number(10, 16)
		Build.part(tree, "Trunk", Vector3.new(1.2, h, 1.2), CFrame.new(O + Vector3.new(tx, h / 2, tz)) * CFrame.Angles(0, 0, math.rad(rng:Number(-6, 6))), Color3.fromRGB(40, 34, 28), M.Wood)
		for _ = 1, 5 do
			Build.detail(tree, "Branch", Vector3.new(0.4, rng:Number(4, 7), 0.4), CFrame.new(O + Vector3.new(tx, h * rng:Number(0.6, 0.95), tz)) * CFrame.Angles(math.rad(rng:Number(-60, 60)), math.rad(rng:Number(0, 360)), math.rad(rng:Number(25, 60))) * CFrame.new(0, 2.5, 0), Color3.fromRGB(40, 34, 28), M.Wood)
		end
	end
	local poleX = cx1 - 6
	Build.part(folder, "LampPole", Vector3.new(0.6, 18, 0.6), CFrame.new(O + Vector3.new(poleX, 9, cz1 - 6)), Color3.fromRGB(34, 34, 36), M.Metal)
	local streetBulb = Build.part(folder, "StreetLamp", Vector3.new(2.4, 0.5, 1.2), CFrame.new(O + Vector3.new(poleX - 1, 18, cz1 - 6)), Color3.fromRGB(255, 200, 140), M.Neon)
	local street = Build.light(streetBulb, "SpotLight", { Brightness = 2, Range = 40, Angle = 100, Face = Enum.NormalId.Bottom, Color = Color3.fromRGB(255, 190, 130), Shadows = true })
	street:AddTag("ExteriorLight")
	-- spawn points in the courtyard facing the entrance
	map.CourtyardSpawns = {}
	for i = 1, 4 do
		local p = O + Vector3.new(doorX - 6 + (i - 1) * 4, 3, cz1 - 10)
		table.insert(map.CourtyardSpawns, CFrame.lookAt(p, O + Vector3.new(doorX, 3, frontZ)))
	end
	-- rain over the courtyard
	local rainHolder = Build.part(folder, "Rain", Vector3.new(cx1 - cx0, 1, cz1 - cz0 + 10), CFrame.new(O + Vector3.new((cx0 + cx1) / 2, 40, (cz0 + cz1) / 2 + 5)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "RainEmitter"
	rain.Rate = 260
	rain.Lifetime = NumberRange.new(1.2, 1.4)
	rain.Speed = NumberRange.new(42, 50)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(2, 2)
	rain.Size = NumberSequence.new(0.06)
	rain.Squash = NumberSequence.new(4)
	rain.Transparency = NumberSequence.new(0.6)
	rain.Color = ColorSequence.new(Color3.fromRGB(170, 180, 190))
	rain.LightInfluence = 1
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Parent = rainHolder

	-- LOADING YARD (exit side)
	local y = Layout.LoadingYard
	local yx0, yz0, yx1, yz1 = y.x0 * CELL, y.z0 * CELL, (y.x1 + 1) * CELL, (y.z1 + 1) * CELL
	Build.part(folder, "Yard", Vector3.new(yx1 - yx0, 0.4, yz1 - yz0), CFrame.new(O + Vector3.new((yx0 + yx1) / 2, -0.2 + 0.01, (yz0 + yz1) / 2)), Color3.fromRGB(50, 50, 50), M.Asphalt)
	for i = 0, 3 do
		Build.detail(folder, "LineMark", Vector3.new(10, 0.05, 0.4), CFrame.new(O + Vector3.new(yx0 + 14, 0.02, yz0 + 12 + i * 10)), Color3.fromRGB(150, 140, 100), M.SmoothPlastic)
	end
	-- the exit shutter
	local exitDoor = Build.model(folder, "ExitShutter")
	local exitCenter = Vector3.zero
	for _, rec in map.ExitCells do
		exitCenter += rec.center
	end
	exitCenter /= math.max(1, #map.ExitCells)
	local shutterClosed = CFrame.new(exitCenter + Vector3.new(0, 4.9, 0))
	local shutter = Build.part(exitDoor, "Shutter", Vector3.new(1, 9.8, 8), shutterClosed, Color3.fromRGB(86, 90, 88), M.CorrodedMetal)
	for i = 0, 11 do
		local slat = Build.detail(exitDoor, "Slat", Vector3.new(1.1, 0.12, 8), shutterClosed * CFrame.new(0, -4.6 + i * 0.8, 0), Color3.fromRGB(60, 62, 60), M.Metal)
		slat:SetAttribute("Offset", shutterClosed:ToObjectSpace(slat.CFrame))
	end
	exitDoor.PrimaryPart = shutter
	exitDoor:SetAttribute("ClosedCFrame", shutterClosed)
	exitDoor:SetAttribute("OpenCFrame", shutterClosed * CFrame.new(0, 9.2, 0))
	exitDoor:SetAttribute("Open", false)
	exitDoor:SetAttribute("Slow", true)
	exitDoor:AddTag("SetPieceDoor")
	map.ExitShutter = exitDoor
	map.ExitCenter = exitCenter
	-- exit panel beside the shutter (inside the dock)
	local panelPos = exitCenter + Vector3.new(-CELL / 2 - 0.05, 5, -CELL - 2)
	map.ExitPanel = Props.exitPanel(folder, CFrame.lookAt(panelPos, panelPos + Vector3.new(-1, 0, 0)))
	-- escape trigger outside the shutter
	local trigger = Build.part(folder, "EscapeZone", Vector3.new(10, 10, 12), CFrame.new(exitCenter + Vector3.new(CELL / 2 + 8, 5, 0)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	map.EscapeZone = trigger
	-- yard lamp and the open night beyond
	local yardBulb = Build.part(folder, "YardLamp", Vector3.new(2.4, 0.5, 1.2), CFrame.new(O + Vector3.new(yx0 + 26, 20, (yz0 + yz1) / 2)), Color3.fromRGB(230, 236, 255), M.Neon)
	local yardLight = Build.light(yardBulb, "SpotLight", { Brightness = 2.4, Range = 52, Angle = 110, Face = Enum.NormalId.Bottom, Color = Color3.fromRGB(210, 220, 255), Shadows = true })
	yardLight:AddTag("ExteriorLight")
	Build.part(folder, "YardPole", Vector3.new(0.6, 20, 0.6), CFrame.new(O + Vector3.new(yx0 + 27.5, 10, (yz0 + yz1) / 2)), Color3.fromRGB(34, 34, 36), M.Metal)
	-- escape cinematic camera anchor
	map.EscapeCamera = CFrame.lookAt(O + Vector3.new(yx0 + 40, 7, (yz0 + yz1) / 2 + 10), exitCenter + Vector3.new(0, 4, 0))
	for x = yx0, yx1, 4 do
		Build.detail(folder, "FencePost", Vector3.new(0.3, 7, 0.3), CFrame.new(O + Vector3.new(x, 3.5, yz0)), Color3.fromRGB(30, 30, 30), M.Metal)
		Build.detail(folder, "FencePost", Vector3.new(0.3, 7, 0.3), CFrame.new(O + Vector3.new(x, 3.5, yz1)), Color3.fromRGB(30, 30, 30), M.Metal)
	end
	-- invisible boundaries so nobody wanders off into the void
	local function boundary(cf, size)
		Build.part(folder, "Boundary", size, cf, Color3.new(), M.SmoothPlastic, { Transparency = 1, CanQuery = false, CastShadow = false })
	end
	boundary(CFrame.new(O + Vector3.new((cx0 + cx1) / 2, 10, cz1 + 1)), Vector3.new(cx1 - cx0 + 4, 20, 1))
	boundary(CFrame.new(O + Vector3.new(cx0 - 1, 10, (cz0 + cz1) / 2)), Vector3.new(1, 20, cz1 - cz0 + 4))
	boundary(CFrame.new(O + Vector3.new(cx1 + 1, 10, (cz0 + cz1) / 2)), Vector3.new(1, 20, cz1 - cz0 + 4))
	boundary(CFrame.new(O + Vector3.new(yx1 + 1, 10, (yz0 + yz1) / 2)), Vector3.new(1, 20, yz1 - yz0 + 4))
	boundary(CFrame.new(O + Vector3.new((yx0 + yx1) / 2, 10, yz0 - 1)), Vector3.new(yx1 - yx0 + 4, 20, 1))
	boundary(CFrame.new(O + Vector3.new((yx0 + yx1) / 2, 10, yz1 + 1)), Vector3.new(yx1 - yx0 + 4, 20, 1))
end

------------------------------------------------------------------------------------
-- Room records
------------------------------------------------------------------------------------

local function collectRooms(map)
	for _, floor in Layout.Floors do
		local width, height = gridSize(floor)
		for z = 0, height - 1 do
			for x = 0, width - 1 do
				local ch = Layout.charAt(floor, x, z)
				if isRoom(ch) then
					local id = floor.id .. "_" .. ch
					local def = Layout.Rooms[id]
					assert(def, "Layout: missing room definition for " .. id)
					local room = map.Rooms[id]
					if not room then
						room = {
							id = id,
							char = ch,
							name = def.name,
							kind = def.kind,
							style = def.style,
							zone = def.zone,
							number = def.number,
							lockKey = def.lockKey,
							closet = def.closet,
							secret = def.secret,
							noSpawns = def.noSpawns,
							shrink = def.shrink,
							floorId = floor.id,
							floorY = floor.y,
							cells = {},
							cellSet = {},
							doors = {},
							windows = {},
							fixtures = {},
							floorParts = {},
							ceilingParts = {},
							wallParts = {},
							wallSpots = {},
							floorSpots = {},
							props = {},
							minX = math.huge,
							minZ = math.huge,
							maxX = -math.huge,
							maxZ = -math.huge,
						}
						map.Rooms[id] = room
					end
					table.insert(room.cells, { x = x, z = z })
					room.cellSet[z * 10000 + x] = true
					room.minX = math.min(room.minX, x)
					room.minZ = math.min(room.minZ, z)
					room.maxX = math.max(room.maxX, x)
					room.maxZ = math.max(room.maxZ, z)
				end
			end
		end
	end
	for _, room in map.Rooms do
		local floor = Layout.getFloor(room.floorId)
		local minP = Layout.Origin + Vector3.new(room.minX * CELL, floor.y, room.minZ * CELL)
		local maxP = Layout.Origin + Vector3.new((room.maxX + 1) * CELL, floor.y + CH, (room.maxZ + 1) * CELL)
		room.min = minP
		room.max = maxP
		room.center = (minP + maxP) / 2
		room.center = Vector3.new(room.center.X, floor.y, room.center.Z)
		room.area = #room.cells * CELL * CELL
	end
end

------------------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------------------

function MapBuilder.build(seed: number, parent: Instance)
	local rng = SeededRandom.new(seed, "map")
	local root = Instance.new("Folder")
	root.Name = "Building"

	local map = setmetatable({
		Root = root,
		Seed = seed,
		Rooms = {},
		Doors = {},
		DoorsById = {},
		EntranceCells = {},
		ExitCells = {},
		Expansions = {},
	}, Map)

	collectRooms(map)

	-- expansion caps are built separately so they can be hidden
	local capCells = {}
	for _, exp in Layout.Expansions do
		for zz = exp.z0, exp.z1 do
			capCells[exp.floor .. ":" .. (zz * 10000 + exp.capX)] = true
		end
	end

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = root
	for i, floor in Layout.Floors do
		local floorFolder = Instance.new("Folder")
		floorFolder.Name = floor.id
		floorFolder.Parent = structure
		local below = Layout.Floors[i - 1]
		local above = Layout.Floors[i + 1]
		local floorCaps = {}
		for key in capCells do
			local fid, num = string.match(key, "^(%a+):(%d+)$")
			if fid == floor.id then
				floorCaps[tonumber(num)] = true
			end
		end
		buildSlabs(map, floor, floorFolder, below ~= nil)
		buildCeilings(map, floor, floorFolder, above == nil)
		buildWalls(map, floor, floorFolder, floorCaps)
		buildSkins(map, floor, floorFolder, rng:Derive("skins" .. floor.id), floorCaps)
		buildDoorsAndWindows(map, floor, floorFolder, rng:Derive("doors" .. floor.id))
		buildStairs(map, floor, floorFolder, above ~= nil)
		buildRoomLights(map, floor, floorFolder, rng:Derive("lights" .. floor.id))
		task.wait()
	end
	local extras = Instance.new("Folder")
	extras.Name = "Extras"
	extras.Parent = root
	buildRoof(map, extras)
	buildExpansions(map, extras, rng:Derive("expansions"))
	buildShrinkWall(map, extras)
	buildExterior(map, extras, rng:Derive("exterior"))
	task.wait()

	local furniture = Instance.new("Folder")
	furniture.Name = "Furniture"
	furniture.Parent = root
	Furnisher.furnishAll(map, furniture, rng:Derive("furnish"))

	root.Parent = parent
	return map
end

return MapBuilder
