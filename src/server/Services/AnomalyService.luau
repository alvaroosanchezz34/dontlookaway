--[[
	AnomalyService
	THE CORE SYSTEM. Selects, activates, tracks, validates and cleans up anomalies.

	Definitions live in ServerScriptService/Server/Anomalies/*. Each definition:
		id, category, rarity, difficulty (1-5), scopes = {"GLOBAL","PLAYER","TEAM"},
		detection ("FOCUS" | "INTERACT" | "ENDURE"), minPlayers?, maxUses?,
		requires? (function(ctx) -> boolean), weight?,
		candidates(ctx) -> { candidate },
		create(ctx, candidate) -> spec | nil
	A spec describes the change:
		ops            RealityOps applied through RealityService
		anchors        { { pos = Vector3 | Instance, radius = number } } report targets
		checkPoints?   points that must be unseen before activation (default anchors)
		lifetime?      seconds before it is "missed"
		claim?         instance reserved while active
		interactTarget? server instance players may interact with (INTERACT)
		update?(inst, dt) -> "resolve" | "fail" | "expire" | nil
		onApplied?(inst, createdInstances)
		onResolve?(inst, player), onExpire?(inst), onFail?(inst, player)
		onInteract?(inst, player) -> "resolve" | "fail" | nil
		onFlashlight?(inst, player, on)
		keepOnResolve?  do not revert when solved (rare)

	Rules enforced here:
	  * an anomaly only activates where no player in its scope is looking
	  * the server alone decides whether a report hits an anomaly
	  * every change is reversible and reverted on resolve / expire / round end
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)
local Props = require(script.Parent.Parent.Map.Props)
local Build = require(script.Parent.Parent.Map.Build)
local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)

local AnomalyService = {}

AnomalyService.Resolved = Signal.new() -- (inst, player)
AnomalyService.Missed = Signal.new() -- (inst)

local RARITY_WEIGHT = { COMMON = 10, UNCOMMON = 6, RARE = 2.4, LEGENDARY = 0.35 }

local safeAnchors: (points: { Vector3 }) -> boolean
local placementSafe: (inst: any, def: any) -> boolean
local cleanup: (inst: any, revert: boolean) -> ()

local definitions: { any } = {}
local defsById: { [string]: any } = {}
local active: { [string]: any } = {}
local uses: { [string]: number } = {}
local claims: { [Instance]: string } = {}
local history: { [Player]: { { pos: Vector3, t: number } } } = {}
local lastReport: { [Player]: number } = {}
local recentResolved: { { pos: Vector3, t: number } } = {}
local rng = SeededRandom.new(1)
local counter = 0
local roundStats = { spawned = 0, found = 0, missed = 0, misreports = {} :: { [Player]: number } }
local enabled = false
local templatesBuilt = false

------------------------------------------------------------------------------------
-- Templates for things anomalies add to reality
------------------------------------------------------------------------------------

local function stripTags(model: Instance)
	for _, d in model:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
	end
	for _, tag in model:GetTags() do
		model:RemoveTag(tag)
	end
end

local function buildTemplates()
	if templatesBuilt then
		return
	end
	templatesBuilt = true
	local RS = Registry.RealityService
	local r = SeededRandom.new(77, "templates")
	local origin = CFrame.new()
	local chair = Props.woodChair(nil, origin, r)
	stripTags(chair)
	RS:AddTemplate("Chair", chair)
	local mannequin = Props.mannequin(nil, origin)
	stripTags(mannequin)
	RS:AddTemplate("Mannequin", mannequin)
	local resident = Props.resident(nil, origin, r, "standing")
	stripTags(resident)
	RS:AddTemplate("Resident", resident)
	local pale = Props.paleFigure(nil, origin)
	stripTags(pale)
	RS:AddTemplate("PaleFigure", pale)
	-- a distant figure: a static, anchored silhouette of the Observer
	local figure = ObserverRig.build(origin)
	for _, d in figure:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Motor6D") or d:IsA("Humanoid") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	stripTags(figure)
	figure.Name = "Figure"
	RS:AddTemplate("Figure", figure)
	-- doors that should not exist
	local function falseDoor(name: string, plateText: string?, ajar: boolean?)
		local m = Build.model(nil, name, origin)
		local frameCol = Color3.fromRGB(52, 40, 30)
		Build.part(m, "FrameL", Vector3.new(0.45, 10.2, 0.5), origin * CFrame.new(-2.05, 5.1, -0.25), frameCol, Enum.Material.Wood)
		Build.part(m, "FrameR", Vector3.new(0.45, 10.2, 0.5), origin * CFrame.new(2.05, 5.1, -0.25), frameCol, Enum.Material.Wood)
		Build.part(m, "FrameT", Vector3.new(4.55, 0.45, 0.5), origin * CFrame.new(0, 10.1, -0.25), frameCol, Enum.Material.Wood)
		local panelCF = origin * CFrame.new(0, 4.9, -0.2)
		if ajar then
			Build.part(m, "Dark", Vector3.new(3.6, 9.6, 0.1), origin * CFrame.new(0, 4.9, -0.05), Color3.fromRGB(4, 4, 4), Enum.Material.SmoothPlastic)
			panelCF = origin * CFrame.new(-1.8, 4.9, -0.3) * CFrame.Angles(0, math.rad(-28), 0) * CFrame.new(1.8, 0, 0)
			local glow = Build.part(m, "Glow", Vector3.new(0.2, 0.2, 0.2), origin * CFrame.new(0.6, 6, 1.5), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
			Build.light(glow, "PointLight", { Brightness = 0.7, Range = 9, Color = Color3.fromRGB(255, 190, 140), Shadows = false })
		end
		local panel = Build.part(m, "Panel", Vector3.new(3.6, 9.6, 0.3), panelCF, Color3.fromRGB(78, 62, 48), Enum.Material.Wood)
		Build.detail(m, "Handle", Vector3.new(0.45, 0.15, 0.15), panelCF * CFrame.new(1.3, -0.6, -0.22), Props.Colors.metal, Enum.Material.Metal)
		if plateText then
			Props.roomPlate(m, origin * CFrame.new(3.3, 6.5, 0), plateText)
		end
		stripTags(m)
		m.PrimaryPart = panel
		return m
	end
	RS:AddTemplate("FalseDoor", falseDoor("FalseDoor", nil, false))
	RS:AddTemplate("B13Door", falseDoor("B13Door", "B-13", true))
	RS:AddTemplate("ZeroDoor", falseDoor("ZeroDoor", "0", true))
	-- a shadow with nobody to cast it
	local shadow = Build.part(nil, "Shadow", Vector3.new(3, 8, 0.02), origin * CFrame.new(0, 4.4, -0.06), Color3.new(), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false })
	local gui = Build.surfaceGui(shadow, Enum.NormalId.Front, 30)
	gui.LightInfluence = 0
	local body = Build.frame(gui, { Size = UDim2.fromScale(0.36, 0.78), Position = UDim2.fromScale(0.32, 0.2), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.35 })
	Build.corner(body, 0.4)
	local head = Build.frame(gui, { Size = UDim2.fromScale(0.26, 0.12), Position = UDim2.fromScale(0.37, 0.06), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.35 })
	Build.corner(head, 0.5)
	local arm = Build.frame(gui, { Size = UDim2.fromScale(0.07, 0.6), Position = UDim2.fromScale(0.68, 0.25), Rotation = -8, BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.35 })
	Build.corner(arm, 0.5)
	RS:AddTemplate("Shadow", shadow)
	-- wet footprint
	local print_ = Build.part(nil, "Footprint", Vector3.new(0.7, 0.03, 1.5), origin * CFrame.new(0, 0.02, 0), Color3.fromRGB(16, 18, 18), Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.3, CanCollide = false, CastShadow = false })
	RS:AddTemplate("Footprint", print_)
end

------------------------------------------------------------------------------------
-- Context helpers handed to definitions
------------------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

function Ctx:tagged(tag: string): { Instance }
	local list = {}
	local root = self.map.Root
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(root) and not claims[inst] then
			table.insert(list, inst)
		end
	end
	table.sort(list, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return list
end

function Ctx:roomOf(inst: Instance)
	local id = inst:GetAttribute("Room")
	if type(id) == "string" and self.map.Rooms[id] then
		return self.map.Rooms[id]
	end
	local pos = Util.boundingSphere(inst)
	return self.map:roomAt(pos + Vector3.new(0, 1, 0))
end

function Ctx:center(inst: Instance): (Vector3, number)
	return Util.boundingSphere(inst)
end

function Ctx:anchor(inst: Instance, extra: number?)
	local c, r = Util.boundingSphere(inst)
	return { pos = c, radius = math.max(1.5, r + (extra or 0.5)) }
end

-- Distance from a point to the nearest scope player.
function Ctx:nearest(point: Vector3): number
	local best = math.huge
	for _, p in self.players do
		local root = Util.getRoot(p)
		if root then
			best = math.min(best, (root.Position - point).Magnitude)
		end
	end
	return best
end

function Ctx:anyPlayerInRoom(room): boolean
	for _, p in Players:GetPlayers() do
		local root = Util.getRoot(p)
		if root and self.map:roomAt(root.Position) == room then
			return true
		end
	end
	return false
end

function Ctx:playerRoom(player: Player)
	local root = Util.getRoot(player)
	return root and self.map:roomAt(root.Position)
end

function Ctx:template(name: string): Instance
	return Registry.RealityService:GetTemplate(name) :: Instance
end

function Ctx:history(player: Player)
	return history[player] or {}
end

function Ctx:isDifficult(): boolean
	local d = Registry.RoundService:GetDifficulty()
	return d == Enums.Difficulty.Hard or d == Enums.Difficulty.Nightmare
end

AnomalyService.Ctx = Ctx

------------------------------------------------------------------------------------
-- Activation
------------------------------------------------------------------------------------

local function scopePlayers(def, alive: { Player }): (string, { Player })
	local scopes = def.scopes or { Enums.AnomalyScope.Global }
	local options = {}
	for _, s in scopes do
		if s == Enums.AnomalyScope.Global then
			table.insert(options, { item = s, weight = 1 })
		elseif s == Enums.AnomalyScope.Player then
			table.insert(options, { item = s, weight = if #alive > 1 then 1.1 else 0.6 })
		elseif s == Enums.AnomalyScope.Team and #alive > 2 then
			table.insert(options, { item = s, weight = 0.6 })
		end
	end
	local scope = rng:Weighted(options) or scopes[1]
	if scope == Enums.AnomalyScope.Global then
		return scope, alive
	elseif scope == Enums.AnomalyScope.Player then
		-- prefer the player who is most alone
		local best, bestD = nil, -1
		for _, p in alive do
			local root = Util.getRoot(p)
			local d = math.huge
			for _, q in alive do
				local other = Util.getRoot(q)
				if q ~= p and root and other then
					d = math.min(d, (root.Position - other.Position).Magnitude)
				end
			end
			if d == math.huge then
				d = 0
			end
			d += rng:Number(0, 20)
			if d > bestD then
				best, bestD = p, d
			end
		end
		return scope, { best or alive[1] }
	else
		local subset = table.clone(alive)
		rng:Shuffle(subset)
		local n = math.max(1, math.floor(#subset / 2))
		local list = {}
		for i = 1, n do
			table.insert(list, subset[i])
		end
		return scope, list
	end
end

local function anchorPosition(anchor): Vector3?
	local pos = anchor.pos
	if typeof(pos) == "Instance" then
		if not pos.Parent then
			return nil
		end
		local c = Util.boundingSphere(pos)
		return c
	end
	return pos
end

local function isUnseen(points: { Vector3 }, players: { Player }): boolean
	-- slightly wider than the screen so peripheral vision counts as "looking"
	local seen = Registry.PlayerService:CanAnyoneSee(points, 62, 240, nil, players)
	return not seen
end

local function eligible(def, alive: { Player }, phase: { [string]: any }): boolean
	if active[def.id] then
		return false
	end
	if (uses[def.id] or 0) >= (def.maxUses or (if def.rarity == "COMMON" then 2 else 1)) then
		return false
	end
	if def.minPlayers and #alive < def.minPlayers then
		return false
	end
	-- the story phase decides how strange the building may get (no danger while
	-- players are still learning it, no legendary events early)
	if Registry.HorrorDirector and not Registry.HorrorDirector:AllowsAnomaly(def) then
		return false
	end
	if def.notInEscape and phase.escape then
		return false
	end
	if phase.darkOnly and def.category ~= Enums.AnomalyCategory.Psychological and def.category ~= Enums.AnomalyCategory.Environment and def.category ~= Enums.AnomalyCategory.Dangerous then
		return false
	end
	return true
end

local function weightOf(def, alive: { Player }): number
	local w = (RARITY_WEIGHT[def.rarity] or 1) * (def.weight or 1)
	if def.category == Enums.AnomalyCategory.Dangerous then
		w *= Registry.RoundService:GetDifficultyConfig().DangerousWeight
	end
	-- novelty: favour anomalies nobody here has discovered yet
	local unseenBy = 0
	for _, p in alive do
		local data = Registry.DataService:Get(p)
		if data and not data.journal[def.id] then
			unseenBy += 1
		end
	end
	if #alive > 0 and unseenBy > 0 then
		w *= 1 + 0.4 * (unseenBy / #alive)
	end
	return w
end

local function register(def, ctx, spec, scope: string, players: { Player })
	counter += 1
	local key = def.id .. "#" .. counter
	local lifetime = spec.lifetime or Registry.RoundService:GetDifficultyConfig().AnomalyLifetime
	local inst = {
		key = key,
		def = def,
		ctx = ctx,
		spec = spec,
		scope = scope,
		players = players,
		startedAt = os.clock(),
		expiresAt = os.clock() + lifetime,
		data = spec.data or {},
		token = nil,
		created = {},
	}
	if spec.claim then
		claims[spec.claim] = key
	end
	local token, created = Registry.RealityService:Apply(spec.ops or {}, scope, players)
	inst.token = token
	inst.created = created
	active[def.id] = inst
	uses[def.id] = (uses[def.id] or 0) + 1
	roundStats.spawned += 1
	if spec.onApplied then
		local ok, err = pcall(spec.onApplied, inst, created)
		if not ok then
			warn("[AnomalyService] onApplied", def.id, err)
		end
	end
	-- a subtle, deniable cue now and then
	if spec.cue ~= false and rng:Chance(0.3) then
		local firstAnchor = spec.anchors and spec.anchors[1]
		local at = firstAnchor and anchorPosition(firstAnchor)
		if at then
			local listeners = {}
			for _, p in players do
				local root = Util.getRoot(p)
				if root and (root.Position - at).Magnitude < 45 then
					table.insert(listeners, p)
				end
			end
			Registry.AudioService:PlayAtFor(listeners, "RealityShift", at, { volume = 0.5 })
		end
	end
	if Registry.AdminService then
		Registry.AdminService:Log(string.format("anomaly %s (%s) -> %d player(s)", def.id, scope, #players))
	end
	return inst
end

-- Anchors must not sit on top of a player (nothing appears inside someone).
safeAnchors = function(points: { Vector3 }): boolean
	for _, p in Players:GetPlayers() do
		local root = Util.getRoot(p)
		if root then
			for _, pt in points do
				if (root.Position - pt).Magnitude < 3.5 then
					return false
				end
			end
		end
	end
	return true
end

-- Solid parts an anomaly created must not overlap players or block a doorway.
placementSafe = function(inst, def): boolean
	local map = Registry.MapService:GetMap()
	local doorAnomaly = string.find(def.id, "DOOR") ~= nil
	for _, created in inst.created or {} do
		local parts = {}
		if typeof(created) == "Instance" then
			if created:IsA("BasePart") then
				table.insert(parts, created)
			end
			for _, d in created:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
		end
		for _, part in parts do
			if part.CanCollide and part.Transparency < 0.95 then
				local half = part.Size / 2
				for _, p in Players:GetPlayers() do
					local root = Util.getRoot(p)
					if root then
						local rel = part.CFrame:PointToObjectSpace(root.Position)
						if math.abs(rel.X) < half.X + 1.2 and math.abs(rel.Y) < half.Y + 2.5 and math.abs(rel.Z) < half.Z + 1.2 then
							return false
						end
					end
				end
				if map and not doorAnomaly then
					for _, door in map.Doors do
						local rel = part.CFrame:PointToObjectSpace(door.center + Vector3.new(0, 3, 0))
						if math.abs(rel.X) < half.X + 1 and math.abs(rel.Y) < half.Y + 3 and math.abs(rel.Z) < half.Z + 1 then
							return false
						end
					end
				end
			end
		end
	end
	return true
end

-- Tries to activate one anomaly. Returns the instance or nil.
function AnomalyService:TrySpawn(forcedId: string?, opts: { [string]: any }?)
	opts = opts or {}
	local map = Registry.MapService:GetMap()
	if not map or not enabled then
		return nil
	end
	local alive = Registry.PlayerService:GetAlive()
	if #alive == 0 then
		return nil
	end
	local phase = { elapsed = Registry.RoundService:GetElapsed(), escape = Registry.RoundService:IsEscape(), darkOnly = opts.darkOnly }
	local pool = {}
	for _, def in definitions do
		if forcedId then
			if def.id == forcedId then
				table.insert(pool, { item = def, weight = 1 })
			end
		elseif eligible(def, alive, phase) then
			table.insert(pool, { item = def, weight = weightOf(def, alive) })
		end
	end
	for _ = 1, 6 do
		local def = rng:Weighted(pool)
		if not def then
			return nil
		end
		if forcedId and active[def.id] then
			return nil
		end
		local scope, players = scopePlayers(def, alive)
		if opts.scope then
			scope = opts.scope
			players = if opts.players then opts.players elseif scope == Enums.AnomalyScope.Player then { alive[1] } else alive
		end
		local ctx = setmetatable({ map = map, rng = rng, players = players, scope = scope, svc = self, def = def }, Ctx)
		local ok, requiresOk = pcall(function()
			return not def.requires or def.requires(ctx)
		end)
		if ok and requiresOk then
			local okC, candidates = pcall(def.candidates, ctx)
			if okC and type(candidates) == "table" and #candidates > 0 then
				-- prefer candidates at a meaningful distance from the players
				local scored = {}
				for _, c in candidates do
					local pos = if typeof(c) == "Instance" then Util.boundingSphere(c) elseif type(c) == "table" and c.pos then c.pos elseif typeof(c) == "Vector3" then c else nil
					local score = rng:Number(0, 1)
					if pos then
						local d = ctx:nearest(pos)
						if d < 12 then
							score += 3
						elseif d <= 80 then
							score += 0
						elseif d <= 140 then
							score += 1.5
						else
							score += 4
						end
					end
					table.insert(scored, { c = c, s = score })
				end
				table.sort(scored, function(a, b)
					return a.s < b.s
				end)
				for i = 1, math.min(#scored, 10) do
					local candidate = scored[i].c
					local okS, spec = pcall(def.create, ctx, candidate)
					if not okS then
						warn("[AnomalyService] create failed", def.id, spec)
					elseif spec then
						local points = {}
						for _, a in spec.checkPoints or spec.anchors or {} do
							local p = if typeof(a) == "Vector3" then a else anchorPosition(a)
							if p then
								table.insert(points, p)
							end
						end
						if (opts.ignoreVisibility or isUnseen(points, players)) and safeAnchors(points) then
							local inst = register(def, ctx, spec, scope, players)
							-- reality must never trap anyone: solid geometry it created may not
							-- overlap a player or fill a doorway (door anomalies excepted)
							if inst and not placementSafe(inst, def) then
								warn("[AnomalyService] unsafe placement reverted:", def.id)
								cleanup(inst, true)
								active[def.id] = nil
								uses[def.id] = math.max(0, (uses[def.id] or 1) - 1)
								roundStats.spawned -= 1
							elseif inst then
								return inst
							end
						end
					end
				end
			end
		end
		-- try another definition
		for i, entry in pool do
			if entry.item == def then
				table.remove(pool, i)
				break
			end
		end
	end
	return nil
end

------------------------------------------------------------------------------------
-- Resolution
------------------------------------------------------------------------------------

cleanup = function(inst, revert: boolean)
	if active[inst.def.id] == inst then
		active[inst.def.id] = nil
	end
	if inst.spec.claim then
		claims[inst.spec.claim] = nil
	end
	if revert and not inst.spec.keepOnResolve then
		if inst.spec.beforeRevert then
			pcall(inst.spec.beforeRevert, inst)
		end
		Registry.RealityService:Revert(inst.token)
	end
	if inst.spec.cleanup then
		pcall(inst.spec.cleanup, inst)
	end
end

local function inScope(inst, player: Player): boolean
	return table.find(inst.players, player) ~= nil or inst.scope == Enums.AnomalyScope.Global
end

function AnomalyService:Resolve(inst, player: Player?, how: string?)
	if active[inst.def.id] ~= inst then
		return
	end
	cleanup(inst, true)
	roundStats.found += 1
	local anchor = inst.spec.anchors and inst.spec.anchors[1]
	local at = anchor and anchorPosition(anchor)
	if at then
		table.insert(recentResolved, { pos = at, t = os.clock() })
	end
	if inst.spec.onResolve then
		pcall(inst.spec.onResolve, inst, player)
	end
	Registry.ObjectiveService:AnomalyFound()
	Registry.HorrorDirector:OnAnomalyResolved(inst)
	-- credit: the reporter, plus scope players close enough to share the moment
	local credited = {}
	if player then
		table.insert(credited, player)
	end
	if at then
		for _, p in inst.players do
			local root = Util.getRoot(p)
			if p ~= player and root and (root.Position - at).Magnitude < 35 then
				table.insert(credited, p)
			end
		end
	end
	Registry.ProgressionService:AnomalyReported(player, credited, inst.def, inst)
	for _, p in Players:GetPlayers() do
		if p == player then
			Net.fire(p, "Effect", { name = "RealitySnap", at = at })
		elseif Registry.PlayerService:IsAlive(p) and player then
			Net.fire(p, "Notify", { kind = "team", text = string.format("%s spotted an anomaly", player.DisplayName) })
		end
	end
	if at then
		Registry.AudioService:PlayAt("RealitySnap", at, { volume = 0.8 })
	end
	if player then
		Registry.AnalyticsService:AnomalyDiscovered(player, inst.def.id)
	end
	inst.resolvedHow = how
	AnomalyService.Resolved:Fire(inst, player)
end

function AnomalyService:Expire(inst)
	if active[inst.def.id] ~= inst then
		return
	end
	cleanup(inst, true)
	if inst.spec.onExpire then
		pcall(inst.spec.onExpire, inst)
	end
	if inst.spec.noMiss then
		return
	end
	roundStats.missed += 1
	Registry.AnalyticsService:AnomalyMissed(inst.def.id)
	Registry.HorrorDirector:AddDread(4, "missed")
	AnomalyService.Missed:Fire(inst)
	local maxMissed = Registry.RoundService:GetDifficultyConfig().MaxMissed
	if roundStats.missed >= maxMissed then
		Registry.RoundService:FailRound(Enums.Ending.FailedToIdentify)
	elseif roundStats.missed >= maxMissed - 2 then
		Net.fireAll("Notify", { kind = "warning", text = "Reality is slipping. Too many changes went unnoticed." })
	end
end

function AnomalyService:Fail(inst, player: Player?)
	if active[inst.def.id] ~= inst then
		return
	end
	cleanup(inst, true)
	if inst.spec.onFail then
		pcall(inst.spec.onFail, inst, player)
	end
	Registry.HorrorDirector:AddDread(8, "dangerous")
end

------------------------------------------------------------------------------------
-- Reports (FOCUS detection)
------------------------------------------------------------------------------------

local function matchScore(origin: Vector3, dir: Vector3, center: Vector3, radius: number): number?
	local t = (center - origin):Dot(dir)
	if t < 0 or t > GameConfig.Report.MaxDistance then
		return nil
	end
	local closest = origin + dir * t
	local perpendicular = (closest - center).Magnitude
	local allowed = radius + 0.6 + t * 0.045
	if perpendicular > allowed then
		return nil
	end
	return perpendicular / allowed
end

function AnomalyService:Report(player: Player, origin: any, dir: any)
	if not enabled or not Registry.PlayerService:IsAlive(player) then
		return
	end
	if not Util.isFiniteVector(origin) or not Util.isFiniteVector(dir) or dir.Magnitude < 0.5 then
		return
	end
	local now = os.clock()
	if lastReport[player] and now - lastReport[player] < GameConfig.Report.Cooldown then
		return
	end
	lastReport[player] = now
	dir = dir.Unit
	local head = Util.getHead(player)
	if not head then
		return
	end
	if (origin - head.Position).Magnitude > 4 then
		origin = head.Position
	end
	-- a teammate who is not a teammate
	if Registry.ObserverService:ReportMimic(player, origin, dir) then
		return
	end
	local best, bestScore = nil, math.huge
	for _, inst in active do
		local reportable = inst.def.detection ~= Enums.Detection.Endure or inst.spec.reportable == true
		if reportable and inScope(inst, player) then
			do
				for _, anchor in inst.spec.anchors or {} do
					local center = anchorPosition(anchor)
					if center then
						local score = matchScore(origin, dir, center, anchor.radius or 2)
						if score and score < bestScore then
							local ignore = if typeof(anchor.pos) == "Instance" then anchor.pos else nil
							local losTarget = center - (center - origin).Unit * math.min((anchor.radius or 2), (center - origin).Magnitude - 0.1)
							if Registry.PlayerService:HasLineOfSight(origin, losTarget, ignore) then
								best, bestScore = inst, score
							end
						end
					end
				end
			end
		end
	end
	if best then
		self:Resolve(best, player, "report")
		return
	end
	-- nothing there. Was it something a teammate fixed a moment ago?
	for _, r in recentResolved do
		if now - r.t < 4 and matchScore(origin, dir, r.pos, 4) then
			return
		end
	end
	roundStats.misreports[player] = (roundStats.misreports[player] or 0) + 1
	Registry.ProgressionService:FalseReport(player)
	Registry.HorrorDirector:AddDread(Registry.RoundService:GetDifficultyConfig().MisreportDread, "misreport", player)
	Registry.AudioService:Play2D({ player }, "ReportWrong")
	Net.fire(player, "Effect", { name = "ReportWrong" })
end

------------------------------------------------------------------------------------
-- Hooks used by other services
------------------------------------------------------------------------------------

function AnomalyService:IsInteractTarget(player: Player, target: Instance): boolean
	for _, inst in active do
		if inst.spec.interactTarget == target and inScope(inst, player) then
			return true
		end
	end
	return false
end

local function onAnomalyInteract(player: Player, target: Instance): boolean
	for _, inst in active do
		if inst.spec.interactTarget == target and inScope(inst, player) and inst.spec.onInteract then
			local ok, result = pcall(inst.spec.onInteract, inst, player)
			if ok then
				if result == "resolve" then
					AnomalyService:Resolve(inst, player, "interact")
				elseif result == "fail" then
					AnomalyService:Fail(inst, player)
				end
			end
			return true
		end
	end
	return false
end

function AnomalyService:OnFalseItemTaken(player: Player, model: Instance)
	for _, inst in active do
		if inst.spec.claim == model or inst.data.pickup == model then
			model:Destroy()
			self:Fail(inst, player)
			return
		end
	end
	model:Destroy()
end

function AnomalyService:OnFlashlight(player: Player, on: boolean)
	for _, inst in active do
		if inst.spec.onFlashlight and inScope(inst, player) then
			local ok, result = pcall(inst.spec.onFlashlight, inst, player, on)
			if ok and result == "fail" then
				self:Fail(inst, player)
			end
		end
	end
end

function AnomalyService:GetActive()
	return active
end

function AnomalyService:GetActiveCount(): number
	return Util.count(active)
end

function AnomalyService:GetRoundStats()
	return roundStats
end

function AnomalyService:GetDefinitions()
	return definitions
end

-- Forces the first, very readable anomaly of a new player's first round.
function AnomalyService:SpawnTutorial()
	local map = Registry.MapService:GetMap()
	if not map then
		return
	end
	local painting = nil
	for _, p in CollectionService:GetTagged("Painting") do
		if p:IsDescendantOf(map.Root) and p:GetAttribute("Tutorial") then
			painting = p
		end
	end
	if not painting then
		return
	end
	task.spawn(function()
		local deadline = os.clock() + 120
		while enabled and os.clock() < deadline do
			local canvas = painting:FindFirstChild("Canvas")
			if canvas and not active.PAINTING_SWAP then
				local alive = Registry.PlayerService:GetAlive()
				local seenOnce = false
				for _, p in alive do
					local root = Util.getRoot(p)
					if root and (root.Position - canvas.Position).Magnitude < 60 then
						seenOnce = true
					end
				end
				if seenOnce and isUnseen({ canvas.Position }, alive) then
					local def = defsById.PAINTING_SWAP
					local ctx = setmetatable({ map = map, rng = rng, players = alive, scope = Enums.AnomalyScope.Global, svc = self, def = def }, Ctx)
					local spec = def.create(ctx, painting)
					if spec then
						spec.lifetime = 240
						spec.data = { tutorial = true }
						spec.cue = false
						register(def, ctx, spec, Enums.AnomalyScope.Global, alive)
						Registry.AudioService:PlayAt("RealityShift", canvas.Position, { volume = 0.9 })
						task.delay(6, function()
							for _, p in Registry.PlayerService:GetAlive() do
								local data = Registry.DataService:Get(p)
								if data and not data.flags.tutorialDone then
									Net.fire(p, "Effect", { name = "TutorialHint" })
								end
							end
						end)
					end
					return
				end
			end
			task.wait(1)
		end
	end)
end

------------------------------------------------------------------------------------
-- Round lifecycle
------------------------------------------------------------------------------------

function AnomalyService:BeginRound(seed: number)
	rng = SeededRandom.new(seed, "anomalies")
	enabled = true
	uses = {}
	claims = {}
	recentResolved = {}
	roundStats = { spawned = 0, found = 0, missed = 0, misreports = {} }
	buildTemplates()
end

function AnomalyService:EndRound()
	enabled = false
	for _, inst in table.clone(active) do
		cleanup(inst, true)
	end
	active = {}
	claims = {}
	Registry.RealityService:RevertAll()
end

function AnomalyService:IsEnabled(): boolean
	return enabled
end

local function loadDefinitions()
	local folder = script.Parent.Parent:FindFirstChild("Anomalies")
	for _, module in folder:GetChildren() do
		if module:IsA("ModuleScript") then
			local list = require(module)
			for _, def in list do
				assert(JournalCatalog.ById[def.id], "anomaly not in journal: " .. tostring(def.id))
				assert(not defsById[def.id], "duplicate anomaly " .. def.id)
				defsById[def.id] = def
				local entry = JournalCatalog.ById[def.id]
				def.category = def.category or entry.category
				def.rarity = def.rarity or entry.rarity
				table.insert(definitions, def)
			end
		end
	end
	table.sort(definitions, function(a, b)
		return JournalCatalog.ById[a.id].number < JournalCatalog.ById[b.id].number
	end)
	for _, entry in JournalCatalog.List do
		if not defsById[entry.id] then
			warn("[AnomalyService] journal entry without behaviour:", entry.id)
		end
	end
end

function AnomalyService:Init()
	loadDefinitions()
	Registry.InteractionService:Register("Anomaly", onAnomalyInteract)
	Net.on("Report", function(player, origin, dir)
		AnomalyService:Report(player, origin, dir)
	end)
end

function AnomalyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		history[player] = nil
		lastReport[player] = nil
	end)
	-- position history (footprints, followers)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, p in Registry.PlayerService:GetAlive() do
				local root = Util.getRoot(p)
				if root then
					local h = history[p] or {}
					table.insert(h, { pos = root.Position, t = now })
					if #h > 40 then
						table.remove(h, 1)
					end
					history[p] = h
				end
			end
			for i = #recentResolved, 1, -1 do
				if now - recentResolved[i].t > 6 then
					table.remove(recentResolved, i)
				end
			end
		end
	end)
	-- update loop for active anomalies
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		local step = acc
		acc = 0
		if not enabled then
			return
		end
		local now = os.clock()
		for _, inst in table.clone(active) do
			if active[inst.def.id] == inst then
				local result = nil
				if inst.spec.update then
					local ok, r = pcall(inst.spec.update, inst, step)
					if ok then
						result = r
					else
						warn("[AnomalyService] update", inst.def.id, r)
					end
				end
				if result == "resolve" then
					self:Resolve(inst, inst.data.resolver, "endure")
				elseif result == "fail" then
					self:Fail(inst, inst.data.victim)
				elseif result == "expire" or now >= inst.expiresAt then
					self:Expire(inst)
				end
			end
		end
	end)
end

return AnomalyService
