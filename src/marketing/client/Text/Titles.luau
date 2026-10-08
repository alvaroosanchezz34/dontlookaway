--[[
	Titles
	Cinematic text inside the safe frame (never part of the game's UI).
	Each title is built letter by letter so it can track (letters drifting
	apart), type itself out, or glitch single characters.

	Titles.show(tl, id, text, opts)   Titles.hide(tl, id, fadeOut)
	opts:
	  style     "title" (default) | "whisper" | "cctv" | "typewriter" | "warning"
	  position  "center" | "upper" | "lower" | UDim2
	  size      text height as a fraction of the frame height (0.045)
	  duration  seconds, then fades out (nil = until hidden)
	  fadeIn, fadeOut
	  tracking  { from = px, to = px } letter spacing animated over the title's life
	  glitch    0..1 chance per frame of a broken character
	  typeSpeed letters per second (typewriter reveal)
	  color, transparency
]]

local Runtime = require(script.Parent.Parent.Runtime)
local Screen = require(script.Parent.Parent.Effects.Screen)

local Titles = {}

local STYLES = {
	title = { font = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold), color = Color3.fromRGB(236, 232, 224), size = 0.05, tracking = 6 },
	whisper = { font = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Light, Enum.FontStyle.Italic), color = Color3.fromRGB(205, 200, 190), size = 0.03, tracking = 2 },
	cctv = { font = Font.new("rbxasset://fonts/families/RobotoMono.json"), color = Color3.fromRGB(230, 240, 230), size = 0.03, tracking = 2 },
	typewriter = { font = Font.new("rbxasset://fonts/families/SpecialElite.json"), color = Color3.fromRGB(226, 218, 200), size = 0.038, tracking = 1 },
	warning = { font = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold), color = Color3.fromRGB(220, 60, 52), size = 0.045, tracking = 5 },
}

local POSITIONS = {
	center = UDim2.fromScale(0.5, 0.5),
	upper = UDim2.fromScale(0.5, 0.2),
	lower = UDim2.fromScale(0.5, 0.8),
}

local GLYPHS = { "#", "%", "/", "\\", "?", "▓", "░", "0", "1", "_" }

type Title = { holder: Frame, letters: { TextLabel }, chars: { string }, opacity: number, opts: { [string]: any }, born: number, list: UIListLayout, shown: number }

local titles: { [string]: Title } = {}
local surfaces: { [string]: { part: BasePart, label: TextLabel } } = {}
local random = Random.new()

function Titles.reset()
	table.clear(titles)
	table.clear(surfaces)
end

local function chars(text: string): { string }
	local out = {}
	for _, code in utf8.codes(text) do
		table.insert(out, utf8.char(code))
	end
	return out
end

local function render(t: Title)
	local style = STYLES[t.opts.style or "title"] or STYLES.title
	local base = t.opts.transparency or 0
	for i, label in t.letters do
		local visible = i <= t.shown
		label.TextTransparency = if visible then base + (1 - base) * (1 - t.opacity) else 1
		label.TextStrokeTransparency = if visible then 0.4 + 0.6 * (1 - t.opacity) else 1
		label.TextColor3 = t.opts.color or style.color
	end
end

