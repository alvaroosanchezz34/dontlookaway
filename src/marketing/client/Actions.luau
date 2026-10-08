--[[
	Actions
	The event vocabulary of a scene timeline. An event is a table:

	  { at = 3.0, action = "FlickerLights", at_ = ..., duration = 1.2, ... }

	Every action is a function (tl, event). Anything that lasts uses
	tl:span(...) so it follows the scene clock (pause, slow motion). Add your
	own with Actions.register("Name", function(tl, e) ... end).

	CAMERA    SetCamera Cut TeleportCamera MoveCamera SetFOV ShakeCamera Jolt
	          TrackTarget StopTracking
	LIGHT     SetLighting FadeLights RestoreLights Blackout FlickerLights
	          KeyLight KeyLightOff Fog Grade Vignette Blur
	SOUND     PlaySound PlayAmbience StopSound Silence Unsilence MuteGame
	OBJECTS   UseDoor OpenDoor CloseDoor SpawnEffect DestroyEffect MoveObject
	          FadeObject
	THE EYE   ShowEye HideEye BlinkEye EyeLook SetEye
	SCREEN    Glitch CCTV ShowText HideText SurfaceText WriteText Backdrop
	          FadeToBlack FadeFromBlack CutToBlack
	OTHER     Wait RunCallback
]]

local CameraRig = require(script.Parent.Cameras.CameraRig)
local Presets = require(script.Parent.Cameras.Presets)
local Screen = require(script.Parent.Effects.Screen)
local LightFX = require(script.Parent.Effects.LightFX)
local Doors = require(script.Parent.Effects.Doors)
local Eye = require(script.Parent.Effects.Eye)
local Figures = require(script.Parent.Effects.Figures)
local Audio = require(script.Parent.Audio.MarketingAudio)
local Titles = require(script.Parent.Text.Titles)
local Scratch = require(script.Parent.Text.Scratch)
local Runtime = require(script.Parent.Runtime)

local Actions = {}

local registry: { [string]: (any, { [string]: any }) -> () } = {}
local random = Random.new()

function Actions.register(name: string, fn: (any, { [string]: any }) -> ())
	registry[name] = fn
end

function Actions.has(name: string): boolean
	return registry[name] ~= nil
end

function Actions.names(): { string }
	local list = {}
	for k in registry do
		table.insert(list, k)
	end
	table.sort(list)
	return list
end

function Actions.run(tl: any, e: { [string]: any })
	local fn = registry[e.action]
	if not fn then
		warn("[Marketing] unknown action " .. tostring(e.action))
		return
	end
	fn(tl, e)
end

-- "figure:name", "eye", a Vector3, a BasePart / Model.
local function resolveTarget(target: any): any
	if type(target) == "string" then
		if target == "eye" then
			local s = Eye.get()
			return s and s.part
		end
		local name = string.match(target, "^figure:(.+)$")
		if name then
			local f = Figures.get(name)
			if f then
				local head = f.model:FindFirstChild("Head", true)
				return head or f.model
			end
		end
		return nil
	end
	return target
end

------------------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------------------

local function setCamera(_tl, e)
	CameraRig.cut(e.cframe, e.preset, e.fov)
	CameraRig.setMoveAlpha(0)
	if e.track then
		CameraRig.track(resolveTarget(e.track), e.smooth)
	else
		CameraRig.track(nil)
	end
end
Actions.register("SetCamera", setCamera)
Actions.register("Cut", setCamera)
Actions.register("TeleportCamera", setCamera)

Actions.register("MoveCamera", function(tl, e)
	local from = CameraRig.getBase()
	local to: CFrame = e.to
	local fromFov = CameraRig.getFov()
	local toFov = e.fov
	tl:span(e.duration or 2, e.ease or "inOutSine", function(a)
		CameraRig.setBase(from:Lerp(to, a))
		CameraRig.setMoveAlpha(a)
		if toFov then
			CameraRig.setFov(fromFov + (toFov - fromFov) * a)
		end
	end, e.at, "camera.move")
end)

Actions.register("SetFOV", function(tl, e)
	local from = CameraRig.getFov()
	tl:span(e.duration or 0, e.ease or "inOutSine", function(a)
		CameraRig.setFov(from + (e.fov - from) * a)
	end, e.at, "camera.fov")
end)

Actions.register("ShakeCamera", function(_tl, e)
	CameraRig.shake(e.amount or 0.4, e.decay)
end)

