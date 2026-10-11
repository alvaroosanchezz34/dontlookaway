--[[
	Runtime test harness (Lune).

	Loads the built place file, executes the REAL server modules (map builder,
	furnisher, props, art, objective planning, puzzle setup, every anomaly
	definition, reality ops) inside a Lune DataModel and checks invariants:
	  * the building builds for many seeds without errors
	  * every room is furnished, has spawn spots, puzzle fixtures exist
	  * the objective planner always places every required item (solvable)
	  * every anomaly definition produces candidates and valid, revertible ops
	Engine-only features (physics, rendering, networking) are stubbed.

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/runtime_test.luau build/test.rbxlx
]]

local env = require("./lib/env")
local roblox = env.roblox
local stdio = require("@lune/stdio")
local process = require("@lune/process")
local task = require("@lune/task")
local game = env.game
local workspace = env.workspace
local requireModule = env.requireModule
local makeSignal = env.makeSignal
local syncPositions = env.syncPositions
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

------------------------------------------------------------------------------------
-- Test helpers
------------------------------------------------------------------------------------

local failures = 0
local checks = 0

local function check(cond, message)
	checks += 1
	if not cond then
		failures += 1
		stdio.write(stdio.color("red") .. "FAIL " .. stdio.color("reset") .. message .. "\n")
	end
end

local function section(name)
	stdio.write(stdio.color("cyan") .. "== " .. name .. stdio.color("reset") .. "\n")
end

local SSS = game:GetService("ServerScriptService")
local Server = SSS:FindFirstChild("Server")
local RS = game:GetService("ReplicatedStorage")

------------------------------------------------------------------------------------
-- 1. Shared modules load
------------------------------------------------------------------------------------

section("shared modules")
for _, m in RS.Shared:GetDescendants() do
	if m:IsA("ModuleScript") and m.Name ~= "Net" and m.Name ~= "SoundFactory" then
		local ok, err = pcall(requireModule, m)
		check(ok, "require " .. m:GetFullName() .. ": " .. tostring(err))
	end
end

local JournalCatalog = requireModule(RS.Shared.Catalog.JournalCatalog)
check(JournalCatalog.Count >= 40, "at least 40 anomalies in the journal")
local AudioLibrary = requireModule(RS.Shared.Config.AudioLibrary)
local soundCount = 0
for key, def in AudioLibrary.Sounds do
	soundCount += 1
	check(type(def.id) == "string" and def.id:match("^rbxasset"), "sound id for " .. key)
	for _, e in def.effects or {} do
		local ok, inst = pcall(Instance.new, e[1])
		check(ok, "sound effect class " .. tostring(e[1]))
		if ok then
			for prop, value in e[2] do
				local okSet, err = pcall(function()
					inst[prop] = value
				end)
				check(okSet, key .. ": " .. e[1] .. "." .. prop .. " " .. tostring(err))
			end
		end
	end
end
print(string.format("  %d sounds validated", soundCount))

------------------------------------------------------------------------------------
-- 2. Map builds for many seeds
------------------------------------------------------------------------------------

