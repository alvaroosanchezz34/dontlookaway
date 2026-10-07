--[[
	ChallengeService
	Daily and weekly challenges. The draw for a day / week is the same for every
	player (seeded by the UTC date). Progress is recorded from server events only
	(ChallengeService:Record), saved with the profile, and paid out (Echoes + XP)
	the moment a challenge completes. Old progress is cleared when the day or the
	week rolls over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Challenges = require(ReplicatedStorage.Shared.Catalog.Challenges)
local Registry = require(script.Parent.Parent.Registry)

local ChallengeService = {}

local function current()
	local day, week = Challenges.dayKey(), Challenges.weekKey()
	return day, week, Challenges.draw(Challenges.Daily, day, Challenges.PerDay), Challenges.draw(Challenges.Weekly, week, Challenges.PerWeek)
end

-- Rolls the profile over to today's / this week's draw.
local function refresh(player: Player)
	local day, week = Challenges.dayKey(), Challenges.weekKey()
	Registry.DataService:Update(player, function(d)
		local ch = d.challenges
		if ch.day ~= day then
			ch.day = day
			ch.daily = {}
		end
		if ch.week ~= week then
			ch.week = week
			ch.weekly = {}
		end
	end)
end

-- What the client shows: the current draw with progress.
function ChallengeService:Snapshot(player: Player)
	local d = Registry.DataService:Get(player)
	if not d then
		return nil
	end
	local _, _, daily, weekly = current()
	local function rows(list, bucket)
		local out = {}
		for _, def in list do
			local rec = d.challenges[bucket][def.id] or { p = 0, done = false }
			table.insert(out, { id = def.id, text = def.text, goal = def.goal, progress = rec.p, done = rec.done, echoes = def.echoes, xp = def.xp })
		end
		return out
	end
	local now = os.time()
	return {
		daily = rows(daily, "daily"),
		weekly = rows(weekly, "weekly"),
		dailyResetsIn = 86400 - now % 86400,
		weeklyResetsIn = ((Challenges.weekKey(now) + 1) * 7 - 3) * 86400 - now,
		dailiesDone = d.challenges.dailiesDone,
	}
end

function ChallengeService:Push(player: Player)
	local snap = self:Snapshot(player)
	if snap then
		Net.fire(player, "Challenge", snap)
	end
end

--[[
	Records progress of `kind` (see Challenges) for a player. amount defaults to 1.
]]
function ChallengeService:Record(player: Player, kind: string, amount: any)
	local d = Registry.DataService:Get(player)
	if not d then
		return
	end
	refresh(player)
	local n = if type(amount) == "number" and amount > 0 and amount < 1000 then math.floor(amount) else 1
	-- blackout progress means "survived one", whatever its level
	if kind == "blackout" then
		n = 1
	end
	local _, _, daily, weekly = current()
	local completed = {}
	Registry.DataService:Update(player, function(dd)
		for bucket, list in { daily = daily, weekly = weekly } do
			for _, def in list do
				if def.kind == kind then
					local rec = dd.challenges[bucket][def.id] or { p = 0, done = false }
					if not rec.done then
						rec.p = math.min(def.goal, rec.p + n)
						if rec.p >= def.goal then
							rec.done = true
							dd.echoes += def.echoes
							dd.xp += def.xp
							if bucket == "daily" then
								dd.challenges.dailiesDone += 1
							else
								dd.challenges.weekliesDone += 1
							end
							table.insert(completed, def)
						end
					end
					dd.challenges[bucket][def.id] = rec
				end
			end
		end
	end)
	for _, def in completed do
		Net.fire(player, "Unlock", { type = "challenge", name = def.text, echoes = def.echoes, xp = def.xp })
		Registry.AudioService:Play2D({ player }, "ChallengeDone")
		Registry.AnalyticsService:Event(player, "ChallengeComplete", def.echoes, { id = def.id })
	end
	local after = Registry.DataService:Get(player)
	if after and after.challenges.dailiesDone >= 10 then
		Registry.ProgressionService:Award(player, "DAILY_DEVOTION")
	end
	if #completed > 0 then
		Registry.ProgressionService:Push(player)
	end
	self:Push(player)
end

function ChallengeService:Start()
	Registry.DataService.Loaded:Connect(function(player)
		refresh(player)
		self:Push(player)
	end)
	-- the day can change while people play
	task.spawn(function()
		local lastDay = Challenges.dayKey()
		while true do
			task.wait(60)
			local day = Challenges.dayKey()
			if day ~= lastDay then
				lastDay = day
				for _, p in Players:GetPlayers() do
					refresh(p)
					self:Push(p)
				end
			end
		end
	end)
end

return ChallengeService
