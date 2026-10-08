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
local Color3 = roblox.Color3

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
	{ "GuiButton", "MouseButton1Down" },
	{ "GuiButton", "MouseButton1Up" },
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
-- a pinhole camera projection (enough for HUD markers)
roblox.implementMethod("Camera", "WorldToViewportPoint", function(self, point)
	local cf = self.CFrame
	local rel = cf:PointToObjectSpace(point)
	local depth = -rel.Z
	local viewport = Vector2.new(1920, 1080)
	if depth <= 0.01 then
		return Vector3.new(viewport.X / 2, viewport.Y / 2, depth), false
	end
	local f = (viewport.Y / 2) / math.tan(math.rad(35))
	local x = viewport.X / 2 + rel.X / depth * f
	local y = viewport.Y / 2 - rel.Y / depth * f
	return Vector3.new(x, y, depth), x >= 0 and x <= viewport.X and y >= 0 and y <= viewport.Y
end)

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
	UnbindFromRenderStep = function(_, name)
		renderFns[name] = nil
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
local EquipmentCatalog = requireModule(RS.Shared.Catalog.Equipment)
local gearItems, gearUpgrades = {}, {}
for i, e in EquipmentCatalog.List do
	table.insert(gearItems, { id = e.id, kind = e.kind, owned = e.default == true or i % 3 == 0, price = e.price, level = e.level, locked = (e.level or 0) > 6, equipped = e.default == true })
end
for i, u in EquipmentCatalog.Upgrades do
	table.insert(gearUpgrades, { id = u.id, level = i % 2, max = #u.levels, price = u.levels[1].price, needLevel = u.levels[1].level, locked = i == 3 })
end
local gearSnapshot = { echoes = 2400, level = 6, items = gearItems, upgrades = gearUpgrades, loadout = { "SPARE_CELL" }, slots = 3, flashlight = "FL_STARTER", battery = "BAT_STANDARD" }
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self)
	if self.Name == "GetShop" then
		return { items = shopItems, echoes = 1234 }
	elseif self.Name == "GetGear" then
		return gearSnapshot
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
			local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback() end, 1 / 60)
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

section("supply room")
fire("Challenge", { daily = { { id = "D_ANOMALY_3", text = "Find 3 anomalies", goal = 3, progress = 1, done = false, echoes = 60, xp = 80 } }, weekly = { { id = "W_SURVIVE_5", text = "Survive 5", goal = 5, progress = 5, done = true, echoes = 500, xp = 700 } }, dailyResetsIn = 4000, weeklyResetsIn = 300000, dailiesDone = 2 })
check(State.challenges ~= nil, "challenge snapshot reaches State")
do
	local ShopPanel = requireModule(clientRoot.UI.ShopPanel)
	local KitM = requireModule(clientRoot.UI.Kit)
	for _, tab in { "EQUIPMENT", "UPGRADES", "LOADOUT", "COSMETICS", "CHALLENGES" } do
		local holder = KitM.frame({})
		local ok, err = pcall(function()
			ShopPanel.build(holder, {
				tabs = function(_, names, onSelect)
					return function(name)
						onSelect(name)
					end
				end,
				backButton = function() end,
			}, tab)
		end)
		check(ok, "supply room tab " .. tab .. ": " .. tostring(err))
		frames(2)
		-- click every button and card once
		for _, d in holder:GetDescendants() do
			if d:IsA("GuiButton") then
				local ok2, err2 = pcall(function()
					signalFor(d, "MouseEnter"):Fire()
					signalFor(d, "Activated"):Fire()
				end)
				check(ok2, "supply room " .. tab .. " click: " .. tostring(err2))
			end
		end
		frames(2)
		signalFor(holder, "Destroying"):Fire()
		holder:Destroy()
	end
	fire("ToolEvent", { kind = "gear", gear = gearSnapshot })
	check(State.gear == gearSnapshot, "gear snapshot reaches State")
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
check(not Registry.CameraController:HasOverride(), "lobby: no camera override blocks movement")

-- the player can actually walk in the lobby
local function walkCheck(label: string)
	check(State.uiOpen == false, label .. ": no UI holds focus")
	check(not Registry.CameraController:HasOverride(), label .. ": camera free (movement enabled)")
end
walkCheck("lobby")

