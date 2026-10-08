--[[
	LightFX
	Cinematic lighting, local and fully restorable:

	  * the world's exposure, ambient and fog (Lighting / Atmosphere), changed
	    through Runtime.setProp so cleanup puts back the game's values
	  * the building's real fixtures flicker through the game's own
	    LightController:FlickerNear (read-only adapter; the game decides how a
	    fixture flickers, Marketing only asks)
	  * key lights: local spot / point lights placed for a shot (rim light on
	    a figure, an emergency strobe, a light leaking under a door)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Runtime = require(script.Parent.Parent.Runtime)

local LightFX = {}

local keys: { [string]: { part: BasePart, light: Light, base: number } } = {}
local fill: { part: BasePart, light: PointLight }? = nil

-- The game's LightController, if the game's client is running (adapter).
local function gameLights(): any
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local client = scripts and scripts:FindFirstChild("Client")
	local registryModule = client and client:FindFirstChild("Registry")
	if not registryModule then
		return nil
	end
	local ok, registry = pcall(require, registryModule)
	return if ok and type(registry) == "table" then registry.LightController else nil
end

local lookExposure: number? = nil

function LightFX.reset()
	table.clear(keys)
	fill = nil
	lookExposure = nil
end

-- The exposure looks are offset from: the scene's exposure (after the fill
-- light) the first time a look is used, so consecutive looks never stack.
function LightFX.lookBase(): number
	if lookExposure == nil then
		lookExposure = Lighting.ExposureCompensation
	end
	return lookExposure :: number
end

-- Flicker the real fixtures around a point.
function LightFX.flickerFixtures(position: Vector3, radius: number?, duration: number?, limit: number?): boolean
	local lc = gameLights()
	if lc and lc.FlickerNear then
		local ok, at = pcall(lc.FlickerNear, lc, position, radius or 20, duration or 1, limit or 2)
		return ok and at ~= nil
	end
	return false
end

-- Lighting properties as a table, for blending.
function LightFX.read(): { [string]: any }
	return {
		ExposureCompensation = Lighting.ExposureCompensation,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
	}
end

function LightFX.write(values: { [string]: any })
	for k, v in values do
		Runtime.setProp(Lighting, k, v)
	end
end

function LightFX.blend(from, to, a: number)
	local out = {}
	for k, v in to do
		local f = from[k]
		if typeof(v) == "number" and typeof(f) == "number" then
			out[k] = f + (v - f) * a
		elseif typeof(v) == "Color3" and typeof(f) == "Color3" then
			out[k] = f:Lerp(v, a)
		else
			out[k] = v
		end
	end
	LightFX.write(out)
end

-- The game's own values (before the scene touched them).
function LightFX.original(): { [string]: any }
	return {
		ExposureCompensation = Runtime.original(Lighting, "ExposureCompensation"),
		Ambient = Runtime.original(Lighting, "Ambient"),
		OutdoorAmbient = Runtime.original(Lighting, "OutdoorAmbient"),
		Brightness = Runtime.original(Lighting, "Brightness"),
	}
end

-- Fog through the Atmosphere if there is one (the game uses one), else Lighting fog.
function LightFX.fogTarget(): (Instance, { [string]: any })
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		return atmosphere, { Density = atmosphere.Density, Haze = atmosphere.Haze, Color = atmosphere.Color }
	end
	return Lighting, { FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, FogColor = Lighting.FogColor }
end

function LightFX.fogValues(density: number, color: Color3?): (Instance, { [string]: any }, { [string]: any })
	local target, current = LightFX.fogTarget()
	local want
	if target:IsA("Atmosphere") then
		want = { Density = math.clamp(density, 0, 1), Haze = math.clamp(density * 4, 0, 10), Color = color or current.Color }
	else
		want = { FogStart = 0, FogEnd = math.max(8, 400 * (1 - density)), FogColor = color or current.FogColor }
	end
	return target, current, want
end

------------------------------------------------------------------------------------
-- Fill: so the picture is never just black. Lifts exposure and ambient, and
-- carries a soft shadowless light with the camera (like a film crew's fill).
-- level 0 = off .. 4 = bright.
------------------------------------------------------------------------------------

function LightFX.fill(level: number)
	if level <= 0 then
		return
	end
	local lift = math.clamp(level, 0, 4)
	local exposure = Lighting.ExposureCompensation
	Runtime.setProp(Lighting, "ExposureCompensation", exposure + 0.35 * lift)
	local floor = 14 + 14 * lift
	local function lifted(c: Color3): Color3
		return Color3.fromRGB(math.max(c.R * 255, floor), math.max(c.G * 255, floor), math.max(c.B * 255, floor + 6))
	end
	Runtime.setProp(Lighting, "Ambient", lifted(Lighting.Ambient))
	Runtime.setProp(Lighting, "OutdoorAmbient", lifted(Lighting.OutdoorAmbient))
	local part = Instance.new("Part")
	part.Name = "FillLight"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	local light = Instance.new("PointLight")
	light.Range = 34 + 6 * lift
	light.Brightness = 0.35 * lift
	light.Color = Color3.fromRGB(214, 220, 236)
	light.Shadows = false
	light.Parent = part
	part.Parent = Runtime.folder()
	fill = { part = part, light = light }
end

-- Follow the camera (called every frame while a scene plays).
function LightFX.updateFill(cameraCf: CFrame)
	local f = fill
	if f and f.part.Parent then
		f.part.CFrame = cameraCf * CFrame.new(0, 1.5, 2.5)
	end
end

------------------------------------------------------------------------------------
-- Key lights
------------------------------------------------------------------------------------

function LightFX.key(name: string, cf: CFrame, opts: { [string]: any }?): Light
	opts = opts or {}
	local existing = keys[name]
	if existing and existing.part.Parent then
		existing.part.CFrame = cf
		return existing.light
	end
	local part = Instance.new("Part")
	part.Name = "Key_" .. name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cf
	local kind = opts.kind or "spot"
	local light: Light
	if kind == "point" then
		local l = Instance.new("PointLight")
		l.Range = opts.range or 14
		light = l
	else
		local l = Instance.new("SpotLight")
		l.Range = opts.range or 24
		l.Angle = opts.angle or 45
		l.Face = Enum.NormalId.Front
		light = l
	end
	light.Color = opts.color or Color3.fromRGB(210, 220, 255)
	light.Brightness = opts.brightness or 2
	light.Shadows = opts.shadows ~= false
	light.Parent = part
	part.Parent = Runtime.folder()
	keys[name] = { part = part, light = light, base = light.Brightness }
	return light
end

-- Treat a light the scene built (a set's lamp) as a key light, so
-- FlickerLights / KeyLightOff can drive it by name.
function LightFX.adopt(name: string, part: BasePart, light: Light)
	keys[name] = { part = part, light = light, base = light.Brightness }
end

-- Dim a key light to `ratio` (0..1 of its base); a glowing bulb part and its
-- light shaft dim with it.
function LightFX.setKeyRatio(name: string, ratio: number)
	local k = keys[name]
	if not k or not k.part.Parent then
		return
	end
	k.light.Brightness = k.base * ratio
	local p = k.part
	if p.Material == Enum.Material.Neon then
		local base = p:GetAttribute("MarketingBaseColor")
		if typeof(base) ~= "Color3" then
			base = p.Color
			p:SetAttribute("MarketingBaseColor", base)
		end
		p.Color = Color3.fromRGB(20, 20, 20):Lerp(base :: Color3, math.clamp(ratio, 0, 1))
	end
	for _, d in p:GetChildren() do
		if d:IsA("Beam") then
			d.Enabled = ratio > 0.05
		elseif d:IsA("PointLight") and d ~= k.light then
			local b = d:GetAttribute("MarketingBase")
			if typeof(b) ~= "number" then
				b = d.Brightness
				d:SetAttribute("MarketingBase", b)
			end
			d.Brightness = (b :: number) * ratio
		end
	end
end

function LightFX.getKey(name: string)
	local k = keys[name]
	if k and k.part.Parent then
		return k
	end
	return nil
end

function LightFX.removeKey(name: string)
	local k = keys[name]
	if k then
		k.part:Destroy()
		keys[name] = nil
	end
end

return LightFX
