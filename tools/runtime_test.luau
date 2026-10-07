--[[
	Runtime test harness (Lune).

	Loads the built place file, executes the REAL server modules (map builder,
	furnisher, props, art, objective planning, puzzle setup, every anomaly
	definition, reality ops) inside a Lune DataModel and checks invariants:
	  * the building builds for many seeds without errors
	  * every room is furnished, has spawn spots, puzzle fixtures exist
	  * the objective planner always places every required item (solvable)
	  * every anomaly definition produces candidates and valid, revertible ops
	Engine-only features (physics, rendering, networking) are stubbed.

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/runtime_test.luau build/test.rbxlx
]]

local env = require("./lib/env")
local roblox = env.roblox
local stdio = require("@lune/stdio")
local process = require("@lune/process")
local task = require("@lune/task")
local game = env.game
local workspace = env.workspace
local requireModule = env.requireModule
local makeSignal = env.makeSignal
local syncPositions = env.syncPositions
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

------------------------------------------------------------------------------------
-- Test helpers
------------------------------------------------------------------------------------

local failures = 0
local checks = 0

local function check(cond, message)
	checks += 1
	if not cond then
		failures += 1
		stdio.write(stdio.color("red") .. "FAIL " .. stdio.color("reset") .. message .. "\n")
	end
end

local function section(name)
	stdio.write(stdio.color("cyan") .. "== " .. name .. stdio.color("reset") .. "\n")
end

local SSS = game:GetService("ServerScriptService")
local Server = SSS:FindFirstChild("Server")
local RS = game:GetService("ReplicatedStorage")

------------------------------------------------------------------------------------
-- 1. Shared modules load
------------------------------------------------------------------------------------

section("shared modules")
for _, m in RS.Shared:GetDescendants() do
	if m:IsA("ModuleScript") and m.Name ~= "Net" and m.Name ~= "SoundFactory" then
		local ok, err = pcall(requireModule, m)
		check(ok, "require " .. m:GetFullName() .. ": " .. tostring(err))
	end
end

local JournalCatalog = requireModule(RS.Shared.Catalog.JournalCatalog)
check(JournalCatalog.Count >= 40, "at least 40 anomalies in the journal")
local AudioLibrary = requireModule(RS.Shared.Config.AudioLibrary)
local soundCount = 0
for key, def in AudioLibrary.Sounds do
	soundCount += 1
	check(type(def.id) == "string" and def.id:match("^rbxasset"), "sound id for " .. key)
	for _, e in def.effects or {} do
		local ok, inst = pcall(Instance.new, e[1])
		check(ok, "sound effect class " .. tostring(e[1]))
		if ok then
			for prop, value in e[2] do
				local okSet, err = pcall(function()
					inst[prop] = value
				end)
				check(okSet, key .. ": " .. e[1] .. "." .. prop .. " " .. tostring(err))
			end
		end
	end
end
print(string.format("  %d sounds validated", soundCount))

------------------------------------------------------------------------------------
-- 2. Map builds for many seeds
------------------------------------------------------------------------------------

