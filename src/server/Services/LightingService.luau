--[[
	LightingService
	Global, cinematic lighting. Uses Future lighting with restrained post effects:
	soft bloom only on emissive sources, a cold desaturated grade, atmosphere for
	depth. Per-player effects (fear tint, blur, blink, dark adaptation) are handled
	on clients.

	Darkness is a deep grey, MONOCHROME's dark (docs/LIGHTING_MONOCHROME.md).
	With power, the fixtures do the lighting: each throws a pool that fades out
	and the space between two still reads, dimly; a room with no lamp is a deep
	grey where silhouettes show up close. Each blackout level takes light
	away and changes how what is left behaves (LightingRules). Without power (EMERGENCY)
	what you see without the flashlight is what glows (emergency lamps, exit
	signs, beacon domes) and the silhouettes right next to you: you need the
	flashlight. No light follows the camera. The only lift is the
	player's brightness setting (AccessibilityController), kept to a small range
	so it helps a dark screen without erasing the dark. Fully black happens
	once, on purpose and only on one screen: the jumpscare (ScareController)
	blacks out every light around the lens for about a second.

	Power
	  workspace "Power" (bool)        MAIN circuit fixtures need it
	Blackouts (temporary, layered on top of Power)
	  workspace "Blackout" (0-4)      0 none. Each level is darker and more
	                                  macabre (LightingRules.LEVEL_MEAN):
	                                  1 FAILS: a third of the lamps stutter and buzz
	                                  2 BREATHES: the lamps swell and sink together,
	                                    the light drains to a sick pale white
	                                  3 BEATS: the lamps beat like a heart, the
	                                    emergency lamps turn red, figures in the light
	                                  4 WATCHES: lamps die far to near and come
	                                    back; eyes at the edge of the light
	                                  Without power only the emergency lamps light,
	                                  and level 4 takes half of them (the collapse)
	  workspace "BlackoutZone"        a floor id (kept for level 2's sounds; it no
	                                  longer darkens the floor)
	  workspace "BlackoutSeed"        which lamps stutter (clients hash it)
	Fixtures, exit signs and beacons read these attributes client-side.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LightingRules = require(ReplicatedStorage.Shared.LightingRules)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local LightingService = {}

LightingService.BlackoutChanged = Signal.new() -- (level)

local cc: ColorCorrectionEffect
local bloom: BloomEffect
local atmosphere: Atmosphere
local dof: DepthOfFieldEffect

-- Ambient values light nothing on their own inside the building: the fixtures
-- do. Inside, every preset is NORMAL or darker, and each step of the power
-- failing is a step down (NORMAL >= EMERGENCY >= BLACKOUT in ambient and in
-- exposure). The escape and the scripted moments change the colour and the
-- grade, never the amount of light. Only the places outside the building
-- (LOBBY, OUTSIDE, RESULTS) are lighter.
-- Colour: near monochrome, like MONOCHROME's grey (saturation -0.75 to -0.86
-- inside): the red of the emergency lamps and of danger is what is left of
-- colour. The black is a deep grey, never a dead screen (MONOCHROME): ColorCorrection
-- pivots contrast round mid grey, so without a lift every dark tone below a
-- threshold is crushed to 0 and the stretch between two lamps reads as a hole
-- right next to the pool. Each interior grade lifts its blacks by half its
-- contrast plus BLACK_FLOOR, like the raised blacks of old film. The
-- contrast itself is low: the pool and the stretch between two pools are
-- closer in brightness, the dark comes from the exposure, not from crushing.
-- Measured in Studio, docs/LIGHTING_MONOCHROME.md (v3).
local BLACK_FLOOR = 0.035
local function lifted(contrast: number): number
	return contrast / 2 + BLACK_FLOOR
end

LightingService.Presets = {
	LOBBY = {
		Ambient = Color3.fromRGB(34, 32, 30),
		OutdoorAmbient = Color3.fromRGB(40, 42, 48),
		ExposureCompensation = 0.2,
		cc = { Brightness = 0.02, Contrast = 0.12, Saturation = -0.45, TintColor = Color3.fromRGB(255, 244, 232) },
		atmosphere = { Density = 0.3, Haze = 1.3, Glare = 0, Color = Color3.fromRGB(70, 76, 86), Decay = Color3.fromRGB(40, 42, 48) },
	},
	OUTSIDE = {
		Ambient = Color3.fromRGB(30, 33, 40),
		OutdoorAmbient = Color3.fromRGB(46, 52, 64),
		ExposureCompensation = 0.35,
		cc = { Brightness = 0.0, Contrast = 0.14, Saturation = -0.6, TintColor = Color3.fromRGB(226, 234, 255) },
		atmosphere = { Density = 0.4, Haze = 2.1, Glare = 0, Color = Color3.fromRGB(70, 78, 92), Decay = Color3.fromRGB(36, 40, 50) },
	},
	-- main power lost: emergency lamps, exit signs, the flashlight. Darker than
	-- NORMAL in what reaches the eye (no fixture lights the floor); the
	-- exposure stays a little over NORMAL's so the beam still reads
	EMERGENCY = {
		Ambient = Color3.fromRGB(14, 14, 16),
		OutdoorAmbient = Color3.fromRGB(16, 17, 19),
		ExposureCompensation = 0.3,
		cc = { Brightness = lifted(0.1), Contrast = 0.1, Saturation = -0.75, TintColor = Color3.fromRGB(226, 234, 250) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(14, 15, 18), Decay = Color3.fromRGB(6, 6, 8) },
	},
	-- NORMAL: the building with power and no event. The reference for play: a
	-- dark corridor where only the fixtures light anything. Each one throws a
	-- pool that fades out (VisualStandards.Fixtures) and the stretch between
	-- pools is dim, never a hole; the glowing tubes read from afar. A minimal
	-- ambient, a cold near-monochrome grade, no haze to grey the distance. The
	-- exposure is under zero: the dark is the exposure's, and the contrast is
	-- kept low so the penumbra of every pool survives.
	NORMAL = {
		Ambient = Color3.fromRGB(16, 16, 17),
		OutdoorAmbient = Color3.fromRGB(18, 19, 21),
		ExposureCompensation = -1.6,
		cc = { Brightness = lifted(0.08), Contrast = 0.08, Saturation = -0.82, TintColor = Color3.fromRGB(228, 236, 250) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(26, 28, 32), Decay = Color3.fromRGB(10, 10, 12) },
	},
	-- scripted moments (cinematics, the Observer's reveal): the same building,
	-- harder and colder, for a few seconds at a time. NORMAL's light, a
	-- harsher, colder grade
	CINEMATIC = {
		Ambient = Color3.fromRGB(15, 15, 16),
		OutdoorAmbient = Color3.fromRGB(17, 18, 21),
		ExposureCompensation = -1.6,
		cc = { Brightness = lifted(0.14), Contrast = 0.14, Saturation = -0.86, TintColor = Color3.fromRGB(220, 230, 252) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(24, 27, 33), Decay = Color3.fromRGB(9, 10, 12) },
	},
	-- The blackouts with power (LightingRules.LEVEL_MEAN): each level takes
	-- light away, lamps and exposure both, and turns the grade. 2 BREATHES:
	-- the light drains to a sick pale white; 3 BEATS: harder, a trace of red
	-- (the emergency lamps are the only colour); 4 WATCHES: the darkest,
	-- coldest grade
	BREATH = {
		Ambient = Color3.fromRGB(14, 14, 15),
		OutdoorAmbient = Color3.fromRGB(16, 17, 19),
		ExposureCompensation = -1.75,
		cc = { Brightness = lifted(0.08), Contrast = 0.08, Saturation = -0.85, TintColor = Color3.fromRGB(232, 240, 222) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(26, 28, 26), Decay = Color3.fromRGB(10, 11, 10) },
	},
	HEARTBEAT = {
		Ambient = Color3.fromRGB(12, 12, 13),
		OutdoorAmbient = Color3.fromRGB(14, 15, 17),
		ExposureCompensation = -1.9,
		cc = { Brightness = lifted(0.1), Contrast = 0.1, Saturation = -0.78, TintColor = Color3.fromRGB(246, 228, 226) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(30, 24, 24), Decay = Color3.fromRGB(12, 9, 9) },
	},
	BLACKOUT = {
		Ambient = Color3.fromRGB(10, 10, 11),
		OutdoorAmbient = Color3.fromRGB(12, 13, 15),
		ExposureCompensation = -2.05,
		cc = { Brightness = lifted(0.12), Contrast = 0.12, Saturation = -0.86, TintColor = Color3.fromRGB(236, 228, 232) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(20, 20, 22), Decay = Color3.fromRGB(8, 8, 9) },
	},
	ESCAPE = {
		Ambient = Color3.fromRGB(16, 12, 12),
		OutdoorAmbient = Color3.fromRGB(18, 14, 14),
		ExposureCompensation = -1.7,
		cc = { Brightness = lifted(0.12), Contrast = 0.12, Saturation = -0.6, TintColor = Color3.fromRGB(255, 222, 216) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(32, 22, 22), Decay = Color3.fromRGB(12, 8, 8) },
	},
	RESULTS = {
		Ambient = Color3.fromRGB(26, 26, 30),
		OutdoorAmbient = Color3.fromRGB(36, 38, 46),
		ExposureCompensation = 0.3,
		cc = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.6, TintColor = Color3.fromRGB(240, 242, 255) },
		atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0, Color = Color3.fromRGB(80, 84, 96), Decay = Color3.fromRGB(46, 48, 56) },
	},
}

