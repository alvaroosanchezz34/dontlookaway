--[[
	MenuController
	Main menu over a slow cinematic tour of the building, the pause menu, and the
	panels: HOW TO PLAY, JOURNAL (anomalies + record), SHOP, SETTINGS, CREDITS.
	Also the one-time flashing lights warning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local Achievements = require(ReplicatedStorage.Shared.Catalog.Achievements)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local MenuController = {}

local C = Kit.C
local menuGui: ScreenGui
local panelGui: ScreenGui
local mainMenu: Frame
local pauseMenu: Frame
local profileLabel: TextLabel
local title: TextLabel
local currentPanel: Frame? = nil
local currentPanelName: string? = nil
local settingsDirty = false
local lastSettingsSend = 0

------------------------------------------------------------------------------------
-- Menu cinematic
------------------------------------------------------------------------------------

local SHOTS = {
	{ from = CFrame.lookAt(Vector3.new(96, 6, 98), Vector3.new(60, 7, 60)), to = CFrame.lookAt(Vector3.new(84, 6, 84), Vector3.new(58, 7, 54)) },
	{ from = CFrame.lookAt(Vector3.new(8, 6.5, 44), Vector3.new(150, 5, 44)), to = CFrame.lookAt(Vector3.new(40, 6.5, 44), Vector3.new(150, 5, 44)) },
	{ from = CFrame.lookAt(Vector3.new(150, -12, 44), Vector3.new(40, -13, 44)), to = CFrame.lookAt(Vector3.new(125, -12, 43), Vector3.new(40, -13, 44)) },
	{ from = CFrame.lookAt(Vector3.new(150, 24, 20), Vector3.new(120, 23, 10)), to = CFrame.lookAt(Vector3.new(140, 24, 26), Vector3.new(118, 23, 12)) },
	{ from = CFrame.lookAt(Vector3.new(80, 6, 162), Vector3.new(80, 10, 120)), to = CFrame.lookAt(Vector3.new(80, 5, 146), Vector3.new(80, 10, 120)) },
}
local SHOT_TIME = 15

local function menuCamera(): CFrame?
	if not Workspace:GetAttribute("MapReady") then
		local lobbyCam = Workspace:GetAttribute("LobbyCamera")
		return if typeof(lobbyCam) == "CFrame" then lobbyCam else nil
	end
	local t = os.clock() / SHOT_TIME
	local index = math.floor(t) % #SHOTS + 1
	local alpha = t - math.floor(t)
	local shot = SHOTS[index]
	-- slow dolly with a breath of handheld drift
	local cf = shot.from:Lerp(shot.to, alpha)
	local n = os.clock() * 0.35
	return cf * CFrame.Angles(math.noise(n, 3) * 0.012, math.noise(n, 7) * 0.016, 0)
end

------------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------------

local function closePanel()
	if currentPanel then
		currentPanel:Destroy()
		currentPanel = nil
		currentPanelName = nil
	end
	if State.status ~= "MENU" then
		State.setUIOpen(pauseMenu.Visible)
	end
	if mainMenu.Visible then
		GuiService.SelectedObject = mainMenu:FindFirstChild("Buttons") and mainMenu.Buttons:FindFirstChildWhichIsA("GuiButton")
	end
end

local function backButton(body: Instance)
	return Kit.button({ Text = "BACK", Size = UDim2.fromOffset(150, 42), Position = UDim2.new(1, -150, 1, -42), Parent = body }, function()
		Kit.sound("UIBack")
		closePanel()
	end)
end

local function tabs(parent: Instance, names: { string }, onSelect: (string) -> ())
	local bar = Kit.frame({ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = parent })
	Kit.list(bar, 8, true)
	local buttons = {}
	local function select(name: string)
		for n, b in buttons do
			b.TextColor3 = if n == name then C.Text else C.Muted
			b.BackgroundTransparency = if n == name then 0.1 else 0.6
		end
		onSelect(name)
	end
	for i, name in names do
		local b = Kit.button({ Text = name, Size = UDim2.fromOffset(math.max(96, #name * 11 + 30), 36), TextSize = 14, LayoutOrder = i, Parent = bar }, function()
			select(name)
		end)
		buttons[name] = b
	end
	return select
end

local function howToPlay(body: Frame)
	local scroll = Kit.scroll(body, { Size = UDim2.new(1, 0, 1, -56) })
	Kit.list(scroll, 14)
	local function block(heading: string, text: string, order: number)
		local f = Kit.frame({ Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.3, LayoutOrder = order, Parent = scroll })
		Kit.corner(f, 4)
		Kit.padding(f, 16)
		Kit.list(f, 6)
		Kit.text({ Text = heading, Size = UDim2.new(1, 0, 0, 26), FontFace = Kit.F.Heading, TextSize = 20, Parent = f })
		Kit.text({ Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Light, TextSize = 17, TextColor3 = C.TextDim, LayoutOrder = 2, Parent = f })
	end
	local IC = Registry.InputController
	block("THE BUILDING CHANGES WHEN YOU STOP LOOKING", "Paintings, doors, rooms, people. When nobody is looking, something changes. Notice it.", 1)
	block("REPORT ANOMALIES", "Look straight at what changed and hold [" .. IC:Label("Report") .. "]. If you are right, reality snaps back. If you are wrong, something notices. Reach the anomaly quota to release one of the exit locks.", 2)
	block("ESCAPE", "The exit has four locks: restore the POWER, solve the two puzzles the building gives you tonight, and find enough ANOMALIES. Read every note. Keys, fuses and clues are hidden in different rooms every night.", 3)
	block("THE OBSERVER", "It only moves when nobody is looking at it. Keep your eyes on it and back away. But you cannot stare forever: you will blink. Stay together so someone is always watching.", 4)
	block("RULES", "Some anomalies are dangerous. If the lights die and something whispers, keep your light on. If footsteps follow you, don't turn around. If you can't stop staring at something pale, report it. Never open B-13.", 5)
	block("CONTROLS", string.format("Move WASD / left stick / thumbstick.  Sprint [%s].  Interact [%s].  Flashlight [%s].  Report [%s].  Ping [%s] (hold for the wheel).  Items 1-4 / D-pad, use [%s], drop [%s].  Notes [%s].  Menu [%s].", IC:Label("Sprint"), IC:Label("Interact"), IC:Label("Flashlight"), IC:Label("Report"), IC:Label("Ping"), IC:Label("UseItem"), IC:Label("DropItem"), IC:Label("Notes"), IC:Label("Pause")), 6)
	backButton(body)
end

local function journal(body: Frame)
	local profile = State.profile or {}
	local entries = profile.journal or {}
	local found = Util.count(entries)
	Kit.text({ Text = string.format("%d / %d DISCOVERED", found, JournalCatalog.Count), Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.new(0.5, 0, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 15, TextColor3 = C.TextDim, Parent = body })
	local content = Kit.frame({ Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, Parent = body })
	local function showAnomalies(category: string)
		content:ClearAllChildren()
		local scroll = Kit.scroll(content)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(250, 150), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		for _, e in JournalCatalog.List do
			if category == "ALL" or e.category == category then
				local rec = entries[e.id]
				local card = Kit.frame({ BackgroundColor3 = C.PanelLight, BackgroundTransparency = if rec then 0.15 else 0.55, LayoutOrder = e.number, Parent = scroll })
				Kit.corner(card, 4)
				Kit.padding(card, 12)
				Kit.text({ Text = JournalCatalog.format(e.number), Size = UDim2.new(1, 0, 0, 16), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = if rec then JournalCatalog.RarityColors[e.rarity] else C.Muted, Parent = card })
				if rec then
					Kit.stroke(card, JournalCatalog.RarityColors[e.rarity], 1, 0.5)
					Kit.text({ Text = e.name, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 18), FontFace = Kit.F.Heading, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
					Kit.text({ Text = e.rarity .. "  ·  " .. e.category, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 40), FontFace = Kit.F.Light, TextSize = 11, TextColor3 = C.Muted, Parent = card })
					Kit.text({ Text = e.description, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 56), FontFace = Kit.F.Light, TextSize = 13, TextColor3 = C.TextDim, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
					Kit.text({ Text = string.format("seen %d×  ·  first %s", rec.c or 1, os.date("%Y-%m-%d", rec.f or 0)), Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), FontFace = Kit.F.Mono, TextSize = 11, TextColor3 = C.Muted, Parent = card })
				else
					Kit.text({ Text = "UNKNOWN", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 18), FontFace = Kit.F.Heading, TextSize = 17, TextColor3 = C.Muted, Parent = card })
					Kit.text({ Text = "??????????", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 56), FontFace = Kit.F.Mono, TextSize = 15, TextColor3 = C.Line, Parent = card })
				end
			end
		end
	end
	local function showRecord()
		content:ClearAllChildren()
		local scroll = Kit.scroll(content)
		Kit.list(scroll, 8)
		local stats = profile.stats or {}
		local lines = {
			{ "ROUNDS", stats.rounds or 0 },
			{ "ESCAPES", stats.escapes or 0 },
			{ "TIMES CAUGHT", stats.deaths or 0 },
			{ "ANOMALIES REPORTED", stats.anomaliesReported or 0 },
			{ "FALSE REPORTS", stats.falseReports or 0 },
			{ "BEST ESCAPE", if (stats.bestTime or 0) > 0 then Util.formatTime(stats.bestTime) else "-" },
			{ "OBSERVER SIGHTINGS", stats.observerSightings or 0 },
			{ "SECRET ENDINGS", stats.secretEndings or 0 },
		}
		for i, l in lines do
			local row = Kit.frame({ Size = UDim2.new(1, -12, 0, 30), BackgroundTransparency = 1, LayoutOrder = i, Parent = scroll })
			Kit.text({ Text = l[1], Size = UDim2.fromScale(0.6, 1), TextColor3 = C.TextDim, Parent = row })
			Kit.text({ Text = tostring(l[2]), Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, Parent = row })
		end
		Kit.text({ Text = "ACHIEVEMENTS", Size = UDim2.new(1, 0, 0, 40), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 100, Parent = scroll })
		local unlocked = profile.achievements or {}
		for i, a in Achievements.List do
			local has = unlocked[a.id] ~= nil
			local row = Kit.frame({ Size = UDim2.new(1, -12, 0, 46), BackgroundColor3 = C.PanelLight, BackgroundTransparency = if has then 0.2 else 0.7, LayoutOrder = 100 + i, Parent = scroll })
			Kit.corner(row, 4)
			Kit.text({ Text = a.name, Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.fromOffset(12, 0), FontFace = Kit.F.Heading, TextSize = 15, TextColor3 = if has then C.Text else C.Muted, Parent = row })
			Kit.text({ Text = a.description, Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.fromScale(0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Light, TextSize = 13, TextColor3 = C.TextDim, Parent = row })
		end
	end
	local select = tabs(body, { "ALL", "VISUAL", "ENVIRONMENT", "NPC", "PSYCHOLOGICAL", "DANGEROUS", "RECORD" }, function(name)
		if name == "RECORD" then
			showRecord()
		else
			showAnomalies(name)
		end
	end)
	select("ALL")
	backButton(body)
end

local function shop(body: Frame)
	local content = Kit.frame({ Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, Parent = body })
	local balance = Kit.text({ Text = "", Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.new(0.6, 0, 1, -38), TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kit.F.Mono, TextSize = 16, Parent = body })
	local category = "FLASHLIGHT"
	local function render()
		content:ClearAllChildren()
		local ok, data = pcall(function()
			return Net.func("GetShop"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			Kit.text({ Text = "The shop is unavailable right now.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = content })
			return
		end
		balance.Text = "ECHOES  " .. Util.formatNumber(data.echoes or 0)
		local scroll = Kit.scroll(content)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(250, 128), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		for i, item in data.items do
			if item.category == category then
				local def = Cosmetics.get(item.id)
				local card = Kit.frame({ BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = i, Parent = scroll })
				Kit.corner(card, 4)
				Kit.padding(card, 12)
				if def and (def.light or def.accent or def.color) then
					local sw = Kit.frame({ Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -18, 0, 0), BackgroundColor3 = def.light or def.accent or def.color, Parent = card })
					Kit.corner(sw, 9)
				end
				Kit.text({ Text = item.name, Size = UDim2.new(1, -26, 0, 22), FontFace = Kit.F.Heading, TextSize = 17, Parent = card })
				local info = if item.owned then "OWNED" elseif item.price then (Util.formatNumber(item.price) .. " ECHOES") elseif item.lock then item.lock else ""
				Kit.text({ Text = info, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 26), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = card })
				local label, action = nil, nil
				if item.category == "EMOTE" then
					label = if item.owned then "OWNED" else (if item.price then "BUY" else nil)
					action = if not item.owned and item.price then "buy" else nil
				elseif item.equipped then
					label = "EQUIPPED"
				elseif item.owned then
					label, action = "EQUIP", "equip"
				elseif item.price then
					label, action = "BUY", "buy"
				elseif item.lock == "PASS" and item.pass then
					label, action = "GET PASS", "pass"
				end
				if label then
					local b = Kit.button({ Text = label, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 1, -36), TextSize = 14, Style = if action == "buy" or action == "pass" then "primary" else "ghost", Parent = card }, function()
						if action == "pass" then
							Net.event("Shop"):FireServer("pass", item.pass)
						elseif action then
							Net.event("Shop"):FireServer(action, item.id)
							task.delay(0.5, render)
						end
					end)
					b.Active = action ~= nil
				end
			end
		end
	end
	local select = tabs(body, { "FLASHLIGHT", "BEAM", "TRAIL", "EMOTE", "TITLE", "UI" }, function(name)
		category = name
		render()
	end)
	select("FLASHLIGHT")
	Kit.text({ Text = "Cosmetic only. Nothing here helps you survive.", Size = UDim2.new(0.6, 0, 0, 24), Position = UDim2.new(0, 0, 1, -38), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Muted, Parent = body })
	backButton(body)
end

local function sendSettings()
	settingsDirty = true
end

local function settings(body: Frame)
	local s = State.settings
	local scroll = Kit.scroll(body, { Size = UDim2.new(1, 0, 1, -56) })
	Kit.list(scroll, 2)
	local function changed()
		State.SettingsChanged:Fire()
		sendSettings()
	end
	local function slider(label: string, key: string, order: number)
		local row = Kit.slider(scroll, label, s[key], function(v)
			s[key] = v
			changed()
		end)
		row.LayoutOrder = order
	end
	slider("Master volume", "master", 1)
	slider("Music", "music", 2)
	slider("Sound effects", "sfx", 3)
	slider("Ambience", "ambient", 4)
	slider("Interface sounds", "ui", 5)
	local sens = Kit.slider(scroll, "Look sensitivity", (s.sensitivity - 0.05) / 1.95, function(v)
		s.sensitivity = 0.05 + v * 1.95
		changed()
	end, function(v)
		return string.format("%.2f", 0.05 + v * 1.95)
	end)
	sens.LayoutOrder = 6
	local minF, maxF = GameConfig.Camera.MinFOV, GameConfig.Camera.MaxFOV
	local fov = Kit.slider(scroll, "Field of view", (s.fov - minF) / (maxF - minF), function(v)
		s.fov = math.floor(minF + v * (maxF - minF) + 0.5)
		changed()
	end, function(v)
		return tostring(math.floor(minF + v * (maxF - minF) + 0.5))
	end)
	fov.LayoutOrder = 7
	local function toggle(label: string, key: string, order: number)
		local row = Kit.toggle(scroll, label, s[key] == true, function(v)
			s[key] = v
			changed()
		end)
		row.LayoutOrder = order
	end
	toggle("Head bob & motion", "headBob", 8)
	toggle("Camera shake", "cameraShake", 9)
	toggle("Reduced effects (no flashes or glitches)", "reducedEffects", 10)
	toggle("Subtitles", "subtitles", 11)
	toggle("Invert look", "invertY", 12)
	backButton(body)
end

local function credits(body: Frame)
	local lines = {
		GameConfig.GameName,
		GameConfig.Tagline,
		"",
		"An original cooperative psychological horror experience.",
		"Every model, room, sound design and interface was built inside Roblox from parts, materials, lights and the client's built-in sounds.",
		"The score is generative: it is composed while you play.",
		"",
		"No paid advantages. Cosmetics only.",
		"",
		"Thank you for looking.",
	}
	local scroll = Kit.scroll(body, { Size = UDim2.new(1, 0, 1, -56) })
	Kit.list(scroll, 6)
	for i, l in lines do
		Kit.text({ Text = l, Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = if i == 1 then Kit.F.Title elseif i == 2 then Kit.F.Heading else Kit.F.Light, TextSize = if i == 1 then 32 else 18, TextColor3 = if i <= 2 then C.Text else C.TextDim, LayoutOrder = i, Parent = scroll })
	end
	backButton(body)
end

local PANELS = {
	HOWTO = { title = "HOW TO PLAY", build = howToPlay, size = UDim2.fromOffset(920, 820) },
	JOURNAL = { title = "ANOMALY JOURNAL", build = journal, size = UDim2.fromOffset(1400, 880) },
	SHOP = { title = "SHOP", build = shop, size = UDim2.fromOffset(1400, 880) },
	SETTINGS = { title = "SETTINGS", build = settings, size = UDim2.fromOffset(920, 860) },
	CREDITS = { title = "CREDITS", build = credits, size = UDim2.fromOffset(820, 640) },
}

function MenuController:OpenPanel(name: string)
	local def = PANELS[name]
	if not def then
		return
	end
	closePanel()
	local panel, body = Kit.panel(panelGui, def.title, def.size)
	currentPanel = panel
	currentPanelName = name
	State.setUIOpen(true)
	Kit.sound("UIOpen")
	def.build(body)
	if State.inputType == "Gamepad" then
		GuiService.SelectedObject = panel:FindFirstChildWhichIsA("GuiButton", true)
	end
end

function MenuController:IsPanelOpen(): boolean
	return currentPanel ~= nil
end

------------------------------------------------------------------------------------
-- Main & pause menus
------------------------------------------------------------------------------------

local function buildMain()
	mainMenu = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = menuGui })
	local shade = Kit.frame({ Size = UDim2.fromScale(0.55, 1), BackgroundColor3 = Color3.new(), Parent = mainMenu })
	Kit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }), Parent = shade })
	title = Kit.text({ Text = GameConfig.GameName, Size = UDim2.fromOffset(900, 96), Position = UDim2.fromOffset(110, 170), FontFace = Kit.F.Title, TextSize = 84, Parent = mainMenu })
	Kit.text({ Text = GameConfig.Tagline, Size = UDim2.fromOffset(900, 30), Position = UDim2.fromOffset(114, 266), FontFace = Kit.F.Light, TextSize = 22, TextColor3 = C.TextDim, Parent = mainMenu })
	local buttons = Kit.frame({ Name = "Buttons", Size = UDim2.fromOffset(320, 420), Position = UDim2.fromOffset(110, 360), BackgroundTransparency = 1, Parent = mainMenu })
	Kit.list(buttons, 10)
	local entries = {
		{ "PLAY", "primary", function()
			MenuController:Play()
		end },
		{ "HOW TO PLAY", "ghost", function()
			MenuController:OpenPanel("HOWTO")
		end },
		{ "JOURNAL", "ghost", function()
			MenuController:OpenPanel("JOURNAL")
		end },
		{ "SHOP", "ghost", function()
			MenuController:OpenPanel("SHOP")
		end },
		{ "SETTINGS", "ghost", function()
			MenuController:OpenPanel("SETTINGS")
		end },
		{ "CREDITS", "ghost", function()
			MenuController:OpenPanel("CREDITS")
		end },
	}
	for i, e in entries do
		local b = Kit.button({ Text = e[1], Size = UDim2.fromOffset(300, 52), TextSize = 19, Style = e[2], LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left, Parent = buttons }, e[3])
		Kit.padding(b, 0, 22)
	end
	profileLabel = Kit.text({ Text = "", Size = UDim2.fromOffset(500, 24), Position = UDim2.new(1, -540, 0, 40), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 16, TextColor3 = C.TextDim, Parent = mainMenu })
	Kit.text({ Text = string.format("v%s   ·   1-%d PLAYERS   ·   %s", GameConfig.Version, GameConfig.MaxPlayers, GameConfig.BuildingName), Size = UDim2.fromOffset(900, 20), Position = UDim2.new(0, 110, 1, -60), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Muted, Parent = mainMenu })
