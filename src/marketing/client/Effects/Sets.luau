--[[
	Sets
	Small film sets built locally, far away from the game's map, for shots that
	need a composed frame (key-art scenes). Everything goes into
	MarketingRuntime and disappears with the scene.

	Sets.doorway()  -> the DON'T LOOK AWAY key art: a grimy wall, a dark doorway,
	                   a door that swings in, a hanging lamp with a light shaft,
	                   a wet floor, and a black room behind the door.
	                   Returns { door = Model, origin = CFrame, eyeAt = Vector3,
	                   lamp = { light = SpotLight, bulb = BasePart, beam = Beam } }
	Materials use the game's own (Concrete / WoodPlanks / Metal), so the
	custom textures apply when they are configured.
]]

local Runtime = require(script.Parent.Parent.Runtime)

local Sets = {}

-- The game's Blender DoorLeaf mesh (ReplicatedStorage.PropMeshTemplates,
-- loaded by the server) dresses a set's door when it is available: same
-- asset as the playable building. The part-built leaf stays for the shape of
-- the door and is hidden; the mesh follows it (Offset).
local function dressLeaf(door: Model, leaf: BasePart)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("PropMeshTemplates")
	local tpl = folder and folder:FindFirstChild("DoorLeaf")
	if not (tpl and tpl:IsA("BasePart")) then
		return
	end
	local mesh = tpl:Clone()
	mesh.Name = "LeafMesh"
	mesh.Size = Vector3.new(leaf.Size.X, leaf.Size.Y, math.max(leaf.Size.Z, 0.3))
	mesh.CFrame = leaf.CFrame
	mesh:SetAttribute("Offset", CFrame.new())
	mesh.Parent = door
	leaf.Transparency = 1
	for _, d in door:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Panel" then
			d.Transparency = 1
		end
	end
end

-- Far above the building and the Field Office: nothing of the game can be seen.
Sets.Origin = CFrame.new(0, 1600, 0)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: any, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in (props or {}) :: { [string]: any } do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

