--[[
	FlashlightController
	Your flashlight is a shadow-casting SpotLight that follows the camera with a
	little weight. Teammates' flashlights follow their heads and the pitch they are
	looking at, so you can see where a friend is looking from across a hall.
	Battery is server authoritative; this only renders it. Interference: the
	closer The Observer is, the more every flashlight stutters.
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
local spot: SpotLight
local fill: PointLight
local dust: ParticleEmitter
local hazeBeam: Beam
local lagCF = CFrame.new()
local localOn = false
local pendingUntil = 0
local others: { [Player]: { part: Part, light: SpotLight } } = {}
local random = Random.new()
local flickerUntil = 0

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
		Registry.HUDController:Hint("The battery is dead. Find batteries.", 3)
		return
	end
	localOn = want
	pendingUntil = os.clock() + 1.2
	Registry.AudioController:PlayUI(if want then "FlashlightOn" else "FlashlightOff")
	Net.event("Flashlight"):FireServer(want)
end

local function applyCosmetics()
	local color = player:GetAttribute("FlashlightColor")
	if typeof(color) == "Color3" then
		spot.Color = color
		fill.Color = color
	end
	local effect = player:GetAttribute("BeamEffect") or "clean"
	dust.Enabled = effect == "dust" or effect == "haze"
	hazeBeam.Enabled = effect == "haze"
end

local function interference(): number
	local d = State.observerDistance
	if d < GameConfig.Observer.PresenceRadius then
		return 1 - d / GameConfig.Observer.PresenceRadius
	end
	return 0
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
	local target = camera.CFrame * CFrame.new(0.55, -0.45, -0.4)
	lagCF = lagCF:Lerp(target, Util.damp(22, dt))
	holder.CFrame = CFrame.new(lagCF.Position) * (camera.CFrame - camera.CFrame.Position)
	local battery = player:GetAttribute("Battery") or 100
	local brightness = FL.Brightness
	local on = localOn
	if on then
		-- weak battery: dimmer and unsteady
		if battery < FL.LowBatteryThreshold then
			brightness *= 0.55 + 0.45 * (battery / FL.LowBatteryThreshold)
			if random:NextNumber() < 0.012 then
				flickerUntil = os.clock() + random:NextNumber(0.05, 0.25)
			end
		end
		local i = interference()
		if i > 0 and random:NextNumber() < 0.02 + i * 0.12 then
			flickerUntil = os.clock() + random:NextNumber(0.04, 0.12 + i * 0.3)
		end
		if (player:GetAttribute("BeamEffect") == "flicker") and random:NextNumber() < 0.004 then
			flickerUntil = os.clock() + 0.06
		end
		if os.clock() < flickerUntil then
			brightness *= random:NextNumber(0, 0.35)
		end
	end
	spot.Enabled = on
	fill.Enabled = on
	spot.Brightness = brightness
	fill.Brightness = brightness * 0.06
	dust.Rate = if on then 6 else 0
	hazeBeam.Enabled = on and player:GetAttribute("BeamEffect") == "haze"
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
			local b = FL.Brightness
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
	spot = Instance.new("SpotLight")
	spot.Range = FL.Range
	spot.Angle = FL.Angle
	spot.Brightness = FL.Brightness
	spot.Shadows = true
	spot.Face = Enum.NormalId.Front
	spot.Enabled = false
	spot.Parent = holder
	-- a faint fill so the immediate surroundings are not pitch black around the cone
	fill = Instance.new("PointLight")
	fill.Range = 9
	fill.Brightness = 0.12
	fill.Shadows = false
	fill.Enabled = false
	fill.Parent = holder
	-- dust motes hanging in the beam
	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Position = Vector3.new(0, 0, -8)
	dustAttachment.Parent = holder
	dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(2, 4)
	dust.Speed = NumberRange.new(0.1, 0.4)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new(0.05)
	dust.LightInfluence = 1
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.Parent = dustAttachment
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
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Flashlight" and began then
			self:Toggle()
		end
	end)
	RunService:BindToRenderStep("DLA_Flashlight", Enum.RenderPriority.Camera.Value + 2, update)
end

return FlashlightController
