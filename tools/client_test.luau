--[[
	Client runtime test (Lune).
	Runs every client controller's Init/Start against stubbed engine services,
	drives the per-frame loops, fires every server->client message the game uses
	and opens every menu panel, so UI construction and controller logic execute
	for real (Lune validates every property name and type that is set).

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/client_test.luau build/test.rbxlx
]]

local env = require("./lib/env")
local stdio = require("@lune/stdio")
local process = require("@lune/process")
local task = require("@lune/task")

local roblox = env.roblox
local game = env.game
local workspace = env.workspace
local requireModule = env.requireModule
local makeSignal = env.makeSignal
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame

local failures, checks = 0, 0
local function check(cond, message)
	checks += 1
	if not cond then
		failures += 1
		stdio.write(stdio.color("red") .. "FAIL " .. stdio.color("reset") .. tostring(message) .. "\n")
	end
end
local function section(name)
	stdio.write(stdio.color("cyan") .. "== " .. name .. stdio.color("reset") .. "\n")
end

------------------------------------------------------------------------------------
-- Signals on instances (events are not simulated by Lune)
------------------------------------------------------------------------------------

local signalStore = setmetatable({}, { __mode = "k" })
local function signalFor(inst, name)
	local perInst = signalStore[inst]
	if not perInst then
		perInst = {}
		signalStore[inst] = perInst
	end
	local s = perInst[name]
	if not s then
		s = makeSignal()
		perInst[name] = s
	end
	return s
end

for _, pair in {
	{ "Instance", "Changed" },
	{ "Instance", "Destroying" },
	{ "Instance", "DescendantAdded" },
	{ "Instance", "ChildAdded" },
	{ "GuiButton", "Activated" },
	{ "GuiButton", "MouseButton1Click" },
	{ "GuiObject", "MouseEnter" },
	{ "GuiObject", "MouseLeave" },
	{ "GuiObject", "SelectionGained" },
	{ "GuiObject", "SelectionLost" },
	{ "GuiObject", "InputBegan" },
	{ "GuiObject", "InputEnded" },
	{ "Sound", "Ended" },
	{ "RemoteEvent", "OnClientEvent" },
} do
	roblox.implementProperty(pair[1], pair[2], function(self)
		return signalFor(self, pair[2])
	end)
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, prop)
	return signalFor(self, "prop:" .. prop)
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attr)
	return signalFor(self, "attr:" .. attr)
end)
roblox.implementMethod("RemoteEvent", "FireServer", function() end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)

------------------------------------------------------------------------------------
-- Engine services
------------------------------------------------------------------------------------

local RS = game:GetService("ReplicatedStorage")
-- remotes as the server would create them
local Net = nil
do
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = RS
end

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local playerScripts = Instance.new("Folder")
playerScripts.Name = "PlayerScripts"
local attrs = { Status = "MENU", Battery = 100, Flashlight = false, FlashlightColor = roblox.Color3.new(1, 1, 1), BeamEffect = "dust", IsAdmin = true }
local localPlayer
localPlayer = {
	Name = "Tester",
	DisplayName = "Tester",
	UserId = 1,
	Character = nil,
	Parent = game,
	CharacterAdded = makeSignal(),
	GetAttribute = function(_, k)
		return attrs[k]
	end,
	SetAttribute = function(_, k, v)
		attrs[k] = v
		signalFor(localPlayer, "attr:" .. k):Fire()
	end,
	GetAttributeChangedSignal = function(_, k)
		return signalFor(localPlayer, "attr:" .. k)
	end,
	WaitForChild = function(_, name)
		if name == "PlayerGui" then
			return playerGui
		elseif name == "PlayerScripts" then
			return playerScripts
		end
		return nil
	end,
	FindFirstChild = function(_, name)
		return localPlayer:WaitForChild(name)
	end,
}

env.setService("Players", {
	LocalPlayer = localPlayer,
	GetPlayers = function()
		return { localPlayer }
	end,
	PlayerAdded = makeSignal(),
	PlayerRemoving = makeSignal(),
	GetPlayerFromCharacter = function()
		return nil
	end,
})

local inputSignals = {}
local uis = setmetatable({
	TouchEnabled = false,
	KeyboardEnabled = true,
	GamepadEnabled = false,
	MouseBehavior = roblox.Enum.MouseBehavior.Default,
	MouseIconEnabled = true,
	GetMouseDelta = function()
		return Vector2.zero
	end,
	IsMouseButtonPressed = function()
		return false
	end,
}, {
	__index = function(t, k)
		local s = makeSignal()
		inputSignals[k] = s
		rawset(t, k, s)
		return s
	end,
})
env.setService("UserInputService", uis)
env.setService("GuiService", { SelectedObject = nil, AutoSelectGuiEnabled = true })

