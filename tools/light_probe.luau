--[[
	Light probe export (Lune). The numbers behind docs/LIGHTING_MONOCHROME.md.

	Builds the building for a seed and writes the ground floor's west half
	(offices G-01 / G-02, the main corridor, the reception) to JSON: every
	visible part (same format as tools/light_study.luau) and every light, with
	its brightness, colour and on/off in each building state worked out by the
	game's own rules (Shared/LightingRules, the fixture's Ratio, the quality
	tier's main light). tools/light_probe.py measures fixed points from it.

	States: NORMAL, EMERGENCY (no power), B1..B4 (blackout levels, power on).

	Usage:
		lune run tools/light_probe.luau build/test.rbxl [seed] [out.json]
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
local RS = game:GetService("ReplicatedStorage")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local LightingService = requireModule(Server.Services.LightingService)
local LightingRules = requireModule(RS.Shared.LightingRules)
local VisualStandards = requireModule(RS.Shared.VisualStandards)

local seed = tonumber(process.args[2]) or 42
local out = process.args[3] or "build/light_probe.json"

local holder = Instance.new("Folder")
holder.Parent = env.workspace
local map = MapBuilder.build(seed, holder)
env.syncPositions(map.Root)

-- ground floor, x 0..112, z 0..108: G-01, G-02, the corridor, the reception
local lo, hi = Vector3.new(0, -1, 0), Vector3.new(112, 15, 108)
local function inside(p: Vector3, r: number): boolean
	return p.X + r > lo.X and p.X - r < hi.X and p.Y + r > lo.Y and p.Y - r < hi.Y and p.Z + r > lo.Z and p.Z - r < hi.Z
end
local function v3(v)
	return { v.X, v.Y, v.Z }
end
local function c3(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local STATES = {
	NORMAL = { power = true, level = 0 },
	EMERGENCY = { power = false, level = 0 },
	B1 = { power = true, level = 1 },
	B2 = { power = true, level = 2, zone = "G" },
	B3 = { power = true, level = 3 },
	B4 = { power = true, level = 4 },
}
local function presetFor(st): string
	if st.level >= 4 then
		return "BLACKOUT"
	elseif not st.power or st.level >= 3 then
		return "EMERGENCY"
	end
	return "NORMAL"
end
-- the client's lights are driven at the medium quality tier
local useMain = VisualStandards.Quality[2].secondary

local parts, lights = {}, {}
for _, d in map.Root:GetDescendants() do
	if d:IsA("BasePart") then
		local cf = d.CFrame
		if d.Transparency < 0.95 and inside(cf.Position, d.Size.Magnitude / 2) then
			local shape = "box"
			local ok, sh = pcall(function()
				return (d :: any).Shape
			end)
			if ok and sh and not d:IsA("WedgePart") then
				shape = if sh.Name == "Cylinder" then "cyl" elseif sh.Name == "Ball" then "ball" else "box"
			end
			table.insert(parts, {
				name = d.Name,
				pos = v3(cf.Position),
				rx = v3(cf.RightVector),
				ry = v3(cf.UpVector),
				rz = v3(-cf.LookVector),
				size = v3(d.Size),
				shape = shape,
				color = c3(d.Color),
				material = d.Material.Name,
				variant = d.MaterialVariant,
				transparency = d.Transparency,
				castShadow = d.CastShadow,
			})
		end
	elseif d:IsA("Light") then
		local host = d.Parent
		if host and host:IsA("BasePart") and inside(host.CFrame.Position, 1) then
			local fixture = host:FindFirstAncestorWhichIsA("Model")
			local isFixture = fixture ~= nil and fixture:HasTag("Fixture")
			local cf = host.CFrame
			local dir, origin = -cf.UpVector, cf.Position
			if not d:IsA("PointLight") then
				local n = (d :: any).Face.Name
				local dirs = { Top = cf.UpVector, Bottom = -cf.UpVector, Front = cf.LookVector, Back = -cf.LookVector, Right = cf.RightVector, Left = -cf.RightVector }
				local half = host.Size / 2
				local ext = { Top = half.Y, Bottom = half.Y, Front = half.Z, Back = half.Z, Right = half.X, Left = half.X }
				dir = dirs[n] or dir
				origin = cf.Position + dir * (ext[n] or 0)
			end
			local per = {}
			local include = isFixture or d:HasTag("Moonlight") or d:GetAttribute("PoweredLight") == true or d.Name == "Glow"
			if include then
				for name, st in STATES do
					local on, brightness, color = d.Enabled, d.Brightness, d.Color
					if isFixture then
						local world = { power = st.power, level = st.level, zone = st.zone or "", seed = 7, escape = false }
						local lit, b, c = LightingRules.evaluate(LightingRules.fixture(fixture), world, 0, { steady = true })
						local main = d:GetAttribute("Main") == true
						local ratio = d:GetAttribute("Ratio") or 1
						local solo = d:GetAttribute("Solo") or ratio
						on = lit and (useMain or not main)
						brightness = b * (if main or useMain then ratio else solo)
						color = c
					elseif d:GetAttribute("PoweredLight") == true then
						on = st.power and st.level < 4
					elseif d:HasTag("Moonlight") then
						on = true
					end
					per[name] = { on = on, brightness = brightness, color = c3(color) }
				end
				table.insert(lights, {
					class = d.ClassName,
					pos = v3(origin),
					dir = v3(dir),
					range = d.Range,
					angle = if d:IsA("PointLight") then 180 else (d :: any).Angle,
					-- a lamp near the camera casts shadows (LightController's shadow
					-- LOD): measured as the player standing there sees it
					shadows = d.Shadows or isFixture,
					room = if isFixture then fixture:GetAttribute("Room") else nil,
					fixture = if isFixture then fixture:GetFullName() else nil,
					states = per,
				})
			end
		end
	end
end

-- fixed probe points (floor level, 0.1 above the floor, facing up)
local function fixturesOf(roomId: string)
	local list = {}
	for _, f in map.Rooms[roomId].fixtures do
		if f:GetAttribute("Mode") ~= "dead" then
			table.insert(list, f:GetPivot().Position)
		end
	end
	table.sort(list, function(a, b)
		return a.X < b.X
	end)
	return list
end
local floorY = map.Rooms.G_c.min.Y + 0.1
local probes = {}
local function probe(name: string, p: Vector3, exclude: { string }?)
	table.insert(probes, { name = name, pos = { p.X, floorY, p.Z }, exclude = exclude or {} })
end
local corridor = fixturesOf("G_c")
local a, b = corridor[3], corridor[4]
probe("corridor: under a lamp", a)
probe("corridor: 5 studs from it", a + Vector3.new(5, 0, 0))
probe("corridor: halfway between two lamps", (a + b) / 2)
local rec = fixturesOf("G_r")
probe("reception: under a lamp", rec[1])
local g02 = map.Rooms.G_b
probe("office G-02: centre", g02.center)
probe("office G-02 without its lamps: centre", g02.center, { "G_b" })
-- light through a wall: the working lamp closest to a wall of its room (in
-- the probed area), measured 1.5 studs past that wall in the next room with
-- the next room's own lamps off
do
	local best
	for id, room in map.Rooms do
		if inside(room.center, 0) and room.kind ~= "corridor" then
			for _, f in room.fixtures do
				if f:GetAttribute("Mode") ~= "dead" then
					local p = f:GetPivot().Position
					for _, side in { { "X", -1, room.min.X }, { "X", 1, room.max.X }, { "Z", -1, room.min.Z }, { "Z", 1, room.max.Z } } do
						local d = math.abs(p[side[1]] - side[3])
						local beyond = if side[1] == "X" then Vector3.new(side[3] + side[2] * 5.5, room.min.Y + 2, p.Z) else Vector3.new(p.X, room.min.Y + 2, side[3] + side[2] * 5.5)
						local other = map:roomAt(beyond)
						if other and other ~= room and inside(beyond, 0) and (not best or d < best.d) then
							best = { d = d, at = beyond, from = id, to = other.id }
						end
					end
				end
			end
		end
	end
	if best then
		probe(string.format("%s, lamps off, behind the wall of lit %s", best.to, best.from), best.at, { best.to })
		probe(string.format("the same spot with no lamp anywhere near (ambient only)"), best.at, { best.to, best.from })
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
local statePresets = {}
for name, st in STATES do
	statePresets[name] = presetFor(st)
end

fs.writeFile(out, serde.encode("json", {
	seed = seed,
	room = "G_west",
	min = v3(lo),
	max = v3(hi),
	parts = parts,
	lights = lights,
	presets = presets,
	statePresets = statePresets,
	envDiffuse = LightingService.Base.EnvironmentDiffuseScale,
	probes = probes,
	views = {
		{ name = "corridor", eye = { 8, floorY + 5.3, 44 }, target = { 60, floorY + 4.2, 44 } },
		{ name = "G-02", eye = { 70, floorY + 5.3, 34 }, target = { 44, floorY + 3, 8 } },
	},
}))
print(string.format("seed %d: %d parts, %d lights, %d probes -> %s", seed, #parts, #lights, #probes, out))
