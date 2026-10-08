--[[
	Lobby
	"The Field Office": the investigators' research base across the street from
	the building, where players gather between nights. Built once at server
	start, far away from the building. Every station is a physical place:

	  NORTH  the DEPLOYMENT door into the building, with the ready line
	  WEST   RECORDS: the anomaly journal terminal, the personal record terminal
	         and the leaderboard wall
	  EAST   SUPPLY: the supply counter, the wardrobe and the equipment lockers
	         (loadout)
	  SOUTH  the challenge board, the news board and the orientation terminal
	  MIDDLE the briefing table with the building's floor plan
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Layout)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local M = Enum.Material

local Lobby = {}

local TEXT = Color3.fromRGB(220, 214, 200)
local DIM = Color3.fromRGB(150, 146, 136)
local ACCENT = Color3.fromRGB(140, 186, 214)

-- A terminal on a stand. `kind` is the station the server opens (see LobbyService).
local function kiosk(folder: Instance, name: string, label: string, sub: string, kind: string, cf: CFrame)
	local m = Build.model(folder, name, cf)
	Build.part(m, "Stand", Vector3.new(3, 4, 1.6), cf * CFrame.new(0, 2, 0), Color3.fromRGB(40, 38, 36), M.Metal)
	Build.detail(m, "Base", Vector3.new(3.4, 0.2, 2), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(26, 26, 26), M.Metal)
	local top = Build.part(m, "Screen", Vector3.new(2.6, 1.8, 0.2), cf * CFrame.new(0, 5, -0.2) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(20, 24, 26), M.SmoothPlastic)
	Build.detail(m, "Neck", Vector3.new(0.4, 0.9, 0.3), cf * CFrame.new(0, 4.3, 0.1), Color3.fromRGB(30, 30, 30), M.Metal)
	local gui = Build.surfaceGui(top, Enum.NormalId.Front, 60)
	gui.LightInfluence = 0.15
	gui.Brightness = 1.4
	Build.text(gui, { Size = UDim2.fromScale(0.9, 0.42), Position = UDim2.fromScale(0.05, 0.16), Text = label, Font = Enum.Font.GothamBold, TextColor3 = TEXT })
	Build.text(gui, { Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.62), Text = sub, Font = Enum.Font.Gotham, TextColor3 = ACCENT })
	local glow = Build.light(top, "SurfaceLight", { Brightness = 0.6, Range = 7, Angle = 80, Face = Enum.NormalId.Front, Color = Color3.fromRGB(170, 200, 220), Shadows = false })
	glow.Name = "ScreenGlow"
	top:AddTag("Interactable")
	top:SetAttribute("InteractKind", "Kiosk")
	top:SetAttribute("Kiosk", kind)
	top:SetAttribute("Prompt", "Use the " .. string.lower(label) .. " terminal")
	return m
end

