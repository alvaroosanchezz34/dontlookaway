--[[
	ENVIRONMENT anomalies: the building itself changes shape, light, material.
	NPC anomalies: the residents of the building do things residents should not.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util.Util)
local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Parent.Registry)
local Layout = require(script.Parent.Parent.Map.Layout)

local G, P = "GLOBAL", "PLAYER"
local FOCUS = "FOCUS"

local function expansionCenter(exp)
	local cf, size = exp.group:GetBoundingBox()
	return cf.Position, size
end

-- Players inside a pre-built expansion must be brought back before it vanishes.
local function evacuate(exp)
	local def = exp.def
	local floor = Layout.getFloor(def.floor)
	local minX = def.x0 * Layout.Cell - 4
	local maxX = (def.capX + 1) * Layout.Cell
	local minZ = def.z0 * Layout.Cell
	local maxZ = (def.z1 + 1) * Layout.Cell
	for _, p in Registry.PlayerService:GetAlive() do
		local root = Util.getRoot(p)
		if root then
			local pos = root.Position - Layout.Origin
			if pos.X >= minX and pos.X <= maxX and pos.Z >= minZ and pos.Z <= maxZ and pos.Y > floor.y - 2 and pos.Y < floor.y + 14 then
				local back = Layout.Origin + Vector3.new((def.capX + 1.5) * Layout.Cell, floor.y + 3, math.clamp(pos.Z, minZ + 2, maxZ - 2))
				Registry.PlayerService:Teleport(p, CFrame.lookAt(back, back + Vector3.new(1, 0, 0)))
				Net.fire(p, "Effect", { name = "PortalGlitch" })
			end
		end
	end
end

local function expansionAnomaly(id: string, expName: string, difficulty: number)
	return {
		id = id,
		difficulty = difficulty,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			local exp = ctx.map.Expansions[expName]
			return if exp then { exp } else {}
		end,
		create = function(ctx, exp)
			local center, size = expansionCenter(exp)
			local capCenter = exp.cap:GetBoundingBox().Position
			if ctx:nearest(capCenter) < 8 then
				return nil
			end
			return {
				ops = { { t = "Hide", target = exp.cap }, { t = "Show", target = exp.group } },
				anchors = { { pos = center, radius = math.max(size.X, size.Z) / 2 } },
				checkPoints = { capCenter, capCenter + Vector3.new(0, 4, 0) },
				lifetime = 110,
				beforeRevert = function()
					evacuate(exp)
				end,
				onApplied = function()
					Registry.AudioService:PlayAt("StretchGroan", capCenter, { volume = 0.6 })
				end,
			}
		end,
	}
end

local FLOOR_SWAP = {
	[Enum.Material.Carpet] = { Enum.Material.WoodPlanks, Color3.fromRGB(90, 66, 46) },
	[Enum.Material.CeramicTiles] = { Enum.Material.Carpet, Color3.fromRGB(84, 40, 38) },
	[Enum.Material.Marble] = { Enum.Material.Carpet, Color3.fromRGB(46, 58, 70) },
	[Enum.Material.WoodPlanks] = { Enum.Material.CeramicTiles, Color3.fromRGB(150, 150, 146) },
	[Enum.Material.Concrete] = { Enum.Material.WoodPlanks, Color3.fromRGB(80, 60, 44) },
	[Enum.Material.DiamondPlate] = { Enum.Material.Carpet, Color3.fromRGB(70, 46, 46) },
}

local function roomTopProps(room)
	local list = {}
	for _, prop in room.props do
		if typeof(prop) == "Instance" and prop.Parent and prop:HasTag("Movable") and prop.Parent == room.folder then
			table.insert(list, prop)
		end
	end
	return list
end

local function residentAnchor(npc: Instance)
	local head = npc:FindFirstChild("Head")
	return { pos = head or npc, radius = 2.4 }
end

local function playCreatedSounds(created)
	for _, inst in created do
		for _, d in inst:GetDescendants() do
			if d:IsA("Sound") and d:GetAttribute("AutoPlay") then
				d:Play()
			end
		end
	end
end

