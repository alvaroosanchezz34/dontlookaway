--[[
	FlashlightController
	The flashlight is a physical object in your hand, not a cone glued to the
	screen:
	  * two shadow-casting spot lights (a tight hot centre and a soft wide spill)
	    give a real falloff, plus a faint bounce around you
	  * it hangs below and to the right of the view and follows it on a spring, so
	    fast turns drag the beam and it settles with a little overshoot
	  * it warms up when switched on (a stutter, then full brightness)
	  * dust hangs in the beam and a very faint volumetric cone shows its shape
	  * a weak battery dims it and makes it unsteady but never blinds you; the HUD
	    and a soft beep warn at 20%, 10% and 5%
	  * The Observer interferes with it: the closer it is, the more it stutters,
	    and during an attack it strobes
	Teammates' flashlights follow their heads and the pitch they are looking at,
	so you can see where a friend is looking from across a hall.
	Battery and equipment tiers are server authoritative (player attributes):
	  Battery, Flashlight, FlashlightRange, FlashlightAngle, FlashlightPower
	Cosmetics change the colour and beam effect, never brightness or range.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local FlashlightController = {}

local player = Players.LocalPlayer
local FL = GameConfig.Flashlight

local holder: Part
local core: SpotLight
local spill: SpotLight
local fill: PointLight
local dust: ParticleEmitter
local hazeBeam: Beam
local coneBeam: Beam
local springPos = Vector3.zero
local springVel = Vector3.zero
local springRot = CFrame.new()
local localOn = false
local pendingUntil = 0
local switchedAt = 0
local others: { [Player]: { part: Part, light: SpotLight } } = {}
local random = Random.new()
local flickerUntil = 0
local lastWarned = 100
local intensity = 0 -- smoothed 0..1 output (warm-up / switch-off)

local function makeHolder(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = Workspace
	return p
end

local function stats(): (number, number, number)
	local range = player:GetAttribute("FlashlightRange")
	local angle = player:GetAttribute("FlashlightAngle")
	local power = player:GetAttribute("FlashlightPower")
	return (if type(range) == "number" then range else FL.Range), (if type(angle) == "number" then angle else FL.Angle), (if type(power) == "number" then power else FL.Brightness)
end

function FlashlightController:IsOn(): boolean
	return localOn
end

function FlashlightController:Toggle()
	if State.status ~= "ALIVE" then
		return
	end
	local battery = player:GetAttribute("Battery") or 100
	local want = not localOn
	if want and battery <= 0 then
		Registry.AudioController:PlayUI("FlashlightDead")
		Registry.HUDController:Hint("The battery is dead. Use a battery, or let it rest.", 3)
		-- a dead flashlight still clicks and sputters once
		flickerUntil = os.clock() + 0.12
		return
	end
	localOn = want
	pendingUntil = os.clock() + 1.2
	if want then
		switchedAt = os.clock()
	end
	Registry.AudioController:PlayUI(if want then "FlashlightOn" else "FlashlightOff")
	Registry.CameraController:Shake(0.04)
	Net.event("Flashlight"):FireServer(want)
end

local function effectsEnabled(): boolean
	return State.settings.flashlightEffects ~= false and State.settings.graphics ~= "LOW"
end

local function applyCosmetics()
	local color = player:GetAttribute("FlashlightColor")
	if typeof(color) == "Color3" then
		core.Color = color
		spill.Color = color
		fill.Color = color
		coneBeam.Color = ColorSequence.new(color)
	end
end

local function interference(): number
	local d = State.observerDistance
	if d < GameConfig.Observer.PresenceRadius then
		return 1 - d / GameConfig.Observer.PresenceRadius
	end
	return 0
end

local function warnBattery(battery: number)
	for _, threshold in { 20, 10, 5 } do
		if battery <= threshold and lastWarned > threshold then
			lastWarned = threshold
			Registry.AudioController:PlayUI("LowBattery")
			Registry.HUDController:Hint(string.format("Battery %d%%. Find batteries.", threshold), 2.5)
			return
		end
	end
	if battery > lastWarned + 5 then
		-- recharged
		lastWarned = 100
	end
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	-- server truth wins once our request has had time to arrive
	if os.clock() > pendingUntil then
		localOn = player:GetAttribute("Flashlight") == true
	end
	if State.status ~= "ALIVE" then
		localOn = false
	end
	-- spring-follow: the light lags behind fast turns and settles with overshoot
	local target = camera.CFrame * CFrame.new(0.55, -0.5, -0.45)
	local stiffness, damping = 220, 22
	local accel = (target.Position - springPos) * stiffness - springVel * damping
	springVel += accel * math.min(dt, 1 / 30)
	springPos += springVel * math.min(dt, 1 / 30)
	if (springPos - target.Position).Magnitude > 6 then
		springPos = target.Position
		springVel = Vector3.zero
	end
	local camRot = camera.CFrame - camera.CFrame.Position
	springRot = springRot:Lerp(camRot, Util.damp(16, dt))
	-- hand sway while walking
	local t = os.clock()
	local moving = State.sprinting and 1 or 0.4
	local sway = CFrame.Angles(math.noise(t * 0.7, 1) * 0.012 * moving, math.noise(t * 0.7, 2) * 0.016 * moving, 0)
	holder.CFrame = CFrame.new(springPos) * springRot * sway

	local battery = player:GetAttribute("Battery") or 100
	local range, angle, power = stats()
	local on = localOn
	local brightness = power
	if on then
		warnBattery(battery)
		-- warm-up: a stutter, then full output
		local since = os.clock() - switchedAt
		if since < 0.18 then
			brightness *= if since < 0.05 or (since > 0.09 and since < 0.12) then 0.25 else 0.8
		end
		-- weak battery: dimmer and unsteady, never black
		if battery < FL.LowBatteryThreshold then
			brightness *= 0.5 + 0.5 * (battery / FL.LowBatteryThreshold)
			local chance = if battery < 8 then 0.03 else 0.012
			if random:NextNumber() < chance then
				flickerUntil = os.clock() + random:NextNumber(0.05, 0.22)
			end
		end
		local i = interference()
		local attacking = Workspace:GetAttribute("ObserverState") == "ATTACKING"
		if attacking and i > 0.4 then
			-- strobe
			brightness *= if math.floor(os.clock() * 14) % 2 == 0 then 1 else 0.1
		elseif i > 0 and random:NextNumber() < 0.02 + i * 0.12 then
			flickerUntil = os.clock() + random:NextNumber(0.04, 0.12 + i * 0.3)
		end
		if player:GetAttribute("BeamEffect") == "flicker" and random:NextNumber() < 0.004 then
			flickerUntil = os.clock() + 0.06
		end
		if os.clock() < flickerUntil then
			brightness *= random:NextNumber(0.25, 0.5)
		end
		-- the faintest living flicker of a real bulb
		brightness *= 0.97 + math.noise(t * 6, 3) * 0.03
	elseif os.clock() < flickerUntil then
		-- a dead light sputtering on a click
		on = true
		brightness *= 0.12
	end
	intensity += ((if on then 1 else 0) - intensity) * Util.damp(if on then 30 else 18, dt)
	local out = brightness * intensity
	local lit = intensity > 0.02
	core.Enabled = lit
	spill.Enabled = lit
	fill.Enabled = lit
	core.Range = range + 6
	core.Angle = angle * 0.42
	core.Brightness = out * 0.75
	spill.Range = range
	spill.Angle = angle
	spill.Brightness = out * 0.7
	fill.Brightness = out * 0.05
	local fx = effectsEnabled()
	local effect = player:GetAttribute("BeamEffect") or "clean"
	dust.Rate = if lit and fx then (if effect == "dust" or effect == "haze" then 14 else 5) else 0
	hazeBeam.Enabled = lit and fx and effect == "haze"
	coneBeam.Enabled = lit and fx
	coneBeam.Width1 = math.tan(math.rad(angle * 0.5)) * 2 * 18
	local coneAlpha = 1 - math.clamp(intensity * (brightness / math.max(power, 0.01)), 0, 1) * 0.045
	coneBeam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, coneAlpha), NumberSequenceKeypoint.new(0.3, 1 - (1 - coneAlpha) * 0.7), NumberSequenceKeypoint.new(1, 1) })

	-- teammates' lights
	for other, rec in others do
		local character = other.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local onOther = other:GetAttribute("Flashlight") == true and head ~= nil and other:GetAttribute("Status") == "ALIVE"
		if onOther and head then
			local distance = (head.Position - camera.CFrame.Position).Magnitude
			onOther = distance < 140
			local pitch = character and character:GetAttribute("LookPitch") or 0
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local yawCF = if root then (root.CFrame - root.CFrame.Position) else (head.CFrame - head.CFrame.Position)
			rec.part.CFrame = CFrame.new(head.Position + yawCF.LookVector * 0.6 + Vector3.new(0, -0.2, 0)) * yawCF * CFrame.Angles(pitch, 0, 0)
			local color = other:GetAttribute("FlashlightColor")
			if typeof(color) == "Color3" then
				rec.light.Color = color
			end
			local oRange = other:GetAttribute("FlashlightRange")
			local oAngle = other:GetAttribute("FlashlightAngle")
			local oPower = other:GetAttribute("FlashlightPower")
			rec.light.Range = if type(oRange) == "number" then oRange else FL.Range
			rec.light.Angle = if type(oAngle) == "number" then oAngle else FL.Angle
			local b = if type(oPower) == "number" then oPower else FL.Brightness
			local ob = other:GetAttribute("Battery") or 100
			if ob < FL.LowBatteryThreshold then
				b *= 0.5 + 0.5 * (ob / FL.LowBatteryThreshold)
			end
			if os.clock() < flickerUntil then
				b *= 0.3
			end
			rec.light.Brightness = b
		end
		rec.light.Enabled = onOther
	end
