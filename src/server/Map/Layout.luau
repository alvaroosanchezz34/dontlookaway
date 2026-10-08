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
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(92, 88, 78) },
		lower = { Enum.Material.WoodPlanks, Color3.fromRGB(58, 44, 34), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(104, 110, 98) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(86, 86, 82) },
		light = "fluoro",
		lightColor = Color3.fromRGB(214, 230, 222),
	},
	office = {
		floor = { Enum.Material.Carpet, Color3.fromRGB(62, 66, 74) },
		lower = { Enum.Material.Plaster, Color3.fromRGB(118, 110, 96), 1 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(126, 118, 102) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(96, 94, 88) },
		light = "fluoro",
		lightColor = Color3.fromRGB(226, 232, 220),
	},
	reception = {
		floor = { Enum.Material.Marble, Color3.fromRGB(66, 72, 68) },
		lower = { Enum.Material.Wood, Color3.fromRGB(64, 46, 34), 5 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(122, 112, 96) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(92, 88, 80) },
		light = "pendant",
		lightColor = Color3.fromRGB(255, 220, 178),
	},
	restroom = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(112, 118, 116) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(150, 160, 156), 8 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(116, 122, 118) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(96, 100, 98) },
		light = "fluoro",
		lightColor = Color3.fromRGB(210, 236, 236),
	},
	breakroom = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(110, 100, 80) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(128, 116, 92), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(134, 124, 98) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(98, 94, 84) },
		light = "fluoro",
		lightColor = Color3.fromRGB(240, 230, 204),
	},
	industrial = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(78, 78, 76) },
		floorVariant = "DLA_WetConcrete", -- MaterialLibrary.WetConcrete
		lower = { Enum.Material.Concrete, Color3.fromRGB(84, 84, 82), 1 },
		upper = { Enum.Material.Brick, Color3.fromRGB(88, 76, 68) },
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(64, 64, 64) },
		light = "cage",
		lightColor = Color3.fromRGB(255, 214, 160),
	},
	basement = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(66, 66, 64) },
		floorVariant = "DLA_WetConcrete", -- MaterialLibrary.WetConcrete
		lower = { Enum.Material.Concrete, Color3.fromRGB(58, 60, 58), 3 },
		-- painted block wall above a bare concrete dado; the paint is failing
		upper = { Enum.Material.Plaster, Color3.fromRGB(104, 108, 100) },
		upperVariant = "DLA_PeelingPaint", -- MaterialLibrary.PeelingPaint
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(52, 52, 52) },
		light = "cage",
		lightColor = Color3.fromRGB(255, 206, 150),
	},
	archive = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(70, 54, 40) },
		lower = { Enum.Material.Wood, Color3.fromRGB(54, 40, 30), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(108, 98, 84) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(84, 80, 74) },
		light = "bulb",
		lightColor = Color3.fromRGB(255, 210, 160),
	},
	quiet = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(78, 62, 50) },
		lower = { Enum.Material.Wood, Color3.fromRGB(96, 84, 76), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(122, 104, 102) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(96, 88, 86) },
		light = "bulb",
		lightColor = Color3.fromRGB(255, 200, 150),
	},
	gallery = {
		floor = { Enum.Material.WoodPlanks, Color3.fromRGB(60, 46, 36) },
		lower = { Enum.Material.Wood, Color3.fromRGB(44, 34, 28), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(84, 66, 64) },
		upperVariant = "DLA_Wallpaper", -- MaterialLibrary.Wallpaper
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(70, 64, 60) },
		light = "pendant",
		lightColor = Color3.fromRGB(255, 214, 170),
	},
	infirmary = {
		floor = { Enum.Material.CeramicTiles, Color3.fromRGB(120, 126, 124) },
		lower = { Enum.Material.CeramicTiles, Color3.fromRGB(132, 148, 146), 5 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(130, 140, 138) },
		ceiling = { Enum.Material.Plaster, Color3.fromRGB(104, 108, 106) },
		light = "fluoro",
		lightColor = Color3.fromRGB(214, 240, 236),
	},
	server = {
		floor = { Enum.Material.DiamondPlate, Color3.fromRGB(70, 72, 74) },
		lower = { Enum.Material.Metal, Color3.fromRGB(70, 74, 78), 2 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(96, 100, 104) },
		ceiling = { Enum.Material.Metal, Color3.fromRGB(60, 62, 64) },
		light = "fluoro",
		lightColor = Color3.fromRGB(200, 220, 255),
	},
	stairs = {
		floor = { Enum.Material.Concrete, Color3.fromRGB(80, 80, 78) },
		lower = { Enum.Material.Concrete, Color3.fromRGB(70, 74, 70), 4 },
		upper = { Enum.Material.Plaster, Color3.fromRGB(96, 102, 96) },
		upperVariant = "DLA_PeelingPaint", -- MaterialLibrary.PeelingPaint
		ceiling = { Enum.Material.Concrete, Color3.fromRGB(62, 62, 62) },
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
		floor = { Enum.Material.DiamondPlate, Color3.fromRGB(96, 104, 108) },
		lower = { Enum.Material.Metal, Color3.fromRGB(110, 118, 122), 13 },
		upper = { Enum.Material.Metal, Color3.fromRGB(110, 118, 122) },
		ceiling = { Enum.Material.Metal, Color3.fromRGB(90, 96, 100) },
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
