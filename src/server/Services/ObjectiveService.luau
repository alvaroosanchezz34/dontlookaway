--[[
	ObjectiveService
	Plans and tracks the round's objectives from the round seed:
	  * the exit (loading dock shutter) has four locks: POWER, two puzzle locks
	    chosen per round, and the ANOMALIES quota
	  * required items (fuses, keys, cassette, offerings...) are distributed over
	    reachable rooms; locked rooms never hide the key that opens them, so the
	    round is always completable
	  * documents carry clues (breaker pattern, keypad code halves, hints, lore)
	The objective list is pushed to clients as plain text; there are no waypoint
	markers, the building has to be learned.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)
local Build = require(script.Parent.Parent.Map.Build)
local Art = require(script.Parent.Parent.Map.Art)
local Lore = require(ReplicatedStorage.Shared.Catalog.Lore)

local ObjectiveService = {}

ObjectiveService.LockReleased = Signal.new() -- (lockName)
ObjectiveService.AllLocksReleased = Signal.new()

ObjectiveService.PuzzleNames = {
	CODE = "Find the two halves of the security code (Security G-07)",
	SYMBOLS = "Open the archive cabinet (1-01): find its four symbols",
	DOORS = "Find the cassette, then open the closets (B-09) in order",
	OFFERING = "Return three belongings to the Quiet Room (1-03)",
}

local state = nil
local readBy: { [Player]: { [string]: boolean } } = {}
local docs: { [string]: { title: string, body: string, kind: string? } } = {}
local docFolder: Folder? = nil

-- the story pieces themselves live in Catalog/Lore (chapters, archive categories)

------------------------------------------------------------------------------------
-- Planning
------------------------------------------------------------------------------------

local function spotCandidates(map, rng, filter)
	local list = {}
	for _, room in map.Rooms do
		if not room.secret and not room.noSpawns and room.kind ~= "stairs" and room.kind ~= "closet" and (not filter or filter(room)) then
			for _, cf in room.itemSpots or {} do
				table.insert(list, { room = room, cf = cf })
			end
		end
	end
	table.sort(list, function(a, b)
		if a.room.id == b.room.id then
			return a.cf.Position.X + a.cf.Position.Z * 0.001 < b.cf.Position.X + b.cf.Position.Z * 0.001
		end
		return a.room.id < b.room.id
	end)
	return rng:Shuffle(list)
end

local usedSpots = {}

local function takeSpot(map, rng, filter)
	for _, spot in spotCandidates(map, rng, filter) do
		local key = string.format("%d_%d_%d", math.floor(spot.cf.Position.X), math.floor(spot.cf.Position.Y), math.floor(spot.cf.Position.Z))
		if not usedSpots[key] then
			usedSpots[key] = true
			return spot
		end
	end
	return nil
end

local function placeItem(map, rng, itemId, filter)
	local spot = takeSpot(map, rng, filter)
	if not spot then
		spot = takeSpot(map, rng, nil)
	end
	if not spot then
		warn("[ObjectiveService] no spot for", itemId)
		return nil
	end
	local cf = CFrame.new(spot.cf.Position) * CFrame.Angles(0, math.rad(rng:Number(0, 360)), 0)
	local model = Registry.InventoryService:SpawnPickup(itemId, cf)
	if model then
		model:SetAttribute("Room", spot.room.id)
	end
	return model, spot.room
end

local function placeDocument(map, rng, docId, title, body, filter, kind, loreId: string?)
	local spot = takeSpot(map, rng, filter)
	if not spot then
		spot = takeSpot(map, rng, nil)
	end
	if not spot then
		return nil
	end
	docs[docId] = { title = title, body = body, kind = kind, loreId = loreId }
	local paper = Build.part(docFolder, "Document", Vector3.new(0.9, 0.04, 1.2), CFrame.new(spot.cf.Position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, math.rad(rng:Number(0, 360)), 0), Color3.fromRGB(214, 206, 184), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
	local hit = Build.part(paper, "Hit", Vector3.new(1.6, 0.8, 1.6), paper.CFrame * CFrame.new(0, 0.3, 0), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false })
	hit:AddTag("Interactable")
	hit:SetAttribute("InteractKind", "Document")
	hit:SetAttribute("DocId", docId)
	hit:SetAttribute("Prompt", "Read")
	paper:SetAttribute("Room", spot.room.id)
	return paper, spot.room
end

-- Painted wall marking for the symbol puzzle.
local function placeMarking(map, rng, symbol, order, usedRooms)
	local rooms = {}
	for _, room in map.Rooms do
		if (room.zone == "UPPER" or room.zone == "GROUND") and not room.secret and room.kind ~= "stairs" and not usedRooms[room.id] and room.wallSpots and #room.wallSpots > 0 and not room.lockKey then
			table.insert(rooms, room)
		end
	end
	table.sort(rooms, function(a, b)
		return a.id < b.id
	end)
	local room = rng:Pick(rng:Shuffle(rooms))
	if not room then
		return
	end
	usedRooms[room.id] = true
	local spot = rng:Pick(room.wallSpots)
	local cf = spot.cframe * CFrame.new(0, 3.2, -0.08)
	local plate = Build.part(docFolder, "Marking", Vector3.new(2.4, 2.4, 0.02), cf, Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false })
	local gui = Build.surfaceGui(plate, Enum.NormalId.Front, 40)
	gui.LightInfluence = 1
	local bg = Build.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	Art.symbol(bg, symbol, Color3.fromRGB(120, 34, 30), 2)
	for d = 1, order do
		local dot = Build.frame(bg, { Size = UDim2.fromScale(0.08, 0.08), Position = UDim2.fromScale(0.5 + (d - (order + 1) / 2) * 0.13 - 0.04, 0.9), BackgroundColor3 = Color3.fromRGB(120, 34, 30) })
		Build.corner(dot, 0.5)
	end
	plate:SetAttribute("Room", room.id)
	return room