section("round")
fire("RoundState", { state = "EXPLORING", difficulty = "NORMAL", seed = 7, elapsed = 0 })
localPlayer:SetAttribute("Status", "ALIVE")
fire("Objective", { list = { { text = "Find the anomalies  1/7", done = false, primary = true }, { text = "Restore the power  (fuses 1/3)", done = false }, { text = "Exit locks released  0/4", done = false, dim = true } }, found = 1, quota = 7 })
fire("InventoryState", { slots = { { id = "FUSE", count = 2 }, { id = "BATTERY", count = 1 }, false, { id = "MAINT_KEY", count = 1 } }, selected = 2, battery = 64, light = true })
fire("PlayerStates", { { userId = 1, name = "Tester", status = "ALIVE" }, { userId = 2, name = "Friend", status = "DEAD" } })
frames(2)
walkCheck("round")
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
-- every flashlight has its own beam and runs on a weak battery
for _, id in { "FL_STARTER", "FL_INDUSTRIAL", "FL_TACTICAL", "FL_ADVANCED", "FL_PROTOTYPE", "UNKNOWN" } do
	localPlayer:SetAttribute("FlashlightModel", id)
	localPlayer:SetAttribute("Flashlight", true)
	localPlayer:SetAttribute("Battery", 6)
	local ok = pcall(frames, 5)
	check(ok, "flashlight beam " .. id)
end
localPlayer:SetAttribute("Battery", 100)
-- presence: every proximity state and every paranoia moment runs and cleans up
do
	local before = #workspace:GetChildren()
	for _, prox in { "AWARE", "NEAR", "VERY_NEAR", "HUNT", "FAR" } do
		localPlayer:SetAttribute("ObserverProx", prox)
		frames(3)
	end
	check(State.prox == "FAR", "presence: proximity state follows the server")
	for _, kind in { "micro", "glimpse", "shadow", "silence", "bogus" } do
		local ok = pcall(function()
			fire("Director", { cue = "paranoia", kind = kind, seed = 1 })
		end)
		check(ok, "paranoia " .. kind)
		frames(10)
	end
	task.wait(1.2)
	frames(5)
	check(#workspace:GetChildren() <= before + 1, "paranoia leaves nothing behind")
end
fire("RoundState", { state = "ESCAPE", difficulty = "NORMAL", seed = 7, elapsed = 500, escapeRemaining = 120 })
frames(5)
fire("Death", { killer = CFrame.new(5, 0, 5), position = Vector3.new(0, 3, 0) })
frames(30)
-- every Observer death cinematic plays through and cleans up after itself
section("observer animation")
do
	local ObserverRig = requireModule(RS.Shared.ObserverRig)
	local rig = ObserverRig.build(CFrame.new(0, 0, -20), { localCopy = true })
	rig.Parent = workspace
	-- Lune has no physics: give the root a velocity before the animator reads it
	pcall(function()
		(rig.PrimaryPart :: any).AssemblyLinearVelocity = Vector3.zero
	end)
	rig:AddTag("Observer")
	env.tagAdded("Observer", rig)
	task.wait()
	frames(2)
	local root = rig.PrimaryPart :: any
	for _, case in {
		{ "DORMANT", Vector3.zero },
		{ "MOVING", Vector3.new(4, 0, 0) },
		{ "HUNTING", Vector3.new(10, 0, 0) },
		{ "HUNTING", Vector3.new(16, 0, 0) },
		{ "WATCHED", Vector3.zero },
		{ "ATTACKING", Vector3.zero },
		{ "HUNTING", Vector3.zero },
	} do
		rig:SetAttribute("State", case[1])
		pcall(function()
			root.AssemblyLinearVelocity = case[2]
		end)
		frames(20)
	end
	local moved = 0
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") then
			-- Transform has no default in Lune until something writes it
			local ok, t = pcall(function()
				return d.Transform
			end)
			if ok and t ~= CFrame.identity then
				moved += 1
			end
		end
	end
	check(moved >= 8, "observer motors animated (" .. moved .. ")")
	rig:Destroy()
	frames(2)
end

section("death cinematics")
for _, variant in { "behind", "side", "front", "dark", "door", "mirror", "mimic" } do
	local finished = false
	local ok, err = pcall(function()
		Registry.ScareController:Death({ variant = variant, position = Vector3.new(0, 3, 0), side = 1, door = Vector3.new(6, 0, 2), mirror = Vector3.new(0, 6, -8), mimicUserId = 2, mimicName = "Friend" }, function()
			finished = true
		end)
	end)
	check(ok, "death cinematic " .. variant .. ": " .. tostring(err))
	local deadline = os.clock() + 4
	while not finished and os.clock() < deadline do
		frames(2)
		task.wait(0.05)
	end
	frames(4)
	task.wait(0.3)
	check(finished, "death cinematic " .. variant .. " reaches the black screen")
	check(not Registry.ScareController:IsActive(), "death cinematic " .. variant .. " cleans up")
	local leftovers = 0
	for _, d in workspace:GetChildren() do
		if d.Name == "ObserverScare" then
			leftovers += 1
		end
	end
	check(leftovers == 0, "no scare rig left behind after " .. variant)
	Registry.CameraController:ClearOverride("Death")
end
local okFlash = pcall(function()
	Registry.ScareController:Flash("mimic")
end)
check(okFlash, "short scare")
task.wait(0.4)
frames(3)
fire("Effect", { name = "ObserverClose" })
fire("Effect", { name = "GuideMarker", at = Vector3.new(10, 3, 10), text = "MAIL ROOM" })
frames(5)
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
	reward = { echoes = 120, xp = 300, levelBefore = 4, levelAfter = 5, xpInto = 20, xpNeed = 250, found = 4, newJournal = 2, achievements = { "ESCAPED" }, breakdown = { { label = "Time in the building  10:40", echoes = 43, xp = 107 }, { label = "Escaped", echoes = 40, xp = 90 }, { label = "Played with friends  +10%", echoes = 8, xp = 20 } } },
	roster = { { name = "Tester", outcome = "ESCAPED" }, { name = "Friend", outcome = "DEAD" } },
})
frames(5)
task.wait(3.5)
frames(3)
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

