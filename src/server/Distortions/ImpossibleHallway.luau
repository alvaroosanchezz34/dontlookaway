--[[
	ImpossibleHallway
	A distortion (Catalog/Distortions): one player is somewhere they cannot
	be, The Observer is at the end of it, and the way out is behind them.
	DistortionService chooses the moment and the player, saves where they
	were, and brings them back; this module runs everything in between.
	The server decides every outcome; the client (DistortionController) only
	paints, plays and frames what it is told.

	Phases (ctx.phase), each with its own time limit:
	  BREAK   the client flickers, drops the sound, cuts to black (0.7 s)
	  ARRIVE  the player is in the corridor, facing down it; the picture
	          fades in. Far away, at the end, something stands (1.4 s)
	  NOTICE  it only watches. Nothing moves. The far lamps sag around it.
	          5-8 s, or less if the player walks toward it
	  WAKE    the lamps around it die all at once; it starts (1.6 s)
	  CHASE   it comes. The dark comes with it: every lamp behind it and a
	          few steps ahead of it is dead (the corridor's DarkFrom). Its
	          pace keeps it a little behind someone who keeps moving, closer
	          and closer toward the end; someone who stops, it reaches.
	          Its own rules hold: looking at it holds it, but only where it
	          can be made out (a lamp still lit at it, a flashlight on it, or
	          within arm's reach of the dark), and nobody can stare forever
	          (the forced blink). The catch keeps its fairness: you hear it
	          breathe one reaction time before it can take you.
	Outcomes (to DistortionService:Finish)
	  escaped   the player reached the door (the local exit line)
	  taken     it reached them, or the chase ran out of time: no death; a
	            jolt, and the building's attention (dread)
	  cancelled anything that breaks the event (handled by the service)

	The corridor is HallwayBuilder's, built once and kept in ServerStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)
local HallwayBuilder = require(script.Parent.HallwayBuilder)

local ImpossibleHallway = {}

ImpossibleHallway.id = "ImpossibleHallway"

-- the pacing, in one place (local studs along the corridor, toward the door)
ImpossibleHallway.Pace = {
	gapStart = 46, -- how far behind a moving player it stays at first
	gapEnd = 14, -- and at the door: closer and closer
	follow = 0.6, -- how hard it closes the difference (1/s)
	minSpeed = 5,
	maxSpeed = 24, -- faster than a sprint: stopping is never safe
	stallSpeed = 12, -- a player standing still is reached
	stallAfter = 1.6, -- seconds under 2.5 studs/s before it counts as stopping
	darkAhead = 8, -- the dead lamps reach this far in front of it
	stepEvery = 3.6, -- studs between its footsteps
	noticeMin = 5,
	noticeMax = 8,
	chaseLimit = 55,
}

local hall: Model? = nil
local lamps: { { z: number, dead: boolean } } = {}

-- The corridor, built on first use and kept out of the world between uses.
function ImpossibleHallway.hall(): Model
	if hall and hall.Parent then
		return hall :: Model
	end
	local built = HallwayBuilder.build()
	built.Parent = ServerStorage
	table.clear(lamps)
	for _, lamp in (built:FindFirstChild("Lamps") :: Folder):GetChildren() do
		table.insert(lamps, { z = lamp:GetAttribute("Z"), dead = lamp:GetAttribute("Dead") == true })
	end
	hall = built
	return built
end

-- Is there a lamp lit over this local z (not dead, not in the dark)?
function ImpossibleHallway.litAt(z: number, darkFrom: number): boolean
	if z <= darkFrom then
		return false
	end
	for _, lamp in lamps do
		if not lamp.dead and lamp.z > darkFrom and math.abs(lamp.z - z) <= HallwayBuilder.SEGMENT * 0.6 then
			return true
		end
	end
	return false
end

-- Where it wants to be: behind the player by the gap for this point of the
-- run; returns its speed this step.
function ImpossibleHallway.paceSpeed(gap: number, progress: number, playerSpeed: number, stalledFor: number, speedScale: number): number
	local P = ImpossibleHallway.Pace
	local target = P.gapStart - (P.gapStart - P.gapEnd) * math.clamp(progress, 0, 1) ^ 1.2
	local speed = math.max(playerSpeed, 0) + (gap - target) * P.follow
	if stalledFor >= P.stallAfter then
		speed = math.max(speed, P.stallSpeed)
	end
	return math.clamp(speed * speedScale, P.minSpeed, P.maxSpeed * speedScale)
end

local function send(ctx, cue: string, data: { [string]: any }?)
	local payload = data or {}
	payload.cue = cue
	payload.id = ImpossibleHallway.id
	payload.token = ctx.token
	Net.fire(ctx.player, "Distortion", payload)
end

local function setDark(ctx, z: number)
	local h = hall
	if not h then
		return
	end
	-- the dark only ever comes closer
	if z > ctx.data.darkFrom + 0.5 then
		ctx.data.darkFrom = z
		h:SetAttribute("DarkFrom", math.floor(z * 2) / 2)
	end
end

-- Can the player hold it in place right now (its own rule, in this place)?
local function holds(ctx, observerHead: Vector3, model: Model): boolean
	local player = ctx.player
	if (ctx.data.blinkUntil or 0) > os.clock() then
		return false
	end
	if not Registry.PlayerService:IsLookingAt(player, observerHead, "screen", 260, model) then
		return false
	end
	local headLocal = HallwayBuilder.toLocal(observerHead)
	if ImpossibleHallway.litAt(headLocal.Z, ctx.data.darkFrom) then
		return true
	end
	local eye = Registry.PlayerService:GetEye(player)
	if eye and (eye - observerHead).Magnitude <= GameConfig.Perception.DarkSightRange then
		return true
	end
	-- a flashlight on it
	if Registry.InventoryService:IsLightOn(player) then
		local look = Registry.PlayerService:GetLook(player)
		local F = GameConfig.Flashlight
		if look then
			local delta = observerHead - look.origin
			local dist = delta.Magnitude
			if dist <= F.Range and look.dir:Dot(delta / math.max(dist, 0.01)) >= math.cos(math.rad(F.Angle / 2 + 6)) then
				return true
			end
		end
	end
	return false
end

function ImpossibleHallway.check(ctx): (boolean, string?)
	if not Registry.ObserverService:IsAvailable() then
		return false, "The Observer is busy elsewhere"
	end
	local ok, err = pcall(ImpossibleHallway.hall)
	if not ok then
		return false, "the corridor could not be built: " .. tostring(err)
	end
	return true, nil
end

function ImpossibleHallway.start(ctx)
	ctx.data.darkFrom = -HallwayBuilder.LENGTH - 10
	ctx.service:Phase(ctx, "BREAK")
	send(ctx, "break")
	-- the cut to black happens on the client; the move happens behind it
	ctx.service:After(ctx, 0.7, function()
		local h = ImpossibleHallway.hall()
		h:SetAttribute("DarkFrom", ctx.data.darkFrom)
		h:SetAttribute("Stutter", false)
		h.Parent = workspace
		local model, humanoid, root = Registry.ObserverService:Borrow(HallwayBuilder.observerCFrame(), ctx.player)
		if not model or not humanoid or not root then
			ctx.service:Finish(ctx, "cancelled", "The Observer could not be placed")
			return
		end
		root.Anchored = true
		ctx.data.model, ctx.data.humanoid, ctx.data.root = model, humanoid, root
		Registry.PlayerService:Teleport(ctx.player, HallwayBuilder.spawnCFrame())
		local proot = Util.getRoot(ctx.player)
		if proot then
			proot.AssemblyLinearVelocity = Vector3.zero
		end
		ctx.data.lastPz = HallwayBuilder.SPAWN_Z
		ctx.data.lastObsZ = HallwayBuilder.OBSERVER_Z
		ctx.data.stepAcc = 0
		ctx.data.stalled = 0
		ctx.data.stare = 0
		ctx.data.playerSpeed = 0
		ctx.service:Phase(ctx, "ARRIVE")
		send(ctx, "arrive", { hall = h, look = HallwayBuilder.toWorld(0, 3, HallwayBuilder.SPAWN_Z - 40) })
	end)
end

local function wake(ctx)
	ctx.service:Phase(ctx, "WAKE")
	local root = ctx.data.root :: BasePart
	local obsZ = HallwayBuilder.toLocal(root.Position).Z
	-- the lamps around it die at once
	setDark(ctx, obsZ + ImpossibleHallway.Pace.darkAhead)
	Registry.AudioService:PlayAtFor({ ctx.player }, "ObserverSting", root.Position + Vector3.new(0, 7, 0), { volume = 0.9 })
	send(ctx, "wake", { at = root.Position })
	ctx.service:After(ctx, 1.6, function()
		local r = ctx.data.root :: BasePart
		r.Anchored = false
		pcall(function()
			r:SetNetworkOwner(nil)
		end)
		Registry.ObserverService:DistortionDrive({ behavior = "STALKING", state = Enums.ObserverState.Hunting, chase = true, sync = true })
		ctx.data.chaseStartedAt = os.clock()
		ctx.service:Phase(ctx, "CHASE")
		send(ctx, "chase")
	end)
end

local function taken(ctx)
	if ctx.data.taking then
		return
	end
	ctx.data.taking = true
	local humanoid = ctx.data.humanoid :: Humanoid
	humanoid.WalkSpeed = 0
	humanoid:Move(Vector3.zero)
	Registry.ObserverService:DistortionDrive({ behavior = "ATTACKING", state = Enums.ObserverState.Attacking })
	send(ctx, "taken")
	ctx.service:After(ctx, 0.9, function()
		ctx.service:Finish(ctx, "taken", "it reached them")
	end)
end

local function chaseStep(ctx, dt: number, pz: number)
	local P = ImpossibleHallway.Pace
	local model = ctx.data.model :: Model
	local humanoid = ctx.data.humanoid :: Humanoid
	local root = ctx.data.root :: BasePart
	local obsZ = HallwayBuilder.toLocal(root.Position).Z
	local gap = pz - obsZ
	-- how fast the player is getting away (smoothed), and whether they stopped
	local raw = (pz - ctx.data.lastPz) / math.max(dt, 1e-3)
	ctx.data.lastPz = pz
	ctx.data.playerSpeed += (raw - ctx.data.playerSpeed) * math.min(1, dt * 3)
	ctx.data.stalled = if ctx.data.playerSpeed < 2.5 then ctx.data.stalled + dt else 0
	local progress = (pz - HallwayBuilder.SPAWN_Z) / (0 - HallwayBuilder.SPAWN_Z)
	local cfg = Registry.RoundService:GetDifficultyConfig()
	local scale = math.max(1, (cfg.ObserverSpeed or 13.5) / 13.5)
	-- the dark comes with it
	setDark(ctx, obsZ + P.darkAhead)
	if hall then
		local stutter = progress > 0.55
		if hall:GetAttribute("Stutter") ~= stutter then
			hall:SetAttribute("Stutter", stutter)
		end
	end
	-- its own rule: held while someone can make it out, and nobody stares forever
	local head = model:FindFirstChild("Head") :: BasePart?
	local headPos = if head then head.Position else root.Position + Vector3.new(0, 4, 0)
	local held = holds(ctx, headPos, model)
	if held then
		ctx.data.stare += dt
		if ctx.data.stare >= (cfg.BlinkAfter or 11) then
			ctx.data.stare = 0
			ctx.data.blinkUntil = os.clock() + GameConfig.Observer.StareForcedBlinkDuration
			Net.fire(ctx.player, "Effect", { name = "Blink", duration = GameConfig.Observer.StareForcedBlinkDuration })
		end
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero)
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		Registry.ObserverService:DistortionDrive({ behavior = "OBSERVING", state = Enums.ObserverState.Watched, sync = true })
	else
		ctx.data.stare = math.max(0, ctx.data.stare - dt * 2)
		local speed = ImpossibleHallway.paceSpeed(gap, progress, ctx.data.playerSpeed, ctx.data.stalled, scale)
		humanoid.WalkSpeed = speed
		local goal = HallwayBuilder.toWorld(0, 0, math.min(pz - 1, -1))
		humanoid:MoveTo(goal)
		Registry.ObserverService:DistortionDrive({ behavior = "STALKING", state = Enums.ObserverState.Hunting, face = goal - root.Position })
		-- (its steps, breath and the frenzy around them are the client's:
		-- DistortionController hears it move)
	end
	ctx.data.lastObsZ = obsZ
	-- the breath, then (one reaction time later) the catch
	local reaction = cfg.ReactionTime or 1.2
	local reach = GameConfig.Observer.CatchDistance + 1.5
	if gap < reach + (humanoid.WalkSpeed * reaction) and not ctx.data.warnedAt then
		ctx.data.warnedAt = os.clock()
		ctx.data.strikeAfter = reaction + math.random() * 0.25
		Registry.AudioService:PlayAtFor({ ctx.player }, "ObserverInhale", headPos, { volume = 1 })
		Net.fire(ctx.player, "Effect", { name = "ObserverClose" })
	elseif ctx.data.warnedAt and gap > reach + 12 then
		-- they got away again: the next approach breathes again
		ctx.data.warnedAt = nil
	end
	if gap <= reach and ctx.data.warnedAt and os.clock() - ctx.data.warnedAt >= ctx.data.strikeAfter then
		taken(ctx)
		return
	end
	if os.clock() - (ctx.data.chaseStartedAt or os.clock()) > P.chaseLimit then
		taken(ctx)
	end
end

function ImpossibleHallway.step(ctx, dt: number)
	local phase = ctx.phase
	if phase == "BREAK" or ctx.data.taking then
		return
	end
	local proot = Util.getRoot(ctx.player)
	if not proot then
		ctx.service:Finish(ctx, "cancelled", "no character")
		return
	end
	if not HallwayBuilder.contains(proot.Position, 6) then
		ctx.service:Finish(ctx, "cancelled", "the player left the corridor")
		return
	end
	local pz = HallwayBuilder.toLocal(proot.Position).Z
	if pz >= HallwayBuilder.EXIT_Z then
		ctx.service:Finish(ctx, "escaped", "reached the door")
		return
	end
	local since = os.clock() - ctx.phaseAt
	if phase == "ARRIVE" then
		if since >= 1.4 then
			ctx.data.noticeFor = ImpossibleHallway.Pace.noticeMin + math.random() * (ImpossibleHallway.Pace.noticeMax - ImpossibleHallway.Pace.noticeMin)
			ctx.service:Phase(ctx, "NOTICE")
			send(ctx, "notice")
			local root = ctx.data.root :: BasePart
			Registry.AudioService:PlayAtFor({ ctx.player }, "ObserverBreath", root.Position + Vector3.new(0, 7, 0), { volume = 0.5 })
		end
	elseif phase == "NOTICE" then
		-- walking toward it wakes it sooner
		if since >= ctx.data.noticeFor or pz < HallwayBuilder.SPAWN_Z - 15 then
			wake(ctx)
		end
	elseif phase == "CHASE" then
		chaseStep(ctx, dt, pz)
	end
end

-- Puts everything back (the service calls it once the player has been moved
-- out, whatever the outcome).
function ImpossibleHallway.cleanup(_ctx)
	Registry.ObserverService:Release()
	local h = hall
	if h then
		h:SetAttribute("DarkFrom", -HallwayBuilder.LENGTH - 10)
		h:SetAttribute("Stutter", false)
		h.Parent = ServerStorage
	end
end

-- Tests: the lamp list without building through hall().
function ImpossibleHallway._setLamps(list)
	lamps = list
end

return ImpossibleHallway
