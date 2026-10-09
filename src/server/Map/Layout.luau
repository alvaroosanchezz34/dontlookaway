--[[
	Layout
	The authored floor plan of the Ashgrove Building.

	Each floor is an ASCII grid. One character is one 4x4 stud cell.
		' '  void (no geometry)
		'#'  solid wall
		a-z, 0-9  room cells (room ids are "<floor>_<char>")
		'D'  door            'L'  locked door (key from Rooms[...].lockKey)
		'K'  keypad door     'P'  puzzle closet door
		'H'  boarded hidden passage (crowbar)
		'O'  open archway    'W'  boarded window (exterior wall)
		'E'  main entrance   'X'  final exit shutter

	Floors share a stairwell at the same cells so the vertical stack is coherent.
	The plan was laid out so players can build a mental map: a long east-west
	corridor on every level, the stairwell in the same place, landmarks per wing.
]]

local Layout = {}

Layout.Cell = 4
Layout.LevelHeight = 18
Layout.CeilingHeight = 13
Layout.DoorHeight = 10
Layout.WindowSill = 4
Layout.WindowTop = 10
Layout.Origin = Vector3.new(0, 0, 0)

Layout.Floors = {
	{
		id = "B",
		name = "BASEMENT",
		level = -1,
		y = -18,
		grid = {
			"         ###############################",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #ffffffffffffff#ssss#ddddddddd#",
			"         #######D#########D#######L#####",
			"         #ccccccccccccccccccccccccccccc#",
			"         #ccccccccccccccccccccccccccccc#",
			"         #####D#######D#######H#####D###",
			"         #wwwwwwwwwwwwwwwww#zzzzzz#hhhh#",
			"         #wwwwwwwwwwwwwwwww#zzzzzz#hhhh#",
			"         #wwwwwwwwwwwwwwwww#zzzzzz#hhhh#",
			"         ###P###P###P###P###zzzzzz#hhhh#",
			"         ##111#222#333#444##zzzzzz#hhhh#",
			"         ##111#222#333#444##zzzzzz#hhhh#",
			"         ##111#222#333#444##zzzzzz#hhhh#",
			"         ###############################",
		},
	},
	{
		id = "G",
		name = "GROUND FLOOR",
		level = 0,
		y = 0,
		grid = {
			"###W##W#####W##W################W###W###",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"Waaaaaaaa#bbbbbbbb#mmmmm#ssss#gggggggggW",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"#aaaaaaaa#bbbbbbbb#mmmmm#ssss#ggggggggg#",
			"####D########L#######D####D#######D#####",
			"#cccccccccccccccccccccccccccccccccccccc#",
			"#cccccccccccccccccccccccccccccccccccccc#",
			"###D#####D########OOOO########K#####D###",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyy#",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyy#",
			"Wttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyyW",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyy#",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyy#",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr#qqqqqq#yyyy#",
			"#ttttt#uuuuu#rrrrrrrrrrrrrr########yyyy#",
			"########D####rrrrrrrrrrrrrr#yyyyyyyyyyy#",
			"#kkkkkkkkkkk#rrrrrrrrrrrrrr#yyyyyyyyyyy#",
			"#kkkkkkkkkkk#rrrrrrrrrrrrrrDyyyyyyyyyyy#",
			"#kkkkkkkkkkk#rrrrrrrrrrrrrr#yyyyyyyyyyy#",
			"WkkkkkkkkkkkDrrrrrrrrrrrrrr#yyyyyyyyyyyX",
			"#kkkkkkkkkkk#rrrrrrrrrrrrrr#yyyyyyyyyyyX",
			"#kkkkkkkkkkk#######DD#######yyyyyyyyyyy#",
			"#kkkkkkkkkkk#####eeeeee#####yyyyyyyyyyy#",
			"#kkkkkkkkkkk#####eeeeee#####yyyyyyyyyyy#",
			"####W###W##########EE##########W####W###",
		},
	},
	{
		id = "U",
		name = "UPPER FLOOR",
		level = 1,
		y = 18,
		grid = {
			"###W##W#####W##W#####W##########W###W###",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"Wnnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvvW",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"#nnnnnnnn#oooooooo#ppppp#ssss#vvvvvvvvv#",
			"####D########D#######D####D#######D#####",
			"#cccccccccccccccccccccccccccccccccccccc#",
			"#cccccccccccccccccccccccccccccccccccccc#",
			"######D#########D######D######D#####D###",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"Wiiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxxW",
			"#iiiiiiiiiiiDjjjjjjjjjjjjjj#llllll#xxxx#",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"#iiiiiiiiiii#jjjjjjjjjjjjjj#llllll#xxxx#",
			"####W###W#######W#####W#################",
		},
	},
}

