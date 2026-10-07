--[[
	Enums
	Shared string enums used by both server and client. Strings (instead of numbers)
	keep remote payloads readable when debugging and make DataStore content stable.
]]

local Enums = {}

Enums.RoundState = {
	Lobby = "LOBBY",
	Starting = "STARTING",
	Exploring = "EXPLORING",
	Objective = "OBJECTIVE",
	Escape = "ESCAPE",
	Results = "RESULTS",
	Returning = "RETURNING",
}

Enums.Difficulty = {
	Easy = "EASY",
	Normal = "NORMAL",
	Hard = "HARD",
}

Enums.DifficultyOrder = { "EASY", "NORMAL", "HARD" }

Enums.AnomalyScope = {
	Global = "GLOBAL",
	Player = "PLAYER",
	Team = "TEAM",
}

Enums.AnomalyCategory = {
	Visual = "VISUAL",
	Environment = "ENVIRONMENT",
	NPC = "NPC",
	Psychological = "PSYCHOLOGICAL",
	Dangerous = "DANGEROUS",
}

Enums.Rarity = {
	Common = "COMMON",
	Uncommon = "UNCOMMON",
	Rare = "RARE",
	Legendary = "LEGENDARY",
}

-- How an anomaly is resolved by players.
Enums.Detection = {
	Focus = "FOCUS", -- look at it and hold the report input
	Interact = "INTERACT", -- interact with the affected object
	Endure = "ENDURE", -- survive it without breaking its rule
}

Enums.ObserverState = {
	Dormant = "DORMANT",
	Watched = "WATCHED",
	Moving = "MOVING",
	Hunting = "HUNTING",
	Disappearing = "DISAPPEARING",
	Attacking = "ATTACKING",
}

Enums.PlayerStatus = {
	Menu = "MENU",
	Lobby = "LOBBY",
	Alive = "ALIVE",
	Dead = "DEAD",
	Escaped = "ESCAPED",
	Waiting = "WAITING", -- joined while a round is running
}

Enums.Ending = {
	Escaped = "ESCAPED",
	EscapedAlone = "ESCAPED_ALONE",
	EveryoneSurvived = "EVERYONE_SURVIVED",
	ObserverCaughtYou = "OBSERVER_CAUGHT_YOU",
	FailedToIdentify = "FAILED_TO_IDENTIFY",
	Witness = "THE_WITNESS", -- secret ending
}

Enums.TensionPhase = {
	Calm = "CALM",
	Tension = "TENSION",
	Fear = "FEAR",
	Relief = "RELIEF",
}

Enums.MusicState = {
	None = "NONE",
	Exploration = "EXPLORATION",
	Tension = "TENSION",
	Chase = "CHASE",
	Escape = "ESCAPE",
	Death = "DEATH",
	Results = "RESULTS",
	Menu = "MENU",
}

Enums.PingKind = {
	Anomaly = "ANOMALY",
	ComeHere = "COME_HERE",
	Danger = "DANGER",
	Door = "DOOR",
	Item = "ITEM",
}

return Enums