end

function ObjectiveService:Plan(map, rng, playerCount: number)
	usedSpots = {}
	readBy = {}
	docs = {}
	if docFolder then
		docFolder:Destroy()
	end
	docFolder = Instance.new("Folder")
	docFolder.Name = "Documents"
	docFolder.Parent = map.Root
	Registry.InventoryService:ClearPickups()

	local puzzlePool = { "CODE", "SYMBOLS", "DOORS", "OFFERING" }
	rng:Shuffle(puzzlePool)
	local chosen = { puzzlePool[1], puzzlePool[2] }
	table.sort(chosen)

	local quota = Registry.RoundService:GetQuota(playerCount)
	state = {
		puzzles = chosen,
		locks = { POWER = false, [chosen[1]] = false, [chosen[2]] = false, ANOMALIES = false },
		lockOrder = { "POWER", chosen[1], chosen[2], "ANOMALIES" },
		quota = quota,
		found = 0,
		fuses = 0,
		power = true, -- the lights work until THE OUTAGE
		outage = false,
		breakerPattern = {},
		code = "",
		symbols = {},
		doorOrder = {},
		subProgress = {},
	}

	local function unlocked(room)
		return room.lockKey == nil and room.kind ~= "secret"
	end
	-- keys
	placeItem(map, rng, "MAINT_KEY", function(room)
		return unlocked(room) and room.zone ~= "BASEMENT"
	end)
	placeItem(map, rng, "OFFICE_KEY", function(room)
		return unlocked(room) and room.zone ~= "BASEMENT"
	end)
	-- fuses: one per floor, never behind the maintenance door
	for _, zone in { "GROUND", "UPPER", "BASEMENT" } do
		placeItem(map, rng, "FUSE", function(room)
			return unlocked(room) and room.zone == zone
		end)
	end
	-- batteries
	local extra = Registry.RoundService:GetDifficultyConfig().ExtraBatteries or 0
	for _ = 1, math.max(1, 3 + math.min(2, playerCount - 1) + extra) do
		placeItem(map, rng, "BATTERY", unlocked)
	end
	placeItem(map, rng, "CROWBAR", unlocked)
	if rng:Chance(0.65) then
		placeItem(map, rng, "WARD", unlocked)
	end
	-- the photograph always waits in the hidden room
	local secretRoom = map.Rooms.B_z
	if secretRoom and secretRoom.secretSpot then
		Registry.InventoryService:SpawnPickup("PHOTOGRAPH", secretRoom.secretSpot)
	end

	-- breaker pattern: always at least two up and one down
	local pattern = {}
	repeat
		local ups = 0
		for i = 1, 5 do
			pattern[i] = rng:Chance(0.5)
			if pattern[i] then
				ups += 1
			end
		end
	until ups >= 2 and ups <= 4
	state.breakerPattern = pattern
	local lines = {}
	for i, up in pattern do
		table.insert(lines, string.format("%d %s", i, if up then "UP" else "DOWN"))
	end
	local officeB = map.Rooms.G_b
	placeDocument(map, rng, "BREAKERS", "MAINTENANCE LOG - B1", "If the lights go out again:\n\n1. Three fuses in the box. Spares are kept on every floor.\n2. Then the breakers, exactly like this:\n\n" .. table.concat(lines, "\n") .. "\n\nThe maintenance key hangs somewhere upstairs. Don't go down alone.", function(room)
		return room == officeB
	end, "breakers")

	for _, p in chosen do
		if p == "CODE" then
			local code = string.format("%d%d%d%d", rng:Int(1, 9), rng:Int(0, 9), rng:Int(0, 9), rng:Int(0, 9))
			state.code = code
			placeDocument(map, rng, "CODE_A", "TORN NOTE", "security door\nfirst half: " .. code:sub(1, 1) .. " " .. code:sub(2, 2) .. "\n\n(the rest is with the other half)", function(room)
				return unlocked(room) and room.zone == "UPPER"
			end, "code")
			placeDocument(map, rng, "CODE_B", "TORN NOTE", "...second half: " .. code:sub(3, 3) .. " " .. code:sub(4, 4) .. "\n\nmemorise it. burn this.", function(room)
				return unlocked(room) and room.zone ~= "UPPER" and room.id ~= "G_q"
			end, "code")
		elseif p == "SYMBOLS" then
			local used = { U_n = true }
			for i = 1, 4 do
				local symbol = rng:Pick(Art.Symbols)
				state.symbols[i] = symbol
				placeMarking(map, rng, symbol, i, used)
			end
			placeDocument(map, rng, "SYMBOLS", "ARCHIVE NOTICE", "The cabinet keeps the old records.\nIt opens for four shapes.\n\nWe painted them where we used to work. The dots under each shape tell you which dial it belongs to.", function(room)
				return room.id == "U_n"
			end, "symbols")
		elseif p == "DOORS" then
			local order = rng:Shuffle({ 1, 2, 3, 4 })
			state.doorOrder = order
			placeItem(map, rng, "TAPE", function(room)
				return unlocked(room) and room.zone ~= "BASEMENT"
			end)
		elseif p == "OFFERING" then
			for _, item in { "MUSIC_BOX", "DOLL", "CANDLE" } do
				placeItem(map, rng, item, function(room)
					return unlocked(room) and room.id ~= "U_p"
				end)
			end
			placeDocument(map, rng, "OFFERING", "CHILD'S DRAWING", "(a drawing of a small room with a table)\n\nMY MUSIC BOX\nMY DOLL\nMY CANDLE\n\nGIVE THEM BACK AND I WILL LET YOU GO", function(room)
				return room.id == "U_p"
			end, "offering")
		end
	end
	-- lore: tonight's pieces continue the team's story in order (Catalog/Lore)
	local team = {}
	for _, p in Players:GetPlayers() do
		local d = Registry.DataService:Get(p)
		if d then
			table.insert(team, d.lore or {})
		end
	end
	if #team == 0 then
		table.insert(team, {})
	end
	for _, entry in Lore.pick(team, 4, rng) do
		placeDocument(map, rng, "LORE_" .. entry.id, entry.title, entry.body, unlocked, "lore", entry.id)
	end
	Registry.PuzzleService:Setup(map, state, rng)
	self:UpdateExitPanel()
	self:Push()
	return state
