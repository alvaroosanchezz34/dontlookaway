--[[
	HallwayBuilder
	The impossible hallway's geometry, built once per server and kept out of
	the world (ServerStorage) until a distortion needs it.

	Where: far outside everything (ORIGIN), never near the building, the
	lobby or the courtyard, and fully closed (floor, ceiling, walls, both
	ends), so nothing outside it can be seen or reached and nothing from it
	leaks into the map. It does not depend on the round's procedural map, so
	it is the same, valid space every round.

	Shape (local space: the corridor runs along -Z from the exit door at
	z = 0 to a blank wall at z = -LENGTH, floor top at y = 0):
	  * SEGMENTS of SEGMENT studs, WIDTH wide and HEIGHT high
	  * a fixture in the middle of every segment (a few dead): the corridor
	    is in a total blackout, lit only by red emergency tubes
	  * doors on alternating sides, every one numbered alike, a few not quite
	  * a darker lower wall band and baseboards: the repetition you count by
	  * at z = 0 the way out: a doorway into black under an EXIT sign
	Structural parts touch, never overlap; every decoration is thin, offset
	from its surface (no z-fighting) and does not collide (nothing to snag
	on while running). The project's surface textures are applied
	(MaterialLibrary), so it is the same building's skin, made wrong.

	The client drives the lamps (DistortionController): each lamp model
	carries Index, Z and Dead attributes; the server writes the corridor's
	"DarkFrom" (the dark's edge, a local Z) on the model.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaterialLibrary = require(ReplicatedStorage.Shared.MaterialLibrary)

local HallwayBuilder = {}

HallwayBuilder.ORIGIN = CFrame.new(4000, 300, 4000)
HallwayBuilder.SEGMENT = 12
HallwayBuilder.SEGMENTS = 40
HallwayBuilder.LENGTH = HallwayBuilder.SEGMENT * HallwayBuilder.SEGMENTS
HallwayBuilder.WIDTH = 8
HallwayBuilder.HEIGHT = 10
-- where the player arrives and where it waits (local z)
HallwayBuilder.SPAWN_Z = -330
HallwayBuilder.OBSERVER_Z = -455
-- crossing this (local z, toward the door) is reaching the way out
HallwayBuilder.EXIT_Z = -4

local WALL = Color3.fromRGB(150, 156, 140)
local BAND = Color3.fromRGB(84, 92, 82)
local FLOOR = Color3.fromRGB(66, 64, 58)
local CEILING = Color3.fromRGB(168, 168, 160)
local TRIM = Color3.fromRGB(38, 32, 26)
local DOOR = Color3.fromRGB(62, 50, 38)
local FRAME = Color3.fromRGB(54, 52, 48)
-- the corridor is in a total blackout (level 4): only the red emergency
-- tubes are lit
local TUBE = Color3.fromRGB(255, 72, 58)
local HOUSING = Color3.fromRGB(64, 66, 62)
local STAIN = Color3.fromRGB(96, 100, 86)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: any, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function plaque(parent: Instance, cf: CFrame, text: string)
	local p = part(parent, "Plaque", Vector3.new(0.9, 0.32, 0.05), cf, Color3.fromRGB(176, 170, 150), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(30, 28, 24)
	label.Parent = gui
end

-- The number on a door: almost always the same one.
local function doorNumber(i: number): string
	local odd = { [7] = "B-31", [15] = "13-B", [22] = "B-13 ", [29] = "B-1", [34] = "B-13" }
	return odd[i] or "B-13"
end

-- Builds the corridor (not parented). Returns the model.
function HallwayBuilder.build(): Model
	local S, N, W, H = HallwayBuilder.SEGMENT, HallwayBuilder.SEGMENTS, HallwayBuilder.WIDTH, HallwayBuilder.HEIGHT
	local O = HallwayBuilder.ORIGIN
	local model = Instance.new("Model")
	model.Name = "ImpossibleHallway"
	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model
	local detail = Instance.new("Folder")
	detail.Name = "Detail"
	detail.Parent = model
	local lamps = Instance.new("Folder")
	lamps.Name = "Lamps"
	lamps.Parent = model
	for i = 0, N - 1 do
		local zc = -(i + 0.5) * S
		local at = function(x: number, y: number, z: number): CFrame
			return O * CFrame.new(x, y, z)
		end
		part(structure, "Floor", Vector3.new(W + 2, 1, S), at(0, -0.5, zc), FLOOR, Enum.Material.Concrete, true)
		part(structure, "Ceiling", Vector3.new(W + 2, 1, S), at(0, H + 0.5, zc), CEILING, Enum.Material.Plaster, true)
		for _, side in { -1, 1 } do
			part(structure, "Wall", Vector3.new(1, H, S), at(side * (W / 2 + 0.5), H / 2, zc), WALL, Enum.Material.Plaster, true)
			-- the lower band and the baseboard: what the eye counts the segments by
			part(detail, "Band", Vector3.new(0.04, 3.2, S), at(side * (W / 2 - 0.03), 1.6, zc), BAND, Enum.Material.Plaster)
			part(detail, "Baseboard", Vector3.new(0.12, 0.4, S), at(side * (W / 2 - 0.08), 0.2, zc), TRIM, Enum.Material.Wood)
		end
		-- the fixture: a housing and a tube, lit by the client
		local lamp = Instance.new("Model")
		lamp.Name = "Lamp"
		-- a few are dead from the start, never where you arrive, where it
		-- waits, or at the door
		local dead = (i * 7 + 3) % 9 == 0 and i > 3 and math.abs(zc - HallwayBuilder.SPAWN_Z) > 30 and math.abs(zc - HallwayBuilder.OBSERVER_Z) > 20
		lamp:SetAttribute("Index", i + 1)
		lamp:SetAttribute("Z", zc)
		lamp:SetAttribute("Dead", dead)
		part(lamp, "Housing", Vector3.new(2.2, 0.3, 4.6), at(0, H - 0.15, zc), HOUSING, Enum.Material.Metal)
		local tube = part(lamp, "Tube", Vector3.new(0.5, 0.12, 4.2), at(0, H - 0.36, zc), TUBE, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Color = Color3.fromRGB(255, 84, 66)
		light.Range = 18
		light.Brightness = 0.9
		light.Shadows = false
		light.Enabled = false
		light.Parent = tube
		lamp.PrimaryPart = tube
		lamp.Parent = lamps
		-- a door every other segment, sides alternating
		if i % 2 == 0 and i > 0 then
			local side = if i % 4 == 0 then -1 else 1
			local face = side * (W / 2)
			local dz = zc + 2.5
			-- the plaque faces into the corridor (its front is its -Z)
			local rot = CFrame.Angles(0, if side < 0 then math.rad(-90) else math.rad(90), 0)
			local door = Instance.new("Model")
			door.Name = "Door"
			part(door, "Panel", Vector3.new(0.1, 7, 3), at(face - side * 0.06, 3.5, dz), DOOR, Enum.Material.Wood)
			part(door, "JambA", Vector3.new(0.22, 7.3, 0.3), at(face - side * 0.11, 3.65, dz - 1.65), FRAME, Enum.Material.Metal)
			part(door, "JambB", Vector3.new(0.22, 7.3, 0.3), at(face - side * 0.11, 3.65, dz + 1.65), FRAME, Enum.Material.Metal)
			part(door, "Head", Vector3.new(0.22, 0.3, 3.6), at(face - side * 0.11, 7.45, dz), FRAME, Enum.Material.Metal)
			part(door, "Knob", Vector3.new(0.22, 0.22, 0.22), at(face - side * 0.2, 3.4, dz - 1.1), Color3.fromRGB(120, 110, 90), Enum.Material.Metal)
			plaque(door, O * CFrame.new(face - side * 0.04, 5.6, dz + 2.4) * rot, doorNumber(i))
			door.Parent = detail
		elseif i % 5 == 3 then
			-- a water stain: one more thing to remember the wrong way
			local side = if i % 2 == 0 then 1 else -1
			part(detail, "Stain", Vector3.new(0.03, 2.2, 3.4), at(side * (W / 2 - 0.05), 6.2, zc - 1), STAIN, Enum.Material.Plaster)
		end
	end
	-- the blank far end
	part(structure, "FarWall", Vector3.new(W + 2, H + 2, 1), O * CFrame.new(0, H / 2, -HallwayBuilder.LENGTH - 0.5), Color3.fromRGB(20, 20, 20), Enum.Material.Plaster, true)
	-- the way out: a doorway into black, under an EXIT sign
	local doorW, doorH = 4, 7.6
	part(structure, "EndWallL", Vector3.new((W + 2 - doorW) / 2, H + 2, 1), O * CFrame.new(-(doorW / 2 + (W + 2 - doorW) / 4), H / 2, 0.5), WALL, Enum.Material.Plaster, true)
	part(structure, "EndWallR", Vector3.new((W + 2 - doorW) / 2, H + 2, 1), O * CFrame.new(doorW / 2 + (W + 2 - doorW) / 4, H / 2, 0.5), WALL, Enum.Material.Plaster, true)
	part(structure, "EndHeader", Vector3.new(doorW, H + 1 - doorH, 1), O * CFrame.new(0, doorH + (H + 1 - doorH) / 2, 0.5), WALL, Enum.Material.Plaster, true)
	-- behind the doorway: a short black box (the cut back happens before
	-- anyone gets far into it)
	local depth = 3
	part(structure, "VoidFloor", Vector3.new(doorW, 1, depth), O * CFrame.new(0, -0.5, 1 + depth / 2), FLOOR, Enum.Material.Concrete, true)
	part(structure, "VoidL", Vector3.new(1, doorH, depth), O * CFrame.new(-(doorW / 2 + 0.5), doorH / 2, 1 + depth / 2), Color3.new(0, 0, 0), Enum.Material.Fabric, true)
	part(structure, "VoidR", Vector3.new(1, doorH, depth), O * CFrame.new(doorW / 2 + 0.5, doorH / 2, 1 + depth / 2), Color3.new(0, 0, 0), Enum.Material.Fabric, true)
	part(structure, "VoidTop", Vector3.new(doorW + 2, 1, depth), O * CFrame.new(0, doorH + 0.5, 1 + depth / 2), Color3.new(0, 0, 0), Enum.Material.Fabric, true)
	part(structure, "Void", Vector3.new(doorW + 2, doorH + 2, 1), O * CFrame.new(0, doorH / 2, 1 + depth + 0.5), Color3.new(0, 0, 0), Enum.Material.Fabric, true)
	local sign = part(detail, "ExitSign", Vector3.new(2.4, 0.7, 0.16), O * CFrame.new(0, doorH + 0.75, -0.1), Color3.fromRGB(150, 40, 34), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(255, 80, 64)
	glow.Range = 10
	glow.Brightness = 0.5
	glow.Shadows = false
	glow.Parent = sign
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "EXIT"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 226, 220)
	label.Parent = gui
	model:SetAttribute("Length", HallwayBuilder.LENGTH)
	model:SetAttribute("DarkFrom", -HallwayBuilder.LENGTH - 10)
	model.PrimaryPart = structure:FindFirstChild("Floor") :: BasePart
	pcall(MaterialLibrary.dress, model)
	return model
end

-- Local position (the corridor's own space) of a world point.
function HallwayBuilder.toLocal(position: Vector3): Vector3
	return HallwayBuilder.ORIGIN:PointToObjectSpace(position)
end

function HallwayBuilder.toWorld(x: number, y: number, z: number): Vector3
	return HallwayBuilder.ORIGIN:PointToWorldSpace(Vector3.new(x, y, z))
end

-- Is a world point inside the corridor (with a margin)?
function HallwayBuilder.contains(position: Vector3, margin: number?): boolean
	local p = HallwayBuilder.toLocal(position)
	local m = margin or 0
	return math.abs(p.X) <= HallwayBuilder.WIDTH / 2 + m and p.Y >= -2 - m and p.Y <= HallwayBuilder.HEIGHT + m and p.Z <= 4 + m and p.Z >= -HallwayBuilder.LENGTH - m
end

-- Where the player arrives (standing, facing down the corridor toward it).
function HallwayBuilder.spawnCFrame(): CFrame
	local at = HallwayBuilder.toWorld(0, 3, HallwayBuilder.SPAWN_Z)
	local ahead = HallwayBuilder.toWorld(0, 3, HallwayBuilder.SPAWN_Z - 10)
	return CFrame.lookAt(at, ahead)
end

-- Where it waits (on the floor, facing the player).
function HallwayBuilder.observerCFrame(): CFrame
	local at = HallwayBuilder.toWorld(0, 0, HallwayBuilder.OBSERVER_Z)
	local toward = HallwayBuilder.toWorld(0, 0, HallwayBuilder.OBSERVER_Z + 10)
	return CFrame.lookAt(at, toward)
end

return HallwayBuilder
