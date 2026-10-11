--[[
	Mimic (driver)
	THE MIMIC: something that has learned to look like one of you, almost.
	At a distance it passes: it wears a teammate's clothes and name tag. Up
	close it is wrong in every way that matters:
	  * too tall and too thin (height x1.15, width x0.78), head a little small
	  * grey, bloodless skin on every limb
	  * no face of its own: two tall black eyes, and a mouth that is a thin
	    line almost from ear to ear (drawn on the head; the avatar's face and
	    dynamic head are removed)
	  * the clothes washed out, as if copied from memory
	  * it holds its head tilted and its shoulders forward
	The tells of the original design stay: no flashlight, silent steps, a
	glitching name tag, a head that turns too far when it stops, a wave that
	is too slow, a fake ping with a friend's name. Reporting it unmasks it.

	Why it used to look exactly like a player and walk into walls:
	  * it was built with Players:CreateHumanoidModelFromDescription from the
	    imitated player's description, unchanged (and from your own when you
	    spawn it alone from the admin panel): a perfect copy of an avatar
	  * it walked a straight line to a point 20 studs "away from the viewer"
	    with Humanoid:MoveTo every tick, no pathfinding, no check that the
	    point was reachable, and no stuck detection; and its walk animation
	    played even while it stood still

	This driver measures the world for MimicBrain (the state machine), walks
	real paths (PathfindingService, re-planned when blocked), detects being
	stuck, plays Roblox's own R15 idle / walk / run animations on its R15 rig
	and switches them by its real speed, and cleans everything up when it
	leaves. ObserverService keeps the public API (Mimic, ReportMimic, OnPing).
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)
local MimicBrain = require(script.Parent.MimicBrain)

local Mimic = {}

local S = MimicBrain.States

-- Roblox's default R15 animations (the ones the stock Animate script uses):
-- owned by Roblox, they load on any R15 rig in any experience.
Mimic.Animations = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
}

local SKIN = Color3.fromRGB(150, 150, 142) -- bloodless grey
local CLOTH_TINT = Color3.fromRGB(150, 146, 142) -- washed-out clothes
local PATH_PARAMS = { AgentRadius = 1.5, AgentHeight = 6.5, AgentCanJump = false, WaypointSpacing = 4 }
local STUCK_AFTER = 2.2 -- seconds trying to move without making progress

type Data = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	viewer: Player,
	imitated: Player?,
	state: string,
	stateAt: number,
	spawned: number,
	reason: string?,
	seenFor: number,
	lastSeen: number,
	lastLos: number,
	waved: boolean,
	pinged: boolean,
	pingAt: number,
	ping: Vector3?,
	destination: Vector3?,
	waypoints: { any },
	wpIndex: number,
	pathAt: number,
	pathPending: boolean,
	picking: boolean,
	routeFailed: boolean,
	blocked: RBXScriptConnection?,
	progressPos: Vector3,
	progressAt: number,
	stuck: boolean,
	stuckCount: number,
	recoveries: number,
	recovered: boolean,
	failedSpots: { Vector3 },
	tracks: { [string]: AnimationTrack },
	animStatus: { [string]: string },
	playing: string?,
	attacked: boolean,
	history: { string },
}

local current: Data? = nil
local helpers: { [string]: any } = {}

-- ObserverService passes its spot helpers (candidateSpots, unseenAt).
function Mimic.init(h: { [string]: any })
	helpers = h
end

function Mimic.get(): Model?
	return if current then current.model else nil
end

local function log(text: string)
	print("[Mimic] " .. text)
end

------------------------------------------------------------------------------------
-- Model
------------------------------------------------------------------------------------

local function description(imitated: Player?): HumanoidDescription
	local desc: HumanoidDescription? = nil
	local h = imitated and imitated.Character and imitated.Character:FindFirstChildOfClass("Humanoid")
	if h then
		local ok, d = pcall(function()
			return h:GetAppliedDescription()
		end)
		if ok and d then
			desc = d
		end
	end
	local d = desc or Instance.new("HumanoidDescription")
	-- its own body: taller, thinner, a little small in the head
	d.HeightScale = 1.15
	d.WidthScale = 0.78
	d.DepthScale = 0.82
	d.HeadScale = 0.92
	d.BodyTypeScale = 0
	d.ProportionScale = 0
	-- no face or dynamic head of its own: a plain head we draw on
	d.Head = 0
	d.Face = 0
	d.FaceAccessory = ""
	for _, part in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
		(d :: any)[part] = SKIN
	end
	return d