function Titles.show(tl: any, id: string, text: string, opts: { [string]: any }?)
	opts = opts or {}
	Titles.remove(id)
	local layer = Screen.textLayer()
	if not layer then
		return
	end
	local style = STYLES[opts.style or "title"] or STYLES.title
	local frameHeight = Screen.safeSize().Y
	local px = math.max(12, math.floor(frameHeight * (opts.size or style.size)))
	local holder = Instance.new("Frame")
	holder.Name = "Title_" .. id
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = if typeof(opts.position) == "UDim2" then opts.position else (POSITIONS[opts.position or "center"] or POSITIONS.center)
	holder.Size = UDim2.new(0.92, 0, 0, px * 1.4)
	holder.ZIndex = 11
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, if opts.tracking then opts.tracking.from else style.tracking)
	list.Parent = holder
	local letters = {}
	local cs = chars(text)
	for i, c in cs do
		local l = Instance.new("TextLabel")
		l.Name = "L" .. i
		l.LayoutOrder = i
		l.BackgroundTransparency = 1
		l.FontFace = style.font
		l.TextSize = px
		l.Text = if c == " " then " " else c
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.new(0, if c == " " then px * 0.35 else 0, 1, 0)
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		l.ZIndex = 11
		l.Parent = holder
		table.insert(letters, l)
	end
	holder.Parent = layer
	local t: Title = { holder = holder, letters = letters, chars = cs, opacity = 0, opts = opts, born = if tl then tl.clock else 0, list = list, shown = if opts.typeSpeed then 0 else #cs }
	titles[id] = t
	render(t)
	local fadeIn = opts.fadeIn or 0.4
	if tl and fadeIn > 0 then
		tl:span(fadeIn, "outQuad", function(a)
			t.opacity = a
			render(t)
		end, nil, "title.fade." .. id)
	else
		t.opacity = 1
		render(t)
	end
	if tl and opts.duration then
		local fadeOut = opts.fadeOut or 0.4
		tl:span(opts.duration, "linear", function(a)
			if a >= 1 then
				Titles.hide(tl, id, fadeOut)
			end
		end, nil, "title.life." .. id)
	end
end

function Titles.hide(tl: any, id: string, fadeOut: number?)
	local t = titles[id]
	if not t then
		return
	end
	if tl and fadeOut and fadeOut > 0 then
		local from = t.opacity
		tl:span(fadeOut, "inQuad", function(a)
			t.opacity = from * (1 - a)
			render(t)
			if a >= 1 then
				Titles.remove(id)
			end
		end, nil, "title.fade." .. id)
	else
		Titles.remove(id)
	end
end

function Titles.remove(id: string)
	local t = titles[id]
	if t then
		t.holder:Destroy()
		titles[id] = nil
	end
end

function Titles.removeAll()
	for id in titles do
		Titles.remove(id)
	end
end

-- Per-frame: tracking, typewriter, glitching characters.
function Titles.update(dt: number, clock: number)
	for _, t in titles do
		local age = clock - t.born
		local o = t.opts
		if o.tracking then
			local life = o.duration or 4
			local a = math.clamp(age / life, 0, 1)
			t.list.Padding = UDim.new(0, o.tracking.from + (o.tracking.to - o.tracking.from) * a)
		end
		if o.typeSpeed and t.shown < #t.letters then
			local want = math.floor(age * o.typeSpeed)
			if want > t.shown then
				t.shown = math.min(#t.letters, want)
				render(t)
			end
		end
		local chance = o.glitch or 0
		for i, label in t.letters do
			if chance > 0 and t.chars[i] ~= " " and random:NextNumber() < chance then
				label.Text = GLYPHS[random:NextInteger(1, #GLYPHS)]
			else
				label.Text = t.chars[i]
			end
		end
	end
end

------------------------------------------------------------------------------------
-- Text written on a surface in the world (a mirror, a wall)
------------------------------------------------------------------------------------

--[[
	Titles.surface(id, cf, size, opts) creates a sheet (local part) at `cf`
	(its front face toward the viewer) with an empty label; Titles.write sets
	its text. opts: color, font, transparency (how much the wall shows through).
]]
function Titles.surface(id: string, cf: CFrame, size: Vector2, opts: { [string]: any }?)
	opts = opts or {}
	Titles.removeSurface(id)
	local part = Instance.new("Part")
	part.Name = "Writing_" .. id
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
	gui.LightInfluence = opts.lightInfluence or 0.8
	gui.PixelsPerStud = 60
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = opts.font or Font.new("rbxasset://fonts/families/PermanentMarker.json")
	label.TextScaled = true
	label.TextColor3 = opts.color or Color3.fromRGB(120, 18, 16)
	label.TextTransparency = opts.transparency or 0.08
	label.Text = ""
	label.Parent = gui
	if opts.backing then
		-- a wall to write on where there is none (virtual set)
		local wall = Instance.new("Part")
		wall.Name = "Backing"
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanQuery = false
		wall.Size = Vector3.new(size.X + 6, size.Y + 6, 0.4)
		wall.CFrame = cf * CFrame.new(0, 0, 0.25)
		wall.Color = Color3.fromRGB(150, 146, 136)
		wall.Material = Enum.Material.Plaster
		wall.Parent = part
	end
	part.Parent = Runtime.folder()
	surfaces[id] = { part = part, label = label }
end

function Titles.write(id: string, text: string)
	local s = surfaces[id]
	if s then
		s.label.Text = text
	end
end

function Titles.removeSurface(id: string)
	local s = surfaces[id]
	if s then
		s.part:Destroy()
		surfaces[id] = nil
	end
end

function Titles.resetSurfaces()
	table.clear(surfaces)
end

return Titles
