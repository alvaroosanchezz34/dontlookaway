--[[
	LightingService
	Global, cinematic lighting. Uses Future lighting with restrained post effects:
	soft bloom only on emissive sources, a cold desaturated grade, atmosphere for
	depth. Per-player effects (fear tint, blur, blink, dark adaptation) are handled
	on clients.

	Darkness is never black. Every preset keeps a faint, cold ambient floor (the
	moon through dirty windows, light bleeding from the street), so walls, doors,
	floors and teammates always read as silhouettes. The flashlight is the main
	source of detail, never the only source of orientation.

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
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local LightingService = {}

LightingService.BlackoutChanged = Signal.new() -- (level)

local cc: ColorCorrectionEffect
local bloom: BloomEffect
local atmosphere: Atmosphere
local dof: DepthOfFieldEffect

-- Ambient values are the "never blind" floor. They are deliberately cold and
-- low-saturation so darkness still reads as darkness, just not as a black screen.
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
	-- main power lost: moonlight, emergency lighting, flashlight
	DARK = {
		Ambient = Color3.fromRGB(24, 26, 33),
		OutdoorAmbient = Color3.fromRGB(34, 39, 50),
		ExposureCompensation = 0.4,
		cc = { Brightness = 0.01, Contrast = 0.14, Saturation = -0.3, TintColor = Color3.fromRGB(228, 236, 248) },
		atmosphere = { Density = 0.36, Haze = 1.7, Glare = 0, Color = Color3.fromRGB(58, 63, 74), Decay = Color3.fromRGB(28, 31, 38) },
	},
	-- the building at work: warm practical lights, still a little dirty
	POWERED = {
		Ambient = Color3.fromRGB(30, 29, 28),
		OutdoorAmbient = Color3.fromRGB(30, 33, 40),
		ExposureCompensation = 0.12,
		cc = { Brightness = 0.0, Contrast = 0.13, Saturation = -0.2, TintColor = Color3.fromRGB(246, 242, 234) },
		atmosphere = { Density = 0.33, Haze = 1.5, Glare = 0, Color = Color3.fromRGB(66, 66, 70), Decay = Color3.fromRGB(32, 32, 36) },
	},
	-- a total blackout: the darkest the game ever gets, still never black
	BLACKOUT = {
		Ambient = Color3.fromRGB(19, 20, 27),
		OutdoorAmbient = Color3.fromRGB(28, 31, 42),
		ExposureCompensation = 0.45,
		cc = { Brightness = 0.0, Contrast = 0.18, Saturation = -0.38, TintColor = Color3.fromRGB(236, 226, 228) },
		atmosphere = { Density = 0.4, Haze = 2, Glare = 0, Color = Color3.fromRGB(52, 50, 58), Decay = Color3.fromRGB(26, 24, 30) },
	},
	ESCAPE = {
		Ambient = Color3.fromRGB(28, 20, 20),
		OutdoorAmbient = Color3.fromRGB(36, 26, 26),
		ExposureCompensation = 0.3,
		cc = { Brightness = -0.01, Contrast = 0.22, Saturation = -0.35, TintColor = Color3.fromRGB(255, 226, 222) },
		atmosphere = { Density = 0.44, Haze = 2.3, Glare = 0, Color = Color3.fromRGB(70, 56, 56), Decay = Color3.fromRGB(36, 26, 26) },
	},
	RESULTS = {
		Ambient = Color3.fromRGB(26, 26, 30),
		OutdoorAmbient = Color3.fromRGB(36, 38, 46),
		ExposureCompensation = 0.3,
		cc = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.35, TintColor = Color3.fromRGB(240, 242, 255) },
		atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0, Color = Color3.fromRGB(80, 84, 96), Decay = Color3.fromRGB(46, 48, 56) },
	},
}

local current = "LOBBY"
local blackoutToken = 0
local blackoutLevel = 0
local blackoutEndsAt = 0

function LightingService:ApplyPreset(name: string, duration: number?)
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
		return "DARK"
	end
	return "POWERED"
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
	local props = {
		GlobalShadows = true,
		Brightness = 0.6,
		ClockTime = 0.4,
		GeographicLatitude = 30,
		EnvironmentDiffuseScale = 0.22,
		EnvironmentSpecularScale = 0.45,
		ShadowSoftness = 0.3,
		FogEnd = 100000,
	}
	for prop, value in props do
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