-- Visual styles. Colours are deliberately desaturated; the building is old and damp.
Layout.Styles = {
	corridor = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(178, 170, 152) },
		lower = { Enum.Material.WoodPlanks, Color3.fromRGB(175, 138, 112), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(172, 182, 163) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(215, 215, 206) },
		light = "fluoro",
		lightColor = Color3.fromRGB(214, 230, 222),
	},
	office = {
		floor = { Enum.Material.Carpet, Color3.fromRGB(142, 150, 167) },
		lower = { Enum.Material.Plaster, Color3.fromRGB(189, 177, 156), 1 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(205, 193, 168) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(222, 218, 205) },
		light = "fluoro",
		lightColor = Color3.fromRGB(226, 232, 220),
	},
	reception = {
		floor = { Enum.Material.Marble, Color3.fromRGB(158, 170, 162) },
		lower = { Enum.Material.Wood, Color3.fromRGB(152, 114, 88), 5 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(218, 201, 174) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(229, 219, 201) },
		light = "pendant",
		lightColor = Color3.fromRGB(255, 220, 178),
	},
	restroom = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(174, 183, 180) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(195, 208, 203), 8 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(191, 201, 194) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(205, 213, 209) },
		light = "fluoro",
		lightColor = Color3.fromRGB(210, 236, 236),
	},
	breakroom = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(185, 169, 137) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(203, 184, 148), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(213, 197, 158) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(218, 210, 189) },
		light = "fluoro",
		lightColor = Color3.fromRGB(240, 230, 204),
	},
	industrial = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(180, 180, 176) },
		floorVariant = "DLA_WetConcrete", -- MaterialLibrary.WetConcrete
		lower = { Enum.Material.Concrete, Color3.fromRGB(174, 174, 170), 1 },
		upper = { Enum.Material.Brick, Color3.fromRGB(194, 170, 153) },
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(155, 155, 155) },
		light = "cage",
		lightColor = Color3.fromRGB(255, 214, 160),
	},
	basement = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(158, 158, 154) },
		floorVariant = "DLA_WetConcrete", -- MaterialLibrary.WetConcrete
		lower = { Enum.Material.Concrete, Color3.fromRGB(152, 156, 152), 3 },
		-- painted block wall above a bare concrete dado; the paint is failing
		upper = { Enum.Material.Plaster, Color3.fromRGB(185, 191, 178) },
		upperVariant = "DLA_PeelingPaint", -- MaterialLibrary.PeelingPaint
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(142, 142, 142) },
		light = "cage",
		lightColor = Color3.fromRGB(255, 206, 150),
	},
	archive = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(203, 162, 126) },
		lower = { Enum.Material.Wood, Color3.fromRGB(140, 108, 86), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(197, 180, 155) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(206, 197, 184) },
		light = "bulb",
		lightColor = Color3.fromRGB(255, 210, 160),
	},
	quiet = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(206, 168, 139) },
		lower = { Enum.Material.Wood, Color3.fromRGB(164, 144, 131), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(211, 181, 178) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(216, 200, 195) },
		light = "bulb",
		lightColor = Color3.fromRGB(255, 200, 150),
	},
	gallery = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(189, 151, 123) },
		lower = { Enum.Material.Wood, Color3.fromRGB(127, 102, 88), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(184, 148, 144) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(196, 181, 171) },
		light = "pendant",
		lightColor = Color3.fromRGB(255, 214, 170),
	},
	infirmary = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(184, 193, 190) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(187, 209, 207), 5 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(196, 211, 208) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(212, 220, 216) },
		light = "fluoro",
		lightColor = Color3.fromRGB(214, 240, 236),
	},
	server = {
		floor = { Enum.Material.DiamondPlate, Color3.fromRGB(166, 170, 174) },
		lower = { Enum.Material.Metal, Color3.fromRGB(143, 151, 158), 2 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(178, 185, 192) },
		ceiling = { Enum.Material.Metal, Color3.fromRGB(146, 150, 154) },
		light = "fluoro",
		lightColor = Color3.fromRGB(200, 220, 255),
	},
	stairs = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(167, 167, 163) },
		lower = { Enum.Material.Concrete, Color3.fromRGB(161, 169, 161), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(187, 198, 187) },
		upperVariant = "DLA_PeelingPaint", -- MaterialLibrary.PeelingPaint
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(159, 159, 159) },
		light = "cage",
		lightColor = Color3.fromRGB(230, 240, 226),
	},
	secret = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(46, 38, 32) },
		lower = { Enum.Material.Wood, Color3.fromRGB(40, 32, 28), 13 },
		upper = { Enum.Material.Wood, Color3.fromRGB(40, 32, 28) },
		ceiling = { Enum.Material.Wood, Color3.fromRGB(34, 28, 24) },
		light = "bulb",
		lightColor = Color3.fromRGB(255, 190, 130),
	},
	cold = {
		floor = { Enum.Material.DiamondPlate, Color3.fromRGB(191, 206, 213) },
		lower = { Enum.Material.Metal, Color3.fromRGB(175, 187, 193), 13 },
		upper = { Enum.Material.Metal, Color3.fromRGB(175, 187, 193) },
		ceiling = { Enum.Material.Metal, Color3.fromRGB(165, 176, 183) },
		light = "fluoro",
		lightColor = Color3.fromRGB(200, 226, 255),
	},
}