end

local function buildPause()
	pauseMenu = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.35, Visible = false, Parent = menuGui })
	Kit.text({ Text = "PAUSED", Size = UDim2.fromOffset(600, 60), Position = UDim2.fromOffset(110, 200), FontFace = Kit.F.Title, TextSize = 52, Parent = pauseMenu })
	Kit.text({ Text = "The building does not pause.", Size = UDim2.fromOffset(600, 26), Position = UDim2.fromOffset(112, 258), FontFace = Kit.F.Light, TextSize = 18, TextColor3 = C.TextDim, Parent = pauseMenu })
	local buttons = Kit.frame({ Name = "Buttons", Size = UDim2.fromOffset(320, 420), Position = UDim2.fromOffset(110, 320), BackgroundTransparency = 1, Parent = pauseMenu })
	Kit.list(buttons, 10)
	local entries = {
		{ "RESUME", "primary", function()
			MenuController:SetPaused(false)
		end },
		{ "HOW TO PLAY", "ghost", function()
			MenuController:OpenPanel("HOWTO")
		end },
		{ "JOURNAL", "ghost", function()
			MenuController:OpenPanel("JOURNAL")
		end },
		{ "SETTINGS", "ghost", function()
			MenuController:OpenPanel("SETTINGS")
		end },
		{ "BACK TO MENU", "ghost", function()
			if State.status == "LOBBY" then
				MenuController:SetPaused(false)
				Net.event("Lobby"):FireServer("menu")
			else
				Registry.HUDController:Hint("You can leave once you are back in the waiting room.", 3)
			end
		end },
	}
	for i, e in entries do
		local b = Kit.button({ Text = e[1], Size = UDim2.fromOffset(300, 52), TextSize = 19, Style = e[2], LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left, Parent = buttons }, e[3])
		Kit.padding(b, 0, 22)
	end