end

local function addOther(other: Player)
	if other == player or others[other] then
		return
	end
	local part = makeHolder("Flashlight_" .. other.UserId)
	local light = Instance.new("SpotLight")
	light.Range = FL.Range
	light.Angle = FL.Angle
	light.Brightness = FL.Brightness
	light.Shadows = true
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Parent = part
	others[other] = { part = part, light = light }
end

function FlashlightController:Init()
	holder = makeHolder("LocalFlashlight")
	core = Instance.new("SpotLight")
	core.Name = "Core"
	core.Range = FL.Range + 6
	core.Angle = FL.Angle * 0.42
	core.Brightness = FL.Brightness
	core.Shadows = true
	core.Face = Enum.NormalId.Front
	core.Enabled = false
	core.Parent = holder
	spill = Instance.new("SpotLight")
	spill.Name = "Spill"
	spill.Range = FL.Range
	spill.Angle = FL.Angle
	spill.Brightness = FL.Brightness
	spill.Shadows = true
	spill.Face = Enum.NormalId.Front
	spill.Enabled = false
	spill.Parent = holder
	-- light bouncing back off whatever you point at: the space around you never goes black
	fill = Instance.new("PointLight")
	fill.Range = 10
	fill.Brightness = 0.12
	fill.Shadows = false
	fill.Enabled = false
	fill.Parent = holder
	-- dust motes hanging in the beam
	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Position = Vector3.new(0, 0, -7)
	dustAttachment.Parent = holder
	dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(2.5, 4.5)
	dust.Speed = NumberRange.new(0.05, 0.3)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new(0.045)
	dust.LightInfluence = 1
	dust.LightEmission = 0.15
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-20, 20)
	dust.Parent = dustAttachment
	dustAttachment.CFrame = CFrame.new(0, 0, -7)
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -22)
	a1.Parent = holder
	hazeBeam = Instance.new("Beam")
	hazeBeam.Attachment0 = a0
	hazeBeam.Attachment1 = a1
	hazeBeam.Width0 = 0.3
	hazeBeam.Width1 = 12
	hazeBeam.FaceCamera = true
	hazeBeam.LightEmission = 0.3
	hazeBeam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
	hazeBeam.Enabled = false
	hazeBeam.Parent = holder
	-- a barely-there volumetric cone so the beam has a shape in the air
	local c1 = Instance.new("Attachment")
	c1.Position = Vector3.new(0, 0, -18)
	c1.Parent = holder
	coneBeam = Instance.new("Beam")
	coneBeam.Attachment0 = a0
	coneBeam.Attachment1 = c1
	coneBeam.Width0 = 0.25
	coneBeam.Width1 = 14
	coneBeam.FaceCamera = true
	coneBeam.LightEmission = 0.25
	coneBeam.LightInfluence = 0
	coneBeam.Segments = 6
	coneBeam.Enabled = false
	coneBeam.Parent = holder
end

function FlashlightController:Start()
	for _, p in Players:GetPlayers() do
		addOther(p)
	end
	Players.PlayerAdded:Connect(addOther)
	Players.PlayerRemoving:Connect(function(p)
		local rec = others[p]
		if rec then
			rec.part:Destroy()
			others[p] = nil
		end
	end)
	player:GetAttributeChangedSignal("FlashlightColor"):Connect(applyCosmetics)
	player:GetAttributeChangedSignal("BeamEffect"):Connect(applyCosmetics)
	applyCosmetics()
	springPos = Workspace.CurrentCamera.CFrame.Position
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Flashlight" and began then
			self:Toggle()
		end
	end)
	RunService:BindToRenderStep("DLA_Flashlight", Enum.RenderPriority.Camera.Value + 2, update)
end

return FlashlightController