-- Rooms by "<floor>_<char>". kind drives the furnisher.
Layout.Rooms = {
	-- BASEMENT
	B_f = { name = "BOILER ROOM", kind = "boiler", style = "basement", zone = "BASEMENT" },
	B_s = { name = "STAIRWELL B1", kind = "stairs", style = "stairs", zone = "BASEMENT", number = "B1" },
	B_d = { name = "MAINTENANCE", kind = "maintenance", style = "industrial", zone = "BASEMENT", lockKey = "MAINT_KEY", number = "B-04" },
	B_c = { name = "BASEMENT CORRIDOR", kind = "corridor", style = "basement", zone = "BASEMENT" },
	B_w = { name = "THE CLOSETS", kind = "closets", style = "basement", zone = "BASEMENT", number = "B-09" },
	B_1 = { name = "CLOSET I", kind = "closet", style = "basement", zone = "BASEMENT", closet = 1 },
	B_2 = { name = "CLOSET II", kind = "closet", style = "basement", zone = "BASEMENT", closet = 2 },
	B_3 = { name = "CLOSET III", kind = "closet", style = "basement", zone = "BASEMENT", closet = 3 },
	B_4 = { name = "CLOSET IV", kind = "closet", style = "basement", zone = "BASEMENT", closet = 4 },
	B_z = { name = "ROOM 0", kind = "secret", style = "secret", zone = "BASEMENT", secret = true, noSpawns = true },
	B_h = { name = "COLD STORAGE", kind = "cold", style = "cold", zone = "BASEMENT", number = "B-11" },
	-- GROUND
	G_a = { name = "OFFICE G-01", kind = "office", style = "office", zone = "GROUND", number = "G-01", shrink = true },
	G_b = { name = "OFFICE G-02", kind = "office", style = "office", zone = "GROUND", number = "G-02", lockKey = "OFFICE_KEY" },
	G_m = { name = "MAIL ROOM", kind = "mail", style = "office", zone = "GROUND", number = "G-03" },
	G_s = { name = "STAIRWELL", kind = "stairs", style = "stairs", zone = "GROUND", number = "G" },
	G_g = { name = "STORAGE", kind = "storage", style = "industrial", zone = "GROUND", number = "G-05" },
	G_c = { name = "MAIN CORRIDOR", kind = "corridor", style = "corridor", zone = "GROUND" },
	G_t = { name = "MEN'S RESTROOM", kind = "restroom", style = "restroom", zone = "GROUND" },
	G_u = { name = "WOMEN'S RESTROOM", kind = "restroom", style = "restroom", zone = "GROUND" },
	G_k = { name = "BREAK ROOM", kind = "breakroom", style = "breakroom", zone = "GROUND", number = "G-08" },
	G_r = { name = "RECEPTION", kind = "reception", style = "reception", zone = "GROUND" },
	G_e = { name = "VESTIBULE", kind = "vestibule", style = "reception", zone = "GROUND" },
	G_q = { name = "SECURITY", kind = "security", style = "office", zone = "GROUND", number = "G-07", keypad = true },
	G_y = { name = "LOADING DOCK", kind = "dock", style = "industrial", zone = "GROUND" },
	-- UPPER
	U_n = { name = "ARCHIVE", kind = "archive", style = "archive", zone = "UPPER", number = "1-01" },
	U_o = { name = "CONFERENCE ROOM", kind = "conference", style = "office", zone = "UPPER", number = "1-02" },
	U_p = { name = "THE QUIET ROOM", kind = "quiet", style = "quiet", zone = "UPPER", number = "1-03" },
	U_s = { name = "STAIRWELL 1F", kind = "stairs", style = "stairs", zone = "UPPER", number = "1F" },
	U_v = { name = "PORTRAIT GALLERY", kind = "gallery", style = "gallery", zone = "UPPER", number = "1-05" },
	U_c = { name = "UPPER CORRIDOR", kind = "corridor", style = "corridor", zone = "UPPER" },
	U_i = { name = "INFIRMARY", kind = "infirmary", style = "infirmary", zone = "UPPER", number = "1-06" },
	U_j = { name = "OPEN OFFICE", kind = "openoffice", style = "office", zone = "UPPER", number = "1-07" },
	U_l = { name = "SERVER ROOM", kind = "server", style = "server", zone = "UPPER", number = "1-08" },
	U_x = { name = "UTILITY CLOSET", kind = "utility", style = "industrial", zone = "UPPER", number = "1-09" },
}

