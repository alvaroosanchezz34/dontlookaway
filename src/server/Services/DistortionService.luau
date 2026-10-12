--[[
	DistortionService
	The director of reality distortions (Catalog/Distortions): rare, built
	events where the building stops obeying its rules for one player and
	then puts everything back. Each event's own module runs it
	(Server/Distortions/<id>); this service decides when, for whom, and makes
	sure it always ends cleanly.

	When (never on a schedule you could learn)
	  * a running round, exploring (not starting, not the escape, not the
	    results), from the event's story phase on
	  * the director's curve in a quiet part (CALM or TENSION: false calm)
	    and its tension budget able to pay for it
	  * no blackout above level 2, The Observer free (it is borrowed)
	  * one distortion at a time; a cooldown after each; per-player and
	    per-round limits
	  * then a small chance on each check (every few seconds) that grows the
	    longer it has been possible: no fixed rhythm
	Who (one player, the others go on in the building)
	  alive, in the building (not a secret room), nothing near them (the
	  Observer's proximity FAR), not holding an interaction, no menu, puzzle
	  or note open (the client's own "busy" flag: it can only ever veto),
	  past their first night's tutorial, not the one who had the last one.

	Every run is a context (ctx) with a token. Every delayed step goes
	through After(), which checks the token: a step left over from a run
	that ended (or from another round) does nothing.

	How it always ends (Finish): the client cuts to black, the player is put
	back where they stood (the spot is checked for anything solid, players
	included; otherwise the nearest clear spot in the same room, the room's
	centre, the entrance), the event cleans up, the client fades back in.
	A run that escaped or was taken leaves one small difference in the room
	they came from (a dead lamp, an open door, a crooked frame): nothing
	that is an anomaly, nothing in the way, and reporting it is neither
	right nor wrong. Taken adds dread, never death.
	Interruptions: the player dies, leaves or is no longer alive in the
	round; the round ends or the escape starts; the event errors or runs
	past its limit; an admin cancels it.

	Admin (AdminService): distortionList, distortionTest, distortionStatus,
	distortionCancel, distortionReport. A forced run skips the timing (and
	the budget) but never the safety checks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Catalog = require(ReplicatedStorage.Shared.Catalog.Distortions)
local Registry = require(script.Parent.Parent.Registry)

local DistortionService = {}

local modules: { [string]: any } = {}
for _, def in Catalog.List do
	local m = script.Parent.Parent:FindFirstChild("Distortions") and script.Parent.Parent.Distortions:FindFirstChild(def.id)
	if def.enabled and m then
		modules[def.id] = require(m)
	end
end

DistortionService.CheckEvery = 5 -- seconds between the director's checks
DistortionService.BaseChance = 0.035 -- per check, once fully "ripe"
DistortionService.RipeAfter = 150 -- seconds past the cooldown to reach the full chance
DistortionService.BudgetCost = 40

local current: any = nil
local tokens = 0
local lastEndedAt = -math.huge
local lastPlayer: Player? = nil
local perRound = { total = 0, byPlayer = {} :: { [number]: number }, byEvent = {} :: { [string]: number } }
local busyUI: { [Player]: boolean } = {}
local residues: { { userId: number, pos: Vector3, radius: number } } = {}
local lastReport: { [string]: any }? = nil
local lastRejectLog = 0
local nextCheckAt = 0

local function log(text: string)
	if Registry.AdminService then
		Registry.AdminService:Log("distortion: " .. text)
	end
end

------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------

function DistortionService:IsBusy(player: Player): boolean
	return current ~= nil and current.player == player
end

function DistortionService:IsActive(): boolean
	return current ~= nil
end

function DistortionService:Current()
	return current
end

function DistortionService:Phase(ctx, phase: string)
	if ctx ~= current or ctx.finished then
		return
	end
	ctx.phase = phase
	ctx.phaseAt = os.clock()
	table.insert(ctx.timeline, string.format("%s@%.1f", phase, os.clock() - ctx.startedAt))
end

-- A delayed step of a run: nothing happens if the run is over meanwhile.
function DistortionService:After(ctx, seconds: number, fn: () -> ())
	local token = ctx.token
	task.delay(seconds, function()
		if current ~= ctx or ctx.finished or ctx.token ~= token then
			return
		end
		local ok, err = pcall(fn)
		if not ok then
			warn("[DistortionService] step error:", err)
			DistortionService:Finish(ctx, "error", tostring(err))
		end
	end)
end

------------------------------------------------------------------------------------
-- Eligibility
------------------------------------------------------------------------------------

-- The round as a whole: can a distortion happen now? (reason when not)
function DistortionService:RoundAllows(def: any, forced: boolean?): (boolean, string?)
	local R = Registry.RoundService
	if not R:IsRunning() then
		return false, "no round running"
	end
	local state = R:GetState()
	if state ~= Enums.RoundState.Exploring and state ~= Enums.RoundState.Objective then
		return false, "round state " .. tostring(state)
	end
	local director = Registry.HorrorDirector
	local story = director:GetStoryPhase()
	if story == Enums.RoundPhase.Escape then
		return false, "the escape"
	end
	if not forced and not director:Reached(def.minStory) then
		return false, "story phase " .. tostring(story) .. " (needs " .. def.minStory .. ")"
	end
	if not forced then
		local phase = director:GetPhase()
		if phase ~= Enums.TensionPhase.Calm and phase ~= Enums.TensionPhase.Tension then
			return false, "the director is in " .. tostring(phase)
		end
	end
	if Registry.LightingService:GetBlackout() > 2 then
		return false, "a major blackout"
	end
	if current then
		return false, "another distortion is running"
	end
	if not Registry.ObserverService:IsAvailable() then
		return false, "The Observer is busy"
	end
	if not forced then
		if os.clock() - lastEndedAt < def.cooldown then
			return false, "cooldown"
		end
		if perRound.total >= def.perRound or (perRound.byEvent[def.id] or 0) >= def.perRound then
			return false, "round limit"
		end
	end
	return true, nil
end

-- One player: can they be taken right now? (reason when not)
function DistortionService:PlayerAllows(player: Player, def: any, forced: boolean?): (boolean, string?)
	if not player.Parent or not Registry.PlayerService:IsAlive(player) then
		return false, "not alive in the round"
	end
	local root = Util.getRoot(player)
	local map = Registry.MapService:GetMap()
	local room = root and map and map:roomAt(root.Position)
	if not room then
		return false, "not inside the building"
	end
	if room.secret then
		return false, "in a secret room"
	end
	if Registry.ObserverService:ProximityLevel(player) > 1 then
		return false, "The Observer is near them"
	end
	-- (an admin test is started from the admin panel, itself a menu)
	if busyUI[player] and not forced then
		return false, "a menu, puzzle or note is open"
	end
	if Registry.InteractionService.IsHolding and Registry.InteractionService:IsHolding(player) then
		return false, "holding an interaction"
	end
	if not forced then
		local data = Registry.DataService:Get(player)
		if not data or not data.flags.tutorialDone then
			return false, "still learning the building (tutorial)"
		end
		if (perRound.byPlayer[player.UserId] or 0) >= def.perPlayer then
			return false, "already had one this round"
		end
	end
	return true, nil
end

------------------------------------------------------------------------------------
-- Running one
------------------------------------------------------------------------------------

local function newContext(def: any, player: Player, forced: boolean)
	tokens += 1
	local root = Util.getRoot(player) :: BasePart
	local map = Registry.MapService:GetMap()
	local room = map and map:roomAt(root.Position)
	return {
		id = def.id,
		def = def,
		player = player,
		userId = player.UserId,
		token = tokens,
		forced = forced,
		startedAt = os.clock(),
		phase = "START",
		phaseAt = os.clock(),
		timeline = {},
		data = {},
		finished = false,
		service = DistortionService,
		origin = { cf = root.CFrame, roomId = room and room.id },
	}
end

function DistortionService:Trigger(player: Player, id: string, forced: boolean?): (boolean, string)
	local def = Catalog.get(id)
	if not def then
		return false, "unknown distortion " .. tostring(id)
	end
	local module = modules[id]
	if not def.enabled or not module then
		return false, id .. " is designed but not built"
	end
	local ok, why = self:RoundAllows(def, forced)
	if not ok then
		return false, why or "?"
	end
	ok, why = self:PlayerAllows(player, def, forced)
	if not ok then
		return false, player.Name .. ": " .. (why or "?")
	end
	local ctx = newContext(def, player, forced == true)
	local ready, reason = module.check(ctx)
	if not ready then
		return false, reason or "the event is not ready"
	end
	current = ctx
	perRound.total += 1
	perRound.byPlayer[player.UserId] = (perRound.byPlayer[player.UserId] or 0) + 1
	perRound.byEvent[id] = (perRound.byEvent[id] or 0) + 1
	lastPlayer = player
	player:SetAttribute("Distortion", id)
	log(string.format("%s -> %s%s (room %s)", id, player.Name, if forced then " [forced]" else "", tostring(ctx.origin.roomId)))
	local started, err = pcall(module.start, ctx)
	if not started then
		warn("[DistortionService] start error:", err)
		self:Finish(ctx, "error", tostring(err))
		return false, "the event failed to start: " .. tostring(err)
	end
	return true, string.format("%s started for %s", id, player.Name)
end

-- A clear place to stand back in the building: where they were if nothing
-- is there now, else the nearest clear spot of the same room.
function DistortionService:ReturnSpot(ctx): CFrame?
	local map = Registry.MapService:GetMap()
	if not map then
		return nil
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if ctx.player.Character then
		table.insert(ignore, ctx.player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local function clear(at: Vector3): boolean
		for _, hit in workspace:GetPartBoundsInBox(CFrame.new(at), Vector3.new(2.2, 4.6, 2.2), params) do
			if hit.CanCollide and hit.Transparency < 0.95 then
				return false
			end
		end
		return true
	end
	local origin = ctx.origin.cf :: CFrame
	local look = origin.LookVector
	local function facing(at: Vector3): CFrame
		return CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z).Unit)
	end
	if clear(origin.Position) then
		return facing(origin.Position)
	end
	local room = ctx.origin.roomId and map.Rooms[ctx.origin.roomId]
	if room then
		local spots = table.clone(room.floorSpots or {})
		table.sort(spots, function(a, b)
			return (a - origin.Position).Magnitude < (b - origin.Position).Magnitude
		end)
		for _, spot in spots do
			local at = spot + Vector3.new(0, 3, 0)
			if clear(at) then
				return facing(at)
			end
		end
		return facing(room.center + Vector3.new(0, 3, 0))
	end
	local entrance = map.Rooms.G_e
	return if entrance then facing(entrance.center + Vector3.new(0, 3, 0)) else nil
end

------------------------------------------------------------------------------------
-- The trace it leaves: one small, harmless difference in the room
------------------------------------------------------------------------------------

local function inActiveAnomaly(instance: Instance): boolean
	for _, inst in Registry.AnomalyService:GetActive() do
		for _, anchor in inst.spec.anchors or {} do
			if typeof(anchor.pos) == "Instance" and (anchor.pos == instance or instance:IsDescendantOf(anchor.pos) or anchor.pos:IsDescendantOf(instance)) then
				return true
			end
		end
	end
	return false
end

function DistortionService:LeaveResidue(ctx): string?
	local map = Registry.MapService:GetMap()
	local room = map and ctx.origin.roomId and map.Rooms[ctx.origin.roomId]
	if not room then
		return nil
	end
	local player = ctx.player
	local rng = Random.new()
	local options = { "light", "door", "frame" }
	for i = #options, 2, -1 do
		local j = rng:NextInteger(1, i)
		options[i], options[j] = options[j], options[i]
	end
	local function remember(pos: Vector3, radius: number)
		table.insert(residues, { userId = player.UserId, pos = pos, radius = radius })
	end
	for _, kind in options do
		if kind == "light" then
			-- one lamp of the room is dead, for them only
			local lit = {}
			for _, f in room.fixtures or {} do
				if f.Parent and f:GetAttribute("Mode") ~= "dead" and f:GetAttribute("Circuit") ~= "EMERGENCY" and not inActiveAnomaly(f) then
					table.insert(lit, f)
				end
			end
			if #lit >= 2 then
				local f = lit[rng:NextInteger(1, #lit)]
				Registry.RealityService:Apply({ { t = "Attr", target = f, name = "Mode", value = "dead" } }, Enums.AnomalyScope.Player, { player })
				remember(f:GetPivot().Position, 3)
				return "a dead lamp"
			end
		elseif kind == "door" then
			-- a door of the room that was closed is open (for everyone: doors are shared)
			for _, door in map.Doors or {} do
				local m = door.model
				if m and m.Parent and not m:GetAttribute("Locked") and m:GetAttribute("Kind") ~= "closet" and not m:GetAttribute("KeyId") and not m:GetAttribute("Keypad") and not Registry.DoorService:IsOpen(m) and not inActiveAnomaly(m) then
					local c = door.center
					if c.X >= room.min.X - 1 and c.X <= room.max.X + 1 and c.Z >= room.min.Z - 1 and c.Z <= room.max.Z + 1 and math.abs(c.Y - room.floorY) < 6 then
						Registry.DoorService:SetOpen(m, true, { silent = true })
						remember(c, 3)
						return "an open door"
					end
				end
			end
		else
			-- a small thing on a wall hangs crooked, for them only (nothing that
			-- collides: never in anyone's way)
			for _, prop in room.props or {} do
				if typeof(prop) == "Instance" and prop:IsA("Model") and prop.Parent and not inActiveAnomaly(prop) then
					local _, size = prop:GetBoundingBox()
					local collides = false
					for _, d in prop:GetDescendants() do
						if d:IsA("BasePart") and d.CanCollide then
							collides = true
							break
						end
					end
					if not collides and size.Magnitude < 6 then
						local tilt = math.rad((rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(7, 11))
						Registry.RealityService:Apply({ { t = "Pivot", target = prop, cframe = prop:GetPivot() * CFrame.Angles(0, 0, tilt) } }, Enums.AnomalyScope.Player, { player })
						remember(prop:GetPivot().Position, 3)
						return "a crooked frame"
					end
				end
			end
		end
	end
	return nil
end

-- A report aimed at the trace a distortion left is neither right nor wrong.
function DistortionService:IsResidue(player: Player, origin: Vector3, dir: Vector3): boolean
	for _, r in residues do
		if r.userId == player.UserId then
			local to = r.pos - origin
			local dist = to.Magnitude
			if dist > 0.1 and dist < 80 then
				local angle = math.deg(math.acos(math.clamp(to.Unit:Dot(dir.Unit), -1, 1)))
				if angle <= math.deg(math.atan2(r.radius, dist)) + 4 then
					return true
				end
			end
		end
	end
	return false
end

------------------------------------------------------------------------------------
-- The end, whatever it is
------------------------------------------------------------------------------------

function DistortionService:Finish(ctx, outcome: string, reason: string?)
	if not ctx or ctx.finished then
		return
	end
	ctx.finished = true
	ctx.outcome = outcome
	ctx.reason = reason
	local player = ctx.player
	local module = modules[ctx.id]
	table.insert(ctx.timeline, string.format("END:%s@%.1f", outcome, os.clock() - ctx.startedAt))
	task.spawn(function()
		local restored = true
		local residue = nil
		-- 1. the cut to black (the client hides the move)
		if player.Parent then
			Net.fire(player, "Distortion", { cue = "exit", id = ctx.id, token = ctx.token, outcome = outcome })
		end
		task.wait(0.3)
		-- 2. back where they stood (if they still have a body)
		if player.Parent and player.Character and Util.getRoot(player) then
			local ok, spot = pcall(DistortionService.ReturnSpot, DistortionService, ctx)
			if ok and spot then
				Registry.PlayerService:Teleport(player, spot)
				local root = Util.getRoot(player)
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
			else
				restored = false
				warn("[DistortionService] no return spot for " .. player.Name .. ": " .. tostring(spot))
			end
		end
		-- 3. the event puts its things away
		if module and module.cleanup then
			local ok, err = pcall(module.cleanup, ctx)
			if not ok then
				restored = false
				warn("[DistortionService] cleanup error:", err)
			end
		end
		if player.Parent then
			player:SetAttribute("Distortion", nil)
		end
		-- 4. the trace, and the building's attention
		local stillPlaying = player.Parent and Registry.PlayerService:IsAlive(player) and Registry.RoundService:IsRunning()
		if stillPlaying and (outcome == "escaped" or outcome == "taken") then
			local ok, what = pcall(DistortionService.LeaveResidue, DistortionService, ctx)
			residue = if ok then what else nil
		end
		if stillPlaying and outcome == "taken" then
			Registry.HorrorDirector:AddDread(15, "taken in a distortion", nil)
		end
		-- 5. the picture comes back
		if player.Parent then
			Net.fire(player, "Distortion", { cue = "return", id = ctx.id, token = ctx.token, outcome = outcome })
		end
		local duration = os.clock() - ctx.startedAt
		lastReport = {
			id = ctx.id,
			player = player.Name,
			forced = ctx.forced,
			outcome = outcome,
			reason = reason,
			duration = duration,
			timeline = ctx.timeline,
			restored = restored,
			residue = residue,
			room = ctx.origin.roomId,
		}
		log(string.format("%s for %s ended: %s (%s) after %.1f s, restored %s, trace %s", ctx.id, player.Name, outcome, tostring(reason), duration, tostring(restored), tostring(residue)))
		if current == ctx then
			current = nil
		end
		lastEndedAt = os.clock()
	end)
end

function DistortionService:Cancel(reason: string?): (boolean, string)
	if not current then
		return false, "no distortion running"
	end
	local ctx = current
	self:Finish(ctx, "cancelled", reason or "cancelled")
	return true, "cancelling " .. ctx.id .. " for " .. ctx.player.Name
end

------------------------------------------------------------------------------------
-- Admin text
------------------------------------------------------------------------------------

function DistortionService:List(): string
	local lines = {}
	for _, def in Catalog.List do
		table.insert(lines, string.format("%s [%s] %s%s", def.id, def.category, if def.enabled and modules[def.id] then "ready" else "designed only", if perRound.byEvent[def.id] then string.format(", %d this round", perRound.byEvent[def.id]) else ""))
	end
	return table.concat(lines, " | ")
end

function DistortionService:Status(): string
	if current then
		return string.format("%s for %s: phase %s for %.1f s (total %.1f s)", current.id, current.player.Name, current.phase, os.clock() - current.phaseAt, os.clock() - current.startedAt)
	end
	local def = Catalog.get("ImpossibleHallway")
	local ok, why = self:RoundAllows(def, false)
	return string.format("idle; last ended %s; round allows: %s%s; this round %d", if lastEndedAt > 0 then string.format("%.0f s ago", os.clock() - lastEndedAt) else "never", tostring(ok), if why then " (" .. why .. ")" else "", perRound.total)
end

function DistortionService:Report(): string
	local r = lastReport
	if not r then
		return "no distortion has run yet"
	end
	return string.format("%s for %s%s: %s (%s), %.1f s, restored %s, trace %s, room %s | %s", r.id, r.player, if r.forced then " [forced]" else "", r.outcome, tostring(r.reason), r.duration, tostring(r.restored), tostring(r.residue), tostring(r.room), table.concat(r.timeline, " "))
end

function DistortionService:LastReport()
	return lastReport
end

------------------------------------------------------------------------------------
-- The director
------------------------------------------------------------------------------------

local function choosePlayer(def: any): Player?
	local list = {}
	for _, p in Registry.PlayerService:GetAlive() do
		if DistortionService:PlayerAllows(p, def, false) then
			table.insert(list, p)
		end
	end
	if #list > 1 and lastPlayer then
		local i = table.find(list, lastPlayer)
		if i then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function directorCheck()
	if current then
		return
	end
	local enabled = {}
	for _, def in Catalog.enabled() do
		if modules[def.id] and DistortionService:RoundAllows(def, false) then
			table.insert(enabled, def)
		end
	end
	if #enabled == 0 then
		return
	end
	local def = enabled[math.random(1, #enabled)]
	-- the longer it has been possible, the likelier: no rhythm to learn
	local since = math.min(os.clock() - lastEndedAt, Registry.RoundService:GetElapsed()) - def.cooldown
	local ripe = math.clamp(since / DistortionService.RipeAfter, 0, 1)
	if ripe <= 0 or math.random() > DistortionService.BaseChance * ripe then
		return
	end
	if not Registry.HorrorDirector:CanAfford("distortion") then
		return
	end
	local player = choosePlayer(def)
	if not player then
		if os.clock() - lastRejectLog > 60 then
			lastRejectLog = os.clock()
			log("the moment was right, but nobody could be taken")
		end
		return
	end
	local ok, why = DistortionService:Trigger(player, def.id, false)
	if ok then
		Registry.HorrorDirector:Spend("distortion")
	elseif os.clock() - lastRejectLog > 60 then
		lastRejectLog = os.clock()
		log("not started: " .. why)
	end
end

function DistortionService:BeginRound()
	if current then
		self:Cancel("a new round")
	end
	perRound = { total = 0, byPlayer = {}, byEvent = {} }
	table.clear(residues)
	lastEndedAt = -math.huge
	lastPlayer = nil
end

function DistortionService:Init()
	Net.on("ClientFlag", function(player, flag, value)
		-- the client's own "something is open" (menus, puzzles, notes): it can
		-- only ever stop a distortion from choosing them
		if flag == "busy" then
			busyUI[player] = value == true
		end
	end)
end

function DistortionService:Start()
	Registry.RoundService.StateChanged:Connect(function(state)
		if current and state ~= Enums.RoundState.Exploring and state ~= Enums.RoundState.Objective then
			DistortionService:Cancel("round state " .. tostring(state))
		end
		if state == Enums.RoundState.Exploring then
			DistortionService:BeginRound()
		end
	end)
	Registry.PlayerService.StatusChanged:Connect(function(player, status)
		if current and current.player == player and status ~= Enums.PlayerStatus.Alive then
			DistortionService:Cancel("the player is " .. tostring(status))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		busyUI[player] = nil
		if current and current.player == player then
			DistortionService:Cancel("the player left")
		end
	end)
	local stepAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		stepAcc += dt
		if stepAcc < 0.1 then
			return
		end
		local step = stepAcc
		stepAcc = 0
		DistortionService:Tick(step)
	end)
end

-- One step (10 Hz): the running event, its limit, else the director.
function DistortionService:Tick(step: number)
	local ctx = current
	if ctx and not ctx.finished then
		if os.clock() - ctx.startedAt > ctx.def.maxDuration then
			self:Finish(ctx, "cancelled", "ran past its limit")
			return
		end
		local module = modules[ctx.id]
		local ok, err = pcall(module.step, ctx, step)
		if not ok then
			warn("[DistortionService] step error:", err)
			self:Finish(ctx, "error", tostring(err))
		end
		return
	end
	if os.clock() >= nextCheckAt then
		nextCheckAt = os.clock() + self.CheckEvery
		local ok, err = pcall(directorCheck)
		if not ok then
			warn("[DistortionService] director error:", err)
		end
	end
end

return DistortionService
