--[[
	FilmController
	The old camera the game is seen through (MONOCHROME's look): film grain,
	dust and scratches, a projector's flicker, the gate weave of an old
	camera, and a slightly heavier vignette. On everywhere (menu, lobby, the
	building, results) unless the player turns it off (Settings -> Graphics:
	filmGrain, grainIntensity).

	Grain   two full-screen tiled layers over the world and under the HUD (the
	        HUD is not part of the film): white grain that lifts the image and
	        black grain that sinks it. 24 times a second both jump to a random
	        offset, so the grain is new every frame. It shows more in the dark
	        (no power, deep blackouts), with fear, and in a scare (Spike).
	        Where the grain comes from, best first:
	          texture  the uploaded sheets (AssetIds.Film, tools/gen_film.py)
	          runtime  a noise texture made in the game (EditableImage: in a
	                   published game the owner must be ID verified and turn
	                   on Security -> Allow Mesh / Image APIs)
	          specks   needs nothing: a field of single-pixel specks, white
	                   and black, scattered anew every frame (a few hundred,
	                   by graphics quality). Coarser than film, but always there
	Dust    now and then a speck or a vertical scratch for one frame.
	Flicker the grade's brightness wavers by +-0.01 at 24 Hz (not with
	        reduced effects).
	Weave   the frame drifts by a few hundredths of a degree (CameraController
	        reads Weave(); not with reduced motion).
	Vignette EffectsController's, a little heavier (not a second one).
]]

local AssetService = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AssetIds = require(ReplicatedStorage.Shared.Config.AssetIds)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local FilmController = {}

local FPS = 24
local TILE = 256 -- on-screen size of one grain tile (pixels)
local NOISE = 128 -- runtime noise texture (EditableImage fallback)

local gui: ScreenGui
local layers: { ImageLabel } = {}
local mode = "off" -- texture | runtime | specks | off
local specks: { Frame } = {}
-- how many specks by graphics quality (AccessibilityController:Quality())
local SPECKS = { [1] = 220, [2] = 450, [3] = 700 }
local dustLayer: Frame
local flicker: ColorCorrectionEffect
local available = false
local warned = false
local acc = 0
local spikeUntil = 0
local spikeAmount = 0
local weave = CFrame.new()
local random = Random.new()
local transient: { GuiObject } = {}

local function enabled(): boolean
	return available and State.settings.filmGrain ~= false
end

-- A grain texture made at runtime: one channel of noise, as alpha.
local function runtimeGrain(light: boolean): any
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(NOISE, NOISE) })
	local pixels = buffer.create(NOISE * NOISE * 4)
	local value = if light then 255 else 0
	for i = 0, NOISE * NOISE - 1 do
		-- a rough gaussian (sum of uniforms), centred on grey
		local g = (random:NextNumber() + random:NextNumber() + random:NextNumber() - 1.5) / 0.5
		local a = if (g > 0) == light then math.clamp(math.abs(g) / 2.6, 0, 1) ^ 0.8 * 255 else 0
		buffer.writeu8(pixels, i * 4, value)
		buffer.writeu8(pixels, i * 4 + 1, value)
		buffer.writeu8(pixels, i * 4 + 2, value)
		buffer.writeu8(pixels, i * 4 + 3, math.floor(a))
	end
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(NOISE, NOISE), pixels)
	return Content.fromObject(image)
end

local function makeLayer(name: string, light: boolean): ImageLabel?
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Tile
	label.TileSize = UDim2.fromOffset(TILE, TILE)
	label.Size = UDim2.new(1, TILE * 2, 1, TILE * 2)
	label.ImageTransparency = 1
	label.ZIndex = 1
	local id = AssetIds.Film[if light then "grain_light" else "grain_dark"]
	local url = AssetIds.url(id)
	if url then
		label.Image = url
		mode = "texture"
	else
		local ok, content = pcall(runtimeGrain, light)
		if not ok then
			label:Destroy()
			return nil
		end
		label.ImageContent = content
		mode = "runtime"
	end
	label.Parent = gui
	return label
end

