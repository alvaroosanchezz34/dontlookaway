--[[
	Visual audit (Lune).
	Builds the building for one seed and reports what a player actually sees:
	part counts per folder, lights by class / shadow casting, materials and
	MaterialVariants in use, architectural detail per room. Used before and after
	visual passes to compare real numbers (it does not render anything).

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/visual_audit.luau build/test.rbxlx [seed]
]]

local env = require("./lib/env")
local process = require("@lune/process")
local roblox = env.roblox
local game = env.game
local requireModule = env.requireModule
local Instance = roblox.Instance

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local MapBuilder = requireModule(Server.Map.MapBuilder)

local seed = tonumber(process.args[2]) or 8919
local holder = Instance.new("Folder")
holder.Parent = env.workspace
local map = MapBuilder.build(seed, holder)

local function count(root)
	local parts, lights, shadowLights, byClass, mats, variants = 0, 0, 0, {}, {}, {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local m = d.Material.Name
			mats[m] = (mats[m] or 0) + 1
			if d.MaterialVariant ~= "" then
				variants[d.MaterialVariant] = (variants[d.MaterialVariant] or 0) + 1
			end
		elseif d:IsA("Light") then
			lights += 1
			byClass[d.ClassName] = (byClass[d.ClassName] or 0) + 1
			if d.Shadows then
				shadowLights += 1
			end
		end
	end
	return parts, lights, shadowLights, byClass, mats, variants
end

local function sorted(t)
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return t[a] > t[b]
	end)
	local out = {}
	for _, k in keys do
		table.insert(out, string.format("%s=%d", k, t[k]))
	end
	return table.concat(out, " ")
end

print(string.format("seed %d", seed))
for _, f in map.Root:GetChildren() do
	local parts, lights, shadows = count(f)
	print(string.format("  %-10s parts %6d  lights %4d (shadows %d)", f.Name, parts, lights, shadows))
end
local parts, lights, shadows, byClass, mats, variants = count(map.Root)
print(string.format("TOTAL parts %d  lights %d  shadow-casting %d", parts, lights, shadows))
print("lights by class: " .. sorted(byClass))
print("materials: " .. sorted(mats))
print("variants: " .. sorted(variants))
local fixtures = 0
for _, room in map.Rooms do
	fixtures += #room.fixtures
end
print(string.format("rooms %d  fixtures %d  doors %d", (function()
	local n = 0
	for _ in map.Rooms do
		n += 1
	end
	return n
end)(), fixtures, #map.Doors))
local detail = map.Root:FindFirstChild("Detail")
if detail then
	local per = {}
	for _, d in detail:GetDescendants() do
		if d:IsA("BasePart") then
			local key = d.Name
			per[key] = (per[key] or 0) + 1
		end
	end
	print("detail parts by name: " .. sorted(per))
end
