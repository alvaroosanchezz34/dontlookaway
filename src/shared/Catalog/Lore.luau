--[[
	Lore
	The Ashgrove Observation Project, told in short pieces found in the building
	and kept in the ARCHIVE (Field Office records terminal).

	Chapters are the order the story unlocks in. Each night the building offers
	the team documents from the earliest chapters they have not finished, so
	the story arrives in order without ever being a wall of text:

	  1  Ashgrove was a project            5  the researchers disappear
	  2  something strange appears          6  it imitates people
	  3  the rooms begin to change          7  Vale discovers something
	  4  the Observer appears               8  THE WITNESS

	It never says what the Observer is. Three readings are seeded on purpose:
	an ENTITY (it hunts, it learns), a PERCEPTUAL phenomenon (it is what an
	unobserved world looks like when it looks back), and something from OUTSIDE
	(the building is a window, not a container).

	kind: "doc" | "tape" (audio log transcript) | "photo" (a described photograph)
	`witness = true` marks the entries that point to the secret ending.
]]

local Lore = {}

Lore.Categories = { "PROJECT FILES", "PERSONNEL", "INCIDENTS", "RESEARCH", "AUDIO LOGS", "PHOTOGRAPHS", "CLASSIFIED" }

-- Entries needed (found across all your nights) before the photograph from the
-- hidden room develops into THE WITNESS ending.
Lore.WitnessRequired = 10

