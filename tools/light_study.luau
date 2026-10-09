--[[
	Light study export (Lune).
	Builds the building for a seed and writes one room (plus a margin) to JSON:
	every visible part (box / cylinder / ball, colour, material, variant) and
	every light with what it needs to be evaluated (fixture mode and circuit),
	plus the lighting presets. tools/light_study.py renders it.

	This is NOT Roblox's renderer: it is a consistent approximation used to
	compare light levels before / after a change and NORMAL vs BLACKOUT.

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/light_study.luau build/test.rbxlx [roomId] [seed] [out.json]
]]

local env = require("./lib/env")
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = env.roblox
local game = env.game
local requireModule = env.requireModule
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local LightingService = requireModule(Server.Services.LightingService)

local roomId = process.args[2] or "G_r"
local seed = tonumber(process.args[3]) or 8919
local out = process.args[4] or ("build/light_" .. roomId .. ".json")

local holder = Instance.new("Folder")
holder.Parent = env.workspace
local map = MapBuilder.build(seed, holder)
local room = map.Rooms[roomId]
assert(room, "no room " .. roomId)
local margin = 6
local lo = room.min - Vector3.new(margin, 1, margin)
local hi = room.max + Vector3.new(margin, 2, margin)

local function inside(p: Vector3, size: Vector3): boolean
	local r = size.Magnitude / 2
	return p.X + r > lo.X and p.X - r < hi.X and p.Y + r > lo.Y and p.Y - r < hi.Y and p.Z + r > lo.Z and p.Z - r < hi.Z
end

local function c3(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local parts, lights = {}, {}
for _, d in map.Root:GetDescendants() do
	if d:IsA("BasePart") then
		local p = d.CFrame.Position
		if d.Transparency < 0.95 and inside(p, d.Size) then
			local cf = d.CFrame
			local shape = "box"
			local ok, sh = pcall(function()
				return (d :: any).Shape
			end)
			if ok and sh then
				if sh.Name == "Cylinder" then
					shape = "cyl"
				elseif sh.Name == "Ball" then
					shape = "ball"
				end
			end
			if d:IsA("WedgePart") then
				shape = "box"
			end
			table.insert(parts, {
				name = d.Name,
				pos = { p.X, p.Y, p.Z },
				rx = { cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z },
				ry = { cf.UpVector.X, cf.UpVector.Y, cf.UpVector.Z },
				rz = { -cf.LookVector.X, -cf.LookVector.Y, -cf.LookVector.Z },
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				shape = shape,
				color = c3(d.Color),
				material = d.Material.Name,
				variant = d.MaterialVariant,
				transparency = d.Transparency,
			})
		end
	elseif d:IsA("Light") then
		local host = d.Parent
		if host and host:IsA("BasePart") and inside(host.CFrame.Position, Vector3.new(1, 1, 1)) then
			local fixture = host:FindFirstAncestorWhichIsA("Model")
			local face = if d:IsA("PointLight") then nil else (d :: any).Face
			local cf = host.CFrame
			local dir = -cf.UpVector
			local origin = cf.Position
			if face then
				local n = face.Name
				local map_ = {
					Top = cf.UpVector,
					Bottom = -cf.UpVector,
					Front = cf.LookVector,
					Back = -cf.LookVector,
					Right = cf.RightVector,
					Left = -cf.RightVector,
				}
				dir = map_[n] or dir
				local half = host.Size / 2
				local ext = { Top = half.Y, Bottom = half.Y, Front = half.Z, Back = half.Z, Right = half.X, Left = half.X }
				origin = cf.Position + dir * (ext[n] or 0)
			end
			local isFixture = fixture and fixture:HasTag("Fixture")
			table.insert(lights, {
				class = d.ClassName,
				pos = { origin.X, origin.Y, origin.Z },
				dir = { dir.X, dir.Y, dir.Z },
				brightness = d.Brightness,
				range = d.Range,
				angle = if d:IsA("PointLight") then 180 else (d :: any).Angle,
				color = c3(d.Color),
				shadows = d.Shadows,
				-- how the client drives it (LightController): share of the fixture brightness
				ratio = d:GetAttribute("Ratio"),
				main = d:GetAttribute("Main") == true,
				fixture = isFixture,
				mode = if isFixture then fixture:GetAttribute("Mode") else "always",
				circuit = if isFixture then fixture:GetAttribute("Circuit") else "NONE",
				baseBrightness = if isFixture then fixture:GetAttribute("BaseBrightness") else nil,
				tag = if d:HasTag("Moonlight") then "moon" else (if isFixture then "fixture" else (d.Enabled and "on" or "off")),
				powered = d:GetAttribute("PoweredLight") == true,
			})
		end
	end
end

local presets = {}
for name, preset in LightingService.Presets do
	presets[name] = {
		ambient = c3(preset.Ambient),
		exposure = preset.ExposureCompensation,
		contrast = preset.cc.Contrast,
		saturation = preset.cc.Saturation,
		brightness = preset.cc.Brightness,
		tint = c3(preset.cc.TintColor),
	}
end

fs.writeFile(out, serde.encode("json", {
	room = roomId,
	seed = seed,
	min = { room.min.X, room.min.Y, room.min.Z },
	max = { room.max.X, room.max.Y, room.max.Z },
	parts = parts,
	lights = lights,
	presets = presets,
}))
print(string.format("%s seed %d: %d parts, %d lights -> %s", roomId, seed, #parts, #lights, out))