-- Old names still used by callers and admin tools.
LightingService.Aliases = { POWERED = "NORMAL", DARK = "EMERGENCY" }

-- Global Lighting properties, the single source (default.project.json carries
-- the same values so edit mode in Studio matches play).
LightingService.Base = {
	GlobalShadows = true,
	Brightness = 0.6,
	ClockTime = 0.4,
	GeographicLatitude = 30,
	-- the night sky barely lights the inside: no fill where no fixture reaches
	EnvironmentDiffuseScale = 0.08,
	EnvironmentSpecularScale = 0.5,
	-- soft shadow edges, like the pools themselves
	ShadowSoftness = 0.65,
	FogEnd = 100000,
}

local current = "LOBBY"
local blackoutToken = 0
local blackoutLevel = 0
local blackoutEndsAt = 0

function LightingService:ApplyPreset(name: string, duration: number?)
	name = self.Aliases[name] or name
	local preset = self.Presets[name]
	if not preset then
		return
	end
	current = name
	local info = TweenInfo.new(duration or 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, {
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		ExposureCompensation = preset.ExposureCompensation,
	}):Play()
	if cc and cc.Parent then
		TweenService:Create(cc, info, preset.cc):Play()
	end
	if atmosphere and atmosphere.Parent then
		TweenService:Create(atmosphere, info, preset.atmosphere):Play()
	end