function Sets.doorway(origin: CFrame?)
	local o = origin or Sets.Origin -- floor centre of the doorway; the camera side is +Z
	local m = Instance.new("Model")
	m.Name = "Set_Doorway"
	local black = Color3.new(0, 0, 0)
	local wall = Color3.fromRGB(62, 60, 58)
	local wood = Color3.fromRGB(48, 40, 34)
	local DOOR_W, DOOR_H = 4.4, 9.4
	local ROOM_H = 16

	-- floor: dark, slightly reflective (wet)
	part(m, "Floor", Vector3.new(40, 1, 46), o * CFrame.new(0, -0.5, 8), Color3.fromRGB(26, 26, 28), Enum.Material.Concrete, { Reflectance = 0.06 })
	-- wet sheen: light streaks from the doorway towards the camera
	local sheen = part(m, "WetSheen", Vector3.new(7, 0.05, 18), o * CFrame.new(0, 0.03, 9.5), black, Enum.Material.SmoothPlastic, { Transparency = 1 })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0.2
	sg.Brightness = 1
	sg.PixelsPerStud = 30
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.Parent = sheen
	local random = Random.new(9)
	for i = 1, 26 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(210, 210, 214)
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.fromScale(0.5 + random:NextNumber(-0.32, 0.32), random:NextNumber(0, 0.35))
		f.Size = UDim2.new(0, random:NextInteger(1, 4), random:NextNumber(0.2, 0.65), 0)
		f.Parent = sg
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, random:NextNumber(0.55, 0.8)), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Name = "Streak" .. i
	end

	-- the wall with its doorway
	local side = (20 - DOOR_W / 2) / 2
	part(m, "WallL", Vector3.new(side * 2, ROOM_H, 1), o * CFrame.new(-(DOOR_W / 2 + side), ROOM_H / 2, -0.5), wall, Enum.Material.Concrete)
	part(m, "WallR", Vector3.new(side * 2, ROOM_H, 1), o * CFrame.new(DOOR_W / 2 + side, ROOM_H / 2, -0.5), wall, Enum.Material.Concrete)
	part(m, "WallTop", Vector3.new(DOOR_W, ROOM_H - DOOR_H, 1), o * CFrame.new(0, DOOR_H + (ROOM_H - DOOR_H) / 2, -0.5), wall, Enum.Material.Concrete)
	-- frame trims
	part(m, "TrimL", Vector3.new(0.35, DOOR_H + 0.35, 1.2), o * CFrame.new(-DOOR_W / 2 - 0.17, (DOOR_H + 0.35) / 2, -0.45), wood, Enum.Material.WoodPlanks)
	part(m, "TrimR", Vector3.new(0.35, DOOR_H + 0.35, 1.2), o * CFrame.new(DOOR_W / 2 + 0.17, (DOOR_H + 0.35) / 2, -0.45), wood, Enum.Material.WoodPlanks)
	part(m, "TrimTop", Vector3.new(DOOR_W + 0.7, 0.35, 1.2), o * CFrame.new(0, DOOR_H + 0.17, -0.45), wood, Enum.Material.WoodPlanks)
	-- the room behind: absolute black
	local back = Instance.new("Model")
	back.Name = "Dark"
	part(back, "Back", Vector3.new(14, ROOM_H, 1), o * CFrame.new(0, ROOM_H / 2, -14), black, Enum.Material.SmoothPlastic)
	part(back, "L", Vector3.new(1, ROOM_H, 14), o * CFrame.new(-7, ROOM_H / 2, -7), black, Enum.Material.SmoothPlastic)
	part(back, "R", Vector3.new(1, ROOM_H, 14), o * CFrame.new(7, ROOM_H / 2, -7), black, Enum.Material.SmoothPlastic)
	part(back, "Top", Vector3.new(14, 1, 14), o * CFrame.new(0, ROOM_H, -7), black, Enum.Material.SmoothPlastic)
	part(back, "Floor", Vector3.new(14, 1, 14), o * CFrame.new(0, -0.45, -7), Color3.fromRGB(4, 4, 4), Enum.Material.SmoothPlastic)
	back.Parent = m
	-- the camera's side of the room: closed so no sky shows
	part(m, "Ceiling", Vector3.new(40, 1, 46), o * CFrame.new(0, ROOM_H + 0.5, 8), Color3.fromRGB(14, 14, 15), Enum.Material.Concrete)
	part(m, "SideL", Vector3.new(1, ROOM_H, 46), o * CFrame.new(-20, ROOM_H / 2, 8), Color3.fromRGB(18, 18, 19), Enum.Material.Concrete)
	part(m, "SideR", Vector3.new(1, ROOM_H, 46), o * CFrame.new(20, ROOM_H / 2, 8), Color3.fromRGB(18, 18, 19), Enum.Material.Concrete)
	part(m, "Behind", Vector3.new(40, ROOM_H, 1), o * CFrame.new(0, ROOM_H / 2, 31), Color3.fromRGB(10, 10, 11), Enum.Material.Concrete)

	-- the door: hinged on the right, swings into the dark room
	local door = Instance.new("Model")
	door.Name = "Door"
	local hinge = o * CFrame.new(DOOR_W / 2, DOOR_H / 2, -0.55)
	local leafCf = hinge * CFrame.new(-DOOR_W / 2, 0, 0)
	local leaf = part(door, "Leaf", Vector3.new(DOOR_W - 0.08, DOOR_H - 0.1, 0.22), leafCf, Color3.fromRGB(56, 48, 42), Enum.Material.WoodPlanks)
	for i, spec in { { 0, 2.3, 3.2, 3.6 }, { 0, -2.2, 3.2, 3.8 } } do
		local panel = part(door, "Panel" .. i, Vector3.new(spec[3], spec[4], 0.06), leafCf * CFrame.new(spec[1], spec[2], 0.13), Color3.fromRGB(44, 38, 33), Enum.Material.WoodPlanks)
		panel:SetAttribute("Offset", leafCf:ToObjectSpace(panel.CFrame))
	end
	local knob = part(door, "Knob", Vector3.new(0.28, 0.28, 0.35), leafCf * CFrame.new(-DOOR_W / 2 + 0.45, -0.5, 0.2), Color3.fromRGB(120, 108, 84), Enum.Material.Metal)
	knob:SetAttribute("Offset", leafCf:ToObjectSpace(knob.CFrame))
	door.PrimaryPart = leaf
	door:SetAttribute("ClosedCFrame", leafCf)
	door:SetAttribute("OpenCFrame", hinge * CFrame.Angles(0, math.rad(-78), 0) * CFrame.new(-DOOR_W / 2, 0, 0))
	dressLeaf(door, leaf)
	door.Parent = m

	-- the hanging lamp: cord, metal shade, glowing bulb, hard down-light, dusty shaft
	local lampAt = o * CFrame.new(0, ROOM_H - 2.6, 2.2)
	part(m, "Cord", Vector3.new(0.06, 2.2, 0.06), lampAt * CFrame.new(0, 1.5, 0), Color3.fromRGB(10, 10, 10), Enum.Material.SmoothPlastic)
	part(m, "Shade", Vector3.new(0.7, 2.6, 2.6), lampAt * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(34, 34, 36), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	local bulb = part(m, "Bulb", Vector3.new(0.12, 2.1, 2.1), lampAt * CFrame.new(0, -0.18, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 246, 228), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Left -- the cylinder's -X points down after the roll
	light.Angle = 78
	light.Range = 24
	light.Brightness = 3.2
	light.Color = Color3.fromRGB(255, 240, 222)
	light.Shadows = true
	light.Parent = bulb
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 0.6
	glow.Color = Color3.fromRGB(255, 236, 210)
	glow.Shadows = false
	glow.Parent = bulb
	-- light shaft (a soft beam from the shade to the floor)
	local a0 = Instance.new("Attachment")
	a0.Name = "ShaftTop"
	a0.Position = Vector3.new(0, 0, 0)
	a0.Parent = bulb
	local floorAnchor = part(m, "ShaftFloor", Vector3.new(0.2, 0.2, 0.2), o * CFrame.new(0, 0.2, 2.6), black, Enum.Material.SmoothPlastic, { Transparency = 1 })
	local a1 = Instance.new("Attachment")
	a1.Name = "ShaftBottom"
	a1.Parent = floorAnchor
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2
	beam.Width1 = 11
	beam.FaceCamera = true
	beam.LightEmission = 0.4
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(235, 230, 220))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(0.6, 0.93), NumberSequenceKeypoint.new(1, 1) })
	beam.Segments = 1
	beam.Parent = bulb

	m.Parent = Runtime.folder()
	return {
		model = m,
		door = door,
		origin = o,
		eyeAt = (o * CFrame.new(0, 6.3, -2.6)).Position,
		lamp = { light = light, bulb = bulb, beam = beam, glow = glow },
		camera = function(distance: number, height: number?)
			local eye = (o * CFrame.new(0, height or 5.8, distance)).Position
			return CFrame.lookAt(eye, (o * CFrame.new(0, 6.6, 0)).Position)
		end,
	}
