--[[
	Screen
	Everything drawn over the picture, inside MarketingRuntimeGui:

	  Bars     black bars around the social safe frame (9:16, 16:9, 1:1)
	  Safe     the frame the clip is composed in (text lives here)
	  Fade     black fade (FadeToBlack / FadeFromBlack / cuts)
	  Vignette soft dark edges
	  FX       glitch blocks, CCTV scanlines, grain

	Also the colour grade (a ColorCorrection + Blur on the camera, tracked).
]]

local Workspace = game:GetService("Workspace")

local Runtime = require(script.Parent.Parent.Runtime)
local Format = require(script.Parent.Parent.Utilities.Format)

local Screen = {}

local format = "SOCIAL_VERTICAL"
local nodes: { [string]: any } = {}
local grade: ColorCorrectionEffect? = nil
local blur: BlurEffect? = nil
local random = Random.new()

Screen.Grades = {
	neutral = { Brightness = 0, Contrast = 0.05, Saturation = -0.1, TintColor = Color3.new(1, 1, 1) },
	cold = { Brightness = 0.03, Contrast = 0.16, Saturation = -0.4, TintColor = Color3.fromRGB(205, 218, 255) },
	warm = { Brightness = 0.04, Contrast = 0.1, Saturation = -0.25, TintColor = Color3.fromRGB(255, 232, 205) },
	dread = { Brightness = 0.02, Contrast = 0.22, Saturation = -0.55, TintColor = Color3.fromRGB(215, 222, 235) },
	cctv = { Brightness = 0.08, Contrast = 0.3, Saturation = -1, TintColor = Color3.fromRGB(196, 232, 206) },
	dark = { Brightness = -0.12, Contrast = 0.32, Saturation = -0.7, TintColor = Color3.fromRGB(200, 205, 225) },
	blackout = { Brightness = -0.85, Contrast = 0.5, Saturation = -1, TintColor = Color3.fromRGB(150, 155, 170) },
	keyart = { Brightness = 0.0, Contrast = 0.38, Saturation = -0.72, TintColor = Color3.fromRGB(228, 226, 232) },
	red = { Brightness = 0.02, Contrast = 0.3, Saturation = -0.3, TintColor = Color3.fromRGB(255, 170, 165) },
}

