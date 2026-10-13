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
	elseif self.Name == "GetPremium" then
		return {
			canShop = true,
			items = {
				{ key = "VIP", kind = "pass", name = "Patron", description = "A pass", grants = { "Patron" }, configured = false, owned = false },
				{ key = "SKIN_CANDLE", kind = "product", name = "Candlelight Finish", description = "A finish", grants = { "Candlelight" }, configured = true, owned = false, price = 75 },
				{ key = "SKIN_ASHEN", kind = "product", name = "Ashen Finish", description = "A finish", grants = { "Ashen" }, configured = true, owned = true, price = 75 },
				{ key = "SUPPORT", kind = "product", name = "Leave a Light On", description = "Thanks", grants = {}, configured = true, owned = false, repeatable = true },
			},
		}
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
for _, panel in { "HOWTO", "JOURNAL", "SHOP", "PREMIUM", "SETTINGS", "CREDITS" } do
	local ok, err = pcall(function()
		Registry.MenuController:OpenPanel(panel)
	end)
	check(ok, "open panel " .. panel .. ": " .. tostring(err))
	frames(2)
end

section("loading: real phases, no fake progress, never stuck")
do
	local bootFolder = game:GetService("ReplicatedFirst"):FindFirstChild("Boot")
	check(bootFolder ~= nil and bootFolder:FindFirstChild("BootState") ~= nil and bootFolder:FindFirstChild("Loading") ~= nil, "the loading screen and its state live in ReplicatedFirst")
	local Boot = requireModule(bootFolder.BootState)
	check(Boot.get("records") == "done", "the record phase is reported done once the profile arrived (NetController)")
	Boot.reset()
	check(not Boot.ready(), "nothing is ready at the start")
	check(Boot.claim("client") and not Boot.claim("client"), "the client can only be claimed once (no double start)")
	Boot.set("world", "done")
	Boot.set("world", "active")
	check(Boot.get("world") == "done", "a finished phase never goes back to active")
	for _, phase in Boot.PHASES do
		Boot.set(phase.id, if phase.id == "assets" then "skipped" else "done")
	end
	check(Boot.ready(), "ready once every phase finished (a skipped one included)")
	Boot.set("nonsense", "done")
	check(Boot.get("nonsense") == nil, "unknown phases are ignored")
	for id, t in Boot.TIMEOUT do
		check(t > 0 and t <= 60, "phase " .. id .. " has a time limit (" .. t .. " s)")
	end
	local src = bootFolder.Loading.Source
	check(string.find(src, "PreloadAsync", 1, true) ~= nil, "assets are really preloaded")
	check(string.find(src, "%%", 1, true) == nil, "no percentage anywhere on the loading screen")
	check(string.find(src, "RemoveDefaultLoadingScreen", 1, true) ~= nil, "the default screen is replaced")
	check(string.find(src, "TeleportService", 1, true) ~= nil and string.find(src, "RETRY", 1, true) ~= nil, "a server that never answers gets a RETRY that rejoins")
	check(string.find(src, "while not (BootState.ready() and BootState.get(\"systems\") == \"done\") do", 1, true) ~= nil, "the screen leaves on real conditions, not a timer")
	check(string.find(src, "task.wait(3)", 1, true) == nil and string.find(src, "task.wait(5)\n\tgui", 1, true) == nil, "no fixed-time exit")
	local main = clientRoot:FindFirstChild("Main")
	check(main ~= nil and string.find(main.Source, "BootState.claim(\"client\")", 1, true) ~= nil, "Main claims the client before starting controllers")
	check(main ~= nil and string.find(main.Source, "BootState.set(\"systems\", \"done\"", 1, true) ~= nil, "Main reports the systems once they started")
end

section("menu: PLAY waits for the server")
do
	localPlayer:SetAttribute("Status", "MENU")
	frames(2)
	Registry.MenuController:Play()
	check(Registry.MenuController:IsPlayPending(), "PLAY waits for an answer")
	Registry.MenuController:Play()
	localPlayer:SetAttribute("Status", "LOBBY")
	frames(2)
	task.wait(0.3)
	frames(2)
	check(not Registry.MenuController:IsPlayPending(), "once the server puts you in the Field Office, PLAY is done")
	localPlayer:SetAttribute("Status", "MENU")
	frames(2)
end

