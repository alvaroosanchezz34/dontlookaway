--[[
	Loading
	The first thing a player sees, from the moment the client starts. It
	stays while the client really prepares itself (BootState) and goes the
	moment everything is ready:

	  world     game.Loaded: the experience's content has arrived
	  systems   Client/Main says every controller ran Init and started
	  records   NetController says the player's record arrived
	  assets    here: the menu's sounds and the building's textures are
	            preloaded (ContentProvider:PreloadAsync), with a time limit:
	            an asset that fails or hangs never holds the screen
	  building  the server's MapReady (tonight's building is built)

	There is no percentage: the true total is unknown, so the bar is a slow
	sweep and each phase says what is being done, and only says it is done
	when it is. Each phase has a time limit; past it the game goes on and
	the phase finishes in the background (records, sounds, the building),
	or, if the systems themselves never start (the server is not answering),
	the screen says so and offers RETRY, which rejoins the experience.

	The NOTE lines are tips, shown apart from the phases and shuffled, never
	the same order twice. They hint at how to survive, never at what is in
	the building.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BootState = require(script.Parent:WaitForChild("BootState"))

local player = Players.LocalPlayer
if not BootState.claim("loadingScreen") then
	return
end

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local BLACK = Color3.fromRGB(6, 6, 7)
local BONE = Color3.fromRGB(232, 228, 220)
local DIM = Color3.fromRGB(168, 165, 158)
local MUTED = Color3.fromRGB(120, 120, 124)
local LINE = Color3.fromRGB(58, 58, 62)
local GOOD = Color3.fromRGB(190, 206, 190)
local WARN = Color3.fromRGB(214, 190, 140)

-- once everything is ready the title stays a little longer, and the screen
-- is never shown for less than this in all
local HOLD_AFTER_READY = 2.5
local MIN_SHOW = 8
local shownAt = os.clock()

local TIPS = {
	"Not every room is the same.",
	"If something changed, it changed while nobody was looking.",
	"Your light is worth more than you think.",
	"Report what changed. Only what changed.",
	"Stay where someone can see you.",
	"Read what the building leaves for you.",
	"Some doors are better left closed.",
	"When the lights fail, don't wander alone.",
}

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for k, v in props do
		(inst :: any)[k] = v
	end
	if inst:IsA("GuiObject") then
		(inst :: any).BorderSizePixel = 0
	end
	inst.Parent = parent
	return inst
end

------------------------------------------------------------------------------------
-- The screen
------------------------------------------------------------------------------------

local gui = new("ScreenGui", { Name = "Loading", DisplayOrder = 100, IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
-- a plain Frame (a CanvasGroup would render it all into a texture: blurry text)
local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0, Parent = gui })
-- the black covers the whole screen at any size; what is drawn on it lives on
-- a 1920x1080 stage, centred and scaled to fit (phones, ultrawide, TVs)
local stage = new("Frame", { Name = "Stage", Size = UDim2.fromOffset(1920, 1080), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Parent = root })
local scale = new("UIScale", { Parent = stage })
local function rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		if v.X > 1 and v.Y > 1 then
			scale.Scale = math.min(v.X / 1920, v.Y / 1080)
		end
	end
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
task.spawn(function()
	-- the camera's size is only known a moment after the client starts
	for _ = 1, 20 do
		task.wait(0.25)
		rescale()
	end
end)

-- the dark closes in from the edges (whole screen, not the stage)
local function edge(rotation: number, size: UDim2, position: UDim2, anchor: Vector2)
	local f = new("Frame", { Size = size, Position = position, AnchorPoint = anchor, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, Parent = root })
	new("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }), Parent = f })
end
edge(0, UDim2.fromScale(0.28, 1), UDim2.fromScale(0, 0), Vector2.zero)
edge(180, UDim2.fromScale(0.28, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0))
edge(90, UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), Vector2.zero)
edge(-90, UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 1), Vector2.new(0, 1))

-- a faint band of old video drifting down the screen
local band = new("Frame", { Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = Color3.fromRGB(150, 150, 140), BackgroundTransparency = 0.965, Parent = root })
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = band })

-- eyes in the dark: now and then, somewhere you weren't looking, two pale
-- points open, watch, blink once and are gone
local eyesHolder = new("Frame", { Size = UDim2.fromOffset(70, 20), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = stage })
local eyeParts = {}
for i, x in { 0, 46 } do
	local e = new("Frame", { Size = UDim2.fromOffset(9, 6), Position = UDim2.fromOffset(x + 8, 7), BackgroundColor3 = Color3.fromRGB(214, 214, 204), BackgroundTransparency = 1, Parent = eyesHolder })
	new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = e })
	eyeParts[i] = e
