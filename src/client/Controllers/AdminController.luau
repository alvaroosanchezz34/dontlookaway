--[[
	AdminController
	Owner-only debug panel (F8). The panel is only built for players the server
	flagged as admins, and every button is just a request: the server re-checks
	authorization for each command.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local AdminController = {}

local C = Kit.C
local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local panel: Frame
local info: TextLabel
local logs: TextLabel
local message: TextLabel
local anomalyList: ScrollingFrame
local targetList: Frame
local snapshot = nil
local selectedTarget: number? = nil

local ROOMS = { "G_r", "G_c", "G_q", "G_y", "G_b", "U_c", "U_n", "U_p", "U_v", "B_c", "B_d", "B_w", "B_z", "B_f" }

local function send(command: string, arg: any?)
	Net.event("Admin"):FireServer(command, arg)
end

local function render()
	if not snapshot or not gui then
		return
	end
	local s = snapshot
	local lines = {
		string.format("ROUND %s   difficulty %s   elapsed %ds", s.round, s.difficulty, s.elapsed),
		string.format("seed %s   map seed %s   %s", tostring(s.seed), tostring(s.mapSeed), if s.dataMock then "(DATASTORE MOCK)" else ""),
		string.format("director %s   dread %d   observer %s / %s", s.phase, s.dread, s.observer, tostring(s.observerMode)),
	}
	if s.stats then
		table.insert(lines, string.format("anomalies spawned %d  found %d  missed %d", s.stats.spawned, s.stats.found, s.stats.missed))
	end
	if s.objective then
		local locks = {}
		for k, v in s.objective.locks or {} do
			table.insert(locks, k .. (if v then "+" else "-"))
		end
		table.insert(lines, string.format("puzzles %s   locks %s   quota %d/%d   code %s", table.concat(s.objective.puzzles or {}, ","), table.concat(locks, " "), s.objective.found or 0, s.objective.quota or 0, tostring(s.objective.code)))
	end
	table.insert(lines, "ACTIVE:")
	for _, a in s.active or {} do
		table.insert(lines, string.format("  %s  %s  %ds  (%d players)", a.id, a.scope, a.remaining, a.players))
	end
	table.insert(lines, "PLAYERS:")
	for _, p in s.players or {} do
		table.insert(lines, string.format("  %s  %s  %s  battery %d %s", p.name, p.status, p.room, p.battery, if p.light then "ON" else ""))
	end
	if s.analytics then
		table.insert(lines, string.format("analytics: rounds %d/%d  escapes %d  deaths %d  avg %ds  players %.1f", s.analytics.roundsCompleted or 0, s.analytics.roundsStarted or 0, s.analytics.escapes or 0, s.analytics.deaths or 0, math.floor(s.analytics.averageRoundDuration or 0), s.analytics.averagePlayerCount or 0))
	end
	info.Text = table.concat(lines, "\n")
	logs.Text = table.concat(s.logs or {}, "\n")
	-- anomaly buttons (built once)
	if #anomalyList:GetChildren() <= 1 then
		for i, id in s.anomalyIds or {} do
			Kit.button({ Text = id, Size = UDim2.new(1, -8, 0, 26), TextSize = 11, LayoutOrder = i, Parent = anomalyList }, function()
				send("forceAnomaly", id)
			end)
		end
	end
	for _, c in targetList:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i, p in s.players or {} do
		local b = Kit.button({ Text = p.name, Size = UDim2.fromOffset(140, 28), TextSize = 12, LayoutOrder = i, Parent = targetList }, function()
			selectedTarget = p.userId
			render()
		end)
		if selectedTarget == p.userId then
			b.TextColor3 = C.Good
		end
	end
end

local function build()
	gui = Kit.screen("Admin", 20)
	local g = gui :: ScreenGui
	panel = Kit.frame({ Size = UDim2.fromOffset(1500, 900), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Black, BackgroundTransparency = 0.08, Visible = false, Parent = g })
	Kit.stroke(panel, C.Danger, 1, 0.3)
	Kit.text({ Text = "ADMIN  ·  owner tools", Size = UDim2.fromOffset(600, 30), Position = UDim2.fromOffset(20, 12), FontFace = Kit.F.Heading, TextSize = 20, TextColor3 = C.Danger, Parent = panel })
	message = Kit.text({ Text = "", Size = UDim2.fromOffset(800, 24), Position = UDim2.fromOffset(660, 14), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 14, Parent = panel })
	local commands = Kit.frame({ Size = UDim2.fromOffset(300, 800), Position = UDim2.fromOffset(20, 60), BackgroundTransparency = 1, Parent = panel })
	Kit.list(commands, 6)
	local entries = {
		{ "Refresh", "refresh" },
		{ "Start round", "startRound" },
		{ "End round", "endRound" },
		{ "Reset round", "resetRound" },
		{ "Spawn Observer (hunt)", "spawnObserver", true },
		{ "Observer sighting", "sighting", true },
		{ "Mimic", "mimic", true },
		{ "Vanish Observer", "vanishObserver" },
		{ "Release POWER", "releaseLock", "POWER" },
		{ "Release ANOMALIES", "releaseLock", "ANOMALIES" },
		{ "Teleport to target", "teleport", true },
		{ "Kill me (test death)", "killSelf" },
	}
	for i, e in entries do
		Kit.button({ Text = e[1], Size = UDim2.fromOffset(290, 36), TextSize = 14, LayoutOrder = i, Parent = commands }, function()
			local arg = e[3]
			if arg == true then
				arg = selectedTarget
			end
			send(e[2], arg)
		end)
	end
	Kit.text({ Text = "TELEPORT TO ROOM", Size = UDim2.fromOffset(290, 24), LayoutOrder = 50, FontFace = Kit.F.Heading, TextSize = 13, TextColor3 = C.TextDim, Parent = commands })
	local rooms = Kit.frame({ Size = UDim2.fromOffset(290, 160), BackgroundTransparency = 1, LayoutOrder = 51, Parent = commands })
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(68, 28), CellPadding = UDim2.fromOffset(4, 4), Parent = rooms })
	for _, id in ROOMS do
		Kit.button({ Text = id, TextSize = 12, Parent = rooms }, function()
			send("teleport", id)
		end)
	end
	Kit.text({ Text = "TARGET", Size = UDim2.fromOffset(200, 20), Position = UDim2.fromOffset(340, 60), FontFace = Kit.F.Heading, TextSize = 13, TextColor3 = C.TextDim, Parent = panel })
	targetList = Kit.frame({ Size = UDim2.fromOffset(600, 34), Position = UDim2.fromOffset(340, 82), BackgroundTransparency = 1, Parent = panel })
	Kit.list(targetList, 6, true)
	info = Kit.text({ Text = "", Size = UDim2.fromOffset(820, 400), Position = UDim2.fromOffset(340, 124), FontFace = Kit.F.Mono, TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top, Parent = panel })
	local logScroll = Kit.scroll(panel, { Size = UDim2.fromOffset(820, 330), Position = UDim2.fromOffset(340, 540) })
	logs = Kit.text({ Text = "", Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.TextDim, TextYAlignment = Enum.TextYAlignment.Top, Parent = logScroll })
	Kit.text({ Text = "FORCE ANOMALY", Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(1180, 60), FontFace = Kit.F.Heading, TextSize = 13, TextColor3 = C.TextDim, Parent = panel })
	anomalyList = Kit.scroll(panel, { Size = UDim2.fromOffset(300, 800), Position = UDim2.fromOffset(1180, 84) })
	Kit.list(anomalyList, 4)
end

function AdminController:Start()
	Net.event("AdminData").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if not gui then
			build()
		end
		snapshot = p.snapshot
		if message then
			message.Text = tostring(p.message or "")
		end
		render()
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if action ~= "Admin" or not began or not player:GetAttribute("IsAdmin") then
			return
		end
		if not gui then
			build()
		end
		panel.Visible = not panel.Visible
		State.setUIOpen(panel.Visible)
		if panel.Visible then
			send("refresh")
		end
	end)
	-- live refresh while open
	task.spawn(function()
		while true do
			task.wait(2)
			if gui and panel.Visible then
				send("refresh")
			end
		end
	end)
end

return AdminController
