--[[
	Pings
	Communication markers. Text-first so they read clearly without voice chat.
]]

local Pings = {}

Pings.Order = { "ANOMALY", "FOUND_IT", "COME_HERE", "WAIT", "DANGER", "DOOR", "ITEM", "OBJECTIVE" }

Pings.List = {
	ANOMALY = { label = "ANOMALY?", sound = "PingAnomaly", color = Color3.fromRGB(226, 222, 210) },
	FOUND_IT = { label = "FOUND IT", sound = "PingAnomaly", color = Color3.fromRGB(150, 200, 230) },
	COME_HERE = { label = "COME HERE", sound = "PingComeHere", color = Color3.fromRGB(200, 214, 226) },
	WAIT = { label = "WAIT FOR ME", sound = "PingComeHere", color = Color3.fromRGB(190, 190, 200) },
	DANGER = { label = "DANGER", sound = "PingDanger", color = Color3.fromRGB(190, 60, 56) },
	DOOR = { label = "DOOR", sound = "PingDoor", color = Color3.fromRGB(206, 196, 176) },
	ITEM = { label = "ITEM", sound = "PingItem", color = Color3.fromRGB(214, 206, 160) },
	OBJECTIVE = { label = "OBJECTIVE", sound = "PingItem", color = Color3.fromRGB(170, 210, 180) },
}

-- What a quick (tap) ping means when it lands on something you can use.
Pings.ForInteractKind = {
	Pickup = "ITEM",
	Door = "DOOR",
	FuseBox = "OBJECTIVE",
	Breaker = "OBJECTIVE",
	Keypad = "OBJECTIVE",
	SymbolDial = "OBJECTIVE",
	Override = "OBJECTIVE",
	Offering = "OBJECTIVE",
	Boards = "OBJECTIVE",
	TapeRecorder = "ITEM",
	Document = "ITEM",
}

return Pings
