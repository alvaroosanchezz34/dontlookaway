--[[
	Cosmetics
	Purely visual items. None of them changes brightness, range, battery, speed or
	anything else that affects survival: every flashlight shares identical stats.

	unlock:
		price      Echoes cost in the shop
		level      level required (free once reached)
		achievement awarded by an achievement
		pass       requires a game pass key from GameConfig.GamePasses
		default    owned by everyone
]]

local Cosmetics = {}

Cosmetics.Categories = { "FLASHLIGHT", "BEAM", "GLOVES", "BADGE", "TRAIL", "EMOTE", "TITLE", "UI" }

Cosmetics.CategoryNames = {
	FLASHLIGHT = "FLASHLIGHT SKINS",
	BEAM = "LIGHT EFFECTS",
	GLOVES = "GLOVES",
	BADGE = "BADGES",
	TRAIL = "LOBBY TRAILS",
	EMOTE = "EMOTES",
	TITLE = "TITLES",
	UI = "INTERFACE",
}

Cosmetics.List = {
	-- Flashlights: light tint + body colour. Same brightness and range for all.
	{ id = "FL_STANDARD", category = "FLASHLIGHT", name = "Standard Issue", default = true, light = Color3.fromRGB(255, 244, 228), body = Color3.fromRGB(40, 40, 42) },
	{ id = "FL_TUNGSTEN", category = "FLASHLIGHT", name = "Tungsten", price = 150, light = Color3.fromRGB(255, 214, 160), body = Color3.fromRGB(70, 52, 38) },
	{ id = "FL_SURGICAL", category = "FLASHLIGHT", name = "Surgical", price = 250, light = Color3.fromRGB(236, 246, 255), body = Color3.fromRGB(200, 204, 210) },
	{ id = "FL_SODIUM", category = "FLASHLIGHT", name = "Sodium Lamp", level = 8, light = Color3.fromRGB(255, 196, 130), body = Color3.fromRGB(90, 70, 30) },
	{ id = "FL_MOON", category = "FLASHLIGHT", name = "Moonlight", price = 400, light = Color3.fromRGB(214, 226, 255), body = Color3.fromRGB(30, 34, 46) },
	{ id = "FL_BRASS", category = "FLASHLIGHT", name = "Old Brass", level = 15, light = Color3.fromRGB(255, 226, 190), body = Color3.fromRGB(150, 116, 60) },
	{ id = "FL_ARCHIVE", category = "FLASHLIGHT", name = "Archivist", achievement = "JOURNAL_25", light = Color3.fromRGB(240, 236, 220), body = Color3.fromRGB(110, 90, 70) },
	{ id = "FL_SILVER", category = "FLASHLIGHT", name = "Silver Lantern", pass = "VIP", light = Color3.fromRGB(246, 246, 255), body = Color3.fromRGB(190, 190, 196) },
	{ id = "FL_NOIR", category = "FLASHLIGHT", name = "Noir", pass = "FlashlightCollection", light = Color3.fromRGB(250, 250, 250), body = Color3.fromRGB(12, 12, 12) },
	{ id = "FL_ROSE", category = "FLASHLIGHT", name = "Faded Rose", pass = "FlashlightCollection", light = Color3.fromRGB(255, 226, 226), body = Color3.fromRGB(120, 80, 84) },

	-- Beam effects
	{ id = "BM_CLEAN", category = "BEAM", name = "Clean Beam", default = true, effect = "clean" },
	{ id = "BM_DUST", category = "BEAM", name = "Dust Motes", price = 200, effect = "dust" },
	{ id = "BM_HAZE", category = "BEAM", name = "Haze", level = 12, effect = "haze" },
	{ id = "BM_FLICKER", category = "BEAM", name = "Old Bulb", price = 300, effect = "flicker" },

	-- Trails (shown only in the lobby, never during a round)
	{ id = "TR_NONE", category = "TRAIL", name = "None", default = true, effect = "none" },
	{ id = "TR_ASH", category = "TRAIL", name = "Ash", price = 250, effect = "ash", color = Color3.fromRGB(120, 120, 120) },
	{ id = "TR_STATIC", category = "TRAIL", name = "Static", price = 350, effect = "static", color = Color3.fromRGB(220, 220, 220) },
	{ id = "TR_EMBER", category = "TRAIL", name = "Ember", level = 20, effect = "ember", color = Color3.fromRGB(255, 150, 90) },
	{ id = "TR_VOID", category = "TRAIL", name = "Void", pass = "VIP", effect = "void", color = Color3.fromRGB(20, 20, 24) },

	-- Emotes (procedural animations)
	{ id = "EM_WAVE", category = "EMOTE", name = "Wave", default = true, emote = "wave" },
	{ id = "EM_POINT", category = "EMOTE", name = "Point", default = true, emote = "point" },
	{ id = "EM_SHRUG", category = "EMOTE", name = "Shrug", price = 100, emote = "shrug" },
	{ id = "EM_SALUTE", category = "EMOTE", name = "Salute", price = 150, emote = "salute" },
	{ id = "EM_LOOK", category = "EMOTE", name = "Look Around", level = 5, emote = "look" },
	{ id = "EM_HUSH", category = "EMOTE", name = "Hush", pass = "EmotePack", emote = "hush" },
	{ id = "EM_BOW", category = "EMOTE", name = "Bow", pass = "EmotePack", emote = "bow" },

	-- Titles
	{ id = "TI_VISITOR", category = "TITLE", name = "Visitor", default = true },
	{ id = "TI_WANDERER", category = "TITLE", name = "Wanderer", level = 3 },
	{ id = "TI_NIGHTSHIFT", category = "TITLE", name = "Night Shift", level = 10 },
	{ id = "TI_WITNESS", category = "TITLE", name = "Witness", achievement = "THE_WITNESS" },
	{ id = "TI_UNBLINKING", category = "TITLE", name = "Unblinking", achievement = "HARD_ESCAPE" },
	{ id = "TI_ARCHIVIST", category = "TITLE", name = "Archivist", achievement = "FOUND_150" },
	{ id = "TI_SURVIVOR", category = "TITLE", name = "Survivor", achievement = "ESCAPED" },
	{ id = "TI_LONER", category = "TITLE", name = "Lone Light", achievement = "SURVIVED_ALONE" },
	{ id = "TI_CARETAKER", category = "TITLE", name = "Caretaker", achievement = "PUZZLE_MASTER" },
	{ id = "TI_TENANT", category = "TITLE", name = "Tenant", price = 500 },
	{ id = "TI_UNSEEN", category = "TITLE", name = "Unseen", level = 25 },
	{ id = "TI_VIP", category = "TITLE", name = "Patron", pass = "VIP" },

	-- Gloves (your hands in first person, and your character's hands)
	{ id = "GL_BARE", category = "GLOVES", name = "Bare Hands", default = true, color = nil },
	{ id = "GL_WORK", category = "GLOVES", name = "Work Gloves", price = 200, color = Color3.fromRGB(150, 120, 80) },
	{ id = "GL_LATEX", category = "GLOVES", name = "Latex", price = 300, color = Color3.fromRGB(200, 214, 220) },
	{ id = "GL_LEATHER", category = "GLOVES", name = "Black Leather", level = 10, color = Color3.fromRGB(26, 24, 24) },
	{ id = "GL_RUBBER", category = "GLOVES", name = "Rubber Gloves", price = 450, color = Color3.fromRGB(190, 160, 50) },
	{ id = "GL_FIELD", category = "GLOVES", name = "Field Investigator", achievement = "DAILY_DEVOTION", color = Color3.fromRGB(70, 80, 66) },

	-- Badges (a small mark beside your name)
	{ id = "BD_NONE", category = "BADGE", name = "No Badge", default = true, glyph = "" },
	{ id = "BD_EYE", category = "BADGE", name = "Open Eye", price = 250, glyph = "◉" },
	{ id = "BD_KEY", category = "BADGE", name = "Old Key", level = 6, glyph = "⚿" },
	{ id = "BD_MOON", category = "BADGE", name = "Crescent", price = 400, glyph = "☾" },
	{ id = "BD_STAR", category = "BADGE", name = "Unblinking Star", achievement = "HARD_ESCAPE", glyph = "✦" },
	{ id = "BD_SKULL", category = "BADGE", name = "Nightmare", achievement = "NIGHTMARE", glyph = "✕" },

	-- Titles earned through the new milestones
	{ id = "TI_INVESTIGATOR", category = "TITLE", name = "Field Investigator", achievement = "DAILY_DEVOTION" },
	{ id = "TI_LIGHTKEEPER", category = "TITLE", name = "Lightkeeper", achievement = "POWER_OUTAGE" },
	{ id = "TI_EYES", category = "TITLE", name = "Eyes Open", achievement = "DONT_BLINK" },
	{ id = "TI_NIGHTMARE", category = "TITLE", name = "Nightmare", achievement = "NIGHTMARE" },

	-- Interface accents
	{ id = "UI_BONE", category = "UI", name = "Bone", default = true, accent = Color3.fromRGB(232, 228, 220) },
	{ id = "UI_ASH", category = "UI", name = "Ash", price = 120, accent = Color3.fromRGB(170, 172, 176) },
	{ id = "UI_SEPIA", category = "UI", name = "Sepia", price = 180, accent = Color3.fromRGB(214, 192, 158) },
	{ id = "UI_PHOSPHOR", category = "UI", name = "Phosphor", level = 18, accent = Color3.fromRGB(176, 214, 186) },
	{ id = "UI_FROST", category = "UI", name = "Frost", pass = "VIP", accent = Color3.fromRGB(196, 214, 236) },
}

Cosmetics.ById = {}
for _, c in Cosmetics.List do
	Cosmetics.ById[c.id] = c
end

Cosmetics.Defaults = {
	FLASHLIGHT = "FL_STANDARD",
	BEAM = "BM_CLEAN",
	GLOVES = "GL_BARE",
	BADGE = "BD_NONE",
	TRAIL = "TR_NONE",
	TITLE = "TI_VISITOR",
	UI = "UI_BONE",
}

function Cosmetics.get(id: string)
	return Cosmetics.ById[id]
end

return Cosmetics
