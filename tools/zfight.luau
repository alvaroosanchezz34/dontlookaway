--[[
	Z-fighting audit (Lune).
	Finds pairs of visible block parts with a coplanar face pointing the same way
	and overlapping area: those flicker in game ("the floor glitches").

	Usage:
		rojo build default.project.json -o build/test.rbxlx
		lune run tools/zfight.luau build/test.rbxlx [seedCount] [verbose]
]]

local env = require("./lib/env")
local process = require("@lune/process")
local roblox = env.roblox
local game = env.game
local requireModule = env.requireModule
local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local MapBuilder = requireModule(Server.Map.MapBuilder)
local Lobby = requireModule(Server.Map.Lobby)

local seedCount = tonumber(process.args[2]) or 3
local verbose = process.args[3] == "verbose"

local EPS = 0.012 -- planes closer than this flicker
local MIN_AREA = 0.04

-- faces of an (almost) axis aligned block: normal, plane offset, 2D rect on the plane
local function faces(p)
	local cf = p.CFrame
	local out = {}
	local half = p.Size / 2
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local halves = { half.X, half.Y, half.Z }
	for i = 1, 3 do
		for _, sign in { 1, -1 } do
			local n = axes[i] * sign
			-- only world-axis aligned faces (the vast majority); others are skipped
			local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
			local worldAxis = if ax > 0.999 then 1 elseif ay > 0.999 then 2 elseif az > 0.999 then 3 else nil
			if worldAxis then
				local center = cf.Position + n * halves[i]
				-- the face rect in world space: extent along the other two world axes
				local corners = {}
				local j, k = (i % 3) + 1, ((i + 1) % 3) + 1
				for _, sj in { -1, 1 } do
					for _, sk in { -1, 1 } do
						table.insert(corners, center + axes[j] * halves[j] * sj + axes[k] * halves[k] * sk)
					end
				end
				local function comp(v, a)
					return if a == 1 then v.X elseif a == 2 then v.Y else v.Z
				end
				local u, v = if worldAxis == 1 then 2 elseif worldAxis == 2 then 1 else 1, if worldAxis == 3 then 2 else 3
				local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
				for _, c in corners do
					minU = math.min(minU, comp(c, u))
					maxU = math.max(maxU, comp(c, u))
					minV = math.min(minV, comp(c, v))
					maxV = math.max(maxV, comp(c, v))
				end
				local dir = if comp(n, worldAxis) > 0 then 1 else -1
				table.insert(out, { axis = worldAxis, dir = dir, d = comp(center, worldAxis), minU = minU, maxU = maxU, minV = minV, maxV = maxV })
			end
		end
	end
	return out
end