-- How strong the grain is right now (0..1 before the player's intensity).
local function amount(): number
	local power = Workspace:GetAttribute("Power") == true
	local blackout = Workspace:GetAttribute("Blackout")
	local level = if type(blackout) == "number" then blackout else 0
	local dark = if not power and State.round.state ~= "LOBBY" then 0.6 else level * 0.12
	local spike = if os.clock() < spikeUntil then spikeAmount else 0
	local a = 0.55 + dark + (State.fear or 0) * 0.25 + spike
	if level >= 4 and not State.settings.reducedEffects then
		-- the grain trembles
		a *= 0.85 + 0.3 * random:NextNumber()
	end
	return a
end

local function clearTransient()
	for _, g in transient do
		g:Destroy()
	end
	table.clear(transient)
end

-- One frame of dirt on the film: a speck or a vertical scratch.
local function dirt()
	local size = workspace.CurrentCamera.ViewportSize
	if random:NextNumber() < 1 / 40 then
		local d = random:NextInteger(2, 6)
		local speck = Kit.frame({
			Size = UDim2.fromOffset(d, d),
			Position = UDim2.fromOffset(random:NextNumber(0, size.X), random:NextNumber(0, size.Y)),
			BackgroundColor3 = if random:NextNumber() < 0.7 then Color3.new(0, 0, 0) else Color3.new(1, 1, 1),
			BackgroundTransparency = random:NextNumber(0.3, 0.6),
			ZIndex = 2,
			Parent = dustLayer,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = speck })
		table.insert(transient, speck)
	end
	if random:NextNumber() < 1 / 110 then
		local h = random:NextNumber(0.3, 0.9)
		local scratch = Kit.frame({
			Size = UDim2.new(0, 1, h, 0),
			Position = UDim2.new(random:NextNumber(0.05, 0.95), 0, random:NextNumber(0, 1 - h), 0),
			BackgroundColor3 = if random:NextNumber() < 0.5 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
			BackgroundTransparency = 0.65,
			ZIndex = 2,
			Parent = dustLayer,
		})
		table.insert(transient, scratch)
	end
end

-- The speck field: no texture needed. Each frame every speck jumps to a new
-- place, with a new tone (white or black) and strength.
local function makeSpecks()
	local holder = Kit.frame({ Name = "Specks", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
	for i = 1, SPECKS[3] do
		local s = Instance.new("Frame")
		s.Name = "S"
		s.BorderSizePixel = 0
		s.Size = UDim2.fromOffset(1, 1)
		s.BackgroundTransparency = 1
		s.ZIndex = 1
		s.Parent = holder
		specks[i] = s
	end
end

local function scatter(alpha: number)
	local access = Registry.AccessibilityController
	local count = SPECKS[if access then access:Quality() else 2] or SPECKS[2]
	local size = workspace.CurrentCamera.ViewportSize
	for i, s in specks do
		if i > count or alpha <= 0.005 then
			s.Visible = false
		else
			s.Visible = true
			local px = if random:NextNumber() < 0.25 then 2 else 1
			s.Size = UDim2.fromOffset(px, px)
			s.Position = UDim2.fromOffset(random:NextInteger(0, math.max(1, size.X)), random:NextInteger(0, math.max(1, size.Y)))
			local light = random:NextNumber() < 0.5
			s.BackgroundColor3 = if light then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			-- a speck is a single pixel: it must be stronger than a texture's
			-- grain to read (the field is sparse)
			s.BackgroundTransparency = 1 - math.clamp(alpha * 3 * random:NextNumber(0.7, 1.4), 0, 0.85)
		end
	end
end

local function frame()
	clearTransient()
	local on = enabled()
	local intensity = math.clamp(State.settings.grainIntensity or 0.5, 0, 1)
	local alpha = if on then math.clamp(amount() * intensity * 0.5, 0, 0.6) else 0
	for _, label in layers do
		label.Visible = alpha > 0.005
		label.ImageTransparency = 1 - alpha
		label.Position = UDim2.fromOffset(-random:NextInteger(0, TILE), -random:NextInteger(0, TILE))
	end
	if mode == "specks" then
		scatter(alpha)
	end
	if on and intensity > 0 then
		dirt()
	end
	flicker.Brightness = if on and not State.settings.reducedEffects then random:NextNumber(-0.01, 0.01) * intensity * 2 else 0
	-- gate weave: a few hundredths of a degree, a new position each frame
	if on and not State.settings.reduceMotion then
		local t = os.clock()
		weave = CFrame.Angles(math.rad(math.noise(t * 0.9, 1.3) * 0.05), math.rad(math.noise(t * 0.9, 7.1) * 0.05), 0)
	else
		weave = CFrame.new()
	end
	-- the old lens darkens its corners a little more; a total blackout closes in
	local effects = Registry.EffectsController
	if effects and effects.SetFilmVignette then
		local blackout = Workspace:GetAttribute("Blackout")
		local deep = type(blackout) == "number" and blackout >= 4
		effects:SetFilmVignette(if on then (if deep then 0.22 else 0.06) else 0)
	end
end

-- A scare: the grain jumps for `duration` seconds.
function FilmController:Spike(duration: number, strength: number?)
	spikeUntil = os.clock() + duration
	spikeAmount = strength or 0.8
end

-- The gate weave, applied by CameraController after the shake.
function FilmController:Weave(): CFrame
	return weave
end

function FilmController:IsAvailable(): boolean
	return available
end

-- Where the grain comes from: "texture", "runtime", "specks" (or "off").
function FilmController:Mode(): string
	return mode
end

function FilmController:LayerCount(): number
	return #layers
end

function FilmController:Init()
	gui = Kit.screen("Film", 1, false)
	gui.IgnoreGuiInset = true
	for _, spec in { { "GrainLight", true }, { "GrainDark", false } } do
		local label = makeLayer(spec[1], spec[2])
		if label then
			table.insert(layers, label)
		end
	end
	if #layers == 0 then
		-- no uploaded sheets and no runtime texture: the speck field
		mode = "specks"
		makeSpecks()
		if not warned then
			warned = true
			print("[FilmController] film grain from specks (upload assets/film and set AssetIds.Film for finer grain)")
		end
	end
	available = true
	dustLayer = Kit.frame({ Name = "Dust", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = gui })
	flicker = Instance.new("ColorCorrectionEffect")
	flicker.Name = "FilmFlicker"
	flicker.Parent = Lighting
end

function FilmController:Start()
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 1 / FPS then
			acc %= 1 / FPS
			frame()
		end
	end)
end

return FilmController
