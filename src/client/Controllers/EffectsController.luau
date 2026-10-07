--[[
	EffectsController
	Local screen and world effects. Everything here is subtle by design and
	respects the accessibility settings: "reduced effects" removes flashes and
	glitch strobing (replacing them with soft fades), "camera shake" scales shake.

	Server cues arrive as Effect events and are dispatched by name.
	Continuous effects: Observer presence (vignette, desaturation, micro-glitches)
	and fear (drives HUD fade, heartbeat, music).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local EffectsController = {}

local gui: ScreenGui
local blackout: Frame
local flash: Frame
local vignette: Frame
local glitchLayer: Frame
local cinematicText: TextLabel
local subText: TextLabel
local cc: ColorCorrectionEffect
local blur: BlurEffect
local presence = 0
local vignetteBase = 0.35
local handlers: { [string]: (any) -> () } = {}

local function reduced(): boolean
	return State.settings.reducedEffects == true
end

------------------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------------------

local function makeVignette(parent: Instance): Frame
	local holder = Kit.frame({ Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = parent })
	local edges = {
		{ UDim2.new(1, 0, 0.32, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.32, 0), UDim2.fromScale(0, 0.68), -90 },
		{ UDim2.new(0.26, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.26, 0, 1, 0), UDim2.fromScale(0.74, 0), 180 },
	}
	for _, e in edges do
		local f = Kit.frame({ Size = e[1], Position = e[2], BackgroundColor3 = Color3.new(), Parent = holder })
		Kit.new("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f,
		})
	end
	return holder
end

function EffectsController:Fade(alpha: number, time: number)
	Kit.tween(blackout, time, { BackgroundTransparency = 1 - alpha })
end

function EffectsController:Flash(color: Color3?, strength: number?, time: number?)
	if reduced() then
		strength = (strength or 0.6) * 0.25
	end
	flash.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1 - (strength or 0.6)
	Kit.tween(flash, time or 0.35, { BackgroundTransparency = 1 })
end

function EffectsController:Glitch(strength: number, duration: number?)
	if reduced() then
		self:Flash(Color3.new(0, 0, 0), 0.25 * strength, 0.3)
		return
	end
	local d = duration or 0.25
	for _ = 1, math.floor(3 + strength * 6) do
		local h = math.random(4, 26)
		local bar = Kit.frame({
			Size = UDim2.new(1, 0, 0, h),
			Position = UDim2.new(0, math.random(-30, 30), math.random(), 0),
			BackgroundColor3 = if math.random() < 0.5 then Color3.fromRGB(200, 40, 40) else Color3.fromRGB(40, 200, 220),
			BackgroundTransparency = 0.82 - strength * 0.12,
			Parent = glitchLayer,
		})
		Debris:AddItem(bar, d * math.random(5, 10) / 10)
	end
	Registry.CameraController:Shake(0.15 * strength)
end

function EffectsController:Blur(size: number, time: number)
	Kit.tween(blur, time, { Size = size })
end

-- Cinematic text, centre screen. Returns after it has faded in.
function EffectsController:Title(text: string, sub: string?, hold: number?, font: Font?)
	cinematicText.FontFace = font or Kit.F.Title
	cinematicText.Text = text
	subText.Text = sub or ""
	cinematicText.TextTransparency = 1
	subText.TextTransparency = 1
	Kit.tween(cinematicText, 1.2, { TextTransparency = 0 })
	Kit.tween(subText, 1.6, { TextTransparency = 0.15 })
	Registry.AudioController:PlayUI("TitleHit")
	task.delay(hold or 3, function()
		if cinematicText.Text == text then
			Kit.tween(cinematicText, 1.4, { TextTransparency = 1 })
			Kit.tween(subText, 1.4, { TextTransparency = 1 })
		end
	end)
end

function EffectsController:Blink(duration: number)
	local top = Kit.frame({ Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(), Parent = gui, ZIndex = 20 })
	local bottom = Kit.frame({ Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = Color3.new(), Parent = gui, ZIndex = 20 })
	local close = math.min(0.09, duration * 0.3)
	Kit.tween(top, close, { Size = UDim2.fromScale(1, 0.52) })
	Kit.tween(bottom, close, { Size = UDim2.fromScale(1, 0.52) })
	Registry.AudioController:PlayUI("Blink")
	task.delay(duration - close, function()
		Kit.tween(top, 0.14, { Size = UDim2.fromScale(1, 0) })
		Kit.tween(bottom, 0.14, { Size = UDim2.fromScale(1, 0) })
		Debris:AddItem(top, 0.3)
		Debris:AddItem(bottom, 0.3)
	end)
end

local function particleBurst(at: Vector3, color: Color3, count: number, speed: number, size: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	holder.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.6, 2.2)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Size = NumberSequence.new(size)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.4
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, 3)
end

------------------------------------------------------------------------------------
-- Named effects (server cues)
------------------------------------------------------------------------------------

handlers.RealitySnap = function()
	EffectsController:Flash(Color3.fromRGB(235, 240, 255), 0.35, 0.4)
	EffectsController:Glitch(0.35, 0.18)
	Registry.CameraController:SetFovEffect(-6)
	task.delay(0.25, function()
		Registry.CameraController:SetFovEffect(0)
	end)
