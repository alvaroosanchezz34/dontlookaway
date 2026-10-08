--[[
	Eye
	THE EYE, the campaign's symbol. The project has no eye asset of its own
	(only the round "eye" an altered painting grows, Map/Art.luau), so this
	draws one in the same language: flat shapes, no textures, no uploads.
	Sickly sclera, a dark ringed iris, a pupil that dilates, a wet highlight,
	and two lids that close over it.

	Two modes, same drawing:
	  world   a billboard in the scene (behind a door, at the end of a corridor,
	          in the dark of a room). Always turned to the camera.
	  screen  full-frame close-up on the safe frame (black-screen scenes).

	Eye.show(opts)  Eye.hide(fade)  Eye.blink(duration)
	Eye.lookAt(target | "camera")    Eye.setIntensity(n)  Eye.setScale(n)
	Eye.setOpacity(n)  Eye.setPosition(pos)  Eye.setPupil(size)
	Animated values are driven by the scene timeline (Eye.update).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Runtime = require(script.Parent.Parent.Runtime)
local Screen = require(script.Parent.Screen)
local Format = require(script.Parent.Parent.Utilities.Format)
local Config = require(ReplicatedStorage:WaitForChild("Marketing"):WaitForChild("MarketingConfig"))

local Eye = {}

type State = {
	mode: string,
	holder: Instance?,
	part: BasePart?,
	gui: any,
	group: GuiObject?,
	iris: Frame?,
	pupil: Frame?,
	lidTop: GuiObject?,
	lidBottom: GuiObject?,
	photo: boolean,
	anchor: Vector3?, -- "anchored" mode: a world point the on-screen eye is pinned to
	brightness: number?,
	glow: PointLight?,
	opacity: number,
	open: number, -- 1 = open, 0 = shut
	pupilSize: number,
	look: Vector2, -- -1..1 offset of the iris
	lookTarget: any,
	drift: boolean,
	scale: number,
	intensity: number,
}

local state: State? = nil

local function corner(f: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = f
end

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

-- Draw the eye into `parent` (fills it; keep it about 2:1).
local function draw(parent: Instance)
	local group = Instance.new("CanvasGroup")
	group.Name = "Eye"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 1
	group.Parent = parent
	-- sclera: an almond made from an ellipse, darker and bloodshot at the edges
	local sclera = frame(group, "Sclera", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.62), BackgroundColor3 = Color3.fromRGB(214, 206, 188), ClipsDescendants = true })
	corner(sclera, 0.5)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 70, 62)), ColorSequenceKeypoint.new(0.28, Color3.fromRGB(214, 206, 188)), ColorSequenceKeypoint.new(0.72, Color3.fromRGB(214, 206, 188)), ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 70, 62)) })
	g.Parent = sclera
	local random = Random.new(7)
	for i = 1, 7 do
		local side = if i % 2 == 0 then 0.02 else 0.78
		frame(sclera, "Vein" .. i, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(side + random:NextNumber(0, 0.06), random:NextNumber(0.25, 0.75)), Size = UDim2.new(random:NextNumber(0.1, 0.2), 0, 0, 2), Rotation = random:NextNumber(-25, 25), BackgroundColor3 = Color3.fromRGB(150, 50, 46), BackgroundTransparency = 0.45 })
	end
	-- iris: dark, ringed, with a faint pale inner ring
	local iris = frame(sclera, "Iris", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 1.05), BackgroundColor3 = Color3.fromRGB(52, 50, 44) })
	Instance.new("UIAspectRatioConstraint", iris).AspectRatio = 1
	corner(iris, 0.5)
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(12, 12, 10)
	ring.Thickness = 3
	ring.Parent = iris
	local ig = Instance.new("UIGradient")
	ig.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 112, 90)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(70, 66, 54)), ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 24, 20)) })
	ig.Rotation = 90
	ig.Parent = iris
	local pupil = frame(iris, "Pupil", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42), BackgroundColor3 = Color3.new(0, 0, 0) })
	corner(pupil, 0.5)
	frame(iris, "Glint", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.34, 0.3), Size = UDim2.fromScale(0.13, 0.13), BackgroundColor3 = Color3.fromRGB(255, 252, 240), BackgroundTransparency = 0.1 })
	corner(iris:FindFirstChild("Glint") :: Frame, 0.5)
	-- lids: dark skin closing from above and below
	-- (clipped to the eye's box, so open lids are simply out of frame)
	local lids = frame(group, "Lids", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.62), BackgroundTransparency = 1, ClipsDescendants = true })
	local lidTop = frame(lids, "LidTop", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1.1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 7) })
	corner(lidTop, 0.5)
	local lidBottom = frame(lids, "LidBottom", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1.1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 7) })
	corner(lidBottom, 0.5)
	return group, iris, pupil, lidTop, lidBottom