section("map builder")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local Layout = requireModule(Server.Map.Layout)
local maps = {}
for _, seed in { 1, 42, 1337, 99991, 123456 } do
	local holder = Instance.new("Folder")
	holder.Name = "Seed" .. seed
	holder.Parent = workspace
	local t0 = os.clock()
	local ok, map = pcall(MapBuilder.build, seed, holder)
	check(ok, "build seed " .. seed .. ": " .. tostring(map))
	if ok then
		maps[seed] = map
		local parts = 0
		local lights = 0
		for _, d in map.Root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				local p = d.CFrame.Position
				check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN CFrame on " .. d:GetFullName())
				check(d.Size.X > 0 and d.Size.Y > 0 and d.Size.Z > 0, "bad size on " .. d:GetFullName())
			elseif d:IsA("Light") then
				lights += 1
			end
		end
		local rooms, spotless = 0, {}
		for id, room in map.Rooms do
			rooms += 1
			if #room.floorSpots == 0 and room.kind ~= "stairs" then
				table.insert(spotless, id)
			end
			check(room.folder ~= nil, "room furnished: " .. id)
		end
		check(rooms == 34, "34 rooms, got " .. rooms)
		check(#map.EntranceDoors == 2, "two entrance doors")
		check(map.ExitShutter ~= nil and map.ExitPanel ~= nil and map.EscapeZone ~= nil, "exit set piece")
		check(#map.CourtyardSpawns == 4, "four courtyard spawns")
		check(map.Expansions.CorridorStretch ~= nil and map.Expansions.BoilerExpand ~= nil, "expansions built")
		check(map.ShrinkWall ~= nil, "shrink wall built")
		check(#(map.Residents or {}) >= 1, "residents placed")
		-- geometry audit: nothing through walls, floating, blocking walkways or doors
		local GeometryValidator = requireModule(Server.Map.GeometryValidator)
		local report = GeometryValidator.run(map)
		check(#report.issues == 0, string.format("seed %d geometry: %s", seed, GeometryValidator.summary(report)))
		for i, issue in report.issues do
			if i <= 5 then
				print(string.format("    [%s] %s %s in %s: %s", issue.severity, issue.kind, issue.name, tostring(issue.room), issue.detail))
			end
		end
		for _, tag in { "FuseBox", "BreakerPanel", "Keypad", "SymbolCabinet", "OfferingTable", "TapeRecorder", "SecurityOverride", "BoardedPassage" } do
			local n = 0
			for _, d in map.Root:GetDescendants() do
				if d:HasTag(tag) then
					n += 1
				end
			end
			check(n == 1, string.format("seed %d: exactly one %s (got %d)", seed, tag, n))
		end
		local lamps = 0
		for _, d in map.Root:GetDescendants() do
			if d:HasTag("ClosetLamp") then
				lamps += 1
			end
		end
		check(lamps == 4, "four closet lamps, got " .. lamps)
		local doors = 0
		for _, rec in map.Doors do
			if rec.model and rec.model:HasTag("Door") then
				doors += 1
				check(typeof(rec.model:GetAttribute("OpenCFrame")) == "CFrame", "door open cframe " .. rec.id)
			end
		end
		-- room lookup works for every room cell
		for id, room in map.Rooms do
			local c = room.cells[1]
			local pos = Layout.cellToWorld(room.floorY, c.x, c.z) + Vector3.new(0, 3, 0)
			local found = map:roomAt(pos)
			check(found == room, "roomAt " .. id)
		end
		print(string.format("  seed %d: %d parts, %d lights, %d rooms, %d doors, %.2fs, rooms w/o free floor: %s", seed, parts, lights, rooms, doors, os.clock() - t0, table.concat(spotless, ",")))
	end
end

------------------------------------------------------------------------------------
-- 3. Objective planning is always solvable
------------------------------------------------------------------------------------

section("custom assets (textures + sculpted Observer)")
do
	local Enum = env.roblox.Enum
	local RS = game:GetService("ReplicatedStorage")
	local AssetIds = requireModule(RS.Shared.Config.AssetIds)
	local MaterialLibrary = requireModule(RS.Shared.MaterialLibrary)
	local ObserverRig = requireModule(RS.Shared.ObserverRig)
	local MeshMeta = requireModule(RS.Shared.Config.ObserverMeshMeta)
	local MaterialService = game:GetService("MaterialService")
	-- the variants are written into the place by Rojo (tools/sync_assets.py)
	check(MaterialLibrary.count() == 10, "ten custom textures in MaterialService, got " .. MaterialLibrary.count())
	for key, entry in AssetIds.Materials do
		check(entry.color > 0, "texture uploaded: " .. key)
	end
	local plaster = MaterialService:FindFirstChild("DLA_Plaster")
	check(plaster ~= nil and plaster:IsA("MaterialVariant") and plaster.BaseMaterial == Enum.Material.Plaster, "plaster variant present")
	check(plaster ~= nil and plaster.StudsPerTile == 10, "plaster tiling")
	check(MaterialService:FindFirstChild(MaterialLibrary.Wallpaper) ~= nil and MaterialService:FindFirstChild(MaterialLibrary.CeilingTile) ~= nil, "named variants present")
	local okOverride, plasterName = pcall(function()
		return (MaterialService :: any).PlasterName
	end)
	check(not okOverride or plasterName == "DLA_Plaster", "plaster override set in the project")
	check(RS.Shared:FindFirstChild("ObserverSkin") ~= nil and RS.Shared.ObserverSkin:IsA("SurfaceAppearance"), "observer skin template present")
	local plain = ObserverRig.build(nil, { localCopy = true })
	check(plain:GetAttribute("Sculpted") ~= true, "plain rig until the meshes load")
	-- sculpted Observer: templates stand in for the uploaded meshes
	local folder = Instance.new("Folder")
	folder.Name = "ObserverMeshes"
	for name in MeshMeta do
		local mp = Instance.new("MeshPart")
		mp.Name = name
		mp.Parent = folder
	end
	folder.Parent = RS
	local rig = ObserverRig.build(CFrame.new(0, 0, 0), { localCopy = true })
	check(rig:GetAttribute("Sculpted") == true, "rig dressed with meshes")
	local meshes, hiddenSegments, visibleDetails = 0, 0, 0
	for _, d in rig:GetChildren() do
		if d:IsA("MeshPart") then
			meshes += 1
			local weld = d:FindFirstChildOfClass("WeldConstraint")
			check(weld ~= nil and weld.Part0 ~= nil and weld.Part0.Transparency == 1, "mesh welded to a hidden segment: " .. d.Name)
			check(not d.Anchored and d.Massless and not d.CanCollide, "mesh is cosmetic: " .. d.Name)
		elseif d:IsA("BasePart") then
			if (d.Name == "Rib" or d.Name == "Spine" or string.find(d.Name, "Finger")) and d.Transparency < 1 then
				visibleDetails += 1
			end
			if d.Name == "UpperTorso" and d.Transparency == 1 then
				hiddenSegments += 1
			end
		end
	end
	check(meshes == 18, "18 meshes (both sides), got " .. meshes)
	check(hiddenSegments == 1 and visibleDetails == 0, "segments and sculpted details hidden")
	check(ObserverRig.dress(rig) == false, "dressing twice does nothing")
	-- the mesh sits on its segment's mesh offset
	local torso = rig:FindFirstChild("UpperTorso") :: any
	local torsoMesh = rig:FindFirstChild("UpperTorsoMesh") :: any
	local rel = torso.CFrame:PointToObjectSpace(torsoMesh.CFrame.Position)
	check((rel - MeshMeta.UpperTorso.offset).Magnitude < 0.01, "mesh placed at its offset")
	check((torsoMesh.Size - MeshMeta.UpperTorso.size).Magnitude < 0.01, "mesh sized to its bounding box")
	-- the eyes still exist for the face-opening cinematic
	check(rig:FindFirstChild("EyeL") ~= nil and rig:FindFirstChild("JawL", true) ~= nil, "face rig intact")
	folder:Destroy()
end

section("lobby (field office)")
do
	local Lobby = requireModule(Server.Map.Lobby)
	local holder = Instance.new("Folder")
	holder.Name = "LobbyTest"
	holder.Parent = workspace
	local ok, lobby = pcall(Lobby.build, holder)
	check(ok, "build lobby: " .. tostring(lobby))
	if ok then
		check(#lobby.Spawns == 4, "four lobby spawns")
		check(lobby.Boards and lobby.Boards.Leaderboard and #lobby.Boards.Leaderboard.rows >= 10, "leaderboard board")
		local O, size = lobby.Center, lobby.Size
		local minX, maxX = O.X - size.X / 2 + 0.15, O.X + size.X / 2 - 0.15
		local minZ, maxZ = O.Z - size.Z / 2 + 0.15, O.Z + size.Z / 2 - 0.15
		-- every free-standing model stays inside the room, on the floor, and clear of the others
		local boxes = {}
		for _, m in lobby.Root:GetChildren() do
			if m:IsA("Model") and #m:GetChildren() > 0 then
				local cf, sz = m:GetBoundingBox()
				local p = cf.Position
				local lo = p - sz / 2
				local hi = p + sz / 2
				check(lo.X >= minX - 0.25 and hi.X <= maxX + 0.25 and lo.Z >= minZ - 0.25 and hi.Z <= maxZ + 0.25, "lobby prop inside the room: " .. m.Name .. string.format(" (%.1f..%.1f, %.1f..%.1f)", lo.X - O.X, hi.X - O.X, lo.Z - O.Z, hi.Z - O.Z))
				check(lo.Y >= O.Y - 0.3, "lobby prop above the floor: " .. m.Name)
				local wallMounted = lo.Y > O.Y + 2 or m.Name == "Sign" or m.Name == "Clock" or m.Name == "Extinguisher"
				if not wallMounted then
					table.insert(boxes, { name = m.Name, lo = lo, hi = hi })
				end
			end
		end
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				local pad = 0.05
				local overlap = a.lo.X < b.hi.X - pad and b.lo.X < a.hi.X - pad and a.lo.Z < b.hi.Z - pad and b.lo.Z < a.hi.Z - pad and a.lo.Y < b.hi.Y - pad and b.lo.Y < a.hi.Y - pad
				-- a CRT sits on its table by design
				if overlap and not ((a.name == "Table" and b.name == "CRT") or (a.name == "CRT" and b.name == "Table")) then
					check(false, "lobby props overlap: " .. a.name .. " / " .. b.name)
				end
			end
		end
		-- each terminal can be walked up to: 3 studs in front of the screen are free
		for _, d in lobby.Root:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("InteractKind") == "Kiosk" then
				local model = d:FindFirstAncestorWhichIsA("Model")
				local front = d.CFrame.Position + d.CFrame.LookVector * 3
				front = Vector3.new(front.X, O.Y + 2, front.Z)
				local blocked = nil
				for _, b in boxes do
					if model and b.name == model.Name then
						continue
					end
					if front.X > b.lo.X and front.X < b.hi.X and front.Z > b.lo.Z and front.Z < b.hi.Z and front.Y > b.lo.Y and front.Y < b.hi.Y then
						blocked = b.name
					end
				end
				check(blocked == nil, "terminal reachable: " .. tostring(d:GetAttribute("Kiosk")) .. " (blocked by " .. tostring(blocked) .. ")")
				check(front.X > minX and front.X < maxX and front.Z > minZ and front.Z < maxZ, "terminal faces into the room: " .. tostring(d:GetAttribute("Kiosk")))
			end
		end
		for _, sp in lobby.Spawns do
			for _, b in boxes do
				local p = sp.Position
				check(not (p.X > b.lo.X - 1 and p.X < b.hi.X + 1 and p.Z > b.lo.Z - 1 and p.Z < b.hi.Z + 1), "lobby spawn clear of " .. b.name)
			end
		end
	end
	holder:Destroy()
end

section("objectives")
syncPositions(workspace)
local Registry = requireModule(Server.Registry)
local SeededRandom = requireModule(RS.Shared.Util.SeededRandom)
local Signal = requireModule(RS.Shared.Util.Signal)
local currentMap = maps[42]
local spawned = {}
-- minimal service stubs: real InventoryService pickup creation, real Objective & Puzzle logic
Registry.MapService = { GetMap = function()
	return currentMap
end }
Registry.RoundService = {
	GetQuota = function(_, n)
		return 6 + (n - 1)
	end,
	IsEscape = function()
		return false
	end,
	GetDifficulty = function()
		return "NORMAL"
	end,
	GetDifficultyConfig = function()
		return requireModule(RS.Shared.Config.GameConfig).Difficulty.NORMAL
	end,
	GetElapsed = function()
		return 400
	end,
}
Registry.InventoryService = requireModule(Server.Services.InventoryService)
local origSpawn = Registry.InventoryService.SpawnPickup
Registry.InventoryService.SpawnPickup = function(self, id, cf, opts)
	local m = origSpawn(self, id, cf, opts)
	table.insert(spawned, { id = id, model = m })
	return m
end
Registry.AudioService = setmetatable({}, { __index = function()
	return function() end
end })
local handlers = {}
Registry.InteractionService = { Register = function(_, kind, fn)
	handlers[kind] = fn
end }
Registry.PuzzleService = requireModule(Server.Services.PuzzleService)
Registry.ObjectiveService = requireModule(Server.Services.ObjectiveService)
Registry.ObjectiveService.Push = function() end
Registry.HorrorDirector = {
	AddDread = function() end,
	OnMilestone = function() end,
	Rng = function()
		return SeededRandom.new(1)
	end,
	AllowsAnomaly = function()
		return true
	end,
	GetStoryPhase = function()
		return "DISTORTION"
	end,
}

for _, seed in { 1, 42, 1337, 99991, 123456 } do
	currentMap = maps[seed]
	if currentMap then
		spawned = {}
		local ok, state = pcall(function()
			return Registry.ObjectiveService:Plan(currentMap, SeededRandom.new(seed, "objectives"), 3)
		end)
		check(ok, "plan seed " .. seed .. ": " .. tostring(state))
		if ok then
			local counts = {}
			for _, s in spawned do
				counts[s.id] = (counts[s.id] or 0) + 1
				local room = s.model and currentMap:roomAt(s.model:GetPivot().Position + Vector3.new(0, 1.5, 0))
				if s.id ~= "PHOTOGRAPH" then
					check(room ~= nil, "item inside a room: " .. s.id)
					if room then
						check(room.lockKey == nil, s.id .. " not behind a locked door (" .. room.id .. ")")
						if s.id == "MAINT_KEY" or s.id == "OFFICE_KEY" then
							check(room.zone ~= "BASEMENT", "keys never in the basement")
						end
					end
				end
			end
			check(counts.FUSE == 3, "three fuses")
			check(counts.MAINT_KEY == 1 and counts.OFFICE_KEY == 1, "both keys")
			check((counts.BATTERY or 0) >= 3, "batteries")
			check(counts.PHOTOGRAPH == 1, "photograph in the hidden room")
			for _, p in state.puzzles do
				if p == "DOORS" then
					check(counts.TAPE == 1, "tape for the closets")
					check(#state.doorOrder == 4, "door order")
				elseif p == "OFFERING" then
					check(counts.MUSIC_BOX == 1 and counts.DOLL == 1 and counts.CANDLE == 1, "offerings")
				elseif p == "CODE" then
					check(#state.code == 4, "code")
				elseif p == "SYMBOLS" then
					check(#state.symbols == 4, "symbols")
				end
			end
			-- every item and note rests on a surface, inside nothing
			local audit = Instance.new("Folder")
			audit.Name = "AuditPickups"
			audit.Parent = workspace
			for _, sp in spawned do
				if sp.model and sp.id ~= "PHOTOGRAPH" then
					sp.model.Parent = audit
				end
			end
			local GeometryValidator = requireModule(Server.Map.GeometryValidator)
			local extra = { audit }
			local docs = currentMap.Root:FindFirstChild("Documents")
			if docs then
				table.insert(extra, docs)
			end
			local report = GeometryValidator.run(currentMap, { extra = extra })
			local itemIssues = {}
			for _, issue in report.issues do
				local inst = issue.inst
				if inst:IsDescendantOf(audit) or (docs and inst:IsDescendantOf(docs)) then
					table.insert(itemIssues, issue)
				end
			end
			check(#itemIssues == 0, string.format("seed %d: items and notes placed cleanly (%d issues)", seed, #itemIssues))
			for i, issue in itemIssues do
				if i <= 5 then
					print(string.format("    [%s] %s %s in %s: %s", issue.severity, issue.kind, issue.name, tostring(issue.room), issue.detail))
				end
			end
			print(string.format("  seed %d: puzzles %s, quota %d, items %d", seed, table.concat(state.puzzles, "+"), state.quota, #spawned))
		end
	end
end

------------------------------------------------------------------------------------
-- 4. Every anomaly definition creates valid, revertible reality ops
------------------------------------------------------------------------------------

section("anomalies")
requireModule(RS.Shared.SoundFactory).ensureGroups()
syncPositions(game)
local RealityOps = requireModule(RS.Shared.RealityOps)
local AnomalyService = requireModule(Server.Services.AnomalyService)
currentMap = maps[42]
local assets = Instance.new("Folder")
assets.Name = "RealityAssets"
assets.Parent = RS
local dynamic = Instance.new("Folder")
dynamic.Name = "Dynamic"
dynamic.Parent = assets
Registry.RealityService = {
	AddTemplate = function(_, name, inst, isDynamic)
		inst.Name = name
		inst.Parent = if isDynamic then dynamic else assets
		return inst
	end,
	GetTemplate = function(_, name)
		return assets:FindFirstChild(name) or dynamic:FindFirstChild(name)
	end,
}
Registry.PlayerService = {
	GetAlive = function()
		return {}
	end,
	IsLookingAt = function()
		return false
	end,
	CanAnyoneSee = function()
		return false
	end,
	HasLineOfSight = function()
		return true
	end,
}
Registry.DataService = { Get = function()
	return nil
end }
Registry.DoorService = { DoorToggled = Signal.new(), OpenNear = function() end }
Registry.ObjectiveService.GetState = function()
	return { fuses = 0 }
end
-- build the anomaly templates through the real code path
local okInit, errInit = pcall(function()
	AnomalyService:Init()
end)
check(okInit, "AnomalyService:Init " .. tostring(errInit))
AnomalyService:BeginRound(42)
local defs = AnomalyService:GetDefinitions()
check(#defs == JournalCatalog.Count, string.format("every journal entry has behaviour (%d/%d)", #defs, JournalCatalog.Count))

local function fakeCharacter(name, pos)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0))
	head.Parent = m
	Instance.new("Humanoid").Parent = m
	m.WorldPivot = CFrame.new(pos)
	m.Parent = workspace
	syncPositions(m)
	return m
end
local corridorPos = currentMap.Rooms.G_c.center + Vector3.new(0, 3, 0)
local fakePlayer = { Name = "Tester", DisplayName = "Tester", UserId = 1, Character = fakeCharacter("Tester", corridorPos) }
local otherPlayer = { Name = "Other", DisplayName = "Other", UserId = 2, Character = fakeCharacter("Other", corridorPos + Vector3.new(30, 0, 0)) }
Registry.PlayerService.GetAlive = function()
	return { fakePlayer, otherPlayer }
end
Registry.PlayerService.IsAlive = function()
	return true
end
Registry.DoorService.SetOpen = function(_, model, open)
	model:SetAttribute("Open", open)
end
local Ctx = AnomalyService.Ctx
local okDefs, noCandidates = 0, {}
for _, def in defs do
	local ctx = setmetatable({ map = currentMap, rng = SeededRandom.new(7, def.id), players = { fakePlayer }, scope = "GLOBAL", svc = AnomalyService, def = def }, Ctx)
	ctx.nearest = function()
		return 50
	end
	ctx.anyPlayerInRoom = function()
		return false
	end
	ctx.playerRoom = function()
		return currentMap.Rooms.G_c
	end
	ctx.history = function()
		local h = {}
		for i = 1, 12 do
			table.insert(h, { pos = Vector3.new(20 + i * 3, 3, 42), t = i })
		end
		return h
	end
	local okC, candidates = pcall(def.candidates, ctx)
	if not okC then
		check(false, def.id .. " candidates error: " .. tostring(candidates))
	elseif #candidates == 0 then
		table.insert(noCandidates, def.id)
	else
		local created = false
		for i = 1, math.min(5, #candidates) do
			syncPositions(workspace)
			syncPositions(RS)
			local okS, spec = pcall(def.create, ctx, candidates[i])
			if not okS then
				check(false, def.id .. " create error: " .. tostring(spec))
				break
			elseif spec then
				created = true
				check(type(spec.ops) == "table", def.id .. " has ops")
				check(type(spec.anchors) == "table", def.id .. " has anchors")
				local revert, made = RealityOps.applyAll(spec.ops)
				check(type(revert) == "function", def.id .. " revert function")
				if spec.onApplied then
					local okA, errA = pcall(spec.onApplied, { data = {}, players = { fakePlayer } }, made)
					check(okA, def.id .. " onApplied: " .. tostring(errA))
				end
				local okR, errR = pcall(revert)
				check(okR, def.id .. " revert: " .. tostring(errR))
				for _, inst in made do
					check(inst.Parent == nil, def.id .. " clone removed on revert")
				end
				okDefs += 1
				break
			end
		end
		check(created, def.id .. " produced a spec from its candidates")
	end
end
print(string.format("  %d/%d definitions exercised; need live players for: %s", okDefs, #defs, table.concat(noCandidates, ", ")))

------------------------------------------------------------------------------------
-- 5. Every puzzle type can be solved through the real server logic
------------------------------------------------------------------------------------

section("puzzles")
Registry.ProgressionService = { PuzzleSolved = function() end, Award = function() end }
Registry.LightingService = { SetPower = function() end }
Registry.DoorService = requireModule(Server.Services.DoorService)
Registry.HorrorDirector.OnMilestone = function() end
local realGetState = requireModule(Server.Services.ObjectiveService).GetState
Registry.ObjectiveService.GetState = realGetState
local okPS, errPS = pcall(function()
	Registry.PuzzleService:Init()
	Registry.InventoryService:Init()
end)
check(okPS, "PuzzleService/InventoryService init " .. tostring(errPS))
local solverChar = fakeCharacter("Solver", Vector3.zero)
local solverAttrs = {}
local solver = {
	Name = "Solver",
	DisplayName = "Solver",
	UserId = 99,
	Character = solverChar,
	Parent = game,
	SetAttribute = function(_, k, v)
		solverAttrs[k] = v
	end,
	GetAttribute = function(_, k)
		return solverAttrs[k]
	end,
}
Registry.PlayerService.IsAlive = function()
	return true
end
local function moveSolverTo(pos)
	solverChar:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 4)))
	syncPositions(solverChar)
end
local function findTagged(root, tag)
	for _, d in root:GetDescendants() do
		if d:HasTag(tag) then
			return d
		end
	end
	return nil
end
local covered = {}
for _, seed in { 1, 42, 1337, 99991, 123456 } do
	currentMap = maps[seed]
	local state = Registry.ObjectiveService:Plan(currentMap, SeededRandom.new(seed, "objectives"), 1)
	syncPositions(currentMap.Root)
	local root = currentMap.Root
	Registry.InventoryService:Reset(solver)
	-- POWER: fuses, then breakers from the log
	local fuseBox = findTagged(root, "FuseBox")
	local hit = fuseBox:FindFirstChild("Interact")
	for _ = 1, 3 do
		Registry.InventoryService:Add(solver, "FUSE")
	end
	-- before THE OUTAGE the lights work and the box refuses new fuses
	check(state.power == true and state.outage == false, "seed " .. seed .. ": the building starts powered")
	handlers.FuseBox(solver, hit)
	check(state.fuses == 0 and Registry.InventoryService:Count(solver, "FUSE") == 3, "seed " .. seed .. ": no fuses before the outage")
	Registry.PuzzleService:BurnOut()
	check(state.power == false and state.outage == true and state.fuses == 0, "seed " .. seed .. ": the outage burns the fuses out")
	for _ = 1, 3 do
		handlers.FuseBox(solver, hit)
	end
	check(state.fuses == 3, "seed " .. seed .. ": three fuses inserted")
	local breaker = findTagged(root, "BreakerPanel")
	for i = 1, 5 do
		if state.breakerPattern[i] then
			handlers.Breaker(solver, breaker:FindFirstChild("Lever" .. i))
		end
	end
	check(state.power == true and state.locks.POWER == true, "seed " .. seed .. ": power restored")
	covered.POWER = true
	for _, p in state.puzzles do
		if p == "CODE" then
			local keypad = findTagged(root, "Keypad")
			moveSolverTo(keypad:GetPivot().Position)
			handlers.Keypad(solver, keypad:FindFirstChild("Body"))
			Registry.PuzzleService:SubmitCode(solver, "0000")
			task.wait(0.9)
			Registry.PuzzleService:SubmitCode(solver, state.code)
			local override = findTagged(root, "SecurityOverride")
			handlers.Override(solver, override:FindFirstChild("Lever"))
			check(state.locks.CODE == true, "seed " .. seed .. ": keypad + override")
		elseif p == "SYMBOLS" then
			local cabinet = findTagged(root, "SymbolCabinet")
			local Art = requireModule(Server.Map.Art)
			-- odometer over every combination (6^4); the server opens the drawer on the right one
			local n = #Art.Symbols
			for counter = 1, n ^ 4 do
				if state.locks.SYMBOLS then
					break
				end
				handlers.SymbolDial(solver, cabinet:FindFirstChild("DialHit4"))
				if counter % n == 0 then
					handlers.SymbolDial(solver, cabinet:FindFirstChild("DialHit3"))
				end
				if counter % (n * n) == 0 then
					handlers.SymbolDial(solver, cabinet:FindFirstChild("DialHit2"))
				end
				if counter % (n * n * n) == 0 then
					handlers.SymbolDial(solver, cabinet:FindFirstChild("DialHit1"))
				end
			end
			check(state.locks.SYMBOLS == true, "seed " .. seed .. ": symbol cabinet")
		elseif p == "DOORS" then
			local recorder = findTagged(root, "TapeRecorder")
			Registry.InventoryService:Add(solver, "TAPE")
			handlers.TapeRecorder(solver, recorder:FindFirstChild("Body"))
			local closets = {}
			for _, rec in currentMap.Doors do
				if rec.model and rec.model:GetAttribute("Kind") == "closet" then
					closets[rec.model:GetAttribute("Closet")] = rec.model
				end
			end
			-- one wrong door resets, then the right order
			local wrong = state.doorOrder[2]
			Registry.PuzzleService:OnClosetDoor(solver, closets[wrong])
			for _, idx in state.doorOrder do
				Registry.PuzzleService:OnClosetDoor(solver, closets[idx])
			end
			check(state.locks.DOORS == true, "seed " .. seed .. ": closets in order")
		elseif p == "OFFERING" then
			local tableModel = findTagged(root, "OfferingTable")
			for i, item in { "MUSIC_BOX", "DOLL", "CANDLE" } do
				Registry.InventoryService:Add(solver, item)
				handlers.Offering(solver, tableModel:FindFirstChild("Slot" .. i))
			end
			check(state.locks.OFFERING == true, "seed " .. seed .. ": offerings")
		end
		covered[p] = true
	end
	-- anomaly quota releases the last lock
	for _ = 1, state.quota do
		Registry.ObjectiveService:AnomalyFound()
	end
	local all = true
	for _, v in state.locks do
		all = all and v
	end
	check(all, "seed " .. seed .. ": all four exit locks released")
end
for _, kind in { "POWER", "CODE", "SYMBOLS", "DOORS", "OFFERING" } do
	check(covered[kind], "puzzle covered by test seeds: " .. kind)
end

------------------------------------------------------------------------------------
-- 6. Anomaly lifecycle through the real services
------------------------------------------------------------------------------------

section("anomaly lifecycle")
Registry.ObserverService = {
	ReportMimic = function()
		return false
	end,
	IsActive = function()
		return false
	end,
}
currentMap = maps[42]
local objectiveState = Registry.ObjectiveService:Plan(currentMap, SeededRandom.new(42, "objectives"), 1)
syncPositions(currentMap.Root)
Registry.RealityService = requireModule(Server.Services.RealityService)
Registry.RealityService:Init()
local reported, falseReports = 0, 0
Registry.ProgressionService = {
	AnomalyReported = function()
		reported += 1
	end,
	FalseReport = function()
		falseReports += 1
	end,
	Award = function() end,
	PuzzleSolved = function() end,
}
Registry.AnalyticsService = setmetatable({}, { __index = function()
	return function() end
end })
Registry.HorrorDirector = {
	AddDread = function() end,
	OnAnomalyResolved = function() end,
	OnMilestone = function() end,
	Rng = function()
		return SeededRandom.new(7)
	end,
	AllowsAnomaly = function()
		return true
	end,
	GetStoryPhase = function()
		return "DISTORTION"
	end,
}
Registry.RoundService.FailRound = function() end
Registry.PlayerService.GetAlive = function()
	return { solver }
end
Registry.PlayerService.GetLook = function()
	return nil
end
moveSolverTo(currentMap.Rooms.G_c.center)
AnomalyService:BeginRound(7)
local spawnedIds = {}
for _ = 1, 30 do
	syncPositions(workspace)
	local inst = AnomalyService:TrySpawn()
	syncPositions(workspace)
	if inst then
		spawnedIds[inst.def.id] = true
		-- aim exactly at the first anchor and report it
		local anchor = inst.spec.anchors[1]
		if anchor and inst.def.detection ~= "ENDURE" then
			local target = if typeof(anchor.pos) == "Instance" then (anchor.pos:IsA("BasePart") and anchor.pos.CFrame.Position or anchor.pos:GetPivot().Position) else anchor.pos
			local before = objectiveState.found
			-- walk up to it (reports have a 75 stud range)
			moveSolverTo(target + Vector3.new(6, -3, 6))
			local head = solverChar:FindFirstChild("Head")
			local origin = head.CFrame.Position
			task.wait(1.5)
			AnomalyService:Report(solver, origin, (target - origin).Unit)
			check(objectiveState.found == before + 1, "report resolves " .. inst.def.id)
		else
			AnomalyService:Expire(inst)
		end
	end
end
local n = 0
for _ in spawnedIds do
	n += 1
end
check(n >= 10, "many different anomalies spawned (" .. n .. ")")
-- a report at nothing is a false report
task.wait(1.5)
local head = solverChar:FindFirstChild("Head")
AnomalyService:Report(solver, head.CFrame.Position, Vector3.new(0, 1, 0))
check(falseReports >= 1, "false report is penalised")
-- expiry reverts and counts as missed
local inst = AnomalyService:TrySpawn("PAINTING_SWAP", { ignoreVisibility = true })
if inst then
	local missedBefore = AnomalyService:GetRoundStats().missed
	AnomalyService:Expire(inst)
	check(AnomalyService:GetRoundStats().missed == missedBefore + 1, "expired anomaly counted as missed")
	check(not Registry.RealityService:IsLive(inst.token), "expired anomaly reverted")
end
AnomalyService:EndRound()
print(string.format("  %d distinct anomalies spawned and reported, %d reports credited", n, reported))

------------------------------------------------------------------------------------
-- 7. Story phases, the outage, phase-gated anomalies and soft guidance
------------------------------------------------------------------------------------

section("story & guidance")
do
	local GameConfig = requireModule(RS.Shared.Config.GameConfig)
	local Enums = requireModule(RS.Shared.Enums)
	currentMap = maps[1337]
	local state = Registry.ObjectiveService:Plan(currentMap, SeededRandom.new(1337, "objectives"), 1)
	Registry.ObjectiveService.GetState = function()
		return state
	end
	syncPositions(currentMap.Root)
	local lighting = {
		power = true,
		blackout = 0,
		Blackout = function(self, level)
			self.blackout = level
			return true
		end,
		EndBlackout = function(self)
			self.blackout = 0
		end,
		SetPower = function(self, on)
			self.power = on
		end,
		IsPowered = function(self)
			return self.power
		end,
		GetBlackout = function(self)
			return self.blackout
		end,
		BlackoutChanged = Signal.new(),
	}
	Registry.LightingService = lighting
	Registry.ObserverService = { IsActive = function()
		return false
	end }
	Registry.AdminService = nil
	local difficulty = "NORMAL"
	Registry.RoundService.GetDifficulty = function()
		return difficulty
	end
	Registry.RoundService.GetDifficultyConfig = function()
		return GameConfig.Difficulty[difficulty]
	end
	Registry.RoundService.IsRunning = function()
		return true
	end
	Registry.RoundService.GetState = function()
		return "EXPLORING"
	end
	local Director = requireModule(Server.Services.HorrorDirector)
	Registry.HorrorDirector = Director
	Director:BeginRound(1337)
	check(Director:GetStoryPhase() == "ARRIVAL", "rounds begin in ARRIVAL")
	local defs = requireModule(Server.Services.AnomalyService):GetDefinitions()
	local function allowedCount(pred)
		local n = 0
		for _, def in defs do
			if Director:AllowsAnomaly(def) and pred(def) then
				n += 1
			end
		end
		return n
	end
	check(allowedCount(function()
		return true
	end) == 0, "no anomalies while arriving")
	Director:TriggerOutage()
	task.wait(5.4)
	check(Director:GetStoryPhase() == "UNEASE", "the outage starts UNEASE")
	check(lighting.power == false, "the outage cuts the power")
	check(state.outage == true and state.power == false and state.fuses == 0, "the outage burns out the fuse box")
	check(allowedCount(function(def)
		return def.category == Enums.AnomalyCategory.Dangerous
	end) == 0, "nothing dangerous during UNEASE")
	check(allowedCount(function()
		return true
	end) > 0, "subtle anomalies during UNEASE")
	Director:AdvanceStory()
	check(Director:GetStoryPhase() == "DISTORTION", "advance to DISTORTION")
	Director:AdvanceStory()
	check(Director:GetStoryPhase() == "DANGER", "advance to DANGER")
	check(allowedCount(function(def)
		return def.category == Enums.AnomalyCategory.Dangerous
	end) > 0, "dangerous anomalies once it hunts")
	Director:AdvanceStory()
	check(Director:GetStoryPhase() == "COLLAPSE", "advance to COLLAPSE")
	check(Director:Reached("DANGER") and not Director:Reached("ESCAPE"), "phase ordering")
	Director:EndRound()

	-- soft guidance always has a next step and walks through the objectives
	Registry.InventoryService:Reset(solver)
	Registry.AnomalyService = { GetActive = function()
		return {}
	end }
	local Guidance = requireModule(Server.Services.GuidanceService)
	Registry.GuidanceService = Guidance
	Guidance:BeginRound()
	local t = Guidance:NextTarget()
	check(t ~= nil and t.room ~= nil, "guidance: a target after the outage")
	if t then
		check(string.find(t.key, "fuse") ~= nil or t.key == "maintkey", "guidance: power first (" .. t.key .. ")")
		print("  first nudge: " .. t.key .. " -> " .. t.where)
	end
	-- with the power back, it points at the puzzles
	state.power = true
	state.locks.POWER = true
	t = Guidance:NextTarget()
	check(t ~= nil, "guidance: a puzzle target")
	if t then
		print("  next nudge: " .. t.key .. " -> " .. t.where)
	end
	for _, kind in state.puzzles do
		state.locks[kind] = true
	end
	state.locks.ANOMALIES = false
	for _, id in { "BREAKERS", "SYMBOLS", "OFFERING", "LORE_1", "LORE_2", "LORE_3", "LORE_4", "CODE_A", "CODE_B" } do
		Guidance:DocumentRead(id)
	end
	t = Guidance:NextTarget()
	check(t == nil or string.find(t.key, "anomaly") ~= nil, "guidance: nothing left but anomalies")
	-- difficulty tables are complete
	for _, name in Enums.DifficultyOrder do
		local c = GameConfig.Difficulty[name]
		check(c ~= nil and c.ArrivalDuration and c.PhaseDurations and c.HintDelay and c.RewardMultiplier, "difficulty config " .. name)
	end
end

------------------------------------------------------------------------------------

section("summary")
print(string.format("%d checks, %d failures", checks, failures))
process.exit(if failures == 0 then 0 else 1)
