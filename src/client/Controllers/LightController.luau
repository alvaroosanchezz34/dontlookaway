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

	Blackout levels
	  1 failing   a third of the lights stutter, everything a little dimmer
	  2 partial   one floor goes dark; emergency lighting there
	  3 major     most of the building dark; emergency turns red, beacons spin
	  4 total     everything off except some red emergency lamps, the beacons
	              and the battery-backed exit signs

	Never blind: on top of the fixtures, a soft "dark adaptation" light follows the
	camera. When the lights die it is darkest for a heartbeat, then your eyes
	adjust over a few seconds and walls, doors, floors and teammates come back as
	cold silhouettes. The flashlight remains the only way to see detail.

	Lights far from the camera are disabled locally (light LOD) so the building
	stays fast on phones and consoles; their glowing tubes still read from afar.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local LightController = {}

local LOD_DISTANCE = 95
local EMERGENCY_COLOR = Color3.fromRGB(255, 176, 120)
local ALARM_COLOR = Color3.fromRGB(255, 64, 52)
local DARK = Color3.fromRGB(38, 38, 36)
local ADAPT_COLOR = Color3.fromRGB(168, 184, 222)

type Info = { model: Model, light: PointLight?, lamps: { BasePart }, flickerUntil: number, seed: number, lit: boolean, floor: string }
type Beacon = { model: Model, rotor: BasePart, beams: { SpotLight }, glow: PointLight?, dome: BasePart?, phase: number }

local fixtures: { [Model]: Info } = {}
local beacons: { [Model]: Beacon } = {}
local signs: { [Model]: PointLight } = {}
local roomFlicker: { [string]: number } = {}
local random = Random.new()

local adaptHolder: Part
local adaptLight: PointLight
local adaptGrade: ColorCorrectionEffect
local adaptation = 0 -- 0 = eyes used to light, 1 = fully adjusted to the dark
local darkness = 0 -- how dark the building is around you right now (0..1)

local function hashFrac(a: number, b: number): number
	local h = (a * 7919 + b * 104729 + 1013) % 100003
	return (h % 1000) / 1000
end