end

function ObjectiveService:GetState()
	return state
end

------------------------------------------------------------------------------------
-- Progress
------------------------------------------------------------------------------------

function ObjectiveService:UpdateExitPanel()
	local map = Registry.MapService:GetMap()
	if not map or not map.ExitPanel or not state then
		return
	end
	local released = 0
	for i, name in state.lockOrder do
		local lamp = map.ExitPanel:FindFirstChild("Lock" .. i)
		if lamp then
			lamp.Color = if state.locks[name] then Color3.fromRGB(220, 226, 214) else Color3.fromRGB(70, 20, 20)
		end
		if state.locks[name] then
			released += 1
		end
	end
	local screen = map.ExitPanel:FindFirstChild("Screen")
	local readout = screen and screen:FindFirstChild("Readout", true)
	if readout and readout:IsA("TextLabel") then
		readout.Text = if released >= 4 then "OPEN" else string.format("LOCKED %d/4", released)
		readout.TextColor3 = if released >= 4 then Color3.fromRGB(210, 230, 210) else Color3.fromRGB(200, 120, 110)
	end
end

function ObjectiveService:ReleaseLock(name: string)
	if not state or state.locks[name] == nil or state.locks[name] then
		return
	end
	state.locks[name] = true
	local map = Registry.MapService:GetMap()
	if map and map.ExitPanel and map.ExitPanel.PrimaryPart then
		Registry.AudioService:PlayAt("LockRelease", map.ExitPanel:GetPivot().Position)
	end
	Registry.AudioService:Play2DAll("ObjectiveUpdate")
	self:UpdateExitPanel()
	self:Push()
	ObjectiveService.LockReleased:Fire(name)
	local all = true
	for _, v in state.locks do
		if not v then
			all = false
		end
	end
	if all then
		ObjectiveService.AllLocksReleased:Fire()
	end
