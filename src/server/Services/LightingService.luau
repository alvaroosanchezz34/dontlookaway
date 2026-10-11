--[[
	LightingService
	Global, cinematic lighting. Uses Future lighting with restrained post effects:
	soft bloom only on emissive sources, a cold desaturated grade, atmosphere for
	depth. Per-player effects (fear tint, blur, blink, dark adaptation) are handled
	on clients.

	Darkness is dark. With power, only the fixtures light anything: each throws a
	pool that fades out and the space between them is dark. Without power
	(EMERGENCY) and in a total blackout (BLACKOUT) there is no ambient fill and
	no light follows the camera: what you see without the flashlight is what
	glows (tubes still on, exit signs, beacon domes) and the silhouettes right
	next to you. Low light means you need the flashlight. The only lift is the
	player's brightness setting (AccessibilityController), kept to a small range
	so it helps a dark screen without erasing the dark. Fully black happens
	once, on purpose and only on one screen: the jumpscare (ScareController)
	blacks out every light around the lens for about a second.

	Power
	  workspace "Power" (bool)        MAIN circuit fixtures need it
	Blackouts (temporary, layered on top of Power)
	  workspace "Blackout" (0-4)      0 none
	                                  1 failing: a share of lights flicker, buzz
	                                  2 partial: one floor goes dark, emergency on
	                                  3 major: most of the building dark, red emergency
	                                  4 total: everything but emergency beacons and
	                                    exit signs, short and special
	  workspace "BlackoutZone"        floor id for level 2
	  workspace "BlackoutSeed"        which fixtures fail (clients hash it)
	Fixtures, exit signs and beacons read these attributes client-side.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
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
LightingService.Presets = {
	LOBBY = {
		Ambient = Color3.fromRGB(34, 32, 30),
		OutdoorAmbient = Color3.fromRGB(40, 42, 48),
		ExposureCompensation = 0.2,
		cc = { Brightness = 0.02, Contrast = 0.12, Saturation = -0.22, TintColor = Color3.fromRGB(255, 244, 232) },
		atmosphere = { Density = 0.3, Haze = 1.3, Glare = 0, Color = Color3.fromRGB(70, 76, 86), Decay = Color3.fromRGB(40, 42, 48) },
	},
	OUTSIDE = {
		Ambient = Color3.fromRGB(30, 33, 40),
		OutdoorAmbient = Color3.fromRGB(46, 52, 64),
		ExposureCompensation = 0.35,
		cc = { Brightness = 0.0, Contrast = 0.14, Saturation = -0.3, TintColor = Color3.fromRGB(226, 234, 255) },
		atmosphere = { Density = 0.4, Haze = 2.1, Glare = 0, Color = Color3.fromRGB(70, 78, 92), Decay = Color3.fromRGB(36, 40, 50) },
	},
	-- main power lost: emergency lamps, exit signs, the flashlight
	EMERGENCY = {
		Ambient = Color3.fromRGB(5, 5, 7),
		OutdoorAmbient = Color3.fromRGB(7, 8, 10),
		ExposureCompensation = 0,
		cc = { Brightness = 0, Contrast = 0.2, Saturation = -0.5, TintColor = Color3.fromRGB(226, 234, 250) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(14, 15, 18), Decay = Color3.fromRGB(6, 6, 8) },
	},
	-- NORMAL: the building with power and no event. The reference for play: a
	-- dark corridor where only the fixtures light anything. Each one throws a
	-- pool that fades out (VisualStandards.Fixtures) and the stretch between
	-- pools is dark; the glowing tubes read from afar. A minimal ambient, a cold
	-- near-monochrome grade, no haze to grey the distance. The contrast is kept
	-- moderate: a hard one crushes the penumbra of every pool to black.
	NORMAL = {
		Ambient = Color3.fromRGB(7, 7, 8),
		OutdoorAmbient = Color3.fromRGB(9, 10, 12),
		ExposureCompensation = 0,
		cc = { Brightness = 0.0, Contrast = 0.16, Saturation = -0.6, TintColor = Color3.fromRGB(228, 236, 250) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(26, 28, 32), Decay = Color3.fromRGB(10, 10, 12) },
	},
	-- scripted moments (cinematics, the Observer's reveal): the same building,
	-- harder and colder, for a few seconds at a time. NORMAL's light, a
	-- harsher, colder grade
	CINEMATIC = {
		Ambient = Color3.fromRGB(6, 6, 8),
		OutdoorAmbient = Color3.fromRGB(8, 9, 12),
		ExposureCompensation = 0,
		cc = { Brightness = 0, Contrast = 0.22, Saturation = -0.68, TintColor = Color3.fromRGB(220, 230, 252) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(24, 27, 33), Decay = Color3.fromRGB(9, 10, 12) },
	},
	-- a total blackout: the darkest the game gets. Only what glows and the
	-- silhouettes right next to you; everything else needs the flashlight
	BLACKOUT = {
		Ambient = Color3.fromRGB(3, 3, 4),
		OutdoorAmbient = Color3.fromRGB(4, 4, 6),
		ExposureCompensation = -0.05,
		cc = { Brightness = 0, Contrast = 0.22, Saturation = -0.5, TintColor = Color3.fromRGB(236, 228, 232) },
		atmosphere = { Density = 0.2, Haze = 0.1, Glare = 0, Color = Color3.fromRGB(8, 8, 10), Decay = Color3.fromRGB(4, 4, 5) },
	},
	-- the way out: NORMAL's light turned red and harder (the fixtures pulse,
	-- the alarm beacons turn), not a brighter or hazier building
	ESCAPE = {
		Ambient = Color3.fromRGB(8, 5, 5),
		OutdoorAmbient = Color3.fromRGB(10, 7, 7),
		ExposureCompensation = 0,
		cc = { Brightness = 0, Contrast = 0.2, Saturation = -0.45, TintColor = Color3.fromRGB(255, 222, 216) },
		atmosphere = { Density = 0.2, Haze = 0.2, Glare = 0, Color = Color3.fromRGB(32, 22, 22), Decay = Color3.fromRGB(12, 8, 8) },
	},
	RESULTS = {
		Ambient = Color3.fromRGB(26, 26, 30),
		OutdoorAmbient = Color3.fromRGB(36, 38, 46),
		ExposureCompensation = 0.3,
		cc = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.35, TintColor = Color3.fromRGB(240, 242, 255) },
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
	ShadowSoftness = 0.5,
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
	if blackoutLevel >= 4 then
		return "BLACKOUT"
	end
	if workspace:GetAttribute("Escape") == true then
		return "ESCAPE"
	end
	if workspace:GetAttribute("Power") ~= true or blackoutLevel >= 3 then
		return "EMERGENCY"
	end
	return "NORMAL"
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

-- THE definition of "it is dark here", for every system that cares (The
-- Observer's speed and blinks, what it takes to see it, the director's fear
-- events): no main power, a major or total blackout, or a partial one on this
-- position's floor. Without a position: dark for the whole building.
function LightingService:IsDark(position: Vector3?): boolean
	if blackoutLevel >= 3 or not self:IsPowered() then
		return true
	end
	if blackoutLevel == 2 and position and Registry.MapService then
		local map = Registry.MapService:GetMap()
		local floor = map and map:floorAtY(position.Y)
		return floor ~= nil and floor.id == workspace:GetAttribute("BlackoutZone")
	end
	return false
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
	Starts a temporary blackout. Returns false if a stronger one is running.
	opts.zone: floor id for level 2 (defaults to a random floor)
	opts.silent: no announcement sounds
]]
function LightingService:Blackout(level: number, duration: number, opts: { [string]: any }?): boolean
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
	setBlackout(level, zone)
	blackoutEndsAt = os.clock() + duration
	if not opts.silent and Registry.AudioService then
		Registry.AudioService:Play2DAll(if level >= 3 then "PowerDown" else "ElectricSurge", { volume = 0.6 + level * 0.1 })
	end
	Net.fireAll("Director", { cue = "blackout", level = level, duration = duration, zone = zone })
	self:ApplyPreset(self:InteriorPreset(), if level >= 3 then 0.6 else 1.5)
	task.delay(duration, function()
		if token ~= blackoutToken then
			return
		end
		LightingService:EndBlackout()
	end)
	return true
end

function LightingService:EndBlackout(silent: boolean?)
	if blackoutLevel == 0 then
		return
	end
	blackoutToken += 1
	local was = blackoutLevel
	setBlackout(0, nil)
	blackoutEndsAt = 0
	if not silent and Registry.AudioService and was >= 2 and self:IsPowered() then
		Registry.AudioService:Play2DAll("PowerOn", { volume = 0.35 })
	end
	Net.fireAll("Director", { cue = "blackoutEnd", level = was })
	if Registry.RoundService and Registry.RoundService:IsRunning() then
		self:ApplyPreset(self:InteriorPreset(), 2)
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
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.5
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
	self:ApplyPreset("LOBBY", 0)
end

return LightingService
