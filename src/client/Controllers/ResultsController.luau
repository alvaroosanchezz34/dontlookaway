--[[
	ResultsController
	End of night: the ending, what happened to everyone, the anomalies, the time,
	and what you earned (Echoes, XP, level, achievements, journal entries).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local ResultsController = {}

local C = Kit.C
local gui: ScreenGui
local root: Frame
local showToken: any = nil

local ENDINGS = {
	ESCAPED = { "ESCAPED", "Not everyone made it out. You did." },
	ESCAPED_ALONE = { "ESCAPED ALONE", "Nobody saw you leave. Nobody will believe you." },
	EVERYONE_SURVIVED = { "EVERYONE SURVIVED", "You kept your eyes on each other. It was enough. Tonight." },
	OBSERVER_CAUGHT_YOU = { "THE OBSERVER CAUGHT YOU", "You looked away." },
	FAILED_TO_IDENTIFY = { "FAILED TO IDENTIFY THE ANOMALIES", "Reality drifted too far. The building kept you." },
	THE_WITNESS = { "THE WITNESS", "The photograph develops on the drive home: eleven people on the front steps, and Vale among them. Behind every window, something tall is watching. Count the people again. There are twelve." },
}

local OUTCOME = { ESCAPED = "ESCAPED", DEAD = "TAKEN", LOST = "LOST" }

local function show(payload)
	root:ClearAllChildren()
	local ending = ENDINGS[payload.ending] or ENDINGS.ESCAPED
	local summary = payload.summary or {}
	local reward = payload.reward or {}
	gui.Enabled = true
	State.setUIOpen(true)
	local bg = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 1, Parent = root })
	Kit.tween(bg, 1.5, { BackgroundTransparency = 0.25 })
	local holder = Kit.frame({ Size = UDim2.fromOffset(1300, 860), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Parent = root })
	local title = Kit.text({ Text = ending[1], Size = UDim2.new(1, 0, 0, 80), FontFace = Kit.F.Title, TextSize = 64, TextColor3 = if payload.ending == "OBSERVER_CAUGHT_YOU" or payload.ending == "FAILED_TO_IDENTIFY" then Color3.fromRGB(196, 170, 166) else C.Text, TextTransparency = 1, Parent = holder })
	local sub = Kit.text({ Text = ending[2], Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(4, 84), FontFace = Kit.F.Light, TextSize = 22, TextColor3 = C.TextDim, TextTransparency = 1, Parent = holder })
	Kit.tween(title, 1.2, { TextTransparency = 0 })
	Kit.tween(sub, 2, { TextTransparency = 0 })
	-- left column: the night
	local left = Kit.frame({ Size = UDim2.new(0.5, -20, 0, 600), Position = UDim2.fromOffset(0, 160), BackgroundTransparency = 1, Parent = holder })
	Kit.list(left, 10)
	local function row(parent, label: string, value: string, order: number)
		local r = Kit.frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
		Kit.text({ Text = label, Size = UDim2.fromScale(0.6, 1), TextColor3 = C.TextDim, TextSize = 18, Parent = r })
		Kit.text({ Text = value, Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 18, Parent = r })
	end
	Kit.text({ Text = "THE NIGHT", Size = UDim2.new(1, 0, 0, 30), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 0, Parent = left })
	row(left, "Time inside", Util.formatTime(summary.duration or 0), 1)
	row(left, "Difficulty", summary.difficulty or "NORMAL", 2)
	row(left, "Anomalies found (team)", string.format("%d / %d", summary.anomaliesFound or 0, summary.quota or 0), 3)
	row(left, "Anomalies missed", tostring(summary.anomaliesMissed or 0), 4)
	row(left, "Survivors", string.format("%d / %d", summary.escapedCount or 0, summary.playerCount or 1), 5)
	row(left, "Exit locks released", string.format("%d / 4", summary.locksReleased or 0), 6)
	row(left, "Seed", tostring(summary.seed or 0), 7)
	Kit.text({ Text = "WHO", Size = UDim2.new(1, 0, 0, 40), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 10, Parent = left })
	for i, r in payload.roster or {} do
		row(left, r.name, OUTCOME[r.outcome] or "LOST", 10 + i)
	end
	-- right column: you. The breakdown is counted in line by line.
	local right = Kit.frame({ Size = UDim2.new(0.5, -20, 0, 640), Position = UDim2.new(0.5, 20, 0, 160), BackgroundTransparency = 1, Parent = holder })
	Kit.list(right, 6)
	Kit.text({ Text = "YOU", Size = UDim2.new(1, 0, 0, 30), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 0, Parent = right })
	local breakdown = reward.breakdown or {}
	local order = 1
	local rowsOut = {}
	for _, item in breakdown do
		order += 1
		local r = Kit.frame({ Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = order, Parent = right })
		local label = Kit.text({ Text = item.label, Size = UDim2.fromScale(0.58, 1), TextColor3 = C.TextDim, TextSize = 16, TextTransparency = 1, Parent = r })
		local e = Kit.text({ Text = if item.echoes ~= 0 then ("+" .. Util.formatNumber(item.echoes) .. " E") else "", Size = UDim2.fromScale(0.22, 1), Position = UDim2.fromScale(0.58, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 16, TextTransparency = 1, Parent = r })
		local x = Kit.text({ Text = if item.xp ~= 0 then ("+" .. Util.formatNumber(item.xp) .. " XP") else "", Size = UDim2.fromScale(0.2, 1), Position = UDim2.fromScale(0.8, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 14, TextColor3 = C.Muted, TextTransparency = 1, Parent = r })
		table.insert(rowsOut, { label, e, x, item })
	end
	order += 1
	Kit.frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, LayoutOrder = order, Parent = right })
	order += 1
	local totalRow = Kit.frame({ Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = order, Parent = right })
	Kit.text({ Text = "TOTAL", Size = UDim2.fromScale(0.4, 1), FontFace = Kit.F.Heading, TextSize = 20, Parent = totalRow })
	local totalEchoes = Kit.text({ Text = "+0 ECHOES", Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.4, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 22, TextColor3 = C.Accent, Parent = totalRow })
	local totalXP = Kit.text({ Text = "+0 XP", Size = UDim2.fromScale(0.2, 1), Position = UDim2.fromScale(0.8, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 16, TextColor3 = C.TextDim, Parent = totalRow })
	order += 1
	local levelRow = Kit.frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order, Parent = right })
	local levelUp = (reward.levelAfter or 1) > (reward.levelBefore or 1)
	Kit.text({ Text = if levelUp then "LEVEL UP" else "LEVEL", Size = UDim2.fromScale(0.6, 1), FontFace = Kit.F.Heading, TextSize = 17, TextColor3 = if levelUp then C.Accent else C.TextDim, Parent = levelRow })
	Kit.text({ Text = if levelUp then string.format("%d  >  %d", reward.levelBefore or 1, reward.levelAfter or 1) else tostring(reward.levelAfter or 1), Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 18, Parent = levelRow })
	order += 1
	local barTrack = Kit.frame({ Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C.Line, LayoutOrder = order, Parent = right })
	local fill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = barTrack })
	order += 1
	Kit.text({ Text = string.format("Anomalies you found: %d   ·   New journal entries: %d", reward.found or 0, reward.newJournal or 0), Size = UDim2.new(1, 0, 0, 26), FontFace = Kit.F.Light, TextSize = 15, TextColor3 = C.Muted, LayoutOrder = order, Parent = right })
	if reward.achievements and #reward.achievements > 0 then
		order += 1
		Kit.text({ Text = "ACHIEVEMENTS", Size = UDim2.new(1, 0, 0, 34), FontFace = Kit.F.Heading, TextSize = 18, LayoutOrder = order, Parent = right })
		for _, name in reward.achievements do
			order += 1
			Kit.text({ Text = name, Size = UDim2.new(1, 0, 0, 22), FontFace = Kit.F.Body, TextSize = 16, TextColor3 = C.Good, LayoutOrder = order, Parent = right })
		end
	end
	local pct = if (reward.xpNeed or 0) > 0 then (reward.xpInto or 0) / reward.xpNeed else 1
	local token = {}
	showToken = token
	task.spawn(function()
		task.wait(1.6)
		local sumE, sumX = 0, 0
		for _, r in rowsOut do
			if showToken ~= token then
				return
			end
			local label, e, x, item = r[1], r[2], r[3], r[4]
			Kit.tween(label, 0.25, { TextTransparency = 0 })
			Kit.tween(e, 0.25, { TextTransparency = 0 })
			Kit.tween(x, 0.25, { TextTransparency = 0 })
			-- count the total up toward the new value
			local fromE, fromX = sumE, sumX
			sumE += item.echoes
			sumX += item.xp
			for step = 1, 6 do
				local a = step / 6
				totalEchoes.Text = "+" .. Util.formatNumber(math.floor(fromE + (sumE - fromE) * a + 0.5)) .. " ECHOES"
				totalXP.Text = "+" .. Util.formatNumber(math.floor(fromX + (sumX - fromX) * a + 0.5)) .. " XP"
				task.wait(0.035)
			end
			if item.echoes > 0 then
				Kit.sound("UICoin")
			end
			task.wait(0.18)
		end
		if showToken ~= token then
			return
		end
		totalEchoes.Text = "+" .. Util.formatNumber(reward.echoes or sumE) .. " ECHOES"
		totalXP.Text = "+" .. Util.formatNumber(reward.xp or sumX) .. " XP"
		Kit.tween(fill, 1.2, { Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1) })
		if levelUp then
			Kit.sound("LevelUp")
		end
	end)
	Kit.text({ Text = "Returning to the Field Office...", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 16, TextColor3 = C.Muted, Parent = holder })
	Registry.SpectatorController:Stop()
end

local function hide()
	if gui.Enabled then
		showToken = nil
		gui.Enabled = false
		root:ClearAllChildren()
		State.setUIOpen(false)
	end
end

function ResultsController:Init()
	gui = Kit.screen("Results", 8)
	root = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	gui.Enabled = false
end

function ResultsController:Start()
	Net.event("Results").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			show(payload)
		end
	end)
	State.RoundChanged:Connect(function()
		if State.round.state == "LOBBY" or State.round.state == "STARTING" then
			hide()
		end
	end)
	State.StatusChanged:Connect(function()
		if State.status == "LOBBY" and State.round.state ~= "RESULTS" then
			hide()
		end
	end)
end

return ResultsController