end

function LightingService:GetPreset(): string
	return current
end

-- The preset that matches the current power / blackout situation inside the building.
function LightingService:InteriorPreset(): string
	local powered = workspace:GetAttribute("Power") == true
	if powered and blackoutLevel >= 4 then
		return "BLACKOUT"
	end
	if workspace:GetAttribute("Escape") == true then
		return "ESCAPE"
	end
	if not powered then
		return "EMERGENCY"
	end
	return if blackoutLevel == 3 then "HEARTBEAT" elseif blackoutLevel == 2 then "BREATH" else "NORMAL"
end

function LightingService:SetPower(on: boolean, keepPreset: boolean?)
	workspace:SetAttribute("Power", on)
	if keepPreset then
		return
	end
	self:ApplyPreset(self:InteriorPreset(), 1.2)
end

function LightingService:IsPowered(): boolean
	return workspace:GetAttribute("Power") == true
end

-- Fixtures of the current map with where they are and how far they light,
-- collected once per map.
type FixtureSpot = { model: Model, pos: Vector3, reach: number }
local fixtureCache: { root: Instance?, list: { FixtureSpot } } = { root = nil, list = {} }

local function mapFixtures(map): { FixtureSpot }
	if fixtureCache.root == map.Root then
		return fixtureCache.list
	end
	local list = {}
	for _, room in map.Rooms do
		for _, m in room.fixtures or {} do
			local light = m:FindFirstChild("Light", true)
			local reach = if light and light:IsA("Light") then (light :: any).Range else 12
			table.insert(list, { model = m, pos = if light and light.Parent and light.Parent:IsA("BasePart") then light.Parent.Position else m:GetPivot().Position, reach = reach })
		end
	end
	fixtureCache.root = map.Root
	fixtureCache.list = list
	return list
end

local darkCache: { [string]: { t: number, dark: boolean } } = {}