local function frame(parent: Instance, name: string, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	for k, v in (props or {}) :: { [string]: any } do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

function Screen.setFormat(name: string)
	format = if Format.Presets[name] then name else "SOCIAL_VERTICAL"
	Screen.layout()
end

function Screen.getFormat(): string
	return format
end

-- Build the overlay (once per scene).
function Screen.begin()
	local gui = Runtime.gui()
	table.clear(nodes)
	nodes.root = gui
	nodes.safe = frame(gui, "Safe", { ZIndex = 1, ClipsDescendants = true })
	nodes.vignette = frame(nodes.safe, "Vignette", { ZIndex = 2 })
	for i, spec in { { 0, 0, 1, 0.22, 90 }, { 0, 0.78, 1, 0.22, -90 }, { 0, 0, 0.22, 1, 0 }, { 0.78, 0, 0.22, 1, 180 } } do
		local edge = frame(nodes.vignette, "Edge" .. i, { Position = UDim2.fromScale(spec[1], spec[2]), Size = UDim2.fromScale(spec[3], spec[4]), BackgroundTransparency = 0 })
		local g = Instance.new("UIGradient")
		g.Rotation = spec[5]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = edge
	end
	nodes.vignette.Visible = false
	nodes.backdrop = frame(nodes.safe, "Backdrop", { ZIndex = 1, BackgroundTransparency = 1 })
	nodes.fx = frame(nodes.safe, "FX", { ZIndex = 5 })
	nodes.text = frame(nodes.safe, "Text", { ZIndex = 10 })
	nodes.fade = frame(gui, "Fade", { ZIndex = 20, BackgroundTransparency = 1 })
	nodes.bars = frame(gui, "Bars", { ZIndex = 30 })
	for _, name in { "Left", "Right", "Top", "Bottom" } do
		frame(nodes.bars, name, { BackgroundTransparency = 0 })
	end
	local camera = Workspace.CurrentCamera
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "MarketingGrade"
	g.Parent = camera
	grade = Runtime.track(g)
	local b = Instance.new("BlurEffect")
	b.Name = "MarketingBlur"
	b.Size = 0
	b.Parent = camera
	blur = Runtime.track(b)
	Screen.layout()
end

function Screen.layout()
	if not nodes.safe or not nodes.safe.Parent then
		return
	end
	local viewport = Workspace.CurrentCamera.ViewportSize
	local pos, size = Format.safeRect(format, viewport)
	nodes.safe.Position = UDim2.fromOffset(pos.X, pos.Y)
	nodes.safe.Size = UDim2.fromOffset(size.X, size.Y)
	local bars = nodes.bars
	bars.Left.Size = UDim2.fromOffset(pos.X + 1, viewport.Y)
	bars.Right.Position = UDim2.fromOffset(pos.X + size.X - 1, 0)
	bars.Right.Size = UDim2.fromOffset(viewport.X - pos.X - size.X + 2, viewport.Y)
	bars.Top.Size = UDim2.fromOffset(viewport.X, pos.Y + 1)
	bars.Bottom.Position = UDim2.fromOffset(0, pos.Y + size.Y - 1)
	bars.Bottom.Size = UDim2.fromOffset(viewport.X, viewport.Y - pos.Y - size.Y + 2)
	nodes.fade.Position = nodes.safe.Position
	nodes.fade.Size = nodes.safe.Size
end

function Screen.safe(): Frame?
	return nodes.safe
end

function Screen.textLayer(): Frame?
	return nodes.text
end

function Screen.fxLayer(): Frame?
	return nodes.fx
end

function Screen.safeSize(): Vector2
	local _, size = Format.safeRect(format, Workspace.CurrentCamera.ViewportSize)
	return size
end

-- 0 = clear, 1 = black
function Screen.setFade(alpha: number)
	if nodes.fade then
		nodes.fade.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
	end
end

function Screen.getFade(): number
	return if nodes.fade then 1 - nodes.fade.BackgroundTransparency else 0
end

-- A black card behind the eye and the text (but over the world): black-screen scenes.
function Screen.setBackdrop(alpha: number)
	if nodes.backdrop then
		nodes.backdrop.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
	end
end

function Screen.getBackdrop(): number
	return if nodes.backdrop then 1 - nodes.backdrop.BackgroundTransparency else 0
end

function Screen.setVignette(on: boolean)
	if nodes.vignette then
		nodes.vignette.Visible = on
	end
end

function Screen.setBlur(size: number)
	if blur then
		blur.Size = size
	end
end

function Screen.getGrade(): ColorCorrectionEffect?
	return grade
end

-- Read the grade as a table (for blending).
function Screen.gradeValues()
	local g = grade
	if not g then
		return Screen.Grades.neutral
	end
	return { Brightness = g.Brightness, Contrast = g.Contrast, Saturation = g.Saturation, TintColor = g.TintColor }
end

function Screen.blendGrade(from, to, a: number)
	local g = grade
	if not g then
		return
	end
	g.Brightness = from.Brightness + (to.Brightness - from.Brightness) * a
	g.Contrast = from.Contrast + (to.Contrast - from.Contrast) * a
	g.Saturation = from.Saturation + (to.Saturation - from.Saturation) * a
	g.TintColor = from.TintColor:Lerp(to.TintColor, a)
end

------------------------------------------------------------------------------------
-- Glitch: torn horizontal blocks, colour split, a jump of exposure
------------------------------------------------------------------------------------

function Screen.glitchFrame(intensity: number)
	local fx = nodes.fx
	if not fx then
		return
	end
	local layer = fx:FindFirstChild("Glitch") or frame(fx, "Glitch", { ZIndex = 6 })
	layer:ClearAllChildren()
	local count = math.floor(3 + intensity * 9)
	for _ = 1, count do
		local h = random:NextNumber(0.005, 0.06) * (0.5 + intensity)
		local y = random:NextNumber(0, 1 - h)
		local tint = ({ Color3.fromRGB(255, 40, 60), Color3.fromRGB(40, 255, 220), Color3.fromRGB(240, 240, 240), Color3.new(0, 0, 0) })[random:NextInteger(1, 4)]
		frame(layer, "Tear", {
			Position = UDim2.fromScale(random:NextNumber(-0.2, 0.3), y),
			Size = UDim2.fromScale(random:NextNumber(0.3, 1.2), h),
			BackgroundColor3 = tint,
			BackgroundTransparency = random:NextNumber(0.35, 0.8),
			ZIndex = 6,
		})
	end
end

function Screen.clearGlitch()
	local fx = nodes.fx
	local layer = fx and fx:FindFirstChild("Glitch")
	if layer then
		layer:Destroy()
	end
end

------------------------------------------------------------------------------------
-- CCTV overlay: scanlines, grain, REC, camera name, timestamp
------------------------------------------------------------------------------------

function Screen.setCCTV(on: boolean, label: string?, stamp: string?)
	local fx = nodes.fx
	if not fx then
		return
	end
	local layer = fx:FindFirstChild("CCTV")
	if not on then
		if layer then
			layer:Destroy()
		end
		return
	end
	if not layer then
		layer = frame(fx, "CCTV", { ZIndex = 7 })
		for i = 0, 59 do
			frame(layer, "Scan", { Position = UDim2.fromScale(0, i / 60), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.82, ZIndex = 7 })
		end
		local grain = frame(layer, "Grain", { ZIndex = 8 })
		for i = 1, 40 do
			frame(grain, "Dot" .. i, { Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, ZIndex = 8 })
		end
		local function label_(name: string, pos: UDim2, anchor: Vector2, size: number)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.AnchorPoint = anchor
			t.Position = pos
			t.Size = UDim2.fromScale(0.6, size)
			t.Font = Enum.Font.Code
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(235, 240, 235)
			t.TextStrokeTransparency = 0.6
			t.TextXAlignment = if anchor.X > 0.5 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
			t.ZIndex = 9
			t.Text = ""
			t.Parent = layer
			return t
		end
		label_("Cam", UDim2.fromScale(0.05, 0.04), Vector2.new(0, 0), 0.035)
		label_("Rec", UDim2.fromScale(0.95, 0.04), Vector2.new(1, 0), 0.03).Text = "● REC"
		label_("Stamp", UDim2.fromScale(0.05, 0.95), Vector2.new(0, 1), 0.026)
	end
	if label then
		(layer :: any).Cam.Text = label
	end
	if stamp then
		(layer :: any).Stamp.Text = stamp
	end
end

-- Animate the CCTV layer (grain, blinking REC). Cheap: 40 dots.
function Screen.updateCCTV(clock: number, stamp: string?)
	local fx = nodes.fx
	local layer = fx and fx:FindFirstChild("CCTV")
	if not layer then
		return
	end
	local rec = layer:FindFirstChild("Rec") :: TextLabel?
	if rec then
		rec.TextTransparency = if math.floor(clock * 1.2) % 2 == 0 then 0 else 1
	end
	if stamp then
		(layer :: any).Stamp.Text = stamp
	end
	local grain = layer:FindFirstChild("Grain")
	if grain then
		for _, d in grain:GetChildren() do
			(d :: Frame).Position = UDim2.fromScale(random:NextNumber(), random:NextNumber())
		end
	end
end

------------------------------------------------------------------------------------
-- Film grain: fine dust and a few vertical scratches (cheap: ~60 frames)
------------------------------------------------------------------------------------

function Screen.setGrain(on: boolean, amount: number?)
	local fx = nodes.fx
	if not fx then
		return
	end
	local layer = fx:FindFirstChild("Grain")
	if not on then
		if layer then
			layer:Destroy()
		end
		return
	end
	if layer then
		return
	end
	layer = frame(fx, "Grain", { ZIndex = 8 })
	local a = amount or 1
	for i = 1, math.floor(56 * a) do
		frame(layer, "Dust" .. i, { Size = UDim2.fromOffset(random:NextInteger(1, 3), random:NextInteger(1, 3)), BackgroundColor3 = if i % 3 == 0 then Color3.new(0, 0, 0) else Color3.fromRGB(230, 230, 230), BackgroundTransparency = 0.55, ZIndex = 8 })
	end
	for i = 1, 3 do
		frame(layer, "Scratch" .. i, { Size = UDim2.new(0, 1, random:NextNumber(0.3, 1), 0), BackgroundColor3 = Color3.fromRGB(220, 220, 220), BackgroundTransparency = 0.7, ZIndex = 8 })
	end
end

function Screen.updateGrain()
	local fx = nodes.fx
	local layer = fx and fx:FindFirstChild("Grain")
	if not layer then
		return
	end
	for _, d in layer:GetChildren() do
		local f = d :: Frame
		if string.sub(f.Name, 1, 7) == "Scratch" then
			f.Visible = random:NextNumber() < 0.35
			f.Position = UDim2.fromScale(random:NextNumber(), random:NextNumber(-0.2, 0.3))
		else
			f.Position = UDim2.fromScale(random:NextNumber(), random:NextNumber())
		end
	end
end

return Screen