Actions.register("Jolt", function(_tl, e)
	CameraRig.jolt(e.amount or 0.6)
end)

Actions.register("TrackTarget", function(_tl, e)
	CameraRig.track(resolveTarget(e.target), e.smooth)
end)

Actions.register("StopTracking", function()
	CameraRig.track(nil)
end)

------------------------------------------------------------------------------------
-- Light
------------------------------------------------------------------------------------

local function lightingTarget(e): { [string]: any }
	local want = {}
	if e.exposure ~= nil then
		want.ExposureCompensation = e.exposure
	end
	if e.ambient ~= nil then
		want.Ambient = e.ambient
		want.OutdoorAmbient = e.ambient
	end
	if e.brightness ~= nil then
		want.Brightness = e.brightness
	end
	return want
end

local function lightTo(tl, want, duration, ease, at)
	local from = LightFX.read()
	tl:span(duration or 0, ease or "inOutSine", function(a)
		LightFX.blend(from, want, a)
	end, at, "light.world")
end

Actions.register("SetLighting", function(tl, e)
	lightTo(tl, lightingTarget(e), e.duration, e.ease, e.at)
end)
Actions.register("FadeLights", function(tl, e)
	lightTo(tl, lightingTarget(e), e.duration or 1.5, e.ease, e.at)
end)

local function gradeTo(tl, target, duration, at)
	local to = if type(target) == "string" then Screen.Grades[target] else target
	if not to then
		return
	end
	local from = Screen.gradeValues()
	tl:span(duration or 0, "inOutSine", function(a)
		Screen.blendGrade(from, to, a)
	end, at, "light.grade")
end

Actions.register("Grade", function(tl, e)
	gradeTo(tl, e.grade or e.preset or "neutral", e.duration, e.at)
end)

Actions.register("RestoreLights", function(tl, e)
	lightTo(tl, LightFX.original(), e.duration or 1, e.ease, e.at)
	if e.grade ~= false then
		gradeTo(tl, e.grade or "neutral", e.duration or 1, e.at)
	end
end)

Actions.register("Blackout", function(tl, e)
	local d = e.duration or 0.08
	lightTo(tl, { ExposureCompensation = -4 }, d, "outQuad", e.at)
	gradeTo(tl, "blackout", d, e.at)
	if e.sound ~= false then
		Audio.play(tl, e.sound or "PowerDown", { volume = e.volume or 0.8 })
	end
end)

Actions.register("FlickerLights", function(tl, e)
	local duration = e.duration or 1.2
	if typeof(e.position) == "Vector3" then
		LightFX.flickerFixtures(e.position, e.radius or 22, duration, e.limit or 2)
	end
	-- key lights and the world exposure stutter with them
	local key = e.key and LightFX.getKey(e.key)
	local fromExposure = LightFX.read().ExposureCompensation
	local depth = e.depth or 1.2
	tl:span(duration, "linear", function(a)
		local on = a >= 1 or random:NextNumber() > (e.chance or 0.45)
		if key then
			key.light.Brightness = if on then key.base else key.base * random:NextNumber(0, 0.15)
		end
		if e.world ~= false then
			LightFX.write({ ExposureCompensation = if on then fromExposure else fromExposure - depth })
		end
	end, e.at, "light.flicker." .. tostring(e.key))
	if e.sound ~= false then
		Audio.play(tl, e.sound or "LightFlicker", { at = e.position, volume = e.volume or 0.9 })
	end
end)

Actions.register("KeyLight", function(tl, e)
	local light = LightFX.key(e.name or "key", e.cframe, e)
	local k = LightFX.getKey(e.name or "key")
	if k and (e.fadeIn or 0) > 0 then
		local target = k.base
		light.Brightness = 0
		tl:span(e.fadeIn, "inOutSine", function(a)
			light.Brightness = target * a
		end, e.at, "light.key." .. (e.name or "key"))
	end
end)

Actions.register("KeyLightOff", function(tl, e)
	local name = e.name or "key"
	local k = LightFX.getKey(name)
	if not k then
		return
	end
	local from = k.light.Brightness
	tl:span(e.duration or 0, "inOutSine", function(a)
		k.light.Brightness = from * (1 - a)
		if a >= 1 then
			LightFX.removeKey(name)
		end
	end, e.at, "light.key." .. name)
end)

