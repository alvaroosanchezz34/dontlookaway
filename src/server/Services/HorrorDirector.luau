--[[
	HorrorDirector
	Paces fear on two levels.

	1. The story of a round (Enums.RoundPhase)
	  ARRIVAL     lights on, nothing hunts, almost nothing changes. Players learn
	              the building, the flashlight, the notes, how reporting works.
	              It ends with THE OUTAGE: the power fails floor by floor and the
	              fuse box burns out.
	  UNEASE      small, deniable changes; failing lights; the building settles.
	  DISTORTION  anomalies become clear; it starts to show itself far away;
	              someone you know might be standing at the end of a corridor.
	  DANGER      it hunts.
	  COLLAPSE    the building turns hostile: more changes, a total blackout,
	              shorter breathing room.
	  ESCAPE      get out.
	Phases advance on a timer (per difficulty) or earlier with progress.

	2. The rhythm inside each phase (Enums.TensionPhase)
	  CALM -> TENSION -> (silence) -> FEAR -> RELIEF -> CALM ...
	  CALM always has something to do (anomalies to spot, ambient life);
	  FEAR is one event (a hunt, a sighting, a mimic, a blackout, a scare);
	  RELIEF guarantees breathing room. Never a scare every 20 seconds.

	TENSION BUDGET (0-100): every event costs budget and the budget refills at a
	rate set by the story phase (none while arriving, fastest in the collapse).
	Big events (a hunt, a mimic) need the meter to have filled; small paranoia
	(a sound behind you, a glimpse in a mirror, a moment of silence) is cheap.
	That is what keeps the curve a curve instead of a constant noise.

	PARANOIA: private, deniable moments for one player that are NOT anomalies
	(they cannot be reported and are never counted): a light stutters, a step
	echoes once behind you, something stands in a mirror or a dark window for
	a few frames, a screen shows a face, the building goes silent and then
	something heavy falls far away.

	DREAD (0-100) accumulates from mistakes (false reports, missed anomalies,
	broken rules) and shortens the calm. Dynamic difficulty scales with time,
	progress and player count. Jumpscares are capped and spaced far apart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local Registry = require(script.Parent.Parent.Registry)

local HorrorDirector = {}

HorrorDirector.StoryPhaseChanged = Signal.new() -- (phase)

local Phase = Enums.TensionPhase
local Story = Enums.RoundPhase

local rng = SeededRandom.new(1, "director")
local running = false
local phase = Phase.Calm
local phaseEndsAt = 0
local story = Story.Arrival
local storyStartedAt = 0
local outageDone = false
local dread = 0
local lastSpawnAt = 0
local nextSpawnIn = 30
local lastAmbientAt = 0
local nextAmbientIn = 20
local lastHuntAt = -math.huge
local lastSightingAt = -math.huge
local lastScareAt = -math.huge
local lastBlackoutAt = -math.huge
local totalBlackoutDone = false
local scaresThisRound = 0
local usedScares: { [string]: boolean } = {}
local roundStart = 0

local MAX_SCARES = 4

local budget = 0
local BUDGET_MAX = 100
-- refill per second for each story phase
local BUDGET_RATE = { ARRIVAL = 0, UNEASE = 0.35, DISTORTION = 0.5, DANGER = 0.65, COLLAPSE = 0.85, ESCAPE = 1 }
local COST = { hunt = 45, mimic = 40, sighting = 30, blackout = 35, scare = 25, shadow = 12, glimpse = 10, silence = 8, micro = 4 }
local nextParanoiaAt = 0

function HorrorDirector:Rng()
	return rng
end

function HorrorDirector:GetPhase(): string
	return phase
end

function HorrorDirector:GetStoryPhase(): string
	return story
end

function HorrorDirector:StoryIndex(): number
	return table.find(Enums.RoundPhaseOrder, story) or 1
end

-- Has the round reached (at least) this story phase?
function HorrorDirector:Reached(name: string): boolean
	return self:StoryIndex() >= (table.find(Enums.RoundPhaseOrder, name) or 99)
end

function HorrorDirector:GetDread(): number
	return dread
end

function HorrorDirector:GetBudget(): number
	return budget
end

-- Can the budget pay for this kind of event? (`free` for forced/admin events)
local function afford(kind: string, free: boolean?): boolean
	return free == true or budget >= (COST[kind] or 0)
end

local function charge(kind: string, free: boolean?)
	if not free then
		budget = math.max(0, budget - (COST[kind] or 0))
	end
end

function HorrorDirector:IsRunning(): boolean
	return running
end

local function elapsed(): number
	return os.clock() - roundStart
end

local function inStory(): number
	return os.clock() - storyStartedAt
end

local function cfg()
	return Registry.RoundService:GetDifficultyConfig()
end

local function locksReleased(): number
	local state = Registry.ObjectiveService:GetState()
	local released = 0
	if state then
		for _, v in state.locks do
			if v then
				released += 1
			end
		end
	end
	return released
end

-- 0.8 .. 1.6: grows with time, progress and team size
local function aggression(): number
	local players = #Registry.PlayerService:GetAlive()
	local storyBoost = (HorrorDirector:StoryIndex() - 1) * 0.06
	return math.clamp(0.8 + elapsed() / 1200 + locksReleased() / 4 * 0.25 + math.max(0, players - 1) * 0.06 + dread / 250 + storyBoost, 0.8, 1.6)
end

local function setPhase(newPhase: string, duration: number)
	phase = newPhase
	phaseEndsAt = os.clock() + duration
	workspace:SetAttribute("TensionPhase", newPhase)
	Net.fireAll("Director", { cue = "phase", phase = newPhase })
end

local function setStory(newStory: string)
	if story == newStory then
		return
	end
	story = newStory
	storyStartedAt = os.clock()
	workspace:SetAttribute("RoundPhase", newStory)
	Net.fireAll("Director", { cue = "story", phase = newStory })
	HorrorDirector.StoryPhaseChanged:Fire(newStory)
	if Registry.AdminService then
		Registry.AdminService:Log("story phase -> " .. newStory)
	end
	if Registry.ObjectiveService then
		Registry.ObjectiveService:Push()
	end
end

function HorrorDirector:AddDread(amount: number, reason: string?, player: Player?)
	dread = math.clamp(dread + amount, 0, 100)
	if Registry.AdminService then
		Registry.AdminService:Log(string.format("dread +%d (%s) -> %d", amount, reason or "?", dread))
	end
	-- too much dread draws attention to whoever caused it (only once it can show itself)
	if player and dread >= 70 and phase ~= Phase.Fear and not Registry.ObserverService:IsActive() and self:Reached(Story.Distortion) then
		self:EnterFear(player)
	end
end

------------------------------------------------------------------------------------
-- Ambient life (never silent for long, never threatening on its own)
------------------------------------------------------------------------------------

local AMBIENT = { "DistantPipe", "DistantKnock", "DistantMetal", "DistantGroan", "WoodCreak", "DistantPipe", "WoodCreak", "BuildingSettle", "ElevatorGroan" }

local function randomAlive(): Player?
	local alive = Registry.PlayerService:GetAlive()
	if #alive == 0 then
		return nil
	end
	return alive[rng:Int(1, #alive)]
end

local function ambientEvent()
	local player = randomAlive()
	local root = player and Util.getRoot(player)
	if not root then
		return
	end
	local roll = rng:Number()
	local quiet = story == Story.Arrival
	if roll < 0.55 or quiet then
		-- a sound somewhere nearby, never on top of the player
		local angle = rng:Number(0, math.pi * 2)
		local dist = rng:Number(25, 60)
		local pos = root.Position + Vector3.new(math.cos(angle) * dist, rng:Number(-6, 10), math.sin(angle) * dist)
		local key = rng:Pick(AMBIENT)
		if quiet and key == "DistantGroan" then
			key = "BuildingSettle"
		end
		Registry.AudioService:PlayAt(key, pos)
	elseif roll < 0.8 then
		-- lights flicker in the player's room
		local map = Registry.MapService:GetMap()
		local room = map and map:roomAt(root.Position)
		if room then
			Net.fireAll("Director", { cue = "flicker", room = room.id, duration = rng:Number(1.2, 3) })
		end
	elseif roll < 0.92 then
		Registry.DoorService:OpenNear(root.Position + Vector3.new(rng:Number(-30, 30), 0, rng:Number(-30, 30)), 6)
	else
		local map = Registry.MapService:GetMap()
		local room = map and map:roomAt(root.Position)
		if room then
			Net.fireAll("Director", { cue = "flicker", room = room.id, duration = 0.6 })
			Registry.AudioService:PlayAt("LightFlicker", room.center + Vector3.new(0, 10, 0))
		end
	end
end

------------------------------------------------------------------------------------
-- Jumpscares: few, varied, spaced out
------------------------------------------------------------------------------------

local SCARES = {}

SCARES.door_slam = function(player, root)
	if Registry.DoorService:SlamNear(root.Position, 26) then
		Net.fire(player, "Effect", { name = "Shake", strength = 0.5 })
		return true
	end
	return false
end

SCARES.bulb_pop = function(player, root)
	local map = Registry.MapService:GetMap()
	local room = map and map:roomAt(root.Position)
	if not room or #room.fixtures == 0 then
		return false
	end
	local fixture = room.fixtures[rng:Int(1, #room.fixtures)]
	fixture:SetAttribute("Mode", "dead")
	Registry.AudioService:PlayAt("BulbPop", fixture:GetPivot().Position)
	Net.fireAll("Director", { cue = "sparks", at = fixture:GetPivot().Position })
	return true
end

SCARES.vent_bang = function(player, root)
	local pos = root.Position + Vector3.new(rng:Number(-6, 6), 9, rng:Number(-6, 6))
	Registry.AudioService:PlayAt("Thud", pos, { volume = 1.2 })
	Net.fire(player, "Effect", { name = "DustBurst", at = pos })
	Net.fire(player, "Effect", { name = "Shake", strength = 0.6 })
	return true
end

SCARES.whisper_ear = function(player)
	Registry.AudioService:Play2D({ player }, "Whisper", { volume = 1.6 })
	Net.fire(player, "Caption", { text = "...don't look away...", duration = 3, speaker = "whisper" })
	return true
end

SCARES.shadow_run = function(player, root)
	local look = Registry.PlayerService:GetLook(player)
	if not look then
		return false
	end
	local ahead = look.origin + Util.flat(look.dir).Unit * 30
	if not Registry.PlayerService:HasLineOfSight(look.origin, ahead) then
		return false
	end
	local side = Vector3.new(-look.dir.Z, 0, look.dir.X).Unit
	Net.fire(player, "Effect", { name = "ShadowRun", from = ahead - side * 10 - Vector3.new(0, 1, 0), to = ahead + side * 10 - Vector3.new(0, 1, 0) })
	Registry.AudioService:PlayAtFor({ player }, "ObserverStep", ahead, { volume = 1 })
	return true
end

SCARES.falling_box = function(player, root)
	local map = Registry.MapService:GetMap()
	local room = map and map:roomAt(root.Position)
	if not room then
		return false
	end
	for _, prop in room.props do
		if typeof(prop) == "Instance" and prop.Parent and prop.Name == "Box" then
			local cf = prop:GetPivot()
			if (cf.Position - root.Position).Magnitude < 22 then
				prop:PivotTo(cf * CFrame.new(rng:Number(-1, 1), 0, rng:Number(-1, 1)) * CFrame.Angles(math.rad(80), math.rad(rng:Number(0, 90)), 0))
				Registry.AudioService:PlayAt("Thud", cf.Position)
				return true
			end
		end
	end
	return false
end

SCARES.mirror_flash = function(player, root)
	for _, mirror in CollectionService:GetTagged("Mirror") do
		local glass = mirror:FindFirstChild("Glass")
		if glass and (glass.Position - root.Position).Magnitude < 16 and Registry.PlayerService:IsLookingAt(player, glass.Position, 30, 20) then
			local figure = glass:FindFirstChild("Figure", true)
			if figure then
				local token = Registry.RealityService:Apply({ { t = "Prop", target = figure, prop = "Visible", value = true } }, Enums.AnomalyScope.Player, { player })
				Registry.AudioService:Play2D({ player }, "JumpSting")
				task.delay(0.45, function()
					Registry.RealityService:Revert(token, true)
				end)
				return true
			end
		end
	end
	return false
end

SCARES.lights_out_brief = function(player, root)
	local map = Registry.MapService:GetMap()
	local room = map and map:roomAt(root.Position)
	if not room or #room.fixtures == 0 then
		return false
	end
	local ops = {}
	for _, f in room.fixtures do
		table.insert(ops, { t = "Attr", target = f, name = "Override", value = "off" })
	end
	local token = Registry.RealityService:Apply(ops)
	Registry.AudioService:PlayAt("ObserverBreath", root.Position + Vector3.new(0, 2, 0), { volume = 0.9 })
	task.delay(rng:Number(2.5, 4), function()
		Registry.RealityService:Revert(token)
	end)
	return true
end

SCARES.breath_neck = function(player)
	Registry.AudioService:Play2D({ player }, "BreathHeavy", { volume = 1.4, speed = 0.8 })
	Net.fire(player, "Effect", { name = "Shake", strength = 0.3 })
	return true
end

SCARES.radio_static = function(player, root)
	Registry.AudioService:PlayAtFor({ player }, "Static", root.Position + Vector3.new(rng:Number(-8, 8), 2, rng:Number(-8, 8)), { volume = 1.3 })
	Net.fire(player, "Effect", { name = "Glitch", strength = 0.5 })
	return true
end

SCARES.phone_burst = function(player, root)
	for _, phone in CollectionService:GetTagged("Phone") do
		local base = phone:FindFirstChild("Base")
		if base and (base.Position - root.Position).Magnitude < 25 and not Registry.AnomalyService:GetActive().PHONE_RING then
			Registry.AudioService:PlayAt("PhoneRing", base.Position, { volume = 1.2 })
			return true
		end
	end
	return false
end

SCARES.name_whisper = function(player)
	-- your own name, from somewhere behind you
	local root = Util.getRoot(player)
	if not root then
		return false
	end
	Registry.AudioService:PlayAtFor({ player }, "ObserverWhisperName", root.Position - Util.flat(root.CFrame.LookVector).Unit * 6 + Vector3.new(0, 2, 0), { volume = 0.9 })
	Net.fire(player, "Caption", { text = "..." .. string.lower(player.DisplayName) .. "...", duration = 2.6, speaker = "whisper" })
	return true
end

SCARES.observer_peek = function(player, root)
	if Registry.ObserverService:IsActive() or not HorrorDirector:Reached(Story.Distortion) then
		return false
	end
	return Registry.ObserverService:Sighting(player)
end

local SCARE_ORDER = { "door_slam", "bulb_pop", "vent_bang", "whisper_ear", "shadow_run", "falling_box", "mirror_flash", "lights_out_brief", "breath_neck", "radio_static", "phone_burst", "name_whisper", "observer_peek" }

local function tryScare(player: Player): boolean
	if scaresThisRound >= MAX_SCARES or os.clock() - lastScareAt < 90 or not afford("scare") then
		return false
	end
	-- never a cheap scare on top of the real thing
	if Registry.ObserverService:ProximityLevel(player) >= 3 then
		return false
	end
	local root = Util.getRoot(player)
	if not root then
		return false
	end
	local options = {}
	for _, name in SCARE_ORDER do
		if not usedScares[name] then
			table.insert(options, name)
		end
	end
	rng:Shuffle(options)
	for _, name in options do
		local ok, result = pcall(SCARES[name], player, root)
		if ok and result then
			usedScares[name] = true
			scaresThisRound += 1
			lastScareAt = os.clock()
			charge("scare")
			if Registry.AdminService then
				Registry.AdminService:Log("scare: " .. name .. " -> " .. player.Name)
			end
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------
-- Power: the outage and later blackouts
------------------------------------------------------------------------------------

-- THE OUTAGE: the end of ARRIVAL. Lights die floor by floor, the fuse box burns out.
function HorrorDirector:TriggerOutage()
	if outageDone then
		return
	end
	outageDone = true
	local map = Registry.MapService:GetMap()
	Registry.AudioService:Play2DAll("ElectricSurge", { volume = 0.7 })
	Net.fireAll("Director", { cue = "outageWarning" })
	-- a few seconds of failing lights first
	Registry.LightingService:Blackout(1, 6, { silent = true })
	task.delay(5, function()
		if not running then
			return
		end
		Registry.LightingService:EndBlackout(true)
		Registry.PuzzleService:BurnOut()
		Registry.LightingService:SetPower(false)
		Registry.AudioService:Play2DAll("PowerDown", { volume = 0.9 })
		Net.fireAll("Director", { cue = "blackout", level = 3, duration = 0, outage = true })
		if map and map.Rooms.B_d then
			Registry.AudioService:PlayAt("Sparks", map.Rooms.B_d.center + Vector3.new(0, 6, 0), { volume = 1.2 })
		end
		Net.fireAll("Notify", { kind = "objective", text = "THE POWER IS OUT", sub = "Restore it: the fuse box is in Maintenance (B-04)" })
		for _, p in Registry.PlayerService:GetAlive() do
			Registry.AnalyticsService:Milestone(p, "ARRIVAL_COMPLETE", math.floor(elapsed()))
		end
		setStory(Story.Unease)
		setPhase(Phase.Relief, 25)
		budget = 30
		Registry.ObjectiveService:Push()
	end)
end

local function maybeBlackout(): boolean
	-- only once the building has power again (before that it is already dark)
	if not Registry.LightingService:IsPowered() or Registry.LightingService:GetBlackout() > 0 then
		return false
	end
	if os.clock() - lastBlackoutAt < 110 then
		return false
	end
	local level
	if story == Story.Unease then
		level = 1
	elseif story == Story.Distortion then
		level = rng:Pick({ 1, 2, 2 })
	elseif story == Story.Danger then
		level = rng:Pick({ 2, 3, 3 })
	elseif story == Story.Collapse then
		if not totalBlackoutDone then
			level = 4
			totalBlackoutDone = true
		else
			level = rng:Pick({ 2, 3 })
		end
	else
		return false
	end
	lastBlackoutAt = os.clock()
	local duration = ({ 8, 22, 28, 20 })[level] + rng:Number(0, 6)
	Registry.LightingService:Blackout(level, duration)
	if level >= 4 then
		-- the building does something special in the dark
		task.delay(2, function()
			if running then
				Registry.AnomalyService:TrySpawn(nil, { ignoreVisibility = true, darkOnly = true })
			end
		end)
	end
	return true
end

function HorrorDirector:OnBlackoutSurvived(level: number)
	for _, p in Registry.PlayerService:GetAlive() do
		Registry.ProgressionService:Challenge(p, "blackout", level)
	end
end

------------------------------------------------------------------------------------
-- Fear events
------------------------------------------------------------------------------------

local function mostIsolated(): Player?
	local alive = Registry.PlayerService:GetAlive()
	local best, bestD = nil, -1
	for _, p in alive do
		local r = Util.getRoot(p)
		local d = 0
		if r then
			d = math.huge
			for _, q in alive do
				local o = Util.getRoot(q)
				if q ~= p and o then
					d = math.min(d, (r.Position - o.Position).Magnitude)
				end
			end
			if d == math.huge then
				d = 50
			end
		end
		d += rng:Number(0, 15)
		if d > bestD then
			best, bestD = p, d
		end
	end
	return best
end

local function separatedPair(): (Player?, Player?)
	local alive = Registry.PlayerService:GetAlive()
	for _, a in alive do
		for _, b in alive do
			local ra, rb = Util.getRoot(a), Util.getRoot(b)
			if a ~= b and ra and rb and (ra.Position - rb.Position).Magnitude > 55 then
				return a, b
			end
		end
	end
	return nil, nil
end

function HorrorDirector:EnterFear(forced: Player?)
	local c = cfg()
	local free = forced ~= nil
	local victim = forced or mostIsolated()
	if not victim then
		setPhase(Phase.Relief, 20)
		return
	end
	setPhase(Phase.Fear, 40)
	local agg = aggression()
	local dark = Registry.LightingService:GetBlackout() >= 3
	-- hunts: from DANGER on (sooner after the previous one when it is dark)
	if self:Reached(Story.Danger) then
		local interval = rng:Range(c.HuntInterval) / agg * (if dark then 0.6 else 1)
		if os.clock() - lastHuntAt >= interval and afford("hunt", free) and Registry.ObserverService:StartHunt(victim, { reason = "director" }) then
			charge("hunt", free)
			return
		end
	end
	-- sightings & mimics: from DISTORTION on
	if self:Reached(Story.Distortion) and os.clock() - lastSightingAt > (if dark then 45 else 70) then
		local viewer, imitated = separatedPair()
		local mimicChance = 0.45 + c.ObserverCunning * 0.1
		if viewer and afford("mimic", free) and rng:Chance(mimicChance) and Registry.ObserverService:Mimic(viewer, imitated) then
			lastSightingAt = os.clock()
			charge("mimic", free)
			return
		end
		if #Registry.PlayerService:GetAlive() == 1 and afford("mimic", free) and rng:Chance(0.2) and Registry.ObserverService:Mimic(victim, victim) then
			lastSightingAt = os.clock()
			charge("mimic", free)
			return
		end
		if afford("sighting", free) and Registry.ObserverService:Sighting(victim) then
			lastSightingAt = os.clock()
			charge("sighting", free)
			return
		end
	end
	-- a blackout can be the event itself
	if self:Reached(Story.Unease) and afford("blackout", free) and rng:Chance(0.35) and maybeBlackout() then
		charge("blackout", free)
		return
	end
	if not tryScare(victim) then
		-- nothing appropriate: let the tension dissolve on its own
		setPhase(Phase.Relief, rng:Number(15, 25))
	end
end

function HorrorDirector:OnHuntStarted(_player: Player)
	lastHuntAt = os.clock()
	if phase ~= Phase.Fear then
		setPhase(Phase.Fear, 45)
	end
end

function HorrorDirector:OnAnomalyResolved(_inst)
	dread = math.max(0, dread - 6)
end

function HorrorDirector:OnMilestone(name: string)
	if name == "power" then
		-- a moment of relief when the lights come back
		setPhase(Phase.Relief, 40)
		dread = math.max(0, dread - 15)
		lastBlackoutAt = os.clock()
	end
end

------------------------------------------------------------------------------------
-- Story phase machine
------------------------------------------------------------------------------------

local function storyStep()
	local c = cfg()
	local durations = c.PhaseDurations or {}
	local t = inStory()
	local state = Registry.ObjectiveService:GetState()
	local found = state and state.found or 0
	local locks = locksReleased()
	if story == Story.Arrival then
		if t >= (c.ArrivalDuration or 180) then
			HorrorDirector:TriggerOutage()
		end
	elseif story == Story.Unease then
		if t >= (durations.UNEASE or 150) or (t > 60 and found >= 2) then
			setStory(Story.Distortion)
		end
	elseif story == Story.Distortion then
		if t >= (durations.DISTORTION or 160) or (t > 60 and locks >= 2) then
			setStory(Story.Danger)
		end
	elseif story == Story.Danger then
		if t >= (durations.DANGER or 200) or (t > 60 and locks >= 3) then
			setStory(Story.Collapse)
			Net.fireAll("Effect", { name = "Shake", strength = 0.5 })
			Registry.AudioService:Play2DAll("StretchGroan", { volume = 1 })
		end
	end
end

-- Which anomalies fit the current phase (called by AnomalyService).
function HorrorDirector:AllowsAnomaly(def): boolean
	if not running then
		return true
	end
	local cunning = cfg().ObserverCunning or 0
	local tier = def.difficulty or 2
	if story == Story.Arrival then
		return false
	elseif story == Story.Unease then
		return tier <= 2 + math.min(cunning, 1) and def.category ~= Enums.AnomalyCategory.Dangerous and def.rarity ~= "LEGENDARY"
	elseif story == Story.Distortion then
		return tier <= 3 + math.min(cunning, 1) and def.category ~= Enums.AnomalyCategory.Dangerous and def.rarity ~= "LEGENDARY"
	elseif story == Story.Danger then
		return def.rarity ~= "LEGENDARY" or cunning >= 1
	end
	return true
end

------------------------------------------------------------------------------------
-- Loop
------------------------------------------------------------------------------------

local function spawnInterval(): number
	local c = cfg()
	local base = rng:Range(c.SpawnInterval)
	if phase == Phase.Calm then
		base *= 0.8
	elseif phase == Phase.Fear then
		base *= 1.6
	elseif phase == Phase.Relief then
		base *= 1.1
	end
	if story == Story.Unease then
		base *= 1.25
	elseif story == Story.Collapse then
		base *= 0.75
	end
	-- keep the quota reachable: speed up when the clock is running out
	local state = Registry.ObjectiveService:GetState()
	if state and not state.locks.ANOMALIES then
		local remaining = GameConfig.Round.MaxRoundTime - Registry.RoundService:GetElapsed()
		local needed = state.quota - state.found
		if needed > 0 and remaining / needed < 70 then
			base *= 0.55
		end
	end
	return base / aggression()
end

local function targetActive(): number
	local players = #Registry.PlayerService:GetAlive()
	local n = 1 + math.ceil(players / 2)
	local d = Registry.RoundService:GetDifficulty()
	if d == Enums.Difficulty.Hard then
		n += 1
	elseif d == Enums.Difficulty.Nightmare then
		n += 2
	end
	if story == Story.Unease then
		n = math.min(n, 2)
	end
	return n
end

-- One private, deniable moment for one player (see PARANOIA above). Only for
-- players the Observer is not already near, only in the quiet parts of the curve.
local function paranoia()
	local candidates = {}
	for _, p in Registry.PlayerService:GetAlive() do
		if Registry.ObserverService:ProximityLevel(p) <= 2 then
			table.insert(candidates, p)
		end
	end
	if #candidates == 0 then
		return
	end
	local player = candidates[rng:Int(1, #candidates)]
	local pool
	if story == Story.Unease then
		pool = { "micro", "micro", "micro", "silence" }
	else
		pool = { "micro", "micro", "glimpse", "glimpse", "shadow", "silence" }
	end
	local kind = rng:Pick(pool)
	if not afford(kind) then
		kind = "micro"
		if not afford(kind) then
			return
		end
	end
	charge(kind)
	Net.fire(player, "Director", { cue = "paranoia", kind = kind, seed = rng:Int(1, 1e6) })
end

function HorrorDirector:Paranoia(player: Player, kind: string)
	Net.fire(player, "Director", { cue = "paranoia", kind = kind, seed = rng:Int(1, 1e6) })
end

local function step()
	if not running then
		return
	end
	local now = os.clock()
	dread = math.max(0, dread - 0.25)
	storyStep()
	-- anomalies (none during ARRIVAL: the tutorial one is handled by RoundService)
	if story ~= Story.Arrival and Registry.AnomalyService:GetActiveCount() < targetActive() and now - lastSpawnAt > nextSpawnIn then
		lastSpawnAt = now
		nextSpawnIn = spawnInterval()
		Registry.AnomalyService:TrySpawn()
	end
	-- ambience: sparse while arriving, regular afterwards
	if phase ~= Phase.Fear and now - lastAmbientAt > nextAmbientIn then
		lastAmbientAt = now
		nextAmbientIn = if story == Story.Arrival then rng:Number(24, 45) else rng:Number(14, 32)
		ambientEvent()
	end
	-- the opening is quiet: no tension cycle until the power fails
	if story == Story.Arrival then
		return
	end
	budget = math.min(BUDGET_MAX, budget + (BUDGET_RATE[story] or 0.5) * aggression())
	workspace:SetAttribute("TensionBudget", math.floor(budget))
	if (phase == Phase.Calm or phase == Phase.Tension) and now >= nextParanoiaAt then
		nextParanoiaAt = now + rng:Number(24, 52) / aggression()
		paranoia()
	end
	-- phase machine
	if phase == Phase.Fear then
		if not Registry.ObserverService:IsActive() and now > phaseEndsAt - 30 then
			setPhase(Phase.Relief, rng:Number(28, 45))
		elseif now > phaseEndsAt and not Registry.ObserverService:IsActive() then
			setPhase(Phase.Relief, rng:Number(28, 45))
		end
	elseif now >= phaseEndsAt then
		if phase == Phase.Calm then
			setPhase(Phase.Tension, rng:Number(22, 38) / aggression())
		elseif phase == Phase.Tension then
			-- silence before the event
			Net.fireAll("Director", { cue = "silence", duration = rng:Number(5, 9) })
			task.delay(rng:Number(4, 7), function()
				if running and phase == Phase.Tension then
					HorrorDirector:EnterFear()
				end
			end)
			phaseEndsAt = now + 12
		elseif phase == Phase.Relief then
			local calm = rng:Number(40, 75) / aggression() * (1 - dread / 200)
			if story == Story.Unease then
				calm *= 1.3
			elseif story == Story.Collapse then
				calm *= 0.7
			end
			setPhase(Phase.Calm, calm)
		end
	end
	-- the total blackout of the collapse happens even without a fear event
	if story == Story.Collapse and not totalBlackoutDone and inStory() > 20 then
		maybeBlackout()
	end
end

function HorrorDirector:BeginRound(seed: number)
	rng = SeededRandom.new(seed, "director")
	running = true
	roundStart = os.clock()
	dread = 0
	outageDone = false
	totalBlackoutDone = false
	lastSpawnAt = os.clock()
	nextSpawnIn = 18
	lastAmbientAt = os.clock()
	nextAmbientIn = 20
	lastHuntAt = -math.huge
	lastSightingAt = -math.huge
	lastBlackoutAt = os.clock()
	lastScareAt = os.clock() - 30
	scaresThisRound = 0
	usedScares = {}
	budget = 0
	nextParanoiaAt = os.clock() + 40
	story = ""
	setStory(Story.Arrival)
	setPhase(Phase.Calm, 9999)
end

function HorrorDirector:BeginEscape()
	setStory(Story.Escape)
	setPhase(Phase.Fear, 9999)
end

function HorrorDirector:EndRound()
	running = false
	Registry.LightingService:EndBlackout(true)
	phase = Phase.Calm
	story = Story.Arrival
	workspace:SetAttribute("TensionPhase", Phase.Calm)
	workspace:SetAttribute("RoundPhase", nil)
end

-- Admin: jump to the next story phase.
function HorrorDirector:AdvanceStory()
	if not running then
		return
	end
	if story == Story.Arrival then
		self:TriggerOutage()
		return
	end
	local index = self:StoryIndex()
	local nextPhase = Enums.RoundPhaseOrder[index + 1]
	if nextPhase and nextPhase ~= Story.Escape then
		setStory(nextPhase)
	end
end

function HorrorDirector:Start()
	local blackoutLevel = 0
	Registry.LightingService.BlackoutChanged:Connect(function(level)
		local previous = blackoutLevel
		blackoutLevel = level
		if level == 0 and running then
			-- whoever is still standing survived it
			local was = workspace:GetAttribute("LastBlackoutLevel") or 0
			if was >= 3 then
				HorrorDirector:OnBlackoutSurvived(was)
			end
		end
		if level > 0 then
			if running and previous == 0 then
				for _, p in Registry.PlayerService:GetAlive() do
					Registry.AnalyticsService:Milestone(p, "BLACKOUT", level)
				end
			end
			workspace:SetAttribute("LastBlackoutLevel", level)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step)
			if not ok then
				warn("[HorrorDirector] step error:", err)
			end
		end
	end)
end

return HorrorDirector