local renderFns = {}
local loops = { RenderStepped = makeSignal(), Heartbeat = makeSignal(), Stepped = makeSignal() }
local function connectable(name)
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		fire = function(...)
			for _, h in handlers do
				h(...)
			end
		end,
		handlers = handlers,
		name = name,
	}
end
loops.RenderStepped = connectable("RenderStepped")
loops.Heartbeat = connectable("Heartbeat")
loops.Stepped = connectable("Stepped")
env.setService("RunService", {
	BindToRenderStep = function(_, name, _, fn)
		renderFns[name] = fn
	end,
	RenderStepped = loops.RenderStepped,
	Heartbeat = loops.Heartbeat,
	Stepped = loops.Stepped,
	IsServer = function()
		return false
	end,
	IsClient = function()
		return true
	end,
	IsStudio = function()
		return true
	end,
})
env.setService("TweenService", {
	Create = function()
		return { Play = function() end, Cancel = function() end, Completed = makeSignal() }
	end,
})
env.setService("Debris", { AddItem = function() end })
env.setService("StarterGui", { SetCoreGuiEnabled = function() end, SetCore = function() end })

local camera = Instance.new("Camera")
camera.CFrame = CFrame.new(0, 5, 0)
camera.ViewportSize = Vector2.new(1920, 1080)
camera.Parent = workspace
workspace.CurrentCamera = camera
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.time()
end)
env.setRaycast(function()
	return nil
end)
roblox.implementMethod("Workspace", "Spherecast", function()
	return nil
end)

-- Net needs the remotes: create them through the real module definitions
Net = requireModule(RS.Shared.Net)
local remotesFolder = RS:FindFirstChild("Remotes")
for name in Net.Events do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotesFolder
end
for name in Net.Functions do
	local r = Instance.new("RemoteFunction")
	r.Name = name
	r.Parent = remotesFolder
end
local Cosmetics = requireModule(RS.Shared.Catalog.Cosmetics)
local shopItems = {}
for _, c in Cosmetics.List do
	table.insert(shopItems, { id = c.id, category = c.category, name = c.name, price = c.price, owned = c.default == true, equipped = false, lock = if c.level then "LEVEL " .. c.level else nil })
end
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self)
	if self.Name == "GetShop" then
		return { items = shopItems, echoes = 1234 }
	end
	return nil
end)

local function fire(name, payload)
	local remote = remotesFolder:FindFirstChild(name)
	signalFor(remote, "OnClientEvent"):Fire(payload)
end

------------------------------------------------------------------------------------
-- Run the controllers
------------------------------------------------------------------------------------

section("controllers")
local clientRoot = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local Registry = requireModule(clientRoot.Registry)
local State = requireModule(clientRoot.State)
local mainSource = clientRoot.Main.Source
local order = {}
for name in string.gmatch(string.match(mainSource, "local ORDER = (%b{})"), '"(%w+)"') do
	table.insert(order, name)
