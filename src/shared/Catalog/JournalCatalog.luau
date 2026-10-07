--[[
	JournalCatalog
	Public, player-facing information for every anomaly. Server-side behaviour lives
	in ServerScriptService (Anomalies/*) and is keyed by the same id. Nothing here
	reveals where or when an anomaly will occur.
]]

local JournalCatalog = {}

-- number, id, name, category, rarity, description
local RAW = {
	-- VISUAL
	{ 1, "PAINTING_SWAP", "THE OTHER PAINTING", "VISUAL", "COMMON", "The frame is the same. What it holds is not." },
	{ 2, "PAINTING_GONE", "THE EMPTY HOOK", "VISUAL", "COMMON", "A pale rectangle on the wall where a painting used to hang." },
	{ 3, "CLOCK_WRONG", "WRONG HOUR", "VISUAL", "UNCOMMON", "The clock disagrees with every other clock in the building." },
	{ 4, "CLOCK_STOPPED", "THE STOPPED CLOCK", "VISUAL", "UNCOMMON", "The second hand waits. So should you." },
	{ 5, "CHAIR_APPEARS", "ONE MORE SEAT", "VISUAL", "COMMON", "Someone pulled up a chair. Nobody sat down." },
	{ 6, "CHAIR_GONE", "THE MISSING CHAIR", "VISUAL", "COMMON", "There were four chairs. Count again." },
	{ 7, "EXTRA_DOOR", "THE EXTRA DOOR", "VISUAL", "UNCOMMON", "A door on a wall that has never had one. It does not open." },
	{ 8, "DOOR_GONE", "THE SEALED DOORWAY", "VISUAL", "RARE", "The doorway is plaster now. Still warm." },
	{ 9, "WINDOW_CHANGE", "THE OPEN WINDOW", "VISUAL", "UNCOMMON", "The boards are gone. The handprints are on the inside." },
	{ 10, "OBJECT_MOVED", "IT WAS OVER THERE", "VISUAL", "COMMON", "Small things move when nobody is counting them." },
	{ 11, "OBJECT_COLOR", "THE WRONG SHADE", "VISUAL", "COMMON", "Same object. Different colour. You are sure of it." },
	{ 12, "LAMP_CHANGE", "THE WRONG LAMP", "VISUAL", "COMMON", "The lamp is lit with a light that is not quite light." },
	{ 13, "PLANT_GONE", "THE WILTED SPACE", "VISUAL", "COMMON", "Only a ring of soil remains on the floor." },
	{ 14, "MIRROR_CHANGE", "THE CRACKED MIRROR", "VISUAL", "UNCOMMON", "It cracked without a sound." },
	{ 15, "ROOM_NUMBER", "ROOM 1O4", "VISUAL", "UNCOMMON", "The numbers on the door have rearranged themselves." },
	{ 16, "TEXT_CHANGE", "THE SIGN THAT LIES", "VISUAL", "UNCOMMON", "Read it again. Slowly." },
	{ 17, "PHOTO_CHANGE", "ONE MORE IN THE PHOTO", "VISUAL", "RARE", "The staff photograph has one more employee." },
	{ 18, "MANNEQUIN", "THE NEW EMPLOYEE", "VISUAL", "UNCOMMON", "It wears a staff badge. The badge has no name." },
	-- ENVIRONMENT
	{ 19, "CORRIDOR_LONGER", "THE LONG WAY DOWN", "ENVIRONMENT", "RARE", "The basement corridor goes further than the building does." },
	{ 20, "ROOM_BIGGER", "MORE ROOM", "ENVIRONMENT", "RARE", "The boiler room has grown into the earth." },
	{ 21, "ROOM_SMALLER", "THE CLOSING WALL", "ENVIRONMENT", "RARE", "The office is smaller than it was a minute ago." },
	{ 22, "DOOR_PORTAL", "THE WRONG SIDE", "ENVIRONMENT", "RARE", "You walked through a door and arrived somewhere else." },
	{ 23, "LIGHTS_CHANGE", "COLD LIGHT", "ENVIRONMENT", "COMMON", "The room is lit by a colour no bulb makes." },
	{ 24, "FLOOR_CHANGE", "THE NEW FLOOR", "ENVIRONMENT", "UNCOMMON", "Nobody re-floored this room. Nobody has been here in years." },
	{ 25, "CEILING_LOW", "LOW CEILING", "ENVIRONMENT", "UNCOMMON", "The ceiling has come down to meet you." },
	{ 26, "WATER", "STANDING WATER", "ENVIRONMENT", "UNCOMMON", "Still water. No source. No ripples until you step in." },
	{ 27, "FOG", "INDOOR FOG", "ENVIRONMENT", "UNCOMMON", "Something exhaled in here." },
	{ 28, "FLOATING", "WEIGHTLESS", "ENVIRONMENT", "RARE", "Everything in the room forgot how heavy it is." },
	-- NPC
	{ 29, "NPC_APPEARS", "THE VISITOR", "NPC", "UNCOMMON", "A resident stands where nobody was standing." },
	{ 30, "NPC_GONE", "THE EMPTY DESK", "NPC", "UNCOMMON", "The resident who never moves has moved away." },
	{ 31, "NPC_MOVED", "THE RESTLESS ONE", "NPC", "UNCOMMON", "The resident is somewhere else now. Facing you." },
	{ 32, "NPC_WATCHING", "EYES ON YOU", "NPC", "UNCOMMON", "It has no eyes. It is still following you with them." },
	{ 33, "NPC_BEHIND", "OVER YOUR SHOULDER", "NPC", "RARE", "Someone is standing right behind you. Only you." },
	{ 34, "NPC_CREEP", "CLOSER EACH TIME", "NPC", "RARE", "Every time you look away, it takes a step." },
	-- PSYCHOLOGICAL
	{ 35, "PHONE_RING", "THE CALL", "PSYCHOLOGICAL", "COMMON", "The line has been dead since 1994. Answer it." },
	{ 36, "TEAMMATE_VOICE", "A FAMILIAR VOICE", "PSYCHOLOGICAL", "UNCOMMON", "Your friend called you from a room they were never in." },
	{ 37, "FOOTSTEPS_BEHIND", "WET FOOTPRINTS", "PSYCHOLOGICAL", "UNCOMMON", "Footsteps that leave prints. Barefoot. Long." },
	{ 38, "BREATHING", "SOMETHING BREATHES", "PSYCHOLOGICAL", "UNCOMMON", "Slow breathing from inside a closed space." },
	{ 39, "DOOR_KNOCK", "THREE KNOCKS", "PSYCHOLOGICAL", "COMMON", "From the other side of a door. Always three." },
	{ 40, "WRONG_SHADOW", "THE SHADOW WITHOUT OWNER", "PSYCHOLOGICAL", "RARE", "A shadow on the wall with nothing to cast it." },
	{ 41, "WRONG_REFLECTION", "BEHIND YOU, IN THE GLASS", "PSYCHOLOGICAL", "RARE", "The glass shows one more person than the room holds." },
	{ 42, "FIGURE_DISTANT", "AT THE END OF THE HALL", "PSYCHOLOGICAL", "UNCOMMON", "A shape at the far end of the corridor. Only you saw it." },
	-- DANGEROUS
	{ 43, "STARE_ENTITY", "DON'T STARE", "DANGEROUS", "UNCOMMON", "A pale figure in a doorway. Report it. Do not admire it." },
	{ 44, "WRONG_OBJECT", "THE DUPLICATE", "DANGEROUS", "UNCOMMON", "One of the things you need is not what it pretends to be." },
	{ 45, "LIGHTS_OUT", "KEEP THE LIGHT ON", "DANGEROUS", "RARE", "When the lights die and the whispering starts, keep your own light burning." },
	{ 46, "LOOK_BACK", "DON'T TURN AROUND", "DANGEROUS", "RARE", "It follows close behind. It only needs you to look." },
	{ 47, "WRONG_ROOM", "ROOM B-13", "DANGEROUS", "RARE", "There is no room B-13. Don't go in." },
	{ 48, "FALSE_PING", "THE FALSE SIGNAL", "DANGEROUS", "UNCOMMON", "A marker no one placed, calling you somewhere dark." },
	-- LEGENDARY
	{ 49, "ROOM_ZERO", "ROOM 0", "ENVIRONMENT", "LEGENDARY", "A door numbered zero. It was always here. It was never here." },
	{ 50, "YOUR_NAME", "EVERYONE IS YOU", "PSYCHOLOGICAL", "LEGENDARY", "Every name in the building is yours." },
}

JournalCatalog.List = {}
JournalCatalog.ById = {}

for _, row in RAW do
	local entry = {
		number = row[1],
		id = row[2],
		name = row[3],
		category = row[4],
		rarity = row[5],
		description = row[6],
	}
	table.insert(JournalCatalog.List, entry)
	JournalCatalog.ById[entry.id] = entry
end

JournalCatalog.Count = #JournalCatalog.List

JournalCatalog.RarityColors = {
	COMMON = Color3.fromRGB(190, 190, 186),
	UNCOMMON = Color3.fromRGB(150, 178, 160),
	RARE = Color3.fromRGB(140, 160, 196),
	LEGENDARY = Color3.fromRGB(206, 182, 120),
}

function JournalCatalog.format(number: number): string
	return string.format("ANOMALY #%03d", number)
end

return JournalCatalog