Lore.List = {
	-- 1. Ashgrove was a project ------------------------------------------------
	{ id = "PF_CHARTER", chapter = 1, category = "PROJECT FILES", kind = "doc", title = "PROJECT CHARTER",
		body = "ASHGROVE OBSERVATION PROJECT\nDirector: Dr. Elias Vale\n\nAim: to document THE UNOBSERVED - events that occur only while no one is watching.\n\nFunding approved for one year." },
	{ id = "PE_VALE", chapter = 1, category = "PERSONNEL", kind = "doc", title = "STAFF FILE - VALE, E.",
		body = "Dr. Elias Vale. Physicist, later perception studies.\nNotes: brilliant, patient, sleeps in his office.\nInsists every room be photographed twice a day." },
	{ id = "PH_STAFF", chapter = 1, category = "PHOTOGRAPHS", kind = "photo", title = "STAFF PHOTOGRAPH, YEAR ONE",
		body = "[Eleven people on the front steps. Dr. Vale in the middle, squinting into the sun.]\n\nOn the back, in pencil: 'everyone accounted for.'" },
	{ id = "RE_METHOD", chapter = 1, category = "RESEARCH", kind = "doc", title = "METHOD, REV. 2",
		body = "1. Photograph the room.\n2. Leave. Lock it. Nobody watches.\n3. Return. Photograph again.\n4. Compare.\n\nWe expect nothing. That is the point." },

	-- 2. Something strange appears ---------------------------------------------
	{ id = "IN_14", chapter = 2, category = "INCIDENTS", kind = "doc", title = "INCIDENT 14",
		body = "Room 1-02. The clock in the second photograph reads 3:40.\nIt was 9:15.\nThe clock has no batteries." },
	{ id = "AL_VALE_01", chapter = 2, category = "AUDIO LOGS", kind = "tape", title = "VALE - LOG 01",
		body = "\"Day forty. A chair moved eleven centimetres. Nobody was inside. I'm... delighted. Something happens when we stop looking. We just have to be very careful not to look.\"" },
	{ id = "NT_DAY3", chapter = 2, category = "INCIDENTS", kind = "doc", title = "NOTE",
		body = "Day 3.\nThe staff photo in the corridor has one more face than we have staff.\nNobody will say whose." },
	{ id = "RE_RULE", chapter = 2, category = "RESEARCH", kind = "doc", title = "WORKING HYPOTHESIS",
		body = "If you stop looking at a thing, it stops having to be what it was.\n\nCorollary: keep your eyes on the doors." },

	-- 3. The rooms begin to change ---------------------------------------------
	{ id = "IN_BASEMENT", chapter = 3, category = "INCIDENTS", kind = "doc", title = "NOTE",
		body = "The basement corridor was longer this morning.\nI counted the lights. There were more lights." },
	{ id = "NT_PAINTING", chapter = 3, category = "INCIDENTS", kind = "doc", title = "NOTE",
		body = "Marta says the painting in reception used to be a landscape.\nI have worked here eleven years.\nIt has always been a portrait.\nHasn't it?" },
	{ id = "MM_FUSES", chapter = 3, category = "PROJECT FILES", kind = "doc", title = "FACILITIES MEMO",
		body = "The fuses burn out at the same minute every night.\nWe have replaced the wiring twice.\nStop asking for a third." },
	{ id = "AL_VALE_02", chapter = 3, category = "AUDIO LOGS", kind = "tape", title = "VALE - LOG 02",
		body = "\"The rooms don't drift at random. They change toward something. As if the building is rehearsing a shape it hasn't decided on yet.\"" },
	{ id = "NT_104", chapter = 3, category = "INCIDENTS", kind = "doc", title = "NOTE",
		body = "Room numbers on the first floor skip 1-04.\nThere is a door where 1-04 should be.\nIt's only there when the lights are off." },

	-- 4. The Observer appears ---------------------------------------------------
	{ id = "CL_O01", chapter = 4, category = "CLASSIFIED", kind = "doc", title = "SUBJECT O-01",
		body = "Designation: SUBJECT O-01.\nHeight: 2.9 m (est.)\nMobility: none observed.\nAll movement occurs between observations.\n\nDo not refer to O-01 by any other name." },
	{ id = "MM_STAIRWELL", chapter = 4, category = "PROJECT FILES", kind = "doc", title = "MEMO TO ALL STAFF",
		body = "Do not report the tall man in the stairwell.\nHe does not like being written down." },
	{ id = "NT_BLINK", chapter = 4, category = "RESEARCH", kind = "doc", title = "NOTE",
		body = "It only moves when you blink.\nYou can't stop blinking.\nSo don't be alone." },
	{ id = "PH_STAIRS", chapter = 4, category = "PHOTOGRAPHS", kind = "photo", title = "PHOTOGRAPH - STAIRWELL, 02:11",
		body = "[An empty stairwell. In the second exposure of the same roll, a pale shape stands on the landing. It is taller than the doorway behind it.]" },

	-- 5. The researchers disappear ----------------------------------------------
	{ id = "IN_41", chapter = 5, category = "INCIDENTS", kind = "doc", title = "INCIDENT 41",
		body = "Employee reported a colleague waving from the end of the hall.\nThe colleague was at home." },
	{ id = "IN_57", chapter = 5, category = "INCIDENTS", kind = "doc", title = "INCIDENT 57",
		body = "Night guard found asleep at the desk with his eyes taped open.\nHe said it was the only way to keep it still." },
	{ id = "PE_ROSTER", chapter = 5, category = "PERSONNEL", kind = "doc", title = "ROSTER, MONTH NINE",
		body = "Active staff: 6.\nOn leave: 0.\nUnaccounted for: 5.\n\nAdministration has been told the five resigned." },
	{ id = "AL_VOICEMAIL", chapter = 5, category = "AUDIO LOGS", kind = "tape", title = "VOICEMAIL",
		body = "\"...it's me. I'm still in the archive. I can hear you in the corridor, why won't you answer? You're standing right outside the door. I can see your shoes under the-\"" },

	-- 6. It imitates people ------------------------------------------------------
	{ id = "IN_63", chapter = 6, category = "INCIDENTS", kind = "doc", title = "INCIDENT 63",
		body = "Six people entered for the evening inspection. Six people left.\nThe signing-out sheet has seven signatures." },
	{ id = "NT_SMILE", chapter = 6, category = "RESEARCH", kind = "doc", title = "NOTE",
		body = "If someone you came with looks at you a moment too long, ask them something only they would know.\nIf they smile before answering, run." },
	{ id = "RE_MIMIC", chapter = 6, category = "RESEARCH", kind = "doc", title = "OBSERVATION LOG 88",
		body = "O-01 has begun to appear as staff.\nThe copies are good. Not perfect.\nThey wave too slowly. They never wear their badges.\nThey always stop to watch." },
	{ id = "MM_QUIET", chapter = 6, category = "PROJECT FILES", kind = "doc", title = "MEMO TO ALL STAFF",
		body = "The Quiet Room is not a storage room.\nPlease return the child's things.\nShe gets upset." },

	-- 7. Vale discovers something -----------------------------------------------
	{ id = "AL_VALE_03", chapter = 7, category = "AUDIO LOGS", kind = "tape", title = "VALE - LOG 03",
		body = "\"We had it backwards. The building doesn't change when we stop looking. It changes when IT starts. We were never the observers here.\"" },
	{ id = "RE_THREE", chapter = 7, category = "RESEARCH", kind = "doc", title = "VALE - THREE READINGS",
		body = "1. It is a creature, and it is learning us.\n2. It is what the world looks like when the world looks back.\n3. It is not in the building. The building is where it can see in from.\n\nI no longer think it matters which." },
	{ id = "CL_ROOM_Z", chapter = 7, category = "CLASSIFIED", kind = "doc", title = "BASEMENT PLAN (ANNOTATED)", witness = true,
		body = "There is a room behind the boarded wall in the basement that is not on the plans.\nVale kept one photograph in there.\n\n'The only picture it is not in.'" },
	{ id = "PE_VALE_LAST", chapter = 7, category = "PERSONNEL", kind = "doc", title = "STAFF FILE - VALE, E. (AMENDED)", witness = true,
		body = "Status: unknown.\nLast seen carrying a single photograph toward the loading dock.\nHe said it had to leave the building with someone who had read everything.\n'Or it won't develop.'" },

	-- 8. The Witness ---------------------------------------------------------------
	{ id = "CL_WITNESS", chapter = 8, category = "CLASSIFIED", kind = "doc", title = "THE WITNESS", witness = true,
		body = "A photograph taken by someone who knew what they were looking at, carried out of Ashgrove.\nIf it develops, the project was not for nothing.\n\nIf it develops, look closely at who is standing behind you in it." },
	{ id = "AL_VALE_04", chapter = 8, category = "AUDIO LOGS", kind = "tape", title = "VALE - LOG 04 (LAST)",
		body = "\"If you are hearing this you got further than any of us. Don't look for me. Look at the photograph. Count the people. Then count again when you're outside.\"" },
}