Actions.register("Fog", function(tl, e)
	local target, current, want = LightFX.fogValues(e.density or 0.4, e.color)
	tl:span(e.duration or 1.5, "inOutSine", function(a)
		for k, v in want do
			local f = current[k]
			local value = v
			if typeof(v) == "number" then
				value = f + (v - f) * a
			elseif typeof(v) == "Color3" then
				value = f:Lerp(v, a)
			end
			Runtime.setProp(target, k, value)
		end
	end, e.at, "light.fog")
end)

Actions.register("Vignette", function(_tl, e)
	Screen.setVignette(e.on ~= false)
end)

Actions.register("Blur", function(tl, e)
	local grade = Screen.getGrade()
	local camera = grade and grade.Parent
	local blur = camera and camera:FindFirstChild("MarketingBlur") :: BlurEffect?
	local from = if blur then blur.Size else 0
	tl:span(e.duration or 0, "inOutSine", function(a)
		Screen.setBlur(from + ((e.size or 0) - from) * a)
	end, e.at, "screen.blur")
end)

------------------------------------------------------------------------------------
-- Sound
------------------------------------------------------------------------------------

local function soundOpts(e)
	return {
		at = e.position,
		volume = e.volume,
		speed = e.speed,
		startTime = e.startTime,
		duration = e.duration,
		fadeIn = e.fadeIn,
		fadeOut = e.fadeOut,
		loop = e.loop,
		name = e.name,
	}
end

Actions.register("PlaySound", function(tl, e)
	Audio.play(tl, e.sound, soundOpts(e))
end)

Actions.register("PlayAmbience", function(tl, e)
	local o = soundOpts(e)
	o.loop = true
	o.fadeIn = e.fadeIn or 1.5
	o.name = e.name or "ambience"
	Audio.play(tl, e.sound or "AmbientDrone", o)
end)

Actions.register("StopSound", function(tl, e)
	Audio.stop(tl, e.name, e.fadeOut)
end)

-- The scene's own sound falls away (0 = total silence).
Actions.register("Silence", function(tl, e)
	Audio.duck(tl, e.level or 0, e.fade or 0.6)
end)

Actions.register("Unsilence", function(tl, e)
	Audio.duck(tl, 1, e.fade or 0.1)
end)

Actions.register("MuteGame", function(tl, e)
	Audio.muteGame(tl, e.fade or 0.5)
end)

------------------------------------------------------------------------------------
-- Objects
------------------------------------------------------------------------------------

-- Choose the scene's door: a real one (model) or a prop built at floorCf.
Actions.register("UseDoor", function(tl, e)
	local model = e.model
	if not Doors.valid(model) then
		model = Doors.prop(e.floorCf or CameraRig.getBase() * CFrame.new(0, -5.4, -10) * CFrame.Angles(0, math.pi, 0))
	end
	tl.data.door = model
	Doors.set(model, e.amount or 0)
end)

local function doorTo(tl, e, amount)
	local model = e.model or tl.data.door
	if not model then
		return
	end
	local from = Doors.amount(model)
	tl:span(e.duration or 0.8, e.ease or "inOutSine", function(a)
		Doors.set(model, from + (amount - from) * a)
	end, e.at, "door")
end

Actions.register("OpenDoor", function(tl, e)
	doorTo(tl, e, e.amount or 1)
end)

Actions.register("CloseDoor", function(tl, e)
	doorTo(tl, e, e.amount or 0)
end)

Actions.register("SpawnEffect", function(_tl, e)
	local name = e.name or e.kind or "effect"
	if e.kind == "person" then
		Figures.person(name, e.cframe, e)
	elseif e.kind == "entity" then
		Figures.entity(name, e.cframe, e)
	else
		warn("[Marketing] SpawnEffect: unknown kind " .. tostring(e.kind))
	end
end)

Actions.register("DestroyEffect", function(_tl, e)
	Figures.remove(e.name)
end)

Actions.register("MoveObject", function(tl, e)
	local f = Figures.get(e.name)
	if not f then
		return
	end
	local from = f.feet
	local to: CFrame = e.to
	tl:span(e.duration or 2, e.ease or "linear", function(a)
		Figures.place(e.name, from:Lerp(to, a))
		if a >= 1 then
			Figures.settle(e.name)
		end
	end, e.at, "object." .. e.name)
end)

Actions.register("FadeObject", function(tl, e)
	tl:span(e.duration or 0, "inOutSine", function(a)
		local from = e.from or 0
		Figures.setTransparency(e.name, from + ((e.to or 1) - from) * a)
	end, e.at, "object.fade." .. e.name)
end)

------------------------------------------------------------------------------------
-- The eye
------------------------------------------------------------------------------------

