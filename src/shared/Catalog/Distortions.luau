--[[
	Distortions
	Breaks in reality: rare, built events where the building stops obeying
	its own rules for one player, then puts everything back as if nothing
	happened. They are not jumpscares and not anomalies (nothing to report,
	nothing to count). DistortionService is the director; each event that is
	`enabled` has a server module (Server/Distortions/<id>) that runs it.

	Every entry defines
	  id, category, name        what it is
	  enabled                   false: designed, not built (never chosen)
	  weight                    relative chance among the eligible
	  cooldown                  seconds after ANY distortion before this one
	  perPlayer                 at most this many per player per round
	  perRound                  at most this many per round in total
	  minStory                  the story phase it needs (Enums.RoundPhase)
	  maxDuration               a hard limit: past it the event ends safely
	  intensity                 1 (a whisper) .. 3 (a set piece): no two
	                            intense moments overlap (one at a time)
	  players                   "solo": one player lives it, the others go on
	                            in the building
	  start/flow/exit/restore   in words: what the module does (the code is
	                            the authority; this is the design record)
	Activation, eligibility, interruption and restoration rules shared by
	every event live in DistortionService.
]]

local Distortions = {}

Distortions.List = {
	{
		id = "ImpossibleHallway",
		category = "SPACE",
		name = "The impossible hallway",
		enabled = true,
		weight = 1,
		cooldown = 300,
		perPlayer = 1,
		perRound = 2,
		minStory = "DISTORTION",
		maxDuration = 85,
		intensity = 3,
		players = "solo",
		start = "A flicker, the sound drops out, a cut to black: the player stands in a corridor far too long to exist, lit by fluorescent tubes, doors every few steps, all numbered the same.",
		flow = "The Observer stands at the far end. It waits, watching, while the player understands; then the dark starts to come down the corridor with it and it walks. Looking at it holds it only where light reaches it; nobody can stare forever. The exit is behind the player.",
		exit = "The player reaches the door at the end (success), it reaches them (taken: no death, a jolt and the building's attention), or a time limit (safe return).",
		restore = "Back in the room they left, where they stood, facing where they faced, as if they never left. One small thing in the room is different: a dead lamp, an open door, a frame hanging crooked.",
	},
	-- designed, not built yet: the director never chooses these
	{
		id = "Intruder",
		category = "PRESENCE",
		name = "The intruder",
		enabled = false,
		weight = 1,
		cooldown = 300,
		perPlayer = 1,
		perRound = 1,
		minStory = "DANGER",
		maxDuration = 40,
		intensity = 2,
		players = "solo",
		flow = "The Observer stands at the far end of a room. Walk toward it or away and the room's doors are no longer where they were.",
	},
	{
		id = "Loop",
		category = "SPACE",
		name = "The loop",
		enabled = false,
		weight = 1,
		cooldown = 300,
		perPlayer = 1,
		perRound = 1,
		minStory = "DISTORTION",
		maxDuration = 60,
		intensity = 2,
		players = "solo",
		flow = "A door leads back into the same corridor. Each pass, one detail is different, until a real way out appears.",
	},
	{
		id = "WrongRoom",
		category = "ROOM",
		name = "The wrong room",
		enabled = false,
		weight = 1,
		cooldown = 240,
		perPlayer = 1,
		perRound = 2,
		minStory = "UNEASE",
		maxDuration = 30,
		intensity = 1,
		players = "solo",
		flow = "For a few seconds an ordinary room holds something impossible. Leave and nothing happens; stay long enough and it reacts.",
	},
}

Distortions.ById = {}
for _, d in Distortions.List do
	Distortions.ById[d.id] = d
end

function Distortions.get(id: string)
	return Distortions.ById[id]
end

-- The events the director may choose (built and enabled).
function Distortions.enabled()
	local list = {}
	for _, d in Distortions.List do
		if d.enabled then
			table.insert(list, d)
		end
	end
	return list
end

return Distortions