Lore.ById = {}
for i, e in Lore.List do
	e.order = i
	Lore.ById[e.id] = e
end

Lore.Count = #Lore.List

-- How much of the archive has a profile found?
function Lore.found(profileLore: { [string]: any }?): number
	local n = 0
	for id in profileLore or {} do
		if Lore.ById[id] then
			n += 1
		end
	end
	return n
end

-- The chapter a profile has reached (the lowest chapter with unfound entries).
function Lore.chapter(profileLore: { [string]: any }?): number
	for chapter = 1, 8 do
		for _, e in Lore.List do
			if e.chapter == chapter and not (profileLore and profileLore[e.id]) then
				return chapter
			end
		end
	end
	return 9
end

--[[
	Picks `count` entries for tonight's building: the team's unfound entries
	from the earliest chapters first (so the story is told in order), never an
	entry beyond the team's current chapter + 1. Falls back to re-reads.
	`team` is a list of profile lore tables. `rng` has :Shuffle.
]]
function Lore.pick(team: { { [string]: any } }, count: number, rng): { any }
	local chapter = 9
	for _, lore in team do
		chapter = math.min(chapter, Lore.chapter(lore))
	end
	local unfound, seen = {}, {}
	for _, e in Lore.List do
		local missing = false
		for _, lore in team do
			if not lore[e.id] then
				missing = true
			end
		end
		if missing and e.chapter <= chapter + 1 then
			table.insert(unfound, e)
		elseif e.chapter <= math.max(chapter, 2) then
			table.insert(seen, e)
		end
	end
	rng:Shuffle(unfound)
	table.sort(unfound, function(a, b)
		return a.chapter < b.chapter
	end)
	local out = {}
	for _, e in unfound do
		if #out >= count then
			break
		end
		table.insert(out, e)
	end
	rng:Shuffle(seen)
	for _, e in seen do
		if #out >= count then
			break
		end
		table.insert(out, e)
	end
	return out
end

return Lore
