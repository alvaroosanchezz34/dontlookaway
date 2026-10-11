--[[
	Observer shot export (Lune): poses THE OBSERVER without physics
	(ObserverRig.solve) and writes the parts, lights and camera to JSON for
	tools/blender/render_room.py, to check what a player actually sees.

	Shots
	  scare      the jumpscare's hit frame: ObserverRig.ScarePose(1, open),
	             placed by ObserverRig.placeFace exactly as ScareController does,
	             at the default field of view, lit only by the light on its
	             head (arg 5: "lowside" = ScareController.Light, "low", "side")
	  scareOld   the impact frame as the cinematic posed it before this pass
	             (attack pose, feet 0.75 studs from the eye), for comparison
	  torch      standing 10 studs away in the black, lit only by your
	             flashlight (GameConfig.Flashlight, held as FlashlightController
	             holds it), at the default field of view
	  torchClose the same, a long lens on its head and torso (to judge the skin)
	  stand      standing 12 studs away in a dim room, eyes on the camera
	  far        at the end of a 40-stud dark corridor, one dim light

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/observer_shot.luau build/test.rbxlx <shot> [out.json] [open] [light]
	OBSERVER_MAPS=build/skin_A picks the folder of the baked maps (default
	assets/observer; a segment missing there falls back to it).
]]

local env = require("./lib/env")
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = env.roblox
local game = env.game
local requireModule = env.requireModule
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local RS = game:GetService("ReplicatedStorage")
local ObserverRig = requireModule(RS.Shared.ObserverRig)
local GameConfig = requireModule(RS.Shared.Config.GameConfig)
local mapsRoot = process.env.OBSERVER_MAPS or "assets/observer"

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local LightingService = requireModule(Server.Services.LightingService)

local shot = process.args[2] or "scare"
local out = process.args[3] or ("build/observer_" .. shot .. ".json")
local open = tonumber(process.args[4]) or 1
-- "smooth": the body as the flowing meshes (assets/observer), like the
-- dressed rig in the game; "parts": the part-built fallback
local body = process.args[7] or "smooth"
-- the scare light on its head (head space; "lowside" mirrors
-- ScareController.Light, the others are the positions it was chosen over)
local SCARE_LIGHTS = {
	lowside = CFrame.new(-0.9, -0.4, -0.45),
	low = CFrame.new(-0.55, -0.8, -0.7),
	side = CFrame.new(-1.0, 0.05, -0.35),
}
local scareLight = SCARE_LIGHTS[process.args[5] or "lowside"] or SCARE_LIGHTS.lowside
-- ScareController's old light levels (scareOld)
local SPOT = 2.2

