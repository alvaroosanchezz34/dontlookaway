--[[
	Art
	Procedural, asset-free artwork: paintings, photographs and wall markings are
	composed from UI frames on SurfaceGuis. Each artwork is built with a normal
	variant "A" and an altered variant "B" that anomalies can switch to.
]]

local Build = require(script.Parent.Build)
local SeededRandom = require(game:GetService("ReplicatedStorage").Shared.Util.SeededRandom)

local Art = {}

local function frame(parent, x, y, w, h, color, extra)
	local props = {
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return Build.frame(parent, props)
end

local function round(f, scale)
	Build.corner(f, scale or 0.5)
	return f
end

local PALETTES = {
	{ sky = { Color3.fromRGB(58, 64, 70), Color3.fromRGB(112, 108, 92) }, land = Color3.fromRGB(52, 58, 44), dark = Color3.fromRGB(26, 28, 24) },
	{ sky = { Color3.fromRGB(40, 44, 58), Color3.fromRGB(96, 90, 100) }, land = Color3.fromRGB(44, 46, 50), dark = Color3.fromRGB(20, 20, 26) },
	{ sky = { Color3.fromRGB(86, 74, 60), Color3.fromRGB(150, 128, 96) }, land = Color3.fromRGB(70, 60, 42), dark = Color3.fromRGB(34, 28, 22) },
	{ sky = { Color3.fromRGB(70, 78, 80), Color3.fromRGB(132, 136, 128) }, land = Color3.fromRGB(60, 70, 62), dark = Color3.fromRGB(28, 32, 30) },
}

local function landscape(container, rng, altered)
	local pal = PALETTES[rng:Int(1, #PALETTES)]
	local sky = frame(container, 0, 0, 1, 0.65, pal.sky[1])
	Build.gradient(sky, pal.sky[1], pal.sky[2], 90)
	local hillA = round(frame(container, -0.2, 0.5, 0.9, 0.7, pal.land), 0.5)
	hillA.ZIndex = 2
	local hillB = round(frame(container, 0.35, 0.56, 1, 0.7, pal.land:Lerp(pal.dark, 0.35)), 0.5)
	hillB.ZIndex = 3
	local ground = frame(container, 0, 0.78, 1, 0.22, pal.land:Lerp(pal.dark, 0.5))
	ground.ZIndex = 4
	-- a lone tree
	local tx = rng:Number(0.15, 0.75)
	local trunk = frame(container, tx, 0.42, 0.02, 0.2, pal.dark)
	trunk.ZIndex = 5
	local crown = round(frame(container, tx - 0.06, 0.32, 0.14, 0.14, pal.dark:Lerp(pal.land, 0.3)), 0.5)
	crown.ZIndex = 5
	if altered then
		-- a tall, thin figure stands on the far hill, facing out of the painting
		local fx = if tx > 0.45 then rng:Number(0.12, 0.3) else rng:Number(0.62, 0.85)
		local body = frame(container, fx, 0.4, 0.018, 0.2, Color3.fromRGB(8, 8, 8))
		body.ZIndex = 6
		local head = round(frame(container, fx - 0.006, 0.37, 0.03, 0.04, Color3.fromRGB(8, 8, 8)), 0.5)
		head.ZIndex = 6
	end
end

local function portrait(container, rng, altered)
	local bg = rng:Pick({ Color3.fromRGB(48, 40, 36), Color3.fromRGB(36, 42, 44), Color3.fromRGB(56, 50, 40) })
	local back = frame(container, 0, 0, 1, 1, bg)
	Build.gradient(back, bg:Lerp(Color3.new(1, 1, 1), 0.08), bg:Lerp(Color3.new(0, 0, 0), 0.4), 45)
	-- chair back
	local chair = round(frame(container, 0.22, 0.45, 0.56, 0.6, Color3.fromRGB(58, 30, 26)), 0.15)
	chair.ZIndex = 2
	if not altered then
		local suit = rng:Pick({ Color3.fromRGB(26, 26, 30), Color3.fromRGB(40, 36, 30), Color3.fromRGB(30, 34, 40) })
		local body = round(frame(container, 0.26, 0.6, 0.48, 0.5, suit), 0.3)
		body.ZIndex = 3
		local neck = frame(container, 0.45, 0.48, 0.1, 0.14, Color3.fromRGB(150, 124, 106))
		neck.ZIndex = 3
		local head = round(frame(container, 0.37, 0.24, 0.26, 0.3, Color3.fromRGB(160, 132, 112)), 0.5)
		head.ZIndex = 4
		local hair = round(frame(container, 0.36, 0.2, 0.28, 0.13, Color3.fromRGB(40, 32, 26)), 0.5)
		hair.ZIndex = 5
		local collar = frame(container, 0.44, 0.6, 0.12, 0.08, Color3.fromRGB(200, 196, 186))
		collar.ZIndex = 4
	else
		-- the sitter has left. Only a dent remains in the chair.
		local dent = round(frame(container, 0.34, 0.6, 0.32, 0.36, Color3.fromRGB(44, 22, 20)), 0.4)
		dent.ZIndex = 3
	end
end

local function sea(container, rng, altered)
	local sky = frame(container, 0, 0, 1, 0.5, Color3.fromRGB(70, 76, 84))
	Build.gradient(sky, Color3.fromRGB(42, 46, 56), Color3.fromRGB(104, 106, 108), 90)
	local water = frame(container, 0, 0.5, 1, 0.5, Color3.fromRGB(34, 44, 52))
	Build.gradient(water, Color3.fromRGB(46, 56, 64), Color3.fromRGB(18, 24, 30), 90)
	local moon = round(frame(container, rng:Number(0.15, 0.7), 0.12, 0.09, 0.12, Color3.fromRGB(206, 204, 190)), 0.5)
	moon.ZIndex = 2
	for i = 1, 3 do
		local wave = frame(container, rng:Number(0, 0.6), 0.55 + i * 0.1, rng:Number(0.2, 0.4), 0.01, Color3.fromRGB(90, 100, 108))
		wave.ZIndex = 2
	end
	if altered then
		local door = frame(container, rng:Number(0.35, 0.6), 0.36, 0.07, 0.17, Color3.fromRGB(12, 12, 12))
		door.ZIndex = 3
		local light = frame(door, 0.1, 0.1, 0.8, 0.8, Color3.fromRGB(214, 208, 180))
		light.ZIndex = 4
		light.BackgroundTransparency = 0.6
	end
end

local function house(container, rng, altered)
	local sky = frame(container, 0, 0, 1, 1, Color3.fromRGB(30, 34, 44))
	Build.gradient(sky, Color3.fromRGB(24, 26, 36), Color3.fromRGB(70, 66, 70), 90)
	local ground = frame(container, 0, 0.8, 1, 0.2, Color3.fromRGB(30, 32, 26))
	ground.ZIndex = 2
	local wall = frame(container, 0.25, 0.4, 0.5, 0.42, Color3.fromRGB(80, 74, 66))
	wall.ZIndex = 3
	local roof = frame(container, 0.2, 0.3, 0.6, 0.12, Color3.fromRGB(46, 36, 32))
	roof.ZIndex = 3
	local lit = rng:Int(1, 4)
	for i = 1, 4 do
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local isLit = (i == lit) ~= altered
		local win = frame(container, 0.32 + col * 0.24, 0.46 + row * 0.18, 0.12, 0.12, if isLit then Color3.fromRGB(210, 180, 120) else Color3.fromRGB(20, 20, 22))
		win.ZIndex = 4
		if altered and i == lit then
			-- every window but one goes dark; in the remaining one, someone waits
			local who = round(frame(win, 0.3, 0.25, 0.4, 0.75, Color3.fromRGB(10, 10, 10)), 0.3)
			who.ZIndex = 5
		end
	end
end

local function abstract(container, rng, altered)
	local base = frame(container, 0, 0, 1, 1, Color3.fromRGB(96, 90, 80))
	Build.gradient(base, Color3.fromRGB(110, 104, 92), Color3.fromRGB(70, 66, 60), 30)
	local colors = { Color3.fromRGB(60, 70, 80), Color3.fromRGB(120, 96, 70), Color3.fromRGB(40, 40, 44), Color3.fromRGB(150, 140, 120) }
	local shapes = {}
	for i = 1, 5 do
		local s = {
			x = rng:Number(0.05, 0.6),
			y = rng:Number(0.05, 0.6),
			w = rng:Number(0.15, 0.4),
			h = rng:Number(0.15, 0.4),
			c = colors[(i - 1) % #colors + 1],
			r = rng:Chance(0.4),
		}
		table.insert(shapes, s)
	end
	if altered then
		-- one shape becomes a circle with something like a pupil
		shapes[1].r = true
		shapes[1].eye = true
	end
	for i, s in shapes do
		local f = frame(container, s.x, s.y, s.w, s.h, s.c)
		f.ZIndex = i + 1
		if s.r then
			Build.corner(f, 0.5)
		end
		if s.eye then
			local pupil = round(frame(f, 0.4, 0.4, 0.2, 0.2, Color3.fromRGB(10, 10, 10)), 0.5)
			pupil.ZIndex = i + 2
		end
	end
end

local KINDS = { landscape = landscape, portrait = portrait, sea = sea, house = house, abstract = abstract }
Art.PaintingKinds = { "landscape", "portrait", "sea", "house", "abstract" }

-- Builds both variants into the surface gui. Returns frames A, B.
function Art.painting(gui: SurfaceGui, rng, kind: string?)
	kind = kind or rng:Pick(Art.PaintingKinds)
	local builder = KINDS[kind] or landscape
	local seed = rng:Int(1, 1e6)
	local a = Build.frame(gui, { Name = "A", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local b = Build.frame(gui, { Name = "B", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	-- Both variants are built from the same seed so only the alteration differs.
	builder(a, SeededRandom.new(seed), false)
	builder(b, SeededRandom.new(seed), true)
	return a, b
end

-- Staff photograph: a row of figures. The altered variant has one more.
function Art.photo(gui: SurfaceGui, rng)
	local seed = rng:Int(1, 1e6)
	local function build(container, altered)
		local r = SeededRandom.new(seed)
		local bg = frame(container, 0, 0, 1, 1, Color3.fromRGB(150, 132, 104))
		Build.gradient(bg, Color3.fromRGB(170, 150, 118), Color3.fromRGB(110, 96, 74), 90)
		local count = r:Int(3, 5)
		local total = if altered then count + 1 else count
		local extraIndex = r:Int(1, total)
		for i = 1, total do
			local x = (i - 0.5) / total
			local isExtra = altered and i == extraIndex
			local tone = if isExtra then Color3.fromRGB(22, 20, 18) else Color3.fromRGB(70, 58, 46):Lerp(Color3.fromRGB(110, 92, 72), r:Number())
			local h = if isExtra then 0.62 else r:Number(0.42, 0.5)
			local w = 0.5 / total
			local body = round(frame(container, x - w / 2, 1 - h + 0.12, w, h, tone), 0.25)
			body.ZIndex = 2
			local head = round(frame(container, x - w * 0.3, 1 - h + 0.02, w * 0.6, 0.14, if isExtra then tone else Color3.fromRGB(176, 152, 120)), 0.5)
			head.ZIndex = 3
		end
		local fade = frame(container, 0, 0, 1, 1, Color3.fromRGB(200, 180, 140))
		fade.BackgroundTransparency = 0.82
		fade.ZIndex = 6
	end
	local a = Build.frame(gui, { Name = "A", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local b = Build.frame(gui, { Name = "B", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	build(a, false)
	build(b, true)
	return a, b
end

-- Symbols used by the symbol puzzle. Drawn with frames so no font glyphs are needed.
Art.Symbols = { "CIRCLE", "RING", "SQUARE", "DIAMOND", "CROSS", "BARS" }

function Art.symbol(parent: GuiObject, symbol: string, color: Color3, zIndex: number?)
	local z = zIndex or 2
	local holder = Build.frame(parent, { Name = "Symbol", Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), BackgroundTransparency = 1, ZIndex = z })
	if symbol == "CIRCLE" then
		local f = frame(holder, 0.1, 0.1, 0.8, 0.8, color, { ZIndex = z })
		Build.corner(f, 0.5)
	elseif symbol == "RING" then
		local f = frame(holder, 0.1, 0.1, 0.8, 0.8, color, { ZIndex = z, BackgroundTransparency = 1 })
		Build.corner(f, 0.5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 6
		stroke.Parent = f
	elseif symbol == "SQUARE" then
		frame(holder, 0.15, 0.15, 0.7, 0.7, color, { ZIndex = z })
	elseif symbol == "DIAMOND" then
		frame(holder, 0.2, 0.2, 0.6, 0.6, color, { ZIndex = z, Rotation = 45 })
	elseif symbol == "CROSS" then
		frame(holder, 0.42, 0.05, 0.16, 0.9, color, { ZIndex = z, Rotation = 45 })
		frame(holder, 0.42, 0.05, 0.16, 0.9, color, { ZIndex = z, Rotation = -45 })
	elseif symbol == "BARS" then
		for i = 0, 2 do
			frame(holder, 0.1, 0.12 + i * 0.3, 0.8, 0.14, color, { ZIndex = z })
		end
	end
	return holder
end

return Art
