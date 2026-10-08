--[[
	Equipment
	Investigation gear bought with Echoes and carried in the LOADOUT. Every
	piece has a real use, but none of it is required: the starter kit is enough
	to finish any night. Better gear mostly buys comfort, information and
	versatility, never invulnerability. Nothing here can be bought with Robux.

	Kinds
	  FLASHLIGHT  replaces the hand light (range / angle / output / drain) and has
	              its own `beam`: colour temperature, hot-core vs flood ratio,
	              warm-up, bulb wobble, switch click and behaviour (graceful
	              fade on a weak battery, `sense`: dims near the Observer)
	  BATTERY     the cell in it (capacity)
	  TOOL        carried on the tool belt (loadout slots), used in a round

	Rarity: COMMON, UNCOMMON, RARE, EPIC, LEGENDARY. Prices rise with rarity and
	most pieces also need a level, so progression lasts many nights.

	Upgrades are permanent, levelled improvements (quality of life, utility,
	information). Loadout slots: 3 by default, up to 5 with POCKETS.
]]

local Equipment = {}

Equipment.Rarities = { "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" }

Equipment.RarityColors = {
	COMMON = Color3.fromRGB(170, 172, 176),
	UNCOMMON = Color3.fromRGB(150, 196, 168),
	RARE = Color3.fromRGB(132, 168, 220),
	EPIC = Color3.fromRGB(184, 150, 220),
	LEGENDARY = Color3.fromRGB(226, 196, 132),
}

Equipment.Kinds = { "FLASHLIGHT", "BATTERY", "TOOL" }

Equipment.KindNames = {
	FLASHLIGHT = "FLASHLIGHTS",
	BATTERY = "BATTERIES",
	TOOL = "TOOLS",
}

Equipment.List = {
	-- Flashlights: the starter is a real flashlight; better ones are kinder to use
	{ id = "FL_STARTER", kind = "FLASHLIGHT", name = "Starter Flashlight", rarity = "COMMON", default = true, range = 46, angle = 52, power = 2.6, drain = 1, beam = { tone = Color3.fromRGB(255, 232, 196), core = 0.42, spill = 0.75, warmup = 0.32, wobble = 0.05, switch = 0.9, feel = "Old bulb: warm, soft, a lazy warm-up." }, description = "Dependable. Gets you home." },
	{ id = "FL_INDUSTRIAL", kind = "FLASHLIGHT", name = "Industrial Flashlight", rarity = "UNCOMMON", price = 600, level = 3, range = 52, angle = 56, power = 2.75, drain = 0.95, beam = { tone = Color3.fromRGB(255, 226, 172), core = 0.6, spill = 0.95, warmup = 0.22, wobble = 0.025, switch = 0.75, feel = "Halogen flood: lights the whole room, not the far end." }, description = "A wider beam and a little more reach." },
	{ id = "FL_TACTICAL", kind = "FLASHLIGHT", name = "Tactical Flashlight", rarity = "RARE", price = 1600, level = 8, range = 60, angle = 44, power = 3.1, drain = 0.9, beam = { tone = Color3.fromRGB(222, 234, 255), core = 0.3, spill = 0.45, warmup = 0, wobble = 0.008, switch = 1.25, feel = "Cold LED spot: instant, a hard bright centre, dark edges." }, description = "A tight, bright beam for long corridors." },
	{ id = "FL_ADVANCED", kind = "FLASHLIGHT", name = "Lumen-9 Advanced", rarity = "EPIC", price = 3800, level = 15, range = 64, angle = 58, power = 3.25, drain = 0.85, beam = { tone = Color3.fromRGB(246, 246, 255), core = 0.45, spill = 0.85, warmup = 0.08, wobble = 0.01, switch = 1.1, graceful = true, feel = "Even and clean. A weak battery fades it instead of making it stutter." }, description = "Wide and long. Kind to its battery." },
	{ id = "FL_PROTOTYPE", kind = "FLASHLIGHT", name = "Halcyon Prototype", rarity = "LEGENDARY", price = 8000, level = 25, range = 68, angle = 60, power = 3.35, drain = 0.8, steady = true, beam = { tone = Color3.fromRGB(236, 232, 255), core = 0.44, spill = 0.85, warmup = 0.05, wobble = 0.004, switch = 1.4, graceful = true, sense = true, feel = "Never stutters. Near IT, it slowly dims and breathes instead: a warning." }, description = "Never stutters on a weak battery. Nobody knows who built it." },

	-- Batteries: capacity in percent of the standard cell
	{ id = "BAT_STANDARD", kind = "BATTERY", name = "Standard Battery", rarity = "COMMON", default = true, capacity = 100, description = "A standard cell." },
	{ id = "BAT_EXTENDED", kind = "BATTERY", name = "Extended Battery", rarity = "UNCOMMON", price = 500, level = 2, capacity = 125, description = "A quarter more light." },
	{ id = "BAT_HIGH", kind = "BATTERY", name = "High Capacity Cell", rarity = "RARE", price = 1400, level = 7, capacity = 150, description = "Half again as much light." },

	-- Tools
	{ id = "GLOWSTICKS", kind = "TOOL", name = "Glow Sticks", rarity = "COMMON", price = 150, charges = 4, description = "Drop one to light a spot and mark where you have been." },
	{ id = "SPARE_CELL", kind = "TOOL", name = "Spare Cell", rarity = "COMMON", price = 200, charges = 1, description = "One extra battery, already in your pocket." },
	{ id = "FIELD_RADIO", kind = "TOOL", name = "Field Radio", rarity = "COMMON", price = 250, level = 2, description = "Hold it to see where your team is. It crackles when something is near." },
	{ id = "MOTION_SENSOR", kind = "TOOL", name = "Tripwire Sensor", rarity = "UNCOMMON", price = 450, level = 4, charges = 2, description = "Place it on the floor. It warns the whole team when something passes." },
	{ id = "INSTANT_CAMERA", kind = "TOOL", name = "Instant Camera", rarity = "UNCOMMON", price = 700, level = 5, charges = 6, description = "Photograph an anomaly from further away. Developed evidence pays a bonus." },
	{ id = "RESONANCE_METER", kind = "TOOL", name = "Resonance Meter", rarity = "RARE", price = 1200, level = 9, description = "Hold it to feel for changes nearby. More bars, closer." },
	{ id = "SIGNAL_TRACKER", kind = "TOOL", name = "Signal Tracker", rarity = "RARE", price = 1500, level = 11, charges = 3, description = "Points toward the nearest thing the night still needs: fuses, keys, belongings." },
	{ id = "THERMAL_VIEWER", kind = "TOOL", name = "Thermal Viewer", rarity = "EPIC", price = 2600, level = 14, charge = 30, description = "Things that are not alive show up cold. So does anyone who is not who they seem." },
	{ id = "ANOMALY_LENS", kind = "TOOL", name = "Anomaly Lens", rarity = "EPIC", price = 3000, level = 18, cooldown = 30, description = "Look through it to make nearby changes shimmer for a moment." },
}