local function c3(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function v3(v)
	return { v.X, v.Y, v.Z }
end

local parts, lights = {}, {}
local function addPart(name, cf, size, color, material, shape)
	table.insert(parts, {
		name = name,
		pos = v3(cf.Position),
		rx = v3(cf.RightVector),
		ry = v3(cf.UpVector),
		rz = v3(-cf.LookVector),
		size = v3(size),
		shape = shape or "box",
		color = c3(color),
		material = material,
		variant = "",
		transparency = 0,
	})
end
--[[
	render_room.py gives a light its brightness at half its Range and lets it
	fall off with the square of the distance; much closer than that it is far
	too strong (a flashlight at 10 studs comes out ~5x Roblox's). For a light
	aimed at one subject `d` studs away: Roblox's falloff there, and a Range
	of 2d, so the render gives what the game gives on the subject.
]]
local function atSubject(brightness: number, range: number, d: number): (number, number)
	local k = (1 - math.min(d / range, 1) ^ 2) ^ 2
	return brightness * k / 0.5625, 2 * d
end

local function addLight(class, pos, dir, brightness, range, angle, color, shadows)
	table.insert(lights, {
		class = class,
		pos = v3(pos),
		dir = v3(dir),
		brightness = brightness,
		range = range,
		angle = angle,
		color = c3(color),
		shadows = shadows,
		tag = "on",
		powered = false,
		mode = "on",
		circuit = "NONE",
	})
end

-- the player's eye: feet on the floor at y = 0, eye 4.5 up, looking -Z
local eye = Vector3.new(0, 4.5, 0)
local look = Vector3.new(0, 0, -1)
local camera = { eye = v3(eye), target = v3(eye + look * 10), fov = 70 }

local rig = ObserverRig.build(CFrame.new(0, 0, -12), { localCopy = true })
local motors = ObserverRig.motors(rig)
local transforms = {}
local rootCf = rig.PrimaryPart.CFrame

if shot == "scare" then
	transforms = ObserverRig.ScarePose(1, open)
	local face = eye + look * ObserverRig.ScareDistance
	rootCf = ObserverRig.placeFace(motors, transforms, face, CFrame.new(eye))
	-- eyes on the lens
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(eye)
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	camera = { eye = v3(eye), target = v3(eye + look * 10), fov = 74 }
	-- ScareController's light: one dim cold point light on its head, short reach
	local headCf = world[rig:FindFirstChild("Head")]
	local lightPos = (headCf * scareLight).Position
	local b, r = atSubject(4.5, 4, (lightPos - (headCf * ObserverRig.FaceAnchor).Position).Magnitude)
	addLight("PointLight", lightPos, Vector3.new(0, 1, 0), b, r, 180, roblox.Color3.fromRGB(196, 212, 255), true)
elseif shot == "scareOld" then
	-- attackPose(t = 1, rage = 1) as it was, placed as it was
	local a, g = 1, 1
	transforms = {
		RootJoint = CFrame.new(0, -2.5 * g, 0),
		LeftShoulder = CFrame.Angles(math.rad(-100 * a - 28 * g), 0, math.rad(-12 * a + 22 * g)),
		RightShoulder = CFrame.Angles(math.rad(-100 * a - 28 * g), 0, math.rad(12 * a - 22 * g)),
		LeftElbow = CFrame.Angles(math.rad(-30 * a - 45 * g), 0, 0),
		RightElbow = CFrame.Angles(math.rad(-30 * a - 45 * g), 0, 0),
		Waist = CFrame.Angles(math.rad(18 * a + 26 * g), 0, 0),
		NeckJoint = CFrame.Angles(math.rad(28 * a + 14 * g), 0, 0),
		HeadJoint = CFrame.Angles(math.rad(8 - 10 * g), 0, math.rad(68 * 0.4)),
		JawL = CFrame.Angles(0, math.rad(-55), 0),
		JawR = CFrame.Angles(0, math.rad(55), 0),
	}
	local feet = Vector3.new(eye.X, 0, eye.Z) + look * 0.75
	rootCf = CFrame.lookAt(feet, Vector3.new(eye.X, 0, eye.Z)) * CFrame.new(0, ObserverRig.HipHeight + 1, 0)
	local world = ObserverRig.solve(rig, rootCf, transforms)
	local head = world[rig:FindFirstChild("Head")]
	camera = { eye = v3(eye - (head.Position - eye).Unit * 0.85), target = v3(head.Position), fov = 30 }
	addLight("SpotLight", eye - look * 0.4, (head.Position - eye).Unit, 9, 18, 70, roblox.Color3.fromRGB(226, 234, 255), true)
elseif shot == "torch" or shot == "torchClose" then
	-- facing the camera (+Z) ten studs away, eyes on you, in the black
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -10) * CFrame.Angles(0, math.pi, 0)
	transforms = ObserverRig.ScarePose(0, 0)
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(eye)
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	local target = if shot == "torch" then Vector3.new(0, 6.6, -10) else Vector3.new(0, 7.9, -10)
	camera = { eye = v3(eye), target = v3(target), fov = if shot == "torch" then 74 else 24 }
	addPart("Floor", CFrame.new(0, -0.5, -12), Vector3.new(14, 1, 30), roblox.Color3.fromRGB(90, 86, 80), "Concrete")
	-- the flashlight: below and right of the eye, aimed at its chest
	local FL = GameConfig.Flashlight
	local hand = eye + Vector3.new(0.55, -0.5, -0.45)
	local aim = (Vector3.new(0, 6.6, -10) - hand).Unit
	local d = (Vector3.new(0, 6.6, -10) - hand).Magnitude
	local b1, r1 = atSubject(FL.Brightness * 0.75, FL.Range + 6, d)
	local b2, r2 = atSubject(FL.Brightness * 0.7, FL.Range, d)
	addLight("SpotLight", hand, aim, b1, r1, FL.Angle * 0.42, roblox.Color3.new(1, 1, 1), true)
	addLight("SpotLight", hand, aim, b2, r2, FL.Angle, roblox.Color3.new(1, 1, 1), true)
elseif shot == "inspect" or shot == "inspectHead" then
	-- studio look at the form: three-quarter view, a key light and a rim
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -12) * CFrame.Angles(0, math.pi, 0)
	transforms = ObserverRig.ScarePose(0, 0)
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(Vector3.new(4, 7, -6))
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	if shot == "inspectHead" then
		camera = { eye = v3(Vector3.new(1.3, 9.3, -7.6)), target = v3(Vector3.new(0, 8.85, -12)), fov = 46 }
	else
		camera = { eye = v3(Vector3.new(3.6, 5.2, -5.4)), target = v3(Vector3.new(0, 4.9, -12)), fov = 74 }
	end
	addPart("Floor", CFrame.new(0, -0.5, -12), Vector3.new(30, 1, 30), roblox.Color3.fromRGB(70, 68, 66), "Concrete")
	addLight("SpotLight", Vector3.new(5, 11, -5), (Vector3.new(0, 6, -12) - Vector3.new(5, 11, -5)).Unit, 3, 26, 60, roblox.Color3.fromRGB(240, 236, 228), true)
	addLight("SpotLight", Vector3.new(-4, 9, -18), (Vector3.new(0, 6, -12) - Vector3.new(-4, 9, -18)).Unit, 2.5, 22, 60, roblox.Color3.fromRGB(200, 214, 240), true)
