--[[
	Scratch
	Words scratched into a surface while you watch: the same hand-drawn strokes
	as the scratched title (tools/gen_title.py), built from thin rotated frames
	on a SurfaceGui and revealed stroke by stroke on the scene clock. Each
	stroke is several jittered pale scratches over a smear of dark red.

	Scratch.surface(id, cf, size, opts)     a writing surface (front face = cf.LookVector)
	Scratch.write(tl, id, text, opts)       scratch a line of text into it
	  opts: line (0-based row), height (fraction of the surface height),
	        x (left edge, 0..1), strokeTime (s per stroke), onStroke(fn)
]]

local Runtime = require(script.Parent.Parent.Runtime)

local Scratch = {}

local function ellipse(cx: number, cy: number, rx: number, ry: number): { { number } }
	local pts = {}
	for i = 0, 22 do
		local a = -0.3 + 2 * math.pi * i / 22
		table.insert(pts, { cx + rx * math.cos(a), cy + ry * math.sin(a) })
	end
	return pts
end

-- glyph = { width, { strokes } }, unit box, y down
local GLYPHS: { [string]: any } = {
	D = { 0.62, { { { 0, 0 }, { 0, 1 } }, { { 0, 0.02 }, { 0.32, 0.04 }, { 0.56, 0.2 }, { 0.62, 0.5 }, { 0.55, 0.8 }, { 0.32, 0.97 }, { 0, 1 } } } },
	O = { 0.66, { ellipse(0.33, 0.5, 0.33, 0.5) } },
	N = { 0.62, { { { 0, 1 }, { 0, 0 } }, { { 0, 0 }, { 0.62, 1 } }, { { 0.62, 1 }, { 0.62, 0 } } } },
	["'"] = { 0.14, { { { 0.08, -0.02 }, { 0, 0.26 } } } },
	T = { 0.64, { { { -0.04, 0.02 }, { 0.68, -0.01 } }, { { 0.32, 0 }, { 0.31, 1 } } } },
	L = { 0.52, { { { 0, 0 }, { 0, 1 }, { 0.54, 0.98 } } } },
	K = { 0.62, { { { 0, 0 }, { 0, 1 } }, { { 0.6, 0 }, { 0.02, 0.56 } }, { { 0.16, 0.42 }, { 0.64, 1 } } } },
	A = { 0.68, { { { 0, 1 }, { 0.34, 0 }, { 0.68, 1 } }, { { 0.13, 0.64 }, { 0.55, 0.6 } } } },
	W = { 0.9, { { { 0, 0 }, { 0.2, 1 }, { 0.44, 0.32 }, { 0.66, 1 }, { 0.9, -0.02 } } } },
	Y = { 0.64, { { { 0, 0 }, { 0.33, 0.52 }, { 0.66, -0.02 } }, { { 0.33, 0.52 }, { 0.3, 1 } } } },
	E = { 0.56, { { { 0.56, 0 }, { 0, 0 }, { 0, 1 }, { 0.56, 1 } }, { { 0, 0.5 }, { 0.44, 0.5 } } } },
	H = { 0.6, { { { 0, 0 }, { 0, 1 } }, { { 0.6, 0 }, { 0.6, 1 } }, { { 0, 0.5 }, { 0.6, 0.5 } } } },
	R = { 0.6, { { { 0, 1 }, { 0, 0 }, { 0.42, 0.02 }, { 0.58, 0.18 }, { 0.42, 0.46 }, { 0, 0.48 } }, { { 0.2, 0.48 }, { 0.6, 1 } } } },
	S = { 0.58, { { { 0.56, 0.08 }, { 0.3, 0 }, { 0.04, 0.12 }, { 0.1, 0.4 }, { 0.48, 0.58 }, { 0.56, 0.86 }, { 0.28, 1 }, { 0, 0.9 } } } },
	I = { 0.12, { { { 0.06, 0 }, { 0.06, 1 } } } },
	["?"] = { 0.5, { { { 0, 0.15 }, { 0.2, 0 }, { 0.45, 0.06 }, { 0.48, 0.3 }, { 0.25, 0.5 }, { 0.24, 0.72 } }, { { 0.24, 0.92 }, { 0.25, 1 } } } },
	["."] = { 0.14, { { { 0.05, 0.92 }, { 0.07, 1 } } } },
	["-"] = { 0.4, { { { 0, 0.55 }, { 0.4, 0.52 } } } },
	[" "] = { 0.36, {} },
}

type Surface = { part: BasePart, gui: SurfaceGui, canvas: Frame, size: Vector2 }

