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

local ENDINGS = {
	ESCAPED = { "ESCAPED", "Not everyone made it out. You did." },
	ESCAPED_ALONE = { "ESCAPED ALONE", "Nobody saw you leave. Nobody will believe you." },
	EVERYONE_SURVIVED = { "EVERYONE SURVIVED", "You kept your eyes on each other. It was enough. Tonight." },
	OBSERVER_CAUGHT_YOU = { "THE OBSERVER CAUGHT YOU", "You looked away." },
	FAILED_TO_IDENTIFY = { "FAILED TO IDENTIFY THE ANOMALIES", "Reality drifted too far. The building kept you." },
	THE_WITNESS = { "THE WITNESS", "You carried the photograph out. Something is developing in it." },
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
	row(left, "Seed", tostring(summary.seed or 0), 6)
	Kit.text({ Text = "WHO", Size = UDim2.new(1, 0, 0, 40), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 10, Parent = left })
	for i, r in payload.roster or {} do
		row(left, r.name, OUTCOME[r.outcome] or "LOST", 10 + i)
	end
	-- right column: you
	local right = Kit.frame({ Size = UDim2.new(0.5, -20, 0, 600), Position = UDim2.new(0.5, 20, 0, 160), BackgroundTransparency = 1, Parent = holder })
	Kit.list(right, 10)
	Kit.text({ Text = "YOU", Size = UDim2.new(1, 0, 0, 30), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 0, Parent = right })
	row(right, "Anomalies you found", tostring(reward.found or 0), 1)
	row(right, "New journal entries", tostring(reward.newJournal or 0), 2)
	row(right, "Echoes earned", "+" .. Util.formatNumber(reward.echoes or 0), 3)
	row(right, "Experience", "+" .. Util.formatNumber(reward.xp or 0), 4)
	if (reward.levelAfter or 1) > (reward.levelBefore or 1) then
		row(right, "LEVEL UP", string.format("%d  >  %d", reward.levelBefore or 1, reward.levelAfter or 1), 5)
	else
		row(right, "Level", tostring(reward.levelAfter or 1), 5)
	end
	local barTrack = Kit.frame({ Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C.Line, LayoutOrder = 6, Parent = right })
	local fill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Text, Parent = barTrack })
	local pct = if (reward.xpNeed or 0) > 0 then (reward.xpInto or 0) / reward.xpNeed else 1
	task.delay(1, function()
		Kit.tween(fill, 1.4, { Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1) })
	end)
	if reward.achievements and #reward.achievements > 0 then
		Kit.text({ Text = "ACHIEVEMENTS", Size = UDim2.new(1, 0, 0, 40), FontFace = Kit.F.Heading, TextSize = 20, LayoutOrder = 10, Parent = right })
		for i, name in reward.achievements do
			Kit.text({ Text = name, Size = UDim2.new(1, 0, 0, 24), FontFace = Kit.F.Body, TextSize = 17, TextColor3 = C.Good, LayoutOrder = 10 + i, Parent = right })
		end
	end
	Kit.text({ Text = "Returning to the waiting room...", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 16, TextColor3 = C.Muted, Parent = holder })
	Registry.SpectatorController:Stop()
end

local function hide()
	if gui.Enabled then
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
