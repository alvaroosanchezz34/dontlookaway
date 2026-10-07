--[[
	GuidanceService
	Soft guidance: the game never leaves a team lost for long, and never breaks
	the fiction to do it. When nobody has made progress for a while (difficulty
	dependent), it works out the most useful next step and nudges toward it,
	escalating only if the nudge is not enough:

	  1  a sound from that direction (a knock, a radio crackle)
	  2  the lights in that room stutter; a door on the way creaks open
	  3  a thought in the notebook ("The maintenance log mentioned the basement.")
	  4  the objective names the place ("-> MAIL ROOM, G-03, ground floor")
	  5  a faint marker shows the direction for a few seconds (NORMAL only)

	Any progress (an item, a note, a lock, an anomaly, a step of a puzzle) resets
	it. NIGHTMARE stops at gentle nudges.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Items = require(ReplicatedStorage.Shared.Catalog.Items)
local Registry = require(script.Parent.Parent.Registry)

local GuidanceService = {}

local lastProgressAt = 0
local level = 0
local docsRead: { [string]: boolean } = {}
local visited: { [string]: boolean } = {}
local lastTargetKey = ""
local playerStill: { [Player]: { pos: Vector3, since: number, hinted: boolean } } = {}

local LEVEL_STEP = 30 -- seconds between escalations

local FLOOR_NAMES = { G = "ground floor", U = "first floor", B = "basement" }

local function roomLabel(room): string
	local name = room.name or room.id
	if room.number then
		name ..= " (" .. room.number .. ")"
	end
	return name
end

local function floorName(room): string
	return FLOOR_NAMES[room.floorId] or ""
end

function GuidanceService:Progress(_reason: string?)
	lastProgressAt = os.clock()
	if level > 0 then
		level = 0
		Registry.ObjectiveService:SetHintLine(nil)
	end
end

function GuidanceService:DocumentRead(docId: string)
	if not docsRead[docId] then
		docsRead[docId] = true
		self:Progress("doc")
	end
end

function GuidanceService:WasRead(docId: string): boolean
	return docsRead[docId] == true
end

------------------------------------------------------------------------------------
-- What should the team do next, and where?
------------------------------------------------------------------------------------

local function teamCentre(): Vector3?
	local sum, n = Vector3.zero, 0
	for _, p in Registry.PlayerService:GetAlive() do
		local root = Util.getRoot(p)
		if root then
			sum += root.Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

local function carried(itemId: string): number
	local n = 0
	for _, p in Registry.PlayerService:GetAlive() do
		n += Registry.InventoryService:Count(p, itemId)
	end
	return n
end

local function pickupRoom(itemId: string)
	local map = Registry.MapService:GetMap()
	local centre = teamCentre()
	if not map then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, model in Registry.InventoryService:GetPickups() do
		if model:GetAttribute("ItemId") == itemId and not model:GetAttribute("FalseItem") then
			local pos = model:GetPivot().Position
			local d = if centre then (pos - centre).Magnitude else 0
			local room = map:roomAt(pos + Vector3.new(0, 1.5, 0))
			if room and d < bestD then
				best, bestD = room, d
			end
		end
	end
	return best
end

local function doorLocked(room): boolean
	for _, door in room.doors do
		if door.model and door.model:GetAttribute("Locked") then
			return true
		end
	end
	return false
end

local function docRoom(docId: string)
	local map = Registry.MapService:GetMap()
	local folder = map and map.Root:FindFirstChild("Documents")
	if not folder then
		return nil
	end
	for _, d in folder:GetDescendants() do
		if d:GetAttribute("DocId") == docId then
			local paper = d.Parent
			local roomId = paper and paper:GetAttribute("Room")
			return if type(roomId) == "string" then map.Rooms[roomId] else nil
		end
	end
	return nil
end

-- Returns { room, key, thought, where } or nil.
function GuidanceService:NextTarget()
	local map = Registry.MapService:GetMap()
	local state = Registry.ObjectiveService:GetState()
	if not map or not state then
		return nil
	end
	local function target(room, key: string, thought: string)
		if not room then
			return nil
		end
		return { room = room, key = key, thought = thought, where = roomLabel(room) .. ", " .. floorName(room) }
	end
	if Registry.RoundService:IsEscape() then
		return target(map.Rooms.G_y, "escape", "The loading dock. Ground floor, at the back of the building.")
	end
	-- power
	if state.outage and not state.power then
		local maint = map.Rooms.B_d
		if state.fuses < 3 then
			if maint and doorLocked(maint) and carried("MAINT_KEY") == 0 then
				local keyRoom = pickupRoom("MAINT_KEY")
				if keyRoom then
					return target(keyRoom, "maintkey", "Maintenance is locked. Its key has a red tag. Somewhere upstairs?")
				end
			end
			if carried("FUSE") + state.fuses >= 3 then
				return target(maint, "fusebox", "We have the fuses. The fuse box is in Maintenance, down in the basement.")
			end
			local fuseRoom = pickupRoom("FUSE")
			if fuseRoom then
				return target(fuseRoom, "fuse:" .. fuseRoom.id, "The log said spare fuses are kept on every floor.")
			end
		else
			local office = map.Rooms.G_b
			if not docsRead.BREAKERS then
				if office and doorLocked(office) and carried("OFFICE_KEY") == 0 then
					local keyRoom = pickupRoom("OFFICE_KEY")
					if keyRoom then
						return target(keyRoom, "officekey", "The maintenance log is in office G-02. It's locked; there's a small key somewhere.")
					end
				end
				return target(office, "log", "The breaker pattern is in the maintenance log, in office G-02.")
			end
			return target(maint, "breakers", "Fuses are in. The breakers, exactly like the log said.")
		end
	end
	-- puzzles, in the order they were given
	for _, kind in state.puzzles do
		if not state.locks[kind] then
			if kind == "CODE" then
				for _, docId in { "CODE_A", "CODE_B" } do
					if not docsRead[docId] then
						local room = docRoom(docId)
						if room then
							return target(room, "code:" .. docId, "Half of a code, torn. The other half must be somewhere else.")
						end
					end
				end
				return target(map.Rooms.G_q, "security", "We have both halves. The keypad is at Security, G-07.")
			elseif kind == "SYMBOLS" then
				if not docsRead.SYMBOLS then
					return target(map.Rooms.U_n, "archive", "The archive cabinet upstairs wants four shapes.")
				end
				for _, marking in (map.Root:FindFirstChild("Documents") or map.Root):GetChildren() do
					local roomId = marking.Name == "Marking" and marking:GetAttribute("Room")
					if type(roomId) == "string" and not visited[roomId] then
						return target(map.Rooms[roomId], "mark:" .. roomId, "Painted shapes where they used to work. One should be in here.")
					end
				end
				return target(map.Rooms.U_n, "cabinet", "Four shapes, four dials. The dots say which dial.")
			elseif kind == "DOORS" then
				if carried("TAPE") == 0 and not state.subProgress.DOORS then
					local tapeRoom = pickupRoom("TAPE")
					if tapeRoom then
						return target(tapeRoom, "tape", "A cassette labelled DOORS. Someone recorded the order.")
					end
				end
				return target(map.Rooms.B_w, "closets", "The closets in the basement, B-09. Play the tape there.")
			elseif kind == "OFFERING" then
				for _, itemId in { "MUSIC_BOX", "DOLL", "CANDLE" } do
					if carried(itemId) == 0 then
						local room = pickupRoom(itemId)
						if room then
							return target(room, "offer:" .. itemId, "The " .. string.lower(Items.get(itemId).name) .. ". The drawing asked for it back.")
						end
					end
				end
				return target(map.Rooms.U_p, "quiet", "Give them back. The Quiet Room, upstairs, 1-03.")
			end
		end
	end
	-- anomalies
	if not state.locks.ANOMALIES then
		for _, inst in Registry.AnomalyService:GetActive() do
			local anchor = inst.spec and inst.spec.anchors and inst.spec.anchors[1]
			local pos = anchor and (if typeof(anchor.pos) == "Vector3" then anchor.pos elseif typeof(anchor.pos) == "Instance" and anchor.pos.Parent then Util.boundingSphere(anchor.pos) else nil)
			local room = pos and map:roomAt(pos)
			if room then
				return target(room, "anomaly:" .. inst.def.id, "Something in here is not how it was.")
			end
		end
	end
	-- notes nobody has read yet
	for _, id in { "BREAKERS", "SYMBOLS", "OFFERING", "LORE_1", "LORE_2", "LORE_3", "LORE_4" } do
		if not docsRead[id] then
			local room = docRoom(id)
			if room then
				return target(room, "doc:" .. id, "There was paper on a desk somewhere. Worth reading.")
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------------
-- Nudges
------------------------------------------------------------------------------------

local function nudge(t, lvl: number)
	local room = t.room
	local centre = room.center + Vector3.new(0, 4, 0)
	local alive = Registry.PlayerService:GetAlive()
	if lvl == 1 then
		-- a sound from that direction, placed between each player and the room
		for _, p in alive do
			local root = Util.getRoot(p)
			if root then
				local dir = centre - root.Position
				local dist = dir.Magnitude
				local at = if dist > 30 then root.Position + dir.Unit * 26 else centre
				Registry.AudioService:PlayAtFor({ p }, if dist > 30 then "DistantKnock" else "DistantRadio", at, { volume = 0.9 })
			end
		end
	elseif lvl == 2 then
		Net.fireAll("Director", { cue = "flicker", room = room.id, duration = 3 })
		Registry.AudioService:PlayAt("LightFlicker", centre + Vector3.new(0, 6, 0), { volume = 1 })
		for _, door in room.doors do
			if door.model and not door.model:GetAttribute("Locked") then
				Registry.DoorService:SetOpen(door.model, true)
				break
			end
		end
	elseif lvl == 3 then
		Net.fireList(alive, "Notify", { kind = "hint", text = t.thought })
	elseif lvl == 4 then
		Registry.ObjectiveService:SetHintLine("-> " .. string.upper(t.where))
	elseif lvl >= 5 then
		Net.fireList(alive, "Effect", { name = "GuideMarker", at = centre, text = room.name })
	end
	if Registry.AdminService then
		Registry.AdminService:Log(string.format("guidance L%d -> %s (%s)", lvl, room.id, t.key))
	end
end

local function step()
	if not Registry.RoundService:IsRunning() or Registry.RoundService:GetState() == "STARTING" then
		return
	end
	local c = Registry.RoundService:GetDifficultyConfig()
	local now = os.clock()
	local map = Registry.MapService:GetMap()
	-- rooms the team has been in
	for _, p in Registry.PlayerService:GetAlive() do
		local root = Util.getRoot(p)
		local room = root and map and map:roomAt(root.Position)
		if room and not visited[room.id] then
			visited[room.id] = true
		end
	end
	-- the escape gets a short fuse: nobody should wander while the exit is open
	local delay = if Registry.RoundService:IsEscape() then 35 else (c.HintDelay or 90)
	local idle = now - lastProgressAt
	if idle < delay then
		return
	end
	local wanted = math.min(c.HintMaxLevel or 5, math.floor((idle - delay) / LEVEL_STEP) + 1)
	if wanted <= level then
		return
	end
	local t = GuidanceService:NextTarget()
	if not t then
		return
	end
	if t.key ~= lastTargetKey then
		lastTargetKey = t.key
	end
	level = wanted
	nudge(t, level)
end

-- Personal nudge for someone standing still for a long time (stuck or AFK-ish).
local function stillCheck()
	if not Registry.RoundService:IsRunning() then
		return
	end
	local now = os.clock()
	for _, p in Registry.PlayerService:GetAlive() do
		local root = Util.getRoot(p)
		if root then
			local rec = playerStill[p]
			if not rec or (root.Position - rec.pos).Magnitude > 8 then
				playerStill[p] = { pos = root.Position, since = now, hinted = false }
			elseif not rec.hinted and now - rec.since > 100 and not Registry.ObserverService:IsActive() then
				rec.hinted = true
				local t = GuidanceService:NextTarget()
				if t then
					Net.fire(p, "Notify", { kind = "hint", text = t.thought })
				end
			end
		end
	end
end

function GuidanceService:BeginRound()
	lastProgressAt = os.clock()
	level = 0
	docsRead = {}
	visited = {}
	lastTargetKey = ""
	playerStill = {}
end

function GuidanceService:GetLevel(): number
	return level
end

function GuidanceService:Start()
	-- anything that moves the round forward counts as progress
	Registry.InventoryService.ItemPicked:Connect(function()
		self:Progress("item")
	end)
	Registry.ObjectiveService.LockReleased:Connect(function()
		self:Progress("lock")
	end)
	Registry.AnomalyService.Resolved:Connect(function()
		self:Progress("anomaly")
	end)
	Registry.HorrorDirector.StoryPhaseChanged:Connect(function()
		self:Progress("phase")
	end)
	Players.PlayerRemoving:Connect(function(p)
		playerStill[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			local ok, err = pcall(step)
			if not ok then
				warn("[GuidanceService] step error:", err)
			end
			pcall(stillCheck)
		end
	end)
end

return GuidanceService
