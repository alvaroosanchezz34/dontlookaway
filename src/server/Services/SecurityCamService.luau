--[[
	SecurityCamService
	The building's old security cameras. Players who are out of the round (taken,
	shut in or already outside) are not out of the game: they can watch through
	the cameras, and what a live camera sees counts as looked at. The Observer
	holds still on camera exactly as it does for the living, so a dead teammate
	can keep it off you.

	It follows the rules of the building:
	  * the cameras run on the building's power. During the outage, and wherever
	    a blackout leaves the room dark, the feed shows nothing useful: restoring
	    the power is also what brings the eyes of the dead back
	  * a camera sees only what is lit (no night vision), within Range and its
	    lens angle, with line of sight
	  * one camera per viewer. A feed holds for HoldTime seconds of live picture,
	    then the old tape rewinds for Cooldown seconds; switching cameras does not
	    reset it
	  * the forced blink from staring applies to the viewer too (ObserverService)
	Server-authoritative: the client only says which camera it wants.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local Layout = require(script.Parent.Parent.Map.Layout)
local Registry = require(script.Parent.Parent.Registry)

local SecurityCamService = {}

type Cam = { index: number, cf: CFrame, label: string, part: BasePart, led: BasePart }
type Viewer = { index: number, held: number, coolUntil: number }

local Status = Enums.PlayerStatus
local cams: { Cam } = {}
local viewers: { [Player]: Viewer } = {}
local folder: Folder? = nil

local function cfg()
	return GameConfig.SecurityCams
end

local function clearViewer(player: Player)
	viewers[player] = nil
	player:SetAttribute("CamIndex", nil)
	player:SetAttribute("CamState", nil)
	player:SetAttribute("CamHold", nil)
end

local function clear()
	for player in viewers do
		clearViewer(player)
	end
	viewers = {}
	cams = {}
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- Out of the round but part of it: taken, shut in, lost or already outside.
local function eligible(player: Player): boolean
	if not player.Parent or not Registry.RoundService:IsRunning() or not Registry.RoundService:IsParticipant(player) then
		return false
	end
	local status = Registry.PlayerService:GetStatus(player)
	return status == Status.Dead or status == Status.Escaped
end

local function powered(): boolean
	return workspace:GetAttribute("Power") == true
end

------------------------------------------------------------------------------------
-- Mounting the cameras
------------------------------------------------------------------------------------

local CORNERS = { { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }

-- A ceiling corner of the room that can see its middle, or nil.
local function mountFor(room): CFrame?
	local cell = Layout.Cell
	local y = room.floorY + Layout.CeilingHeight - 1.2
	local target = room.center + Vector3.new(0, 3, 0)
	for _, c in CORNERS do
		local x = if c[1] < 0 then room.minX else room.maxX
		local z = if c[2] < 0 then room.minZ else room.maxZ
		if room.cellSet[z * 10000 + x] then
			local edgeX = Layout.Origin.X + (x + (if c[1] < 0 then 0 else 1)) * cell
			local edgeZ = Layout.Origin.Z + (z + (if c[2] < 0 then 0 else 1)) * cell
			local pos = Vector3.new(edgeX - c[1] * 1.2, y, edgeZ - c[2] * 1.2)
			if Registry.PlayerService:HasLineOfSight(pos, target) then
				return CFrame.lookAt(pos, target)
			end
		end
	end
	return nil
end

local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- never blocks a view ray or a line of sight
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build(map)
	clear()
	local c = cfg()
	local rng = SeededRandom.new(map.Seed or 0, "cams")
	local corridors, rooms = {}, {}
	for id, room in map.Rooms do
		if not room.secret and room.kind ~= "closet" and room.kind ~= "stairs" and room.kind ~= "secret" and room.center then
			if room.kind == "corridor" then
				table.insert(corridors, { id = id, room = room })
			elseif (room.area or 0) >= 48 then
				table.insert(rooms, { id = id, room = room })
			end
		end
	end
	local byId = function(a, b)
		return a.id < b.id
	end
	table.sort(corridors, byId)
	table.sort(rooms, byId)
	rng:Shuffle(rooms)
	local chosen = {}
	for _, r in corridors do
		table.insert(chosen, r)
	end
	for _, r in rooms do
		if #chosen >= c.Count then
			break
		end
		table.insert(chosen, r)
	end
	folder = Instance.new("Folder")
	folder.Name = "SecurityCams"
	for _, r in chosen do
		local cf = mountFor(r.room)
		if cf then
			local index = #cams + 1
			local label = string.format("CAM %02d  %s", index, r.room.name or r.id)
			local body = makePart("SecurityCam", Vector3.new(0.7, 0.55, 1.2), cf, Color3.fromRGB(46, 46, 44), Enum.Material.Metal, folder :: Folder)
			body:SetAttribute("Index", index)
			body:SetAttribute("Label", label)
			makePart("Lens", Vector3.new(0.4, 0.4, 0.1), cf * CFrame.new(0, 0, -0.62), Color3.fromRGB(10, 10, 12), Enum.Material.Glass, body)
			local led = makePart("Led", Vector3.new(0.12, 0.12, 0.05), cf * CFrame.new(0.22, 0.18, -0.6), Color3.fromRGB(60, 20, 20), Enum.Material.Neon, body)
			table.insert(cams, { index = index, cf = cf, label = label, part = body, led = led })
		end
	end
	folder.Parent = workspace
end

------------------------------------------------------------------------------------
-- Seeing
------------------------------------------------------------------------------------

local function camSees(cam: Cam, point: Vector3, ignore: Instance?): boolean
	local c = cfg()
	local delta = point - cam.cf.Position
	local dist = delta.Magnitude
	if dist > c.Range or dist < 0.1 then
		return false
	end
	if cam.cf.LookVector:Dot(delta / dist) < math.cos(math.rad(c.HalfAngle)) then
		return false
	end
	if Registry.LightingService:IsDark(point) and not Registry.LightingService:IsLit(point) then
		return false
	end
	return Registry.PlayerService:HasLineOfSight(cam.cf.Position, point, ignore)
end

-- Players whose camera feed is live right now.
function SecurityCamService:LiveViewers(): { Player }
	local list = {}
	for player in viewers do
		if player:GetAttribute("CamState") == "LIVE" then
			table.insert(list, player)
		end
	end
	return list
end

-- Does this viewer's live camera see any of the points?
function SecurityCamService:ViewerSees(player: Player, points: { Vector3 }, ignore: Instance?): boolean
	local v = viewers[player]
	local cam = v and cams[v.index]
	if not cam or player:GetAttribute("CamState") ~= "LIVE" then
		return false
	end
	for _, pt in points do
		if camSees(cam, pt, ignore) then
			return true
		end
	end
	return false
end

-- Does any live camera see any of the points?
function SecurityCamService:AnySees(points: { Vector3 }, ignore: Instance?): boolean
	for player in viewers do
		if self:ViewerSees(player, points, ignore) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------------
-- Viewers
------------------------------------------------------------------------------------

local function onSelect(player: Player, index: any)
	if type(index) ~= "number" or index ~= index then
		return
	end
	index = math.floor(index)
	if index == 0 or not eligible(player) then
		clearViewer(player)
		return
	end
	if index < 1 or index > #cams then
		return
	end
	local v = viewers[player]
	if v then
		v.index = index -- the tape keeps running: switching never resets the hold
	else
		viewers[player] = { index = index, held = 0, coolUntil = 0 }
	end
	player:SetAttribute("CamIndex", index)
end

local function step(dt: number)
	local c = cfg()
	local now = os.clock()
	local on = powered()
	local liveCams: { [number]: boolean } = {}
	for player, v in viewers do
		if not eligible(player) then
			clearViewer(player)
			continue
		end
		local state
		if now < v.coolUntil then
			state = "REWIND"
		elseif not on then
			state = "STATIC"
		else
			state = "LIVE"
			v.held += dt
			if v.held >= c.HoldTime then
				v.held = 0
				v.coolUntil = now + c.Cooldown
				state = "REWIND"
			end
		end
		if state == "LIVE" then
			liveCams[v.index] = true
		end
		player:SetAttribute("CamState", state)
		player:SetAttribute("CamHold", if state == "REWIND" then -(v.coolUntil - now) else c.HoldTime - v.held)
	end
	-- the red light on a camera someone is watching through
	for _, cam in cams do
		if cam.led.Parent then
			cam.led.Color = if liveCams[cam.index] then Color3.fromRGB(255, 40, 30) else Color3.fromRGB(60, 20, 20)
		end
	end
end

function SecurityCamService:Init()
	Net.on("SecurityCam", onSelect)
end

function SecurityCamService:Start()
	Registry.MapService.MapBuilt:Connect(function(map)
		local ok, err = pcall(build, map)
		if not ok then
			warn("[SecurityCamService] cameras not mounted: " .. tostring(err))
		end
	end)
	Registry.RoundService.StateChanged:Connect(function(state)
		if state == Enums.RoundState.Returning or state == Enums.RoundState.Lobby then
			for player in viewers do
				clearViewer(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		viewers[player] = nil
	end)
	local last = os.clock()
	while true do
		task.wait(0.1)
		local now = os.clock()
		step(now - last)
		last = now
	end
end

return SecurityCamService