Actions.register("ShowEye", function(tl, e)
	if not Eye.exists() or e.recreate then
		Eye.create({ mode = e.mode, position = e.position, scale = e.scale, intensity = e.intensity, brightness = e.brightness, facing = e.facing, lightInfluence = e.lightInfluence, parent = Screen.fxLayer() })
	end
	if e.look then
		Eye.lookAt(e.look, e.drift)
	end
	Eye.setOpen(e.open or 1)
	local fade = e.fade or 0
	tl:span(fade, e.ease or "inOutSine", function(a)
		Eye.setOpacity(a * (e.opacity or 1))
	end, e.at, "eye.opacity")
end)

Actions.register("HideEye", function(tl, e)
	local s = Eye.get()
	if not s then
		return
	end
	local from = s.opacity
	tl:span(e.fade or 0, e.ease or "inOutSine", function(a)
		Eye.setOpacity(from * (1 - a))
		if a >= 1 and e.destroy ~= false then
			Eye.destroy()
		end
	end, e.at, "eye.opacity")
end)

Actions.register("BlinkEye", function(tl, e)
	local d = e.duration or 0.28
	tl:span(d, "linear", function(a)
		-- shut fast, open slower
		local open = if a < 0.35 then 1 - a / 0.35 else (a - 0.35) / 0.65
		Eye.setOpen(open)
	end, e.at, "eye.blink")
end)

Actions.register("EyeLook", function(_tl, e)
	Eye.lookAt(if e.target == "camera" then "camera" else resolveTarget(e.target) or e.target, e.drift)
end)

Actions.register("SetEye", function(tl, e)
	local s = Eye.get()
	if not s then
		return
	end
	local from = { intensity = s.intensity, scale = s.scale, pupil = s.pupilSize, open = s.open }
	if e.position then
		Eye.setPosition(e.position)
	end
	if e.opacity then
		Eye.setOpacity(e.opacity)
	end
	tl:span(e.duration or 0, e.ease or "inOutSine", function(a)
		if e.intensity then
			Eye.setIntensity(from.intensity + (e.intensity - from.intensity) * a)
		end
		if e.scale then
			Eye.setScale(from.scale + (e.scale - from.scale) * a)
		end
		if e.pupil then
			Eye.setPupil(from.pupil + (e.pupil - from.pupil) * a)
		end
		if e.open then
			Eye.setOpen(from.open + (e.open - from.open) * a)
		end
	end, e.at, "eye.set")
end)

------------------------------------------------------------------------------------
-- Screen
------------------------------------------------------------------------------------

Actions.register("Glitch", function(tl, e)
	local intensity = e.intensity or 0.6
	CameraRig.jolt(intensity * 0.5)
	local from = Screen.gradeValues()
	tl:span(e.duration or 0.25, "linear", function(a)
		if a >= 1 then
			Screen.clearGlitch()
			Screen.blendGrade(from, from, 1)
			return
		end
		Screen.glitchFrame(intensity)
		local flash = { Brightness = from.Brightness + random:NextNumber(-0.2, 0.25) * intensity, Contrast = from.Contrast + 0.3 * intensity, Saturation = from.Saturation, TintColor = from.TintColor }
		Screen.blendGrade(from, flash, 1)
	end, e.at, "screen.glitch")
	if e.sound ~= false then
		Audio.play(tl, e.sound or "RealitySnap", { volume = e.volume or 0.6 })
	end
end)

Actions.register("CCTV", function(tl, e)
	if e.on == false then
		Screen.setCCTV(false)
		tl.data.cctvClock = nil
		return
	end
	Screen.setCCTV(true, e.label or "CAM_04")
	-- the timestamp runs from a fixed night-time hour so every take matches
	tl.data.cctvStart = e.start or (3 * 3600 + 17 * 60 + 4)
	tl.data.cctvClock = tl.clock
	tl.data.cctvDate = e.date or "10-31-1987"
end)

Actions.register("ShowText", function(tl, e)
	Titles.show(tl, e.id or e.text, e.text, e)
end)

Actions.register("HideText", function(tl, e)
	if e.id then
		Titles.hide(tl, e.id, e.fadeOut or 0.3)
	else
		Titles.removeAll()
	end
end)

