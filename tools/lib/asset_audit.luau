--[[
	asset_audit: inspects a model saved from Roblox Studio (.rbxm / .rbxmx)
	before it goes anywhere near the game. Nothing in the file is executed:
	scripts are read as text.

	  audit(instances) -> report
	  strip(instances) -> instances without any script (a geometry-only copy)
	  format(report, name) -> markdown

	What it reports
	  * every script (class, path, disabled, lines) and what it does that a
	    decorative model has no reason to do: require(<asset id>), loadstring,
	    getfenv/setfenv, HTTP, InsertService, purchase prompts, teleports,
	    kicks, new remotes, writes to _G / shared, DataStores, MessagingService,
	    and signs of obfuscation (escape-coded strings, string.char chains,
	    very long lines, base64-sized blobs, l/I/1 identifiers)
	  * every external asset it depends on (meshes, textures, sounds,
	    animations, images), by id
	  * what it costs: parts by class, MeshParts, unions, colliding and
	    unanchored parts, lights (and how many cast shadows), particles,
	    sounds, materials, its size

	A clean report is not a guarantee: it means none of these patterns was
	found in the scripts this file contains. Code fetched at run time from
	elsewhere (a required asset) is not in the file and cannot be read here.
]]

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local AssetAudit = {}

export type Finding = { severity: string, rule: string, detail: string }

-- patterns, severity and why it matters
local RULES: { { pattern: string, severity: string, rule: string, why: string } } = {
	{ pattern = "require%s*%(%s*%d%d%d%d+", severity = "HIGH", rule = "require-by-id", why = "loads code from another asset at run time (the classic backdoor)" },
	{ pattern = "require%s*%(%s*tonumber", severity = "HIGH", rule = "require-by-id", why = "require of a computed asset id" },
	{ pattern = "loadstring", severity = "HIGH", rule = "loadstring", why = "runs code built from a string" },
	{ pattern = "getfenv", severity = "HIGH", rule = "fenv", why = "reads or rewrites script environments" },
	{ pattern = "setfenv", severity = "HIGH", rule = "fenv", why = "reads or rewrites script environments" },
	{ pattern = "HttpService", severity = "HIGH", rule = "http", why = "talks to servers outside Roblox" },
	{ pattern = "PostAsync", severity = "HIGH", rule = "http", why = "sends data out of the game" },
	{ pattern = "RequestAsync", severity = "HIGH", rule = "http", why = "sends data out of the game" },
	{ pattern = "InsertService", severity = "HIGH", rule = "insert", why = "inserts more assets at run time" },
	{ pattern = "LoadAsset", severity = "HIGH", rule = "insert", why = "inserts more assets at run time" },
	{ pattern = "PromptPurchase", severity = "HIGH", rule = "purchase", why = "prompts players to buy something" },
	{ pattern = "PromptProductPurchase", severity = "HIGH", rule = "purchase", why = "prompts players to buy something" },
	{ pattern = "PromptGamePassPurchase", severity = "HIGH", rule = "purchase", why = "prompts players to buy something" },
	{ pattern = "TeleportService", severity = "HIGH", rule = "teleport", why = "moves players to another place" },
	{ pattern = ":Kick%s*%(", severity = "HIGH", rule = "kick", why = "removes players from the server" },
	{ pattern = "DataStoreService", severity = "HIGH", rule = "datastore", why = "reads or writes saved data" },
	{ pattern = "MessagingService", severity = "HIGH", rule = "messaging", why = "talks to other servers" },
	{ pattern = "_G%s*[%.%[]", severity = "MEDIUM", rule = "globals", why = "uses the shared global table (_G)" },
	{ pattern = "shared%s*[%.%[]", severity = "MEDIUM", rule = "globals", why = "uses the shared global table (shared)" },
	{ pattern = "Instance%.new%s*%(%s*[\"']Remote", severity = "HIGH", rule = "new-remote", why = "creates a RemoteEvent/Function (a door into the server)" },
	{ pattern = "ServerScriptService", severity = "MEDIUM", rule = "server-services", why = "reaches into server code" },
	{ pattern = "ServerStorage", severity = "MEDIUM", rule = "server-services", why = "reaches into server storage" },
	{ pattern = "PlayerAdded", severity = "MEDIUM", rule = "players", why = "acts on every player who joins" },
	{ pattern = "MarketplaceService", severity = "MEDIUM", rule = "marketplace", why = "uses purchases / product info" },
	{ pattern = "Chat", severity = "LOW", rule = "chat", why = "uses chat" },
	{ pattern = "%.Touched", severity = "LOW", rule = "touched", why = "reacts to touches" },
}

