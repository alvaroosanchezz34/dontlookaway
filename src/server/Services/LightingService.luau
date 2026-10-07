--[[
	LightingService
	Global, cinematic lighting. Uses Future lighting with restrained post effects:
	soft bloom only on emissive sources, a cold desaturated grade, atmosphere for
	depth. Per-player effects (fear tint, blur, blink) are handled on clients.

	The building's power is a workspace attribute ("Power"); light fixtures read it
	client-side together with their own Mode / Tint / Override attributes.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LightingService = {}

local cc: ColorCorrectionEffect
local bloom: BloomEffect
local atmosphere: Atmosphere
local dof: DepthOfFieldEffect

LightingService.Presets = {
	LOBBY = {
		Ambient = Color3.fromRGB(14, 12, 12),
		OutdoorAmbient = Color3.fromRGB(20, 22, 26),
		ExposureCompensation = 0.1,
		cc = { Brightness = 0.02, Contrast = 0.12, Saturation = -0.25, TintColor = Color3.fromRGB(255, 244, 232) },
		atmosphere = { Density = 0.32, Haze = 1.4, Glare = 0, Color = Color3.fromRGB(70, 76, 86), Decay = Color3.fromRGB(40, 42, 48) },
	},
	OUTSIDE = {
		Ambient = Color3.fromRGB(10, 11, 14),
		OutdoorAmbient = Color3.fromRGB(26, 30, 38),
		ExposureCompensation = 0.2,
		cc = { Brightness = 0.0, Contrast = 0.16, Saturation = -0.3, TintColor = Color3.fromRGB(226, 234, 255) },
		atmosphere = { Density = 0.42, Haze = 2.2, Glare = 0, Color = Color3.fromRGB(70, 78, 92), Decay = Color3.fromRGB(36, 40, 50) },
	},
	DARK = {
		Ambient = Color3.fromRGB(5, 5, 6),
		OutdoorAmbient = Color3.fromRGB(14, 16, 20),
		ExposureCompensation = 0.15,
		cc = { Brightness = 0.0, Contrast = 0.18, Saturation = -0.32, TintColor = Color3.fromRGB(232, 238, 246) },
		atmosphere = { Density = 0.38, Haze = 1.8, Glare = 0, Color = Color3.fromRGB(60, 64, 72), Decay = Color3.fromRGB(30, 32, 38) },
	},
	POWERED = {
		Ambient = Color3.fromRGB(9, 9, 10),
		OutdoorAmbient = Color3.fromRGB(14, 16, 20),
		ExposureCompensation = 0.05,
		cc = { Brightness = 0.0, Contrast = 0.15, Saturation = -0.24, TintColor = Color3.fromRGB(238, 242, 240) },
		atmosphere = { Density = 0.36, Haze = 1.6, Glare = 0, Color = Color3.fromRGB(64, 66, 70), Decay = Color3.fromRGB(32, 32, 36) },
	},
	ESCAPE = {
		Ambient = Color3.fromRGB(10, 6, 6),
		OutdoorAmbient = Color3.fromRGB(18, 12, 12),
		ExposureCompensation = 0.1,
		cc = { Brightness = -0.02, Contrast = 0.24, Saturation = -0.4, TintColor = Color3.fromRGB(255, 226, 222) },
		atmosphere = { Density = 0.45, Haze = 2.4, Glare = 0, Color = Color3.fromRGB(70, 56, 56), Decay = Color3.fromRGB(36, 26, 26) },
	},
	RESULTS = {
		Ambient = Color3.fromRGB(16, 16, 18),
		OutdoorAmbient = Color3.fromRGB(26, 28, 34),
		ExposureCompensation = 0.25,
		cc = { Brightness = 0.02, Contrast = 0.1, Saturation = -0.35, TintColor = Color3.fromRGB(240, 242, 255) },
		atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0, Color = Color3.fromRGB(80, 84, 96), Decay = Color3.fromRGB(46, 48, 56) },
	},
}

local current = "LOBBY"

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
	TweenService:Create(cc, info, preset.cc):Play()
	TweenService:Create(atmosphere, info, preset.atmosphere):Play()
end

function LightingService:GetPreset(): string
	return current
end

function LightingService:SetPower(on: boolean, keepPreset: boolean?)
	workspace:SetAttribute("Power", on)
	if keepPreset then
		return
	end
	if on then
		self:ApplyPreset("POWERED", 1.2)
	else
		self:ApplyPreset("DARK", 1.2)
	end
end

function LightingService:Init()
	Lighting.Technology = Enum.Technology.Future
	Lighting.GlobalShadows = true
	Lighting.Brightness = 0.35
	Lighting.ClockTime = 0.4
	Lighting.GeographicLatitude = 30
	Lighting.EnvironmentDiffuseScale = 0.12
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.ShadowSoftness = 0.25
	Lighting.FogEnd = 100000
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
	bloom.Intensity = 0.35
	bloom.Size = 22
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "DOF"
	dof.FarIntensity = 0.12
	dof.FocusDistance = 40
	dof.InFocusRadius = 60
	dof.NearIntensity = 0
	dof.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.StarCount = 1200
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 9
	sky.SunAngularSize = 0
	sky.Parent = Lighting
	workspace:SetAttribute("Power", false)
	self:ApplyPreset("LOBBY", 0)
end

return LightingService