end

------------------------------------------------------------------------------------
-- The photographic eye: layered images from tools/gen_eye.py (assets/marketing/eye),
-- used as soon as their ids are in MarketingConfig.EyeImages.
------------------------------------------------------------------------------------

-- geometry of the generated layers (1024x512 canvas): iris diameter and centre
local IRIS_W, IRIS_H = 336 / 1024, 336 / 512
local IRIS_Y = 256 / 512

local function imageUrl(key: string): string?
	local ids = Config.EyeImages or {}
	local id = ids[key]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. string.format("%d", id)
	end
	return nil
end

local failedImages: { [string]: string } = {}

function Eye.photographic(): boolean
	for _, key in { "sclera", "iris", "pupil", "socket" } do
		local url = imageUrl(key)
		if not url or failedImages[url] then
			return false
		end
	end
	return true
end

--[[
	Load the eye layers (and any extra urls) before they are needed, and report
	in the Output what Roblox could and could not load. A layer that fails makes
	the eye fall back to the drawn one, so it never just disappears.
]]
function Eye.preload(extra: { string }?)
	local urls = {}
	for _, key in { "sclera", "iris", "pupil", "glint", "lidTop", "lidBottom", "socket" } do
		local url = imageUrl(key)
		if url then
			table.insert(urls, url)
		end
	end
	for _, url in (extra or {}) :: { string } do
		table.insert(urls, url)
	end
	if #urls == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local loaded, failed = 0, {}
			game:GetService("ContentProvider"):PreloadAsync(urls, function(id, status)
				if status == Enum.AssetFetchStatus.Success then
					loaded += 1
				else
					failedImages[id] = status.Name
					table.insert(failed, id .. " (" .. status.Name .. ")")
				end
			end)
			if #failed == 0 then
				print(string.format("[Marketing] images: %d/%d loaded", loaded, #urls))
			else
				warn(string.format("[Marketing] images: %d/%d loaded. Failed: %s", loaded, #urls, table.concat(failed, ", ")))
			end
		end)
		if not ok then
			warn("[Marketing] could not preload images: " .. tostring(err))
		end
	end)
end

local function image(parent: Instance, name: string, key: string, z: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Size = UDim2.fromScale(1, 1)
	img.Image = imageUrl(key) or ""
	img.ScaleType = Enum.ScaleType.Stretch
	img.ZIndex = z
	img.Parent = parent
	return img
end

-- Plain frames and per-image transparency (no CanvasGroup: it does not render
-- reliably inside 3D guis, which is where the eye usually lives).
local function drawPhoto(parent: Instance)
	local group = Instance.new("Frame")
	group.Name = "Eye"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.ClipsDescendants = true
	group.Parent = parent
	image(group, "Sclera", "sclera", 1)
	local iris = Instance.new("Frame")
	iris.Name = "Iris"
	iris.BackgroundTransparency = 1
	iris.AnchorPoint = Vector2.new(0.5, 0.5)
	iris.Position = UDim2.fromScale(0.5, IRIS_Y)
	iris.Size = UDim2.fromScale(IRIS_W, IRIS_H)
	iris.ZIndex = 2
	iris.Parent = group
	image(iris, "IrisImage", "iris", 2)
	local pupil = image(iris, "Pupil", "pupil", 3)
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5, 0.5)
	if imageUrl("glint") then
		image(iris, "Glint", "glint", 4)
	end
	local lidTop, lidBottom = nil, nil
	if imageUrl("lidTop") and imageUrl("lidBottom") then
		lidTop = image(group, "LidTop", "lidTop", 5)
		lidBottom = image(group, "LidBottom", "lidBottom", 5)
	else
		-- no lid images: shut with the dark of the socket
		lidTop = frame(group, "LidTop", { BackgroundColor3 = Color3.fromRGB(8, 6, 6), Size = UDim2.fromScale(1, 0.5), ZIndex = 5 })
		lidBottom = frame(group, "LidBottom", { BackgroundColor3 = Color3.fromRGB(8, 6, 6), Size = UDim2.fromScale(1, 0.5), ZIndex = 5 })
	end
	image(group, "Socket", "socket", 6)
	return group, iris, pupil, lidTop, lidBottom
end

function Eye.reset()
	state = nil
end

function Eye.exists(): boolean
	return state ~= nil and state.group ~= nil and state.group.Parent ~= nil
end

--[[
	opts:
	  mode       "world" (default) or "screen"
	  position   Vector3 (world mode)
	  scale      studs across (world) or fraction of the frame width (screen)
	  intensity  glow 0..3 (world)
	  parent     screen-mode parent frame (the safe frame's FX layer)
]]
function Eye.create(opts: { [string]: any })
	Eye.destroy()
	local mode = opts.mode or "world"
	local s: State = {
		mode = mode,
		opacity = 0,
		open = 1,
		pupilSize = 0.42,
		look = Vector2.zero,
		lookTarget = "camera",
		drift = true,
		scale = opts.scale or (if mode == "screen" then 0.8 else 2.4),
		intensity = opts.intensity or 1,
		photo = Eye.photographic(),
		brightness = opts.brightness,
	}
	if mode == "screen" or mode == "anchored" then
		local holder = Instance.new("Frame")
		holder.Name = "ScreenEye"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.46)
		holder.Size = UDim2.fromScale(s.scale, s.scale * 0.5)
		holder.ZIndex = 4
		Instance.new("UIAspectRatioConstraint", holder).AspectRatio = 2
		holder.Parent = opts.parent
		s.holder = holder
		if mode == "anchored" then
			-- drawn on the screen layer (always renders) but pinned to a point in the
			-- world, sized to `scale` studs across: it moves with the camera like a
			-- real object, and dark surroundings hide that it is an overlay
			s.anchor = opts.position
			holder.ZIndex = 3
		end
		if s.photo then
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = drawPhoto(holder)
		else
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = draw(holder)
		end
	elseif mode == "surface" then
		-- a flat eye in the scene, facing the camera where it is created
		-- (in a doorway, behind glass): depth-sorted like any other surface
		local part = Instance.new("Part")
		part.Name = "TheEye"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(s.scale, s.scale * 0.5, 0.05)
		local at = opts.position or Workspace.CurrentCamera.CFrame.Position + Workspace.CurrentCamera.CFrame.LookVector * 20
		local face = opts.facing or Workspace.CurrentCamera.CFrame.Position
		part.CFrame = CFrame.lookAt(at, Vector3.new(face.X, at.Y, face.Z))
		local gui = Instance.new("SurfaceGui")
		gui.Name = "EyeGui"
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = opts.lightInfluence or 0
		gui.Brightness = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 160
		gui.ResetOnSpawn = false
		gui.Parent = part
		part.Parent = Runtime.folder()
		s.part, s.gui, s.holder = part, gui, gui
		if s.photo then
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = drawPhoto(gui)
		else
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = draw(gui)
		end
	else
		local part = Instance.new("Part")
		part.Name = "TheEye"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Position = opts.position or Workspace.CurrentCamera.CFrame.Position + Workspace.CurrentCamera.CFrame.LookVector * 20
		local gui = Instance.new("BillboardGui")
		gui.Name = "EyeGui"
		gui.Size = UDim2.fromScale(s.scale, s.scale * 0.5)
		gui.LightInfluence = 0
		gui.Brightness = 1
		gui.AlwaysOnTop = false
		gui.MaxDistance = 400
		gui.ResetOnSpawn = false
		gui.Parent = part
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 236, 210)
		glow.Range = 6
		glow.Brightness = 0
		glow.Shadows = false
		glow.Parent = part
		part.Parent = Runtime.folder()
		s.part, s.gui, s.glow, s.holder = part, gui, glow, gui
		if s.photo then
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = drawPhoto(gui)
		else
			s.group, s.iris, s.pupil, s.lidTop, s.lidBottom = draw(gui)
		end
	end
	state = s
	Eye.render()
end

function Eye.destroy()
	if state and state.holder then
		local holder = state.holder
		if state.part then
			state.part:Destroy()
		else
			holder:Destroy()
		end
	end
	state = nil
end

-- Push the state to the drawing (called every frame by the timeline).
function Eye.render()
	local s = state
	if not s or not s.group then
		return
	end
	local fade = 1 - math.clamp(s.opacity, 0, 1)
	if s.group:IsA("CanvasGroup") then
		s.group.GroupTransparency = fade
	else
		for _, d in s.group:GetDescendants() do
			if d:IsA("ImageLabel") then
				d.ImageTransparency = fade
				-- screen overlays are not touched by the scene's grade: dim them to sit in it
				if s.brightness and not s.gui then
					local b = math.clamp(s.brightness, 0, 1)
					d.ImageColor3 = Color3.new(b, b, math.min(1, b * 1.03))
				end
			elseif d:IsA("Frame") and (d.Name == "LidTop" or d.Name == "LidBottom") then
				d.BackgroundTransparency = fade
			end
		end
	end
	-- lids: open = 1 parts them, 0 meets in the middle
	local gap = math.clamp(s.open, 0, 1)
	if s.photo then
		-- the upper lid does the blinking; the lower one only rises a little
		if s.lidTop and s.lidBottom then
			s.lidTop.Position = UDim2.fromScale(0, -0.5 * gap)
			s.lidBottom.Position = UDim2.fromScale(0, 0.3 - 0.075 * (1 - gap))
		end
		if s.pupil then
			s.pupil.Size = UDim2.fromScale(s.pupilSize, s.pupilSize)
		end
		if s.iris then
			s.iris.Position = UDim2.fromScale(0.5 + s.look.X * 0.186, IRIS_Y + s.look.Y * 0.117)
		end
	else
		if s.lidTop and s.lidBottom then
			s.lidTop.Position = UDim2.fromScale(0.5, 0.52 - 0.52 * gap)
			s.lidBottom.Position = UDim2.fromScale(0.5, 0.48 + 0.52 * gap)
		end
		if s.pupil then
			s.pupil.Size = UDim2.fromScale(s.pupilSize, s.pupilSize)
		end
		if s.iris then
			s.iris.Position = UDim2.fromScale(0.5 + s.look.X * 0.22, 0.5 + s.look.Y * 0.18)
		end
	end
	if s.glow then
		s.glow.Brightness = math.max(0, s.intensity) * 0.6 * s.opacity * gap
	end
	if s.gui then
		s.gui.Brightness = s.brightness or (0.6 + s.intensity * 0.6)
		if s.gui:IsA("BillboardGui") then
			s.gui.Size = UDim2.fromScale(s.scale, s.scale * 0.5)
		elseif s.part then
			s.part.Size = Vector3.new(s.scale, s.scale * 0.5, 0.05)
		end
	end
end

local function pin(s: State)
	local holder = s.holder :: Frame
	local camera = Workspace.CurrentCamera
	local anchor = s.anchor :: Vector3
	local p = camera:WorldToViewportPoint(anchor)
	local edge = camera:WorldToViewportPoint(anchor + camera.CFrame.RightVector * (s.scale / 2))
	local width = math.abs(edge.X - p.X) * 2
	local safePos = Format.safeRect(Screen.getFormat(), camera.ViewportSize)
	holder.Visible = p.Z > 0
	holder.Position = UDim2.fromOffset(p.X - safePos.X, p.Y - safePos.Y)
	holder.Size = UDim2.fromOffset(width, width / 2)
end

-- Per-frame life: the iris finds its target and never stops moving a little.
function Eye.update(dt: number, clock: number)
	local s = state
	if not s then
		return
	end
	if s.anchor and s.holder then
		pin(s)
	end
	-- one diagnostic line, a moment after it appears
	if not (s :: any).reported and s.holder then
		local born = (s :: any).born or clock
		;(s :: any).born = born
		if clock - born > 1.5 then
			(s :: any).reported = true
			local images, ready = 0, 0
			for _, d in s.holder:GetDescendants() do
				if d:IsA("ImageLabel") then
					images += 1
					local okLoaded, isLoaded = pcall(function()
						return d.IsLoaded
					end)
					if okLoaded and isLoaded then
						ready += 1
					end
				end
			end
			local okAbs, absPos, absSize = pcall(function()
				local h = s.holder :: any
				return h.AbsolutePosition, h.AbsoluteSize
			end)
			print(string.format("[Marketing] eye (%s, %s): %s, %d/%d image layers loaded, opacity %.2f", s.mode, if s.photo then "photographic" else "drawn",
				if okAbs then string.format("on screen at %d,%d size %dx%d", absPos.X, absPos.Y, absSize.X, absSize.Y) else "position unknown",
				ready, images, s.opacity))
		end
	end
	local want = Vector2.zero
	local target = s.lookTarget
	if target == "follow" and s.anchor then
		-- it watches the camera move: where the camera is, seen from the eye
		local cam = Workspace.CurrentCamera.CFrame
		local basis = (s :: any).basis or cam
		;(s :: any).basis = basis
		local rel = basis:VectorToObjectSpace(cam.Position - (s.anchor :: Vector3))
		local dist = math.max(rel.Magnitude, 1)
		want = Vector2.new(math.clamp(rel.X / dist * 2.6, -1, 1), math.clamp(-rel.Y / dist * 2.6, -1, 1))
	elseif typeof(target) == "Vector2" then
		want = target
	elseif s.mode == "world" and s.part and typeof(target) == "Vector3" then
		local cam = Workspace.CurrentCamera.CFrame
		local dir = target - s.part.Position
		if dir.Magnitude > 0.01 then
			dir = dir.Unit
			want = Vector2.new(dir:Dot(cam.RightVector), -dir:Dot(cam.UpVector))
		end
	end
	if s.drift then
		want += Vector2.new(math.noise(clock * 0.7, 1.7) * 0.18, math.noise(clock * 0.6, 4.2) * 0.12)
	end
	-- it follows slowly (and so keeps moving a moment after the camera stops)
	local rate = if target == "follow" then 2.2 else 7
	s.look = s.look:Lerp(Vector2.new(math.clamp(want.X, -1, 1), math.clamp(want.Y, -1, 1)), math.min(1, dt * rate))
	Eye.render()
end

function Eye.get(): State?
	return state
end

function Eye.setOpacity(v: number)
	if state then
		state.opacity = v
		Eye.render()
	end
end

function Eye.setOpen(v: number)
	if state then
		state.open = v
		Eye.render()
	end
end

function Eye.setPupil(v: number)
	if state then
		state.pupilSize = math.clamp(v, 0.1, 0.9)
		Eye.render()
	end
end

function Eye.setIntensity(v: number)
	if state then
		state.intensity = v
		Eye.render()
	end
end

function Eye.setScale(v: number)
	if state then
		state.scale = v
		if state.mode == "screen" and state.holder then
			(state.holder :: Frame).Size = UDim2.fromScale(v, v * 0.5)
		end
		Eye.render()
	end
end

function Eye.setPosition(pos: any)
	if not state then
		return
	end
	if state.part and typeof(pos) == "Vector3" then
		state.part.Position = pos
	elseif state.mode == "screen" and state.holder and typeof(pos) == "UDim2" then
		(state.holder :: Frame).Position = pos
	end
end

-- "camera" (straight at the viewer), a Vector3 (world), a Vector2 (-1..1), or nil.
function Eye.lookAt(target: any, drift: boolean?)
	if not state then
		return
	end
	state.lookTarget = if target == "camera" or target == nil then Vector2.zero else target
	if drift ~= nil then
		state.drift = drift
	end
end

return Eye