-- Stairwell rectangle, identical on every floor (cells, inclusive).
-- Landing rows are on the south side next to the door.
Layout.Stairwell = { x0 = 25, z0 = 1, x1 = 28, z1 = 8, landingRows = 2, midRows = 2 }

-- Reserved void used by environment anomalies. Geometry is pre-built hidden.
Layout.Expansions = {
	-- The basement corridor continues west into the earth.
	CorridorStretch = { floor = "B", x0 = 1, z0 = 10, x1 = 8, z1 = 11, capX = 9 },
	-- The boiler room grows west.
	BoilerExpand = { floor = "B", x0 = 3, z0 = 2, x1 = 8, z1 = 7, capX = 9 },
}

-- Exterior areas.
Layout.Courtyard = { x0 = 8, z0 = 30, x1 = 31, z1 = 40 } -- south of the entrance (cells)
Layout.LoadingYard = { x0 = 40, z0 = 18, x1 = 52, z1 = 32 } -- east of the exit (cells)

Layout.LobbyOrigin = Vector3.new(-320, 0, 40)

function Layout.cellToWorld(floorY: number, x: number, z: number): Vector3
	local c = Layout.Cell
	return Layout.Origin + Vector3.new(x * c + c / 2, floorY, z * c + c / 2)
end

function Layout.getFloor(id: string)
	for _, floor in Layout.Floors do
		if floor.id == id then
			return floor
		end
	end
	return nil
end

function Layout.charAt(floor, x: number, z: number): string
	local row = floor.grid[z + 1]
	if not row then
		return " "
	end
	if x < 0 or x >= #row then
		return " "
	end
	return string.sub(row, x + 1, x + 1)
end

function Layout.isRoomChar(ch: string): boolean
	return string.match(ch, "^[a-z0-9]$") ~= nil
end

return Layout
