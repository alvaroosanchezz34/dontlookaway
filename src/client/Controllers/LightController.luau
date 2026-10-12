--[[
	LightController
	Renders every light in the building from server attributes.

	Fixtures
	  Mode      on | flicker | dead     (the fixture's personality)
	  Circuit   MAIN | EMERGENCY        (MAIN needs building power)
	  Override  "off"                   (anomalies / scares force darkness)
	  ForceOn   true                    (anomalies light a fixture without power)
	  Tint      Color3                  (anomalies change the colour)
	Building state (workspace attributes)
	  Power, Blackout (0-4), BlackoutZone, BlackoutSeed, Escape

	Blackout levels: darker and more macabre (the rules: Shared/LightingRules)
	  1 FAILS     a third of the lamps stutter and buzz, then come back
	  2 BREATHES  the lamps swell and sink together; the light goes sickly pale
	  3 BEATS     the lamps beat like a heart; a wave of light runs down the
	              corridor toward you; the emergency lamps turn red
	  4 WATCHES   the lamps die one by one, far to near, and come back
	  Here: the wave and the dying (they depend on where you stand) and the
	  lamps near The Observer sagging and stuttering at any level: the light
	  is its. BlackoutFX adds the figures, the eyes and the sounds.

	Without power the dark is real: no light follows the camera. What you see
	without the flashlight is what glows (tubes still on, exit signs, beacon
	domes) and the faint red of the beacons; the flashlight is how you see.

	Lights far from the camera are disabled locally (light LOD) so the building
	stays fast on phones and consoles; their glowing tubes still read from afar.
	The LOD looks ahead: where the camera looks and walks, lamps switch on
	further out (AHEAD_REACH) and fade in over a wide band (FADE_BAND), and
	behind it they go sooner (BEHIND_REACH), so the cost stays about the same
	and a pool is already lit, its shadow settled, before you walk into it.
	The lamps that cast shadows are the ones nearest a point a few studs ahead
	of the camera (LEAD), not the camera itself, and a lamp changing between
	shadowed and not grows or shrinks its range over a few frames instead of
	jumping (RANGE_RATE).
	Near fixtures are evaluated every frame (smooth flicker); far ones in
	FAR_BUCKETS slices, one slice a frame, so no frame pays for all of them.
	Lights that follow the main power (PoweredLight) are collected once, not
	searched for in the whole workspace each time the power changes.

	A fixture can own several lights (VisualStandards.Fixtures): the shaped main
	light (SurfaceLight / SpotLight thrown down from the diffuser or shade) and
	the "Light" point light as fill. Each takes its "Ratio" of the fixture's
	brightness; tints, overrides, flicker and blackouts apply to all of them.
	The graphics quality tier sets the LOD distance, and on low quality only the
	fill stays on (at its "Solo" share) to halve the light count.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local VisualStandards = require(ReplicatedStorage.Shared.VisualStandards)
local LightingRules = require(ReplicatedStorage.Shared.LightingRules)

local LightController = {}

local LOD_DISTANCE = 95 -- updated from the quality tier
-- the LOD's reach ahead of the view (x1 + AHEAD_REACH) and behind it
-- (x1 - BEHIND_REACH), and the share of it over which a lamp fades in
local AHEAD_REACH = 0.35
local BEHIND_REACH = 0.3
local FADE_BAND = 0.35
-- shadows go to the lamps nearest a point this many studs ahead of the camera
local LEAD = 20
-- how fast a lamp's range follows its target (1/s): ~0.3 s to settle
local RANGE_RATE = 8
-- where the view is heading (flat): camera look and walking direction
local heading = Vector3.new(0, 0, -1)
local leadPoint = Vector3.zero
local useMain = true
local DARK = Color3.fromRGB(38, 38, 36)
local DEAD_LAMP = Color3.fromRGB(46, 42, 36)
-- lamps within this many studs of The Observer sag and stutter
local OBSERVER_SAG = 26
local observerAt: Vector3? = nil

type LightEntry = { light: Light, ratio: number, solo: number, main: boolean, range: number, cur: number }
type Info = { model: Model, light: PointLight?, lights: { LightEntry }, lamps: { BasePart }, flickerUntil: number, seed: number, lit: boolean, level: number, floor: string, bucket: number, wallDist: number, shadowed: boolean, dist: number, leadDist: number, inRange: boolean, evaluatedAt: number }
type Beacon = { model: Model, rotor: BasePart, beams: { SpotLight }, glow: PointLight?, dome: BasePart?, phase: number }

local fixtures: { [Model]: Info } = {}
local beacons: { [Model]: Beacon } = {}
local signs: { [Model]: PointLight } = {}
local roomFlicker: { [string]: number } = {}
local poweredLights: { [Light]: boolean } = {}
local random = Random.new()
local FAR_BUCKETS = 8

local function register(model: Instance)
	if not model:IsA("Model") or fixtures[model] then
		return
	end
	local lamps = {}
	local light = nil
	local lights = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Light") then
			if d:IsA("PointLight") and (light == nil or d.Name == "Light") then
				light = d
			end
			local ratio = d:GetAttribute("Ratio")
			local solo = d:GetAttribute("Solo")
			table.insert(lights, {
				light = d,
				ratio = if type(ratio) == "number" then ratio else 1,
				solo = if type(solo) == "number" then solo elseif type(ratio) == "number" then ratio else 1,
				main = d:GetAttribute("Main") == true,
				range = (d :: any).Range,
				cur = (d :: any).Range,
			})
		elseif d:IsA("BasePart") and (d.Name == "Tube" or d.Name == "Tube2" or d.Name == "Bulb") then
			table.insert(lamps, d)
		end
	end
	local room = model:GetAttribute("Room")
	local seed = model:GetAttribute("Seed") or random:NextInteger(1, 100000)
	local wallDist = model:GetAttribute("WallDist")
	fixtures[model] = {
		model = model,
		light = light,
		lights = lights,
		lamps = lamps,
		flickerUntil = 0,
		seed = seed,
		lit = false,
		level = 0,
		floor = if type(room) == "string" then room:sub(1, 1) else "",
		bucket = math.floor(seed) % FAR_BUCKETS,
		-- how far its light may reach without shadows (MapBuilder: WallDist)
		wallDist = (if type(wallDist) == "number" then wallDist else 40) + 1,
		shadowed = false,
		dist = math.huge,
		leadDist = math.huge,
		inRange = false,
		evaluatedAt = os.clock(),
	}
end

local function registerBeacon(model: Instance)
	if not model:IsA("Model") or beacons[model] then
		return
	end
	local rotor = model:FindFirstChild("Rotor") :: BasePart?
	if not rotor then
		return
	end
	local beams = {}
	for _, d in rotor:GetChildren() do
		if d:IsA("SpotLight") then
			table.insert(beams, d)
		end
	end
	local dome = model:FindFirstChild("Dome") :: BasePart?
	beacons[model] = { model = model, rotor = rotor, beams = beams, glow = dome and dome:FindFirstChildOfClass("PointLight"), dome = dome, phase = random:NextNumber(0, math.pi * 2) }
end

local function registerSign(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local glow = model:FindFirstChild("Glow", true)
	if glow and glow:IsA("PointLight") then
		signs[model] = glow
	end
end

local function blackoutLevel(): number
	local b = Workspace:GetAttribute("Blackout")
	return if type(b) == "number" then b else 0
end

local function evaluate(info: Info, camPos: Vector3, now: number, world: any)
	local m = info.model
	-- lit, how bright, what colour: the rules the server also reads (LightingRules)
	local flickerNow = now < info.flickerUntil or (roomFlicker[m:GetAttribute("Room") or ""] or 0) > now
	local reduced = State.settings.reducedEffects == true
	local lit, brightness, color = LightingRules.evaluate(LightingRules.fixture(m, info.seed), world, now, { flicker = flickerNow, reduced = reduced })
	local baseBrightness = m:GetAttribute("BaseBrightness") or 1
	local pivot = m:GetPivot().Position
	local here = (pivot - camPos).Magnitude
	-- the level's own patterns wait for the onset to finish (LightingRules)
	if lit and world.power and not world.escape and world.phase ~= "ONSET" then
		if world.level == 3 and not reduced then
			-- a wave of light runs down toward you (its crests move inward)
			local wave = 0.5 + 0.5 * math.sin(now * 2.4 + here * 0.18)
			brightness *= 0.85 + 0.3 * wave ^ 3
		elseif world.level >= 4 then
			-- the lamps die one by one, far to near, then all come back
			local period = if reduced then 12 else 7
			local p = (now % period) / period
			local front = 60 * (1 - p / 0.6)
			if p < 0.6 and here > math.max(front, 8) then
				lit = false
			end
		end
	end
	-- the light is its: lamps near The Observer sag and stutter, at any level
	if lit and observerAt then
		local r = (pivot - observerAt).Magnitude
		if r < OBSERVER_SAG then
			brightness *= 0.3 + 0.7 * (r / OBSERVER_SAG) ^ 2
			if math.noise(now * 7, info.seed * 0.11) < -0.35 then
				lit = false
			end
		end
	end
	local dist = here
	info.dist = dist
	local step = math.min(now - info.evaluatedAt, 0.5)
	info.evaluatedAt = now
	-- light LOD, looking ahead: a lamp in front of the view (or of where you
	-- walk) switches on further out than one behind you, and fades in over
	-- the outer FADE_BAND of its reach instead of switching on at a line, so
	-- the pool is lit and its shadow settled before you get there; the tube
	-- keeps glowing either way
	local ahead = if here > 0.5 then (pivot - camPos):Dot(heading) / here else 1
	local reach = LOD_DISTANCE * (if ahead >= 0 then 1 + AHEAD_REACH * ahead else 1 + BEHIND_REACH * ahead)
	local fade = math.clamp((reach - dist) / (reach * FADE_BAND), 0, 1)
	fade = fade * fade * (3 - 2 * fade)
	info.inRange = fade > 0
	-- shadow priority: near the lead point, and a lamp behind the view counts
	-- as further away than one in front of it at the same distance
	info.leadDist = (pivot - leadPoint).Magnitude * (if ahead < 0 then 1 - 0.8 * ahead else 1 - 0.15 * ahead)
	-- a jumpscare blacks out every light around you (ScareController)
	local inRange = lit and fade > 0 and not State.scareDark
	-- the lamps nearest the lead point cast shadows (pickShadowed); the others
	-- never reach past their room's walls, which a light without shadows
	-- would go through. A lamp gaining shadows grows to its full range over a
	-- few frames; one losing them keeps its shadows until it has shrunk back
	-- inside its walls, so it never lights through one
	local shadowed = info.shadowed
	local k = 1 - math.exp(-RANGE_RATE * step)
	for _, entry in info.lights do
		local l = entry.light
		if entry.main then
			l.Enabled = inRange and useMain
			l.Brightness = brightness * entry.ratio * fade
		else
			l.Enabled = inRange
			l.Brightness = brightness * (if useMain then entry.ratio else entry.solo) * fade
		end
		l.Color = color
		local cut = math.min(entry.range, info.wallDist)
		local target = if shadowed then entry.range else cut
		if not inRange then
			-- off: no need to ease, it starts from where it should be
			entry.cur = target
		else
			entry.cur += (target - entry.cur) * k
			if math.abs(target - entry.cur) < 0.05 then
				entry.cur = target
			end
		end
		l.Shadows = shadowed or entry.cur > cut + 0.05
		local range = entry.cur
		if math.abs((l :: any).Range - range) > 0.02 then
			(l :: any).Range = range
		end
	end
	info.level = if lit then brightness / math.max(baseBrightness, 0.01) else 0
	-- a dead lamp looks dead (dirty grey glass); one that is only off, dark
	local unlit = if m:GetAttribute("Mode") == "dead" then DEAD_LAMP else DARK
	for _, lamp in info.lamps do
		lamp.Color = if lit then color else unlit
		lamp.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
	end
	info.lit = lit
end

-- Shadow LOD: the N lit lamps nearest the lead point, a few studs ahead of
-- the camera (N per quality tier), cast shadows, so the lamps you are walking
-- toward have theirs before you reach them; a lamp keeps them until it drops
-- out of the nearest N + 3, so shadows do not jump on and off when two lamps
-- are about as far.
local shadowList: { Info } = {}
local function byLead(a: Info, b: Info): boolean
	return a.leadDist < b.leadDist
end
local function pickShadowed(count: number)
	local list = shadowList
	table.clear(list)
	for _, info in fixtures do
		if info.lit and info.inRange then
			table.insert(list, info)
		end
	end
	table.sort(list, byLead)
	local rank: { [Info]: number } = {}
	for i, info in list do
		rank[info] = i
	end
	for _, info in fixtures do
		local r = rank[info]
		if info.shadowed then
			info.shadowed = r ~= nil and r <= count + 3
		else
			info.shadowed = r ~= nil and r <= count
		end
	end
end

local function beaconsActive(): boolean
	return State.round.state ~= "LOBBY" and (Workspace:GetAttribute("Power") ~= true or blackoutLevel() >= 2 or Workspace:GetAttribute("Escape") == true)
end

local function updateBeacons(camPos: Vector3, now: number, dt: number)
	local active = beaconsActive()
	local strong = blackoutLevel() >= 3 or Workspace:GetAttribute("Escape") == true
	for model, b in beacons do
		if not model.Parent then
			beacons[model] = nil
		else
			local dist = (b.rotor.Position - camPos).Magnitude
			local on = active and dist < LOD_DISTANCE and not State.scareDark
			for _, beam in b.beams do
				beam.Enabled = on
				beam.Brightness = if strong then 0.8 else 0.5
			end
			if b.glow then
				b.glow.Enabled = on
				b.glow.Brightness = if strong then 0.45 else 0.3
			end
			if b.dome then
				b.dome.Material = if active then Enum.Material.Neon else Enum.Material.Glass
				b.dome.Color = if active then Color3.fromRGB(255, 70, 56) else Color3.fromRGB(90, 20, 18)
			end
			if on and dist < 70 then
				b.phase += dt * (if strong then 3.6 else 2.4)
				b.rotor.CFrame = CFrame.new(b.rotor.Position) * CFrame.Angles(0, b.phase, 0)
			end
		end
	end
end

local function updateSigns(camPos: Vector3)
	local dark = Workspace:GetAttribute("Power") ~= true or blackoutLevel() >= 2
	for model, glow in signs do
		if not model.Parent then
			signs[model] = nil
		else
			glow.Enabled = (model:GetPivot().Position - camPos).Magnitude < LOD_DISTANCE and not State.scareDark
			glow.Brightness = if dark then 0.95 else 0.55
		end
	end
end

function LightController:FlickerRoom(roomId: string, duration: number)
	roomFlicker[roomId] = os.clock() + duration
end

-- Stutter the fixtures within `radius` of a point (presence, paranoia). Returns
-- the nearest fixture's position, if any.
function LightController:FlickerNear(position: Vector3, radius: number, duration: number, limit: number?): Vector3?
	local hits = {}
	for model, info in fixtures do
		local d = (model:GetPivot().Position - position).Magnitude
		if d < radius then
			table.insert(hits, { info = info, d = d, at = model:GetPivot().Position })
		end
	end
	table.sort(hits, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#hits, limit or 2) do
		hits[i].info.flickerUntil = os.clock() + duration
	end
	return hits[1] and hits[1].at
end

local function trackPowered(d: Instance)
	if d:IsA("Light") and d:GetAttribute("PoweredLight") then
		poweredLights[d] = true
	end
end

-- one full search per map (MapReady); later additions arrive one by one
local function collectPowered()
	table.clear(poweredLights)
	for _, d in Workspace:GetDescendants() do
		trackPowered(d)
	end
end

local function applyPowered()
	local power = Workspace:GetAttribute("Power") == true
	for d in poweredLights do
		if d.Parent then
			d.Enabled = power
		else
			poweredLights[d] = nil
		end
	end
	for _, d in CollectionService:GetTagged("Screen") do
		if d:IsA("BasePart") and d:IsDescendantOf(Workspace) then
			d.Material = if power then Enum.Material.Neon else Enum.Material.Glass
			d.Color = if power then Color3.fromRGB(46, 62, 56) else Color3.fromRGB(18, 22, 20)
		end
	end
end

-- Where light falls right now near the camera: the lit lamps within maxDist
-- (BlackoutFX puts its figures in these pools).
function LightController:LitLamps(maxDist: number): { Vector3 }
	local list = {}
	for model, info in fixtures do
		if info.lit and info.dist < maxDist and model.Parent then
			table.insert(list, model:GetPivot().Position)
		end
	end
	return list
end

function LightController:Start()
	for _, m in CollectionService:GetTagged("Fixture") do
		register(m)
	end
	CollectionService:GetInstanceAddedSignal("Fixture"):Connect(function(m)
		task.defer(register, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Fixture"):Connect(function(m)
		fixtures[m :: Model] = nil
	end)
	for _, m in CollectionService:GetTagged("EmergencyBeacon") do
		registerBeacon(m)
	end
	CollectionService:GetInstanceAddedSignal("EmergencyBeacon"):Connect(function(m)
		task.defer(registerBeacon, m)
	end)
	for _, m in CollectionService:GetTagged("ExitSign") do
		registerSign(m)
	end
	CollectionService:GetInstanceAddedSignal("ExitSign"):Connect(function(m)
		task.defer(registerSign, m)
	end)
	collectPowered()
	Workspace.DescendantAdded:Connect(trackPowered)
	Workspace:GetAttributeChangedSignal("Power"):Connect(applyPowered)
	Workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
		task.wait(0.5)
		collectPowered()
		applyPowered()
	end)
	Net.event("Director").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.cue == "flicker" and type(payload.room) == "string" then
			self:FlickerRoom(payload.room, payload.duration or 2)
		elseif payload.cue == "sparks" and payload.at then
			Registry.EffectsController:Handle("Sparks", { at = payload.at })
		end
	end)
	-- near fixtures every frame (smooth flicker), far ones one slice a frame
	local farAcc = 0
	local lastCamPos: Vector3? = nil
	local frame = 0
	RunService.RenderStepped:Connect(function(dt)
		local camCF = Workspace.CurrentCamera.CFrame
		local camPos = camCF.Position
		local now = os.clock()
		frame += 1
		-- where the view is heading: mostly where it looks, partly where it
		-- walks (smoothed, flat), and the lead point a few studs along it
		local look = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		local moved = if lastCamPos then camPos - lastCamPos else Vector3.zero
		lastCamPos = camPos
		local walk = Vector3.new(moved.X, 0, moved.Z)
		local want = (if look.Magnitude > 0.1 then look.Unit else heading) * 0.65 + (if walk.Magnitude > 0.01 then walk.Unit * 0.35 else Vector3.zero)
		if want.Magnitude > 0.1 then
			heading = heading:Lerp(want.Unit, math.min(1, dt * 6))
			if heading.Magnitude > 0.1 then
				heading = heading.Unit
			end
		end
		leadPoint = camPos + heading * LEAD
		local bucket = frame % FAR_BUCKETS
		observerAt = nil
		for _, o in CollectionService:GetTagged("Observer") do
			if o:IsA("Model") and o:IsDescendantOf(Workspace) then
				observerAt = o:GetPivot().Position
			end
		end
		-- the building's state once per frame (the phases read the server's clock)
		local world = LightingRules.world(Workspace)
		farAcc += dt
		local doFar = farAcc > 0.35
		if doFar then
			farAcc = 0
			updateSigns(camPos)
			local access = Registry.AccessibilityController
			local tier = VisualStandards.tier(if access then access:Quality() else 2)
			LOD_DISTANCE = tier.lightLod
			useMain = tier.secondary
			pickShadowed(tier.shadowLights)
		end
		for model, info in fixtures do
			if not model.Parent then
				fixtures[model] = nil
			else
				local near = (model:GetPivot().Position - camPos).Magnitude < 60
				if near or info.bucket == bucket then
					evaluate(info, camPos, now, world)
				end
			end
		end
		updateBeacons(camPos, now, dt)
	end)
	-- ambient random flickers on nearby lights (not every light is stable)
	task.spawn(function()
		while true do
			task.wait(random:NextNumber(4, 10))
			if State.status == "ALIVE" then
				local camPos = Workspace.CurrentCamera.CFrame.Position
				for model, info in fixtures do
					if (model:GetPivot().Position - camPos).Magnitude < 40 and random:NextNumber() < 0.08 then
						info.flickerUntil = os.clock() + random:NextNumber(0.3, 1.2)
						Registry.AudioController:Play("LightFlicker", model:GetPivot().Position)
						break
					end
				end
			end
		end
	end)
end

return LightController
