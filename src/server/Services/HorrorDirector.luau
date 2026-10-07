--[[
	HorrorDirector
	Paces fear. The round cycles through CALM -> TENSION -> FEAR -> RELIEF.
	  CALM     anomalies happen, the building creaks, music is sparse
	  TENSION  ambience thins, then SILENCE: clients duck their ambient beds
	  FEAR     one event: a hunt, a sighting, a mimic or a (rare) scare
	  RELIEF   nothing hunts you. Breathe.
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
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local Registry = require(script.Parent.Parent.Registry)

local HorrorDirector = {}

local Phase = Enums.TensionPhase

local rng = SeededRandom.new(1, "director")
local running = false
local phase = Phase.Calm
local phaseEndsAt = 0
local dread = 0
local lastSpawnAt = 0
local nextSpawnIn = 30
local lastAmbientAt = 0
local nextAmbientIn = 20
local lastHuntAt = -math.huge
local lastSightingAt = -math.huge
local lastScareAt = -math.huge
local scaresThisRound = 0
local usedScares: { [string]: boolean } = {}
local roundStart = 0

local MAX_SCARES = 4

function HorrorDirector:Rng()
	return rng
end

function HorrorDirector:GetPhase(): string
	return phase
end

function HorrorDirector:GetDread(): number
	return dread
end

local function elapsed(): number
	return os.clock() - roundStart
end

local function cfg()
	return Registry.RoundService:GetDifficultyConfig()
end

-- 0.8 .. 1.6: grows with time, progress and team size
local function aggression(): number
	local state = Registry.ObjectiveService:GetState()
	local progress = 0
	if state then
		local released = 0
		for _, v in state.locks do
			if v then
				released += 1
			end
		end
		progress = released / 4
	end
	local players = #Registry.PlayerService:GetAlive()
	return math.clamp(0.8 + elapsed() / 900 + progress * 0.3 + math.max(0, players - 1) * 0.06 + dread / 250, 0.8, 1.6)
end

function HorrorDirector:AddDread(amount: number, reason: string?, player: Player?)
	dread = math.clamp(dread + amount, 0, 100)
	if Registry.AdminService then
		Registry.AdminService:Log(string.format("dread +%d (%s) -> %d", amount, reason or "?", dread))
	end
	-- too much dread draws attention to whoever caused it
	if player and dread >= 70 and phase ~= Phase.Fear and not Registry.ObserverService:IsActive() and elapsed() > cfg().FirstSightingAt then
		self:EnterFear(player)
	end
end

local function setPhase(newPhase: string, duration: number)
	phase = newPhase
	phaseEndsAt = os.clock() + duration
	workspace:SetAttribute("TensionPhase", newPhase)
	Net.fireAll("Director", { cue = "phase", phase = newPhase })
end

------------------------------------------------------------------------------------
-- Ambient life
------------------------------------------------------------------------------------

local AMBIENT = { "DistantPipe", "DistantKnock", "DistantMetal", "DistantGroan", "WoodCreak", "DistantPipe", "WoodCreak" }

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
	if roll < 0.55 then
		-- a sound somewhere nearby, never on top of the player
		local angle = rng:Number(0, math.pi * 2)
		local dist = rng:Number(25, 60)
		local pos = root.Position + Vector3.new(math.cos(angle) * dist, rng:Number(-6, 10), math.sin(angle) * dist)
		Registry.AudioService:PlayAt(rng:Pick(AMBIENT), pos)
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

SCARES.observer_peek = function(player, root)
	if Registry.ObserverService:IsActive() then
		return false
	end
	if Registry.ObserverService:Sighting(player) then
		return true
	end
	return false
end

local SCARE_ORDER = { "door_slam", "bulb_pop", "vent_bang", "whisper_ear", "shadow_run", "falling_box", "mirror_flash", "lights_out_brief", "breath_neck", "radio_static", "phone_burst", "observer_peek" }

local function tryScare(player: Player): boolean
	if scaresThisRound >= MAX_SCARES or os.clock() - lastScareAt < 90 then
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
			if Registry.AdminService then
				Registry.AdminService:Log("scare: " .. name .. " -> " .. player.Name)
			end
			return true
		end
	end
	return false
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
	local t = elapsed()
	local victim = forced or mostIsolated()
	if not victim then
		setPhase(Phase.Relief, 20)
		return
	end
	setPhase(Phase.Fear, 40)
	local agg = aggression()
	local huntReady = t >= c.FirstHuntAt / agg and os.clock() - lastHuntAt >= rng:Range(c.HuntInterval) / agg
	if huntReady and Registry.ObserverService:StartHunt(victim, { reason = "director" }) then
		return
	end
	if t >= c.FirstSightingAt / agg and os.clock() - lastSightingAt > 70 then
		local viewer, imitated = separatedPair()
		if viewer and rng:Chance(0.55) and Registry.ObserverService:Mimic(viewer, imitated) then
			lastSightingAt = os.clock()
			return
		end
		if #Registry.PlayerService:GetAlive() == 1 and rng:Chance(0.2) and Registry.ObserverService:Mimic(victim, victim) then
			lastSightingAt = os.clock()
			return
		end
		if Registry.ObserverService:Sighting(victim) then
			lastSightingAt = os.clock()
			return
		end
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
		setPhase(Phase.Relief, 35)
		dread = math.max(0, dread - 15)
	end
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
	if Registry.RoundService:GetDifficulty() == Enums.Difficulty.Hard then
		n += 1
	end
	return n
end

local function step()
	if not running then
		return
	end
	local now = os.clock()
	local t = elapsed()
	dread = math.max(0, dread - 0.25)
	-- anomalies
	if t > 12 and Registry.AnomalyService:GetActiveCount() < targetActive() and now - lastSpawnAt > nextSpawnIn then
		lastSpawnAt = now
		nextSpawnIn = spawnInterval()
		Registry.AnomalyService:TrySpawn()
	end
	-- ambience
	if phase ~= Phase.Fear and now - lastAmbientAt > nextAmbientIn then
		lastAmbientAt = now
		nextAmbientIn = rng:Number(14, 32)
		ambientEvent()
	end
	-- the opening of a round is always quiet
	if t < GameConfig.Round.CalmOpening then
		return
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
			setPhase(Phase.Calm, rng:Number(40, 75) / aggression() * (1 - dread / 200))
		end
	end
end

function HorrorDirector:BeginRound(seed: number)
	rng = SeededRandom.new(seed, "director")
	running = true
	roundStart = os.clock()
	dread = 0
	lastSpawnAt = os.clock()
	nextSpawnIn = 18
	lastAmbientAt = os.clock()
	nextAmbientIn = 12
	lastHuntAt = -math.huge
	lastSightingAt = -math.huge
	lastScareAt = os.clock() - 30
	scaresThisRound = 0
	usedScares = {}
	setPhase(Phase.Calm, GameConfig.Round.CalmOpening + 30)
end

function HorrorDirector:BeginEscape()
	setPhase(Phase.Fear, 9999)
end

function HorrorDirector:EndRound()
	running = false
	phase = Phase.Calm
	workspace:SetAttribute("TensionPhase", Phase.Calm)
end

function HorrorDirector:Start()
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
