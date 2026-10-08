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

return Sets