end

local title = new("TextLabel", { Text = "DON'T LOOK AWAY", Size = UDim2.new(1, 0, 0, 100), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamBlack), TextSize = 92, TextColor3 = BONE, TextTransparency = 1, Parent = stage })
-- its red shadow, a hair out of place: it slips now and then
local ghost = new("TextLabel", { Text = "DON'T LOOK AWAY", Size = UDim2.new(1, 0, 0, 100), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 3, 0.38, 2), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamBlack), TextSize = 92, TextColor3 = Color3.fromRGB(120, 18, 16), TextTransparency = 1, ZIndex = 0, Parent = stage })
local overline = new("TextLabel", { Text = "ASHGROVE OBSERVATION PROJECT  ·  NIGHT SHIFT", Size = UDim2.new(1, 0, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, -76), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 18, TextColor3 = MUTED, TextTransparency = 1, Parent = stage })
-- a line from the files, typed out
local epigraph = new("TextLabel", { Text = "", Size = UDim2.new(1, -200, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 74), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.SpecialElite), TextSize = 24, TextColor3 = DIM, Parent = stage })

-- the sweep: no percentage, because the real total is unknown
local track = new("Frame", { Size = UDim2.fromOffset(360, 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 118), BackgroundColor3 = LINE, BackgroundTransparency = 0.3, ClipsDescendants = true, Parent = stage })
local sweep = new("Frame", { Size = UDim2.new(0.25, 0, 1, 0), BackgroundColor3 = BONE, BackgroundTransparency = 0.2, Parent = track })

-- what is being prepared, line by line
local list = new("Frame", { Size = UDim2.fromOffset(620, 170), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.38, 140), BackgroundTransparency = 1, Parent = stage })
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
local lines: { [string]: TextLabel } = {}
for i, phase in BootState.PHASES do
	lines[phase.id] = new("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamMedium), TextSize = 19, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i, Parent = list })
end

-- tips, apart from the phases and marked as such
new("TextLabel", { Text = "NOTE", Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 15, TextColor3 = MUTED, Parent = stage })
local tip = new("TextLabel", { Text = "", Size = UDim2.new(1, -80, 0, 34), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.SpecialElite), TextSize = 26, TextColor3 = DIM, TextTransparency = 1, Parent = stage })

-- when something is wrong: what, and what you can do
local problem = new("Frame", { Size = UDim2.fromOffset(700, 120), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.38, 330), BackgroundTransparency = 1, Visible = false, Parent = stage })
local problemText = new("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamMedium), TextSize = 19, TextColor3 = WARN, TextWrapped = true, Parent = problem })
local retry = new("TextButton", { Text = "RETRY", Size = UDim2.fromOffset(220, 48), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), AutoButtonColor = true, BackgroundColor3 = BONE, TextColor3 = BLACK, FontFace = Font.fromEnum(Enum.Font.GothamBold), TextSize = 17, Selectable = true, Parent = problem })
new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = retry })