local function escapeDensity(src: string): number
	local n = 0
	for _ in string.gmatch(src, "\\%d%d?%d?") do
		n += 1
	end
	return n
end

local function obfuscation(src: string): { Finding }
	local out = {}
	local escapes = escapeDensity(src)
	if escapes >= 40 then
		table.insert(out, { severity = "HIGH", rule = "obfuscation", detail = escapes .. " escape-coded characters (\\ddd): text hidden as numbers" })
	end
	local chars = 0
	for args in string.gmatch(src, "string%.char%s*%(([^%)]*)%)") do
		local _, commas = string.gsub(args, ",", ",")
		chars += commas + 1
	end
	if chars >= 30 then
		table.insert(out, { severity = "HIGH", rule = "obfuscation", detail = chars .. " characters built with string.char" })
	end
	local longest = 0
	for line in string.gmatch(src, "[^\n]+") do
		longest = math.max(longest, #line)
	end
	if longest >= 1000 then
		table.insert(out, { severity = "HIGH", rule = "obfuscation", detail = "a line of " .. longest .. " characters" })
	end
	if string.find(src, string.rep("[%w%+/=]", 200)) then
		table.insert(out, { severity = "MEDIUM", rule = "obfuscation", detail = "a 200+ character unbroken blob (base64-sized)" })
	end
	if string.find(src, "[lI1][lI1][lI1][lI1][lI1][lI1][lI1][lI1]") then
		table.insert(out, { severity = "HIGH", rule = "obfuscation", detail = "identifiers made of l / I / 1 (an obfuscator's signature)" })
	end
	return out
end

local function path(inst: any): string
	local parts = {}
	local i = inst
	while i do
		table.insert(parts, 1, i.Name)
		i = i.Parent
	end
	return table.concat(parts, ".")
end

-- every asset-id-like string on an instance
local ASSET_PROPS = {
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	FileMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	Sound = { "SoundId" },
	Animation = { "AnimationId" },
	ParticleEmitter = { "Texture" },
	Beam = { "Texture" },
	Trail = { "Texture" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" },
	MaterialVariant = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" },
	Shirt = { "ShirtTemplate" },
	Pants = { "PantsTemplate" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
}

local function assetRefs(inst: any): { { prop: string, value: string } }
	local out = {}
	local props = ASSET_PROPS[inst.ClassName]
	if not props then
		return out
	end
	-- current Studio files store these as Content properties (TextureContent,
	-- MeshContent, ColorMapContent, ...); older ones as the plain name
	local seen = {}
	for _, p in props do
		local base = string.gsub(string.gsub(p, "Id$", ""), "ID$", "")
		for _, name in { p, p .. "Content", base .. "Content" } do
			local ok, v = pcall(function()
				return inst[name]
			end)
			if ok and v ~= nil then
				local s = tostring(v)
				local uri = string.match(s, "Uri=([^%)]+)") or s
				if uri ~= "" and uri ~= "nil" and not string.find(uri, "^Content%(") and not seen[uri] then
					seen[uri] = true
					table.insert(out, { prop = name, value = uri })
				end
			end
		end
	end
	return out
end

local function idOf(s: string): string?
	return string.match(s, "rbxassetid://(%d+)") or string.match(s, "[?&]id=(%d+)") or (if string.match(s, "^%d+$") then s else nil)
end

local function isScript(inst: any): boolean
	return inst:IsA("LuaSourceContainer")
end

function AssetAudit.audit(roots: { any })
	local report = {
		scripts = {} :: { any },
		findings = {} :: { Finding },
		assets = {} :: { [string]: { string } },
		external = {} :: { string },
		counts = { instances = 0, parts = 0, meshParts = 0, unions = 0, colliding = 0, unanchored = 0, lights = 0, shadowLights = 0, particles = 0, sounds = 0, scripts = 0 },
		classes = {} :: { [string]: number },
		materials = {} :: { [string]: number },
		size = nil :: Vector3?,
	}
	local lo, hi = nil, nil
	local function visit(inst: any)
		report.counts.instances += 1
		report.classes[inst.ClassName] = (report.classes[inst.ClassName] or 0) + 1
		if isScript(inst) then
			report.counts.scripts += 1
			local okSrc, src = pcall(function()
				return inst.Source
			end)
			src = if okSrc and type(src) == "string" then src else ""
			local okDis, disabled = pcall(function()
				return inst.Disabled
			end)
			local entry = { class = inst.ClassName, path = path(inst), lines = select(2, string.gsub(src, "\n", "\n")) + 1, disabled = okDis and disabled == true, findings = {} }
			for _, r in RULES do
				if string.find(src, r.pattern) then
					table.insert(entry.findings, { severity = r.severity, rule = r.rule, detail = r.why })
				end
			end
			for _, f in obfuscation(src) do
				table.insert(entry.findings, f)
			end
			-- literal asset ids inside code (things it may fetch)
			for id in string.gmatch(src, "rbxassetid://(%d+)") do
				table.insert(entry.findings, { severity = "LOW", rule = "code-asset", detail = "uses asset " .. id .. " from code" })
			end
			table.insert(report.scripts, entry)
			for _, f in entry.findings do
				table.insert(report.findings, { severity = f.severity, rule = f.rule, detail = entry.path .. ": " .. f.detail })
			end
		end
		if inst:IsA("BasePart") then
			report.counts.parts += 1
			if inst:IsA("MeshPart") then
				report.counts.meshParts += 1
			elseif inst:IsA("UnionOperation") then
				report.counts.unions += 1
			end
			if inst.CanCollide then
				report.counts.colliding += 1
			end
			if not inst.Anchored then
				report.counts.unanchored += 1
			end
			local mat = inst.Material.Name
			report.materials[mat] = (report.materials[mat] or 0) + 1
			local cf, size = inst.CFrame, inst.Size
			local half = size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						lo = if lo then lo:Min(p) else p
						hi = if hi then hi:Max(p) else p
					end
				end
			end
		elseif inst:IsA("Light") then
			report.counts.lights += 1
			if inst.Shadows then
				report.counts.shadowLights += 1
			end
		elseif inst:IsA("ParticleEmitter") then
			report.counts.particles += 1
		elseif inst:IsA("Sound") then
			report.counts.sounds += 1
		end
		for _, ref in assetRefs(inst) do
			local id = idOf(ref.value)
			local key = id or ref.value
			report.assets[key] = report.assets[key] or {}
			table.insert(report.assets[key], path(inst) .. "." .. ref.prop)
			if not id and not string.match(ref.value, "^rbxasset://") then
				table.insert(report.external, path(inst) .. "." .. ref.prop .. " = " .. ref.value)
			end
		end
		for _, child in inst:GetChildren() do
			visit(child)
		end
	end
	for _, root in roots do
		visit(root)
	end
	if lo and hi then
		report.size = hi - lo
	end
	if report.counts.scripts > 0 then
		table.insert(report.findings, { severity = "MEDIUM", rule = "has-scripts", detail = report.counts.scripts .. " script(s): a decorative model should not need any (use the stripped copy)" })
	end
	if report.counts.unanchored > 0 then
		table.insert(report.findings, { severity = "LOW", rule = "physics", detail = report.counts.unanchored .. " unanchored part(s): they will fall or be pushed" })
	end
	if report.counts.shadowLights > 0 then
		table.insert(report.findings, { severity = "LOW", rule = "shadow-lights", detail = report.counts.shadowLights .. " light(s) with shadows: costly when repeated (the game budgets its own)" })
	end
	return report
end

-- The verdict the report supports (never "safe": "no pattern found").
function AssetAudit.verdict(report): string
	local worst = "NONE"
	for _, f in report.findings do
		if f.severity == "HIGH" then
			return "REJECT"
		elseif f.severity == "MEDIUM" then
			worst = "MEDIUM"
		end
	end
	if worst == "MEDIUM" then
		return "REVIEW"
	end
	return "NO-PATTERN-FOUND"
end

-- A copy without any script (the original is untouched).
function AssetAudit.strip(roots: { any }): { any }
	local out = {}
	for _, root in roots do
		if not root:IsA("LuaSourceContainer") then
			local copy = root:Clone()
			local doomed = {}
			for _, d in copy:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					table.insert(doomed, d)
				end
			end
			for _, d in doomed do
				d:Destroy()
			end
			table.insert(out, copy)
		end
	end
	return out
end

function AssetAudit.format(report, name: string): string
	local lines = {}
	local function add(s: string)
		table.insert(lines, s)
	end
	add("# Asset audit: " .. name)
	add("")
	add("**Verdict: " .. AssetAudit.verdict(report) .. "** (REJECT = a high-risk pattern; REVIEW = scripts or medium findings; NO-PATTERN-FOUND = none of the checked patterns, not a guarantee)")
	add("")
	local c = report.counts
	add(string.format("- Instances %d · parts %d (MeshParts %d, unions %d) · colliding %d · unanchored %d", c.instances, c.parts, c.meshParts, c.unions, c.colliding, c.unanchored))
	add(string.format("- Lights %d (%d with shadows) · particles %d · sounds %d · scripts %d", c.lights, c.shadowLights, c.particles, c.sounds, c.scripts))
	if report.size then
		add(string.format("- Size %.1f × %.1f × %.1f studs", report.size.X, report.size.Y, report.size.Z))
	end
	local mats = {}
	for m, n in report.materials do
		table.insert(mats, m .. " " .. n)
	end
	table.sort(mats)
	if #mats > 0 then
		add("- Materials: " .. table.concat(mats, ", "))
	end
	add("")
	add("## Findings")
	if #report.findings == 0 then
		add("None.")
	end
	local order = { HIGH = 1, MEDIUM = 2, LOW = 3 }
	local sorted = table.clone(report.findings)
	table.sort(sorted, function(a, b)
		return (order[a.severity] or 9) < (order[b.severity] or 9)
	end)
	for _, f in sorted do
		add(string.format("- **%s** `%s` %s", f.severity, f.rule, f.detail))
	end
	add("")
	add("## Scripts")
	if #report.scripts == 0 then
		add("None.")
	end
	for _, s in report.scripts do
		add(string.format("- %s `%s` (%d lines%s)", s.class, s.path, s.lines, if s.disabled then ", disabled" else ""))
	end
	add("")
	add("## External assets it depends on")
	local ids = {}
	for id, users in report.assets do
		table.insert(ids, string.format("- `%s` ← %s", id, table.concat(users, ", ")))
	end
	table.sort(ids)
	if #ids == 0 then
		add("None.")
	end
	for _, l in ids do
		add(l)
	end
	for _, e in report.external do
		add("- non-Roblox reference: " .. e)
	end
	return table.concat(lines, "\n") .. "\n"
end

return AssetAudit