Equipment.ById = {}
for _, e in Equipment.List do
	Equipment.ById[e.id] = e
end

Equipment.Defaults = {
	FLASHLIGHT = "FL_STARTER",
	BATTERY = "BAT_STANDARD",
}

--[[
	Upgrades: id, name, levels = { { price, level? }, ... }, effect per level.
]]
Equipment.Upgrades = {
	{ id = "POCKETS", name = "Field Vest", description = "Carry one more tool.", per = "+1 loadout slot", levels = { { price = 900, level = 4 }, { price = 2400, level = 12 } } },
	{ id = "BATTERY_LIFE", name = "Efficient Wiring", description = "Every flashlight drains more slowly.", per = "-6% drain", levels = { { price = 350, level = 2 }, { price = 900, level = 6 }, { price = 1800, level = 10 } } },
	{ id = "STEADY_HANDS", name = "Steady Hands", description = "Hold interactions (doors, boards, fuses) finish faster.", per = "-10% hold time", levels = { { price = 300, level = 2 }, { price = 800, level = 5 }, { price = 1500, level = 9 } } },
	{ id = "SIGNAL_READING", name = "Signal Reading", description = "Meters, trackers and sensors reach further.", per = "+20% range", levels = { { price = 700, level = 7 }, { price = 1700, level = 13 } } },
	{ id = "FIELD_NOTES", name = "Field Notes", description = "Reported anomalies are written up properly: their class shows when you report, and evidence pays a little more.", per = "+10% anomaly Echoes", levels = { { price = 1000, level = 8 } } },
}

Equipment.UpgradesById = {}
for _, u in Equipment.Upgrades do
	Equipment.UpgradesById[u.id] = u
end

Equipment.BaseLoadoutSlots = 3
Equipment.MaxLoadoutSlots = 5

function Equipment.get(id: string)
	return Equipment.ById[id]
end

function Equipment.loadoutSlots(upgrades: { [string]: number }?): number
	local extra = (upgrades and upgrades.POCKETS) or 0
	return math.clamp(Equipment.BaseLoadoutSlots + extra, Equipment.BaseLoadoutSlots, Equipment.MaxLoadoutSlots)
end

-- Multipliers from upgrades (shared so the client can show the numbers).
function Equipment.drainMultiplier(upgrades: { [string]: number }?): number
	return 1 - 0.06 * ((upgrades and upgrades.BATTERY_LIFE) or 0)
end

function Equipment.holdMultiplier(upgrades: { [string]: number }?): number
	return 1 - 0.1 * ((upgrades and upgrades.STEADY_HANDS) or 0)
end

function Equipment.rangeMultiplier(upgrades: { [string]: number }?): number
	return 1 + 0.2 * ((upgrades and upgrades.SIGNAL_READING) or 0)
end

return Equipment