local surfaces: { [string]: Surface } = {}
local random = Random.new()

function Scratch.reset()
	table.clear(surfaces)
end

function Scratch.surface(id: string, cf: CFrame, size: Vector2, opts: { [string]: any }?)
	opts = opts or {}
	local old = surfaces[id]
	if old then
		old.part:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = "Scratch_" .. id
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(size.X, size.Y, 0.05)
	part.CFrame = cf
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 90
	gui.LightInfluence = opts.lightInfluence or 1 -- scratches live in the scene's light
	gui.Brightness = opts.brightness or 1.6
	gui.Parent = part
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.Parent = gui
	part.Parent = Runtime.folder()
	surfaces[id] = { part = part, gui = gui, canvas = canvas, size = size }
end

-- One straight scratch between two points (in surface fractions).
local function line(canvas: Frame, a: Vector2, b: Vector2, px: Vector2, width: number, color: Color3, alpha: number): Frame
	local pa = Vector2.new(a.X * px.X, a.Y * px.Y)
	local pb = Vector2.new(b.X * px.X, b.Y * px.Y)
	local mid = (pa + pb) / 2
	local d = pb - pa
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(mid.X, mid.Y)
	f.Size = UDim2.fromOffset(d.Magnitude + width * 0.6, width)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	f.Visible = false
	f.Parent = canvas
	return f
end

--[[
	Builds every stroke of `text` (hidden) and reveals them in order on the
	timeline. Returns the total time it takes.
]]
function Scratch.write(tl: any, id: string, text: string, opts: { [string]: any }?): number
	opts = opts or {}
	local s = surfaces[id]
	if not s then
		return 0
	end
	local px = s.size * 90 -- pixels of the canvas (PixelsPerStud)
	local h = opts.height or 0.22 -- letter height, fraction of the surface height
	local hx = h * s.size.Y / s.size.X -- the same height in fractions of the width
	local x = opts.x or 0.08
	if opts.center then
		local w = 0
		for _, code in utf8.codes(string.upper(text)) do
			local g = GLYPHS[utf8.char(code)] or GLYPHS[" "]
			w += (g[1] + 0.12) * hx
		end
		x = 0.5 - (w - 0.12 * hx) / 2
	end
	local top = (opts.top or 0.08) + (opts.line or 0) * h * 1.25
	local strokes: { { Frame } } = {}
	for _, code in utf8.codes(string.upper(text)) do
		local ch = utf8.char(code)
		local g = GLYPHS[ch] or GLYPHS[" "]
		local lean = random:NextNumber(0.08, 0.18)
		local size = random:NextNumber(0.92, 1.06)
		for _, stroke in g[2] do
			local frames = {}
			-- under-smear (dark red, wide) then 3 pale scratches, each jittered
			for pass = 1, 4 do
				local jitter = if pass == 1 then 0.012 else 0.006
				local ox, oy = random:NextNumber(-jitter, jitter), random:NextNumber(-jitter, jitter)
				for i = 1, #stroke - 1 do
					local p0, p1 = stroke[i], stroke[i + 1]
					local function at(p)
						local u, v = p[1], p[2]
						return Vector2.new(x + (u + (1 - v) * lean) * hx * size + ox, top + v * h * size + oy)
					end
					local a, b = at(p0), at(p1)
					if pass == 1 then
						table.insert(frames, line(s.canvas, a, b, px, h * px.Y * 0.11, Color3.fromRGB(96, 8, 8), 0.55))
					else
						local tone = random:NextInteger(170, 236)
						table.insert(frames, line(s.canvas, a, b, px, random:NextNumber(1.5, 3.5), Color3.fromRGB(tone, tone - 6, tone - 10), random:NextNumber(0.6, 0.95)))
					end
				end
			end
			table.insert(strokes, frames)
		end
		x += (g[1] + 0.12) * hx * size
	end
	local per = opts.strokeTime or 0.16
	local start = if tl then tl.clock else 0
	for i, frames in strokes do
		if tl then
			tl:span(per, "linear", function(a)
				-- reveal this stroke's segments progressively
				local n = math.ceil(#frames * a)
				for k = 1, n do
					frames[k].Visible = true
				end
				if a >= 1 and opts.onStroke then
					opts.onStroke(i)
				end
			end, start + (i - 1) * per)
		else
			for _, f in frames do
				f.Visible = true
			end
		end
	end
	return #strokes * per
end

function Scratch.clear(id: string)
	local s = surfaces[id]
	if s then
		s.canvas:ClearAllChildren()
	end
end

return Scratch