-- An image title: e.image (url) or e.imageKey = "title" (MarketingConfig.TitleImage);
-- falls back to text (e.fallbackText) when no image is configured.
Actions.register("ShowImage", function(tl, e)
	local url = e.image
	if not url and e.imageKey == "title" then
		local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Marketing"):WaitForChild("MarketingConfig"))
		local id = Config.TitleImage
		if type(id) == "number" and id > 0 then
			url = "rbxassetid://" .. string.format("%d", id)
		end
	end
	if url then
		Titles.image(tl, e.id or "image", { image = url, position = e.position, width = e.width, aspect = e.aspect, fadeIn = e.fadeIn, duration = e.duration, fadeOut = e.fadeOut, flicker = e.flicker })
	elseif e.fallbackText then
		Titles.show(tl, e.id or "image", e.fallbackText, { style = e.fallbackStyle or "title", position = e.position, size = e.size, fadeIn = e.fadeIn, duration = e.duration, fadeOut = e.fadeOut, tracking = e.tracking, color = e.color })
	end
end)

Actions.register("FilmGrain", function(_tl, e)
	Screen.setGrain(e.on ~= false, e.amount)
end)

-- Use a light the scene built as a named key (e.g. a set's lamp).
Actions.register("AdoptLight", function(_tl, e)
	if e.part and e.light then
		LightFX.adopt(e.name or "key", e.part, e.light)
	end
end)

-- Dim (or kill, ratio 0) a key light, its bulb and light shaft.
Actions.register("DimKey", function(tl, e)
	local name = e.name or "key"
	local k = LightFX.getKey(name)
	if not k then
		return
	end
	local from = k.light.Brightness / math.max(k.base, 1e-3)
	tl:span(e.duration or 0, e.ease or "inOutSine", function(a)
		LightFX.setKeyRatio(name, from + ((e.ratio or 0) - from) * a)
	end, e.at, "light.key." .. name)
end)

-- Words scratched into a surface, stroke by stroke (Text/Scratch.luau).
Actions.register("ScratchSurface", function(_tl, e)
	Scratch.surface(e.id or "wall", e.cframe, e.size or Vector2.new(4, 4), e)
end)

Actions.register("ScratchWrite", function(tl, e)
	local sound = e.sound
	if sound == nil then
		sound = "PaperRustle"
	end
	Scratch.write(tl, e.id or "wall", e.text or "", {
		line = e.line,
		height = e.height,
		x = e.x,
		top = e.top,
		center = e.center,
		strokeTime = e.strokeTime,
		onStroke = if sound
			then function()
				Audio.play(tl, sound, { at = e.position, volume = e.volume or 0.7, speed = (e.speed or 0.55) * random:NextNumber(0.9, 1.15) })
			end
			else nil,
	})
end)

Actions.register("SurfaceText", function(_tl, e)
	Titles.surface(e.id or "wall", e.cframe, e.size or Vector2.new(4, 2), e)
end)

Actions.register("WriteText", function(_tl, e)
	Titles.write(e.id or "wall", e.text or "")
end)

Actions.register("FadeToBlack", function(tl, e)
	local from = Screen.getFade()
	tl:span(e.duration or 1, e.ease or "inOutSine", function(a)
		Screen.setFade(from + (1 - from) * a)
	end, e.at, "screen.fade")
end)

Actions.register("FadeFromBlack", function(tl, e)
	local from = if e.from ~= nil then e.from else Screen.getFade()
	Screen.setFade(from)
	tl:span(e.duration or 1, e.ease or "inOutSine", function(a)
		Screen.setFade(from * (1 - a))
	end, e.at, "screen.fade")
end)

-- Black card under the eye / text, over the world (1 = black, 0 = gone).
Actions.register("Backdrop", function(tl, e)
	local from = Screen.getBackdrop()
	local to = if e.on == false then 0 else (e.alpha or 1)
	tl:span(e.duration or 0, "inOutSine", function(a)
		Screen.setBackdrop(from + (to - from) * a)
	end, e.at, "screen.backdrop")
end)

Actions.register("CutToBlack", function(tl, e)
	tl:span(0, "linear", function()
		Screen.setFade(1)
	end, e.at, "screen.fade")
	if e.sound then
		Audio.play(tl, e.sound, { volume = e.volume or 1 })
	end
end)

------------------------------------------------------------------------------------
-- Other
------------------------------------------------------------------------------------

Actions.register("Wait", function() end)

Actions.register("RunCallback", function(tl, e)
	if type(e.fn) == "function" then
		e.fn(tl, e)
	end
end)

-- Presets are visible to scene authors through Actions for convenience.
Actions.CameraPresets = Presets

return Actions