for _, label in { title, overline } do
	TweenService:Create(label, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
end
TweenService:Create(ghost, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { TextTransparency = 0.55 }):Play()

local MARK = { pending = "·", done = "✓", failed = "!", skipped = "–" }
local function paint()
	local t = os.clock()
	for _, phase in BootState.PHASES do
		local s, note = BootState.get(phase.id)
		local label = lines[phase.id]
		local text = phase.text
		if s == "active" then
			-- an honest "still working": the dots move, nothing counts up
			text ..= string.rep(".", 1 + math.floor(t * 2) % 3)
			label.TextColor3 = BONE
		elseif s == "done" then
			label.TextColor3 = GOOD
		elseif s == "failed" or s == "skipped" then
			label.TextColor3 = WARN
		else
			label.TextColor3 = MUTED
		end
		local mark = if s == "active" then "…" else MARK[s or "pending"] or "·"
		label.Text = mark .. "   " .. text .. (if note and (s == "failed" or s == "skipped" or s == "done") then "  —  " .. note else "")
	end
end

local alive = true
local rng = Random.new()
local conn = RunService.RenderStepped:Connect(function()
	if not alive then
		return
	end
	local t = os.clock()
	sweep.Position = UDim2.fromScale(((t * 0.35) % 1.25) - 0.25, 0)
	band.Position = UDim2.new(0, 0, (t * 0.045) % 1.2 - 0.1, 0)
	paint()
end)

-- the title is a sign that is failing: a dip now and then (never a flash),
-- its red shadow slipping with it
task.spawn(function()
	task.wait(2.5)
	while alive do
		task.wait(rng:NextNumber(2.5, 6))
		if not alive then
			break
		end
		for _ = 1, rng:NextInteger(1, 3) do
			title.TextTransparency = 0.45
			ghost.Position = UDim2.new(0.5, rng:NextInteger(-9, 9), 0.38, rng:NextInteger(-3, 3))
			task.wait(rng:NextNumber(0.04, 0.09))
			title.TextTransparency = 0
			task.wait(rng:NextNumber(0.05, 0.12))
		end
		ghost.Position = UDim2.new(0.5, 3, 0.38, 2)
	end
end)

-- the eyes: never in the same place, never on a beat
task.spawn(function()
	task.wait(rng:NextNumber(4, 6))
	while alive do
		local side = if rng:NextNumber() < 0.5 then rng:NextNumber(0.08, 0.26) else rng:NextNumber(0.74, 0.92)
		eyesHolder.Position = UDim2.fromScale(side, rng:NextNumber(0.25, 0.8))
		eyesHolder.Visible = true
		for _, e in eyeParts do
			e.Size = UDim2.fromOffset(9, 6)
			TweenService:Create(e, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.35 }):Play()
		end
		task.wait(rng:NextNumber(2.6, 3.6))
		-- a blink
		for _, e in eyeParts do
			TweenService:Create(e, TweenInfo.new(0.08), { Size = UDim2.fromOffset(9, 1) }):Play()
		end
		task.wait(0.14)
		for _, e in eyeParts do
			TweenService:Create(e, TweenInfo.new(0.1), { Size = UDim2.fromOffset(9, 6) }):Play()
		end
		task.wait(rng:NextNumber(0.8, 1.6))
		for _, e in eyeParts do
			TweenService:Create(e, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end
		task.wait(0.4)
		eyesHolder.Visible = false
		task.wait(rng:NextNumber(5, 9))
	end
end)

-- a line from the files, typed one key at a time
local EPIGRAPHS = {
	"They photographed the empty rooms. The rooms did not stay empty.",
	"Everything it does happens between one look and the next.",
	"Day 3. The staff photo has one more face than we have staff.",
	"Do not report the tall man in the stairwell.",
}
task.spawn(function()
	task.wait(1.8)
	local line = EPIGRAPHS[rng:NextInteger(1, #EPIGRAPHS)]
	for i = 1, #line do
		if not alive then
			return
		end
		epigraph.Text = string.sub(line, 1, i)
		task.wait(if string.sub(line, i, i) == " " then 0.07 else rng:NextNumber(0.03, 0.06))
	end
end)

task.spawn(function()
	local order = table.clone(TIPS)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local i = 0
	while alive do
		i = i % #order + 1
		tip.Text = order[i]
		TweenService:Create(tip, TweenInfo.new(0.8), { TextTransparency = 0 }):Play()
		task.wait(5.5)
		if not alive then
			break
		end
		TweenService:Create(tip, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		task.wait(0.9)
	end
end)

-- the sound of the place, once the game's sounds have arrived: a low drone
-- and a slow heart
local drone: Sound? = nil
local function startSound()
	pcall(function()
		local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared", 20)
		if not shared or not alive then
			return
		end
		local SoundFactory = require(shared:WaitForChild("SoundFactory"))
		local SoundService = game:GetService("SoundService")
		local d = SoundFactory.create("AmbientDrone", SoundService, { looped = true })
		if d then
			local target = d.Volume
			d.Volume = 0
			d:Play()
			TweenService:Create(d, TweenInfo.new(3), { Volume = target * 0.9 }):Play()
			drone = d
		end
		task.spawn(function()
			while alive do
				local h = SoundFactory.create("Heartbeat", SoundService, { volume = 0.25 })
				if h then
					h:Play()
					h.Ended:Once(function()
						h:Destroy()
					end)
				end
				task.wait(1.6)
			end
		end)
	end)
end

-- Everything on the screen fades out together (no CanvasGroup: each piece).
local function fadeOut(seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	TweenService:Create(root, info, { BackgroundTransparency = 1 }):Play()
	if drone then
		TweenService:Create(drone, info, { Volume = 0 }):Play()
	end
end

------------------------------------------------------------------------------------
-- The work this screen does itself, and the waiting for the rest
------------------------------------------------------------------------------------

-- Waits until `done()` or the phase's time limit. Returns true if done.
local function waitFor(id: string, done: () -> boolean): boolean
	local deadline = os.clock() + (BootState.TIMEOUT[id] or 20)
	while not done() and os.clock() < deadline do
		task.wait(0.1)
	end
	return done()
end

-- world: the experience's content
task.spawn(function()
	BootState.set("world", "active")
	if waitFor("world", function()
		return game:IsLoaded()
	end) then
		BootState.set("world", "done")
	else
		BootState.set("world", "failed", "some content is still arriving")
	end
end)

-- assets: the menu's sounds and the building's textures, with a time limit
task.spawn(function()
	while not game:IsLoaded() and alive do
		task.wait(0.1)
	end
	task.spawn(startSound)
	BootState.set("assets", "active")
	local list = {}
	local ok = pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local shared = ReplicatedStorage:WaitForChild("Shared", 20)
		if not shared then
			return
		end
		local AudioLibrary = require(shared:WaitForChild("Config"):WaitForChild("AudioLibrary"))
		local SoundFactory = require(shared:WaitForChild("SoundFactory"))
		for _, key in { "AmbientDrone", "AmbientAir", "AmbientRain", "AmbientHum", "MusicPad", "UIHover", "UIClick", "UIOpen", "UIBack", "TitleHit" } do
			local def = AudioLibrary.Sounds[key]
			local url = SoundFactory.custom(key) or (def and def.id)
			if url then
				local probe = Instance.new("Sound")
				probe.SoundId = url
				table.insert(list, probe)
			end
		end
		-- the building's surfaces (MaterialVariants): no pop-in in the menu
		table.insert(list, game:GetService("MaterialService"))
	end)
	if not ok or #list == 0 then
		BootState.set("assets", "failed", "the sound list could not be read")
		return
	end
	local finished, failedCount = false, 0
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list, function(_, status)
				if status == Enum.AssetFetchStatus.Failure then
					failedCount += 1
				end
			end)
		end)
		finished = true
	end)
	if waitFor("assets", function()
		return finished
	end) then
		BootState.set("assets", "done", if failedCount > 0 then string.format("%d could not load", failedCount) else nil)
	else
		BootState.set("assets", "skipped", "still loading, it will finish in play")
	end
end)

-- building: tonight's building, built by the server
task.spawn(function()
	BootState.set("building", "active")
	if waitFor("building", function()
		return Workspace:GetAttribute("MapReady") == true
	end) then
		BootState.set("building", "done")
	else
		BootState.set("building", "skipped", "it will be ready shortly")
	end
end)

-- records and systems are reported by the client's own code; the screen
-- only gives up on the records (the menu works without them)
task.spawn(function()
	if not waitFor("records", function()
		return BootState.isFinished("records")
	end) then
		BootState.set("records", "skipped", "your progress will appear shortly")
	end
end)

task.spawn(function()
	if waitFor("systems", function()
		return BootState.isFinished("systems")
	end) then
		return
	end
	-- the systems never started: the server is not answering
	problem.Visible = true
	problemText.Text = "The building isn't answering. You can keep waiting, or retry to rejoin."
end)

retry.Activated:Connect(function()
	retry.Text = "REJOINING…"
	retry.Active = false
	local ok = pcall(function()
		game:GetService("TeleportService"):Teleport(game.PlaceId, player)
	end)
	if not ok then
		retry.Text = "RETRY"
		retry.Active = true
		problemText.Text = "Couldn't rejoin from here. Leave and join the experience again."
	end
end)

-- leave once everything is really ready (and the systems have started)
task.spawn(function()
	while not (BootState.ready() and BootState.get("systems") == "done") do
		task.wait(0.1)
	end
	paint()
	-- a moment with the title on screen before it goes, never less than
	-- MIN_SHOW in all (the work itself decides when it is ready)
	task.wait(math.max(HOLD_AFTER_READY, MIN_SHOW - (os.clock() - shownAt)))
	fadeOut(1.8)
	task.wait(1.9)
	alive = false
	conn:Disconnect()
	if drone then
		drone:Destroy()
	end
	gui:Destroy()
end)
