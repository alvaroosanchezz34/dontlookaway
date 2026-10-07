--[[
	ProgressionService
	Light progression: XP and levels, the Anomaly Journal, achievements, lifetime
	statistics and end-of-round rewards (Echoes). Everything is computed on the
	server from server-observed events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local Achievements = require(ReplicatedStorage.Shared.Catalog.Achievements)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local ProgressionService = {}

local roundFound: { [Player]: number } = {}
local roundAchievements: { [Player]: { string } } = {}
local roundJournal: { [Player]: number } = {}

local PUZZLE_KINDS = { "POWER", "CODE", "SYMBOLS", "DOORS", "OFFERING" }

------------------------------------------------------------------------------------
-- Snapshots
------------------------------------------------------------------------------------

function ProgressionService:Snapshot(player: Player)
	local data = Registry.DataService:Get(player)
	if not data then
		return nil
	end
	local level, into, need = Progression.fromTotal(data.xp)
	return {
		echoes = data.echoes,
		xp = data.xp,
		level = level,
		xpInto = into,
		xpNeed = need,
		journal = data.journal,
		achievements = data.achievements,
		owned = Registry.EconomyService:OwnedList(player),
		equipped = data.equipped,
		settings = data.settings,
		stats = data.stats,
		flags = data.flags,
		passes = Registry.EconomyService:PassList(player),
	}
end

function ProgressionService:Push(player: Player)
	local snap = self:Snapshot(player)
	if snap then
		Net.fire(player, "Profile", snap)
	end
end

local function syncAttributes(player: Player)
	local data = Registry.DataService:Get(player)
	if not data then
		return
	end
	local level = Progression.fromTotal(data.xp)
	player:SetAttribute("Level", level)
	local title = Cosmetics.get(data.equipped.TITLE)
	player:SetAttribute("Title", title and title.name or "Visitor")
end

------------------------------------------------------------------------------------
-- Achievements
------------------------------------------------------------------------------------

function ProgressionService:Award(player: Player, id: string)
	local def = Achievements.ById[id]
	if not def then
		return
	end
	local data = Registry.DataService:Get(player)
	if not data or data.achievements[id] then
		return
	end
	Registry.DataService:Update(player, function(d)
		d.achievements[id] = os.time()
		d.echoes += def.echoes or 0
	end)
	roundAchievements[player] = roundAchievements[player] or {}
	table.insert(roundAchievements[player], id)
	Net.fire(player, "Unlock", { type = "achievement", id = id, name = def.name, description = def.description, echoes = def.echoes })
	Registry.AudioService:Play2D({ player }, "Achievement")
	Registry.AnalyticsService:Event(player, "Achievement", 1, { id = id })
	-- cosmetics awarded by achievements become available immediately
	for _, c in Cosmetics.List do
		if c.achievement == id then
			Net.fire(player, "Unlock", { type = "cosmetic", id = c.id, name = c.name, category = c.category })
		end
	end
	self:Push(player)
end

local function checkCounts(player: Player)
	local data = Registry.DataService:Get(player)
	if not data then
		return
	end
	local reported = data.stats.anomaliesReported
	if reported >= 10 then
		ProgressionService:Award(player, "FOUND_10")
	end
	if reported >= 50 then
		ProgressionService:Award(player, "FOUND_50")
	end
	if reported >= 150 then
		ProgressionService:Award(player, "FOUND_150")
	end
	local unique = Util.count(data.journal)
	if unique >= 25 then
		ProgressionService:Award(player, "JOURNAL_25")
	end
	if unique >= JournalCatalog.Count then
		ProgressionService:Award(player, "JOURNAL_ALL")
	end
end

------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------

function ProgressionService:AnomalyReported(reporter: Player?, credited: { Player }, def, inst)
	local entry = JournalCatalog.ById[def.id]
	for _, player in credited do
		if player.Parent then
			local isNew = false
			Registry.DataService:Update(player, function(d)
				local j = d.journal[def.id]
				local now = os.time()
				if not j then
					isNew = true
					d.journal[def.id] = { c = 1, f = now, l = now }
					d.echoes += GameConfig.Rewards.FirstDiscoveryBonusEchoes
				else
					j.c += 1
					j.l = now
				end
				if player == reporter then
					d.stats.anomaliesReported += 1
					if def.rarity == "LEGENDARY" then
						d.stats.legendaryReports += 1
					end
				end
			end)
			roundFound[player] = (roundFound[player] or 0) + 1
			if isNew then
				roundJournal[player] = (roundJournal[player] or 0) + 1
				Net.fire(player, "Unlock", { type = "journal", id = def.id, number = entry.number, name = entry.name, rarity = entry.rarity, description = entry.description })
				Registry.AudioService:Play2D({ player }, "JournalEntry")
			else
				Net.fire(player, "Notify", { kind = "anomaly", text = entry.name, sub = JournalCatalog.format(entry.number) })
			end
			if def.rarity == "LEGENDARY" then
				self:Award(player, "LEGENDARY_SIGHT")
			end
			if def.id == "ROOM_ZERO" then
				self:Award(player, "SECRET_ROOM")
			end
			checkCounts(player)
			if inst and inst.data and inst.data.tutorial then
				Registry.DataService:Update(player, function(d)
					if not d.flags.tutorialDone then
						d.flags.tutorialDone = true
						Registry.AnalyticsService:TutorialComplete(player)
					end
				end)
			end
			self:Push(player)
		end
	end
end

-- Recurring challenges (daily / weekly) hear about everything here.
function ProgressionService:Challenge(player: Player, kind: string, value: any)
	if Registry.ChallengeService then
		Registry.ChallengeService:Record(player, kind, value)
	end
end

function ProgressionService:FalseReport(player: Player)
	Registry.DataService:Update(player, function(d)
		d.stats.falseReports += 1
	end)
end

function ProgressionService:ObserverSighted(player: Player)
	Registry.DataService:Update(player, function(d)
		d.stats.observerSightings += 1
	end)
	self:Award(player, "MET_OBSERVER")
end

function ProgressionService:PlayerDied(player: Player)
	Registry.DataService:Update(player, function(d)
		d.stats.deaths += 1
	end)
	self:Award(player, "CAUGHT")
end

function ProgressionService:PuzzleSolved(kind: string, players: { Player })
	for _, player in players do
		local all = false
		Registry.DataService:Update(player, function(d)
			d.puzzlesSolved[kind] = true
			all = true
			for _, k in PUZZLE_KINDS do
				if not d.puzzlesSolved[k] then
					all = false
				end
			end
		end)
		if all then
			self:Award(player, "PUZZLE_MASTER")
		end
	end
end

-- End of round: rewards, statistics, achievements. Returns the summary shown in RESULTS.
function ProgressionService:RoundEnded(player: Player, info)
	local data = Registry.DataService:Get(player)
	if not data then
		return nil
	end
	local R = GameConfig.Rewards
	local escaped = info.outcome == "ESCAPED"
	local minutes = math.min(info.duration, GameConfig.Round.MaxRoundTime) / 60
	local found = roundFound[player] or 0
	local mult = (GameConfig.Difficulty[info.difficulty] or GameConfig.Difficulty.NORMAL).RewardMultiplier or 1
	local echoes = R.EchoesPerMinute * minutes + R.EchoesPerAnomaly * found
	local xp = R.XPPerMinute * minutes + R.XPPerAnomaly * found
	if escaped then
		echoes += R.EchoesEscape
		xp += R.XPEscape
		if info.playerCount > 1 and info.escapedCount == info.playerCount then
			echoes += R.EchoesSurvivedTeamBonus
		end
	elseif info.outcome == "DEAD" then
		xp += R.XPDeath
	end
	echoes = math.floor(echoes * mult + 0.5)
	xp = math.floor(xp * mult + 0.5)
	local levelBefore = Progression.fromTotal(data.xp)
	Registry.DataService:Update(player, function(d)
		d.echoes += echoes
		d.xp += xp
		d.stats.rounds += 1
		if escaped then
			d.stats.escapes += 1
			d.flags.hardUnlocked = true
			local t = math.floor(info.escapedAt or info.duration)
			if d.stats.bestTime == 0 or t < d.stats.bestTime then
				d.stats.bestTime = t
			end
			if info.playerCount == 1 then
				d.stats.soloEscapes += 1
			end
			if info.difficulty == "HARD" then
				d.stats.hardEscapes += 1
				d.flags.nightmareUnlocked = true
			elseif info.difficulty == "NIGHTMARE" then
				d.stats.hardEscapes += 1
				d.stats.nightmareEscapes += 1
				d.flags.nightmareUnlocked = true
			end
			if info.witness then
				d.stats.secretEndings += 1
			end
		end
	end)
	self:Award(player, "FIRST_NIGHT")
	if escaped then
		self:Award(player, "ESCAPED")
		if (info.lightSeconds or 999) < 60 then
			self:Award(player, "NO_LIGHT")
		end
		if info.playerCount == 1 then
			self:Award(player, "SURVIVED_ALONE")
		end
		if info.playerCount >= 4 then
			self:Award(player, "FULL_HOUSE")
		end
		if info.playerCount > 1 and info.escapedCount == info.playerCount then
			self:Award(player, "EVERYONE_OUT")
		end
		if info.lowBattery then
			self:Award(player, "LOW_BATTERY")
		end
		if info.witness then
			self:Award(player, "THE_WITNESS")
		end
		if info.difficulty == "HARD" or info.difficulty == "NIGHTMARE" then
			self:Award(player, "HARD_ESCAPE")
		end
		if info.difficulty == "NIGHTMARE" then
			self:Award(player, "NIGHTMARE")
		end
		if (info.escapedAt or math.huge) < 540 then
			self:Award(player, "QUICK_EXIT")
		end
		if info.misreports == 0 and found > 0 then
			self:Award(player, "PERFECT_EYE")
		end
	end
	local after = Registry.DataService:Get(player)
	local levelAfter, into, need = Progression.fromTotal(after.xp)
	if levelAfter > levelBefore then
		local unlocked = {}
		for _, c in Cosmetics.List do
			if c.level and c.level > levelBefore and c.level <= levelAfter then
				table.insert(unlocked, c.name)
			end
		end
		Net.fire(player, "Unlock", { type = "level", level = levelAfter, unlocked = unlocked })
		Registry.AudioService:Play2D({ player }, "LevelUp")
	end
	local names = {}
	for _, id in roundAchievements[player] or {} do
		table.insert(names, Achievements.ById[id].name)
	end
	local summary = {
		echoes = echoes,
		xp = xp,
		levelBefore = levelBefore,
		levelAfter = levelAfter,
		xpInto = into,
		xpNeed = need,
		found = found,
		newJournal = roundJournal[player] or 0,
		achievements = names,
		totalEchoes = after.echoes,
		bestTime = after.stats.bestTime,
	}
	roundFound[player] = nil
	roundAchievements[player] = nil
	roundJournal[player] = nil
	syncAttributes(player)
	self:Push(player)
	return summary
end

function ProgressionService:Start()
	Registry.DataService.Loaded:Connect(function(player)
		syncAttributes(player)
		self:Push(player)
	end)
	Registry.DataService.Changed:Connect(function(player)
		syncAttributes(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		roundFound[player] = nil
		roundAchievements[player] = nil
		roundJournal[player] = nil
	end)
	-- discovering the hidden room
	task.spawn(function()
		while true do
			task.wait(1)
			local map = Registry.MapService:GetMap()
			local secret = map and map.Rooms.B_z
			if secret and Registry.RoundService:IsRunning() then
				for _, p in Registry.PlayerService:GetAlive() do
					local root = Util.getRoot(p)
					if root and map:roomAt(root.Position) == secret then
						self:Award(p, "SECRET_ROOM")
					end
				end
			end
		end
	end)
	Net.handle("GetProfile", function(player)
		return self:Snapshot(player)
	end)
end

return ProgressionService