section("distortion: the corridor's cues, and everything put back")
do
	local Hall = requireModule(game:GetService("ReplicatedStorage").Shared.HallwayBuilder)
	local hall = Hall.build()
	hall.Parent = workspace
	localPlayer:SetAttribute("Status", "ALIVE")
	frames(2)
	local D = Registry.DistortionController
	check(D ~= nil, "the distortion controller runs")
	local yaw0, pitch0 = Registry.CameraController:GetYawPitch()
	fire("Distortion", { cue = "break", id = "ImpossibleHallway", token = 7 })
	check(Registry.HUDController:IsQuiet(), "the objectives and the team fade during it")
	task.wait(0.6)
	fire("Distortion", { cue = "arrive", id = "ImpossibleHallway", token = 7, hall = hall, look = Hall.toWorld(0, 3, Hall.SPAWN_Z - 40) })
	frames(3)
	check(State.distortion == "ImpossibleHallway", "the client knows it is inside one")
	check(#D:Lamps() == Hall.SEGMENTS, "every lamp of the corridor is driven (" .. #D:Lamps() .. ")")
	local deadLit = false
	for _, lamp in D:Lamps() do
		if lamp.dead and lamp.light.Enabled then
			deadLit = true
		end
	end
	check(not deadLit, "a dead lamp never lights")
	hall:SetAttribute("DarkFrom", 0)
	frames(2)
	local anyLit = false
	for _, lamp in D:Lamps() do
		if lamp.light.Enabled then
			anyLit = true
		end
	end
	check(not anyLit, "the dark takes every lamp it reaches")
	local redLit = true
	hall:SetAttribute("DarkFrom", -1e6)
	frames(2)
	for _, lamp in D:Lamps() do
		if lamp.light.Enabled and not lamp.spot and lamp.light.Color.R < lamp.light.Color.G * 2 then
			redLit = false
		end
	end
	local spots = 0
	for _, lamp in D:Lamps() do
		if lamp.spot then
			spots += 1
		end
	end
	check(spots == 1, "one white tube is left, over where it waits (" .. spots .. ")")
	check(redLit, "the corridor is in a total blackout: only red emergency light")
	check(playerGui:FindFirstChild("DistortionFX") ~= nil, "the red closes in at the edges of sight")
	check(game:GetService("Lighting"):FindFirstChild("DistortionGrade") ~= nil, "the picture takes the blackout's red grade")
	for _, cue in { "notice", "wake", "chase" } do
		local ok, err = pcall(fire, "Distortion", { cue = cue, id = "ImpossibleHallway", token = 7 })
		check(ok, "cue " .. cue .. ": " .. tostring(err))
		frames(1)
		task.wait(0.4)
		local music = Registry.MusicController:GetState()
		if cue == "notice" then
			check(music == "DREAD", "while it watches the music is dread (" .. tostring(music) .. ")")
		elseif cue == "chase" then
			check(music == "RUN", "when it comes the music runs (" .. tostring(music) .. ")")
		end
	end
	fire("Distortion", { cue = "taken", id = "ImpossibleHallway", token = 99 })
	check(State.distortion == "ImpossibleHallway", "a cue from another run is ignored")
	fire("Distortion", { cue = "exit", id = "ImpossibleHallway", token = 7 })
	fire("Distortion", { cue = "return", id = "ImpossibleHallway", token = 7, outcome = "escaped" })
	frames(2)
	local yaw1, pitch1 = Registry.CameraController:GetYawPitch()
	check(State.distortion == nil and not Registry.HUDController:IsQuiet(), "after the return nothing of it is left on screen")
	check(math.abs(yaw1 - yaw0) < 1e-6 and math.abs(pitch1 - pitch0) < 1e-6, "the view faces where it faced before")
	check(#D:Lamps() == 0, "the corridor's lamps are no longer driven")
	check(game:GetService("Lighting"):FindFirstChild("DistortionGrade") == nil and playerGui:FindFirstChild("DistortionFX") == nil, "and its grade and red edges are gone")
	-- the watchdog: no return cue, but the server cleared it
	fire("Distortion", { cue = "break", id = "ImpossibleHallway", token = 8 })
	localPlayer:SetAttribute("Distortion", "ImpossibleHallway")
	localPlayer:SetAttribute("Distortion", nil)
	task.wait(1.7)
	frames(1)
	check(State.distortion == nil and not Registry.HUDController:IsQuiet(), "a lost return still puts everything back")
	hall:Destroy()
	localPlayer:SetAttribute("Status", "MENU")
	frames(2)
end

section("briefing: the case file at the start of a night")
do
	localPlayer:SetAttribute("Status", "ALIVE")
	frames(2)
	local B = Registry.BriefingController
	check(B ~= nil, "the briefing controller runs")
	B:Open()
	check(B:IsOpen() and State.mouseFree() and State.isMouseHeld("briefing"), "it opens and frees the mouse")
	State.setUIOpen(false)
	check(State.mouseFree(), "the cursor stays free even if another panel closes meanwhile")
	local briefGui = playerGui:FindFirstChild("Briefing")
	local function buttonText(t)
		for _, d in briefGui:GetDescendants() do
			if d:IsA("TextButton") and d.Text == t then
				return d
			end
		end
		return nil
	end
	local function hasText(fragment)
		for _, d in briefGui:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, fragment, 1, true) then
				return true
			end
		end
		return false
	end
	check(hasText("ASHGROVE OBSERVATION PROJECT"), "page 1 is the project")
	for i = 1, 4 do
		local nextButton = buttonText("NEXT")
		check(nextButton ~= nil, "page " .. i .. " has NEXT")
		if nextButton then
			signalFor(nextButton, "Activated"):Fire()
		end
	end
	check(hasText("THE RULES") or hasText("BEFORE YOU GO IN"), "the pages explain the rules")
	local enter = buttonText("ENTER THE BUILDING")
	check(enter ~= nil, "the last page sends you in")
	if enter then
		signalFor(enter, "Activated"):Fire()
	end
	check(not B:IsOpen() and not State.mouseFree(), "and closes, giving the mouse back")
	-- Alt frees the cursor, Alt again looks again
	local function press(action)
		for _, h in { Registry.InputController.Action } do
			h:Fire(action, true)
		end
	end
	press("FreeMouse")
	check(State.isMouseHeld("manual") and State.mouseFree(), "Alt frees the cursor")
	press("FreeMouse")
	check(not State.mouseFree(), "Alt again locks it")
	B:Open()
	localPlayer:SetAttribute("Status", "DEAD")
	frames(2)
	check(not B:IsOpen(), "being taken closes it")
	localPlayer:SetAttribute("Status", "MENU")
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
	-- one vocabulary for every item's state
	check(ShopPanel.stateOf({ equipped = true, owned = true }, 0) == "EQUIPPED", "state: equipped")
	check(ShopPanel.stateOf({ owned = true }, 0) == "OWNED", "state: owned")
	check(ShopPanel.stateOf({ locked = true, level = 9, price = 100 }, 1e6) == "LOCKED", "state: a level lock wins over the price")
	check(ShopPanel.stateOf({ lock = "ACHIEVEMENT" }, 1e6) == "LOCKED", "state: earned items are locked until earned")
	check(ShopPanel.stateOf({ price = 100 }, 100) == "AFFORD" and ShopPanel.stateOf({ price = 100 }, 99) == "POOR", "state: affordable or not, by the balance")
	-- the answers: a purchase confirms, a refusal says why, a confirm asks first
	local holder = KitM.frame({})
	ShopPanel.build(holder, {
		tabs = function(_, _, onSelect)
			return function(name)
				onSelect(name)
			end
		end,
		backButton = function() end,
	}, "EQUIPMENT")
	frames(1)
	local function texts()
		local list = {}
		for _, d in holder:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				table.insert(list, d.Text)
			end
		end
		return table.concat(list, "|")
	end
	-- select cards until one offers BUY (an affordable piece)
	local buy = nil
	local cards = {}
	for _, d in holder:GetDescendants() do
		if d:IsA("TextButton") and d.Text == "" and d.Selectable then
			table.insert(cards, d)
		end
	end
	for _, card in cards do
		if buy then
			break
		end
		signalFor(card, "Activated"):Fire()
		for _, d in holder:GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, "BUY", 1, true) == 1 then
				buy = d
			end
		end
	end
	check(buy ~= nil, "an affordable item offers BUY")
	if buy then
		signalFor(buy, "Activated"):Fire()
		check(string.find(texts(), "CONFIRM PURCHASE", 1, true) ~= nil, "buying asks to confirm first")
		local confirmBtn = nil
		for _, d in holder:GetDescendants() do
			if d:IsA("TextButton") and d.Text == "CONFIRM" then
				confirmBtn = d
			end
		end
		if confirmBtn then
			signalFor(confirmBtn, "Activated"):Fire()
		end
		check(buy.Text == "…", "after confirming, the button waits for the server")
	end
	fire("ShopResult", { action = "buy", id = "FL_INDUSTRIAL", ok = false, reason = "Not enough Echoes." })
	frames(1)
	check(string.find(texts(), "Not enough Echoes.", 1, true) ~= nil, "a refusal shows its reason")
	signalFor(holder, "Destroying"):Fire()
	holder:Destroy()
	-- the premium store: pending items can't be bought, priced ones can
	local PremiumPanel = requireModule(clientRoot.UI.PremiumPanel)
	local ph = KitM.frame({})
	PremiumPanel.build(ph, { backButton = function() end })
	frames(1)
	local seen = {}
	for _, d in ph:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			seen[d.Text] = d
		end
	end
	check(seen["PENDING SETUP"] ~= nil and seen["NOT AVAILABLE YET"] ~= nil, "premium: an item with no id says PENDING SETUP and can't be bought")
	check(seen["R$ 75"] ~= nil, "premium: a configured item shows its Roblox price in Robux")
	check(seen["OWNED"] ~= nil, "premium: an owned finish says OWNED")
	local premiumBuy = seen["BUY"]
	check(premiumBuy ~= nil and premiumBuy.Active, "premium: a configured item offers BUY")
	if premiumBuy then
		signalFor(premiumBuy, "Activated"):Fire()
		check(premiumBuy.Text == "WAITING FOR ROBLOX…", "premium: the card waits for Roblox and the server")
	end
	fire("PremiumResult", { key = "SKIN_CANDLE", ok = false, reason = "Purchase cancelled." })
	frames(1)
	local cancelled = false
	for _, d in ph:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Purchase cancelled." then
			cancelled = true
		end
	end
	check(cancelled, "premium: a cancelled purchase says so")
	signalFor(ph, "Destroying"):Fire()
	ph:Destroy()
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
--[[
	The rules of the hit (ScareController): it lands on the very call that
	delivers the death (no frame of warning); the camera keeps the exact
	CFrame and field of view it had, whatever the pitch; every light around
	is off locally and the scare's own light is the only one that reaches its
	head; Lighting, HUD and sound go dark; the face is in front of the
	lens at the distance for the player's field of view; and everything comes
	back exactly as it was, even when a server tween lands mid-scare.
]]
do
	local Lighting = game:GetService("Lighting")
	local SoundService = game:GetService("SoundService")
	local ScareController = Registry.ScareController
	local camera = workspace.CurrentCamera
	-- the death fired earlier in this test clears the "Death" camera override
	-- 6.2 s later (DeathController): let it finish before these start
	task.wait(6.5)
	frames(3)
	-- Lune stores CFrames as 32-bit floats: compare a view within a hair
	local function sameView(a: CFrame, b: CFrame): boolean
		return (a.Position - b.Position).Magnitude < 1e-4 and a.LookVector:Dot(b.LookVector) > 1 - 1e-4 and a.UpVector:Dot(b.UpVector) > 1 - 1e-4
	end
	-- a building around the camera: a lit fixture (LightController), a static
	-- lamp, a lamp that is off, a sky, a server grade that lifts the black
	local fixture = Instance.new("Model")
	fixture.Name = "TestFixture"
	local housing = Instance.new("Part")
	housing.Anchored = true
	housing.Position = Vector3.new(0, 10, -4)
	housing.Parent = fixture
	local fixtureLight = Instance.new("PointLight")
	fixtureLight.Name = "Light"
	fixtureLight.Range = 30
	fixtureLight.Parent = housing
	fixture.PrimaryPart = housing
	fixture:SetAttribute("Mode", "on")
	fixture:SetAttribute("Circuit", "MAIN")
	fixture:SetAttribute("BaseBrightness", 1)
	fixture.Parent = workspace
	fixture:AddTag("Fixture")
	env.tagAdded("Fixture", fixture)
	local lampPart = Instance.new("Part")
	lampPart.Name = "TestLamp"
	lampPart.Anchored = true
	lampPart.Position = Vector3.new(3, 4, -2)
	lampPart.Parent = workspace
	local lamp = Instance.new("SpotLight")
	lamp.Range = 25
	lamp.Enabled = true
	lamp.Parent = lampPart
	local deadLamp = Instance.new("SurfaceLight")
	deadLamp.Enabled = false
	deadLamp.Parent = lampPart
	-- Lune does not fire DescendantAdded: tell the light index by hand
	for _, l in { fixtureLight, lamp, deadLamp } do
		signalFor(workspace, "DescendantAdded"):Fire(l)
	end
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.Parent = Lighting
	local serverGrade = Instance.new("ColorCorrectionEffect")
	serverGrade.Name = "TestGrade"
	serverGrade.Brightness = 0.03
	serverGrade.Parent = Lighting
	local prevPower = workspace:GetAttribute("Power")
	workspace:SetAttribute("Power", true)
	Lighting.Ambient = Color3.fromRGB(44, 42, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(34, 38, 46)
	Lighting.Brightness = 0.6
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 1
	localPlayer:SetAttribute("Flashlight", true)
	-- stand under the fixture (light LOD)
	Registry.CameraController:SetOverride("TestView", 49, function()
		return CFrame.new(0, 4.5, 2), 74
	end)
	task.wait(0.1)
	frames(5)
	check(fixtureLight.Enabled, "test fixture lit before the scare")

	local LIGHTING = { "Ambient", "OutdoorAmbient", "Brightness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }
	local function snapshot()
		local snap = {}
		for _, prop in LIGHTING do
			snap["Lighting." .. prop] = tostring((Lighting :: any)[prop])
		end
		snap["Lighting.ExposureCompensation"] = tostring(Lighting.ExposureCompensation)
		snap.sky = tostring(sky.Parent)
		snap.grade = tostring(serverGrade.Enabled)
		snap.lamp = tostring(lamp.Enabled)
		snap.deadLamp = tostring(deadLamp.Enabled)
		for _, g in playerGui:GetChildren() do
			if g:IsA("LayerCollector") then
				snap["gui." .. g.Name] = tostring(g.Enabled)
			end
		end
		for _, g in SoundService:GetChildren() do
			if g:IsA("SoundGroup") then
				snap["group." .. g.Name] = string.format("%.3f", g.Volume)
			end
		end
		snap.workspace = tostring(#workspace:GetChildren())
		snap.lightingChildren = tostring(#Lighting:GetChildren())
		return snap
	end
	local function restored(before, label)
		local after = snapshot()
		for k, v in before do
			check(after[k] == v, label .. ": " .. k .. " restored (" .. v .. " -> " .. tostring(after[k]) .. ")")
		end
	end
	local function scareRig(): Model?
		for _, d in workspace:GetChildren() do
			if d.Name == "ObserverScare" then
				return d
			end
		end
		return nil
	end
	-- during the scare: only its own light, and it reaches the head
	local function onlyItsLight(label)
		local rig = scareRig()
		local head = rig and rig:FindFirstChild("Head")
		local others, its = {}, nil
		for _, d in workspace:GetDescendants() do
			if d:IsA("Light") and d.Enabled then
				if rig and d:IsDescendantOf(rig) and d.Parent.Name == "ScareLight" then
					its = d
				else
					table.insert(others, d:GetFullName())
				end
			end
		end
		check(#others == 0, label .. ": no other light on: " .. table.concat(others, ", "))
		check(its ~= nil and head ~= nil and (its.Parent.CFrame.Position - head.CFrame.Position).Magnitude < its.Range, label .. ": the scare light reaches its head")
		check(its ~= nil and its.Range <= 4.5, label .. ": the scare light has a short reach")
	end
	local function darkNow(label)
		check(State.scareDark, label .. ": the scare owns the screen")
		for _, prop in LIGHTING do
			local v = (Lighting :: any)[prop]
			check(v == 0 or v == Color3.new(0, 0, 0), label .. ": Lighting." .. prop .. " is zero")
		end
		check(sky.Parent == Lighting, label .. ": the sky is left alone (the black box hides it)")
		check(Lighting.ExposureCompensation > 0.5, label .. ": exposure raised for its lit face")
		check(not serverGrade.Enabled, label .. ": no grade lifting the black")
		for _, g in playerGui:GetChildren() do
			if g:IsA("LayerCollector") and g.Name ~= "Overlay" then
				check(not g.Enabled, label .. ": HUD hidden (" .. g.Name .. ")")
			end
		end
		for _, g in SoundService:GetChildren() do
			if g:IsA("SoundGroup") and g.Name ~= "ScareHit" then
				check(g.Volume == 0, label .. ": " .. g.Name .. " is silent")
			end
		end
		check(workspace:FindFirstChild("ScareDark") ~= nil, label .. ": the black box is up")
		onlyItsLight(label)
	end

	local cases = {}
	for _, variant in { "behind", "side", "front", "dark", "door", "mirror", "mimic" } do
		table.insert(cases, { variant = variant, pitch = 0, beat = 0.5 })
	end
	for _, pitch in { -75, 60 } do
		for _, beat in { 0, 1 } do
			table.insert(cases, { variant = "front", pitch = pitch, beat = beat })
		end
	end
	-- the debug profile runs too (prints a report after each scare)
	workspace:SetAttribute("ScareProfile", true)
	for i, case in cases do
		local label = string.format("%s, pitch %d, beat %.1f", case.variant, case.pitch, case.beat)
		-- the player's view, held by an override just under the death's (no character in Lune)
		local view = CFrame.new(Vector3.new(i * 0.7, 4.5, 2)) * CFrame.Angles(0, math.rad(i * 37), 0) * CFrame.Angles(math.rad(case.pitch), 0, 0)
		Registry.CameraController:SetOverride("TestView", 49, function()
			return view, 74
		end)
		frames(3)
		-- what the player is seeing right now (any shake from earlier effects included)
		local seen = camera.CFrame
		local fov = camera.FieldOfView
		local before = snapshot()
		local finished = false
		local ok, err = pcall(function()
			ScareController:Death({ variant = case.variant, beat = case.beat, sequence = "turn", position = view.Position - Vector3.new(0, 1.5, 0), mimicName = "Friend" }, function()
				finished = true
			end)
		end)
		check(ok, "death " .. label .. ": " .. tostring(err))
		-- the hit is already there: no frame has run since the death arrived
		local f = ScareController.LastFrame
		check(f ~= nil and f.variant == case.variant and f.impactAt == 0, "death " .. label .. ": the hit lands on the first frame")
		check(scareRig() ~= nil, "death " .. label .. ": its face is there before the first frame")
		if f then
			check(f.inFront, "death " .. label .. ": the face is in front of the camera")
			check(math.abs(f.distance - f.expected) < 0.01, string.format("death %s: face %.3f studs from the lens (want %.3f)", label, f.distance, f.expected))
			check(f.centred > 0.9999, string.format("death %s: face dead centre (%.5f)", label, f.centred))
			check(f.facing > 0.999, string.format("death %s: face looking into the lens (%.4f)", label, f.facing))
			check(sameView(f.camera, seen), "death " .. label .. ": the scare used the player's own view (" .. tostring(f.camera) .. " vs " .. tostring(seen) .. ")")
		end
		darkNow("death " .. label)
		-- a server tween lands mid-scare: it is what comes back afterwards
		Lighting.Ambient = Color3.fromRGB(50, 40, 30)
		before["Lighting.Ambient"] = tostring(Color3.fromRGB(50, 40, 30))
		local moved, fovMoved, steps = false, false, 0
		-- it is never a still picture: its head moves on every frame
		local lastHead, frozenFrames = nil, 0
		local deadline = os.clock() + 4
		while not finished and os.clock() < deadline do
			frames(1)
			steps += 1
			local rig = scareRig()
			local head = rig and rig:FindFirstChild("Head")
			if head then
				if lastHead and head.CFrame == lastHead then
					frozenFrames += 1
				end
				lastHead = head.CFrame
			end
			-- the view only shakes: the lens stays put, the angle within a few degrees
			if (camera.CFrame.Position - seen.Position).Magnitude > 1e-3 or camera.CFrame.LookVector:Dot(seen.LookVector) < math.cos(math.rad(6)) then
				moved = true
			end
			if math.abs(camera.FieldOfView - fov) > 1e-4 then
				fovMoved = true
			end
			if steps % 10 == 1 and not finished then
				darkNow("death " .. label .. " (frame " .. steps .. ")")
			end
			task.wait(1 / 60)
		end
		check(finished, "death " .. label .. " reaches the black screen")
		check(not moved, "death " .. label .. ": the camera only shakes (never moves, never turns away)")
		check(not fovMoved, "death " .. label .. ": the field of view never changed")
		check(frozenFrames == 0, string.format("death %s: its face moves on every frame (%d frozen frames)", label, frozenFrames))
		task.wait(0.25)
		frames(3)
		check(not ScareController:IsActive() and not State.scareDark, "death " .. label .. " cleans up")
		check(scareRig() == nil and workspace:FindFirstChild("ScareDark") == nil, "death " .. label .. ": rig and black box gone")
		Registry.CameraController:ClearOverride("Death")
		Registry.CameraController:ClearOverride("TestView")
		restored(before, "death " .. label)
		Registry.EffectsController:Fade(0, 0)
	end

	workspace:SetAttribute("ScareProfile", nil)
	-- its motion: jumps between held poses, starting on the hit
	check(#ScareController.DeathKeys >= 2 and ScareController.DeathKeys[1].at == 0, "the death has its keyed motion, starting on the hit")
	-- no headbutts: no key rolls or turns the head or neck to a side
	local sideways = 0
	for _, key in ScareController.DeathKeys do
		for _, cf in { key.head or CFrame.identity, key.neck or CFrame.identity } do
			local _, ry, rz = cf:ToEulerAnglesXYZ()
			if math.abs(math.deg(ry)) > 1 or math.abs(math.deg(rz)) > 1 then
				sideways += 1
			end
		end
	end
	check(sideways == 0, "no jerks of the head to the sides (" .. sideways .. ")")

	-- the short scare: same rules, half a second, then the camera is yours again
	do
		local view = CFrame.new(2, 4.5, 3) * CFrame.Angles(0, math.rad(20), 0) * CFrame.Angles(math.rad(-30), 0, 0)
		Registry.CameraController:SetOverride("TestView", 49, function()
			return view, 74
		end)
		frames(3)
		local seen = camera.CFrame
		local before = snapshot()
		ScareController:Flash("test")
		local f = ScareController.LastFrame
		check(f ~= nil and f.variant == "flash" and math.abs(f.distance - f.expected) < 0.01 and f.inFront, "short scare: its face in front of the lens on the first frame")
		darkNow("short scare")
		local moved = false
		for _ = 1, 10 do
			frames(1)
			moved = moved or (camera.CFrame.Position - seen.Position).Magnitude > 1e-3 or camera.CFrame.LookVector:Dot(seen.LookVector) < math.cos(math.rad(6))
		end
		check(not moved, "short scare: the camera only shakes")
		task.wait(0.6)
		frames(3)
		check(not ScareController:IsActive() and not Registry.CameraController:IsRegistered("Scare"), "short scare gives the camera back")
		Registry.CameraController:ClearOverride("TestView")
		restored(before, "short scare")
	end

	-- cut short: a death arriving during the short scare replaces it, and
	-- everything still comes back
	do
		local before = snapshot()
		ScareController:Flash("test")
		local finished = false
		ScareController:Death({ variant = "front", beat = 0 }, function()
			finished = true
		end)
		local deadline = os.clock() + 4
		while not finished and os.clock() < deadline do
			frames(1)
			task.wait(1 / 60)
		end
		task.wait(0.3)
		frames(3)
		check(finished and not State.scareDark and scareRig() == nil, "a death cutting a short scare cleans up")
		check(not Registry.CameraController:IsRegistered("Scare"), "the cut short scare let go of the camera")
		Registry.CameraController:ClearOverride("Death")
		restored(before, "death over a short scare")
		Registry.EffectsController:Fade(0, 0)
	end

	-- the hit is heard over the silence, through its own group
	local group = SoundService:FindFirstChild("ScareHit")
	check(group ~= nil and group:IsA("SoundGroup") and group.Volume > 0, "the hit has its own audible group")

	-- out of the workspace first, so LightController lets go of it
	fixture.Parent = nil
	frames(2)
	fixture:Destroy()
	lampPart:Destroy()
	serverGrade:Destroy()
	workspace:SetAttribute("Power", prevPower)
	localPlayer:SetAttribute("Flashlight", false)
end
-- the admin scare test: plays, gives the camera back, reports the frame
do
	Registry.CameraController:ClearOverride("Death")
	local okTest = pcall(function()
		fire("Effect", { name = "ScareTest", variant = "front", sequence = "stillness", beat = 0.5 })
	end)
	check(okTest, "admin scare test starts")
	local deadline = os.clock() + 5
	while (Registry.ScareController:IsActive() or Registry.CameraController:IsRegistered("Death")) and os.clock() < deadline do
		frames(2)
		task.wait(0.05)
	end
	task.wait(0.8)
	frames(3)
	check(not Registry.ScareController:IsActive(), "admin scare test finishes")
	check(not Registry.CameraController:IsRegistered("Death"), "admin scare test gives the camera back (active " .. tostring(Registry.ScareController:IsActive()) .. ")")
	local f = Registry.ScareController.LastFrame
	check(f ~= nil and f.facing > 0.95 and f.inFront and math.abs(f.distance - f.expected) < 0.05, "admin scare test framed the face")
end
-- the scare's local rig follows the sculpted meshes as they arrive: the
-- server adds them to ReplicatedStorage.ObserverMeshes one at a time, and
-- a rig cached with the first ones must not keep a part-built (boxy) head
do
	local MeshMeta = requireModule(RS.Shared.Config.ObserverMeshMeta)
	local folder = Instance.new("Folder")
	folder.Name = "ObserverMeshes"
	local function addMesh(name)
		local mp = Instance.new("MeshPart")
		mp.Name = name
		mp.Size = MeshMeta[name].size
		mp.Parent = folder
	end
	addMesh("UpperTorso")
	folder.Parent = RS
	local function scareHead()
		Registry.ScareController:Flash("test")
		local rig = nil
		for _, d in workspace:GetChildren() do
			if d.Name == "ObserverScare" then
				rig = d
			end
		end
		local hasHead = rig ~= nil and rig:FindFirstChild("HeadMesh") ~= nil
		local hasTorso = rig ~= nil and rig:FindFirstChild("UpperTorsoMesh") ~= nil
		task.wait(0.6)
		frames(3)
		return hasTorso, hasHead
	end
	local torso, head = scareHead()
	check(torso and not head, "scare rig dressed with the meshes there so far")
	for _, name in { "Head", "Neck", "LowerTorso" } do
		addMesh(name)
	end
	torso, head = scareHead()
	check(torso and head, "scare rig picks up meshes that arrive later (no boxy head)")
	folder:Destroy()
end
-- the mimic's lunge: its own face (a stand-in model with a head)
do
	local fake = Instance.new("Model")
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Position = Vector3.new(0, 5, -4)
	head.Parent = fake
	fake.Parent = workspace
	local okLunge = pcall(function()
		fire("Effect", { name = "Jumpscare", kind = "mimic", model = fake })
	end)
	check(okLunge, "mimic lunge scare")
	frames(3)
	task.wait(0.9)
	frames(2)
	check(not Registry.CameraController:IsRegistered("MimicLunge"), "mimic lunge gives the camera back")
	fake:Destroy()
end
local okFlash, flashErr = pcall(function()
	Registry.ScareController:Flash("mimic")
end)
check(okFlash, "short scare: " .. tostring(flashErr))
task.wait(0.6)
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

-- the film (FilmController): at most two grain layers; with the grain ids at 0
-- and no EditableImage (as here) it switches itself off instead of breaking
do
	local film = Registry.FilmController
	check(film:LayerCount() <= 2, "the grain is at most two layers")
	local AssetIds = requireModule(RS.Shared.Config.AssetIds)
	if AssetIds.Film.grain_light == 0 and AssetIds.Film.grain_dark == 0 and film:LayerCount() == 0 then
		-- no sheets and no EditableImage (as here): the speck field, needing nothing
		check(film:IsAvailable() and film:Mode() == "specks", "without textures the grain falls back to specks (" .. film:Mode() .. ")")
		local filmGui = playerGui:FindFirstChild("Film")
		local holder = filmGui and filmGui:FindFirstChild("Specks")
		check(holder ~= nil and #holder:GetChildren() <= 700, "a bounded speck field")
		frames(4)
		local shown = 0
		for _, s in holder and holder:GetChildren() or {} do
			if s.Visible then
				shown += 1
			end
		end
		check(shown > 0 and shown <= 700, "specks are scattered on screen (" .. shown .. ")")
		State.settings.filmGrain = false
		frames(4)
		local still = 0
		for _, s in holder and holder:GetChildren() or {} do
			if s.Visible then
				still += 1
			end
		end
		check(still == 0, "turning film grain off hides every speck")
		State.settings.filmGrain = true
	end
	local weave = film:Weave()
	check(typeof(weave) == "CFrame", "the camera can always read the weave")
	film:Spike(0.2)
	frames(3)
	check(true, "a scare spike does not break the film")
end

-- blackouts: a door eases open on its own (locally) and The Observer's eyes
do
	local door = Instance.new("Model")
	door.Name = "TestDoor"
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Anchored = true
	leaf.Size = Vector3.new(4, 7, 0.3)
	leaf.CFrame = CFrame.new(300, 3.5, 300)
	leaf.Parent = door
	door.PrimaryPart = leaf
	door:SetAttribute("ClosedCFrame", CFrame.new(300, 3.5, 300))
	door:SetAttribute("OpenCFrame", CFrame.new(300, 3.5, 300) * CFrame.Angles(0, math.rad(90), 0))
	door:SetAttribute("Open", false)
	door.Parent = workspace
	door:AddTag("Door")
	env.tagAdded("Door", door)
	task.wait(0.1)
	local doors = Registry.DoorController
	check(doors:NearestClosed(Vector3.new(300, 3.5, 305), 26) == door, "a closed door nearby is found")
	check(doors:Creak(door), "it can creak open")
	task.wait(1.8)
	frames(2)
	local turned = math.deg(math.acos(math.clamp(leaf.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)), -1, 1)))
	check(turned > 5 and turned < 20, string.format("it eased a hand's width open (%.1f degrees)", turned))
	check(door:GetAttribute("Open") == false, "the server's door is untouched")
	door:SetAttribute("Locked", true)
	task.wait(1.6)
	check(doors:NearestClosed(Vector3.new(300, 3.5, 305), 26) == nil, "a locked door never creaks open")
	door:Destroy()
	local rig = Registry.BlackoutFX:EyesRig()
	check(rig ~= nil, "The Observer's eyes come from its own rig")
	if rig then
		local eyes, others = 0, 0
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				if string.find(d.Name, "Eyeball") or d.Name == "Iris" or d.Name == "Pupil" then
					eyes += 1
				else
					others += 1
				end
			end
		end
		check(eyes >= 2 and others == 0, string.format("only its eyes show (%d eye parts, %d others)", eyes, others))
	end
end

-- the menu cinematic again, with its own light (MenuLook)
do
	local VS = requireModule(RS.Shared.VisualStandards)
	local Lighting = game:GetService("Lighting")
	local before = Lighting.ExposureCompensation
	localPlayer:SetAttribute("Status", "MENU")
	frames(5)
	local lights = workspace:FindFirstChild("MenuLights")
	check(Registry.MenuLook:IsActive(), "the menu has its own light")
	check(lights ~= nil and #lights:GetChildren() >= 4, "bare bulbs hang in the menu's shots")
	check(math.abs(Lighting.ExposureCompensation - VS.MenuLook.exposure) < 1e-3, "the menu's exposure is applied")
	check(Lighting:FindFirstChild("MenuGrade") ~= nil, "the menu's grade is on")
	localPlayer:SetAttribute("Status", "LOBBY")
	frames(3)
	check(workspace:FindFirstChild("MenuLights") == nil and Lighting:FindFirstChild("MenuGrade") == nil, "no menu light is left behind")
	check(math.abs(Lighting.ExposureCompensation - before) < 1e-3, "the server's exposure is back")
	localPlayer:SetAttribute("Status", "MENU")
	frames(5)
end

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
	for _, panel in { "JOURNAL", "SHOP", "PREMIUM", "SETTINGS" } do
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
	-- changes are spread over several checks (a few groups at a time): settle
	local function settle(pos)
		for _ = 1, 100 do
			DetailLOD:Update(pos)
		end
	end
	settle(camPos)
	local hiddenWithIt = DetailLOD:HiddenCount()
	group:SetAttribute("Center", camPos + Vector3.new(0, 0, 5))
	settle(camPos)
	check(DetailLOD:HiddenCount() == hiddenWithIt - 1, "near detail group shown again")
	-- no popping on the line: hidden beyond lod + 10 %, shown within lod - 10 %
	local VisualStandards = env.requireModule(game:GetService("ReplicatedStorage").Shared.VisualStandards)
	local lod = VisualStandards.tier(Registry.AccessibilityController:Quality()).detailLod
	local function at(distance)
		group:SetAttribute("Center", camPos + Vector3.new(0, 0, distance + 10))
		settle(camPos)
		return DetailLOD:HiddenCount()
	end
	local shown = at(lod * 0.5)
	check(at(lod * 1.05) == shown, "just past the LOD distance it stays shown")
	check(at(lod * 1.2) == shown + 1, "far detail group hidden")
	check(at(lod * 0.95) == shown + 1, "just inside the LOD distance it stays hidden")
	check(at(lod * 0.8) == shown, "well inside it is shown")
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

section("marketing campaign")
do
	local mRoot = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Marketing")
	local MC = requireModule(mRoot.MarketingController)
	local Runtime = requireModule(mRoot.Runtime)
	local Screen = requireModule(mRoot.Effects.Screen)
	local Rng = requireModule(mRoot.Utilities.Rng)
	MC.SetOption("HoldAtEnd", 0)
	MC.SetFormat("AUTO")
	MC.SetCameraStyle("AUTO")
	local CAMPAIGN = {
		"Scene_Campaign01_ItHasntMoved",
		"Scene_Campaign02_TheHallwayNeverEnds",
		"Scene_Campaign03_SecurityFootage",
		"Scene_Campaign04_ThisFrameShouldNotExist",
		"Scene_Campaign05_ItHasSeenYou",
	}
	-- who may open it: anyone pressing Play in Studio (user- or group-owned
	-- place), nobody on a public server
	do
		local Access = requireModule(RS.Marketing.MarketingAccess)
		local Config = requireModule(RS.Marketing.MarketingConfig)
		local groupStudio = { studio = true, privateServerId = "", privateServerOwnerId = 0, creatorType = roblox.Enum.CreatorType.Group, creatorId = 555 }
		local userStudio = { studio = true, privateServerId = "", privateServerOwnerId = 0, creatorType = roblox.Enum.CreatorType.User, creatorId = 42 }
		local publicServer = { studio = false, privateServerId = "", privateServerOwnerId = 0, creatorType = roblox.Enum.CreatorType.User, creatorId = 42 }
		check(Access.isAuthorized(987654, Config, groupStudio), "marketing access: a developer in Studio on a group-owned place")
		check(Access.isAuthorized(987654, Config, userStudio), "marketing access: a collaborator in Studio on a user-owned place")
		check(not Access.isAuthorized(42, Config, publicServer), "marketing access: never on a public server, not even the owner")
		check(not Access.isAuthorized(987654, Config, publicServer), "marketing access: never on a public server")
	end
	-- the approved Creator Store recordings: played as recorded (no pitch or
	-- distortion chain), the rest of the library untouched
	do
		local SoundFactory = requireModule(RS.Shared.SoundFactory)
		local AudioLibrary = requireModule(RS.Shared.Config.AudioLibrary)
		local APPROVED = {
			AmbientDrone = 9112775175, ElectricBuzz = 619993906, BoilerRumble = 9112839293, ElectricSurge = 9114247505,
			BreakerFlip = 9120099286, TrackHorror = 9039981149, TrackScaryAtmosphere = 1847064374,
		}
		for key, id in APPROVED do
			local def = AudioLibrary.Sounds[key]
			check(def ~= nil and def.recorded == "rbxassetid://" .. id, "store audio: " .. key .. " uses " .. id)
			local snd = SoundFactory.create(key)
			check(snd ~= nil and snd.SoundId == "rbxassetid://" .. id, "store audio: " .. key .. " plays the recording")
			if snd then
				check(math.abs(snd.PlaybackSpeed - 1) < 0.07, "store audio: " .. key .. " at its own speed (" .. snd.PlaybackSpeed .. ")")
				local processed = false
				for _, e in snd:GetChildren() do
					if e:IsA("DistortionSoundEffect") or e:IsA("PitchShiftSoundEffect") or e:IsA("EqualizerSoundEffect") or e:IsA("TremoloSoundEffect") then
						processed = true
					end
				end
				check(not processed, "store audio: " .. key .. " without the old processing")
				snd:Destroy()
			end
		end
		local whisper = SoundFactory.create("Whisper")
		local sheetUrl = SoundFactory.custom("Whisper")
		check(whisper ~= nil and whisper.SoundId == (sheetUrl or AudioLibrary.Sounds.Whisper.id), "store audio: other sounds unchanged (sheet or sample)")
		if whisper then
			whisper:Destroy()
		end
	end
	-- the seeded random source repeats
	Rng.seed(7)
	local a1, a2 = Rng:NextNumber(), Rng:NextInteger(1, 100)
	Rng.seed(7)
	check(Rng:NextNumber() == a1 and Rng:NextInteger(1, 100) == a2, "campaign: Rng repeats from a seed")
	check(Rng.hash("Scene_X") == Rng.hash("Scene_X") and Rng.hash("Scene_X") ~= Rng.hash("Scene_Y"), "campaign: scene-name seeds are stable and distinct")

	local runtime = function(): Instance?
		return workspace:FindFirstChild("MarketingRuntime")
	end
	local function entity(): Model?
		local rt = runtime()
		local m = rt and rt:FindFirstChild("Entity_it")
		return if m and m:IsA("Model") then m else nil
	end
	-- where a world point lands in the 9:16 frame (vertical FOV kept): -1..1 both ways
	local function project(p: Vector3): (number, number, boolean)
		local cam = workspace.CurrentCamera
		local v = cam.CFrame:PointToObjectSpace(p)
		local t = math.tan(math.rad(cam.FieldOfView) / 2)
		if v.Z >= -0.05 then
			return 0, 0, false
		end
		return v.X / (-v.Z * t * (9 / 16)), v.Y / (-v.Z * t), true
	end
	-- the Observer on screen: its height as a fraction of the frame, eyes in frame?
	local function framing(): (number, boolean, number, string)
		local m = entity()
		if not m then
			return 0, false, 0, ""
		end
		local top, bottom = -math.huge, math.huge
		local eyes, eyesIn = 0, 0
		local eyeAt = ""
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local c = d.CFrame.Position
				local h = d.Size.Y / 2
				for _, y in { h, -h } do
					local _, sy, front = project(c + Vector3.new(0, y, 0))
					if front then
						top = math.max(top, sy)
						bottom = math.min(bottom, sy)
					end
				end
				if string.find(d.Name, "Eyeball") then
					eyes += 1
					local sx, sy, front = project(c)
					eyeAt = string.format("%s(%.2f, %.2f; y %.2f above the feet)", eyeAt, sx, sy, c.Y - m:GetPivot().Position.Y)
					if front and math.abs(sx) <= 0.95 and math.abs(sy) <= 0.95 then
						eyesIn += 1
					end
				end
			end
		end
		local frac = if top > bottom then (math.min(top, 1) - math.max(bottom, -1)) / 2 else 0
		-- eyes only count when it faces the lens (from behind, its head hides them)
		local pivot = m:GetPivot()
		local toCam = (workspace.CurrentCamera.CFrame.Position - pivot.Position) * Vector3.new(1, 0, 1)
		local facesLens = toCam.Magnitude > 0 and pivot.LookVector:Dot(toCam.Unit) > 0.5
		return frac, eyes > 0 and eyesIn == eyes and facesLens, eyes, eyeAt .. (if facesLens then "" else " (FACING AWAY)")
	end
	local function playTo(name: string, untilClock: number, dt: number?)
		while MC.IsPlaying() and MC.GetState().clock < untilClock - 1e-6 do
			renderFns.MarketingStudio(dt or 1 / 30)
		end
	end
	-- CAMPAIGN_PREVIS=<dir>: each key frame's real state (set, figure, lights,
	-- camera, grade) as JSON for tools/blender/render_room.py (previs only)
	local previsDir = process.env.CAMPAIGN_PREVIS
	local function exportFrame(path: string)
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local ObserverRig = requireModule(RS.Shared.ObserverRig)
		local MeshMeta = requireModule(RS.Shared.Config.ObserverMeshMeta)
		local function c3(c)
			return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
		end
		local function v3(v)
			return { v.X, v.Y, v.Z }
		end
		local parts, lights, meshes = {}, {}, {}
		local rt = runtime()
		for _, d in (if rt then rt:GetDescendants() else {}) do
			if d:IsA("BasePart") then
				local cf = d.CFrame
				local inEntity = d.Parent and d.Parent.Name == "Entity_it"
				local meshName = inEntity and ObserverRig.SegmentMesh[d.Name]
				if meshName and MeshMeta[meshName] then
					local mcf = cf * CFrame.new(MeshMeta[meshName].offset)
					table.insert(meshes, { file = "assets/observer/" .. meshName .. ".obj", maps = "assets/observer/" .. meshName .. "/" .. meshName, bboxCentre = true, color = c3(d.Color), pos = v3(mcf.Position), rx = v3(mcf.RightVector), ry = v3(mcf.UpVector), rz = v3(-mcf.LookVector) })
				elseif inEntity and ObserverRig.MeshDetails[d.Name] then
					-- covered by the smooth mesh
				elseif d.Transparency < 0.95 then
					local shape = "box"
					if d:IsA("Part") and d.Shape == roblox.Enum.PartType.Ball then
						shape = "ball"
					end
					table.insert(parts, { name = d.Name, pos = v3(cf.Position), rx = v3(cf.RightVector), ry = v3(cf.UpVector), rz = v3(-cf.LookVector), size = v3(d.Size), shape = shape, color = c3(d.Color), material = d.Material.Name, variant = "", transparency = d.Transparency, reflectance = 0 })
				end
			elseif d:IsA("Light") and d.Enabled and d.Brightness > 0 and d.Parent and d.Parent:IsA("BasePart") then
				local cf = (d.Parent :: BasePart).CFrame
				local face = if d:IsA("SpotLight") or d:IsA("SurfaceLight") then (d :: any).Face else nil
				local dir = cf.LookVector
				if face == roblox.Enum.NormalId.Back then
					dir = -cf.LookVector
				elseif face == roblox.Enum.NormalId.Top then
					dir = cf.UpVector
				elseif face == roblox.Enum.NormalId.Bottom then
					dir = -cf.UpVector
				elseif face == roblox.Enum.NormalId.Right then
					dir = cf.RightVector
				elseif face == roblox.Enum.NormalId.Left then
					dir = -cf.RightVector
				end
				table.insert(lights, { class = d.ClassName, pos = v3(cf.Position), dir = v3(dir), brightness = d.Brightness, range = d.Range, angle = if d:IsA("PointLight") then 180 else (d :: any).Angle, color = c3(d.Color), shadows = d.Shadows, tag = "on", powered = false, mode = "on", circuit = "NONE" })
			end
		end
		local Lighting = game:GetService("Lighting")
		local cam = workspace.CurrentCamera
		local g = Screen.gradeValues()
		fs.writeFile(path, serde.encode("json", {
			room = path,
			seed = 0,
			min = { 0, 0, 0 },
			max = { 1, 1, 1 },
			parts = parts,
			lights = lights,
			meshes = meshes,
			presets = { SHOT = { ambient = c3(Lighting.Ambient), exposure = Lighting.ExposureCompensation } },
			camera = { eye = v3(cam.CFrame.Position), target = v3(cam.CFrame.Position + cam.CFrame.LookVector * 10), fov = cam.FieldOfView },
			grade = { brightness = g.Brightness, contrast = g.Contrast, saturation = g.Saturation, tint = c3(g.TintColor) },
		}))
	end
	local measured = {}
	for _, name in CAMPAIGN do
		local def = MC.GetScene(name)
		check(def ~= nil, "campaign scene registered: " .. name)
		if def then
			check(def.Format == "SOCIAL_VERTICAL" and type(def.Seed) == "number" and def.Duration >= 8 and def.Duration <= 25 and def.Isolated == true, "campaign scene spec (9:16, seeded, 8-25 s, isolated): " .. name)
			MC.PlayScene(name)
			check(Screen.getFormat() == "SOCIAL_VERTICAL", "campaign: the scene's own format is used: " .. name)
			MC.StopScene()
		end
	end
	-- key frames: { scene, clock, min height fraction, max, eyes must be in frame }
	local KEYS = {
		{ "Scene_Campaign01_ItHasntMoved", 1.0, 0.06, 0.35, false, "first second" },
		{ "Scene_Campaign01_ItHasntMoved", 3.5, 0.06, 0.35, false, "far, under the white tube" },
		{ "Scene_Campaign01_ItHasntMoved", 6.5, 0.08, 0.45, false, "one lamp closer" },
		{ "Scene_Campaign01_ItHasntMoved", 9.5, 0.12, 0.6, false, "closer" },
		{ "Scene_Campaign01_ItHasntMoved", 11.5, 0.2, 1, false, "close" },
		{ "Scene_Campaign01_ItHasntMoved", 13.0, 0.3, 1, true, "the eyes in the dark" },
		{ "Scene_Campaign02_TheHallwayNeverEnds", 1.0, 0, 0, false, "first second (no figure)" },
		{ "Scene_Campaign02_TheHallwayNeverEnds", 2.4, 0, 0, false, "passing B-13" },
		{ "Scene_Campaign02_TheHallwayNeverEnds", 13.6, 0.3, 1, true, "turned round" },
		{ "Scene_Campaign03_SecurityFootage", 1.0, 0, 0, false, "first second (empty room)" },
		{ "Scene_Campaign03_SecurityFootage", 7.0, 0.08, 0.6, false, "in the far corner" },
		{ "Scene_Campaign03_SecurityFootage", 10.5, 0.15, 0.8, false, "mid-room" },
		{ "Scene_Campaign03_SecurityFootage", 12.6, 0.3, 1, true, "under the lens" },
		{ "Scene_Campaign04_ThisFrameShouldNotExist", 1.0, 0, 0, false, "first second (nothing)" },
		{ "Scene_Campaign04_ThisFrameShouldNotExist", 3.42, 0.5, 1, true, "the frame" },
		{ "Scene_Campaign05_ItHasSeenYou", 1.0, 0.15, 0.8, false, "first second (it is already there)" },
		{ "Scene_Campaign05_ItHasSeenYou", 5.0, 0.15, 0.8, true, "eyes light up" },
		{ "Scene_Campaign05_ItHasSeenYou", 10.4, 0.2, 1, true, "after the push-in" },
	}
	for _, k in KEYS do
		MC.PlayScene(k[1])
		playTo(k[1], k[2], 1 / 60)
		local frac, eyesOk, eyes, eyeAt = framing()
		if previsDir then
			exportFrame(string.format("%s/%s_%05.2f.json", previsDir, k[1], k[2]))
		end
		table.insert(measured, string.format("%s @%.2fs (%s): height %.2f of frame, eyes %s %s", k[1], k[2], k[6], frac, if eyes == 0 then "none" elseif eyesOk then "in frame" else "OUT", eyeAt))
		check(frac >= k[3] and frac <= k[4], string.format("campaign framing %s @%.2f %s: %.2f in [%.2f, %.2f]", k[1], k[2], k[6], frac, k[3], k[4]))
		if k[5] then
			check(eyesOk, string.format("campaign framing %s @%.2f: both eyes in the 9:16 frame", k[1], k[2]))
		end
		MC.StopScene()
	end
	for _, line in measured do
		print("  " .. line)
	end
	-- V7: the frame exists for 0.05 s: at least one frame of a 30 fps recording, three at 60
	for _, fps in { 30, 60 } do
		MC.PlayScene("Scene_Campaign04_ThisFrameShouldNotExist")
		local frames = 0
		while MC.IsPlaying() and MC.GetState().clock < 5 do
			renderFns.MarketingStudio(1 / fps)
			if entity() then
				frames += 1
			end
		end
		MC.StopScene()
		check(frames >= 1 and frames <= math.ceil(0.05 * fps) + 1, string.format("campaign: the one frame lasts %d frame(s) at %d fps", frames, fps))
		print(string.format("  V7 frame visible for %d frame(s) at %d fps", frames, fps))
	end
	-- determinism: two takes, same camera and same figure at the same times
	for _, name in CAMPAIGN do
		local takes = {}
		for take = 1, 2 do
			local samples = {}
			MC.PlayScene(name)
			local n = 0
			while MC.IsPlaying() do
				renderFns.MarketingStudio(1 / 30)
				n += 1
				if n % 15 == 0 then
					local m = entity()
					table.insert(samples, tostring(workspace.CurrentCamera.CFrame) .. "|" .. (if m then tostring(m:GetPivot()) else "-"))
				end
			end
			takes[take] = samples
		end
		local same = #takes[1] == #takes[2] and #takes[1] > 0
		for i = 1, #takes[1] do
			if takes[1][i] ~= takes[2][i] then
				same = false
			end
		end
		check(same, "campaign: two takes are identical (camera + figure): " .. name)
		check(Runtime.isClean(), "campaign: clean after " .. name)
	end
	MC.SetFormat("SOCIAL_VERTICAL")
end

section("summary")
print(string.format("%d checks, %d failures, %d controllers", checks, failures, #controllers))
process.exit(if failures == 0 then 0 else 1)