end

-- Two tall black eyes, a little uneven, and a mouth almost ear to ear.
local function drawFace(head: BasePart)
	for _, d in head:GetChildren() do
		if d:IsA("Decal") or d:IsA("FaceControls") then
			d:Destroy()
		end
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "MimicFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 1
	gui.Parent = head
	local function oval(x, y, w, h, color, rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Rotation = rot or 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		f.Parent = gui
		return f
	end
	oval(0.33, 0.4, 0.13, 0.27, Color3.fromRGB(4, 4, 4), -4)
	oval(0.67, 0.42, 0.12, 0.24, Color3.fromRGB(4, 4, 4), 6)
	-- a pale point in each, slightly off, as if looking past you
	oval(0.34, 0.37, 0.025, 0.025, Color3.fromRGB(200, 196, 186))
	oval(0.665, 0.39, 0.025, 0.025, Color3.fromRGB(200, 196, 186))
	-- the mouth: a thin line, too wide, rising at one end
	oval(0.5, 0.72, 0.86, 0.022, Color3.fromRGB(26, 10, 10), -3)
end

local function posture(model: Model)
	-- head tilted, shoulders and chest pitched forward: it stands like something
	-- that has only seen people from far away. C0 changes keep every animation.
	local head = model:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		neck.C0 = neck.C0 * CFrame.Angles(math.rad(-10), 0, math.rad(17))
	end
	local upper = model:FindFirstChild("UpperTorso")
	local waist = upper and upper:FindFirstChild("Waist")
	if waist and waist:IsA("Motor6D") then
		waist.C0 = waist.C0 * CFrame.Angles(math.rad(-7), 0, 0)
	end
end

local function washClothes(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("Shirt") or d:IsA("Pants") then
			d.Color3 = CLOTH_TINT
		elseif d:IsA("ShirtGraphic") then
			d.Color3 = CLOTH_TINT
		elseif d:IsA("Accessory") and d.AccessoryType == Enum.AccessoryType.Face then
			d:Destroy()
		end
	end
end

-- Builds the rig. Returns (model, error).
local function build(imitated: Player?): (Model?, string?)
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description(imitated), Enum.HumanoidRigType.R15)
	end)
	if not ok or not m then
		-- fall back to a plain description (the imitated avatar may not load)
		ok, m = pcall(function()
			local d = Instance.new("HumanoidDescription")
			d.HeightScale, d.WidthScale, d.DepthScale, d.HeadScale = 1.15, 0.78, 0.82, 0.92
			for _, part in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
				(d :: any)[part] = SKIN
			end
			return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
		end)
		if not ok or not m then
			return nil, "CreateHumanoidModelFromDescription failed: " .. tostring(m)
		end
	end
	local model = m :: Model
	model.Name = "Mimic"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not humanoid or not root or not head or not root:IsA("BasePart") or not head:IsA("BasePart") then
		model:Destroy()
		return nil, "rig incomplete (Humanoid / HumanoidRootPart / Head)"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		model:Destroy()
		return nil, "rig is not R15"
	end
	model.PrimaryPart = root
	drawFace(head)
	washClothes(model)
	posture(model)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Mimic"
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	return model, nil
end

------------------------------------------------------------------------------------
-- Spot validation
------------------------------------------------------------------------------------

local function overlapParams(ignore: { Instance }): OverlapParams
	local p = OverlapParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = true
	return p
end