end

handlers.ReportWrong = function()
	EffectsController:Flash(Color3.new(0, 0, 0), 0.35, 0.5)
	EffectsController:Blur(6, 0.15)
	task.delay(0.35, function()
		EffectsController:Blur(0, 0.6)
	end)
end

handlers.Blink = function(p)
	EffectsController:Blink(p.duration or 0.35)
end

handlers.ObserverSeen = function()
	Registry.CameraController:SetFovEffect(-10)
	Registry.CameraController:Shake(0.25)
	task.delay(1.4, function()
		Registry.CameraController:SetFovEffect(0)
	end)
end

handlers.ObserverVanish = function(p)
	if p.at and (Workspace.CurrentCamera.CFrame.Position - p.at).Magnitude < 60 then
		EffectsController:Glitch(0.4, 0.2)
	end
end

handlers.Intro = function()
	State.notes = {}
	task.spawn(function()
		task.wait(1.2)
		EffectsController:Title("THE BUILDING CHANGES", "WHEN YOU STOP LOOKING.", 3.6)
		task.wait(5.4)
		local key = Registry.InputController:Label("Report")
		EffectsController:Title("FIND THE ANOMALIES", "Look at what changed and hold [" .. key .. "] to report it.", 3.6, Kit.F.Heading)
	end)
end

handlers.TutorialHint = function()
	local key = Registry.InputController:Label("Report")
	Registry.HUDController:Hint("Something in reception changed. Look at it and hold [" .. key .. "].", 8)
end

handlers.PowerSurge = function()
	EffectsController:Flash(Color3.fromRGB(255, 244, 220), 0.3, 0.8)
	Registry.CameraController:Shake(0.2)
end

handlers.EscapeStart = function()
	Registry.CameraController:Shake(0.6)
	EffectsController:Glitch(0.8, 0.5)
	EffectsController:Title("THE EXIT IS OPEN", "Get to the loading dock. Don't stop.", 3.2)
end

handlers.PortalGlitch = function()
	EffectsController:Glitch(0.9, 0.35)
	EffectsController:Fade(1, 0.05)
	task.delay(0.15, function()
		EffectsController:Fade(0, 0.5)
	end)
end

handlers.WrongRoom = function()
	EffectsController:Fade(1, 0.4)
	Registry.AudioController:PlayUI("JumpSting")
	task.delay(1.2, function()
		EffectsController:Fade(0, 1.2)
		EffectsController:Glitch(0.6, 0.3)
	end)
end

handlers.DustBurst = function(p)
	if p.at then
		particleBurst(p.at, Color3.fromRGB(150, 146, 136), 40, 6, 0.25)
	end
end

handlers.Sparks = function(p)
	if p.at then
		particleBurst(p.at, Color3.fromRGB(255, 210, 140), 25, 14, 0.12)
	end
end

handlers.ShadowRun = function(p)
	if not p.from or not p.to then
		return
	end
	local shadow = Instance.new("Part")
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.Size = Vector3.new(1.4, 8.6, 0.8)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Transparency = 0.15
	shadow.CFrame = CFrame.lookAt(p.from + Vector3.new(0, 4.3, 0), p.to + Vector3.new(0, 4.3, 0))
	shadow.Parent = Workspace
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / 0.55
		if t >= 1 then
			conn:Disconnect()
			shadow:Destroy()
			return
		end
		local pos = p.from:Lerp(p.to, t) + Vector3.new(0, 4.3, 0)
		shadow.CFrame = CFrame.lookAt(pos, p.to + Vector3.new(0, 4.3, 0))
	end)
end

handlers.Shake = function(p)
	Registry.CameraController:Shake(p.strength or 0.4)
end

handlers.Glitch = function(p)
	EffectsController:Glitch(p.strength or 0.5, 0.3)
end

handlers.WardBreak = function()
	EffectsController:Flash(Color3.fromRGB(230, 236, 255), 0.6, 1.2)
	Registry.CameraController:Shake(0.5)
end

handlers.Jumpscare = function()
	-- a face that is not a face, for a fraction of a second
	local face = Kit.frame({ Size = UDim2.fromScale(0.38, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), BackgroundColor3 = Color3.fromRGB(8, 8, 8), Parent = gui, ZIndex = 15 })
	Kit.corner(face, 400)
	Kit.frame({ Size = UDim2.new(0.03, 0, 0.6, 0), Position = UDim2.fromScale(0.485, 0.2), BackgroundColor3 = Color3.fromRGB(40, 38, 36), Parent = face, ZIndex = 16 })
	Registry.CameraController:Shake(0.9)
	EffectsController:Glitch(1, 0.3)
	Debris:AddItem(face, if reduced() then 0.15 else 0.28)
end

handlers.RealityCollapse = function()
	EffectsController:Glitch(1, 1)
	Kit.tween(cc, 3, { Saturation = -1, Contrast = 0.6, Brightness = -0.2 })
	EffectsController:Blur(18, 3)
	EffectsController:Title("THE BUILDING FORGOT YOU", "Too many changes went unseen.", 4)
	task.delay(2.5, function()
		EffectsController:Fade(1, 1.5)
	end)