elseif shot == "walk" then
	-- mid-stride in ObserverFX's STALK gait (phase p = 1.3), seen three-quarter
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -10) * CFrame.Angles(0, math.pi * 0.8, 0)
	local p = 1.3
	local sn = math.sin(p)
	transforms = {
		RootJoint = CFrame.new(0, math.abs(math.cos(p)) * 0.1, 0),
		Waist = CFrame.Angles(math.rad(-6), sn * 0.04, 0),
		NeckJoint = CFrame.Angles(math.rad(4), 0, 0),
		LeftShoulder = CFrame.Angles(math.sin(p - 0.9) * 0.22, 0, math.rad(-3)),
		RightShoulder = CFrame.Angles(-math.sin(p - 0.9) * 0.22, 0, math.rad(3)),
		LeftHip = CFrame.Angles(math.max(0, sn) * 0.7 - math.max(0, -sn) * 0.2, 0, 0),
		RightHip = CFrame.Angles(math.max(0, -sn) * 0.7 - math.max(0, sn) * 0.2, 0, 0),
		LeftKnee = CFrame.Angles(-math.max(0, sn) * 1.0, 0, 0),
		RightKnee = CFrame.Angles(-math.max(0, -sn) * 1.0, 0, 0),
	}
	camera = { eye = v3(Vector3.new(0, 5.2, 0)), target = v3(Vector3.new(0, 5.0, -10)), fov = 70 }
	addPart("Floor", CFrame.new(0, -0.5, -10), Vector3.new(30, 1, 30), roblox.Color3.fromRGB(80, 78, 74), "Concrete")
	addLight("SpotLight", Vector3.new(4, 11, -4), (Vector3.new(0, 5, -10) - Vector3.new(4, 11, -4)).Unit, 2.6, 26, 70, roblox.Color3.fromRGB(240, 236, 228), true)
	addLight("SpotLight", Vector3.new(-4, 9, -16), (Vector3.new(0, 6, -10) - Vector3.new(-4, 9, -16)).Unit, 2.2, 22, 60, roblox.Color3.fromRGB(200, 214, 240), true)
elseif shot == "eyesDark" then
	-- the lights-out sequence: only its two eyes, eight studs ahead, in the dark
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -8) * CFrame.Angles(0, math.pi, 0)
	transforms = ObserverRig.ScarePose(0, 0)
	camera = { eye = v3(eye), target = v3(Vector3.new(0, 8.6, -8)), fov = 70 }
