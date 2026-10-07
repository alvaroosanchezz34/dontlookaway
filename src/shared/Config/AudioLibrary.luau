--[[
	AudioLibrary
	Central catalog of every sound the game plays.

	All audio ships with the Roblox client (rbxasset://sounds/...), so the game has
	no third-party or copyrighted audio. The horror identity comes from sound design:
	playback speed, pitch shifting, reverb, echo, distortion and equalisation turn a
	small palette of neutral source samples into drones, impacts, breaths and stingers.

	To upgrade a sound with licensed Creator Store audio, replace its `id` only.

	Fields:
		id        asset id
		group     SoundGroup name (see AudioGroups)
		volume    base volume
		speed     playback speed, number or {min, max} for variation
		looped    boolean
		effects   list of { class, props } SoundEffects applied to the Sound
		min, max  RollOffMinDistance / RollOffMaxDistance for 3D sounds
]]

local S = {
	plastic = "rbxasset://sounds/action_footsteps_plastic.mp3",
	swim = "rbxasset://sounds/action_swim.mp3",
	jump = "rbxasset://sounds/action_jump.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	falling = "rbxasset://sounds/action_falling.mp3",
	getup = "rbxasset://sounds/action_get_up.mp3",
	water = "rbxasset://sounds/impact_water.mp3",
	groan = "rbxasset://sounds/uuhhh.mp3",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/clickfast.wav",
	switch = "rbxasset://sounds/switch.wav",
	button = "rbxasset://sounds/button.wav",
	-- breathy, airy source (swoosh.wav is not shipped with current clients)
	swoosh = "rbxasset://sounds/action_swim.mp3",
	hit = "rbxasset://sounds/hit.wav",
	glass = "rbxasset://sounds/glassbreak.wav",
	snap = "rbxasset://sounds/snap.wav",
	splat = "rbxasset://sounds/splat.wav",
	flash = "rbxasset://sounds/flashbulb.wav",
	collide = "rbxasset://sounds/collide.wav",
	rocket = "rbxasset://sounds/Rocket shot.wav",
	launch = "rbxasset://sounds/Launching rocket.wav",
}

local function reverb(decay, wet)
	return { "ReverbSoundEffect", { DecayTime = decay or 2.4, WetLevel = wet or -2, DryLevel = -3, Density = 1, Diffusion = 1 } }
end

local function echo(delay, feedback, wet)
	return { "EchoSoundEffect", { Delay = delay or 0.35, Feedback = feedback or 0.45, WetLevel = wet or -8, DryLevel = 0 } }
end

local function lowpass(high, mid)
	return { "EqualizerSoundEffect", { HighGain = high or -30, MidGain = mid or -8, LowGain = 4 } }
end

local function distort(level)
	return { "DistortionSoundEffect", { Level = level or 0.55 } }
end

local function pitch(octave)
	return { "PitchShiftSoundEffect", { Octave = octave or 0.5 } }
end

local function tremolo(freq, depth)
	return { "TremoloSoundEffect", { Frequency = freq or 6, Depth = depth or 0.6, Duty = 0.5 } }
end

local function chorus()
	return { "ChorusSoundEffect", { Depth = 0.35, Mix = 0.6, Rate = 0.6 } }
end

local AudioLibrary = {}

AudioLibrary.Groups = { "Ambient", "Footsteps", "Player", "Monster", "Anomaly", "UI", "Interaction", "Music" }

AudioLibrary.Sounds = {
	-- AMBIENT ------------------------------------------------------------------
	AmbientDrone = { id = S.swim, group = "Ambient", volume = 0.55, speed = 0.18, looped = true, effects = { lowpass(-40, -12), reverb(6, 0) } },
	AmbientAir = { id = S.swoosh, group = "Ambient", volume = 0.18, speed = 0.12, looped = true, effects = { lowpass(-25, -6), reverb(4, -4), tremolo(0.2, 0.5) } },
	AmbientHum = { id = S.ping, group = "Ambient", volume = 0.12, speed = 0.05, looped = true, effects = { lowpass(-30, -2), tremolo(8, 0.25) } },
	AmbientRain = { id = S.swim, group = "Ambient", volume = 0.35, speed = 0.55, looped = true, effects = { lowpass(-14, -4), chorus() } },
	DistantPipe = { id = S.collide, group = "Ambient", volume = 0.5, speed = { 0.18, 0.28 }, effects = { reverb(5, 0), echo(0.5, 0.5, -6), lowpass(-18, -2) }, min = 10, max = 140 },
	DistantKnock = { id = S.hit, group = "Ambient", volume = 0.5, speed = { 0.35, 0.45 }, effects = { reverb(4, -1), lowpass(-16, -4) }, min = 10, max = 120 },
	DistantMetal = { id = S.rocket, group = "Ambient", volume = 0.22, speed = { 0.12, 0.2 }, effects = { reverb(7, 0), lowpass(-22, -6) }, min = 20, max = 180 },
	DistantGroan = { id = S.groan, group = "Ambient", volume = 0.18, speed = { 0.32, 0.4 }, effects = { reverb(6, 0), lowpass(-26, -10), echo(0.6, 0.4, -10) }, min = 20, max = 160 },
	WoodCreak = { id = S.getup, group = "Ambient", volume = 0.45, speed = { 0.28, 0.38 }, effects = { reverb(3, -2), lowpass(-10, -2) }, min = 8, max = 90 },
	Drip = { id = S.water, group = "Ambient", volume = 0.25, speed = { 1.6, 2.2 }, effects = { reverb(3, -2), echo(0.25, 0.3, -12) }, min = 4, max = 45 },
	SteamHiss = { id = S.swoosh, group = "Ambient", volume = 0.25, speed = 0.65, looped = true, effects = { lowpass(-6, 2) }, min = 6, max = 50 },
	ElectricBuzz = { id = S.ping, group = "Ambient", volume = 0.18, speed = 0.09, looped = true, effects = { distort(0.4), tremolo(12, 0.4), lowpass(-12, -2) }, min = 4, max = 32 },
	LightFlicker = { id = S.click, group = "Ambient", volume = 0.35, speed = { 0.55, 0.8 }, effects = { distort(0.3) }, min = 6, max = 50 },
	BulbPop = { id = S.glass, group = "Ambient", volume = 0.55, speed = { 1.4, 1.7 }, effects = { reverb(2, -4) }, min = 8, max = 80 },
	Wind = { id = S.swoosh, group = "Ambient", volume = 0.25, speed = 0.08, looped = true, effects = { reverb(5, -2), tremolo(0.15, 0.7) }, min = 10, max = 80 },
	ServerFans = { id = S.swim, group = "Ambient", volume = 0.3, speed = 0.9, looped = true, effects = { lowpass(-18, -6) }, min = 6, max = 40 },
	Static = { id = S.swim, group = "Ambient", volume = 0.25, speed = 2.6, looped = true, effects = { distort(0.8), lowpass(4, 2) }, min = 4, max = 30 },
	ClockTick = { id = S.click, group = "Ambient", volume = 0.18, speed = 1.6, min = 3, max = 18 },
	BoilerRumble = { id = S.swim, group = "Ambient", volume = 0.45, speed = 0.25, looped = true, effects = { lowpass(-35, -8), distort(0.25) }, min = 10, max = 70 },
	Fridge = { id = S.ping, group = "Ambient", volume = 0.1, speed = 0.04, looped = true, effects = { lowpass(-30, -6) }, min = 4, max = 24 },
	Ventilation = { id = S.swim, group = "Ambient", volume = 0.22, speed = 0.42, looped = true, effects = { lowpass(-22, -6), tremolo(0.3, 0.25) }, min = 6, max = 40 },
	ElevatorGroan = { id = S.getup, group = "Ambient", volume = 0.35, speed = { 0.12, 0.16 }, effects = { reverb(7, 0), lowpass(-18, -4), echo(0.5, 0.4, -10) }, min = 20, max = 160 },
	BuildingSettle = { id = S.collide, group = "Ambient", volume = 0.35, speed = { 0.12, 0.18 }, effects = { reverb(6, 0), lowpass(-24, -6) }, min = 20, max = 180 },
	DistantRadio = { id = S.swim, group = "Ambient", volume = 0.18, speed = 2.3, effects = { distort(0.7), tremolo(5, 0.9), lowpass(-6, -2), reverb(3, -4) }, min = 6, max = 50 },
	DistantFootsteps = { id = S.plastic, group = "Ambient", volume = 0.35, speed = { 0.6, 0.7 }, effects = { reverb(5, -1), lowpass(-20, -6) }, min = 15, max = 110 },
	EmergencyAlarm = { id = S.ping, group = "Ambient", volume = 0.16, speed = 0.58, looped = true, effects = { tremolo(1.2, 1), reverb(4, -2), lowpass(-8, -2) }, min = 10, max = 120 },
	PowerDown = { id = S.launch, group = "Interaction", volume = 0.75, speed = 0.09, effects = { reverb(7, 0), lowpass(-14, -2), pitch(0.5) } },
	ElectricSurge = { id = S.ping, group = "Interaction", volume = 0.5, speed = 0.12, effects = { distort(0.7), tremolo(18, 0.9), lowpass(-6, 0) } },
	Sparks = { id = S.snap, group = "Ambient", volume = 0.45, speed = { 1.3, 1.7 }, effects = { distort(0.3) }, min = 6, max = 60 },

	-- FOOTSTEPS ----------------------------------------------------------------
	StepConcrete = { id = S.plastic, group = "Footsteps", volume = 0.45, speed = { 0.82, 0.92 }, effects = { lowpass(-10, -2) }, min = 5, max = 70 },
	StepTile = { id = S.plastic, group = "Footsteps", volume = 0.5, speed = { 1.05, 1.18 }, effects = { reverb(1.5, -8) }, min = 5, max = 70 },
	StepWood = { id = S.plastic, group = "Footsteps", volume = 0.5, speed = { 0.68, 0.76 }, effects = { lowpass(-6, 2) }, min = 5, max = 70 },
	StepMetal = { id = S.plastic, group = "Footsteps", volume = 0.5, speed = { 1.3, 1.45 }, effects = { reverb(1.2, -6), chorus() }, min = 5, max = 80 },
	StepCarpet = { id = S.plastic, group = "Footsteps", volume = 0.25, speed = { 0.6, 0.66 }, effects = { lowpass(-24, -8) }, min = 3, max = 40 },
	StepWater = { id = S.water, group = "Footsteps", volume = 0.35, speed = { 1.3, 1.6 }, min = 5, max = 60 },
	StepLand = { id = S.land, group = "Footsteps", volume = 0.45, speed = 0.8, min = 5, max = 60 },

	-- PLAYER -------------------------------------------------------------------
	Breath = { id = S.swoosh, group = "Player", volume = 0.25, speed = { 0.32, 0.36 }, effects = { lowpass(-12, -2) } },
	BreathHeavy = { id = S.swoosh, group = "Player", volume = 0.45, speed = { 0.38, 0.44 }, effects = { lowpass(-8, 0) } },
	Heartbeat = { id = S.hit, group = "Player", volume = 0.65, speed = 0.33, effects = { lowpass(-40, -14) } },
	HeartbeatFast = { id = S.hit, group = "Player", volume = 0.75, speed = 0.4, effects = { lowpass(-40, -12) } },
	LowBattery = { id = S.ping, group = "Player", volume = 0.25, speed = 0.9, effects = { lowpass(-10, -2) } },
	FlashlightWarm = { id = S.ping, group = "Player", volume = 0.08, speed = 0.2, effects = { distort(0.4), lowpass(-16, -4) } },
	Equip = { id = S.switch, group = "Player", volume = 0.45, speed = 0.75, effects = { reverb(1, -10) } },
	DeviceBeep = { id = S.ping, group = "Player", volume = 0.3, speed = 1.6, effects = { lowpass(-4, 0) }, min = 4, max = 30 },
	DeviceTick = { id = S.click, group = "Player", volume = 0.35, speed = { 1.9, 2.2 }, min = 4, max = 26 },
	MotionAlert = { id = S.ping, group = "Player", volume = 0.45, speed = 1.25, effects = { echo(0.1, 0.4, -6) }, min = 6, max = 40 },
	CameraShutter = { id = S.flash, group = "Player", volume = 0.5, speed = 1.3, min = 4, max = 30 },
	CameraWind = { id = S.click, group = "Player", volume = 0.3, speed = 0.5, min = 3, max = 20 },
	RadioClick = { id = S.switch, group = "Player", volume = 0.35, speed = 1.6 },
	RadioStatic = { id = S.swim, group = "Player", volume = 0.25, speed = 2.6, effects = { distort(0.85), lowpass(2, 2) } },
	ThermalHum = { id = S.ping, group = "Player", volume = 0.08, speed = 0.12, looped = true, effects = { tremolo(3, 0.4), lowpass(-16, -2) } },
	FlashlightOn = { id = S.switch, group = "Player", volume = 0.5, speed = 1.15 },
	FlashlightOff = { id = S.switch, group = "Player", volume = 0.45, speed = 0.9 },
	FlashlightDead = { id = S.click, group = "Player", volume = 0.5, speed = 0.45 },
	Blink = { id = S.swoosh, group = "Player", volume = 0.18, speed = 1.8, effects = { lowpass(-20, -6) } },
	Pickup = { id = S.button, group = "Interaction", volume = 0.5, speed = { 0.85, 0.95 } },
	Drop = { id = S.collide, group = "Interaction", volume = 0.4, speed = 1.2 },

	-- MONSTER ------------------------------------------------------------------
	ObserverBreath = { id = S.groan, group = "Monster", volume = 0.55, speed = 0.22, looped = true, effects = { lowpass(-18, -4), reverb(3, -2), tremolo(0.5, 0.6) }, min = 6, max = 55 },
	ObserverStep = { id = S.collide, group = "Monster", volume = 0.6, speed = { 0.32, 0.4 }, effects = { lowpass(-26, -4), reverb(2.5, -4) }, min = 8, max = 90 },
	ObserverAppear = { id = S.glass, group = "Monster", volume = 0.65, speed = 0.18, effects = { reverb(7, 0), pitch(0.5), lowpass(-14, -2) }, min = 15, max = 200 },
	ObserverVanish = { id = S.swoosh, group = "Monster", volume = 0.5, speed = 0.22, effects = { reverb(5, 0), pitch(0.6) }, min = 10, max = 150 },
	ObserverSting = { id = S.launch, group = "Monster", volume = 0.9, speed = 0.32, effects = { distort(0.6), reverb(4, -1), pitch(0.7) } },
	ObserverScreech = { id = S.groan, group = "Monster", volume = 0.9, speed = 0.75, effects = { distort(0.75), pitch(1.6), reverb(3, -2), chorus() }, min = 15, max = 220 },
	ObserverTwitch = { id = S.snap, group = "Monster", volume = 0.6, speed = { 0.45, 0.6 }, effects = { reverb(2, -4) }, min = 6, max = 60 },
	ObserverHunt = { id = S.rocket, group = "Monster", volume = 0.85, speed = 0.11, effects = { distort(0.5), reverb(7, 0), lowpass(-10, 0) } },
	ObserverCrack = { id = S.snap, group = "Monster", volume = 0.8, speed = { 0.3, 0.38 }, effects = { reverb(2, -6), lowpass(-6, 2) }, min = 4, max = 40 },
	ObserverInhale = { id = S.groan, group = "Monster", volume = 0.7, speed = 0.18, effects = { lowpass(-10, 0), reverb(2, -6), pitch(0.6) }, min = 3, max = 30 },
	ObserverRush = { id = S.swim, group = "Monster", volume = 0.9, speed = 0.55, effects = { distort(0.6), pitch(0.7), reverb(2, -4) } },
	ObserverImpact = { id = S.launch, group = "Monster", volume = 1, speed = 0.3, effects = { distort(0.9), reverb(3, -2), lowpass(-4, 4) } },
	ObserverWhisperName = { id = S.groan, group = "Monster", volume = 0.5, speed = 1.1, effects = { chorus(), reverb(5, 0), tremolo(11, 0.7), lowpass(-10, -2) } },
	TinnitusRing = { id = S.ping, group = "Player", volume = 0.22, speed = 2.4, effects = { reverb(6, -2) } },

	-- ANOMALY / IDENTITY ---------------------------------------------------------
	RealityShift = { id = S.swoosh, group = "Anomaly", volume = 0.5, speed = 0.28, effects = { pitch(0.5), reverb(5, -1), echo(0.4, 0.5, -6) } },
	RealitySnap = { id = S.flash, group = "Anomaly", volume = 0.7, speed = 0.62, effects = { reverb(3.5, -2), echo(0.12, 0.3, -6), chorus() } },
	ReportWrong = { id = S.ping, group = "Anomaly", volume = 0.35, speed = 0.32, effects = { distort(0.5), lowpass(-14, -4) } },
	JournalEntry = { id = S.ping, group = "UI", volume = 0.45, speed = 0.74, effects = { reverb(4, -3), echo(0.3, 0.4, -10) } },
	ExitUnlocked = { id = S.rocket, group = "Anomaly", volume = 0.8, speed = 0.2, effects = { reverb(8, 0), pitch(0.5), chorus() } },
	EscapeSuccess = { id = S.ping, group = "Anomaly", volume = 0.6, speed = 0.5, effects = { reverb(9, 0), echo(0.5, 0.6, -4), chorus() } },
	DeathHit = { id = S.launch, group = "Monster", volume = 1, speed = 0.22, effects = { distort(0.85), pitch(0.6), reverb(5, 0) } },
	DeathFall = { id = S.falling, group = "Player", volume = 0.5, speed = 0.6, effects = { reverb(3, -2) } },
	PhoneRing = { id = S.ping, group = "Anomaly", volume = 0.7, speed = 1.85, looped = true, effects = { tremolo(22, 1), distort(0.2), reverb(2, -6) }, min = 6, max = 80 },
	Whisper = { id = S.swoosh, group = "Anomaly", volume = 0.35, speed = 0.9, effects = { chorus(), reverb(4, -2), lowpass(-4, -2), tremolo(9, 0.8) }, min = 3, max = 25 },
	KnockDoor = { id = S.hit, group = "Anomaly", volume = 0.8, speed = { 0.5, 0.58 }, effects = { reverb(2, -4), lowpass(-12, 0) }, min = 6, max = 70 },
	FootstepsBehind = { id = S.plastic, group = "Anomaly", volume = 0.55, speed = 0.78, effects = { reverb(2, -6), lowpass(-8, -2) }, min = 3, max = 40 },
	BreathingCloset = { id = S.swoosh, group = "Anomaly", volume = 0.35, speed = 0.3, looped = true, effects = { tremolo(0.45, 0.85), lowpass(-14, -2) }, min = 3, max = 26 },
	Thud = { id = S.collide, group = "Anomaly", volume = 0.8, speed = 0.45, effects = { reverb(2.5, -2), lowpass(-14, 0) }, min = 6, max = 80 },
	DoorSlam = { id = S.collide, group = "Interaction", volume = 1, speed = 0.36, effects = { reverb(3.5, -1), distort(0.2) }, min = 10, max = 160 },
	JumpSting = { id = S.launch, group = "Anomaly", volume = 0.75, speed = 0.45, effects = { distort(0.45), reverb(3, -2) } },
	MusicBox = { id = S.ping, group = "Anomaly", volume = 0.4, speed = 1.4, effects = { reverb(4, -3), echo(0.2, 0.3, -12) }, min = 4, max = 40 },
	WaterRush = { id = S.swim, group = "Anomaly", volume = 0.45, speed = 0.4, looped = true, effects = { lowpass(-10, -2) }, min = 6, max = 50 },
	Falsetto = { id = S.groan, group = "Anomaly", volume = 0.4, speed = 1.35, effects = { reverb(4, -1), chorus(), lowpass(-8, -4) }, min = 6, max = 60 },
	StretchGroan = { id = S.getup, group = "Anomaly", volume = 0.5, speed = 0.15, effects = { reverb(6, 0), pitch(0.5) }, min = 10, max = 120 },

	-- INTERACTION ----------------------------------------------------------------
	DoorOpen = { id = S.getup, group = "Interaction", volume = 0.45, speed = { 0.55, 0.65 }, effects = { reverb(2, -6) }, min = 6, max = 60 },
	DoorClose = { id = S.collide, group = "Interaction", volume = 0.55, speed = { 0.62, 0.7 }, effects = { reverb(2, -6) }, min = 6, max = 70 },
	DoorLocked = { id = S.click, group = "Interaction", volume = 0.55, speed = { 0.4, 0.46 }, effects = { distort(0.2) }, min = 4, max = 40 },
	DoorUnlock = { id = S.switch, group = "Interaction", volume = 0.55, speed = 0.6, min = 4, max = 40 },
	FuseInsert = { id = S.switch, group = "Interaction", volume = 0.7, speed = 0.45, effects = { reverb(1.5, -6) }, min = 5, max = 50 },
	BreakerFlip = { id = S.switch, group = "Interaction", volume = 0.8, speed = 0.35, effects = { reverb(2, -4) }, min = 5, max = 60 },
	PowerOn = { id = S.launch, group = "Interaction", volume = 0.6, speed = 0.15, effects = { reverb(6, 0), lowpass(-16, -4) } },
	PowerHum = { id = S.ping, group = "Interaction", volume = 0.18, speed = 0.06, looped = true, effects = { distort(0.25), tremolo(6, 0.3) }, min = 6, max = 60 },
	KeypadBeep = { id = S.ping, group = "Interaction", volume = 0.35, speed = 1.3, min = 3, max = 30 },
	KeypadError = { id = S.ping, group = "Interaction", volume = 0.45, speed = 0.5, effects = { distort(0.5) }, min = 3, max = 30 },
	KeypadOk = { id = S.ping, group = "Interaction", volume = 0.45, speed = 1.7, effects = { echo(0.08, 0.3, -6) }, min = 3, max = 30 },
	DialTurn = { id = S.click, group = "Interaction", volume = 0.5, speed = 0.75, min = 3, max = 30 },
	LockRelease = { id = S.rocket, group = "Interaction", volume = 0.5, speed = 0.4, effects = { reverb(3, -2) }, min = 8, max = 120 },
	TapeInsert = { id = S.click, group = "Interaction", volume = 0.6, speed = 0.55, min = 3, max = 30 },
	TapeHiss = { id = S.swim, group = "Interaction", volume = 0.25, speed = 2.2, looped = true, effects = { distort(0.4), lowpass(-6, 0) }, min = 4, max = 35 },
	BoardsBreak = { id = S.hit, group = "Interaction", volume = 0.9, speed = 0.3, effects = { reverb(3, -2), distort(0.3) }, min = 8, max = 90 },
	ShutterOpen = { id = S.rocket, group = "Interaction", volume = 0.7, speed = 0.17, effects = { reverb(4, -2), distort(0.2) }, min = 15, max = 200 },
	PaperRustle = { id = S.swoosh, group = "Interaction", volume = 0.3, speed = 1.4, effects = { lowpass(4, 2) } },
	Place = { id = S.collide, group = "Interaction", volume = 0.45, speed = 0.9, min = 4, max = 40 },
	WardBreak = { id = S.glass, group = "Interaction", volume = 0.9, speed = 0.6, effects = { reverb(6, 0), chorus() }, min = 10, max = 120 },

	-- UI -------------------------------------------------------------------------
	UIHover = { id = S.click, group = "UI", volume = 0.12, speed = 1.6 },
	UIClick = { id = S.click, group = "UI", volume = 0.3, speed = 1.1 },
	UIBack = { id = S.click, group = "UI", volume = 0.3, speed = 0.8 },
	UIOpen = { id = S.swoosh, group = "UI", volume = 0.2, speed = 1.4, effects = { lowpass(-6, -2) } },
	UIError = { id = S.ping, group = "UI", volume = 0.3, speed = 0.45, effects = { distort(0.3) } },
	UIPurchase = { id = S.ping, group = "UI", volume = 0.4, speed = 1.2, effects = { reverb(2, -4) } },
	UIEquip = { id = S.switch, group = "UI", volume = 0.35, speed = 1.05 },
	UICoin = { id = S.ping, group = "UI", volume = 0.25, speed = 1.9, effects = { echo(0.06, 0.25, -10) } },
	UITab = { id = S.click, group = "UI", volume = 0.22, speed = 1.3 },
	ChallengeDone = { id = S.ping, group = "UI", volume = 0.45, speed = 1.1, effects = { reverb(3, -3), chorus() } },
	EscapeDoor = { id = S.rocket, group = "Interaction", volume = 0.8, speed = 0.14, effects = { reverb(6, 0), lowpass(-12, -2) } },
	ObjectiveUpdate = { id = S.ping, group = "UI", volume = 0.35, speed = 0.62, effects = { reverb(3, -4) } },
	Achievement = { id = S.ping, group = "UI", volume = 0.45, speed = 0.92, effects = { reverb(4, -3), chorus() } },
	LevelUp = { id = S.ping, group = "UI", volume = 0.5, speed = 1.05, effects = { reverb(5, -2), echo(0.18, 0.4, -6) } },
	PingAnomaly = { id = S.ping, group = "UI", volume = 0.45, speed = 0.85, effects = { echo(0.15, 0.35, -8) } },
	PingComeHere = { id = S.ping, group = "UI", volume = 0.45, speed = 1.15 },
	PingDanger = { id = S.ping, group = "UI", volume = 0.5, speed = 0.55, effects = { distort(0.3) } },
	PingDoor = { id = S.ping, group = "UI", volume = 0.4, speed = 1 },
	PingItem = { id = S.ping, group = "UI", volume = 0.4, speed = 1.35 },
	Countdown = { id = S.click, group = "UI", volume = 0.4, speed = 0.7 },
	TitleHit = { id = S.launch, group = "UI", volume = 0.5, speed = 0.18, effects = { reverb(8, 0), lowpass(-20, -6) } },
	Typewriter = { id = S.click, group = "UI", volume = 0.12, speed = { 1.4, 1.8 } },

	-- MUSIC (generative instruments) ------------------------------------------------
	MusicBell = { id = S.ping, group = "Music", volume = 0.18, speed = 1, effects = { reverb(9, 0), echo(0.6, 0.5, -10), lowpass(-14, -2) } },
	MusicLow = { id = S.ping, group = "Music", volume = 0.22, speed = 0.25, effects = { reverb(9, 0), lowpass(-30, -6) } },
	MusicPulse = { id = S.hit, group = "Music", volume = 0.45, speed = 0.3, effects = { lowpass(-34, -8), reverb(3, -6) } },
	MusicPad = { id = S.swim, group = "Music", volume = 0.25, speed = 0.3, looped = true, effects = { lowpass(-30, -6), chorus(), reverb(8, 0) } },
	MusicChasePad = { id = S.rocket, group = "Music", volume = 0.25, speed = 0.13, looped = true, effects = { distort(0.4), lowpass(-14, -2), tremolo(4, 0.6) } },
	MusicString = { id = S.groan, group = "Music", volume = 0.14, speed = 0.5, effects = { reverb(8, 0), chorus(), lowpass(-16, -4) } },
}

return AudioLibrary