local function audit(root)
	local buckets = {}
	local parts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Part") and d.Shape == Enum.PartType.Block and d.Transparency < 0.95 then
			table.insert(parts, d)
		end
	end
	for pi, p in parts do
		for _, f in faces(p) do
			local key = f.axis * 2 + (if f.dir > 0 then 1 else 0)
			local bucket = buckets[key]
			if not bucket then
				bucket = {}
				buckets[key] = bucket
			end
			-- hash by plane offset so near-coplanar faces meet
			local slot = math.floor(f.d / EPS)
			for s = slot - 1, slot + 1 do
				bucket[s] = bucket[s] or {}
			end
			f.part = pi
			table.insert(bucket[slot], f)
		end
	end
	-- coarse spatial hash so we can ask "is this point inside some solid part?"
	local GRID = 8
	local grid = {}
	for pi, p in parts do
		local cf, size = p.CFrame, p.Size
		local r = size.Magnitude / 2
		local c = cf.Position
		for gx = math.floor((c.X - r) / GRID), math.floor((c.X + r) / GRID) do
			for gy = math.floor((c.Y - r) / GRID), math.floor((c.Y + r) / GRID) do
				for gz = math.floor((c.Z - r) / GRID), math.floor((c.Z + r) / GRID) do
					local k = gx .. "," .. gy .. "," .. gz
					grid[k] = grid[k] or {}
					table.insert(grid[k], pi)
				end
			end
		end
	end
	local function insideOther(point, skipA, skipB)
		local k = math.floor(point.X / GRID) .. "," .. math.floor(point.Y / GRID) .. "," .. math.floor(point.Z / GRID)
		for _, pi in grid[k] or {} do
			if pi ~= skipA and pi ~= skipB then
				local p = parts[pi]
				if p.Transparency < 0.05 then
					local rel = p.CFrame:PointToObjectSpace(point)
					local h = p.Size / 2
					if math.abs(rel.X) < h.X and math.abs(rel.Y) < h.Y and math.abs(rel.Z) < h.Z then
						return true
					end
				end
			end
		end
		return false
	end
	local function worldPoint(axis, d, u, v)
		if axis == 1 then
			return Vector3.new(d, u, v)
		elseif axis == 2 then
			return Vector3.new(u, d, v)
		end
		return Vector3.new(u, v, d)
	end
	local hits = {}
	local seen = {}
	for _, bucket in buckets do
		for slot, list in bucket do
			local near = {}
			for s = slot, slot + 1 do
				for _, f in bucket[s] or {} do
					table.insert(near, f)
				end
			end
			for a = 1, #list do
				local fa = list[a]
				for _, fb in near do
					if fb.part ~= fa.part and math.abs(fa.d - fb.d) < EPS then
						local w = math.min(fa.maxU, fb.maxU) - math.max(fa.minU, fb.minU)
						local h = math.min(fa.maxV, fb.maxV) - math.max(fa.minV, fb.minV)
						if w > 0.05 and h > 0.05 and w * h > MIN_AREA then
							local pa, pb = parts[fa.part], parts[fb.part]
							local k = if fa.part < fb.part then fa.part .. ":" .. fb.part else fb.part .. ":" .. fa.part
							-- same colour + material faces do not visibly flicker
							local visible = pa.Color ~= pb.Color or pa.Material ~= pb.Material
							if visible then
								-- a face buried in another solid part is never seen: sample the overlap
								local u0, u1 = math.max(fa.minU, fb.minU), math.min(fa.maxU, fb.maxU)
								local v0, v1 = math.max(fa.minV, fb.minV), math.min(fa.maxV, fb.maxV)
								local shown = false
								for _, su in { 0.15, 0.5, 0.85 } do
									for _, sv in { 0.15, 0.5, 0.85 } do
										local pt = worldPoint(fa.axis, fa.d + fa.dir * 0.03, u0 + (u1 - u0) * su, v0 + (v1 - v0) * sv)
										if not insideOther(pt, fa.part, fb.part) then
											shown = true
										end
									end
								end
								visible = shown
							end
							if visible and not seen[k] then
								seen[k] = true
								table.insert(hits, { a = pa, b = pb, area = w * h, axis = fa.axis, dir = fa.dir, d = fa.d })
							end
						end
					end
				end
			end
		end
	end
	return hits
end

local byPair = {}
local examples = {}
local total = 0
local function report(label, hits)
	print(string.format("%s: %d z-fighting pairs", label, #hits))
	total += #hits
	for _, h in hits do
		local na, nb = h.a.Name, h.b.Name
		local ma = h.a:FindFirstAncestorWhichIsA("Model")
		local mb = h.b:FindFirstAncestorWhichIsA("Model")
		na = (if ma then ma.Name .. "." else "") .. na
		nb = (if mb then mb.Name .. "." else "") .. nb
		local key = if na < nb then na .. "  <>  " .. nb else nb .. "  <>  " .. na
		byPair[key] = (byPair[key] or 0) + 1
		examples[key] = examples[key] or string.format("%.1f,%.1f,%.1f area %.2f axis %d dir %d d %.3f | %s size %s | %s size %s", h.a.CFrame.Position.X, h.a.CFrame.Position.Y, h.a.CFrame.Position.Z, h.area, h.axis, h.dir, h.d, h.a.Name, tostring(h.a.Size), h.b.Name, tostring(h.b.Size))
	end
end

for i = 1, seedCount do
	local seed = 1000 + i * 7919
	local holder = Instance.new("Folder")
	holder.Parent = env.workspace
	local map = MapBuilder.build(seed, holder)
	report("seed " .. seed, audit(map.Root))
	holder:Destroy()
end
do
	local holder = Instance.new("Folder")
	holder.Parent = env.workspace
	local lobby = Lobby.build(holder)
	report("lobby", audit(lobby.Root))
	holder:Destroy()
end

local keys = {}
for k in byPair do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	return byPair[a] > byPair[b]
end)
print("\n== by pair")
for i, k in keys do
	if i > (if verbose then 200 else 60) then
		break
	end
	print(string.format("%5d  %s   (%s)", byPair[k], k, examples[k]))
end
print("\nTOTAL", total)
local _ = Vector3