end

function ObjectiveService:IsLockReleased(name: string): boolean
	return state ~= nil and state.locks[name] == true
end

function ObjectiveService:AnomalyFound()
	if not state then
		return
	end
	state.found += 1
	if state.found >= state.quota then
		self:ReleaseLock("ANOMALIES")
	end
	self:Push()
end

function ObjectiveService:SetSubProgress(key: string, text: string?)
	if not state then
		return
	end
	state.subProgress[key] = text
	if Registry.GuidanceService then
		Registry.GuidanceService:Progress("puzzle:" .. key)
	end
	self:Push()
end

-- A soft-guidance line naming where to go next (nil clears it).
function ObjectiveService:SetHintLine(text: string?)
	if not state or state.hintLine == text then
		return
	end
	state.hintLine = text
	self:Push()
end

-- Where the next step of the power objective is, in plain words.
local function powerText(): string
	local map = Registry.MapService:GetMap()
	if state.fuses < 3 then
		local maint = map and map.Rooms.B_d
		local lockedDoor = false
		if maint then
			for _, door in maint.doors do
				if door.model and door.model:GetAttribute("Locked") then
					lockedDoor = true
				end
			end
		end
		local carried = 0
		for _, p in Registry.PlayerService:GetAlive() do
			carried += Registry.InventoryService:Count(p, "FUSE")
		end
		if lockedDoor then
			return string.format("Restore the power: find fuses (%d/3) and the maintenance key", math.min(3, state.fuses + carried))
		end
		return string.format("Restore the power: fuses %d/3 into the box in Maintenance B-04", state.fuses)
	end
	return state.subProgress.POWER or "Restore the power: set the breakers (maintenance log)"
end

