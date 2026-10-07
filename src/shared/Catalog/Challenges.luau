--[[
	Challenges
	Recurring goals. Every day three DAILY challenges and every week three WEEKLY
	challenges are drawn from these pools (the same for everyone: the draw is
	seeded by the date). Progress counts automatically from what the server sees.

	kind: the event that advances it (see ChallengeService.Record)
	  anomaly    an anomaly you reported or helped report
	  escape     you escaped
	  survive    a round ended with you alive (escaped)
	  round      you finished a round, any outcome
	  friends    you finished a round with at least one other player
	  blackout   you were alive when a major blackout (level 3+) ended
	  power      your team restored the power
	  note       you read a note
	  mimic      you unmasked a mimic
	  dangerous  you reported a dangerous anomaly
	  puzzle     your team solved a puzzle
	  hard       you escaped on HARD or NIGHTMARE
	  clean      you escaped without a false report
]]

local Challenges = {}

Challenges.Daily = {
	{ id = "D_ANOMALY_3", kind = "anomaly", goal = 3, text = "Find 3 anomalies", echoes = 60, xp = 80 },
	{ id = "D_ANOMALY_6", kind = "anomaly", goal = 6, text = "Find 6 anomalies", echoes = 100, xp = 140 },
	{ id = "D_SURVIVE_1", kind = "survive", goal = 1, text = "Survive one round", echoes = 80, xp = 120 },
	{ id = "D_BLACKOUT_1", kind = "blackout", goal = 1, text = "Make it through a blackout", echoes = 50, xp = 70 },
	{ id = "D_FRIENDS_1", kind = "friends", goal = 1, text = "Play a round with another player", echoes = 40, xp = 60 },
	{ id = "D_POWER_1", kind = "power", goal = 1, text = "Restore the power", echoes = 50, xp = 70 },
	{ id = "D_NOTES_4", kind = "note", goal = 4, text = "Read 4 notes", echoes = 40, xp = 60 },
	{ id = "D_ROUNDS_2", kind = "round", goal = 2, text = "Finish 2 rounds", echoes = 60, xp = 90 },
	{ id = "D_PUZZLE_2", kind = "puzzle", goal = 2, text = "Solve 2 puzzles", echoes = 60, xp = 90 },
	{ id = "D_DANGER_1", kind = "dangerous", goal = 1, text = "Report a dangerous anomaly", echoes = 70, xp = 100 },
}

Challenges.Weekly = {
	{ id = "W_ANOMALY_25", kind = "anomaly", goal = 25, text = "Find 25 anomalies", echoes = 400, xp = 600 },
	{ id = "W_SURVIVE_5", kind = "survive", goal = 5, text = "Survive 5 investigations", echoes = 500, xp = 700 },
	{ id = "W_CLEAN_2", kind = "clean", goal = 2, text = "Escape twice without a false report", echoes = 350, xp = 500 },
	{ id = "W_ROUNDS_10", kind = "round", goal = 10, text = "Finish 10 rounds", echoes = 400, xp = 600 },
	{ id = "W_PUZZLE_8", kind = "puzzle", goal = 8, text = "Solve 8 puzzles", echoes = 350, xp = 500 },
	{ id = "W_BLACKOUT_6", kind = "blackout", goal = 6, text = "Make it through 6 blackouts", echoes = 300, xp = 450 },
	{ id = "W_HARD_1", kind = "hard", goal = 1, text = "Escape on HARD or NIGHTMARE", echoes = 600, xp = 800 },
	{ id = "W_MIMIC_2", kind = "mimic", goal = 2, text = "Unmask 2 mimics", echoes = 450, xp = 650 },
}

Challenges.ById = {}
for _, list in { Challenges.Daily, Challenges.Weekly } do
	for _, c in list do
		Challenges.ById[c.id] = c
	end
end

Challenges.PerDay = 3
Challenges.PerWeek = 3

-- Day / week keys in UTC so everyone shares the same draw.
function Challenges.dayKey(t: number?): number
	return math.floor((t or os.time()) / 86400)
end

function Challenges.weekKey(t: number?): number
	-- weeks start on Monday (1970-01-01 was a Thursday)
	return math.floor(((t or os.time()) / 86400 + 3) / 7)
end

-- Deterministic draw of `count` distinct entries from a pool for a key.
function Challenges.draw(pool, key: number, count: number)
	local picked = {}
	local indices = {}
	for i = 1, #pool do
		indices[i] = i
	end
	local state = (key * 2654435761) % 4294967296
	for i = #indices, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = state % i + 1
		indices[i], indices[j] = indices[j], indices[i]
	end
	for i = 1, math.min(count, #indices) do
		table.insert(picked, pool[indices[i]])
	end
	return picked
end

return Challenges
