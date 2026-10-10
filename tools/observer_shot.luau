--[[
	Observer shot export (Lune): poses THE OBSERVER without physics
	(ObserverRig.solve) and writes the parts, lights and camera to JSON for
	tools/blender/render_room.py, to check what a player actually sees.

	Shots
	  scare      the jumpscare's impact frame: ObserverRig.ScarePose(1, open),
	             placed by ObserverRig.placeFace exactly as ScareController does
	  scareOld   the impact frame as the cinematic posed it before this pass
	             (attack pose, feet 0.75 studs from the eye), for comparison
	  stand      standing 12 studs away in a dim room, eyes on the camera
	  far        at the end of a 40-stud dark corridor, one dim light

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/observer_shot.luau build/test.rbxlx <shot> [out.json] [open]
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
local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local LightingService = requireModule(Server.Services.LightingService)

local shot = process.args[2] or "scare"
local out = process.args[3] or ("build/observer_" .. shot .. ".json")
local open = tonumber(process.args[4]) or 1
-- ScareController's light levels at full strength
local SPOT = tonumber(process.args[5]) or 3.2
local UNDER = tonumber(process.args[6]) or 1.1

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
	local face = eye + look * 2.0
	rootCf = ObserverRig.placeFace(motors, transforms, face, eye)
	-- eyes on the lens
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(eye)
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	camera = { eye = v3(eye), target = v3(face), fov = 50 }
	-- ScareController's light: a hard spot from the camera, a low warm one under the jaw
	addLight("SpotLight", eye - look * 0.4, look, SPOT, 18, 70, roblox.Color3.fromRGB(226, 234, 255), true)
	addLight("PointLight", face - Vector3.new(0, 1.8, 0) - look * 0.6, Vector3.new(0, 1, 0), UNDER, 7, 180, roblox.Color3.fromRGB(255, 206, 180), false)
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
elseif shot == "stand" or shot == "far" then
	local dist = if shot == "far" then 40 else 12
	-- facing the camera (+Z). Angles, not CFrame.lookAt: Lune's lookAt faces
	-- the other way.
	rootCf = CFrame.new(0, ObserverRig.HipHeight + 1, -dist) * CFrame.Angles(0, math.pi, 0)
	transforms = { HeadJoint = CFrame.Angles(0, 0, math.rad(14)) }
	local world = ObserverRig.solve(rig, rootCf, transforms)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local rest = world[m.Part0] * m.C0
		local rel = rest:PointToObjectSpace(eye)
		transforms["EyeTurn" .. side] = CFrame.Angles(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), math.atan2(-rel.X, -rel.Z), 0)
	end
	camera = { eye = v3(eye), target = v3(Vector3.new(0, if shot == "far" then 5 else 6.5, -dist)), fov = 70 }
	-- a corridor: floor, walls, ceiling
	local len = dist + 12
	local grey = roblox.Color3.fromRGB(120, 118, 112)
	addPart("Floor", CFrame.new(0, -0.5, -len / 2), Vector3.new(10, 1, len + 4), roblox.Color3.fromRGB(90, 86, 80), "Concrete")
	addPart("Ceiling", CFrame.new(0, 11.5, -len / 2), Vector3.new(10, 1, len + 4), grey, "Plaster")
	addPart("WallL", CFrame.new(-5.5, 5.5, -len / 2), Vector3.new(1, 12, len + 4), grey, "Plaster")
	addPart("WallR", CFrame.new(5.5, 5.5, -len / 2), Vector3.new(1, 12, len + 4), grey, "Plaster")
	addPart("End", CFrame.new(0, 5.5, -len - 1), Vector3.new(12, 12, 1), grey, "Plaster")
	-- one dim fluorescent halfway, one beyond the creature
	addLight("PointLight", Vector3.new(0, 10.5, -dist * 0.5), Vector3.new(0, -1, 0), 0.9, 18, 180, roblox.Color3.fromRGB(220, 226, 230), true)
	addLight("PointLight", Vector3.new(0, 10.5, -dist - 6), Vector3.new(0, -1, 0), 0.7, 16, 180, roblox.Color3.fromRGB(220, 226, 230), true)
end

local world = ObserverRig.solve(rig, rootCf, transforms)
local skipped = 0
for part, cf in world do
	if part.Transparency < 0.95 then
		local shape = "box"
		local size = part.Size
		local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
		if part.Shape == roblox.Enum.PartType.Ball or (mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere) then
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
fs.writeFile(out, serde.encode("json", {
	room = shot,
	seed = 0,
	min = { -6, 0, -40 },
	max = { 6, 12, 2 },
	parts = parts,
	lights = lights,
	presets = presets,
	meshes = {},
	camera = camera,
}))
print(string.format("observer %s: %d parts (%d hidden), %d lights -> %s", shot, #parts, skipped, #lights, out))
