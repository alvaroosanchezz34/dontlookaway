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

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local placePath = process.args[1] or "build/test.rbxlx"
local game = roblox.deserializePlace(fs.readFile(placePath))
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

------------------------------------------------------------------------------------
-- Engine polyfills
------------------------------------------------------------------------------------

-- BasePart.Position derives from CFrame in the engine
for _, className in { "BasePart", "Part", "WedgePart", "MeshPart", "TrussPart", "CornerWedgePart" } do
	roblox.implementProperty(className, "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = CFrame.new(value) * (self.CFrame - self.CFrame.Position)
	end)
end

local function boundingParts(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

roblox.implementMethod("Model", "GetPivot", function(self)
	local primary = self.PrimaryPart
	if primary then
		return primary.CFrame
	end
	return self.WorldPivot
end)

roblox.implementMethod("Model", "PivotTo", function(self, target)
	local current = self:GetPivot()
	local delta = target * current:Inverse()
	for _, p in boundingParts(self) do
		p.CFrame = delta * p.CFrame
	end
	if not self.PrimaryPart then
		self.WorldPivot = target
	end
end)

roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local parts = boundingParts(self)
	if #parts == 0 then
		return self.WorldPivot, Vector3.zero
	end
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in parts do
		local half = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = p.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minV = minV:Min(w)
					maxV = maxV:Max(w)
				end
			end
		end
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)

roblox.implementMethod("Instance", "FindFirstAncestorWhichIsA", function(self, className)
	local p = self.Parent
	while p do
		if p:IsA(className) then
			return p
		end
		p = p.Parent
	end
	return nil
end)

roblox.implementProperty("Attachment", "WorldCFrame", function(self)
	local parent = self.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame * self.CFrame
	end
	return self.CFrame
end, function(self, value)
	local parent = self.Parent
	if parent and parent:IsA("BasePart") then
		self.CFrame = parent.CFrame:Inverse() * value
	else
		self.CFrame = value
	end
end)

roblox.implementProperty("Attachment", "WorldPosition", function(self)
	return self.WorldCFrame.Position
end, function(self, value)
	self.WorldCFrame = CFrame.new(value)
end)

roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return false
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)

-- Lune does not derive Position from CFrame; store it explicitly before reads
local function syncPositions(root)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Position = d.CFrame.Position
		end
	end
end

roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Players", "GetPlayers", function()
	return {}
end)
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction)
	-- no physics in Lune: every ray reaches its end on a "floor"
	return { Position = origin + direction, Normal = Vector3.new(0, 1, 0), Instance = nil, Distance = direction.Magnitude }
end)
roblox.implementMethod("HttpService", "GenerateGUID", function()
	return tostring(math.random(1, 2 ^ 30)) .. "-" .. tostring(os.clock())
end)
roblox.implementMethod("RemoteEvent", "FireClient", function() end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function() end)
roblox.implementProperty("RemoteEvent", "OnServerEvent", function()
	return { Connect = function() end }
end)

-- engine-only Humanoid behaviour
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
roblox.implementMethod("Humanoid", "MoveTo", function() end)
roblox.implementMethod("Humanoid", "Move", function() end)

-- Random (deterministic xorshift, same API surface the game uses)
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = math.floor((seed or os.clock() * 1e6) % 2147483647)
	if s == 0 then
		s = 1234567
	end
	return setmetatable({ s = s }, Random)
end
function Random:_next()
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end
function Random:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local TweenInfo = { new = function(...)
	return { ... }
end }

local function makeSignal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		Wait = function() end,
		Fire = function(_, ...)
			for _, h in handlers do
				h(...)
			end
		end,
	}
end

local tagged = {}
local function scanTags(tag)
	local list = {}
	for _, d in game:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(list, d)
		end
	end
	return list
end

local CollectionServiceStub = {
	GetTagged = function(_, tag)
		return scanTags(tag)
	end,
	GetInstanceAddedSignal = function()
		return makeSignal()
	end,
	GetInstanceRemovedSignal = function()
		return makeSignal()
	end,
}

local services = {}
local function getService(_, name)
	if name == "CollectionService" then
		return CollectionServiceStub
	end
	if services[name] then
		return services[name]
	end
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	if ok and s then
		return s
	end
	-- engine services that do not exist in Lune
	local stub = setmetatable({ Name = name }, {
		__index = function(t, k)
			if k == "Heartbeat" or k == "Stepped" or k == "RenderStepped" or k == "PlayerAdded" or k == "PlayerRemoving" then
				local sig = makeSignal()
				rawset(t, k, sig)
				return sig
			end
			return function()
				return nil
			end
		end,
	})
	services[name] = stub
	return stub
end

local workspace = game:GetService("Workspace")
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return getService
		end
		if k == "Workspace" then
			return workspace
		end
		return (game :: any)[k]
	end,
})

------------------------------------------------------------------------------------
-- Module loader
------------------------------------------------------------------------------------

local cache = {}
local requireModule

local function envFor(scriptInstance)
	local env = {
		script = scriptInstance,
		game = gameProxy,
		workspace = workspace,
		require = function(target)
			return requireModule(target)
		end,
		Instance = Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Font = roblox.Font,
		Random = Random,
		TweenInfo = TweenInfo,
		RaycastParams = { new = function()
			return {}
		end },
		task = require("@lune/task"),
		-- Roblox os.clock is wall-clock time; Lune's is CPU time
		os = setmetatable({ clock = function()
			return require("@lune/datetime").now().unixTimestampMillis / 1000
		end }, { __index = os }),
		typeof = typeof,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
	return setmetatable(env, { __index = _G })
end

function requireModule(target)
	if cache[target] ~= nil then
		return cache[target]
	end
	assert(target:IsA("ModuleScript"), "require target is not a ModuleScript: " .. target:GetFullName())
	local source = target.Source
	local fn = luau.load(source, { debugName = target:GetFullName(), environment = envFor(target) })
	local result = fn()
	cache[target] = result
	return result
end

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
Registry.HorrorDirector = { AddDread = function() end, OnMilestone = function() end, Rng = function()
	return SeededRandom.new(1)
end }

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
Registry.HorrorDirector = { AddDread = function() end, OnAnomalyResolved = function() end, OnMilestone = function() end, Rng = function()
	return SeededRandom.new(3)
end }
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

section("summary")
print(string.format("%d checks, %d failures", checks, failures))
process.exit(if failures == 0 then 0 else 1)