function ObjectiveService:BuildList()
	if not state then
		return {}
	end
	local list = {}
	local escape = Registry.RoundService:IsEscape()
	if escape then
		table.insert(list, { text = "ESCAPE THROUGH THE LOADING DOCK", done = false, primary = true })
		return list
	end
	local arriving = Registry.HorrorDirector:GetStoryPhase() == "ARRIVAL" and not state.outage
	if arriving then
		table.insert(list, { text = "Find the source of the disturbance", done = false, primary = true })
		table.insert(list, { text = "Learn the building. Read every note.", done = false })
	else
		table.insert(list, {
			text = string.format("Document the anomalies  %d/%d", math.min(state.found, state.quota), state.quota),
			done = state.locks.ANOMALIES,
			primary = true,
		})
		if state.locks.POWER then
			table.insert(list, { text = "Power restored", done = true })
		else
			table.insert(list, { text = powerText(), done = false })
		end
	end
	for _, p in state.puzzles do
		table.insert(list, { text = state.subProgress[p] or ObjectiveService.PuzzleNames[p], done = state.locks[p] })
	end
	if state.hintLine then
		table.insert(list, 2, { text = state.hintLine, done = false, hint = true })
	end
	local released = 0
	for _, v in state.locks do
		if v then
			released += 1
		end
	end
	table.insert(list, { text = string.format("Exit locks released  %d/4", released), done = released >= 4, dim = true })
	return list
end

function ObjectiveService:Push(player: Player?)
	local payload = { list = self:BuildList(), found = state and state.found or 0, quota = state and state.quota or 0 }
	if player then
		Net.fire(player, "Objective", payload)
	else
		Net.fireAll("Objective", payload)
	end
end

function ObjectiveService:Clear()
	state = nil
	docs = {}
	Net.fireAll("Objective", { list = {}, found = 0, quota = 0 })
end

------------------------------------------------------------------------------------
-- Documents
------------------------------------------------------------------------------------

local function onRead(player: Player, target: Instance): boolean
	local id = target:GetAttribute("DocId")
	local doc = type(id) == "string" and docs[id]
	if not doc then
		return false
	end
	Registry.AudioService:Play2D({ player }, "PaperRustle")
	local entry = doc.loreId and Lore.ById[doc.loreId]
	Net.fire(player, "Document", { id = id, title = doc.title, body = doc.body, kind = doc.kind, category = entry and entry.category, format = entry and entry.kind })
	if entry then
		ObjectiveService:RecordLore(player, entry.id)
	end
	if Registry.GuidanceService then
		Registry.GuidanceService:DocumentRead(id)
	end
	-- each note counts once per player per night (no farming the same paper)
	readBy[player] = readBy[player] or {}
	if not readBy[player][id] then
		readBy[player][id] = true
		Registry.ProgressionService:Challenge(player, "note", 1)
	end
	return true
end

--[[
	Adds an archive entry to the player's profile (once) and announces it. The
	archive (Field Office records) and THE WITNESS ending read from it.
]]
function ObjectiveService:RecordLore(player: Player, loreId: string)
	local entry = Lore.ById[loreId]
	local data = Registry.DataService:Get(player)
	if not entry or not data or data.lore[loreId] then
		return false
	end
	Registry.DataService:Update(player, function(d)
		d.lore[loreId] = os.time()
	end)
	local found = Lore.found(Registry.DataService:Get(player).lore)
	Net.fire(player, "Unlock", { type = "lore", name = entry.title, category = entry.category, found = found, total = Lore.Count })
	Registry.AnalyticsService:Event(player, "LoreFound", found, { id = loreId, chapter = entry.chapter })
	if found == 1 then
		Registry.AnalyticsService:Milestone(player, "FIRST_LORE")
	end
	if entry.witness then
		Registry.AnalyticsService:Milestone(player, "SECRET_DISCOVERY", entry.chapter)
	end
	Registry.ProgressionService:Push(player)
	return true
end

function ObjectiveService:Init()
	Registry.InteractionService:Register("Document", onRead)
end

function ObjectiveService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		if state then
			self:Push(player)
		end
	end)
end

return ObjectiveService
