--[[
	Achievements
	Server evaluates and awards; this is the shared description.
]]

local Achievements = {}

Achievements.List = {
	{ id = "FIRST_NIGHT", name = "FIRST NIGHT", description = "Finish your first round.", echoes = 25 },
	{ id = "ESCAPED", name = "ESCAPED", description = "Escape the Ashgrove Building.", echoes = 50 },
	{ id = "NO_LIGHT", name = "NO LIGHT", description = "Escape having used your flashlight for less than a minute.", echoes = 120 },
	{ id = "FOUND_10", name = "TRAINED EYE", description = "Report 10 anomalies.", echoes = 40 },
	{ id = "FOUND_50", name = "NOTHING ESCAPES YOU", description = "Report 50 anomalies.", echoes = 120 },
	{ id = "FOUND_150", name = "ARCHIVIST", description = "Report 150 anomalies.", echoes = 300 },
	{ id = "SURVIVED_ALONE", name = "SURVIVED ALONE", description = "Escape in a solo round.", echoes = 80 },
	{ id = "FULL_HOUSE", name = "SURVIVED WITH 4", description = "Escape in a round with 4 players.", echoes = 80 },
	{ id = "EVERYONE_OUT", name = "NOBODY LEFT BEHIND", description = "Everyone escapes in a round with 2 or more players.", echoes = 100 },
	{ id = "NEVER_LOOK_BACK", name = "NEVER LOOK BACK", description = "Survive 'DON'T TURN AROUND' without turning around.", echoes = 90 },
	{ id = "MET_OBSERVER", name = "MET THE OBSERVER", description = "See The Observer for the first time.", echoes = 20 },
	{ id = "LOW_BATTERY", name = "ON FUMES", description = "Escape with less than 10% flashlight battery.", echoes = 70 },
	{ id = "JOURNAL_25", name = "HALF THE STORY", description = "Discover 25 different anomalies.", echoes = 150 },
	{ id = "JOURNAL_ALL", name = "THE COMPLETE RECORD", description = "Discover every anomaly in the Journal.", echoes = 500 },
	{ id = "SECRET_ROOM", name = "BEHIND THE BOARDS", description = "Find the room that is not on the floor plan.", echoes = 80 },
	{ id = "THE_WITNESS", name = "THE WITNESS", description = "Leave with something that should not leave.", echoes = 250 },
	{ id = "HARD_ESCAPE", name = "UNBLINKING", description = "Escape on HARD.", echoes = 150 },
	{ id = "QUICK_EXIT", name = "QUICK EXIT", description = "Escape in under 9 minutes.", echoes = 100 },
	{ id = "PERFECT_EYE", name = "PERFECT EYE", description = "Escape without a single false report.", echoes = 90 },
	{ id = "SAVED_BY_WARD", name = "THREAD AND LUCK", description = "Be saved by a Ward.", echoes = 40 },
	{ id = "CAUGHT", name = "CAUGHT", description = "Get caught by The Observer.", echoes = 15 },
	{ id = "GUARDIAN", name = "EYES FOR EACH OTHER", description = "Freeze The Observer while it hunts a teammate.", echoes = 60 },
	{ id = "LEGENDARY_SIGHT", name = "ONCE IN A LIFETIME", description = "Report a legendary anomaly.", echoes = 200 },
	{ id = "PUZZLE_MASTER", name = "CARETAKER", description = "Solve every kind of puzzle in the building.", echoes = 120 },
}

Achievements.ById = {}
for _, a in Achievements.List do
	Achievements.ById[a.id] = a
end

return Achievements
