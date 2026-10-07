--[[
	VISUAL anomalies: something in the building looks different.
	All of them are reported by FOCUS (look at it and hold the report input).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local G, P = "GLOBAL", "PLAYER"
local FOCUS = "FOCUS"

local function artFrames(model: Instance)
	local canvas = model:FindFirstChild("Canvas")
	local art = canvas and canvas:FindFirstChild("Art")
	if not art then
		return nil
	end
	return art:FindFirstChild("A"), art:FindFirstChild("B"), canvas
end

local function markOf(model: Instance): Instance?
	local ref = model:FindFirstChild("Mark")
	if ref and ref:IsA("ObjectValue") and ref.Value and ref.Value.Parent then
		return ref.Value
	end
	return nil
end

local function largestPart(model: Instance): BasePart?
	local best, size = nil, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > size then
				best, size = d, v
			end
		end
	end
	return best
end

local function isFloorProp(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	local parent = model.Parent
	return parent ~= nil and parent:IsA("Folder")
end

local TEXT_SWAPS = {
	EXIT = "STAY",
	["OUT OF ORDER"] = "IN ORDER",
	STAIRS = "STARES",
	OUTGOING = "INCOMING",
	["AUTHORIZED PERSONNEL ONLY"] = "AUTHORIZED PERSONNEL LONELY",
	["DANGER  HIGH VOLTAGE"] = "DANGER  HIGH VISIBILITY",
	["PLEASE KEEP YOUR EYES OPEN"] = "PLEASE KEEP YOUR EYES ON ME",
	["VISITORS MUST SIGN IN AT RECEPTION"] = "VISITORS MAY NEVER SIGN OUT",
	["EXIT OVERRIDE"] = "EXIT OVERRIDDEN",
	["OPEN THEM IN THE ORDER YOU HEARD"] = "OPEN THEM IN THE ORDER YOU FEAR",
	["YOU WERE ALWAYS HERE"] = "YOU ARE ALWAYS HERE",
}

local function alteredText(original: string, rng): string
	if TEXT_SWAPS[original] then
		return TEXT_SWAPS[original]
	end
	local lines = string.split(original, "\n")
	if #lines > 1 then
		lines[rng:Int(1, #lines)] = "I CAN SEE YOU READING THIS"
		return table.concat(lines, "\n")
	end
	return string.reverse(original)
end

local function scrambleNumber(text: string, rng): string
	local options = {}
	-- swap the last two characters
	if #text >= 2 then
		local swapped = text:sub(1, #text - 2) .. text:sub(#text) .. text:sub(#text - 1, #text - 1)
		if swapped ~= text then
			table.insert(options, swapped)
		end
	end
	-- zero becomes a letter O
	if text:find("0") then
		table.insert(options, (text:gsub("0", "O", 1)))
	end
	table.insert(options, text .. "3")
	local shifted = text:gsub("%d", function(d)
		return tostring((tonumber(d) :: number + 7) % 10)
	end, 1)
	table.insert(options, shifted)
	return rng:Pick(options)
end

local VIVID = { Color3.fromRGB(120, 30, 28), Color3.fromRGB(200, 200, 194), Color3.fromRGB(40, 70, 110), Color3.fromRGB(150, 130, 40), Color3.fromRGB(20, 20, 20) }

return {
	{
		id = "PAINTING_SWAP",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Painting") do
				if not m:GetAttribute("Tutorial") and artFrames(m) then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, painting)
			local a, b, canvas = artFrames(painting)
			if not a or not b then
				return nil
			end
			return {
				claim = painting,
				ops = {
					{ t = "Prop", target = a, prop = "Visible", value = false },
					{ t = "Prop", target = b, prop = "Visible", value = true },
				},
				anchors = { ctx:anchor(canvas, 0.6) },
			}
		end,
	},
	{
		id = "PAINTING_GONE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Painting") do
				if not m:GetAttribute("Tutorial") and markOf(m) then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, painting)
			local mark = markOf(painting)
			if not mark then
				return nil
			end
			return {
				claim = painting,
				ops = { { t = "Hide", target = painting }, { t = "Show", target = mark } },
				anchors = { ctx:anchor(mark, 0.6) },
			}
		end,
	},
	{
		id = "CLOCK_WRONG",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Clock")
		end,
		create = function(ctx, clock)
			local face = clock:FindFirstChild("Face")
			if not face then
				return nil
			end
			local ops = {}
			if ctx.rng:Chance(0.35) then
				table.insert(ops, { t = "Attr", target = clock, name = "ClockMode", value = "backwards" })
			else
				local hours = ctx.rng:Pick({ -5, -3, 2, 4, 6 })
				table.insert(ops, { t = "Attr", target = clock, name = "ClockOffset", value = hours * 3600 + ctx.rng:Int(-900, 900) })
			end
			return { claim = clock, ops = ops, anchors = { ctx:anchor(face, 0.8) } }
		end,
	},
	{
		id = "CLOCK_STOPPED",
		difficulty = 4,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Clock")
		end,
		create = function(ctx, clock)
			local face = clock:FindFirstChild("Face")
			if not face then
				return nil
			end
			return {
				claim = clock,
				ops = { { t = "Attr", target = clock, name = "ClockMode", value = "stopped" } },
				anchors = { ctx:anchor(face, 0.8) },
			}
		end,
	},
	{
		id = "CHAIR_APPEARS",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind ~= "corridor" and room.kind ~= "stairs" and not room.secret and #room.floorSpots > 0 then
					for _, spot in room.floorSpots do
						table.insert(list, { pos = spot, room = room })
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			local door = c.room.doors[1]
			local look = if door then Util.flat(door.center - c.pos) else Vector3.new(0, 0, -1)
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, -1)
			end
			local cf = CFrame.lookAt(c.pos, c.pos + look.Unit)
			return {
				ops = { { t = "Clone", template = ctx:template("Chair"), parent = c.room.folder, cframe = cf, name = "Chair" } },
				anchors = { { pos = c.pos + Vector3.new(0, 2.4, 0), radius = 2.4 } },
			}
		end,
	},
	{
		id = "CHAIR_GONE",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Chair") do
				if isFloorProp(m) then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, chair)
			local c = ctx:center(chair)
			return {
				claim = chair,
				ops = { { t = "Hide", target = chair } },
				anchors = { { pos = c, radius = 2.6 } },
			}
		end,
	},
	{
		id = "EXTRA_DOOR",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if (room.kind == "corridor" or room.kind == "office" or room.kind == "reception" or room.kind == "gallery") and room.wallSpots then
					for _, spot in room.wallSpots do
						table.insert(list, { pos = spot.cframe.Position, cf = spot.cframe, room = room })
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			local cf = c.cf * CFrame.new(0, 0, -0.25)
			return {
				ops = { { t = "Clone", template = ctx:template("FalseDoor"), parent = c.room.folder, cframe = cf, name = "Door?" } },
				anchors = { { pos = (cf * CFrame.new(0, 5, 0)).Position, radius = 3.4 } },
			}
		end,
	},
	{
		id = "DOOR_GONE",
		difficulty = 3,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, rec in ctx.map.Doors do
				if rec.model and rec.model:HasTag("Door") and rec.model:GetAttribute("Kind") == "normal" then
					-- both rooms must keep another way in
					local a, b = ctx.map.Rooms[rec.roomA or ""], ctx.map.Rooms[rec.roomB or ""]
					if a and b and #a.doors >= 2 and #b.doors >= 2 and a.kind ~= "stairs" and b.kind ~= "stairs" then
						table.insert(list, rec)
					end
				end
			end
			return list
		end,
		requires = function(ctx)
			return not ctx.svc:GetActive().DOOR_PORTAL
		end,
		create = function(ctx, rec)
			if ctx:nearest(rec.center) < 10 then
				return nil
			end
			local cf = CFrame.lookAt(rec.center, rec.center + rec.passageDir)
			local plug = Instance.new("Part")
			plug.Name = "Plug"
			plug.Anchored = true
			plug.Size = Vector3.new(4, 10, 3.6)
			plug.CFrame = cf * CFrame.new(0, 5, 0)
			plug.Color = Color3.fromRGB(110, 108, 96)
			plug.Material = Enum.Material.Plaster
			plug.TopSurface = Enum.SurfaceType.Smooth
			plug.BottomSurface = Enum.SurfaceType.Smooth
			local template = Registry.RealityService:AddTemplate("Plug_" .. rec.id, plug, true)
			return {
				claim = rec.model,
				ops = {
					{ t = "Hide", target = rec.model },
					{ t = "Clone", template = template, parent = rec.model.Parent, name = "SealedDoorway" },
				},
				anchors = { { pos = rec.center + Vector3.new(0, 5, 0), radius = 3.6 } },
				lifetime = 120,
			}
		end,
	},
	{
		id = "WINDOW_CHANGE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Window")
		end,
		create = function(ctx, window)
			local boards = window:FindFirstChild("Boards")
			local prints = window:FindFirstChild("Handprints")
			if not boards or not prints then
				return nil
			end
			return {
				claim = window,
				ops = { { t = "Hide", target = boards }, { t = "Show", target = prints } },
				anchors = { ctx:anchor(window:FindFirstChild("Glass") or window, 0.4) },
			}
		end,
	},
	{
		id = "OBJECT_MOVED",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Movable") do
				if isFloorProp(m) and not m:HasTag("Chair") then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, model)
			local room = ctx:roomOf(model)
			if not room or #room.floorSpots == 0 then
				return nil
			end
			local from = model:GetPivot()
			local spot = ctx.rng:Pick(room.floorSpots)
			if (spot - from.Position).Magnitude < 5 then
				return nil
			end
			local target = CFrame.new(spot.X, from.Position.Y, spot.Z) * (from - from.Position) * CFrame.Angles(0, math.rad(ctx.rng:Pick({ 90, 180, 270 })), 0)
			local _, radius = ctx:center(model)
			return {
				claim = model,
				ops = { { t = "Pivot", target = model, cframe = target } },
				anchors = { { pos = target.Position + Vector3.new(0, 1.5, 0), radius = math.max(2, radius) } },
				checkPoints = { from.Position + Vector3.new(0, 1.5, 0), target.Position + Vector3.new(0, 1.5, 0) },
			}
		end,
	},
	{
		id = "OBJECT_COLOR",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Movable") do
				if largestPart(m) then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, model)
			local part = largestPart(model)
			if not part then
				return nil
			end
			local color = ctx.rng:Pick(VIVID)
			if (Vector3.new(color.R, color.G, color.B) - Vector3.new(part.Color.R, part.Color.G, part.Color.B)).Magnitude < 0.3 then
				color = Color3.fromRGB(200, 200, 194)
			end
			return {
				claim = model,
				ops = { { t = "Prop", target = part, prop = "Color", value = color } },
				anchors = { ctx:anchor(part, 0.6) },
			}
		end,
	},
	{
		id = "LAMP_CHANGE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Lamp") do
				table.insert(list, m)
			end
			for _, f in ctx:tagged("Fixture") do
				local room = ctx:roomOf(f)
				if room and room.kind ~= "corridor" and f:GetAttribute("Mode") ~= "dead" then
					table.insert(list, f)
				end
			end
			return list
		end,
		create = function(ctx, lamp)
			local tint = ctx.rng:Pick({ Color3.fromRGB(150, 255, 170), Color3.fromRGB(255, 120, 110), Color3.fromRGB(160, 140, 255) })
			if lamp:HasTag("Fixture") then
				return {
					claim = lamp,
					ops = { { t = "Attr", target = lamp, name = "Tint", value = tint }, { t = "Attr", target = lamp, name = "ForceOn", value = true } },
					anchors = { ctx:anchor(lamp, 1.5) },
				}
			end
			local shade, bulb
			for _, d in lamp:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Shade") then
					shade = d
				elseif d:IsA("BasePart") and d.Name == "Bulb" then
					bulb = d
				end
			end
			if not shade or not bulb then
				return nil
			end
			local light = bulb:FindFirstChildOfClass("SpotLight")
			local ops = {
				{ t = "Prop", target = shade, prop = "Color", value = tint:Lerp(Color3.new(), 0.4) },
				{ t = "Prop", target = bulb, prop = "Color", value = tint },
			}
			if light then
				table.insert(ops, { t = "Prop", target = light, prop = "Color", value = tint })
				table.insert(ops, { t = "Prop", target = light, prop = "Enabled", value = true })
			end
			return { claim = lamp, ops = ops, anchors = { ctx:anchor(lamp, 1) } }
		end,
	},
	{
		id = "PLANT_GONE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, m in ctx:tagged("Plant") do
				if markOf(m) then
					table.insert(list, m)
				end
			end
			return list
		end,
		create = function(ctx, plant)
			local mark = markOf(plant)
			if not mark then
				return nil
			end
			local c = ctx:center(plant)
			return {
				claim = plant,
				ops = { { t = "Hide", target = plant }, { t = "Show", target = mark } },
				anchors = { { pos = c, radius = 2.4 } },
			}
		end,
	},
	{
		id = "MIRROR_CHANGE",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Mirror")
		end,
		create = function(ctx, mirror)
			local glass = mirror:FindFirstChild("Glass")
			local overlay = glass and glass:FindFirstChild("Overlay")
			local crack = overlay and overlay:FindFirstChild("Crack")
			if not crack then
				return nil
			end
			return {
				claim = mirror,
				ops = { { t = "Prop", target = crack, prop = "Visible", value = true } },
				anchors = { ctx:anchor(glass, 0.3) },
			}
		end,
	},
	{
		id = "ROOM_NUMBER",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("RoomNumber")
		end,
		create = function(ctx, plate)
			local label = plate:FindFirstChild("Label", true)
			if not label or not label:IsA("TextLabel") then
				return nil
			end
			return {
				claim = plate,
				ops = { { t = "Prop", target = label, prop = "Text", value = scrambleNumber(label.Text, ctx.rng) } },
				anchors = { ctx:anchor(plate, 1) },
			}
		end,
	},
	{
		id = "TEXT_CHANGE",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, sign in ctx:tagged("Sign") do
				if sign:FindFirstChild("Label", true) then
					table.insert(list, sign)
				end
			end
			for _, board in ctx.map.Root:GetDescendants() do
				if board:IsA("Model") and board.Name == "NoticeBoard" and board:FindFirstChild("Label", true) then
					table.insert(list, board)
				end
			end
			return list
		end,
		create = function(ctx, sign)
			local ops = {}
			local anchorPart = nil
			for _, d in sign:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == "Label" then
					local original = d:GetAttribute("Original") or d.Text
					table.insert(ops, { t = "Prop", target = d, prop = "Text", value = alteredText(original, ctx.rng) })
					anchorPart = anchorPart or d:FindFirstAncestorWhichIsA("BasePart")
				end
			end
			if #ops == 0 or not anchorPart then
				return nil
			end
			return { claim = sign, ops = ops, anchors = { ctx:anchor(anchorPart, 1.2) } }
		end,
	},
	{
		id = "PHOTO_CHANGE",
		difficulty = 4,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Photo")
		end,
		create = function(ctx, photo)
			local a, b, canvas = artFrames(photo)
			if not a or not b then
				return nil
			end
			return {
				claim = photo,
				ops = {
					{ t = "Prop", target = a, prop = "Visible", value = false },
					{ t = "Prop", target = b, prop = "Visible", value = true },
				},
				anchors = { ctx:anchor(canvas, 0.8) },
			}
		end,
	},
	{
		id = "MANNEQUIN",
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
			-- it faces the way people come in
			local door = c.room.doors[ctx.rng:Int(1, math.max(1, #c.room.doors))]
			local look = if door then Util.flat(door.center - c.pos) else Vector3.new(0, 0, 1)
			if look.Magnitude < 0.1 then
				look = Vector3.new(0, 0, 1)
			end
			return {
				ops = { { t = "Clone", template = ctx:template("Mannequin"), parent = c.room.folder, cframe = CFrame.lookAt(c.pos, c.pos + look.Unit), name = "Mannequin" } },
				anchors = { { pos = c.pos + Vector3.new(0, 4, 0), radius = 3.2 } },
			}
		end,
	},
}