-- A wall-mounted board with a title and `rows` text lines (filled by the server).
local function board(folder: Instance, name: string, title: string, rows: number, wallCf: CFrame, width: number, height: number): (Part, { TextLabel })
	local m = Build.model(folder, name, wallCf)
	Build.detail(m, "Frame", Vector3.new(width + 0.4, height + 0.4, 0.2), wallCf * CFrame.new(0, 0, -0.1), Color3.fromRGB(34, 28, 24), M.Wood)
	local face = Build.part(m, "Face", Vector3.new(width, height, 0.1), wallCf * CFrame.new(0, 0, -0.22), Color3.fromRGB(22, 24, 24), M.SmoothPlastic, { CanCollide = false })
	local gui = Build.surfaceGui(face, Enum.NormalId.Front, 40)
	gui.Name = "BoardGui"
	gui.LightInfluence = 0.25
	gui.Brightness = 1.2
	Build.text(gui, { Name = "Title", Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.04), Text = title, Font = Enum.Font.GothamBold, TextColor3 = TEXT })
	Build.frame(gui, { Size = UDim2.new(0.9, 0, 0, 2), Position = UDim2.fromScale(0.05, 0.17), BackgroundColor3 = DIM, BackgroundTransparency = 0.4 })
	local labels = {}
	local rowH = 0.76 / rows
	for i = 1, rows do
		local label = Build.text(gui, {
			Name = "Row" .. i,
			Size = UDim2.fromScale(0.9, rowH * 0.86),
			Position = UDim2.fromScale(0.05, 0.2 + (i - 1) * rowH),
			Text = "",
			Font = Enum.Font.Code,
			TextColor3 = if i == 1 then TEXT else DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		table.insert(labels, label)
	end
	return face, labels
end

--[[
	The evidence wall: one pinned card per chapter of the story (Catalog/Lore).
	Built hidden; each client reveals the cards its own player has reached
	(LobbyController), so the Field Office slowly fills in as you learn more.
]]
local EVIDENCE = {
	{ "PROJECT CHARTER", "ashgrove observation project\n- one year -" },
	{ "INCIDENT 14", "clock reads 3:40\nno batteries" },
	{ "FLOOR PLAN", "basement corridor\nlonger???" },
	{ "SUBJECT O-01", "2.9 m\nmoves only\nbetween looks" },
	{ "ROSTER", "active 6\nunaccounted 5" },
	{ "SIGN-OUT SHEET", "6 in. 6 out.\n7 signatures" },
	{ "VALE", "\"we were never\nthe observers\"" },
	{ "THE WITNESS", "count the people\ncount again" },
}

local function evidenceWall(folder: Instance, wallCf: CFrame)
	local m = Build.model(folder, "EvidenceWall", wallCf)
	Build.detail(m, "Cork", Vector3.new(9, 3.4, 0.15), wallCf * CFrame.new(0, 0, -0.08), Color3.fromRGB(118, 92, 64), M.Fabric)
	for i, card in EVIDENCE do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local cf = wallCf * CFrame.new(-3.3 + col * 2.2, 0.75 - row * 1.55, -0.2) * CFrame.Angles(0, 0, math.rad((i * 37) % 9 - 4))
		local paper = Build.part(m, "LoreCard", Vector3.new(1.8, 1.25, 0.03), cf, Color3.fromRGB(226, 218, 196), M.SmoothPlastic, { CanCollide = false, CanQuery = false, Transparency = 1 })
		paper:SetAttribute("Chapter", i)
		paper:AddTag("LoreCard")
		local gui = Build.surfaceGui(paper, Enum.NormalId.Front, 60)
		gui.Enabled = false
		Build.text(gui, { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.06), Text = card[1], Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(40, 34, 30) })
		Build.text(gui, { Size = UDim2.fromScale(0.9, 0.56), Position = UDim2.fromScale(0.05, 0.38), Text = card[2], Font = Enum.Font.SpecialElite, TextColor3 = Color3.fromRGB(60, 50, 44) })
		local pin = Build.ball(m, "Pin", 0.14, cf * CFrame.new(0, 0.5, -0.05), Color3.fromRGB(160, 30, 30), M.SmoothPlastic, { CanCollide = false, CanQuery = false, Transparency = 1 })
		pin:SetAttribute("Chapter", i)
		pin:AddTag("LoreCard")
	end
	return m
end

local function pendant(folder: Instance, at: Vector3, range: number, brightness: number)
	local bulb = Build.ball(folder, "Bulb", 0.7, CFrame.new(at), Color3.fromRGB(255, 214, 160), M.Neon, { CanCollide = false })
	Build.detail(folder, "Shade", Vector3.new(2.2, 0.5, 2.2), CFrame.new(at + Vector3.new(0, 0.45, 0)), Color3.fromRGB(36, 40, 38), M.Metal)
	Build.detail(folder, "Cord", Vector3.new(0.06, 1.6, 0.06), CFrame.new(at + Vector3.new(0, 1.5, 0)), Color3.new(), M.Rubber)
	local l = Build.light(bulb, "PointLight", { Brightness = brightness, Range = range, Color = Color3.fromRGB(255, 204, 156), Shadows = true })
	l:AddTag("LobbyLamp")
	return l
end

function Lobby.build(parent: Instance)
	local rng = SeededRandom.new(1994, "lobby")
	local O = Layout.Origin + Layout.LobbyOrigin
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local W, D, H = 64, 46, 13
	local floorCol = Color3.fromRGB(64, 62, 58)
	local wallCol = Color3.fromRGB(96, 94, 86)
	Build.part(folder, "Floor", Vector3.new(W, 1, D), CFrame.new(O + Vector3.new(0, -0.5, 0)), floorCol, M.Concrete)
	Build.part(folder, "Ceiling", Vector3.new(W, 1, D), CFrame.new(O + Vector3.new(0, H + 0.5, 0)), Color3.fromRGB(70, 68, 64), M.Plaster)
	local function wall(name, size, pos)
		Build.part(folder, name, size, CFrame.new(O + pos), wallCol, M.Plaster)
	end
	wall("WallN", Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, -D / 2 - 0.5))
	wall("WallS", Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, D / 2 + 0.5))
	wall("WallW", Vector3.new(1, H, D), Vector3.new(-W / 2 - 0.5, H / 2, 0))
	wall("WallE", Vector3.new(1, H, D), Vector3.new(W / 2 + 0.5, H / 2, 0))
	-- painted lower walls and a rubber floor runner through the middle
	for _, side in { { Vector3.new(0, 1.75, -D / 2 + 0.1), Vector3.new(W, 3.5, 0.2) }, { Vector3.new(0, 1.75, D / 2 - 0.1), Vector3.new(W, 3.5, 0.2) }, { Vector3.new(-W / 2 + 0.1, 1.75, 0), Vector3.new(0.2, 3.5, D) }, { Vector3.new(W / 2 - 0.1, 1.75, 0), Vector3.new(0.2, 3.5, D) } } do
		Build.part(folder, "Wainscot", side[2], CFrame.new(O + side[1]), Color3.fromRGB(58, 66, 64), M.SmoothPlastic)
	end
	Build.detail(folder, "Runner", Vector3.new(8, 0.04, D - 6), CFrame.new(O + Vector3.new(0, 0.02, 1)), Color3.fromRGB(40, 42, 40), M.Rubber)

	-- NORTH: deployment door into the building and the ready line
	local doorPos = O + Vector3.new(0, 0, -D / 2 + 0.25)
	local doorCF = CFrame.lookAt(doorPos, doorPos + Vector3.new(0, 0, 1))
	Build.part(folder, "BuildingDoor", Vector3.new(6, 10, 0.4), doorCF * CFrame.new(0, 5, 0), Color3.fromRGB(46, 50, 50), M.Metal)
	Build.part(folder, "DoorFrame", Vector3.new(7, 10.8, 0.3), doorCF * CFrame.new(0, 5.4, 0.15), Color3.fromRGB(30, 30, 30), M.Metal)
	Build.detail(folder, "PushBar", Vector3.new(4.2, 0.25, 0.25), doorCF * CFrame.new(0, 3.6, -0.35), Color3.fromRGB(140, 140, 136), M.Metal)
	local lampPart = Build.part(folder, "DoorLamp", Vector3.new(1.2, 0.4, 0.6), doorCF * CFrame.new(0, 11.2, -0.4), Color3.fromRGB(255, 220, 170), M.Neon, { CanCollide = false })
	Build.light(lampPart, "SpotLight", { Brightness = 1.8, Range = 20, Angle = 70, Face = Enum.NormalId.Bottom, Color = Color3.fromRGB(255, 210, 160), Shadows = true })
	Props.sign(folder, doorCF * CFrame.new(0, 8.9, -0.25), "DEPLOYMENT  ·  " .. GameConfig.BuildingName, 9, 0.9, "brass")
	-- hazard-striped ready line in front of the door
	for i = -3, 3 do
		Build.detail(folder, "ReadyLine", Vector3.new(1.6, 0.05, 0.8), CFrame.new(O + Vector3.new(i * 2, 0.03, -D / 2 + 5)), if i % 2 == 0 then Color3.fromRGB(200, 170, 60) else Color3.fromRGB(26, 26, 26), M.SmoothPlastic)
	end
	Props.sign(folder, CFrame.lookAt(O + Vector3.new(-9, 6.5, -D / 2 + 0.05), O + Vector3.new(-9, 6.5, 0)), "READY UP AT THE DOOR", 5, 0.7)
	Props.sign(folder, CFrame.lookAt(O + Vector3.new(9, 6.5, -D / 2 + 0.05), O + Vector3.new(9, 6.5, 0)), "NOBODY GOES IN ALONE", 5, 0.7)
	Props.bench(folder, CFrame.lookAt(O + Vector3.new(-13, 0, -D / 2 + 1.6), O + Vector3.new(-13, 0, 0)), rng)
	Props.bench(folder, CFrame.lookAt(O + Vector3.new(13, 0, -D / 2 + 1.6), O + Vector3.new(13, 0, 0)), rng)
	Props.clock(folder, CFrame.lookAt(O + Vector3.new(-20, 8.5, -D / 2 + 0.05), O + Vector3.new(-20, 8.5, 0)), rng)
	Props.fireExtinguisher(folder, CFrame.lookAt(O + Vector3.new(20, 0, -D / 2 + 0.62), O + Vector3.new(20, 0, 0)))

	-- WEST: records
	local westX = -W / 2
	Props.sign(folder, CFrame.lookAt(O + Vector3.new(westX + 0.05, 9.5, -4), O + Vector3.new(0, 9.5, -4)), "RECORDS", 5, 0.9, "brass")
	kiosk(folder, "JournalKiosk", "JOURNAL", "anomalies catalogued", "JOURNAL", CFrame.lookAt(O + Vector3.new(westX + 3, 0, -10), O + Vector3.new(0, 0, -10)))
	kiosk(folder, "RecordKiosk", "RECORD", "stats & achievements", "RECORD", CFrame.lookAt(O + Vector3.new(westX + 3, 0, -3), O + Vector3.new(0, 0, -3)))
	kiosk(folder, "ArchiveKiosk", "ARCHIVE", "project files", "ARCHIVE", CFrame.lookAt(O + Vector3.new(westX + 3, 0, -16.5), O + Vector3.new(0, 0, -16.5)))
	evidenceWall(folder, CFrame.lookAt(O + Vector3.new(westX + 0.05, 7.4, -13.5), O + Vector3.new(0, 7.4, -13.5)))
	local leaderFace, leaderRows = board(folder, "Leaderboard", "MOST ESCAPES", 11, CFrame.lookAt(O + Vector3.new(westX + 0.05, 6.6, 8), O + Vector3.new(0, 6.6, 8)), 10, 7)
	for i = 0, 2 do
		Props.filingCabinet(folder, CFrame.lookAt(O + Vector3.new(westX + 1.3, 0, 15 + i * 2), O + Vector3.new(0, 0, 15 + i * 2)), rng)
	end
	Props.plant(folder, CFrame.new(O + Vector3.new(westX + 2, 0, -D / 2 + 2)), rng, true)

	-- EAST: supply
	local eastX = W / 2
	Props.sign(folder, CFrame.lookAt(O + Vector3.new(eastX - 0.05, 9.5, -8), O + Vector3.new(0, 9.5, -8)), "SUPPLY", 5, 0.9, "brass")
	Props.counter(folder, CFrame.lookAt(O + Vector3.new(eastX - 1.3, 0, -13), O + Vector3.new(0, 0, -13)), rng, 10)
	Props.metalShelf(folder, CFrame.lookAt(O + Vector3.new(eastX - 1.25, 0, -20.4), O + Vector3.new(0, 0, -20.4)), rng, { width = 4 })
	kiosk(folder, "ShopKiosk", "SUPPLY", "equipment & upgrades", "SUPPLY", CFrame.lookAt(O + Vector3.new(eastX - 4.5, 0, -3), O + Vector3.new(0, 0, -3)))
	kiosk(folder, "WardrobeKiosk", "WARDROBE", "cosmetics", "COSMETICS", CFrame.lookAt(O + Vector3.new(eastX - 4.5, 0, 3), O + Vector3.new(0, 0, 3)))
	for i = 0, 4 do
		Props.locker(folder, CFrame.lookAt(O + Vector3.new(eastX - 1.1, 0, 10 + i * 2.1), O + Vector3.new(0, 0, 10 + i * 2.1)), rng)
	end
	kiosk(folder, "LoadoutKiosk", "LOADOUT", "pack your tool belt", "LOADOUT", CFrame.lookAt(O + Vector3.new(eastX - 5, 0, 14), O + Vector3.new(0, 0, 14)))

	-- SOUTH: windows, challenge board, news, orientation
	local southZ = D / 2
	for _, x in { -12, 0, 12 } do
		local wp = O + Vector3.new(x, 6.5, southZ)
		Build.part(folder, "Window", Vector3.new(5, 4, 0.2), CFrame.new(wp + Vector3.new(0, 0, -0.1)), Color3.fromRGB(30, 38, 46), M.Glass, { Transparency = 0.2, Reflectance = 0.15 })
		Build.detail(folder, "WindowFrame", Vector3.new(5.6, 4.6, 0.3), CFrame.new(wp + Vector3.new(0, 0, 0.05)), Color3.fromRGB(40, 32, 26), M.Wood)
		local flash = Build.part(folder, "Lightning", Vector3.new(0.2, 0.2, 0.2), CFrame.new(wp + Vector3.new(0, 4, 6)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local l = Build.light(flash, "PointLight", { Brightness = 0, Range = 24, Color = Color3.fromRGB(200, 214, 255), Shadows = false })
		l:AddTag("Lightning")
	end
	local challengeFace, challengeRows = board(folder, "ChallengeBoard", "TONIGHT'S ORDERS", 7, CFrame.lookAt(O + Vector3.new(24, 6.4, southZ - 0.05), O + Vector3.new(24, 6.4, 0)), 9, 5.5)
	challengeFace:AddTag("Interactable")
	challengeFace:SetAttribute("InteractKind", "Kiosk")
	challengeFace:SetAttribute("Kiosk", "CHALLENGES")
	challengeFace:SetAttribute("Prompt", "Read the challenges")
	local newsFace, newsRows = board(folder, "NewsBoard", "FIELD BULLETIN", 7, CFrame.lookAt(O + Vector3.new(-24, 6.4, southZ - 0.05), O + Vector3.new(-24, 6.4, 0)), 9, 5.5)
	for i, line in GameConfig.News or {} do
		if newsRows[i] then
			newsRows[i].Text = line
		end
	end
	kiosk(folder, "OrientationKiosk", "ORIENTATION", "how to survive a night", "TUTORIAL", CFrame.lookAt(O + Vector3.new(-6, 0, southZ - 2.5), O + Vector3.new(-6, 0, 0)))
	Props.sofa(folder, CFrame.lookAt(O + Vector3.new(-24, 0, southZ - 2), O + Vector3.new(-24, 0, 0)), rng)
	-- the TV with static on a low table
	local tv = Props.table(folder, CFrame.new(O + Vector3.new(16, 0, southZ - 5)), rng, 4, 2.4)
	local crt = Props.crt(tv, CFrame.new(O + Vector3.new(16, 3.12, southZ - 5)) * CFrame.Angles(0, math.rad(-150), 0), rng)
	local screen = crt:FindFirstChild("Screen") :: BasePart
	screen.Material = M.Neon
	screen.Color = Color3.fromRGB(70, 74, 78)
	screen:AddTag("StaticScreen")
	Props.plant(folder, CFrame.new(O + Vector3.new(W / 2 - 2, 0, southZ - 2)), rng, true)
	Props.waterCooler(folder, CFrame.lookAt(O + Vector3.new(6, 0, southZ - 1.2), O + Vector3.new(6, 0, 0)), rng)

	-- MIDDLE: the briefing table with the floor plan
	local tableCF = CFrame.new(O + Vector3.new(0, 0, 2))
	local briefing = Props.table(folder, tableCF, rng, 10, 5)
	briefing.Name = "BriefingTable"
	local plan = Build.part(folder, "FloorPlan", Vector3.new(8.4, 0.05, 3.8), tableCF * CFrame.new(0, 3.16, 0), Color3.fromRGB(40, 66, 96), M.SmoothPlastic, { CanCollide = false })
	local planGui = Build.surfaceGui(plan, Enum.NormalId.Top, 30)
	planGui.LightInfluence = 0.6
	-- a stylised plan: corridors and rooms in thin lines
	local lines = {
		{ 0.05, 0.45, 0.9, 0.06 }, -- main corridor
		{ 0.47, 0.08, 0.06, 0.84 }, -- cross corridor
		{ 0.08, 0.1, 0.3, 0.3 },
		{ 0.62, 0.1, 0.3, 0.3 },
		{ 0.08, 0.58, 0.3, 0.32 },
		{ 0.62, 0.58, 0.3, 0.32 },
	}
	for _, l in lines do
		local f = Build.frame(planGui, { Size = UDim2.fromScale(l[3], l[4]), Position = UDim2.fromScale(l[1], l[2]), BackgroundTransparency = 1 })
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 220, 240)
		stroke.Thickness = 2
		stroke.Transparency = 0.2
		stroke.Parent = f
	end
	Build.text(planGui, { Size = UDim2.fromScale(0.5, 0.1), Position = UDim2.fromScale(0.25, 0.88), Text = GameConfig.BuildingName .. "  ·  FLOOR PLAN (INCOMPLETE)", Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(220, 230, 240) })
	for _, side in { -1, 1 } do
		for i = -1, 1 do
			Props.woodChair(folder, CFrame.lookAt(O + Vector3.new(i * 3, 0, 2 + side * 4), O + Vector3.new(i * 3, 0, 2)), rng)
		end
	end
	Props.paperStack(folder, tableCF * CFrame.new(-4.3, 3.12, 1.6), rng)
	Props.deskLamp(folder, tableCF * CFrame.new(4.2, 3.12, -1.6) * CFrame.Angles(0, math.rad(200), 0), rng)

	-- lighting: one pendant per zone
	local mainLight = pendant(folder, O + Vector3.new(0, H - 2.4, 2), 30, 1.4)
	pendant(folder, O + Vector3.new(-W / 2 + 8, H - 2.6, -2), 24, 1.1)
	pendant(folder, O + Vector3.new(W / 2 - 8, H - 2.6, -2), 24, 1.1)
	pendant(folder, O + Vector3.new(0, H - 2.6, -D / 2 + 6), 22, 0.9)
	pendant(folder, O + Vector3.new(0, H - 2.6, D / 2 - 6), 22, 0.9)

	-- spawn points between the briefing table and the door
	local spawns = {}
	for i = 1, 4 do
		local p = O + Vector3.new(-7.5 + (i - 1) * 5, 3, -8)
		table.insert(spawns, CFrame.lookAt(p, O + Vector3.new(0, 3, -D / 2)))
	end
	-- a camera shot used behind lobby UI
	local camera = CFrame.lookAt(O + Vector3.new(22, 8, 16), O + Vector3.new(-4, 4, -8))
	folder.Parent = parent
	return {
		Root = folder,
		Spawns = spawns,
		Camera = camera,
		Center = O,
		Size = Vector3.new(W, H, D),
		MainLight = mainLight,
		Boards = {
			Leaderboard = { face = leaderFace, rows = leaderRows },
			Challenges = { face = challengeFace, rows = challengeRows },
			News = { face = newsFace, rows = newsRows },
		},
	}
end

return Lobby