end

handlers.OpenPanel = function(p)
	Registry.MenuController:OpenPanel(p.panel)
end

function EffectsController:Register(name: string, fn: (any) -> ())
	handlers[name] = fn
end

function EffectsController:Handle(name: string, payload: any)
	local h = handlers[name]
	if h then
		local ok, err = pcall(h, payload or {})
		if not ok then
			warn("[Effects] " .. name .. ": " .. tostring(err))
		end
	end
end

function EffectsController:ResetPost()
	Kit.tween(cc, 1, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	self:Blur(0, 1)
	self:Fade(0, 1)
end

------------------------------------------------------------------------------------
-- Continuous: Observer presence and fear
------------------------------------------------------------------------------------

local function observerModel(): Model?
	for _, m in CollectionService:GetTagged("Observer") do
		if m:IsDescendantOf(Workspace) then
			return m :: Model
		end
	end
	return nil
end

local lastMicro = 0

local function update(dt: number)
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local m = observerModel()
	local distance = math.huge
	if m and m.PrimaryPart then
		distance = (m.PrimaryPart.Position - camPos).Magnitude
	end
	State.observerDistance = distance
	local target = 0
	if State.status == "ALIVE" and distance < 55 then
		target = 1 - distance / 55
	end
	presence += (target - presence) * Util.damp(2.5, dt)
	-- fear: presence, the director's phase, darkness and escape
	local fear = presence
	if State.phase == "FEAR" then
		fear = math.max(fear, 0.45)
	elseif State.phase == "TENSION" then
		fear = math.max(fear, 0.2)
	end
	if State.round.state == "ESCAPE" then
		fear = math.max(fear, 0.6)
	end
	State.fear += (fear - State.fear) * Util.damp(1.5, dt)
	-- post processing
	local sat = -presence * 0.45
	cc.Saturation += (sat - cc.Saturation) * Util.damp(3, dt)
	cc.Contrast += (presence * 0.25 - cc.Contrast) * Util.damp(3, dt)
	local vig = vignetteBase + presence * 0.5 + State.fear * 0.1
	for _, child in vignette:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundTransparency = 1 - math.clamp(vig, 0, 0.95)
		end
	end
	-- micro glitches when it is very close and moving
	if presence > 0.55 and os.clock() - lastMicro > 1.6 and not reduced() then
		local stateAttr = Workspace:GetAttribute("ObserverState")
		if stateAttr ~= "WATCHED" then
			lastMicro = os.clock()
			EffectsController:Glitch(0.25 * presence, 0.12)
		end
	end
end

function EffectsController:Init()
	gui = Kit.screen("Overlay", 3, false)
	vignette = makeVignette(gui)
	glitchLayer = Kit.frame({ Name = "Glitch", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	flash = Kit.frame({ Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Parent = gui, ZIndex = 10 })
	blackout = Kit.frame({ Name = "Blackout", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Parent = gui, ZIndex = 12 })
	local textHolder = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui, ZIndex = 14 })
	Kit.attachScale(textHolder)
	cinematicText = Kit.text({ Size = UDim2.new(1, -80, 0, 70), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Title, TextSize = 44, TextTransparency = 1, Text = "", ZIndex = 14, Parent = textHolder })
	subText = Kit.text({ Size = UDim2.new(1, -80, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 24, TextColor3 = Kit.C.TextDim, TextTransparency = 1, Text = "", ZIndex = 14, Parent = textHolder })
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "LocalGrade"
	cc.Parent = Lighting
	blur = Instance.new("BlurEffect")
	blur.Name = "LocalBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

-- Power failures: a hard dip as the lights die (only on the big ones, and only
-- for a heartbeat), a jolt, sparks overhead. Eyes then adjust (LightController).
local function onBlackout(p)
	if State.status ~= "ALIVE" then
		return
	end
	local level = p.level or 1
	if level >= 3 then
		EffectsController:Fade(if reduced() then 0.45 else 0.8, 0.05)
		task.delay(0.18, function()
			EffectsController:Fade(0, 0.9)
		end)
		Registry.CameraController:Shake(0.25)
		Registry.CameraController:SetFovEffect(-4)
		task.delay(0.6, function()
			Registry.CameraController:SetFovEffect(0)
		end)
		local camera = Workspace.CurrentCamera
		particleBurst(camera.CFrame.Position + camera.CFrame.LookVector * 6 + Vector3.new(0, 6, 0), Color3.fromRGB(255, 210, 140), 18, 12, 0.1)
		if level >= 4 then
			Registry.HUDController:Hint("Total blackout. Stay close. Keep your light on.", 4)
		else
			Registry.HUDController:Hint("The power is failing.", 3)
		end
	elseif level == 2 then
		Registry.CameraController:Shake(0.1)
	end
end

function EffectsController:Start()
	Net.event("Effect").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.name) == "string" then
			self:Handle(payload.name, payload)
		end
	end)
	Net.event("Director").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.cue == "blackout" then
			onBlackout(payload)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return EffectsController
