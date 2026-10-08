--[[
	AnalyticsService (wrapper)
	Records gameplay events through Roblox AnalyticsService (custom events, funnel
	steps) and keeps lightweight in-server aggregates for the admin panel.
	No personal information is ever logged: only UserIds already known to Roblox
	analytics, round numbers and gameplay values.
]]

local RobloxAnalytics = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

local Analytics = {}

local aggregates = {
	sessions = 0,
	roundsStarted = 0,
	roundsCompleted = 0,
	deaths = 0,
	escapes = 0,
	anomaliesDiscovered = 0,
	anomaliesMissed = 0,
	monsterEncounters = 0,
	totalRoundDuration = 0,
	playerCountSum = 0,
	tutorialCompletions = 0,
}

local funnelSessions: { [Player]: string } = {}

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		-- analytics must never break gameplay
		warn("[Analytics] ", err)
	end
end

function Analytics:Event(player: Player?, name: string, value: number?, fields: { [string]: any }?)
	if not player then
		return
	end
	local custom = nil
	if fields then
		custom = {}
		local i = 0
		for k, v in fields do
			i += 1
			if i > 3 then
				break
			end
			custom[Enum.AnalyticsCustomFieldKeys["CustomField0" .. i].Name] = tostring(k) .. ":" .. tostring(v)
		end
	end
	safe(function()
		RobloxAnalytics:LogCustomEvent(player, name, value or 1, custom)
	end)
end

function Analytics:Funnel(player: Player, step: number, stepName: string)
	local session = funnelSessions[player]
	if not session then
		session = HttpService:GenerateGUID(false)
		funnelSessions[player] = session
	end
	safe(function()
		RobloxAnalytics:LogFunnelStepEvent(player, "RoundFlow", session, step, stepName)
	end)
end

function Analytics:Onboarding(player: Player, step: number, stepName: string)
	safe(function()
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

--[[
	Beta metrics: named milestones logged once per player per session (FIRST_*)
	or every time (the rest), and counted for the admin panel. Names:
	  SESSION_START ARRIVAL_COMPLETE FIRST_ANOMALY FIRST_TOOL_USE FIRST_OBSERVER
	  FIRST_DEATH FIRST_PUZZLE FIRST_LORE PUZZLE_COMPLETE BLACKOUT ESCAPE GAME_OVER
	  SHOP_OPEN LOADOUT_CHANGE NIGHTMARE_START SECRET_DISCOVERY THE_WITNESS
	Built on Roblox's own analytics (no external services).
]]
local milestoneSeen: { [Player]: { [string]: boolean } } = {}

function Analytics:Milestone(player: Player?, name: string, value: number?)
	if not player then
		return
	end
	local seen = milestoneSeen[player]
	if not seen then
		seen = {}
		milestoneSeen[player] = seen
	end
	if string.sub(name, 1, 6) == "FIRST_" then
		if seen[name] then
			return
		end
		seen[name] = true
	end
	self:Count("m_" .. name)
	self:Event(player, name, value or 1)
end

function Analytics:Count(key: string, amount: number?)
	aggregates[key] = (aggregates[key] or 0) + (amount or 1)
end

function Analytics:GetAggregates()
	local copy = table.clone(aggregates)
	copy.averageRoundDuration = if aggregates.roundsCompleted > 0 then aggregates.totalRoundDuration / aggregates.roundsCompleted else 0
	copy.averagePlayerCount = if aggregates.roundsStarted > 0 then aggregates.playerCountSum / aggregates.roundsStarted else 0
	return copy
end

-- Convenience wrappers for the events the game cares about.
function Analytics:SessionStart(player: Player)
	self:Count("sessions")
	self:Event(player, "SessionStart")
	self:Onboarding(player, 1, "Joined")
end

function Analytics:RoundStart(players: { Player }, difficulty: string)
	self:Count("roundsStarted")
	self:Count("playerCountSum", #players)
	for _, p in players do
		self:Event(p, "RoundStart", #players, { difficulty = difficulty })
		self:Funnel(p, 1, "RoundStart")
	end
end

function Analytics:RoundComplete(players: { Player }, duration: number, ending: string)
	self:Count("roundsCompleted")
	self:Count("totalRoundDuration", duration)
	for _, p in players do
		if p.Parent then
			self:Event(p, "RoundComplete", math.floor(duration), { ending = ending })
			self:Funnel(p, 4, "RoundComplete")
		end
	end
end

function Analytics:Death(player: Player, roundTime: number)
	self:Count("deaths")
	self:Event(player, "Death", math.floor(roundTime))
end

function Analytics:Escape(player: Player, roundTime: number)
	self:Count("escapes")
	self:Event(player, "Escape", math.floor(roundTime))
	self:Funnel(player, 3, "Escaped")
end

function Analytics:AnomalyDiscovered(player: Player, anomalyId: string)
	self:Count("anomaliesDiscovered")
	self:Event(player, "AnomalyDiscovered", 1, { id = anomalyId })
end

function Analytics:AnomalyMissed(_anomalyId: string)
	self:Count("anomaliesMissed")
end

function Analytics:MonsterEncounter(player: Player)
	self:Count("monsterEncounters")
	self:Event(player, "MonsterEncounter")
	self:Funnel(player, 2, "MetObserver")
end

function Analytics:TutorialComplete(player: Player)
	self:Count("tutorialCompletions")
	self:Onboarding(player, 3, "TutorialComplete")
end

function Analytics:PlayerLeft(player: Player)
	funnelSessions[player] = nil
	milestoneSeen[player] = nil
end

function Analytics:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self:PlayerLeft(player)
	end)
end

return Analytics