local function register(model: Instance)
	if not model:IsA("Model") or fixtures[model] then
		return
	end
	local lamps = {}
	local light = nil
	for _, d in model:GetDescendants() do
		if d:IsA("PointLight") then
			light = d
		elseif d:IsA("BasePart") and (d.Name == "Tube" or d.Name == "Tube2" or d.Name == "Bulb") then
			table.insert(lamps, d)
		end
	end
	local room = model:GetAttribute("Room")
	fixtures[model] = {
		model = model,
		light = light,
		lamps = lamps,
		flickerUntil = 0,
		seed = model:GetAttribute("Seed") or random:NextInteger(1, 100000),
		lit = false,
		floor = if type(room) == "string" then room:sub(1, 1) else "",
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

local function evaluate(info: Info, camPos: Vector3, now: number)
	local m = info.model
	local mode = m:GetAttribute("Mode")
	local power = Workspace:GetAttribute("Power") == true
	local circuit = m:GetAttribute("Circuit")
	local forceOn = m:GetAttribute("ForceOn") == true
	local override = m:GetAttribute("Override")
	local tint = m:GetAttribute("Tint")
	local base = m:GetAttribute("BaseColor")
	local baseBrightness = m:GetAttribute("BaseBrightness") or 1
	local escape = Workspace:GetAttribute("Escape") == true
	local level = blackoutLevel()
	local bseed = Workspace:GetAttribute("BlackoutSeed") or 0
	local frac = hashFrac(info.seed, bseed)
	local emergency = circuit == "EMERGENCY"

	-- does this fixture have current?
	local mainOn = power
	local blackoutFlicker = false
	if level == 1 then
		blackoutFlicker = frac < 0.35
	elseif level == 2 then
		if info.floor == Workspace:GetAttribute("BlackoutZone") then
			mainOn = false
		end
	elseif level == 3 then
		if frac < 0.85 then
			mainOn = false
		else
			blackoutFlicker = true
		end
	elseif level >= 4 then
		mainOn = false
	end
	local emergencyOn = emergency and not (level >= 4 and frac < 0.5)
	local lit = mode ~= "dead" and override ~= "off" and (forceOn or (if emergency then (mainOn or emergencyOn) else mainOn))
	local color = if typeof(tint) == "Color3" then tint elseif typeof(base) == "Color3" then base else Color3.new(1, 1, 1)
	local brightness = baseBrightness
	if level == 1 then
		brightness *= 0.85
	end
	if lit and emergency and not mainOn and not forceOn then
		-- emergency lighting: dim and warm, red when things are serious
		if level >= 3 or escape then
			color = if typeof(tint) == "Color3" then tint else ALARM_COLOR
			brightness *= 0.5 * (0.7 + 0.3 * math.sin(now * (if level >= 4 then 3.2 else 1.6) + info.seed))
		else
			color = if typeof(tint) == "Color3" then tint else EMERGENCY_COLOR
			brightness *= 0.55
		end
	end
	if lit and escape and not (emergency and not mainOn) then
		-- the building is failing: slow, uneasy pulse
		brightness *= 0.55 + 0.35 * math.sin(now * 2.2 + info.seed)
	end
	local flickering = lit and (mode == "flicker" or blackoutFlicker or now < info.flickerUntil or (roomFlicker[m:GetAttribute("Room") or ""] or 0) > now)
	if flickering then
		local n = math.noise(now * 9, info.seed * 0.37)
		if n < -0.15 then
			lit = false
		elseif n < 0.05 then
			brightness *= 0.4
		end
	end
	local dist = (m:GetPivot().Position - camPos).Magnitude
	local light = info.light
	if light then
		light.Enabled = lit and dist < LOD_DISTANCE
		light.Color = color
		light.Brightness = brightness
	end
	for _, lamp in info.lamps do
		lamp.Color = if lit then color else DARK
		lamp.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
	end
	info.lit = lit
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
			local on = active and dist < LOD_DISTANCE
			for _, beam in b.beams do
				beam.Enabled = on
				beam.Brightness = if strong then 2.2 else 1.3
			end
			if b.glow then
				b.glow.Enabled = on
				b.glow.Brightness = if strong then 1.1 else 0.7
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
			glow.Enabled = (model:GetPivot().Position - camPos).Magnitude < LOD_DISTANCE
			glow.Brightness = if dark then 0.95 else 0.55
		end
	end
end

-- How dark is it where the camera is? Counts lit fixtures nearby.
local function measureDarkness(camPos: Vector3): number
	if State.round.state == "LOBBY" or State.status == "MENU" then
		return 0
	end
	local litNear = 0
	for _, info in fixtures do
		if info.lit and info.light then
			local d = (info.model:GetPivot().Position - camPos).Magnitude
			if d < 26 then
				litNear += (1 - d / 26) * (info.light.Brightness / 1.05)
			end
		end
	end
	return math.clamp(1 - litNear * 0.9, 0, 1)
end

local function updateAdaptation(dt: number, camPos: Vector3)
	local playing = State.status == "ALIVE" or State.status == "DEAD" or State.status == "ESCAPED"
	local target = if playing then darkness else 0
	-- eyes go blind instantly but take a few seconds to adjust to the dark
	if target > adaptation then
		adaptation += (target - adaptation) * Util.damp(0.55, dt)
	else
		adaptation += (target - adaptation) * Util.damp(2.5, dt)
	end
	local level = blackoutLevel()
	local strength = 0.24 + (if level >= 4 then 0.06 else 0)
	local gamma = State.settings.brightness or 0.5
	strength *= 0.6 + gamma * 0.8
	adaptHolder.CFrame = CFrame.new(camPos + Vector3.new(0, 1.2, 0))
	adaptLight.Enabled = adaptation > 0.02
	adaptLight.Brightness = adaptation * strength
	adaptLight.Range = 16 + adaptation * 6
	adaptGrade.Brightness = adaptation * 0.035 * (0.6 + gamma * 0.8)
	adaptGrade.Contrast = -adaptation * 0.04
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

function LightController:GetDarkness(): number
	return darkness
end

local function applyPowered()
	local power = Workspace:GetAttribute("Power") == true
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Light") and d:GetAttribute("PoweredLight") then
			d.Enabled = power
		end
	end
	for _, d in CollectionService:GetTagged("Screen") do
		if d:IsA("BasePart") and d:IsDescendantOf(Workspace) then
			d.Material = if power then Enum.Material.Neon else Enum.Material.Glass
			d.Color = if power then Color3.fromRGB(46, 62, 56) else Color3.fromRGB(18, 22, 20)
		end
	end
end

function LightController:Init()
	adaptHolder = Instance.new("Part")
	adaptHolder.Name = "DarkAdaptation"
	adaptHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	adaptHolder.Transparency = 1
	adaptHolder.Anchored = true
	adaptHolder.CanCollide = false
	adaptHolder.CanQuery = false
	adaptHolder.CanTouch = false
	adaptHolder.CastShadow = false
	adaptHolder.Parent = Workspace
	adaptLight = Instance.new("PointLight")
	adaptLight.Color = ADAPT_COLOR
	adaptLight.Shadows = false
	adaptLight.Range = 16
	adaptLight.Brightness = 0
	adaptLight.Enabled = false
	adaptLight.Parent = adaptHolder
	adaptGrade = Instance.new("ColorCorrectionEffect")
	adaptGrade.Name = "DarkAdaptation"
	adaptGrade.Parent = Lighting
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
	Workspace:GetAttributeChangedSignal("Power"):Connect(applyPowered)
	Workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
		task.wait(0.5)
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
	-- near fixtures every frame (smooth flicker), far ones a few times a second
	local farAcc = 0
	local darkAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local camPos = Workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		farAcc += dt
		darkAcc += dt
		local doFar = farAcc > 0.35
		if doFar then
			farAcc = 0
			updateSigns(camPos)
		end
		for model, info in fixtures do
			if not model.Parent then
				fixtures[model] = nil
			else
				local near = (model:GetPivot().Position - camPos).Magnitude < 60
				if near or doFar then
					evaluate(info, camPos, now)
				end
			end
		end
		updateBeacons(camPos, now, dt)
		if darkAcc > 0.2 then
			darkAcc = 0
			darkness = measureDarkness(camPos)
		end
		updateAdaptation(dt, camPos)
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