local function characters(): { Instance }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- A floor spot where a body fits: ground below, nothing solid in the volume.
function Mimic.spotFits(spot: Vector3, ignore: { Instance }?): (boolean, string?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or characters()
	local ground = workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -7, 0), params)
	if not ground then
		return false, "no floor"
	end
	local body = CFrame.new(ground.Position + Vector3.new(0, 3.6, 0))
	local hits = workspace:GetPartBoundsInBox(body, Vector3.new(2.2, 5.6, 2.2), overlapParams(ignore or characters()))
	for _, h in hits do
		if h.CanCollide and h.CollisionGroup ~= "Doors" then
			return false, "inside " .. h:GetFullName()
		end
	end
	return true, nil
end

local function pathTo(a: Vector3, b: Vector3): Path?
	local okC, path = pcall(function()
		return PathfindingService:CreatePath(PATH_PARAMS)
	end)
	if not okC or not path then
		return nil
	end
	local ok = pcall(function()
		path:ComputeAsync(a, b)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path
	end
	return nil
end

------------------------------------------------------------------------------------
-- Animation
------------------------------------------------------------------------------------

local function loadAnimations(data: Data)
	local animator = data.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = data.humanoid
	for name, id in Mimic.Animations do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			data.tracks[name] = track
			data.animStatus[name] = "loading"
		else
			data.animStatus[name] = "failed: " .. tostring(track)
			warn("[Mimic] could not load animation " .. name .. " (" .. id .. "): " .. tostring(track))
		end
	end
	-- confirm they really loaded (Length > 0 once the asset arrives)
	task.spawn(function()
		local deadline = os.clock() + 5
		while os.clock() < deadline and current == data do
			local pending = false
			for name, track in data.tracks do
				if data.animStatus[name] == "loading" then
					if track.Length > 0 then
						data.animStatus[name] = "ok"
					else
						pending = true
					end
				end
			end
			if not pending then
				return
			end
			task.wait(0.25)
		end
		for name, status in data.animStatus do
			if status == "loading" then
				data.animStatus[name] = "did not load"
				warn("[Mimic] animation " .. name .. " did not load in 5 s")
			end
		end
	end)
end

-- The track that matches its real speed: no walking on the spot.
local function updateAnimation(data: Data)
	local v = data.root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local want = if speed < 0.5 then "idle" elseif speed < 12 then "walk" else "run"
	if data.playing ~= want then
		if data.playing and data.tracks[data.playing] then
			data.tracks[data.playing]:Stop(0.25)
		end
		local t = data.tracks[want]
		if t then
			t:Play(0.25)
		end
		data.playing = want
	end
	local t = data.tracks[want]
	if t then
		if want == "walk" then
			-- slightly slower than its feet: a stride that does not quite fit
			t:AdjustSpeed(math.clamp(speed / 14, 0.35, 1.1))
		elseif want == "run" then
			t:AdjustSpeed(math.clamp(speed / 18, 0.6, 1.3))
		else
			t:AdjustSpeed(0.6)
		end
	end
end

------------------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------------------

local function clearRoute(data: Data)
	if data.blocked then
		data.blocked:Disconnect()
		data.blocked = nil
	end
	data.waypoints = {}
	data.wpIndex = 0
end

local function route(data: Data, goal: Vector3)
	if data.pathPending then
		return
	end
	data.pathPending = true
	data.pathAt = os.clock()
	data.destination = goal
	local from = data.root.Position
	task.spawn(function()
		local path = pathTo(from, goal)
		data.pathPending = false
		if current ~= data then
			return
		end
		clearRoute(data)
		if not path then
			data.routeFailed = true
			return
		end
		data.routeFailed = false
		data.waypoints = path:GetWaypoints()
		-- start at the first waypoint ahead of where it is now
		local best, bestD = 1, math.huge
		for i, wp in data.waypoints do
			local d = Util.flat(wp.Position - data.root.Position).Magnitude
			if d < bestD then
				best, bestD = i, d
			end
		end
		data.wpIndex = math.min(#data.waypoints, best + 1)
		data.blocked = path.Blocked:Connect(function(blockedIndex)
			if blockedIndex >= data.wpIndex and data.destination then
				route(data, data.destination)
			end
		end)
	end)
end

-- Follows the current route. Returns true once at the destination.
local function follow(data: Data, speed: number): boolean
	data.humanoid.WalkSpeed = speed
	local wp = data.waypoints[data.wpIndex]
	if not wp then
		data.humanoid:Move(Vector3.zero)
		return data.destination ~= nil and not data.pathPending and Util.flat(data.destination - data.root.Position).Magnitude < 3
	end
	if Util.flat(wp.Position - data.root.Position).Magnitude < 2.2 then
		if data.wpIndex >= #data.waypoints then
			clearRoute(data)
			data.humanoid:Move(Vector3.zero)
			return true
		end
		data.wpIndex += 1
		wp = data.waypoints[data.wpIndex]
	end
	data.humanoid:MoveTo(wp.Position)
	Registry.DoorService:OpenNear(data.root.Position, 6)
	return false
end

local function stand(data: Data)
	data.humanoid.WalkSpeed = 0
	data.humanoid:Move(Vector3.zero)
	data.progressAt = os.clock()
	data.progressPos = data.root.Position
end

-- Stuck: it has been trying to move for STUCK_AFTER seconds without getting anywhere.
local function checkStuck(data: Data, moving: boolean)
	local now = os.clock()
	if not moving or (data.root.Position - data.progressPos).Magnitude > 1.2 then
		data.progressPos = data.root.Position
		data.progressAt = now
		data.stuck = false
	elseif now - data.progressAt > STUCK_AFTER then
		data.stuck = true
	end
end

local function isFailed(data: Data, spot: Vector3): boolean
	for _, f in data.failedSpots do
		if (f - spot).Magnitude < 4 then
			return true
		end
	end
	return false
end

-- A reachable spot to walk to: near its viewer for patrols, near itself for
-- recovery. Yields (pathfinding): only call from pickInBackground.
local function pickSpot(data: Data, around: Vector3, minD: number, maxD: number): Vector3?
	local spots = helpers.candidateSpots and helpers.candidateSpots(minD, maxD, around, true) or {}
	Registry.HorrorDirector:Rng():Shuffle(spots)
	local tries = 0
	for _, spot in spots do
		if (spot - data.root.Position).Magnitude > 8 and not isFailed(data, spot) then
			tries += 1
			if pathTo(data.root.Position, spot) then
				return spot
			end
			table.insert(data.failedSpots, spot)
			if tries >= 5 then
				break
			end
		end
	end
	return nil
end

-- Chooses a destination without blocking the tick; `done(spot?)` runs after.
local function pickInBackground(data: Data, around: Vector3, minD: number, maxD: number, done: (Vector3?) -> ())
	if data.picking or data.pathPending then
		return
	end
	data.picking = true
	task.spawn(function()
		local spot = pickSpot(data, around, minD, maxD)
		data.picking = false
		if current == data then
			done(spot)
		end
	end)
end

------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------

local function setState(data: Data, state: string, reason: string?)
	if data.state == state then
		return
	end
	local line = string.format("%s -> %s%s", data.state, state, if reason then " (" .. reason .. ")" else "")
	table.insert(data.history, line)
	if #data.history > 12 then
		table.remove(data.history, 1)
	end
	data.state = state
	data.stateAt = os.clock()
	data.reason = reason
	data.model:SetAttribute("MimicState", state)
	data.routeFailed = false
	data.stuck = false
	data.recovered = false
	data.progressAt = os.clock()
	data.progressPos = data.root.Position
	clearRoute(data)
	data.destination = nil
	if state == S.RECOVERING then
		data.recoveries += 1
	end
end

-- Leaves: unseen, it is simply gone; seen, its head turns all the way round
-- first. `lunge`: it attacked (the viewer gets the scare, and maybe a hunt).
function Mimic.finish(lunge: boolean, why: string?)
	local data = current
	if not data then
		return
	end
	current = nil
	clearRoute(data)
	local m = data.model
	local viewer = data.viewer
	for _, t in data.tracks do
		t:Stop(0.2)
	end
	log("gone: " .. tostring(why or data.reason or "despawn"))
	local seen = helpers.unseenAt and not helpers.unseenAt(data.root.Position - Vector3.new(0, 3, 0)) or false
	m:SetAttribute("Reveal", seen or lunge)
	local head = m:FindFirstChild("Head") :: BasePart?
	if head and (seen or lunge) then
		Registry.AudioService:PlayAt("ObserverTwitch", head.Position)
	end
	task.delay(if lunge then 0.35 elseif seen then 0.9 else 0, function()
		-- (the lunge's sting is played by the viewer's client with its face)
		Registry.PlayerService:RemovePerceptionExclusion(m)
		m:Destroy()
		if lunge and viewer and helpers.onLunge then
			helpers.onLunge(viewer)
		end
	end)
end

-- Spawns the mimic for `viewer` wearing `imitated`'s clothes. Returns
-- (ok, message). Same path for the director and the admin command.
function Mimic.spawn(viewer: Player, imitated: Player?): (boolean, string)
	if current then
		return false, "a mimic is already out"
	end
	local vroot = Util.getRoot(viewer)
	local look = Registry.PlayerService:GetLook(viewer)
	if not vroot or not look then
		return false, "viewer has no character"
	end
	-- somewhere the viewer will notice soon but cannot see right now, where a
	-- body fits, with a real route to the viewer
	local spot: Vector3? = nil
	local rejected = 0
	for _, s in (helpers.candidateSpots and helpers.candidateSpots(22, 60, vroot.Position, true) or {}) do
		local headAt = s + Vector3.new(0, 4.5, 0)
		if helpers.unseenAt(s) and Registry.PlayerService:HasLineOfSight(look.origin, headAt) then
			local fits = Mimic.spotFits(s)
			if fits and pathTo(s + Vector3.new(0, 3, 0), vroot.Position) then
				spot = s
				break
			end
			rejected += 1
			if rejected > 8 then
				break
			end
		end
	end
	if not spot then
		return false, "no valid spot (unseen, in view later, fits a body, reachable)"
	end
	local model, err = build(imitated)
	if not model then
		warn("[Mimic] spawn failed: " .. tostring(err))
		return false, "model: " .. tostring(err)
	end
	local m = model :: Model
	m:SetAttribute("PlayerName", if imitated then imitated.DisplayName else viewer.DisplayName)
	m:SetAttribute("Title", if imitated then imitated:GetAttribute("Title") else nil)
	m:SetAttribute("Mimic", true)
	m:AddTag("NameTagged")
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = m.PrimaryPart :: BasePart
	-- standing on the floor (HipHeight + half the root above the ground), back
	-- turned to the viewer
	local away = Util.flat((spot :: Vector3) - vroot.Position)
	local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local y = (spot :: Vector3).Y + humanoid.HipHeight + root.Size.Y / 2
	local at = Vector3.new((spot :: Vector3).X, y, (spot :: Vector3).Z)
	m:PivotTo(CFrame.lookAt(at, at + dir))
	m.Parent = workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	Registry.PlayerService:AddPerceptionExclusion(m)
	local rng = Registry.HorrorDirector:Rng()
	local data: Data = {
		model = m,
		humanoid = humanoid,
		root = root,
		viewer = viewer,
		imitated = imitated,
		state = S.SPAWNING,
		stateAt = os.clock(),
		spawned = os.clock(),
		reason = nil,
		seenFor = 0,
		lastSeen = 0,
		lastLos = os.clock(),
		waved = false,
		pinged = false,
		pingAt = if imitated and imitated ~= viewer and rng:Chance(0.35) then os.clock() + rng:Number(4, 8) else math.huge,
		ping = nil,
		destination = nil,
		waypoints = {},
		wpIndex = 0,
		pathAt = 0,
		pathPending = false,
		picking = false,
		routeFailed = false,
		blocked = nil,
		progressPos = root.Position,
		progressAt = os.clock(),
		stuck = false,
		stuckCount = 0,
		recoveries = 0,
		recovered = false,
		failedSpots = {},
		tracks = {},
		animStatus = {},
		playing = nil,
		attacked = false,
		history = {},
	}
	current = data
	m:SetAttribute("MimicState", S.SPAWNING)
	loadAnimations(data)
	log(string.format("spawned for %s wearing %s at %s", viewer.Name, if imitated then imitated.Name else "a plain body", tostring(spot)))
	return true, "mimic placed"
end

-- A real ping near it: it stops and stares at whoever pinged (very close), or
-- goes to look (further away).
function Mimic.onPing(from: Player, position: Vector3)
	local data = current
	if not data then
		return
	end
	local d = (data.root.Position - position).Magnitude
	if d < 7 then
		local froot = Util.getRoot(from)
		if froot then
			data.model:SetAttribute("StareAt", froot.Position)
		end
		data.model:SetAttribute("Pause", true)
		local head = data.model:FindFirstChild("Head") :: BasePart?
		if head then
			Registry.AudioService:PlayAt("ObserverCrack", head.Position, { volume = 0.6 })
		end
	elseif d < 40 then
		data.ping = position
	end
end

function Mimic.tick(dt: number)
	local data = current
	if not data then
		return
	end
	local m = data.model
	if not m.Parent or not data.root.Parent then
		current = nil
		clearRoute(data)
		return
	end
	local now = os.clock()
	local viewer = data.viewer
	local vroot = Util.getRoot(viewer)
	local alive = vroot ~= nil and Registry.PlayerService:IsAlive(viewer)
	local dist = if vroot then (vroot.Position - data.root.Position).Magnitude else math.huge
	local head = m:FindFirstChild("Head") :: BasePart?
	local headPos = if head then head.Position else data.root.Position + Vector3.new(0, 2, 0)
	local look = if alive then Registry.PlayerService:GetLook(viewer) else nil
	local los = look ~= nil and Registry.PlayerService:HasLineOfSight(look.origin, headPos, m)
	local seen = alive and Registry.PlayerService:IsLookingAt(viewer, data.root.Position + Vector3.new(0, 1.5, 0), "focus", 90, m)
	if los then
		data.lastLos = now
	end
	if seen then
		data.seenFor += dt
		data.lastSeen = now
	else
		data.seenFor = math.max(0, data.seenFor - dt * 0.5)
	end

	-- decide
	local ctx = {
		valid = true,
		now = now,
		stateTime = now - data.stateAt,
		lifetime = now - data.spawned,
		viewerAlive = alive,
		dist = dist,
		los = los,
		seen = seen,
		seenFor = data.seenFor,
		unseenFor = now - data.lastLos,
		arrived = false,
		routeFailed = data.routeFailed,
		stuck = data.stuck,
		ping = data.ping,
		recoveries = data.recoveries,
		recovered = data.recovered,
	}
	if data.state == S.SPAWNING then
		local fits, why = Mimic.spotFits(data.root.Position - Vector3.new(0, 3, 0), { m :: Instance, table.unpack(characters()) })
		ctx.valid = fits
		ctx.invalidReason = why
	end
	local nextState, reason = MimicBrain.decide(data.state, ctx)
	if nextState ~= data.state then
		if nextState == S.INVESTIGATING then
			data.ping = nil
		end
		setState(data, nextState, reason)
	end
	if data.state == S.DESPAWNING then
		Mimic.finish(data.attacked, data.reason)
		return
	end

	-- act
	local state = data.state
	local moving = false
	m:SetAttribute("Pause", false)
	if state == S.IDLE then
		stand(data)
	elseif state == S.PATROLLING then
		if not data.destination and vroot then
			pickInBackground(data, vroot.Position, 14, 50, function(spot)
				if data.state ~= S.PATROLLING then
					return
				end
				if spot then
					route(data, spot)
				else
					data.routeFailed = true
				end
			end)
		end
		moving = data.destination ~= nil
		if follow(data, MimicBrain.speed(state)) then
			setState(data, S.IDLE, "arrived")
		end
	elseif state == S.INVESTIGATING then
		if not data.destination and not data.pathPending then
			route(data, ctx.ping or (if vroot then vroot.Position else data.root.Position))
		end
		moving = true
		if follow(data, MimicBrain.speed(state)) then
			setState(data, S.IDLE, "looked around")
		end
	elseif state == S.STALKING and vroot then
		if seen then
			-- looked at: it stops and acts natural (badly)
			stand(data)
			m:SetAttribute("Pause", true)
			if not data.waved and dist < 45 then
				data.waved = true
				m:SetAttribute("Emote", "wave")
				m:SetAttribute("EmoteSpeed", 0.35)
				m:SetAttribute("EmoteAt", workspace:GetServerTimeNow())
			end
		else
			-- a few metres behind its viewer, re-planned as they move
			local back = -Util.flat(vroot.CFrame.LookVector)
			local goal = vroot.Position + (if back.Magnitude > 0.1 then back.Unit else Vector3.zero) * 12
			if dist < 13 then
				stand(data)
			else
				if (not data.destination or (data.destination - goal).Magnitude > 5 or now - data.pathAt > 1.5) and not data.pathPending then
					route(data, goal)
				end
				moving = true
				follow(data, MimicBrain.speed(state))
			end
		end
	elseif state == S.CHASING and vroot then
		if (not data.destination or (data.destination - vroot.Position).Magnitude > 3 or now - data.pathAt > 0.6) and not data.pathPending then
			route(data, vroot.Position)
		end
		moving = true
		follow(data, MimicBrain.speed(state))
		-- the act is over: its head lolls to one side, its face on you
		m:SetAttribute("Chasing", true)
	elseif state == S.ATTACKING then
		stand(data)
		if not data.attacked and vroot and dist <= MimicBrain.Config.AttackRange + 0.75 and alive then
			-- server-checked: in range, alive. The viewer gets its face.
			data.attacked = true
			data.root.CFrame = CFrame.lookAt(data.root.Position, Vector3.new(vroot.Position.X, data.root.Position.Y, vroot.Position.Z))
			if helpers.onAttack then
				helpers.onAttack(viewer, m)
			end
		end
	elseif state == S.RECOVERING then
		if not data.destination then
			pickInBackground(data, data.root.Position, 8, 30, function(spot)
				if data.state ~= S.RECOVERING then
					return
				end
				if spot then
					route(data, spot)
					data.recovered = true
					log("recovering: new route to " .. tostring(spot))
				else
					data.recoveries += 1
				end
			end)
		end
		moving = data.destination ~= nil
		follow(data, MimicBrain.speed(state))
	end
	checkStuck(data, moving and data.humanoid.WalkSpeed > 0)
	if data.stuck then
		data.stuckCount += 1
		if data.destination then
			table.insert(data.failedSpots, data.destination)
		end
	end
	updateAnimation(data)

	-- sometimes it calls you over, with your friend's name
	if not data.pinged and now > data.pingAt and not seen then
		data.pinged = true
		local imitated = data.imitated
		Registry.PingService:FakePing(viewer, "COME_HERE", data.root.Position + Vector3.new(0, 1, 0), if imitated then imitated.DisplayName else viewer.DisplayName, if imitated then imitated.UserId else 0)
	end
end

-- One line for the admin panel: what it is, what it is doing, why.
function Mimic.status(): string
	local data = current
	if not data then
		return "mimic: none"
	end
	local anims = {}
	for name, st in data.animStatus do
		table.insert(anims, name .. "=" .. st)
	end
	table.sort(anims)
	local rig = data.humanoid.RigType.Name
	local pos = data.root.Position
	return string.format(
		"mimic %s (%s) | rig %s, %d parts | anims %s | pos %.0f,%.0f,%.0f | route %s%s | stuck x%d, recoveries %d | %s",
		data.state,
		data.reason or "-",
		rig,
		#data.model:GetDescendants(),
		table.concat(anims, " "),
		pos.X,
		pos.Y,
		pos.Z,
		if data.destination then string.format("%d wp", #data.waypoints) else "none",
		if data.routeFailed then " FAILED" else "",
		data.stuckCount,
		data.recoveries,
		table.concat(data.history, "; ")
	)
end

-- Unmasked by a report: it leaves at once.
function Mimic.unmask()
	Mimic.finish(false, "reported")
end

function Mimic.clear()
	local data = current
	if not data then
		return
	end
	current = nil
	clearRoute(data)
	Registry.PlayerService:RemovePerceptionExclusion(data.model)
	data.model:Destroy()
end

function Mimic.viewer(): Player?
	return if current then current.viewer else nil
end

function Mimic.imitated(): Player?
	return if current then current.imitated else nil
end

return Mimic