section("visual overhaul: shaped fixture lights + detail LOD")
do
	local camPos = workspace.CurrentCamera.CFrame.Position
	-- a troffer like MapBuilder's: SurfaceLight main + point fill, each with its share
	local fixture = Instance.new("Model")
	fixture.Name = "Fixture"
	local housing = Instance.new("Part")
	housing.Name = "Housing"
	housing.Anchored = true
	housing.CFrame = CFrame.new(camPos + Vector3.new(4, 6, 0))
	housing.Parent = fixture
	local tube = Instance.new("Part")
	tube.Name = "Tube"
	tube.Anchored = true
	tube.CFrame = housing.CFrame * CFrame.new(0, -0.3, 0)
	tube.Parent = fixture
	local fill = Instance.new("PointLight")
	fill.Name = "Light"
	fill:SetAttribute("Ratio", 0.42)
	fill:SetAttribute("Solo", 1)
	fill.Parent = tube
	local main = Instance.new("SurfaceLight")
	main.Name = "MainLight"
	main:SetAttribute("Ratio", 1.15)
	main:SetAttribute("Main", true)
	main.Parent = housing
	fixture.PrimaryPart = housing
	fixture:SetAttribute("Mode", "on")
	fixture:SetAttribute("Circuit", "MAIN")
	fixture:SetAttribute("BaseBrightness", 1)
	fixture:SetAttribute("BaseColor", Color3.fromRGB(220, 230, 220))
	fixture:SetAttribute("Room", "G_c")
	fixture:SetAttribute("Seed", 7)
	fixture.Parent = workspace
	fixture:AddTag("Fixture")
	env.tagAdded("Fixture", fixture)
	local prevPower = workspace:GetAttribute("Power")
	workspace:SetAttribute("Power", true)
	task.wait(0.1)
	frames(30)
	check(main.Enabled and fill.Enabled, "both lights of a lit fixture are on")
	check(math.abs(main.Brightness - 1.15) < 0.01 and math.abs(fill.Brightness - 0.42) < 0.01, string.format("brightness shares (main %.2f fill %.2f)", main.Brightness, fill.Brightness))
	fixture:SetAttribute("Tint", Color3.fromRGB(255, 0, 0))
	frames(30)
	check(main.Color == Color3.fromRGB(255, 0, 0) and fill.Color == Color3.fromRGB(255, 0, 0), "an anomaly tint reaches every light of the fixture")
	fixture:SetAttribute("Override", "off")
	frames(30)
	check(not main.Enabled and not fill.Enabled, "an override switches every light off")
	fixture:Destroy()
	workspace:SetAttribute("Power", prevPower)

	-- detail LOD hides a far room's detail and shows it again up close
	local DetailLOD = Registry.DetailLOD
	local group = Instance.new("Folder")
	group.Name = "TestRoom"
	group:SetAttribute("Center", camPos + Vector3.new(0, 0, 400))
	group:SetAttribute("Radius", 10)
	local bolt = Instance.new("Part")
	bolt.Anchored = true
	bolt.Parent = group
	group.Parent = workspace
	group:AddTag("DetailGroup")
	env.tagAdded("DetailGroup", group)
	task.wait(0.1)
	local before = DetailLOD:HiddenCount()
	DetailLOD:Update(camPos)
	check(DetailLOD:HiddenCount() == before + 1, "far detail group hidden")
	DetailLOD:Update(camPos + Vector3.new(0, 0, 400))
	check(DetailLOD:HiddenCount() == before, "near detail group shown again")
	group:Destroy()