end
check(#order >= 25, "controller order parsed (" .. #order .. ")")
local controllers = {}
for _, name in order do
	local module = clientRoot.Controllers:FindFirstChild(name)
	check(module ~= nil, "controller exists: " .. name)
	if module then
		local ok, c = pcall(requireModule, module)
		check(ok, "require " .. name .. ": " .. tostring(c))
		if ok then
			Registry[name] = c
			table.insert(controllers, c)
			c.Name = name
		end
	end
end
for _, c in controllers do
	if c.Init then
		local ok, err = pcall(c.Init, c)
		check(ok, c.Name .. ".Init: " .. tostring(err))
	end
end
for _, c in controllers do
	if c.Start then
		task.spawn(function()
			local ok, err = pcall(c.Start, c)
			check(ok, c.Name .. ".Start: " .. tostring(err))
		end)
	end
end
task.wait(1.5)

local function frames(n)
	for _ = 1, n do
		env.syncPositions(workspace)
		for name, fn in renderFns do
			local ok, err = pcall(fn, 1 / 60)
			check(ok, "render step " .. name .. ": " .. tostring(err))
		end
		for _, loop in loops do
			for _, h in loop.handlers do
				local ok, err = pcall(h, 1 / 60, 1 / 60)
				check(ok, loop.name .. " handler: " .. tostring(err))
			end
		end
	end
end

section("menu")
frames(5)
fire("Profile", {
	echoes = 500,
	xp = 900,
	level = 4,
	xpInto = 50,
	xpNeed = 200,
	journal = { PAINTING_SWAP = { c = 3, f = os.time(), l = os.time() }, ROOM_ZERO = { c = 1, f = os.time(), l = os.time() } },
	achievements = { FIRST_NIGHT = os.time() },
	owned = { FL_STANDARD = true, EM_WAVE = true },
	equipped = { FLASHLIGHT = "FL_STANDARD" },
	settings = { master = 1, music = 0.5, sfx = 1, ambient = 1, ui = 1, sensitivity = 0.5, fov = 74, headBob = true, cameraShake = true, reducedEffects = false, flashingAccepted = false, subtitles = true, invertY = false },
	stats = { rounds = 3, escapes = 1, deaths = 2, anomaliesReported = 12, falseReports = 1, bestTime = 640, observerSightings = 4, secretEndings = 0 },
	flags = { tutorialDone = true, hardUnlocked = false },
})
task.wait(1)
frames(3)
for _, panel in { "HOWTO", "JOURNAL", "SHOP", "SETTINGS", "CREDITS" } do
	local ok, err = pcall(function()
		Registry.MenuController:OpenPanel(panel)
	end)
	check(ok, "open panel " .. panel .. ": " .. tostring(err))
	frames(2)
end

section("lobby")
localPlayer:SetAttribute("Status", "LOBBY")
frames(2)
fire("LobbyState", { players = { { userId = 1, name = "Tester", ready = false, host = true, title = "Visitor", level = 4 }, { userId = 2, name = "Friend", ready = true, host = false } }, difficulty = "NORMAL", hardAvailable = false, countdown = 12, roundRunning = false, hostUserId = 1, maxPlayers = 4 })
frames(3)
local okPause = pcall(function()
	Registry.MenuController:SetPaused(true)
	Registry.MenuController:SetPaused(false)
	Registry.EmoteController:OpenWheel()
	Registry.EmoteController:CloseWheel()
end)
check(okPause, "pause menu & emote wheel")

section("round")
fire("RoundState", { state = "EXPLORING", difficulty = "NORMAL", seed = 7, elapsed = 0 })
localPlayer:SetAttribute("Status", "ALIVE")
fire("Objective", { list = { { text = "Find the anomalies  1/7", done = false, primary = true }, { text = "Restore the power  (fuses 1/3)", done = false }, { text = "Exit locks released  0/4", done = false, dim = true } }, found = 1, quota = 7 })
fire("InventoryState", { slots = { { id = "FUSE", count = 2 }, { id = "BATTERY", count = 1 }, false, { id = "MAINT_KEY", count = 1 } }, selected = 2, battery = 64, light = true })
fire("PlayerStates", { { userId = 1, name = "Tester", status = "ALIVE" }, { userId = 2, name = "Friend", status = "DEAD" } })
fire("Notify", { kind = "item", text = "Fuse", item = "FUSE" })
fire("Notify", { kind = "team", text = "Friend spotted an anomaly" })
fire("Notify", { kind = "anomaly", text = "THE OTHER PAINTING", sub = "ANOMALY #001" })
fire("Notify", { kind = "objective", text = "POWER RESTORED" })
fire("Unlock", { type = "journal", id = "EXTRA_DOOR", number = 7, name = "THE EXTRA DOOR", rarity = "UNCOMMON", description = "..." })
fire("Unlock", { type = "achievement", id = "ESCAPED", name = "ESCAPED", description = "Escape", echoes = 50 })
fire("Unlock", { type = "level", level = 5, unlocked = { "Look Around" } })
fire("Caption", { text = "[TAPE] First... the AMBER light.", duration = 2, speaker = "tape" })
fire("Director", { cue = "phase", phase = "TENSION" })
fire("Director", { cue = "silence", duration = 2 })
fire("Director", { cue = "flicker", room = "G_c", duration = 1 })
fire("PingShow", { id = "p1", kind = "DANGER", position = Vector3.new(10, 3, 10), from = "Friend", duration = 2 })
fire("PingShow", { id = "f1", kind = "COME_HERE", position = Vector3.new(30, 3, 10), from = "Friend", fake = true, duration = 2 })
fire("Document", { id = "BREAKERS", title = "MAINTENANCE LOG", body = "1 UP\n2 DOWN", kind = "breakers" })
fire("PuzzleState", { type = "keypad", open = true })
fire("PuzzleState", { type = "keypad", open = true, result = "error" })
fire("Reality", { action = "apply", token = "t1", ops = { { t = "Attr", target = workspace, name = "Test", value = 1 } } })
fire("Reality", { action = "revert", token = "t1" })
frames(10)
for _, effect in { "RealitySnap", "ReportWrong", "Blink", "ObserverSeen", "Intro", "TutorialHint", "PowerSurge", "EscapeStart", "PortalGlitch", "WrongRoom", "DustBurst", "Sparks", "ShadowRun", "Shake", "Glitch", "WardBreak", "Jumpscare", "OpenPanel" } do
	fire("Effect", { name = effect, at = Vector3.new(0, 3, 0), from = Vector3.new(0, 0, 0), to = Vector3.new(10, 0, 0), duration = 0.3, strength = 0.5, panel = "JOURNAL" })
end
frames(10)
local hudOk = pcall(function()
	Registry.HUDController:SetPrompt("E", "Open", true, 0.5)
	Registry.HUDController:SetFocus(0.6)
	Registry.HUDController:Hint("hint", 1)
	Registry.PuzzleUI:Close()
end)
check(hudOk, "HUD API")
fire("RoundState", { state = "ESCAPE", difficulty = "NORMAL", seed = 7, elapsed = 500, escapeRemaining = 120 })
frames(5)
fire("Death", { killer = CFrame.new(5, 0, 5), position = Vector3.new(0, 3, 0) })
frames(30)
fire("Effect", { name = "Escaped", camera = CFrame.new(0, 10, 0), witness = true })
frames(5)
localPlayer:SetAttribute("Status", "DEAD")
local okSpec = pcall(function()
	Registry.SpectatorController:Begin(false)
end)
check(okSpec, "spectator begins")
frames(5)
fire("Effect", { name = "RealityCollapse" })
fire("Results", {
	ending = "THE_WITNESS",
	team = "ESCAPED",
	summary = { duration = 640, difficulty = "NORMAL", playerCount = 2, escapedCount = 1, anomaliesFound = 7, anomaliesMissed = 2, quota = 7, seed = 7 },
	reward = { echoes = 120, xp = 300, levelBefore = 4, levelAfter = 5, xpInto = 20, xpNeed = 250, found = 4, newJournal = 2, achievements = { "ESCAPED" } },
	roster = { { name = "Tester", outcome = "ESCAPED" }, { name = "Friend", outcome = "DEAD" } },
})
frames(5)
fire("AdminData", { snapshot = { round = "EXPLORING", seed = 7, mapSeed = 7, difficulty = "NORMAL", elapsed = 100, phase = "CALM", dread = 10, observer = "DORMANT", players = { { name = "Tester", userId = 1, status = "ALIVE", room = "RECEPTION", battery = 80, light = true } }, active = { { id = "PAINTING_SWAP", scope = "GLOBAL", remaining = 90, players = 1 } }, stats = { spawned = 3, found = 1, missed = 0 }, objective = { puzzles = { "CODE", "DOORS" }, locks = { POWER = false }, quota = 7, found = 1, code = "1234" }, analytics = { roundsCompleted = 1, roundsStarted = 2 }, logs = { "line" }, anomalyIds = { "PAINTING_SWAP", "EXTRA_DOOR" }, dataMock = true }, message = "ok" })
frames(5)
fire("RoundState", { state = "LOBBY", difficulty = "NORMAL", seed = 7, elapsed = 0 })
localPlayer:SetAttribute("Status", "LOBBY")
frames(5)

-- the menu cinematic again
localPlayer:SetAttribute("Status", "MENU")
frames(5)

section("click every button")
local clicked = 0
local SKIP = { PLAY = true, ["BACK TO MENU"] = true, ["PLAY AGAIN"] = true }
local function clickAll()
	-- snapshot first: clicks may rebuild panels, and those new buttons are covered by the next pass
	local buttons = {}
	for _, d in playerGui:GetDescendants() do
		local okValid, valid = pcall(function()
			return d:IsA("GuiButton") and not SKIP[(d :: any).Text or ""]
		end)
		if okValid and valid then
			table.insert(buttons, d)
		end
		if #buttons >= 150 then
			break
		end
	end
	for _, d in buttons do
		local okAlive, alive = pcall(function()
			return d.Parent ~= nil
		end)
		if okAlive and alive then
			local name = d.Name
			local ok, err = pcall(function()
				signalFor(d, "Activated"):Fire()
				signalFor(d, "MouseEnter"):Fire()
				signalFor(d, "MouseLeave"):Fire()
			end)
			check(ok, "click " .. name .. ": " .. tostring(err))
			clicked += 1
		end
	end
end
for _, status in { "MENU", "LOBBY", "ALIVE" } do
	localPlayer:SetAttribute("Status", status)
	frames(2)
	for _, panel in { "JOURNAL", "SHOP", "SETTINGS" } do
		pcall(function()
			Registry.MenuController:OpenPanel(panel)
		end)
		clickAll()
		frames(1)
	end
end
task.wait(2.5)
frames(3)
print("  clicked " .. clicked .. " buttons")

section("summary")
print(string.format("%d checks, %d failures, %d controllers", checks, failures, #controllers))
process.exit(if failures == 0 then 0 else 1)