--[[
	THE definition of "it is dark here", for every system that cares (The
	Observer's speed and blinks, what it takes to see it, the director's fear
	events). Inside the building it is what the players see: dark unless a
	fixture that is lit right now (LightingRules, the same rules the clients
	paint with) reaches this point with nothing in between. Outside the
	building, or without a position: no main power or a major blackout.
]]
function LightingService:IsDark(position: Vector3?): boolean
	local globalDark = blackoutLevel >= 3 or not self:IsPowered()
	local map = if position and Registry.MapService then Registry.MapService:GetMap() else nil
	if not position or not map or not map:isInsideBuilding(position) then
		return globalDark
	end
	local at = position :: Vector3
	local world = LightingRules.world(workspace)
	local key = string.format("%d,%d,%d|%s%d%d", at.X // 2, at.Y // 2, at.Z // 2, if world.power then "p" else "-", world.level, world.seed)
	local now = os.clock()
	local cached = darkCache[key]
	if cached and now - cached.t < 0.3 then
		return cached.dark
	end
	local litReach = GameConfig.Perception.LitFraction
	local dark = true
	for _, f in mapFixtures(map) do
		local d = (f.pos - at).Magnitude
		if d <= f.reach * litReach and f.model.Parent then
			local fixture = LightingRules.fixture(f.model)
			local lit, brightness = LightingRules.evaluate(fixture, world, now, { steady = true })
			-- a dimmed lamp (a deep blackout) lights a smaller pool: its reach
			-- shrinks with the square root of its share of the light, as the
			-- floor under it falls off
			local share = math.clamp(brightness / math.max(fixture.baseBrightness, 0.01), 0, 1)
			if lit and d <= f.reach * litReach * math.sqrt(share) and Registry.PlayerService:HasLineOfSight(f.pos, at, f.model) then
				dark = false
				break
			end
		end
	end
	if next(darkCache) and math.random() < 0.02 then
		-- forget stale entries now and then
		for k, v in darkCache do
			if now - v.t > 1 then
				darkCache[k] = nil
			end
		end
	end
	darkCache[key] = { t = now, dark = dark }
	return dark
end

-- Can light reach `point`? Always where it is not dark; in the dark only the
-- flashlights (anyone's beam, with line of sight) and glow sticks light it.
function LightingService:IsLit(point: Vector3): boolean
	if not self:IsDark(point) then
		return true
	end
	local F = GameConfig.Flashlight
	local cosBeam = math.cos(math.rad(F.Angle / 2 + 6))
	for _, p in Registry.PlayerService:GetAlive() do
		if Registry.InventoryService:IsLightOn(p) then
			local look = Registry.PlayerService:GetLook(p)
			if look then
				local delta = point - look.origin
				local dist = delta.Magnitude
				if dist < 2 or (dist <= F.Range and look.dir:Dot(delta / dist) >= cosBeam and Registry.PlayerService:HasLineOfSight(look.origin, point)) then
					return true
				end
			end
		end
	end
	for _, glow in Registry.EquipmentService:GetGlowLights() do
		if (glow.position - point).Magnitude <= glow.range then
			return true
		end
	end
	return false
end

function LightingService:GetBlackout(): number
	return blackoutLevel
end

function LightingService:BlackoutRemaining(): number
	return math.max(0, blackoutEndsAt - os.clock())
end

local function setBlackout(level: number, zone: string?)
	blackoutLevel = level
	workspace:SetAttribute("Blackout", level)
	workspace:SetAttribute("BlackoutZone", zone or "")
	workspace:SetAttribute("BlackoutSeed", math.random(1, 100000))
	LightingService.BlackoutChanged:Fire(level)
end

--[[
	Blackout 4: a blackout has phases the clients paint (LightingRules):
	ONSET (the light fails, one of four ways), HOLD (the level), RESTORE (the
	lamps come back one by one). The game's own reading (IsDark, the
	Observer, the director) follows the level alone: it changes at the start
	of the ONSET and at the start of the RESTORE, never in between.
]]
-- how long the light takes to fail, and to come back, per level
LightingService.OnsetTime = { 1.6, 2.4, 2.8, 3.4 }
LightingService.RestoreTime = { 2.5, 4, 5, 6 }

local lastStyle = 0
local phaseToken = 0

local function setPhase(phase: string?, span: number?, extra: { [string]: any }?)
	phaseToken += 1
	workspace:SetAttribute("BlackoutPhase", phase)
	workspace:SetAttribute("BlackoutPhaseAt", if phase then LightingRules.serverNow(workspace) else nil)
	workspace:SetAttribute("BlackoutSpan", span)
	workspace:SetAttribute("BlackoutStyle", extra and extra.style or nil)
	workspace:SetAttribute("BlackoutFrom", extra and extra.from or nil)
	-- a timed phase ends on its own, unless something replaced it meanwhile
	if phase and span and span > 0 then
		local token = phaseToken
		task.delay(span, function()
			if token ~= phaseToken then
				return
			end
			if phase == "ONSET" and blackoutLevel > 0 then
				setPhase("HOLD")
			elseif phase == "RESTORE" then
				setPhase(nil)
			end
		end)
	end
end

function LightingService:GetBlackoutPhase(): string?
	local phase = workspace:GetAttribute("BlackoutPhase")
	return if type(phase) == "string" then phase else nil
end

--[[
	Starts a temporary blackout. Returns false if a stronger one is running.
	opts.zone: floor id for level 2 (defaults to a random floor)
	opts.silent: no announcement sounds
	opts.instant: no onset (the level at once)
	opts.style: force an onset style (1-4; tests, admin)
]]
function LightingService:Blackout(level: number, duration: number, opts: { [string]: any }?)
	opts = opts or {}
	level = math.clamp(math.floor(level), 1, 4)
	if blackoutLevel > level then
		return false
	end
	blackoutToken += 1
	local token = blackoutToken
	local zone = opts.zone
	if level == 2 and not zone then
		local floors = { "G", "U", "B" }
		zone = floors[math.random(1, #floors)]
	end
	-- never the same onset twice in a row
	local style = opts.style
	if type(style) ~= "number" then
		style = math.random(1, #LightingRules.ONSET_STYLES - 1)
		if style >= lastStyle then
			style += 1
		end
	end
	style = math.clamp(math.floor(style), 1, #LightingRules.ONSET_STYLES)
	lastStyle = style
	local onset = if opts.instant or not self:IsPowered() then 0 else self.OnsetTime[level]
	if onset > 0 then
		setPhase("ONSET", onset, { style = style })
	else
		setPhase("HOLD")
	end
	setBlackout(level, zone)
	blackoutEndsAt = os.clock() + duration
	if not opts.silent and Registry.AudioService then
		Registry.AudioService:Play2DAll(if level >= 3 then "PowerDown" else "ElectricSurge", { volume = 0.6 + level * 0.1 })
	end
	Net.fireAll("Director", { cue = "blackout", level = level, duration = duration, zone = zone, onset = onset, style = style })
	-- the grade follows the light down over the onset
	self:ApplyPreset(self:InteriorPreset(), math.max(if level >= 3 then 0.6 else 1.5, onset))
	task.delay(duration, function()
		if token ~= blackoutToken then
			return
		end
		LightingService:EndBlackout()
	end)
	return true
end

--[[
	Ends the blackout. The level is gone at once (the game reads full light);
	with power the lamps then come back one by one (RESTORE).
	silent: no sound. instant: no restore either (a round ending, a reset).
]]
function LightingService:EndBlackout(silent: boolean?, instant: boolean?)
	if blackoutLevel == 0 then
		if instant and workspace:GetAttribute("BlackoutPhase") ~= nil then
			setPhase(nil)
		end
		return
	end
	blackoutToken += 1
	local was = blackoutLevel
	local restore = if instant or not self:IsPowered() then 0 else self.RestoreTime[was] or 3
	if restore > 0 then
		setPhase("RESTORE", restore, { from = was })
	else
		setPhase(nil)
	end
	setBlackout(0, nil)
	blackoutEndsAt = 0
	if not silent and Registry.AudioService and was >= 2 and self:IsPowered() then
		Registry.AudioService:Play2DAll("PowerOn", { volume = 0.35 })
	end
	Net.fireAll("Director", { cue = "blackoutEnd", level = was, restore = restore })
	if Registry.RoundService and Registry.RoundService:IsRunning() then
		self:ApplyPreset(self:InteriorPreset(), math.max(2, restore))
	end
end

function LightingService:Init()
	-- Technology (Future) can't be written by scripts; it is set in default.project.json.
	-- full specular: the 2022 materials (tile, marble, metal, wet floors) catch
	-- the lights; crisp contact shadows read as real space
	for prop, value in self.Base do
		local ok, err = pcall(function()
			(Lighting :: any)[prop] = value
		end)
		if not ok then
			warn("[LightingService] " .. prop .. ": " .. tostring(err))
		end
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Offset = 0.1
	atmosphere.Parent = Lighting
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Parent = Lighting
	bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	-- film halation: a soft glow round the lamps' tubes and bulbs (the
	-- emissive parts), never over the lit walls
	bloom.Intensity = 0.5
	bloom.Size = 30
	bloom.Threshold = 1.25
	bloom.Parent = Lighting
	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "DOF"
	dof.FarIntensity = 0.1
	dof.FocusDistance = 40
	dof.InFocusRadius = 70
	dof.NearIntensity = 0
	dof.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.StarCount = 1600
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 11
	sky.SunAngularSize = 0
	sky.Parent = Lighting
	workspace:SetAttribute("Power", false)
	setBlackout(0, nil)
	setPhase(nil)
	self:ApplyPreset("LOBBY", 0)
end

return LightingService