end

function MenuController:SetPaused(on: boolean)
	if on and State.status ~= "LOBBY" and State.status ~= "ALIVE" then
		return
	end
	pauseMenu.Visible = on
	if not on then
		closePanel()
	end
	State.setUIOpen(on)
	if on and State.inputType == "Gamepad" then
		GuiService.SelectedObject = pauseMenu.Buttons:FindFirstChildWhichIsA("GuiButton")
	end
end

function MenuController:Play()
	if State.status ~= "MENU" then
		return
	end
	Kit.sound("TitleHit")
	Registry.EffectsController:Fade(1, 0.6)
	task.delay(0.7, function()
		Net.event("Lobby"):FireServer("play")
		task.delay(1.2, function()
			Registry.EffectsController:Fade(0, 1.2)
		end)
	end)
end

local function warningIfNeeded()
	if State.settings.flashingAccepted then
		return
	end
	local overlay = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 0.05, Parent = panelGui, ZIndex = 20 })
	local box = Kit.frame({ Size = UDim2.fromOffset(760, 360), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Parent = overlay })
	Kit.text({ Text = "BEFORE YOU ENTER", Size = UDim2.new(1, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Title, TextSize = 38, Parent = box })
	Kit.text({ Text = "This experience contains flickering and flashing lights, sudden loud sounds and psychological horror themes. You can reduce flashes, glitches and camera shake at any time in SETTINGS.", Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromOffset(0, 70), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 20, TextColor3 = C.TextDim, Parent = box })
	local function accept(reducedEffects: boolean)
		State.settings.flashingAccepted = true
		if reducedEffects then
			State.settings.reducedEffects = true
			State.settings.cameraShake = false
		end
		State.SettingsChanged:Fire()
		sendSettings()
		overlay:Destroy()
		State.setUIOpen(false)
	end
	local continue = Kit.button({ Text = "CONTINUE", Size = UDim2.fromOffset(260, 52), Position = UDim2.new(0.5, -270, 0, 230), Style = "primary", Parent = box }, function()
		accept(false)
	end)
	Kit.button({ Text = "REDUCE EFFECTS", Size = UDim2.fromOffset(260, 52), Position = UDim2.new(0.5, 10, 0, 230), Parent = box }, function()
		accept(true)
	end)
	if State.inputType == "Gamepad" then
		GuiService.SelectedObject = continue
	end
end

function MenuController:Init()
	menuGui = Kit.screen("Menu", 5)
	panelGui = Kit.screen("Panels", 9)
	buildMain()
	buildPause()
end

function MenuController:Start()
	Registry.CameraController:SetOverride("Menu", 10, function()
		if State.status == "MENU" then
			return menuCamera(), 62
		end
		return nil
	end)
	local function refresh()
		local inMenu = State.status == "MENU"
		mainMenu.Visible = inMenu
		if inMenu then
			pauseMenu.Visible = false
		end
	end
	State.StatusChanged:Connect(function()
		refresh()
		if State.status ~= "LOBBY" and State.status ~= "ALIVE" and pauseMenu.Visible then
			self:SetPaused(false)
		end
		if State.status == "ALIVE" and currentPanelName == "SHOP" then
			closePanel()
		end
	end)
	refresh()
	State.ProfileChanged:Connect(function()
		local p = State.profile
		if p then
			profileLabel.Text = string.format("LEVEL %d   ·   %s ECHOES", p.level or 1, Util.formatNumber(p.echoes or 0))
		end
	end)
	-- first profile: show the warning once settings are known
	State.ProfileChanged:Once(function()
		task.delay(0.5, warningIfNeeded)
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if not began then
			return
		end
		if action == "Pause" then
			if currentPanel then
				closePanel()
			elseif State.status == "LOBBY" or State.status == "ALIVE" then
				if Registry.PuzzleUI:IsOpen() then
					Registry.PuzzleUI:Close()
				else
					self:SetPaused(not pauseMenu.Visible)
				end
			end
		elseif action == "Back" then
			if currentPanel then
				closePanel()
			elseif pauseMenu.Visible then
				self:SetPaused(false)
			end
		elseif action == "Journal" and (State.status == "LOBBY" or State.status == "MENU") then
			if currentPanelName == "JOURNAL" then
				closePanel()
			else
				self:OpenPanel("JOURNAL")
			end
		end
	end)
	-- the title flickers like a failing sign
	task.spawn(function()
		while true do
			task.wait(math.random(30, 90) / 10)
			if mainMenu.Visible and not State.settings.reducedEffects then
				title.TextTransparency = 0.6
				task.wait(0.05)
				title.TextTransparency = 0
				task.wait(0.08)
				title.TextTransparency = 0.4
				task.wait(0.04)
				title.TextTransparency = 0
			end
		end
	end)
	-- settings are sent at most once a second
	task.spawn(function()
		while true do
			task.wait(0.5)
			if settingsDirty and os.clock() - lastSettingsSend > 1 then
				settingsDirty = false
				lastSettingsSend = os.clock()
				Net.event("Settings"):FireServer(State.settings)
			end
		end
	end)
end

return MenuController