section("map builder")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local Layout = requireModule(Server.Map.Layout)
local maps = {}
for _, seed in { 1, 42, 1337, 99991, 123456 } do
	local holder = Instance.new("Folder")
	holder.Name = "Seed" .. seed
	holder.Parent = workspace
	local t0 = os.clock()
	local ok, map = pcall(MapBuilder.build, seed, holder)
	check(ok, "build seed " .. seed .. ": " .. tostring(map))
	if ok then
		maps[seed] = map
		local parts = 0
		local lights = 0
		for _, d in map.Root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				local p = d.CFrame.Position
				check(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN CFrame on " .. d:GetFullName())
				check(d.Size.X > 0 and d.Size.Y > 0 and d.Size.Z > 0, "bad size on " .. d:GetFullName())
			elseif d:IsA("Light") then
				lights += 1
			end
		end
		local rooms, spotless = 0, {}
		for id, room in map.Rooms do
			rooms += 1
			if #room.floorSpots == 0 and room.kind ~= "stairs" then
				table.insert(spotless, id)
			end
			check(room.folder ~= nil, "room furnished: " .. id)
		end
		check(rooms == 34, "34 rooms, got " .. rooms)
		local landmarks = {}
		for _, d in map.Root:GetDescendants() do
			if d:IsA("Model") and string.sub(d.Name, 1, 9) == "Landmark_" then
				landmarks[d.Name] = (landmarks[d.Name] or 0) + 1
			end
		end
		check(landmarks.Landmark_Floor == 3, "a floor landmark in every stairwell (" .. tostring(landmarks.Landmark_Floor) .. ")")
		check(landmarks.Landmark_Vale == 1 and landmarks.Landmark_Timeline == 1, "Vale portrait plaque and project timeline")
		check(#map.EntranceDoors == 2, "two entrance doors")
		check(map.ExitShutter ~= nil and map.ExitPanel ~= nil and map.EscapeZone ~= nil, "exit set piece")
		check(#map.CourtyardSpawns == 4, "four courtyard spawns")
		check(map.Expansions.CorridorStretch ~= nil and map.Expansions.BoilerExpand ~= nil, "expansions built")
		check(map.ShrinkWall ~= nil, "shrink wall built")
		check(#(map.Residents or {}) >= 1, "residents placed")
		-- geometry audit: nothing through walls, floating, blocking walkways or doors
		local GeometryValidator = requireModule(Server.Map.GeometryValidator)
		local report = GeometryValidator.run(map)
		check(#report.issues == 0, string.format("seed %d geometry: %s", seed, GeometryValidator.summary(report)))
		for i, issue in report.issues do
			if i <= 5 then
				print(string.format("    [%s] %s %s in %s: %s", issue.severity, issue.kind, issue.name, tostring(issue.room), issue.detail))
			end
		end
		for _, tag in { "FuseBox", "BreakerPanel", "Keypad", "SymbolCabinet", "OfferingTable", "TapeRecorder", "SecurityOverride", "BoardedPassage" } do
			local n = 0
			for _, d in map.Root:GetDescendants() do
				if d:HasTag(tag) then
					n += 1
				end
			end
			check(n == 1, string.format("seed %d: exactly one %s (got %d)", seed, tag, n))
		end
		local lamps = 0
		for _, d in map.Root:GetDescendants() do
			if d:HasTag("ClosetLamp") then
				lamps += 1
			end
		end
		check(lamps == 4, "four closet lamps, got " .. lamps)
		local doors = 0
		for _, rec in map.Doors do
			if rec.model and rec.model:HasTag("Door") then
				doors += 1
				check(typeof(rec.model:GetAttribute("OpenCFrame")) == "CFrame", "door open cframe " .. rec.id)
			end
		end
		-- room lookup works for every room cell
		for id, room in map.Rooms do
			local c = room.cells[1]
			local pos = Layout.cellToWorld(room.floorY, c.x, c.z) + Vector3.new(0, 3, 0)
			local found = map:roomAt(pos)
			check(found == room, "roomAt " .. id)
		end
		-- Visual Overhaul V2: architecture pass + shaped fixture lights
		local detail = map.Root:FindFirstChild("Detail")
		check(detail ~= nil, "detail folder built")
		if detail then
			local n, groups, solid = 0, 0, 0
			for _, d in detail:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
					if d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow then
						solid += 1
					end
				elseif d:IsA("Folder") and d:HasTag("DetailGroup") then
					groups += 1
					check(typeof(d:GetAttribute("Center")) == "Vector3", "detail group center " .. d.Name)
				end
			end
			check(n > 800, "architecture detail placed (" .. n .. " parts)")
			check(groups >= 25, "detail grouped per room (" .. groups .. ")")
			check(solid == 0, "detail is pure decoration (" .. solid .. " solid/queryable parts)")
			-- nothing intersects furniture
			local furnitureBoxes = {}
			for _, d in map.Root.Furniture:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					table.insert(furnitureBoxes, GeometryValidator.boxFrom(d.CFrame, d.Size))
				end
			end
			local hits = 0
			for _, d in detail:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "CeilingStain" then
					local box = GeometryValidator.boxFrom(d.CFrame, d.Size)
					for _, fb in furnitureBoxes do
						if box.max.X > fb.min.X and box.min.X < fb.max.X and box.max.Y > fb.min.Y and box.min.Y < fb.max.Y and box.max.Z > fb.min.Z and box.min.Z < fb.max.Z then
							if GeometryValidator.penetration(box, fb) > 0.01 then
								hits += 1
								if hits <= 3 then
									print("    detail in furniture: " .. d:GetFullName())
								end
							end
						end
					end
				end
			end
			check(hits == 0, string.format("seed %d: detail clear of furniture (%d hits)", seed, hits))
		end
		for id, room in map.Rooms do
			local before = room.wallSpotsBeforeDetail or 0
			check(#room.wallSpots >= math.min(before, 3), string.format("%s keeps anomaly wall spots (%d of %d)", id, #room.wallSpots, before))
		end
		local hardware, offsetsOk = 0, true
		for _, rec in map.Doors do
			if rec.model and rec.model:HasTag("Door") then
				for _, d in rec.model:GetChildren() do
					if d:IsA("BasePart") and d ~= rec.model.PrimaryPart then
						if typeof(d:GetAttribute("Offset")) ~= "CFrame" then
							offsetsOk = false
						end
						if d.Name == "KickPlate" then
							hardware += 1
						end
					end
				end
			end
		end
		check(hardware >= 60, "kick plates on the doors (" .. hardware .. ")")
		check(offsetsOk, "every door part moves with the panel (Offset)")
		local shaped, ratiosOk = 0, true
		for _, room in map.Rooms do
			for _, f in room.fixtures do
				for _, l in f:GetDescendants() do
					if l:IsA("Light") then
						if type(l:GetAttribute("Ratio")) ~= "number" then
							ratiosOk = false
						end
						if l:GetAttribute("Main") then
							shaped += 1
						end
					end
				end
			end
		end
		check(ratiosOk, "every fixture light has its brightness share")
		check(shaped >= 60, "shaped main lights on troffers and pendants (" .. shaped .. ")")
		print(string.format("  seed %d: %d parts, %d lights, %d rooms, %d doors, %.2fs, rooms w/o free floor: %s", seed, parts, lights, rooms, doors, os.clock() - t0, table.concat(spotless, ",")))
	end
end

do
	-- the same seed builds the same detail, part for part
	local function signature(seed)
		local holder = Instance.new("Folder")
		holder.Parent = workspace
		local map = MapBuilder.build(seed, holder)
		local n, sum = 0, 0
		for _, d in map.Root.Detail:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
				local p = d.CFrame.Position
				sum += p.X * 0.37 + p.Y * 0.11 + p.Z * 0.53
			end
		end
		holder:Destroy()
		return n, math.floor(sum * 100)
	end
	local n1, s1 = signature(4242)
	local n2, s2 = signature(4242)
	check(n1 == n2 and s1 == s2, string.format("architecture deterministic (%d/%d parts, %d/%d)", n1, n2, s1, s2))
end

section("resident evil quality pass")
do
	local RS = game:GetService("ReplicatedStorage")
	local AssetIds = requireModule(RS.Shared.Config.AssetIds)
	local LightingService = requireModule(Server.Services.LightingService)
	-- lighting profiles: NORMAL is the reference; old names still resolve
	for _, name in { "NORMAL", "EMERGENCY", "BLACKOUT", "CINEMATIC" } do
		check(LightingService.Presets[name] ~= nil, "lighting profile " .. name)
	end
	check(LightingService.Aliases.POWERED == "NORMAL" and LightingService.Aliases.DARK == "EMERGENCY", "old preset names alias the new profiles")
	local normal, blackout = LightingService.Presets.NORMAL, LightingService.Presets.BLACKOUT
	-- NORMAL: no ambient fill (only the fixtures light), a cold hard grade
	local amb = math.max(normal.Ambient.R, normal.Ambient.G, normal.Ambient.B) * 255
	-- NORMAL: a dim neutral grey floor (the fixtures do the lighting), a cold
	-- near-monochrome grade (docs/LIGHTING_MONOCHROME.md)
	local spread = (math.max(normal.Ambient.R, normal.Ambient.G, normal.Ambient.B) - math.min(normal.Ambient.R, normal.Ambient.G, normal.Ambient.B)) * 255
	check(amb <= 24 and spread <= 3, "NORMAL's ambient is a dim neutral grey (max channel " .. math.floor(amb + 0.5) .. ")")
	check(normal.cc.Contrast >= 0.1 and normal.cc.Saturation <= -0.4, "NORMAL grade is contrasted and desaturated (contrast " .. normal.cc.Contrast .. ", saturation " .. normal.cc.Saturation .. ")")
	-- ColorCorrection pivots contrast round mid grey: black on screen is
	-- 0.5 - (1 + contrast) / 2 + brightness. Inside, it is a deep grey, never 0
	for _, name in { "NORMAL", "EMERGENCY", "BREATH", "HEARTBEAT", "BLACKOUT", "CINEMATIC", "ESCAPE" } do
		local cc = LightingService.Presets[name].cc
		local black = 0.5 - (1 + cc.Contrast) / 2 + cc.Brightness
		check(black >= 0.02 and black <= 0.06, string.format("%s: black reads as a deep grey (%.3f)", name, black))
	end
	check(normal.cc.Contrast ~= blackout.cc.Contrast and normal.cc.TintColor ~= blackout.cc.TintColor, "a total blackout has a grade of its own")
	-- surfaces have real albedo: colour (linear) x texture mean of the main surfaces
	local Layout = requireModule(Server.Map.Layout)
	local function lin(c: number): number
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	for name, style in Layout.Styles do
		if name ~= "secret" then
			local c = style.ceiling[2]
			local y = 0.2126 * lin(c.R) + 0.7152 * lin(c.G) + 0.0722 * lin(c.B)
			check(y > 0.18, string.format("%s ceiling is not near-black (linear %.2f)", name, y))
		end
	end

	-- decals: with ids set they are placed with logic, with 0 none are
	local saved = table.clone(AssetIds.Decals)
	for k in AssetIds.Decals do
		AssetIds.Decals[k] = 1
	end
	local holder = Instance.new("Folder")
	holder.Parent = workspace
	local map = MapBuilder.build(4242, holder)
	local kinds = {}
	for _, d in map.Root:GetDescendants() do
		if d:IsA("Decal") then
			kinds[d.Name] = (kinds[d.Name] or 0) + 1
			local carrier = d.Parent :: BasePart
			check(carrier.Transparency == 1 and not carrier.CanCollide and not carrier.CanQuery and not carrier.CanTouch, "decal carrier is invisible decoration")
		end
	end
	for _, k in { "damp_rising", "water_streak", "grime_smudge", "ceiling_stain", "floor_dirt" } do
		check((kinds[k] or 0) > 0, string.format("decal %s placed (%d)", k, kinds[k] or 0))
	end
	-- reception renovation
	local rec = map.Rooms.G_r
	local desk, plate = nil, nil
	for _, p in rec.props do
		if p.Name == "ReceptionDesk" then
			desk = p
		end
	end
	check(desk ~= nil, "reception desk")
	plate = desk and desk:FindFirstChild("NamePlate")
	check(plate ~= nil and desk:FindFirstChild("CounterNose") ~= nil and desk:FindFirstChild("Stile") ~= nil, "desk has panels, nose and name plate")
	local panels, sconces = 0, 0
	local detail = map.Root.Detail:FindFirstChild("G_r")
	for _, d in (if detail then detail:GetDescendants() else {}) do
		if d.Name == "RaisedPanel" then
			panels += 1
		elseif d:IsA("Model") and d:GetAttribute("Room") == "G_r" and d:HasTag("Fixture") then
			sconces += 1
		end
	end
	check(panels >= 20, "reception wainscot panels (" .. panels .. ")")
	check(sconces >= 2, "reception wall sconces (" .. sconces .. ")")
	local dead = 0
	for _, f in rec.fixtures do
		if f:GetAttribute("Mode") == "dead" then
			dead += 1
		end
	end
	check(dead == 0, "no dead lamp in the reception")
	holder:Destroy()
	-- with every id at 0 (not uploaded) nothing is placed
	for k in AssetIds.Decals do
		AssetIds.Decals[k] = 0
	end
	local holder2 = Instance.new("Folder")
	holder2.Parent = workspace
	local plain = MapBuilder.build(4242, holder2)
	local n = 0
	for _, d in plain.Root:GetDescendants() do
		if d:IsA("Decal") and string.sub(d.Parent.Name, 1, 6) == "Decal_" then
			n += 1
		end
	end
	check(n == 0, "no decal placed while not uploaded (" .. n .. ")")
	holder2:Destroy()
	for k, v in saved do
		AssetIds.Decals[k] = v
	end
	for k, v in AssetIds.Decals do
		check(v > 0, "decal uploaded: " .. k)
	end
end

section("hero prop meshes (Blender pipeline)")
do
	local RS = game:GetService("ReplicatedStorage")
	local PropMeshes = requireModule(RS.Shared.PropMeshes)
	local Meta = requireModule(RS.Shared.Config.PropMeshMeta)
	local fs = require("@lune/fs")
	local names = {}
	for name, m in Meta do
		table.insert(names, name)
		check(m.size.X > 0 and m.size.Y > 0 and m.size.Z > 0, "mesh meta size " .. name)
		check(m.triangles > 0 and m.triangles < 20000, string.format("%s under Roblox's triangle limit (%d)", name, m.triangles))
		check(fs.isFile("assets/props/" .. name .. ".obj"), "mesh file " .. name)
		for _, map in { "color", "normal", "roughness" } do
			check(fs.isFile(string.format("assets/props/%s/%s_%s.png", name, name, map)), string.format("%s %s map", name, map))
		end
	end
	check(#names >= 13, "thirteen hero meshes (" .. #names .. ")")
	-- unnamed uploaded meshes are recognised by shape, even when the importer
	-- scaled them (x0.28 here, as a metres/studs mix-up would)
	local sizes, truth, n = {}, {}, 0
	for _, name in names do
		n += 1
		sizes[1000 + n] = Meta[name].size * 0.28
		truth[1000 + n] = name
	end
	local matched, right = PropMeshes.matchPool(sizes, {}), 0
	for _, m in matched do
		if truth[m.id] == m.name and m.distance < PropMeshes.MATCH_TOLERANCE then
			right += 1
		end
	end
	check(#matched == #names and right == #names, string.format("mesh pool recognised by shape (%d of %d)", right, #names))
	-- the closest other prop is far enough that a wrong pair is never accepted
	local margin = math.huge
	for _, a in names do
		for _, b in names do
			if a ~= b then
				margin = math.min(margin, PropMeshes.shapeDistance(Meta[a].size, Meta[b].size))
			end
		end
	end
	check(margin > 2 * PropMeshes.MATCH_TOLERANCE, string.format("prop shapes are distinct (closest pair %.3f)", margin))
	local AssetIdsMod = requireModule(RS.Shared.Config.AssetIds)
	local seen = {}
	for _, id in AssetIdsMod.PropMeshPool do
		check(type(id) == "number" and id > 0 and not seen[id], "mesh pool id " .. tostring(id))
		seen[id] = true
	end
	check(AssetIdsMod.PropMeshPreview == false, "mesh preview off in the committed config")
	-- stand-in templates the exact size of each mesh, then dress a real map
	for _, name in names do
		local stand = Instance.new("Part")
		PropMeshes.register(name, stand)
	end
	local holder = Instance.new("Folder")
	holder.Parent = workspace
	local map = MapBuilder.build(777, holder)
	local dressed = PropMeshes.dress(map.Root)
	check(dressed > 60, "props dressed with meshes (" .. dressed .. ")")
	check(PropMeshes.dress(map.Root) == 0, "dressing twice does nothing")
	local perName, misplaced = {}, 0
	for _, d in map.Root:GetDescendants() do
		local name = d:GetAttribute("MeshAsset")
		if name and d:GetAttribute("MeshDressed") then
			perName[name] = (perName[name] or 0) + 1
			local mesh = d:FindFirstChild("Mesh_" .. name)
			if d:IsA("BasePart") then
				-- a run (skirting, rail, cornice): the mesh sits next to its part,
				-- at the part's origin, stretched to the part's length
				mesh = nil
				local origin0 = d:GetAttribute("MeshOrigin")
				for _, sib in d.Parent:GetChildren() do
					if sib.Name == "Mesh_" .. name and (sib.CFrame.Position - (origin0 * CFrame.new(0, Meta[name].offset.Y, Meta[name].offset.Z)).Position).Magnitude < 0.05 then
						mesh = sib
					end
				end
			end
			check(mesh ~= nil, "mesh placed in " .. d:GetFullName())
			-- the mesh must sit where the parts it replaces were: its box inside
			-- their bounding box grown by a small tolerance, in the holder frame
			local origin = d:GetAttribute("MeshOrigin")
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			local hidden = 0
			local replaced = d:GetChildren()
			table.insert(replaced, d)
			for _, p in replaced do
				if p:IsA("BasePart") and p:GetAttribute("MeshHide") then
					hidden += 1
					check(p.Transparency == 1, "replaced part hidden: " .. p.Name)
					for _, sx in { -0.5, 0.5 } do
						for _, sy in { -0.5, 0.5 } do
							for _, sz in { -0.5, 0.5 } do
								local w = origin:PointToObjectSpace((p.CFrame * CFrame.new(p.Size.X * sx, p.Size.Y * sy, p.Size.Z * sz)).Position)
								lo = Vector3.new(math.min(lo.X, w.X), math.min(lo.Y, w.Y), math.min(lo.Z, w.Z))
								hi = Vector3.new(math.max(hi.X, w.X), math.max(hi.Y, w.Y), math.max(hi.Z, w.Z))
							end
						end
					end
				end
			end
			if mesh and hidden > 0 then
				local c = origin:PointToObjectSpace(mesh.CFrame.Position)
				local half = mesh.Size / 2
				local tol = 0.6
				local inside = c.X - half.X >= lo.X - tol and c.X + half.X <= hi.X + tol and c.Y - half.Y >= lo.Y - tol and c.Y + half.Y <= hi.Y + tol and c.Z - half.Z >= lo.Z - tol and c.Z + half.Z <= hi.Z + tol
				if not inside then
					misplaced += 1
					if misplaced <= 4 then
						print(string.format("    %s mesh box %s +- %s outside parts %s..%s", name, tostring(c), tostring(half), tostring(lo), tostring(hi)))
					end
				end
				if d:GetAttribute("MeshFollow") then
					check(typeof(mesh:GetAttribute("Offset")) == "CFrame", "following mesh has an Offset: " .. name)
				end
			end
		end
	end
	check(misplaced == 0, "every mesh sits on the parts it replaces (" .. misplaced .. " misplaced)")
	for _, name in { "ReceptionDesk", "DoorLeaf", "DoorCasing", "PendantLamp", "WallSconce", "Baseboard", "DadoRail", "Cornice" } do
		check((perName[name] or 0) > 0, string.format("%s used in the map (%d)", name, perName[name] or 0))
	end
	print("  dressed: " .. (function()
		local t = {}
		for k, v in perName do
			table.insert(t, k .. "=" .. v)
		end
		table.sort(t)
		return table.concat(t, " ")
	end)())
	-- the map still passes the geometry audit with meshes in it
	local GeometryValidator = requireModule(Server.Map.GeometryValidator)
	local report = GeometryValidator.run(map)
	check(#report.issues == 0, "geometry with meshes: " .. GeometryValidator.summary(report))
	for i, issue in report.issues do
		if i <= 4 then
			print(string.format("    [%s] %s %s in %s: %s", issue.severity, issue.kind, issue.name, tostring(issue.room), issue.detail))
		end
	end
	holder:Destroy()
	local tf = RS:FindFirstChild("PropMeshTemplates")
	if tf then
		tf:Destroy()
	end
end

------------------------------------------------------------------------------------
-- 3. Objective planning is always solvable
------------------------------------------------------------------------------------

section("custom assets (textures + sculpted Observer)")
do
	local Enum = env.roblox.Enum
	local RS = game:GetService("ReplicatedStorage")
	local AssetIds = requireModule(RS.Shared.Config.AssetIds)
	local MaterialLibrary = requireModule(RS.Shared.MaterialLibrary)
	local ObserverRig = requireModule(RS.Shared.ObserverRig)
	local MeshMeta = requireModule(RS.Shared.Config.ObserverMeshMeta)
	local MaterialService = game:GetService("MaterialService")
	-- the variants are written into the place by Rojo (tools/sync_assets.py)
	-- Visual Overhaul V2 textures are generated in the repo and wait for upload
	-- (0 ids): until then their parts render the built-in material.
	local fs = require("@lune/fs")
	-- textures generated in the repo that wait for their upload (0 ids)
	local PENDING = {}
	local uploaded = 0
	for key, entry in AssetIds.Materials do
		if entry.color > 0 then
			uploaded += 1
		else
			check(PENDING[key] == true, "texture uploaded: " .. key)
		end
	end
	check(MaterialLibrary.count() == uploaded, string.format("%d custom textures in MaterialService, got %d", uploaded, MaterialLibrary.count()))
	check(uploaded == 18, "all eighteen textures uploaded (" .. uploaded .. ")")
	for _, name in { "DLA_Wood", "DLA_Fabric", "DLA_Rust", "DLA_PeelingPaint", "DLA_WetConcrete", "DLA_Hardware" } do
		local v = MaterialService:FindFirstChild(name)
		check(v ~= nil and v:IsA("MaterialVariant"), "V2 variant in MaterialService: " .. name)
		-- Lune cannot read the map properties; check what sync_assets wrote
		local file = string.format("src/materials/%s.model.json", name)
		local src = if fs.isFile(file) then fs.readFile(file) else ""
		check(string.find(src, "ColorMap", 1, true) ~= nil and string.find(src, "NormalMap", 1, true) ~= nil and string.find(src, "RoughnessMap", 1, true) ~= nil, "V2 variant with its maps: " .. name)
	end
	for _, key in { "wood_aged", "fabric_worn", "metal_rusted", "paint_peeling", "concrete_wet", "metal_bare", "marble_tiles", "wallpaper_aged" } do
		for _, map in { "color", "normal", "roughness" } do
			check(fs.isFile(string.format("assets/textures/%s/%s_%s.png", key, key, map)), string.format("generated %s %s map", key, map))
		end
	end
	local plaster = MaterialService:FindFirstChild("DLA_Plaster")
	check(plaster ~= nil and plaster:IsA("MaterialVariant") and plaster.BaseMaterial == Enum.Material.Plaster, "plaster variant present")
	check(plaster ~= nil and plaster.StudsPerTile == 10, "plaster tiling")
	check(MaterialService:FindFirstChild(MaterialLibrary.Wallpaper) ~= nil and MaterialService:FindFirstChild(MaterialLibrary.CeilingTile) ~= nil, "named variants present")
	local okOverride, plasterName = pcall(function()
		return (MaterialService :: any).PlasterName
	end)
	check(not okOverride or plasterName == "DLA_Plaster", "plaster override set in the project")
	check(RS.Shared:FindFirstChild("ObserverSkin") ~= nil and RS.Shared.ObserverSkin:IsA("SurfaceAppearance"), "observer skin template present")
	local plain = ObserverRig.build(nil, { localCopy = true })
	check(plain:GetAttribute("Sculpted") ~= true, "plain rig until the meshes load")
	-- every built-in material with a custom texture gets it, part by part
	local box = Instance.new("Model")
	for _, mat in { Enum.Material.Plaster, Enum.Material.Carpet, Enum.Material.Neon } do
		local p = Instance.new("Part")
		p.Material = mat
		p.Parent = box
	end
	local named = Instance.new("Part")
	named.Material = Enum.Material.Plaster
	named.MaterialVariant = MaterialLibrary.Wallpaper
	named.Parent = box
	local dressedCount = MaterialLibrary.dress(box)
	check(dressedCount == 2, "dress textures plaster and carpet only (" .. tostring(dressedCount) .. ")")
	check(named.MaterialVariant == MaterialLibrary.Wallpaper, "a chosen variant is kept")
	-- the smooth Observer body: templates stand in for the uploaded meshes
	local folder = Instance.new("Folder")
	folder.Name = "ObserverMeshes"
	for name in MeshMeta do
		local mp = Instance.new("MeshPart")
		mp.Name = name
		mp.Parent = folder
	end
	folder.Parent = RS
	check(MeshMeta.FaceL == nil and MeshMeta.Head ~= nil, "the smooth body has no face halves")
	-- unnamed uploads are told apart by exact size (tolerance 0.06)
	local closest = math.huge
	for a, ma in MeshMeta do
		for b, mb in MeshMeta do
			if a ~= b then
				closest = math.min(closest, (ma.size - mb.size).Magnitude)
			end
		end
	end
	check(closest > 0.12, string.format("observer segments differ in size (closest %.2f)", closest))
	for name, meta in MeshMeta do
		check(fs.isFile("assets/observer/" .. name .. ".obj"), "observer mesh file " .. name)
		for _, map in { "color", "normal", "roughness" } do
			check(fs.isFile(string.format("assets/observer/%s/%s_%s.png", name, name, map)), string.format("observer %s baked %s map", name, map))
		end
		check(meta.triangles > 0 and meta.triangles < 20000, string.format("observer %s under the triangle limit (%d)", name, meta.triangles))
	end
	local rig = ObserverRig.build(CFrame.new(0, 0, 0), { localCopy = true })
	check(rig:GetAttribute("Sculpted") == true, "rig dressed with the smooth meshes")
	local meshes, visibleHard = 0, {}
	for _, d in rig:GetChildren() do
		if d:IsA("MeshPart") then
			meshes += 1
			local weld = d:FindFirstChildOfClass("WeldConstraint")
			check(weld ~= nil and weld.Part0 ~= nil and weld.Part0.Transparency == 1, "mesh welded to a hidden segment: " .. d.Name)
			check(not d.Anchored and d.Massless and not d.CanCollide and d.Reflectance == 0, "mesh is cosmetic and matte: " .. d.Name)
		elseif d:IsA("BasePart") and d.Transparency < 1 and not string.find(d.Name, "Eyeball") and d.Name ~= "Pupil" and d.Name ~= "Iris" then
			table.insert(visibleHard, d.Name)
		end
	end
	check(meshes == 16, "16 smooth meshes (both sides), got " .. meshes)
	check(#visibleHard == 0, "no hard-edged part left visible over the smooth body: " .. table.concat(visibleHard, ", "))
	check(ObserverRig.dress(rig) == false, "dressing twice does nothing")
	rig:Destroy()
	-- a segment whose mesh was not loaded (an upload of an older build is
	-- turned away by loadMeshes) keeps its part-built pieces, the rest is dressed
	folder:FindFirstChild("Head"):Destroy()
	local partial = ObserverRig.build(CFrame.new(0, 0, 0), { localCopy = true })
	check(partial:FindFirstChild("HeadMesh") == nil and partial:FindFirstChild("UpperTorsoMesh") ~= nil, "without its mesh the head stays part-built")
	check(partial:FindFirstChild("Head").Transparency == 0 and partial:FindFirstChild("Chin").Transparency == 0, "the part-built head and its chin stay visible")
	check(partial:FindFirstChild("Flank").Transparency == 1, "the torso's part details hide under its mesh")
	partial:Destroy()
	folder:Destroy()
end

------------------------------------------------------------------------------------
-- Round rules: the real services, with the services around them stubbed
------------------------------------------------------------------------------------

-- Stubs the Registry for one section and restores it afterwards.
local function withRegistry(stubs, fn)
	local Registry = requireModule(Server.Registry)
	local saved = {}
	for k, v in Registry do
		saved[k] = v
	end
	for k, v in stubs do
		Registry[k] = v
	end
	local ok, err = pcall(fn, Registry)
	check(ok, "section ran: " .. tostring(err))
	for k in Registry do
		Registry[k] = nil
	end
	for k, v in saved do
		Registry[k] = v
	end
end

local function noop() end

-- A player as far as the server services need one: a character with a root.
local function fakePlayer(userId: number, at: Vector3)
	local character = Instance.new("Model")
	character.Name = "Character" .. userId
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.CFrame = CFrame.new(at)
	rootPart.Position = at
	rootPart.Parent = character
	character.Parent = workspace
	return {
		UserId = userId,
		Name = "Tester" .. userId,
		DisplayName = "Tester" .. userId,
		Character = character,
		Parent = game,
		SetAttribute = noop,
		GetAttribute = noop,
	}
end

section("round rules: what the team needs is never lost with a player")
do
	local handlers = {}
	local inside = true
	withRegistry({
		InteractionService = { Register = function(_, kind, fn)
			handlers[kind] = fn
		end },
		AudioService = { Play2D = noop, PlayAt = noop, PlayAtFor = noop },
		AnomalyService = { OnFlashlight = noop, OnFalseItemTaken = noop },
		PlayerService = { IsAlive = function()
			return true
		end },
		MapService = { GetMap = function()
			return {
				isInsideBuilding = function()
					return inside
				end,
				roomAt = function()
					return if inside then { id = "G_a" } else nil
				end,
			}
		end },
	}, function()
		local Inventory = requireModule(Server.Services.InventoryService)
		Inventory:Init()
		local player = fakePlayer(9001, Vector3.new(20, 3, 20))
		Inventory:Reset(player, nil)
		local function take(id, at)
			local model = Inventory:SpawnPickup(id, CFrame.new(at))
			return handlers.Pickup(player, model:FindFirstChild("Hitbox"))
		end
		local function pickupsOf(id)
			local list = {}
			for _, m in Inventory:GetPickups() do
				if m:GetAttribute("ItemId") == id then
					table.insert(list, m)
				end
			end
			return list
		end
		local home = Vector3.new(60, 1, -40)
		check(take("MAINT_KEY", home) and take("FUSE", Vector3.new(5, 1, 5)) and take("FUSE", Vector3.new(6, 1, 5)) and take("BATTERY", Vector3.new(7, 1, 5)), "the carrier picks up a key, two fuses and a battery")
		check(#pickupsOf("MAINT_KEY") == 0, "the key is in a pocket, not on the floor")
		-- the carrier dies inside the building
		local dropped = Inventory:DropImportant(player, "died")
		check(dropped == 3, "the key and both fuses fall (" .. dropped .. ")")
		check(not Inventory:Has(player, "MAINT_KEY") and not Inventory:Has(player, "FUSE"), "nothing important stays with the dead")
		check(Inventory:Has(player, "BATTERY"), "a battery is personal: it is not dropped")
		local key = pickupsOf("MAINT_KEY")[1]
		local keyAt = key and key:GetAttribute("Home")
		check(key ~= nil, "a Maintenance Key pickup exists")
		if key then
			local body = key.PrimaryPart
			local flat = Vector3.new(body.CFrame.Position.X - 20, 0, body.CFrame.Position.Z - 20)
			check(flat.Magnitude < 3, string.format("it lies where its carrier fell (%.1f studs away)", flat.Magnitude))
			check(typeof(keyAt) == "CFrame" and (keyAt.Position - home).Magnitude < 0.01, "it remembers where it was first found")
		end
		check(#pickupsOf("FUSE") == 2, "both fuses lie there too")
		-- somebody takes the key again and dies outside the building: it goes home
		check(handlers.Pickup(player, key:FindFirstChild("Hitbox")), "the key can be picked up again")
		inside = false
		Inventory:DropImportant(player, "died")
		local back = pickupsOf("MAINT_KEY")[1]
		check(back ~= nil and (back.PrimaryPart.CFrame.Position - home).Magnitude < 1, "a key that cannot land where its carrier fell goes back to where it was found")
		inside = true
		-- a used fuse takes its home with it (no stale homes)
		check(take("FUSE", Vector3.new(8, 1, 8)) and Inventory:Remove(player, "FUSE", 1), "a fuse is used up")
		check(Inventory:DropImportant(player, "died") == 0, "a used-up fuse is not dropped again")
		for _, m in Inventory:GetPickups() do
			m:Destroy()
		end
		player.Character:Destroy()
	end)
end

section("round rules: the round is not lost on the way out")
do
	local escape, quotaMet = false, false
	withRegistry({
		RoundService = { IsEscape = function()
			return escape
		end },
		ObjectiveService = { GetState = function()
			return { locks = { ANOMALIES = quotaMet } }
		end },
	}, function()
		local Anomalies = requireModule(Server.Services.AnomalyService)
		local plain, tutorial = { spec = {} }, { spec = { noMiss = true } }
		check(Anomalies:CountsAsMissed(plain), "an anomaly nobody reported is a miss while the quota is open")
		check(not Anomalies:CountsAsMissed(tutorial), "a noMiss anomaly (the tutorial, the escape) is never a miss")
		quotaMet = true
		check(not Anomalies:CountsAsMissed(plain), "once the quota is met nothing more is missed")
		quotaMet, escape = false, true
		check(not Anomalies:CountsAsMissed(plain), "nothing is missed during the escape")
	end)
	-- the escape's own anomalies, and none from the director while escaping
	local roundSource = Server.Services.RoundService.Source
	check(string.find(roundSource, "ignoreVisibility = true, noMiss = true", 1, true) ~= nil, "the building's escape anomalies are never misses")
	local directorSource = Server.Services.HorrorDirector.Source
	check(string.find(directorSource, "story ~= Story.Escape and Registry.AnomalyService:GetActiveCount()", 1, true) ~= nil, "the director spawns no anomalies during the escape")
end

section("round rules: each ending says what really happened")
do
	local Enums = requireModule(RS.Shared.Enums)
	local Round = requireModule(Server.Services.RoundService)
	local E = Enums.Ending
	local personal, team = Round.EndingsFor({ [1] = { outcome = "LOCKED_IN" }, [2] = { outcome = "LOCKED_IN" } }, nil)
	check(team == E.LockedIn and personal[1] == E.LockedIn, "the shutter closing on everyone is LOCKED IN, not a catch (" .. tostring(team) .. ")")
	personal, team = Round.EndingsFor({ [1] = { outcome = "DEAD" }, [2] = { outcome = "LOCKED_IN" } }, nil)
	check(personal[1] == E.ObserverCaughtYou and personal[2] == E.LockedIn, "a catch and a shut-in each keep their own ending")
	check(team == E.LockedIn, "the night ended with the shutter")
	personal, team = Round.EndingsFor({ [1] = { outcome = "DEAD" } }, nil)
	check(team == E.ObserverCaughtYou and personal[1] == E.ObserverCaughtYou, "caught by it is still THE OBSERVER CAUGHT YOU")
	personal, team = Round.EndingsFor({ [1] = { outcome = "LOST" }, [2] = { outcome = "DEAD" } }, E.OutOfTime)
	check(team == E.OutOfTime and personal[1] == E.OutOfTime and personal[2] == E.ObserverCaughtYou, "running out of time is THE NIGHT RAN OUT, not a failed identification")
	personal, team = Round.EndingsFor({ [1] = { outcome = "LOST" } }, E.FailedToIdentify)
	check(team == E.FailedToIdentify and personal[1] == E.FailedToIdentify, "too many unseen changes is FAILED TO IDENTIFY")
	personal, team = Round.EndingsFor({ [1] = { outcome = "ESCAPED" }, [2] = { outcome = "LOCKED_IN" } }, nil)
	check(team == E.EscapedAlone and personal[1] == E.EscapedAlone and personal[2] == E.LockedIn, "one out, one shut in")
	-- the results screen and the collapse title know every ending
	local results = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.ResultsController.Source
	for _, id in E do
		check(string.find(results, "\t" .. id .. " = {", 1, true) ~= nil, "the results screen has words for " .. id)
	end
	local effects = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.EffectsController.Source
	check(string.find(effects, "OUT_OF_TIME", 1, true) ~= nil, "the collapse title tells running out of time apart")
	local death = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.DeathController.Source
	check(string.find(death, "lockedIn", 1, true) ~= nil, "being shut in has its own death sequence")
end

section("perception: one meaning of looking, one meaning of dark")
do
	local GameConfig = requireModule(RS.Shared.Config.GameConfig)
	local P = GameConfig.Perception
	check(GameConfig.Observer.WatchFOV == nil, "no second definition of the watch angle")
	-- the fallback screen is FOV 74 on a 16:9 window
	local half = math.deg(math.atan(math.tan(math.rad(GameConfig.Camera.DefaultFOV / 2)) * 16 / 9))
	check(math.abs(half - P.Screen) < 1, string.format("the fallback screen half-angle is the default view's (%.1f vs %d)", half, P.Screen))
	check(P.Screen + P.PeripheryMargin > P.Screen and P.Focus < P.Screen and P.Stare < P.Focus, "stare < focus < screen < periphery")
	local lightOn, glows = false, {}
	local viewer = fakePlayer(9101, Vector3.new(0, 3, 0))
	local look = { origin = Vector3.new(0, 5, 0), dir = Vector3.new(0, 0, -1), time = os.clock() }
	withRegistry({
		PlayerService = {
			GetAlive = function()
				return { viewer }
			end,
			GetLook = function()
				return look
			end,
			HasLineOfSight = function()
				return true
			end,
		},
		InventoryService = { IsLightOn = function()
			return lightOn
		end },
		EquipmentService = { GetGlowLights = function()
			return glows
		end },
		MapService = { GetMap = function()
			return nil
		end },
	}, function()
		local Players = requireModule(Server.Services.PlayerService)
		check(Players:ViewAngle(viewer, "screen") == P.Screen, "a client that never reported its view gets the fallback screen")
		check(Players:ViewAngle(viewer, "periphery") == P.Screen + P.PeripheryMargin, "the periphery is the screen plus its margin")
		check(Players:ViewAngle(viewer, "focus") == P.Focus and Players:ViewAngle(viewer, "stare") == P.Stare, "focus and stare are the named angles")
		local Lighting = requireModule(Server.Services.LightingService)
		workspace:SetAttribute("Power", true)
		check(not Lighting:IsDark(Vector3.new(0, 5, -30)), "with power and no blackout it is not dark")
		check(Lighting:IsLit(Vector3.new(0, 5, -30)), "where it is not dark, everything is lit")
		workspace:SetAttribute("Power", false)
		local ahead, aside = Vector3.new(0, 5, -30), Vector3.new(30, 5, 0)
		check(Lighting:IsDark(ahead), "without power the building is dark")
		check(not Lighting:IsLit(ahead), "in the dark, without a light, nothing is lit")
		lightOn = true
		check(Lighting:IsLit(ahead), "a flashlight beam lights what it points at")
		check(not Lighting:IsLit(aside), "but not what is beside it")
		check(not Lighting:IsLit(Vector3.new(0, 5, -(GameConfig.Flashlight.Range + 10))), "nor beyond its range")
		lightOn = false
		glows = { { position = aside + Vector3.new(4, 0, 0), range = 13 } }
		check(Lighting:IsLit(aside), "a glow stick lights what is around it")
		workspace:SetAttribute("Power", nil)
	end)
	viewer.Character:Destroy()
	-- every system asks the same question
	-- what can be seen: one rule (the director may still pace by the blackout)
	check(string.find(Server.Services.ObserverService.Source, "GetBlackout() >= 3", 1, true) == nil, "ObserverService has no darkness rule of its own")
	check(string.find(Server.Services.HorrorDirector.Source, "IsDark(victimRoot and victimRoot.Position)", 1, true) ~= nil, "the director asks LightingService where it is dark")
	local observer = Server.Services.ObserverService.Source
	check(string.find(observer, "\"screen\", 140, model) and canMakeOut(p, pt)", 1, true) ~= nil, "The Observer is only held by someone who can make it out")
end

section("the observer: its breath leaves time to turn")
do
	local GameConfig = requireModule(RS.Shared.Config.GameConfig)
	local D = GameConfig.Difficulty
	check(D.NORMAL.ReactionTime >= 1.2 and D.HARD.ReactionTime >= 0.9 and D.NIGHTMARE.ReactionTime >= 0.6, "at least 1.2 / 0.9 / 0.6 s between the breath and a catch")
	check(D.NORMAL.ReactionTime > D.HARD.ReactionTime and D.HARD.ReactionTime > D.NIGHTMARE.ReactionTime, "the warning shortens with difficulty")
	check(D.NORMAL.ObserverSpeed < D.HARD.ObserverSpeed and D.HARD.ObserverSpeed < D.NIGHTMARE.ObserverSpeed, "NORMAL has the slowest Observer")
	local src = Server.Services.ObserverService.Source
	check(string.find(src, "local warnRadius = reach + speed * reaction", 1, true) ~= nil, "it breathes one reaction time away at its current speed")
	check(string.find(src, "strikeAfter[p] = reaction +", 1, true) ~= nil, "and cannot strike before that time is up")
	for name, c in D do
		local warn = GameConfig.Observer.CatchDistance + 1.5 + c.ObserverSpeed * c.ReactionTime
		check(warn > 14, string.format("%s: it is heard further than before (%.1f studs, was 14)", name, warn))
	end
end

section("the collapse: its total blackout happens with or without power")
do
	local src = Server.Services.HorrorDirector.Source
	local body = string.match(src, "local function maybeBlackout%(%)(.-)\nend\n")
	check(body ~= nil, "maybeBlackout found")
	if body then
		check(string.find(body, "not Registry.LightingService:IsPowered() or", 1, true) == nil, "no power no longer cancels every blackout")
		check(string.find(body, "story == Story.Collapse and not totalBlackoutDone", 1, true) ~= nil, "without power only the collapse's total blackout runs")
	end
	local rules = RS.Shared.LightingRules.Source
	check(string.find(rules, "local emergencyOn = f.emergency and not (level >= 4 and frac < 0.5)", 1, true) ~= nil, "a total blackout over the emergency lighting still takes half the battery lamps")
end

section("scares: a fallen box lies on the floor, never in it")
do
	local SeededRandom = requireModule(RS.Shared.Util.SeededRandom)
	local Props = requireModule(Server.Map.Props)
	withRegistry({
		MapService = { GetMap = function()
			return { Doors = { { center = Vector3.new(40, 0, 40) } } }
		end },
		PlayerService = { GetAlive = function()
			return {}
		end },
	}, function()
		local Director = requireModule(Server.Services.HorrorDirector)
		local holder = Instance.new("Folder")
		holder.Parent = workspace
		local worst, fell = 0, 0
		for i = 1, 12 do
			local rng = SeededRandom.new(i, "box")
			local box = Props.box(holder, CFrame.new(i * 10, 2, 0) * CFrame.Angles(0, i * 0.5, 0), rng)
			syncPositions(box)
			local body = box:FindFirstChild("Body")
			local rest = Director.TippedBoxRest(box, body)
			check(rest ~= nil, "box " .. i .. " has somewhere to fall")
			if rest then
				box:PivotTo(rest)
				syncPositions(box)
				local s = body.Size / 2
				local low, high = math.huge, -math.huge
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local c = (body.CFrame * CFrame.new(s.X * x, s.Y * y, s.Z * z)).Position
							low, high = math.min(low, c.Y), math.max(high, c.Y)
						end
					end
				end
				worst = math.max(worst, math.abs(low - 2))
				fell = math.max(fell, math.abs((high - low) - 2 * s.Z))
			end
		end
		check(worst < 0.02, string.format("its lowest corner rests on the floor (off by %.3f studs)", worst))
		check(fell < 0.02, string.format("it lies on its side: its depth is now its height (off by %.3f)", fell))
		-- near a doorway it does not fall at all
		local rng = SeededRandom.new(99, "box")
		local box = Props.box(holder, CFrame.new(40, 0, 41), rng)
		syncPositions(box)
		check(Director.TippedBoxRest(box, box:FindFirstChild("Body")) == nil, "a box by a doorway stays standing")
		holder:Destroy()
	end)
	local src = Server.Services.HorrorDirector.Source
	check(string.find(src, "prop:PivotTo(cf * CFrame.new", 1, true) == nil, "no snap to a new pose")
	check(string.find(src, "not Registry.PlayerService:CanAnyoneSee({ body.Position }, \"screen\", 60)", 1, true) ~= nil, "it only falls where nobody has it on screen")
end

section("lighting: inside the building nothing is lighter than NORMAL")
do
	local Lighting = requireModule(Server.Services.LightingService)
	local P = Lighting.Presets
	local function lum(c)
		return (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) * 255
	end
	local normal = P.NORMAL
	for _, name in { "EMERGENCY", "BREATH", "HEARTBEAT", "BLACKOUT", "CINEMATIC", "ESCAPE" } do
		local p = P[name]
		check(lum(p.Ambient) <= lum(normal.Ambient) + 0.01, string.format("%s ambient is no brighter than NORMAL (%.1f vs %.1f)", name, lum(p.Ambient), lum(normal.Ambient)))
		check(p.ExposureCompensation <= normal.ExposureCompensation, name .. " exposure is no higher than NORMAL")
		check(p.atmosphere.Haze <= normal.atmosphere.Haze + 0.01, string.format("%s adds no haze to grey the distance (%.1f)", name, p.atmosphere.Haze))
	end
	-- blackouts with power are more macabre, not darker: NORMAL's light, a
	-- grade of their own; no power (EMERGENCY) is the one darker state
	for _, name in { "BREATH", "HEARTBEAT", "BLACKOUT" } do
		check(lum(P[name].Ambient) >= lum(normal.Ambient) - 0.01 and P[name].ExposureCompensation >= normal.ExposureCompensation, name .. " keeps NORMAL's light")
	end
	check(lum(P.EMERGENCY.Ambient) <= lum(normal.Ambient), "without power it is darker than any blackout")
	check(P.ESCAPE.cc.TintColor.R > P.ESCAPE.cc.TintColor.B, "the escape is tinted red")
	check(P.CINEMATIC.cc.Contrast >= normal.cc.Contrast and P.CINEMATIC.cc.Saturation <= normal.cc.Saturation, "a scripted moment is harder and colder than NORMAL")
	check(string.find(Server.Services.LightingService.Source, "never blind", 1, true) == nil, "no comment says the darkness is never blind")
end

section("light: the server's dark is the dark the players see")
do
	local LightingRules = requireModule(RS.Shared.LightingRules)
	local holder = Instance.new("Folder")
	holder.Parent = workspace
	local map = MapBuilder.build(42, holder)
	syncPositions(map.Root)
	withRegistry({
		MapService = { GetMap = function()
			return map
		end },
		PlayerService = { HasLineOfSight = function()
			return true
		end },
	}, function()
		local Lighting = requireModule(Server.Services.LightingService)
		-- a lit fixture in a lit building: right under it is not dark
		local room
		for _, r in map.Rooms do
			if r.kind ~= "corridor" and #r.fixtures > 0 then
				room = r
				break
			end
		end
		local fixture = room.fixtures[1]
		fixture:SetAttribute("Mode", "on")
		local under = fixture:GetPivot().Position - Vector3.new(0, 6, 0)
		workspace:SetAttribute("Power", true)
		workspace:SetAttribute("Blackout", 0)
		workspace:SetAttribute("BlackoutSeed", 7)
		check(LightingRules.evaluate(LightingRules.fixture(fixture), LightingRules.world(workspace), 0, { steady = true }), "the rules light a working lamp with power")
		check(not Lighting:IsDark(under), "under a lit lamp it is not dark")
		-- the same lamp dead (and its neighbours too): dark, even with power
		local saved = {}
		for _, r in map.Rooms do
			for _, f in r.fixtures do
				saved[f] = f:GetAttribute("Mode")
				f:SetAttribute("Mode", "dead")
			end
		end
		task.wait(0.35) -- IsDark keeps an answer for 0.3 s
		check(Lighting:IsDark(under), "under a dead lamp it is dark, power or not")
		for f, mode in saved do
			f:SetAttribute("Mode", mode)
		end
		-- a main-circuit lamp in a total blackout: dark
		local main
		for _, r in map.Rooms do
			for _, f in r.fixtures do
				if f:GetAttribute("Circuit") == "MAIN" and f:GetAttribute("Mode") ~= "dead" then
					main = f
				end
			end
		end
		workspace:SetAttribute("Blackout", 4)
		check(LightingRules.evaluate(LightingRules.fixture(main), LightingRules.world(workspace), 0, { steady = true }), "a total blackout with power keeps the lamps' current (it is macabre, not dark)")
		workspace:SetAttribute("Power", false)
		check(not LightingRules.evaluate(LightingRules.fixture(main), LightingRules.world(workspace), 0, { steady = true }), "without power a main-circuit lamp is out")
		workspace:SetAttribute("Power", true)
		workspace:SetAttribute("Blackout", 0)
		workspace:SetAttribute("Power", nil)
	end)
	holder:Destroy()
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.LightController.Source
	check(string.find(client, "LightingRules.evaluate(", 1, true) ~= nil and string.find(client, "BLACKOUT_SAG", 1, true) == nil, "the client paints with the same rules")
end

section("light: no room lit through a wall, none dark by chance (20 seeds)")
do
	local noWorking, badStretch, missingDist, tooFar, moonLeaks = {}, 0, 0, 0, 0
	for s = 1, 20 do
		local holder = Instance.new("Folder")
		holder.Parent = workspace
		local map = MapBuilder.build(s * 7919, holder)
		syncPositions(map.Root)
		for id, room in map.Rooms do
			local list = room.fixtures or {}
			if #list > 0 and not room.secret and not room.darkByDesign then
				local working = false
				for _, f in list do
					if f:GetAttribute("Mode") == "on" then
						working = true
					end
					-- the reach a lamp gets without shadows ends at its walls
					local d = f:GetAttribute("WallDist")
					if type(d) ~= "number" then
						missingDist += 1
					else
						local p = f:GetPivot().Position
						local out = false
						for i = 0, 7 do
							local a = i * math.pi / 4
							local q = Vector3.new(p.X + math.cos(a) * (d + 1.5), room.min.Y + 2, p.Z + math.sin(a) * (d + 1.5))
							-- (roomAt answers a doorway with a room next to it: past the
							-- room's box counts as out too)
							local outsideBox = q.X < room.min.X or q.X > room.max.X or q.Z < room.min.Z or q.Z > room.max.Z
							if outsideBox or map:roomAt(q) ~= room then
								out = true
							end
						end
						if not out then
							tooFar += 1
						end
					end
				end
				if not working then
					table.insert(noWorking, s .. ":" .. id)
				end
				if room.kind == "corridor" then
					table.sort(list, function(a, b)
						local pa, pb = a:GetPivot().Position, b:GetPivot().Position
						return pa.X + pa.Z < pb.X + pb.Z
					end)
					for i = 1, #list - 2 do
						local any = false
						for k = i, i + 2 do
							any = any or list[k]:GetAttribute("Mode") == "on"
						end
						if not any then
							badStretch += 1
						end
					end
				end
			end
		end
		-- moonlight without shadows ends inside the room it shines into
		for _, d in map.Root:GetDescendants() do
			if d:IsA("SpotLight") and d:HasTag("Moonlight") and not d.Shadows and d.Range > 30 then
				moonLeaks += 1
			end
		end
		holder:Destroy()
	end
	check(#noWorking == 0, "every room has a working lamp: " .. table.concat(noWorking, ", "))
	check(badStretch == 0, "no three corridor lamps in a row are all out (" .. badStretch .. ")")
	check(missingDist == 0, "every lamp knows how far its walls are (" .. missingDist .. " missing)")
	check(tooFar == 0, "every lamp's wall distance really ends at a wall (" .. tooFar .. " too far)")
	check(moonLeaks == 0, "no shadowless moonlight keeps its full range (" .. moonLeaks .. ")")
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers.LightController.Source
	check(string.find(client, "math.min(entry.range, info.wallDist)", 1, true) ~= nil, "a lamp without shadows is cut to its walls")
	check(string.find(client, "l.Shadows = shadowed", 1, true) ~= nil and string.find(client, "pickShadowed(tier.shadowLights)", 1, true) ~= nil, "the nearest lamps cast the shadows")
	check(string.find(client, "LOD_DISTANCE * 0.2", 1, true) ~= nil, "far lamps fade instead of switching off")
end

section("blackouts: each level more macabre, not darker")
do
	local LightingRules = requireModule(RS.Shared.LightingRules)
	local f = { seed = 123, floor = "G", mode = "on", emergency = false, forceOn = false, off = false, tint = nil, base = roblox.Color3.new(1, 1, 1), baseBrightness = 1 }
	-- the light a working lamp gives on average over 20 s, level by level
	local means = {}
	for level = 0, 4 do
		local world = { power = true, level = level, zone = "G", seed = 7, escape = false }
		local sum, n = 0, 0
		for i = 0, 1999 do
			local lit, b = LightingRules.evaluate(f, world, i * 0.01, {})
			sum += if lit then b else 0
			n += 1
		end
		means[level] = sum / n
	end
	for level = 2, 4 do
		check(means[level] >= means[level - 1] - 0.05, string.format("level %d is not darker than level %d (%.3f vs %.3f)", level, level - 1, means[level], means[level - 1]))
	end
	check(means[4] >= 0.8, string.format("a total blackout keeps most of the light (%.3f)", means[4]))
	-- the steady reading (the server's) is the same on every level
	for level = 1, 4 do
		local _, b = LightingRules.evaluate(f, { power = true, level = level, zone = "G", seed = 7, escape = false }, 0, { steady = true })
		check(math.abs(b - LightingRules.LEVEL_MEAN[level]) < 1e-6, "level " .. level .. ": the server reads the level's mean light")
	end
	-- level 3: the emergency lamps are the colour; level 2: the light goes pale
	local em = table.clone(f)
	em.emergency = true
	local _, _, red = LightingRules.evaluate(em, { power = true, level = 3, zone = "", seed = 7, escape = false }, 0, {})
	check(red.R > red.G * 2, "at level 3 the emergency lamps turn red")
	local _, _, pale = LightingRules.evaluate(f, { power = true, level = 2, zone = "", seed = 7, escape = false }, 0, {})
	check(pale ~= f.base, "at level 2 the light drains to a sickly pale")
	-- reduced effects: nothing pulses faster than 1 Hz (level 3 breathes instead)
	local beats = 0
	local prev = 0
	for i = 0, 999 do
		local _, b = LightingRules.evaluate(f, { power = true, level = 3, zone = "", seed = 7, escape = false }, i * 0.01, { reduced = true })
		if b > 1.0 and prev <= 1.0 then
			beats += 1
		end
		prev = b
	end
	check(beats <= 10, "with reduced effects level 3 pulses at most once a second (" .. beats .. " in 10 s)")
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
	check(client:FindFirstChild("BlackoutFX") ~= nil, "figures, eyes and sounds come with the levels (BlackoutFX)")
	check(string.find(client.BlackoutFX.Source, "elseif not reduced then", 1, true) ~= nil, "no one-frame figures with reduced effects")
end

section("film: the old camera, near monochrome, red still reads")
do
	local Lighting = requireModule(Server.Services.LightingService)
	local LightingRules = requireModule(RS.Shared.LightingRules)
	-- colour: inside, the grade is near grey ...
	for _, name in { "NORMAL", "BREATH", "HEARTBEAT", "BLACKOUT", "CINEMATIC", "EMERGENCY" } do
		check(Lighting.Presets[name].cc.Saturation <= -0.75, name .. " is near monochrome (" .. Lighting.Presets[name].cc.Saturation .. ")")
	end
	-- ... and the emergency red is still red through it (saturation round luminance)
	local function through(c, sat)
		local lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
		return lum + (c.R - lum) * (1 + sat), lum + (c.G - lum) * (1 + sat)
	end
	for _, name in { "HEARTBEAT", "BLACKOUT" } do
		local r, g = through(LightingRules.ALARM_LIT, Lighting.Presets[name].cc.Saturation)
		check(r - g > 0.06, string.format("%s: the emergency red still reads (R-G %.3f)", name, r - g))
	end
	-- the grain textures exist and tile; their ids wait for an upload
	local AssetIds = requireModule(RS.Shared.Config.AssetIds)
	check(AssetIds.Film and AssetIds.Film.grain_light ~= nil and AssetIds.Film.grain_dark ~= nil, "AssetIds.Film has the two grain layers")
	local fs = require("@lune/fs")
	check(fs.isFile("assets/film/grain_light.png") and fs.isFile("assets/film/grain_dark.png"), "tools/gen_film.py wrote the grain sheets")
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
	local film = client:FindFirstChild("FilmController")
	check(film ~= nil, "a film controller")
	if film then
		local src = film.Source
		check(string.find(src, 'Kit.screen("Film", 1', 1, true) ~= nil, "the film sits over the world and under the HUD (display order 1 < HUD 2)")
		check(string.find(src, "State.settings.filmGrain ~= false", 1, true) ~= nil and string.find(src, "grainIntensity", 1, true) ~= nil, "the grain follows the player's settings")
		check(string.find(src, "pcall(runtimeGrain", 1, true) ~= nil, "without uploaded grain it tries a runtime texture, safely")
		check(string.find(src, "not State.settings.reducedEffects then random:NextNumber(-0.01, 0.01)", 1, true) ~= nil, "no projector flicker with reduced effects")
		check(string.find(src, "not State.settings.reduceMotion", 1, true) ~= nil, "no gate weave with reduced motion")
	end
end

section("the observer: reference silhouette and jumpscare framing")
do
	local RS = game:GetService("ReplicatedStorage")
	local ObserverRig = requireModule(RS.Shared.ObserverRig)
	local rig = ObserverRig.build(CFrame.new(0, 0, 0), { localCopy = true })
	local m = ObserverRig.motors(rig)
	for _, name in { "Head", "Chin", "EyeballL", "EyeballR", "Neck", "UpperTorso", "LeftUpperArm", "RightHand", "LeftLowerLeg" } do
		check(rig:FindFirstChild(name) ~= nil, "observer has " .. name)
	end
	for _, name in { "EyeTurnL", "EyeTurnR", "HeadJoint", "NeckJoint", "Waist", "RootJoint", "LeftShoulder", "RightElbow", "LeftHip", "RightKnee" } do
		check(m[name] ~= nil, "observer joint " .. name)
	end
	-- nothing the reference does not have
	local forbidden = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			for _, word in { "Rib", "Spine", "Tooth", "Maw", "Finger", "Seam", "Blade" } do
				if string.find(d.Name, word) then
					table.insert(forbidden, d.Name)
				end
			end
		end
	end
	check(#forbidden == 0, "no ribs, teeth, maw, fingers or seam: " .. table.concat(forbidden, ", "))
	-- proportions, measured on the standing rig
	local world = ObserverRig.solve(rig, rig.PrimaryPart.CFrame, {})
	local headParts = { Head = true, Chin = true }
	local headMin, headMax, headLow, headTop, armX, handLow, top = math.huge, -math.huge, math.huge, -math.huge, 0, math.huge, -math.huge
	for part, cf in world do
		if part.Transparency < 1 then
			local half = part.Size / 2
			local corners = {}
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(corners, (cf * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position)
					end
				end
			end
			for _, c in corners do
				top = math.max(top, c.Y)
				if headParts[part.Name] then
					headMin, headMax = math.min(headMin, c.X), math.max(headMax, c.X)
					headLow, headTop = math.min(headLow, c.Y), math.max(headTop, c.Y)
				end
				if string.find(part.Name, "Arm") then
					armX = math.max(armX, math.abs(c.X))
				end
				if string.find(part.Name, "Hand") then
					handLow = math.min(handLow, c.Y)
				end
			end
		end
	end
	local headWidth, headHeight, shoulderWidth = headMax - headMin, headTop - headLow, armX * 2
	print(string.format("  observer: head %.2f studs wide and %.2f tall, shoulders %.2f, height %.2f, hands down to %.2f", headWidth, headHeight, shoulderWidth, top, handLow))
	check(headWidth < shoulderWidth * 0.5, string.format("the head is narrow, no wings (%.2f studs vs shoulders %.1f)", headWidth, shoulderWidth))
	check(headHeight > headWidth * 1.5, string.format("the head is long (%.2f tall, %.2f wide)", headHeight, headWidth))
	check(top > 9 and top < 10, string.format("very tall (%.1f studs)", top))
	check(handLow < 2.3 and handLow > 0.6, string.format("the arms hang to the middle of the shins (hands down to %.1f)", handLow))
	-- matte black body, two small dim eyes
	local lum = function(c)
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end
	local bright, shiny = {}, {}
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			if string.find(d.Name, "Eyeball") then
				-- eyeshine: a small dark eyeball, not lit by itself
				check(lum(d.Color) < 0.1 and d.Material ~= env.roblox.Enum.Material.Neon and d.Size.X < 0.2, "small dark eyeball: " .. d.Name)
			elseif d.Name == "Iris" then
				-- a faint glow (Neon), never a lamp
				check(d.Material == env.roblox.Enum.Material.Neon and lum(d.Color) > 0.05 and lum(d.Color) < 0.35, "faintly glowing iris")
			elseif d.Name ~= "Pupil" and lum(d.Color) > 0.06 then
				table.insert(bright, d.Name)
			end
			if d.Reflectance > 0 then
				table.insert(shiny, d.Name)
			end
		end
	end
	check(#bright == 0, "the body is uniformly black: " .. table.concat(bright, ", "))
	check(#shiny == 0, "the body is matte: " .. table.concat(shiny, ", "))
	-- the jumpscare framing: from many places, headings and pitches (looking
	-- at the floor and at the ceiling too), the face lands exactly in front of
	-- the lens, upright on screen, looking straight into it
	local GameConfig = requireModule(RS.Shared.Config.GameConfig)
	local fov = GameConfig.Camera.DefaultFOV
	local dist = ObserverRig.scareDistance(fov)
	check(math.abs(dist - ObserverRig.ScareDistance) < 1e-6, "ScareDistance is the default field of view's distance")
	check(dist > 0.5 and dist < 2, string.format("its face is a stud or so from the lens (%.2f studs)", dist))
	local worst = { dist = 0, facing = 1, upright = 1, eyes = 0 }
	for i = 0, 11 do
		local yaw = i * math.pi / 6
		local eye = Vector3.new(math.cos(yaw) * 7, 4.5 + (i % 3) * 0.6, math.sin(yaw) * 7)
		for _, pitch in { -80, -35, 0, 40, 80 } do
			local camCf = CFrame.new(eye) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(pitch), 0, 0)
			for _, a in { 0, 0.5, 1 } do
				local pose = ObserverRig.ScarePose(a, 0)
				local target = eye + camCf.LookVector * dist
				local rootCf = ObserverRig.placeFace(m, pose, target, camCf)
				local solved = ObserverRig.solve(rig, rootCf, pose)
				local anchor = rootCf * ObserverRig.headFromRoot(m, pose) * ObserverRig.FaceAnchor
				-- the solver and the full-rig FK agree
				local fromRig = solved[rig:FindFirstChild("Head")] * ObserverRig.FaceAnchor
				worst.dist = math.max(worst.dist, (anchor.Position - target).Magnitude, (fromRig.Position - target).Magnitude)
				worst.facing = math.min(worst.facing, anchor.LookVector:Dot(-camCf.LookVector))
				worst.upright = math.min(worst.upright, anchor.UpVector:Dot(camCf.UpVector))
				if a == 1 then
					for _, side in { "L", "R" } do
						local to = (solved[rig:FindFirstChild("Eyeball" .. side)].Position - eye).Unit
						worst.eyes = math.max(worst.eyes, math.deg(math.acos(math.clamp(to:Dot(camCf.LookVector), -1, 1))))
					end
				end
			end
		end
	end
	check(worst.dist < 1e-3, string.format("the face lands exactly where the jumpscare puts it (worst %.5f)", worst.dist))
	check(worst.facing > 0.999, string.format("the face looks straight into the lens, at any pitch (worst %.4f)", worst.facing))
	check(worst.upright > 0.999, string.format("the face is upright on screen, at any pitch (worst %.4f)", worst.upright))
	print(string.format("  jumpscare: %.2f studs at fov %d, face error %.5f, facing %.4f, upright %.4f, eyes within %.1f deg of centre", dist, fov, worst.dist, worst.facing, worst.upright, worst.eyes))
	check(worst.eyes < fov * 0.25, string.format("both eyes near the centre of the picture (worst %.1f deg)", worst.eyes))
	-- the head fills about two thirds of the screen's height, measured on the
	-- real head mesh (its vertices, as the camera projects them) at several
	-- fields of view
	do
		local fs = require("@lune/fs")
		local verts = {}
		for line in string.gmatch(fs.readFile("assets/observer/Head.obj"), "[^\n]+") do
			local x, y, z = string.match(line, "^v%s+(%S+)%s+(%S+)%s+(%S+)")
			if x then
				table.insert(verts, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
			end
		end
		check(#verts > 100, "head mesh read (" .. #verts .. " vertices)")
		for _, f in { 60, fov, 90 } do
			local camCf = CFrame.new(0, 4.5, 0)
			local pose = ObserverRig.ScarePose(1, 0)
			local d = ObserverRig.scareDistance(f)
			local rootCf = ObserverRig.placeFace(m, pose, camCf.Position + camCf.LookVector * d, camCf)
			local headCf = ObserverRig.solve(rig, rootCf, pose)[rig:FindFirstChild("Head")]
			local lo, hi, nearest = math.huge, -math.huge, math.huge
			local half = math.tan(math.rad(f) / 2)
			for _, v in verts do
				local rel = camCf:PointToObjectSpace(headCf * v)
				local depth = -rel.Z
				nearest = math.min(nearest, depth)
				local y = rel.Y / (depth * half)
				lo, hi = math.min(lo, y), math.max(hi, y)
			end
			local fill = (hi - lo) / 2
			check(fill > 0.6 and fill < 0.74, string.format("at fov %d the head fills %.2f of the screen's height", f, fill))
			check(nearest > 0.2, string.format("at fov %d the head stays clear of the lens (%.2f studs)", f, nearest))
		end
	end
	-- nothing comes between the camera and its head
	do
		local camCf = CFrame.new(0, 4.5, 0)
		local eye = camCf.Position
		local pose = ObserverRig.ScarePose(1, 0)
		local target = eye + Vector3.new(0, 0, -dist)
		local solved = ObserverRig.solve(rig, ObserverRig.placeFace(m, pose, target, camCf), pose)
		local blocking = {}
		for part, cf in solved do
			local onHead = headParts[part.Name] or string.find(part.Name, "Eyeball") or part.Name == "Pupil" or part.Name == "Iris"
			if part.Transparency < 1 and not onHead then
				local rel = cf.Position - eye
				local along = rel:Dot(Vector3.new(0, 0, -1))
				local off = (rel - Vector3.new(0, 0, -1) * along).Magnitude
				if along > 0.1 and along < dist - 0.1 and off < 0.9 then
					table.insert(blocking, part.Name)
				end
			end
		end
		check(#blocking == 0, "nothing between the camera and the head: " .. table.concat(blocking, ", "))
	end
	-- eyes turn toward a point, within limits
	local eyes = ObserverRig.eyesAt(rig, m, Vector3.new(30, 4, -30), 35)
	for name, cf in eyes do
		local rx, ry = cf:ToEulerAnglesXYZ()
		check(math.abs(math.deg(rx)) <= 35.01 and math.abs(math.deg(ry)) <= 35.01, "eye turn limited: " .. name)
	end
	check(next(ObserverRig.faceOpen(1)) == nil, "no opening face (the reference has none)")
	rig:Destroy()
end

section("summary")
print(string.format("%d checks, %d failures", checks, failures))
process.exit(if failures == 0 then 0 else 1)