end

section("marketing studio")
do
	local Lighting = game:GetService("Lighting")
	local SoundService = game:GetService("SoundService")
	local mRoot = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Marketing")
	check(mRoot ~= nil, "marketing client folder")
	local MC = requireModule(mRoot.MarketingController)
	local Runtime = requireModule(mRoot.Runtime)
	local Actions = requireModule(mRoot.Actions)
	local Panel = requireModule(mRoot.UI.Panel)
	local Config = requireModule(RS.Marketing.MarketingConfig)
	local scenes = MC.ListScenes()
	check(#scenes >= 56, "all scenes registered (" .. #scenes .. ")")
	do
		local Looks = requireModule(mRoot.Utilities.Looks)
		check(#Looks.Order == 8, "eight looks")
		for _, name in Looks.Order do
			local look = Looks.Presets[name]
			check(look ~= nil and type(look.grade) == "string", "look defined: " .. name)
			for _, key in look.keys do
				local cf = Looks.keyCFrame(key, CFrame.lookAt(Vector3.new(0, 5, 10), Vector3.new(0, 4, 0)), Vector3.new(0, 4, 0))
				check(cf ~= nil and cf.Position == cf.Position, "look key placed: " .. name .. "." .. key.name)
			end
		end
	end
	local seenNames = {}
	for _, n in scenes do
		check(not seenNames[n], "unique scene name " .. n)
		seenNames[n] = true
		local info = MC.SceneInfo(n)
		check(info ~= nil and info.Category ~= "" and #info.Description > 10 and info.Duration >= 4 and info.Duration <= 20, "scene info " .. n)
	end
	-- every action used by a scene exists
	for _, name in scenes do
		local def = MC.GetScene(name)
		check(def ~= nil and type(def.Build) == "function" and def.Duration > 0, "scene module " .. name)
	end
	local ok, perr = pcall(Panel.mount, MC, Config)
	check(ok, "marketing panel mounts: " .. tostring(perr))
	local panelGui = playerGui:FindFirstChild("MarketingStudioPanel")
	local window = panelGui and panelGui:FindFirstChild("Window")
	check(window ~= nil, "marketing panel window is inside its ScreenGui")
	check(panelGui and panelGui:FindFirstChild("Opener") ~= nil, "marketing opener button")
	if window then
		Panel.setVisible(true)
		check(window.Visible == true and #window:GetChildren() > 5, "marketing panel shows its controls")
		Panel.setVisible(false)
	end
	MC.SetOption("HoldAtEnd", 0)

	local function snapshot()
		local snap = {}
		for _, prop in { "ExposureCompensation", "Ambient", "OutdoorAmbient", "Brightness", "FogEnd" } do
			snap["L." .. prop] = tostring((Lighting :: any)[prop])
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			snap["A.Density"] = tostring(atmosphere.Density)
		end
		snap.workspace = #workspace:GetChildren()
		snap.camera = #workspace.CurrentCamera:GetChildren()
		snap.playerGui = #playerGui:GetChildren()
		snap.sound = #SoundService:GetChildren()
		local enabled = 0
		for _, g in playerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled then
				enabled += 1
			end
		end
		snap.enabledGuis = enabled
		return snap
	end
	local function same(a, b, label)
		for k, v in a do
			check(b[k] == v, label .. ": " .. k .. " restored (" .. tostring(v) .. " -> " .. tostring(b[k]) .. ")")
		end
	end
	local function run(name, label)
		print("  marketing: " .. label .. " " .. name)
		local before = snapshot()
		local okPlay, err = MC.PlayScene(name)
		check(okPlay, label .. " " .. name .. " plays: " .. tostring(err))
		local fn = renderFns.MarketingStudio
		check(fn ~= nil, label .. " " .. name .. " drives a render step")
		local def = MC.GetScene(name)
		local steps = 0
		while renderFns.MarketingStudio and steps < (def.Duration + 2) * 30 do
			local okStep, e = pcall(renderFns.MarketingStudio, 1 / 30)
			check(okStep, label .. " " .. name .. " step: " .. tostring(e))
			if not okStep then
				break
			end
			steps += 1
		end
		check(not MC.IsPlaying(), label .. " " .. name .. " ends by itself")
		check(renderFns.MarketingStudio == nil, label .. " " .. name .. " unbinds its render step")
		check(Runtime.isClean(), label .. " " .. name .. " leaves MarketingRuntime clean")
		same(before, snapshot(), label .. " " .. name)
	end
	-- 1. anywhere (no building): the virtual set
	for _, name in scenes do
		run(name, "virtual")
	end
	-- 2. inside a (small) Ashgrove-like building
	local building = Instance.new("Folder")
	building.Name = "Building"
	local function floor(room, size, pos)
		local p = Instance.new("Part")
		p.Name = "Floor"
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p:SetAttribute("Room", room)
		p.Parent = building
	end
	floor("G_c", Vector3.new(152, 1, 8), Vector3.new(76, -0.5, 44))
	floor("U_c", Vector3.new(152, 1, 8), Vector3.new(76, 17.5, 44))
	floor("G_k", Vector3.new(44, 1, 36), Vector3.new(22, -0.5, 90))
	floor("U_o", Vector3.new(30, 1, 30), Vector3.new(60, 17.5, 20))
	floor("G_b", Vector3.new(30, 1, 30), Vector3.new(60, -0.5, 20))
	local door = Instance.new("Model")
	door.Name = "Door"
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Size = Vector3.new(4, 10, 0.3)
	leaf.CFrame = CFrame.new(60, 5, 39.9)
	leaf.Parent = door
	door.PrimaryPart = leaf
	door:SetAttribute("RoomA", "G_b")
	door:SetAttribute("RoomB", "G_c")
	door:SetAttribute("ClosedCFrame", leaf.CFrame)
	door:SetAttribute("OpenCFrame", CFrame.new(58, 5, 38) * CFrame.Angles(0, math.rad(90), 0))
	door:SetAttribute("Open", false)
	door:AddTag("Door")
	door.Parent = building
	local mirror = Instance.new("Model")
	mirror.Name = "Mirror"
	local glass = Instance.new("Part")
	glass.Name = "Glass"
	glass.Size = Vector3.new(3, 3.6, 0.05)
	glass.CFrame = CFrame.new(10, 6, 80)
	glass.Parent = mirror
	local overlay = Instance.new("SurfaceGui")
	overlay.Name = "Overlay"
	overlay.Parent = glass
	mirror:AddTag("Mirror")
	mirror.Parent = building
	building.Parent = workspace
	env.syncPositions(workspace)
	local doorBefore = leaf.CFrame
	for _, name in scenes do
		run(name, "building")
	end
	check(leaf.CFrame == door:GetAttribute("ClosedCFrame"), "the real door is back where the game left it")
	local _ = doorBefore
	-- 2b. the photographic eye (images configured)
	local savedEye = Config.EyeImages
	Config.EyeImages = { sclera = 1, iris = 2, pupil = 3, glint = 4, lidTop = 5, lidBottom = 6, socket = 7 }
	MC.PlayScene("Scene04_TheEye")
	local sawPhoto = false
	for _ = 1, 200 do
		renderFns.MarketingStudio(1 / 30)
		for _, where in { workspace:FindFirstChild("MarketingRuntime"), playerGui:FindFirstChild("MarketingRuntimeGui") } do
			if where and where:FindFirstChild("IrisImage", true) and where:FindFirstChild("Socket", true) then
				sawPhoto = true
			end
		end
	end
	check(sawPhoto, "marketing: the photographic eye is used once its images are set")
	MC.StopScene()
	run("Scene02_DidYouSeeIt", "photo-eye")
	Config.EyeImages = savedEye
	-- 2c. CAM_04 with a real character to copy (an avatar-like rig)
	local character = Instance.new("Model")
	character.Name = "Tester"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = character
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = CFrame.new(0, 3.5, 0)
	torso.Parent = character
	local hip = Instance.new("Motor6D")
	hip.Name = "LeftHip"
	hip.Part0 = root
	hip.Part1 = torso
	hip.Parent = torso
	local hum = Instance.new("Humanoid")
	hum.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	localPlayer.Character = character
	MC.PlayScene("Scene03_CAM04")
	local sawActor = false
	for _ = 1, 120 do
		renderFns.MarketingStudio(1 / 30)
		local rt = workspace:FindFirstChild("MarketingRuntime")
		if rt and rt:FindFirstChild("Actor_staff") then
			sawActor = true
		end
	end
	check(sawActor, "marketing: CAM_04 uses a real character copy")
	MC.StopScene()
	check(Runtime.isClean(), "marketing: actor scene cleans up")
	localPlayer.Character = nil
	character:Destroy()
	-- 3. pause / resume / restart / stop mid-scene, slow motion, formats, camera styles
	MC.SetOption("TimeScale", 0.5)
	MC.SetFormat("SQUARE")
	MC.SetCameraStyle("HANDHELD")
	MC.PlayScene("Scene08_Launch")
	for _ = 1, 40 do
		renderFns.MarketingStudio(1 / 30)
	end
	MC.PauseScene()
	local clock = MC.GetState().clock
	for _ = 1, 10 do
		renderFns.MarketingStudio(1 / 30)
	end
	check(MC.GetState().clock == clock, "pause freezes the scene clock")
	MC.ResumeScene()
	renderFns.MarketingStudio(1 / 30)
	check(MC.GetState().clock > clock, "resume continues")
	check(math.abs(MC.GetState().clock - (clock + 0.5 / 30)) < 1e-6, "slow motion runs at half speed")
	MC.RestartScene()
	check(MC.GetState().clock == 0 and MC.IsPlaying(), "restart starts over")
	for _ = 1, 20 do
		renderFns.MarketingStudio(1 / 30)
	end
	MC.StopScene()
	check(not MC.IsPlaying() and Runtime.isClean(), "stop mid-scene cleans everything")
	-- switching scenes mid-way: the first is cleaned before the second starts
	MC.PlayScene("Scene_CCTV_TimeLoop")
	for _ = 1, 60 do
		renderFns.MarketingStudio(1 / 30)
	end
	MC.PlayScene("Scene_TheRoomIsWatching")
	check(MC.GetState().scene == "Scene_TheRoomIsWatching" and MC.GetState().clock == 0, "switching scene starts the new one")
	local sets = 0
	for _, c in (workspace:FindFirstChild("MarketingRuntime") or Instance.new("Folder")):GetChildren() do
		if string.sub(c.Name, 1, 4) == "Set_" then
			sets += 1
		end
	end
	check(sets == 1, "only the new scene's set exists after switching (" .. sets .. ")")
	for _ = 1, 45 do
		renderFns.MarketingStudio(1 / 30)
	end
	MC.StopScene()
	check(Runtime.isClean(), "stop after a switch cleans everything")
	MC.CleanupMarketingScene()
	MC.CleanupMarketingScene()
	check(Runtime.isClean(), "cleanup is idempotent")
	MC.SetOption("TimeScale", 1)
	MC.SetFormat("SOCIAL_VERTICAL")
	MC.SetCameraStyle("AUTO")
	check(#Actions.names() >= 40, "action vocabulary (" .. #Actions.names() .. ")")
	building:Destroy()
	Panel.unmount()
end

section("summary")
print(string.format("%d checks, %d failures, %d controllers", checks, failures, #controllers))
process.exit(if failures == 0 then 0 else 1)