return {
	expansionAnomaly("CORRIDOR_LONGER", "CorridorStretch", 2),
	expansionAnomaly("ROOM_BIGGER", "BoilerExpand", 3),
	{
		id = "ROOM_SMALLER",
		difficulty = 3,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			return if ctx.map.ShrinkWall then { ctx.map.ShrinkWall } else {}
		end,
		create = function(ctx, wall)
			local room = ctx.map.Rooms.G_a
			if not room or ctx:anyPlayerInRoom(room) then
				return nil
			end
			local center = wall:GetBoundingBox().Position
			return {
				ops = { { t = "Show", target = wall } },
				anchors = { { pos = center, radius = 9 } },
				lifetime = 120,
			}
		end,
	},
	{
		id = "DOOR_PORTAL",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		requires = function(ctx)
			return not ctx.svc:GetActive().DOOR_GONE
		end,
		candidates = function(ctx)
			local list = {}
			for _, rec in ctx.map.Doors do
				if rec.model and rec.model:HasTag("Door") and rec.model:GetAttribute("Kind") == "normal" then
					local a, b = ctx.map.Rooms[rec.roomA or ""], ctx.map.Rooms[rec.roomB or ""]
					if a and b and (a.kind == "corridor" or b.kind == "corridor") and a.kind ~= "stairs" and b.kind ~= "stairs" then
						table.insert(list, rec)
					end
				end
			end
			return list
		end,
		create = function(ctx, rec)
			-- destination: a similar door on another floor
			local options = {}
			for _, other in ctx.map.Doors do
				if other ~= rec and other.floor ~= rec.floor and other.model and other.model:HasTag("Door") and other.model:GetAttribute("Kind") == "normal" then
					local a, b = ctx.map.Rooms[other.roomA or ""], ctx.map.Rooms[other.roomB or ""]
					if a and b and (a.kind == "corridor" or b.kind == "corridor") then
						table.insert(options, other)
					end
				end
			end
			local dest = ctx.rng:Pick(options)
			if not dest then
				return nil
			end
			local ops = {}
			-- the tell: the door's number plate now shows where it really leads
			local roomSide = ctx.map.Rooms[rec.roomA or ""]
			if roomSide and roomSide.kind == "corridor" then
				roomSide = ctx.map.Rooms[rec.roomB or ""]
			end
			local destRoom = ctx.map.Rooms[dest.roomA or ""]
			if destRoom and destRoom.kind == "corridor" then
				destRoom = ctx.map.Rooms[dest.roomB or ""]
			end
			if roomSide and roomSide.plate and destRoom then
				local label = roomSide.plate:FindFirstChild("Label", true)
				if label then
					table.insert(ops, { t = "Prop", target = label, prop = "Text", value = destRoom.number or "?" })
				end
			end
			local passed = {}
			return {
				claim = rec.model,
				ops = ops,
				anchors = { { pos = rec.center + Vector3.new(0, 5, 0), radius = 3 } },
				lifetime = 140,
				update = function(inst)
					local srcFrame = CFrame.lookAt(rec.center, rec.center + rec.passageDir)
					local dstFrame = CFrame.lookAt(dest.center, dest.center + dest.passageDir)
					for _, p in inst.players do
						local root = Util.getRoot(p)
						if root and Registry.PlayerService:IsAlive(p) and not passed[p] then
							local rel = srcFrame:ToObjectSpace(root.CFrame)
							if math.abs(rel.Position.X) < 1.8 and math.abs(rel.Position.Z) < 1.4 and rel.Position.Y > 0 and rel.Position.Y < 6 then
								passed[p] = true
								Registry.PlayerService:Teleport(p, dstFrame * rel)
								Net.fire(p, "Effect", { name = "PortalGlitch" })
								inst.data.resolver = p
								return "resolve"
							end
						end
					end
					return nil
				end,
			}
		end,
	},
	{
		id = "LIGHTS_CHANGE",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if #room.fixtures > 0 and not room.secret then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			local tint = ctx.rng:Pick({ Color3.fromRGB(130, 255, 200), Color3.fromRGB(255, 120, 90), Color3.fromRGB(150, 140, 255), Color3.fromRGB(255, 240, 120) })
			local ops, anchors = {}, {}
			for _, f in room.fixtures do
				if f:GetAttribute("Mode") ~= "dead" then
					table.insert(ops, { t = "Attr", target = f, name = "Tint", value = tint })
					table.insert(ops, { t = "Attr", target = f, name = "ForceOn", value = true })
					table.insert(anchors, ctx:anchor(f, 2.5))
				end
			end
			if #ops == 0 then
				return nil
			end
			table.insert(anchors, { pos = room.center + Vector3.new(0, 5, 0), radius = 5 })
			return { ops = ops, anchors = anchors, checkPoints = { room.center + Vector3.new(0, 4, 0) } }
		end,
	},
	{
		id = "FLOOR_CHANGE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "corridor" and room.kind ~= "stairs" and #room.floorParts > 0 and not room.secret then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			if ctx:anyPlayerInRoom(room) then
				return nil
			end
			local ops, anchors = {}, {}
			for _, part in room.floorParts do
				local swap = FLOOR_SWAP[part.Material] or { Enum.Material.Carpet, Color3.fromRGB(80, 40, 40) }
				table.insert(ops, { t = "Prop", target = part, prop = "Material", value = swap[1] })
				table.insert(ops, { t = "Prop", target = part, prop = "Color", value = swap[2] })
				table.insert(anchors, { pos = part.Position + Vector3.new(0, 0.5, 0), radius = math.min(part.Size.X, part.Size.Z) / 2 + 1 })
			end
			return { ops = ops, anchors = anchors, checkPoints = { room.center + Vector3.new(0, 1, 0) } }
		end,
	},
	{
		id = "CEILING_LOW",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "corridor" and room.kind ~= "stairs" and #room.ceilingParts > 0 and not room.secret then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			if ctx:anyPlayerInRoom(room) then
				return nil
			end
			local drop = CFrame.new(0, -3.6, 0)
			local ops, anchors = {}, {}
			for _, part in room.ceilingParts do
				table.insert(ops, { t = "Prop", target = part, prop = "CFrame", value = drop * part.CFrame })
				table.insert(anchors, { pos = part.Position - Vector3.new(0, 3.6, 0), radius = math.min(part.Size.X, part.Size.Z) / 2 + 1 })
			end
			for _, f in room.fixtures do
				table.insert(ops, { t = "Pivot", target = f, cframe = drop * f:GetPivot() })
			end
			return { ops = ops, anchors = anchors, checkPoints = { room.center + Vector3.new(0, 10, 0) } }
		end,
	},
	{
		id = "WATER",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "stairs" and room.kind ~= "corridor" and not room.secret then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			local size = room.max - room.min
			local water = Instance.new("Part")
			water.Name = "Water"
			water.Anchored = true
			water.CanCollide = false
			water.CastShadow = false
			water.Material = Enum.Material.Glass
			water.Color = Color3.fromRGB(34, 46, 50)
			water.Transparency = 0.3
			water.Reflectance = 0.3
			water.Size = Vector3.new(size.X - 0.4, 0.15, size.Z - 0.4)
			local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)
			local s = SoundFactory.create("WaterRush", water)
			if s then
				s:SetAttribute("AutoPlay", true)
				s.Volume *= 0.6
			end
			local template = Registry.RealityService:AddTemplate("Water_" .. room.id, water, true)
			local cf = CFrame.new(room.center + Vector3.new(0, 0.12, 0))
			return {
				ops = { { t = "Clone", template = template, parent = room.folder, cframe = cf, name = "Water" } },
				anchors = { { pos = room.center + Vector3.new(0, 0.3, 0), radius = math.min(size.X, size.Z) / 2 + 1 } },
				checkPoints = { room.center + Vector3.new(0, 1, 0) },
				onApplied = function(_, created)
					playCreatedSounds(created)
				end,
			}
		end,
	},
	{
		id = "FOG",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "stairs" and not room.secret and room.area >= 160 then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			local size = room.max - room.min
			local holder = Instance.new("Part")
			holder.Name = "Fog"
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CastShadow = false
			holder.Transparency = 1
			holder.Size = Vector3.new(size.X - 2, 2, size.Z - 2)
			local e = Instance.new("ParticleEmitter")
			e.Rate = math.clamp(room.area / 40, 6, 24)
			e.Lifetime = NumberRange.new(8, 12)
			e.Speed = NumberRange.new(0.2, 0.6)
			e.SpreadAngle = Vector2.new(180, 20)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 10) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(0.7, 0.86), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(Color3.fromRGB(176, 180, 186))
			e.LightInfluence = 1
			e.RotSpeed = NumberRange.new(-8, 8)
			e.Rotation = NumberRange.new(0, 360)
			e.Parent = holder
			local template = Registry.RealityService:AddTemplate("Fog_" .. room.id, holder, true)
			return {
				ops = { { t = "Clone", template = template, parent = room.folder, cframe = CFrame.new(room.center + Vector3.new(0, 2, 0)), name = "Fog" } },
				anchors = { { pos = room.center + Vector3.new(0, 3, 0), radius = math.min(size.X, size.Z) / 2 } },
				checkPoints = { room.center + Vector3.new(0, 3, 0) },
			}
		end,
	},
	{
		id = "FLOATING",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if #roomTopProps(room) >= 3 and not room.secret then
					table.insert(list, room)
				end
			end
			table.sort(list, function(a, b)
				return a.id < b.id
			end)
			return list
		end,
		create = function(ctx, room)
			if ctx:anyPlayerInRoom(room) then
				return nil
			end
			local ops, anchors, checks = {}, {}, {}
			local props = roomTopProps(room)
			ctx.rng:Shuffle(props)
			for i = 1, math.min(6, #props) do
				local prop = props[i]
				local cf = prop:GetPivot()
				local lifted = CFrame.new(0, ctx.rng:Number(1.6, 3.6), 0) * cf * CFrame.Angles(math.rad(ctx.rng:Number(-14, 14)), math.rad(ctx.rng:Number(-30, 30)), math.rad(ctx.rng:Number(-14, 14)))
				table.insert(ops, { t = "Pivot", target = prop, cframe = lifted })
				local c, r = ctx:center(prop)
				table.insert(anchors, { pos = c + Vector3.new(0, 2.5, 0), radius = math.max(1.8, r) })
				table.insert(checks, c)
			end
			return { ops = ops, anchors = anchors, checkPoints = checks }
		end,
	},
	-- NPC ---------------------------------------------------------------------------
	{
		id = "NPC_APPEARS",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "stairs" and not room.secret then
					for _, spot in room.floorSpots do
						table.insert(list, { pos = spot, room = room })
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			local door = c.room.doors[1]
			local look = if door then Util.flat(door.center - c.pos) else Vector3.new(0, 0, 1)
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, 1)
			end
			return {
				ops = { { t = "Clone", template = ctx:template("Resident"), parent = c.room.folder, cframe = CFrame.lookAt(c.pos, c.pos + look.Unit), name = "Resident" } },
				anchors = { { pos = c.pos + Vector3.new(0, 4, 0), radius = 3.2 } },
			}
		end,
	},
	{
		id = "NPC_GONE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Resident")
		end,
		create = function(ctx, npc)
			local c = ctx:center(npc)
			return { claim = npc, ops = { { t = "Hide", target = npc } }, anchors = { { pos = c, radius = 3 } } }
		end,
	},
	{
		id = "NPC_MOVED",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Resident")
		end,
		create = function(ctx, npc)
			local room = ctx:roomOf(npc)
			if not room or #room.floorSpots == 0 then
				return nil
			end
			local from = npc:GetPivot()
			local spot = ctx.rng:Pick(room.floorSpots)
			if (spot - from.Position).Magnitude < 6 then
				return nil
			end
			local door = room.doors[1]
			local look = if door then Util.flat(door.center - spot) else from.LookVector
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, 1)
			end
			local target = CFrame.lookAt(Vector3.new(spot.X, from.Position.Y, spot.Z), Vector3.new(spot.X, from.Position.Y, spot.Z) + look.Unit)
			return {
				claim = npc,
				ops = { { t = "Pivot", target = npc, cframe = target } },
				anchors = { { pos = target.Position + Vector3.new(0, 3.5, 0), radius = 3 } },
				checkPoints = { from.Position + Vector3.new(0, 3, 0), target.Position + Vector3.new(0, 3, 0) },
			}
		end,
	},
	{
		id = "NPC_WATCHING",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Resident")
		end,
		create = function(ctx, npc)
			return {
				claim = npc,
				ops = { { t = "Attr", target = npc, name = "Watching", value = true } },
				anchors = { residentAnchor(npc) },
				lifetime = 150,
			}
		end,
	},
	{
		id = "NPC_BEHIND",
		difficulty = 2,
		scopes = { P },
		detection = FOCUS,
		candidates = function(ctx)
			local target = ctx.players[1]
			local root = target and Util.getRoot(target)
			if not root then
				return {}
			end
			local back = -Util.flat(root.CFrame.LookVector)
			if back.Magnitude < 0.1 then
				return {}
			end
			back = back.Unit
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { target.Character :: Instance }
			for _, dist in { 6, 5, 4 } do
				local hit = workspace:Raycast(root.Position, back * (dist + 1.5), params)
				if not hit then
					local spot = root.Position + back * dist
					local ground = workspace:Raycast(spot, Vector3.new(0, -8, 0), params)
					if ground then
						return { { pos = ground.Position, face = -back } }
					end
				end
			end
			return {}
		end,
		create = function(ctx, c)
			local room = ctx.map:roomAt(c.pos + Vector3.new(0, 2, 0))
			local parent = room and room.folder or ctx.map.Root
			local seenFor = 0
			return {
				ops = { { t = "Clone", template = ctx:template("Resident"), parent = parent, cframe = CFrame.lookAt(c.pos, c.pos + c.face), name = "Resident" } },
				anchors = { { pos = c.pos + Vector3.new(0, 4, 0), radius = 3 } },
				lifetime = 14,
				update = function(inst, dt)
					local target = inst.players[1]
					if Registry.PlayerService:IsLookingAt(target, c.pos + Vector3.new(0, 4, 0), 30, 60) then
						seenFor += dt
						if seenFor > 2.2 then
							return "expire"
						end
					end
					return nil
				end,
			}
		end,
	},
	{
		id = "NPC_CREEP",
		difficulty = 3,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind == "corridor" then
					for _, spot in room.floorSpots do
						local d = ctx:nearest(spot)
						if d > 40 and d < 110 then
							table.insert(list, { pos = spot, room = room })
						end
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			local clone: Model? = nil
			local timer = 0
			local spec
			spec = {
				ops = { { t = "Clone", template = ctx:template("Resident"), parent = c.room.folder, cframe = CFrame.new(c.pos), name = "Resident" } },
				anchors = { { pos = c.pos + Vector3.new(0, 4, 0), radius = 3 } },
				lifetime = 90,
				onApplied = function(_, created)
					clone = created[1] :: Model?
					if clone then
						local head = clone:FindFirstChild("Head")
						spec.anchors[1] = { pos = head or clone, radius = 3 }
					end
				end,
				update = function(inst, dt)
					timer += dt
					if not clone or not clone.Parent or timer < 2.4 then
						return nil
					end
					timer = 0
					local head = clone:FindFirstChild("Head") :: BasePart?
					if not head then
						return nil
					end
					if Registry.PlayerService:CanAnyoneSee({ head.Position }, 62, 200, nil, inst.players) then
						return nil
					end
					-- step toward the nearest player, never closer than 8 studs
					local best, bestD = nil, math.huge
					for _, p in inst.players do
						local root = Util.getRoot(p)
						if root then
							local d = (root.Position - clone:GetPivot().Position).Magnitude
							if d < bestD then
								best, bestD = root, d
							end
						end
					end
					if not best or bestD < 9 then
						return nil
					end
					local from = clone:GetPivot().Position
					local dir = Util.flat(best.Position - from)
					if dir.Magnitude < 0.1 then
						return nil
					end
					dir = dir.Unit
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { clone }
					params.RespectCanCollide = true
					local step = math.min(5, bestD - 8)
					local hit = workspace:Raycast(from + Vector3.new(0, 2.5, 0), dir * (step + 1), params)
					if hit then
						return nil
					end
					local to = from + dir * step
					clone:PivotTo(CFrame.lookAt(to, to + dir))
					return nil
				end,
			}
			return spec
		end,
	},
}
