--[[
	Pings
	Communication markers. Text-first so they read clearly without voice chat.
]]

local Pings = {}

Pings.Order = { "ANOMALY", "COME_HERE", "DANGER", "DOOR", "ITEM" }

Pings.List = {
	ANOMALY = { label = "ANOMALY", sound = "PingAnomaly", color = Color3.fromRGB(226, 222, 210) },
	COME_HERE = { label = "COME HERE", sound = "PingComeHere", color = Color3.fromRGB(200, 214, 226) },
	DANGER = { label = "DANGER", sound = "PingDanger", color = Color3.fromRGB(190, 60, 56) },
	DOOR = { label = "DOOR", sound = "PingDoor", color = Color3.fromRGB(206, 196, 176) },
	ITEM = { label = "ITEM", sound = "PingItem", color = Color3.fromRGB(214, 206, 160) },
}

return Pings
