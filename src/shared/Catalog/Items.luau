--[[
	Items
	Definitions for every inventory item. Behaviour lives on the server
	(InventoryService / ObjectiveService); this table is the shared description.
]]

local Items = {}

Items.List = {
	FUSE = {
		name = "Fuse",
		description = "A heavy ceramic fuse. The fuse box in Maintenance takes three.",
		stack = 3,
		color = Color3.fromRGB(196, 170, 120),
		icon = "fuse",
		important = true,
	},
	BATTERY = {
		name = "Battery",
		description = "Use to recharge your flashlight.",
		stack = 2,
		color = Color3.fromRGB(150, 160, 150),
		icon = "battery",
		usable = true,
	},
	MAINT_KEY = {
		name = "Maintenance Key",
		description = "A brass key on a red tag: MAINT. B1.",
		stack = 1,
		color = Color3.fromRGB(200, 165, 80),
		icon = "key",
		important = true,
	},
	OFFICE_KEY = {
		name = "Office Key",
		description = "A small key stamped G-02.",
		stack = 1,
		color = Color3.fromRGB(180, 180, 175),
		icon = "key",
		important = true,
	},
	TAPE = {
		name = "Cassette",
		description = "A cassette labelled 'DOORS - DO NOT ERASE'.",
		stack = 1,
		color = Color3.fromRGB(60, 60, 64),
		icon = "tape",
		important = true,
	},
	CROWBAR = {
		name = "Crowbar",
		description = "Pries boards loose. Heavy.",
		stack = 1,
		color = Color3.fromRGB(110, 40, 36),
		icon = "tool",
	},
	MUSIC_BOX = {
		name = "Music Box",
		description = "It still plays three notes when tilted.",
		stack = 1,
		color = Color3.fromRGB(140, 100, 70),
		icon = "box",
		important = true,
		offering = true,
	},
	DOLL = {
		name = "Cloth Doll",
		description = "Button eyes. One is missing.",
		stack = 1,
		color = Color3.fromRGB(170, 150, 140),
		icon = "doll",
		important = true,
		offering = true,
	},
	CANDLE = {
		name = "Candle",
		description = "Half burnt. The wick is still warm.",
		stack = 1,
		color = Color3.fromRGB(225, 215, 190),
		icon = "candle",
		important = true,
		offering = true,
	},
	WARD = {
		name = "Ward",
		description = "A thread charm. It breaks instead of you. Once.",
		stack = 1,
		color = Color3.fromRGB(200, 200, 210),
		icon = "ward",
	},
	PHOTOGRAPH = {
		name = "Undeveloped Photograph",
		description = "Black. If you stare long enough there is a door in it.",
		stack = 1,
		color = Color3.fromRGB(20, 20, 22),
		icon = "photo",
		secret = true,
	},
	-- Dangerous duplicate: looks like a fuse in the world. Picking it up is a mistake.
	FALSE_FUSE = {
		name = "Fuse",
		description = "It is warm. Fuses are not warm.",
		stack = 1,
		color = Color3.fromRGB(196, 170, 120),
		icon = "fuse",
		hidden = true,
	},
}

function Items.get(id: string)
	return Items.List[id]
end

return Items
