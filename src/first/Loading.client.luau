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
local root = new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0, Parent = gui })
-- authored for 1080p, scaled for phones and TVs
local scale = new("UIScale", { Parent = root })
local function rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		local v = camera.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 1920, v.Y / 1080) * (if v.Y < 600 then 1.25 else 1), 0.5, 1.5)
	end
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- a door left ajar in the dark: a thin slit of light behind the title,
-- breathing very slowly
local slit = new("Frame", { Size = UDim2.new(0, 4, 0.62, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), BackgroundColor3 = Color3.fromRGB(92, 88, 80), BackgroundTransparency = 0.55, Parent = root })
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.2), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 1) }), Parent = slit })
local spill = new("Frame", { Size = UDim2.new(0, 220, 0.4, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.6), BackgroundColor3 = Color3.fromRGB(60, 58, 54), BackgroundTransparency = 0.8, Parent = root })
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }), Parent = spill })

local title = new("TextLabel", { Text = "DON'T LOOK AWAY", Size = UDim2.new(1, 0, 0, 80), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamBlack), TextSize = 68, TextColor3 = BONE, TextTransparency = 1, Parent = root })
local overline = new("TextLabel", { Text = "ASHGROVE  ·  NIGHT SHIFT", Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, -58), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 15, TextColor3 = MUTED, TextTransparency = 1, Parent = root })

-- the sweep: no percentage, because the real total is unknown
local track = new("Frame", { Size = UDim2.fromOffset(320, 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 62), BackgroundColor3 = LINE, BackgroundTransparency = 0.3, ClipsDescendants = true, Parent = root })
local sweep = new("Frame", { Size = UDim2.new(0.25, 0, 1, 0), BackgroundColor3 = BONE, BackgroundTransparency = 0.2, Parent = track })

-- what is being prepared, line by line
local list = new("Frame", { Size = UDim2.fromOffset(460, 150), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.4, 86), BackgroundTransparency = 1, Parent = root })
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
local lines: { [string]: TextLabel } = {}
for i, phase in BootState.PHASES do
	lines[phase.id] = new("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.Gotham), TextSize = 16, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = i, Parent = list })
end

-- tips, apart from the phases and marked as such
new("TextLabel", { Text = "NOTE", Size = UDim2.new(1, 0, 0, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 13, TextColor3 = MUTED, Parent = root })
local tip = new("TextLabel", { Text = "", Size = UDim2.new(1, -80, 0, 28), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -78), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.SpecialElite), TextSize = 21, TextColor3 = DIM, TextTransparency = 1, Parent = root })

-- when something is wrong: what, and what you can do
local problem = new("Frame", { Size = UDim2.fromOffset(620, 110), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.4, 250), BackgroundTransparency = 1, Visible = false, Parent = root })
local problemText = new("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, FontFace = Font.fromEnum(Enum.Font.GothamMedium), TextSize = 17, TextColor3 = WARN, TextWrapped = true, Parent = problem })
local retry = new("TextButton", { Text = "RETRY", Size = UDim2.fromOffset(200, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), AutoButtonColor = true, BackgroundColor3 = BONE, TextColor3 = BLACK, FontFace = Font.fromEnum(Enum.Font.GothamBold), TextSize = 16, Selectable = true, Parent = problem })
new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = retry })

for _, label in { title, overline } do
	TweenService:Create(label, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
end

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
local conn = RunService.RenderStepped:Connect(function()
	if not alive then
		return
	end
	local t = os.clock()
	sweep.Position = UDim2.fromScale(((t * 0.35) % 1.25) - 0.25, 0)
	slit.Size = UDim2.new(0, 3 + 3 * (0.5 + 0.5 * math.sin(t * 0.4)), 0.62, 0)
	paint()
end)

task.spawn(function()
	local order = table.clone(TIPS)
	local rng = Random.new()
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
	task.wait(0.4)
	local fade = TweenService:Create(root, TweenInfo.new(1.1, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	alive = false
	conn:Disconnect()
	gui:Destroy()
end)
