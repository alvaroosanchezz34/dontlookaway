--[[
	Audit a model saved from Roblox Studio before it enters the game
	(tools/lib/asset_audit.luau). Nothing in the file is run.

	  In Studio: insert the asset into an EMPTY place (never the game's),
	  select it, right-click > Save to File... (.rbxm), then:

	    lune run tools/audit_asset.luau path/to/model.rbxm [report.md] [--strip stripped.rbxm]

	Prints the report (and writes it to report.md if given). --strip writes a
	copy with every script removed: the geometry, materials and sounds only.
	Exit code 2 when the verdict is REJECT.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local AssetAudit = require("./lib/asset_audit")

local args = process.args
local input = args[1]
if not input then
	print("usage: lune run tools/audit_asset.luau model.rbxm [report.md] [--strip out.rbxm]")
	process.exit(1)
end
local reportPath, stripPath = nil, nil
local i = 2
while i <= #args do
	if args[i] == "--strip" then
		stripPath = args[i + 1]
		i += 2
	else
		reportPath = args[i]
		i += 1
	end
end

local roots = roblox.deserializeModel(fs.readFile(input))
local report = AssetAudit.audit(roots)
local name = string.match(input, "[^/\\]+$") or input
local text = AssetAudit.format(report, name)
print(text)
if reportPath then
	fs.writeFile(reportPath, text)
end
if stripPath then
	fs.writeFile(stripPath, roblox.serializeModel(AssetAudit.strip(roots)))
	print("stripped copy (no scripts) -> " .. stripPath)
end
if AssetAudit.verdict(report) == "REJECT" then
	process.exit(2)
end