end

--[[
	Sets.room(): a lived-in room for the figure / reflection / sound scenes.
	Plaster walls, wooden floor, one ceiling lamp, and:
	  back wall  (z-): a window onto a faint blue night (something can stand there)
	  left wall  (x-): a mirror
	  right wall (x+): a door onto black
	  furniture: chair, table, cabinet, a picture
	Returns refs and camera helpers. Origin = floor centre, +Z towards the
	camera's usual side.
]]
function Sets.room(origin: CFrame?)
	local o = origin or (Sets.Origin * CFrame.new(120, 0, 0))
	local m = Instance.new("Model")
	m.Name = "Set_Room"
	local plaster = Color3.fromRGB(150, 144, 132)
	local trim = Color3.fromRGB(70, 60, 50)
	local black = Color3.new(0, 0, 0)
	local H = 13
	part(m, "Floor", Vector3.new(26, 1, 26), o * CFrame.new(0, -0.5, 0), Color3.fromRGB(78, 62, 48), Enum.Material.WoodPlanks)
	part(m, "Ceiling", Vector3.new(26, 1, 26), o * CFrame.new(0, H + 0.5, 0), Color3.fromRGB(120, 116, 108), Enum.Material.Plaster)
	-- back wall with a window opening (x -2.5..2.5, y 4..10)
	part(m, "BackL", Vector3.new(10.5, H, 1), o * CFrame.new(-7.75, H / 2, -12.5), plaster, Enum.Material.Plaster)
	part(m, "BackR", Vector3.new(10.5, H, 1), o * CFrame.new(7.75, H / 2, -12.5), plaster, Enum.Material.Plaster)
	part(m, "BackLow", Vector3.new(5, 4, 1), o * CFrame.new(0, 2, -12.5), plaster, Enum.Material.Plaster)
	part(m, "BackHigh", Vector3.new(5, H - 10, 1), o * CFrame.new(0, 10 + (H - 10) / 2, -12.5), plaster, Enum.Material.Plaster)
	part(m, "Sill", Vector3.new(5.6, 0.25, 1.4), o * CFrame.new(0, 3.95, -12.1), trim, Enum.Material.Wood)
	local glass = part(m, "WindowGlass", Vector3.new(5, 6, 0.1), o * CFrame.new(0, 7, -12.6), Color3.fromRGB(40, 48, 58), Enum.Material.Glass, { Transparency = 0.55, Reflectance = 0.15 })
	part(m, "Mullion", Vector3.new(0.16, 6, 0.16), o * CFrame.new(0, 7, -12.5), trim, Enum.Material.Wood)
	-- outside: a faint blue night so a silhouette reads against it
	local night = part(m, "Night", Vector3.new(26, 20, 1), o * CFrame.new(0, 6, -22), Color3.fromRGB(36, 44, 62), Enum.Material.SmoothPlastic)
	local sky = Instance.new("SurfaceLight")
	sky.Face = Enum.NormalId.Front
	sky.Color = Color3.fromRGB(120, 140, 190)
	sky.Brightness = 0.6
	sky.Range = 12
	sky.Parent = night
	night.CFrame = CFrame.lookAt(night.CFrame.Position, (o * CFrame.new(0, 6, 0)).Position)
	part(m, "OutsideGround", Vector3.new(26, 1, 10), o * CFrame.new(0, -0.5, -17.5), Color3.fromRGB(16, 18, 20), Enum.Material.Concrete)
	part(m, "OutsideL", Vector3.new(1, 20, 10), o * CFrame.new(-13, 6, -17.5), black, Enum.Material.SmoothPlastic)
	part(m, "OutsideR", Vector3.new(1, 20, 10), o * CFrame.new(13, 6, -17.5), black, Enum.Material.SmoothPlastic)
	part(m, "OutsideTop", Vector3.new(26, 1, 10), o * CFrame.new(0, 16, -17.5), black, Enum.Material.SmoothPlastic)
	-- left wall with a mirror
	part(m, "Left", Vector3.new(1, H, 26), o * CFrame.new(-12.5, H / 2, 0), plaster, Enum.Material.Plaster)
	local mirrorCf = o * CFrame.new(-11.9, 6.6, 2) * CFrame.Angles(0, math.rad(-90), 0) -- faces +X
	part(m, "MirrorFrame", Vector3.new(3.6, 4.6, 0.12), mirrorCf * CFrame.new(0, 0, 0.06), Color3.fromRGB(58, 56, 54), Enum.Material.Metal)
	local mirror = part(m, "MirrorGlass", Vector3.new(3.2, 4.2, 0.06), mirrorCf * CFrame.new(0, 0, -0.04), Color3.fromRGB(70, 78, 84), Enum.Material.Glass, { Reflectance = 0.55 })
	-- right wall with a door onto black
	part(m, "RightA", Vector3.new(1, H, 11.3), o * CFrame.new(12.5, H / 2, -6.35), plaster, Enum.Material.Plaster)
	part(m, "RightB", Vector3.new(1, H, 9.3), o * CFrame.new(12.5, H / 2, 8.35), plaster, Enum.Material.Plaster)
	part(m, "RightTop", Vector3.new(1, H - 9.4, 4.4), o * CFrame.new(12.5, 9.4 + (H - 9.4) / 2, 1.5), plaster, Enum.Material.Plaster)
	part(m, "DoorVoid", Vector3.new(1, 10, 6), o * CFrame.new(16, 5, 1.5), black, Enum.Material.SmoothPlastic)
	local door = Instance.new("Model")
	door.Name = "Door"
	local hinge = o * CFrame.new(12.55, 4.7, -0.7) -- hinge at the back edge of the opening
	local leafCf = hinge * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), 0)
	local leaf = part(door, "Leaf", Vector3.new(4.32, 9.3, 0.2), leafCf, Color3.fromRGB(62, 52, 44), Enum.Material.WoodPlanks)
	local knob = part(door, "Knob", Vector3.new(0.3, 0.3, 0.3), leafCf * CFrame.new(1.7, -0.4, 0.2), Color3.fromRGB(150, 130, 90), Enum.Material.Metal)
	knob:SetAttribute("Offset", leafCf:ToObjectSpace(knob.CFrame))
	door.PrimaryPart = leaf
	door:SetAttribute("ClosedCFrame", leafCf)
	door:SetAttribute("OpenCFrame", hinge * CFrame.Angles(0, math.rad(80), 0) * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.rad(90), 0))
	dressLeaf(door, leaf)
	door.Parent = m
	-- front wall (behind the usual camera)
	part(m, "Front", Vector3.new(26, H, 1), o * CFrame.new(0, H / 2, 12.5), plaster, Enum.Material.Plaster)
	-- skirting
	for i, spec in { { 0, -11.95, 24, 0.2 }, { 0, 11.95, 24, 0.2 } } do
		part(m, "Skirt" .. i, Vector3.new(spec[3], 0.5, spec[4]), o * CFrame.new(spec[1], 0.25, spec[2]), trim, Enum.Material.Wood)
	end
	-- furniture
	local chair = Instance.new("Model")
	chair.Name = "Chair"
	local chairCf = o * CFrame.new(-4, 0, -5) * CFrame.Angles(0, math.rad(20), 0)
	local seat = part(chair, "Seat", Vector3.new(2, 0.25, 2), chairCf * CFrame.new(0, 2, 0), trim, Enum.Material.Wood)
	for _, l in { { -0.85, -0.85 }, { 0.85, -0.85 }, { -0.85, 0.85 }, { 0.85, 0.85 } } do
		part(chair, "Leg", Vector3.new(0.2, 2, 0.2), chairCf * CFrame.new(l[1], 1, l[2]), trim, Enum.Material.Wood)
	end
	part(chair, "Back", Vector3.new(2, 2.4, 0.2), chairCf * CFrame.new(0, 3.3, 0.9), trim, Enum.Material.Wood)
	chair.PrimaryPart = seat
	chair.Parent = m
	part(m, "TableTop", Vector3.new(5, 0.3, 3), o * CFrame.new(4, 3, -6), Color3.fromRGB(86, 70, 54), Enum.Material.Wood)
	for _, l in { { 1.7, -6 - 1.2 }, { 6.3, -6 - 1.2 }, { 1.7, -6 + 1.2 }, { 6.3, -6 + 1.2 } } do
		part(m, "TableLeg", Vector3.new(0.3, 3, 0.3), o * CFrame.new(l[1], 1.5, l[2]), trim, Enum.Material.Wood)
	end
	part(m, "Cabinet", Vector3.new(3, 6, 2), o * CFrame.new(9.5, 3, -10.4), Color3.fromRGB(70, 66, 60), Enum.Material.Wood)
	part(m, "Picture", Vector3.new(3, 2.2, 0.12), o * CFrame.new(-6, 7.5, -11.95), Color3.fromRGB(40, 36, 32), Enum.Material.Wood)
	part(m, "PictureCanvas", Vector3.new(2.6, 1.8, 0.05), o * CFrame.new(-6, 7.5, -11.87), Color3.fromRGB(96, 104, 92), Enum.Material.Fabric)
	-- the lamp
	local bulb = part(m, "Bulb", Vector3.new(0.9, 0.9, 0.9), o * CFrame.new(0, H - 1.6, -1), Color3.fromRGB(255, 240, 214), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CastShadow = false })
	part(m, "Cord", Vector3.new(0.06, 1.2, 0.06), o * CFrame.new(0, H - 0.6, -1), Color3.fromRGB(10, 10, 10), Enum.Material.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 232, 205)
	light.Shadows = true
	light.Parent = bulb

	m.Parent = Runtime.folder()
	local function at(x: number, y: number, z: number): Vector3
		return (o * CFrame.new(x, y, z)).Position
	end
	return {
		model = m,
		origin = o,
		door = door,
		chair = chair,
		mirror = mirror,
		mirrorCf = mirrorCf,
		window = glass,
		outsideFeet = CFrame.lookAt(at(0, 0, -15.5), at(0, 0, 0)),
		lamp = { bulb = bulb, light = light },
		at = at,
		-- named camera positions (all look at sensible points)
		shot = function(name: string): CFrame
			if name == "window" then
				return CFrame.lookAt(at(1.5, 5.6, 6), at(0, 6.4, -12.5))
			elseif name == "mirror" then
				return CFrame.lookAt(at(4, 5.8, 8), at(-12, 6.4, 2))
			elseif name == "door" then
				return CFrame.lookAt(at(-3, 5.6, 6), at(12.5, 5, 1.5))
			elseif name == "corner" then
				return CFrame.lookAt(at(10.5, 11, 10.5), at(-2, 2, -4))
			elseif name == "left" then
				return CFrame.lookAt(at(-8, 5.6, 9), at(-8, 5, -12))
			elseif name == "right" then
				return CFrame.lookAt(at(8, 5.6, 9), at(8, 5, -12))
			end
			return CFrame.lookAt(at(0, 5.6, 10), at(0, 5, -12))
		end,
	}