elseif shot == "stand" or shot == "far" or shot == "side" or shot == "dark" then
	local dist = if shot == "far" then 40 elseif shot == "side" then 10 else 12
	-- facing the camera (+Z). Angles, not CFrame.lookAt: Lune's lookAt faces
	-- the other way.
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -dist) * CFrame.Angles(0, if shot == "side" then math.pi / 2 else math.pi, 0)
	transforms = ObserverRig.ScarePose(0, 0)
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(eye)
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	camera = { eye = v3(eye), target = v3(Vector3.new(0, if shot == "far" then 5 else 6.2, -dist)), fov = 70 }
	-- a corridor: floor, walls, ceiling
	local len = dist + 12
	local grey = roblox.Color3.fromRGB(120, 118, 112)
	addPart("Floor", CFrame.new(0, -0.5, -len / 2), Vector3.new(10, 1, len + 4), roblox.Color3.fromRGB(90, 86, 80), "Concrete")
	addPart("Ceiling", CFrame.new(0, 11.5, -len / 2), Vector3.new(10, 1, len + 4), grey, "Plaster")
	addPart("WallL", CFrame.new(-5.5, 5.5, -len / 2), Vector3.new(1, 12, len + 4), grey, "Plaster")
	addPart("WallR", CFrame.new(5.5, 5.5, -len / 2), Vector3.new(1, 12, len + 4), grey, "Plaster")
	addPart("End", CFrame.new(0, 5.5, -len - 1), Vector3.new(12, 12, 1), grey, "Plaster")
	if shot == "dark" then
		-- only a light far behind it: it stands in the dark against a lit wall
		addLight("PointLight", Vector3.new(0, 10.5, -dist - 8), Vector3.new(0, -1, 0), 1.2, 18, 180, roblox.Color3.fromRGB(220, 226, 230), true)
	else
		-- one fluorescent halfway, one beyond the creature
		addLight("PointLight", Vector3.new(0, 10.5, -dist * 0.5), Vector3.new(0, -1, 0), 0.9, 18, 180, roblox.Color3.fromRGB(220, 226, 230), true)
		addLight("PointLight", Vector3.new(0, 10.5, -dist - 6), Vector3.new(0, -1, 0), 0.7, 16, 180, roblox.Color3.fromRGB(220, 226, 230), true)
	end
end

local world = ObserverRig.solve(rig, rootCf, transforms)
local MeshMeta = requireModule(RS.Shared.Config.ObserverMeshMeta)
local meshes = {}
local skipped = 0
for part, cf in world do
	local meshName = ObserverRig.SegmentMesh[part.Name]
	if shot == "eyesDark" and not (string.find(part.Name, "Eyeball") or part.Name == "Pupil") then
		meshName = nil
		skipped += 1
		continue
	end
	if body == "smooth" and meshName and MeshMeta[meshName] then
		local mcf = cf * CFrame.new(MeshMeta[meshName].offset)
		table.insert(meshes, {
			file = "assets/observer/" .. meshName .. ".obj",
			maps = if fs.isFile(mapsRoot .. "/" .. meshName .. "/" .. meshName .. "_color.png") then mapsRoot .. "/" .. meshName .. "/" .. meshName else "assets/observer/" .. meshName .. "/" .. meshName,
			bboxCentre = true,
			color = c3(part.Color),
			pos = v3(mcf.Position),
			rx = v3(mcf.RightVector),
			ry = v3(mcf.UpVector),
			rz = v3(-mcf.LookVector),
		})
		skipped += 1
	elseif body == "smooth" and ObserverRig.MeshDetails[part.Name] then
		skipped += 1
	elseif part.Transparency < 0.95 then
		local shape = "box"
		local size = part.Size
		local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
		if part:IsA("WedgePart") then
			shape = "wedge"
		elseif part.Shape == roblox.Enum.PartType.Ball or (mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere) then
			shape = "ball"
		end
		addPart(part.Name, cf, size, part.Color, part.Material.Name, shape)
	else
		skipped += 1
	end
end

local presets = {}
for name, preset in LightingService.Presets do
	presets[name] = { ambient = c3(preset.Ambient), exposure = preset.ExposureCompensation }
end
-- the jumpscare: Lighting's ambient at zero and its exposure (ScareController)
presets.SCARE = { ambient = { 0, 0, 0 }, exposure = 0.8 }
fs.writeFile(out, serde.encode("json", {
	room = shot,
	seed = 0,
	min = { -6, 0, -40 },
	max = { 6, 12, 2 },
	parts = parts,
	lights = lights,
	presets = presets,
	meshes = meshes,
	camera = camera,
}))
print(string.format("observer %s: %d parts (%d hidden), %d lights -> %s", shot, #parts, skipped, #lights, out))
