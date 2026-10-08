--[[
	Locations
	Finds shot locations in whatever the player is standing in, read-only:

	  * inside a round: the procedural Ashgrove building (Workspace.Building).
	    Rooms are found from their floor parts (attribute "Room"), doors from
	    the "Door" tag (attributes RoomA / RoomB / ClosedCFrame), mirrors from
	    the "Mirror" tag. Room ids are fixed by the authored floor plan
	    (G_c ground corridor, U_c upper corridor, G_r reception, ...).
	  * anywhere else (lobby, empty baseplate): a virtual set in front of the
	    current camera, so every scene still plays (black-screen scenes need
	    nothing at all).

	Every function returns plain CFrames / positions; nothing is changed.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Locations = {}

export type Bounds = { id: string, min: Vector3, max: Vector3, center: Vector3, floorY: number, size: Vector3 }

local EYE = 5.4 -- camera height above the floor

function Locations.building(): Instance?
	return Workspace:FindFirstChild("Building")
end

function Locations.hasBuilding(): boolean
	return Locations.building() ~= nil
end

-- A reference frame for the virtual set: where the camera stands, level.
function Locations.reference(): CFrame
	local cam = Workspace.CurrentCamera.CFrame
	local look = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	local ground = cam.Position - Vector3.new(0, EYE, 0)
	return CFrame.lookAt(ground, ground + look.Unit)
end

local cache: { [string]: Bounds | false } = {}

function Locations.reset()
	table.clear(cache)
end

function Locations.room(id: string): Bounds?
	local hit = cache[id]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local building = Locations.building()
	local min, max = nil, nil
	if building then
		for _, d in building:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Floor" and d:GetAttribute("Room") == id then
				local half = d.Size / 2
				local p = d.CFrame.Position
				local lo, hi = p - half, p + half
				min = if min then min:Min(lo) else lo
				max = if max then max:Max(hi) else hi
			end
		end
	end
	if not min or not max then
		cache[id] = false
		return nil
	end
	local b: Bounds = { id = id, min = min, max = max, center = (min + max) / 2, floorY = max.Y, size = max - min }
	cache[id] = b
	return b
end

-- A long straight corridor shot along its length (east -> west by default).
function Locations.corridor(floorId: string?, reverse: boolean?): (CFrame, CFrame, number)
	local b = Locations.room((floorId or "G") .. "_c")
	if b then
		local y = b.floorY + EYE
		local z = b.center.Z
		local west = Vector3.new(b.min.X + 3, y, z)
		local east = Vector3.new(b.max.X - 3, y, z)
		local from, to = west, east
		if reverse then
			from, to = east, west
		end
		return CFrame.lookAt(from, to), CFrame.lookAt(to, to + (to - from).Unit), (to - from).Magnitude
	end
	local ref = Locations.reference()
	local from = ref * CFrame.new(0, EYE, 0)
	return from, from * CFrame.new(0, 0, -60), 60
end

-- Points on the corridor's centre line at a fraction 0..1 of its length.
function Locations.corridorPoint(floorId: string?, fraction: number, height: number?): Vector3
	local from, _, length = Locations.corridor(floorId)
	local p = from.Position + from.LookVector * length * fraction
	return Vector3.new(p.X, p.Y - EYE + (height or 0), p.Z)
end

-- A door between `roomId` and a corridor, with a camera spot in the corridor
-- facing it. Returns the door model (or nil in the virtual set), the door's
-- centre on the floor, and the camera CFrame `distance` studs in front of it.
function Locations.doorShot(roomIds: { string }, distance: number?): (Model?, CFrame, CFrame)
	distance = distance or 9
	for _, roomId in roomIds do
		local room = Locations.room(roomId)
		for _, m in CollectionService:GetTagged("Door") do
			if m:IsA("Model") and m:IsDescendantOf(Workspace) and room then
				local a, b = m:GetAttribute("RoomA"), m:GetAttribute("RoomB")
				local other = if a == roomId then b elseif b == roomId then a else nil
				local closed = m:GetAttribute("ClosedCFrame")
				if other and typeof(closed) == "CFrame" and string.sub(tostring(other), -2) == "_c" then
					local corridor = Locations.room(other :: string)
					if corridor then
						local doorPos = Vector3.new(closed.Position.X, corridor.floorY, closed.Position.Z)
						-- face from the corridor side: away from the room's centre
						local away = Vector3.new(doorPos.X - room.center.X, 0, doorPos.Z - room.center.Z)
						if math.abs(away.X) > math.abs(away.Z) then
							away = Vector3.new(math.sign(away.X), 0, 0)
						else
							away = Vector3.new(0, 0, math.sign(away.Z))
						end
						local camPos = doorPos + away * (distance :: number) + Vector3.new(0, EYE, 0)
						local doorFloor = CFrame.lookAt(doorPos, doorPos + away)
						return m, doorFloor, CFrame.lookAt(camPos, doorPos + Vector3.new(0, EYE - 0.6, 0))
					end
				end
			end
		end
	end
	-- virtual set: a door ahead of the camera
	local ref = Locations.reference()
	local doorFloor = ref * CFrame.new(0, 0, -(distance :: number)) * CFrame.Angles(0, math.pi, 0)
	local cam = ref * CFrame.new(0, EYE, 0)
	return nil, doorFloor, CFrame.lookAt(cam.Position, doorFloor.Position + Vector3.new(0, EYE - 0.6, 0))
end

-- Inside a room, standing in its doorway (or one end), looking at the far wall.
function Locations.roomShot(roomIds: { string }): (CFrame, Vector3, Bounds?)
	for _, id in roomIds do
		local b = Locations.room(id)
		if b then
			local y = b.floorY + EYE
			-- look along the room's longer axis, from one end to the other
			local from, to
			if b.size.X >= b.size.Z then
				from = Vector3.new(b.min.X + 2.5, y, b.center.Z)
				to = Vector3.new(b.max.X - 0.5, y - 0.4, b.center.Z)
			else
				from = Vector3.new(b.center.X, y, b.min.Z + 2.5)
				to = Vector3.new(b.center.X, y - 0.4, b.max.Z - 0.5)
			end
			return CFrame.lookAt(from, to), to, b
		end
	end
	local ref = Locations.reference()
	local cam = ref * CFrame.new(0, EYE, 0)
	return cam, (cam * CFrame.new(0, -0.4, -30)).Position, nil
end

-- A high corner of a corridor, looking down its length (security camera).
function Locations.cctvShot(floorId: string?): (CFrame, Vector3, Vector3)
	local b = Locations.room((floorId or "G") .. "_c")
	if b then
		local ceiling = b.floorY + 11.5
		local corner = Vector3.new(b.min.X + 1.5, ceiling, b.min.Z + 1.2)
		local walkFrom = Vector3.new(b.min.X + 30, b.floorY, b.center.Z + 1)
		local walkTo = Vector3.new(b.min.X + 6, b.floorY, b.center.Z - 1)
		local look = Vector3.new(b.min.X + 22, b.floorY + 2, b.center.Z)
		return CFrame.lookAt(corner, look), walkFrom, walkTo
	end
	local ref = Locations.reference()
	local corner = (ref * CFrame.new(-4, 11, 0)).Position
	local look = (ref * CFrame.new(0, 2, -20)).Position
	return CFrame.lookAt(corner, look), (ref * CFrame.new(3, 0, -26)).Position, (ref * CFrame.new(-3, 0, -8)).Position
end

-- The nearest mirror's glass (a reflective surface for messages), or nil.
function Locations.mirror(): BasePart?
	local best, bestD = nil, math.huge
	local cam = Workspace.CurrentCamera.CFrame.Position
	for _, m in CollectionService:GetTagged("Mirror") do
		local glass = m:FindFirstChild("Glass")
		if glass and glass:IsA("BasePart") and m:IsDescendantOf(Workspace) then
			local d = (glass.Position - cam).Magnitude
			if d < bestD then
				best, bestD = glass, d
			end
		end
	end
	return best
end

-- Floor height under a point (raycast), or the given fallback.
function Locations.floorAt(position: Vector3, fallback: number?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local rt = Workspace:FindFirstChild("MarketingRuntime")
	if rt then
		table.insert(exclude, rt)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), params)
	if hit then
		return hit.Position.Y
	end
	return fallback or position.Y
end

Locations.EyeHeight = EYE

return Locations
