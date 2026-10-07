--[[
	Map geometry audit (Lune).
	Builds the building for several seeds and runs the GeometryValidator on each,
	printing every issue grouped by kind and prop.

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/validate_map.luau build/test.rbxlx [seedCount] [verbose]
]]

local env = require("./lib/env")
local process = require("@lune/process")
local roblox = env.roblox
local game = env.game
local requireModule = env.requireModule
local Instance = roblox.Instance

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local GeometryValidator = requireModule(Server.Map.GeometryValidator)

local seedCount = tonumber(process.args[2]) or 6
local verbose = process.args[3] == "verbose"
local totals = {}
local byName = {}
local examples = {}
local total = 0
for i = 1, seedCount do
	local seed = 1000 + i * 7919
	local holder = Instance.new("Folder")
	holder.Parent = env.workspace
	local map = MapBuilder.build(seed, holder)
	local report = GeometryValidator.run(map)
	print(string.format("seed %d: %s", seed, GeometryValidator.summary(report)))
	for _, issue in report.issues do
		total += 1
		totals[issue.kind] = (totals[issue.kind] or 0) + 1
		local k = issue.kind .. " " .. issue.name
		byName[k] = (byName[k] or 0) + 1
		examples[k] = examples[k] or {}
		if #examples[k] < (if verbose then 6 else 2) then
			table.insert(examples[k], string.format("%s [%s] %s @ %.1f,%.1f,%.1f", issue.room or "?", issue.severity, issue.detail, issue.position.X, issue.position.Y, issue.position.Z))
		end
	end
	holder:Destroy()
end
print("\n== by kind")
for k, n in totals do
	print(k, n)
end
print("\n== by prop")
local keys = {}
for k in byName do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	return byName[a] > byName[b]
end)
for _, k in keys do
	print(string.format("%4d  %s", byName[k], k))
	for _, e in examples[k] do
		print("        " .. e)
	end
end
print("\nTOTAL ISSUES", total)
process.exit(if total == 0 then 0 else 1)