end

--[[
	Sets.cctvCamera(cf): a wall-mounted security camera (housing, lens, red
	LED) as a model whose pivot is the mount; rotate it with MoveObject.
]]
function Sets.cctvCamera(cf: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "SecurityCamera"
	local mount = part(m, "Mount", Vector3.new(0.5, 0.5, 0.5), cf, Color3.fromRGB(60, 60, 62), Enum.Material.Metal)
	part(m, "Arm", Vector3.new(0.18, 0.18, 0.8), cf * CFrame.new(0, 0, -0.5), Color3.fromRGB(60, 60, 62), Enum.Material.Metal)
	part(m, "Housing", Vector3.new(0.9, 0.8, 1.8), cf * CFrame.new(0, -0.1, -1.6), Color3.fromRGB(200, 200, 196), Enum.Material.SmoothPlastic)
	part(m, "Lens", Vector3.new(0.4, 0.55, 0.55), cf * CFrame.new(0, -0.1, -2.55) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(10, 10, 12), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Reflectance = 0.4 })
	local led = part(m, "LED", Vector3.new(0.12, 0.12, 0.12), cf * CFrame.new(0.32, 0.22, -2.45), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 3
	glow.Brightness = 1
	glow.Parent = led
	m.PrimaryPart = mount
	m.Parent = Runtime.folder()
	return m
end

return Sets
