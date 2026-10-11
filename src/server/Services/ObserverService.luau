--[[
	ObserverService
	THE OBSERVER. A perception entity: it cannot move while any player is looking
	at it. States: DORMANT, WATCHED, MOVING, HUNTING, DISAPPEARING, ATTACKING.

	Behaviours
	  Sighting  it appears far away where the target will see it, waits to be seen,
	            and is gone the next time they look away.
	  Hunt      it pursues a target. Every player's gaze freezes it, so teammates
	            can protect each other. Nobody can stare forever: after a few
	            seconds of continuous staring the server makes that player BLINK,
	            and during a blink it moves.
	  Mimic     a wrong copy of a teammate near someone separated from them
	            (Server/Mimic: its own body, face and state machine). Tells: no
	            flashlight, silent steps, a name tag that glitches, a head that
	            turns too far, a wave that is too slow. It may ping you, follow
	            you, and run at you when you notice it up close. Report it.
	  Escape    during the escape it never stops coming.

	Fairness
	  * it is never seen moving or teleporting: every jump happens unseen
	  * a hunt starts out of sight, at a distance, with a real path to its target
	  * you always hear it breathe first: within 14 studs it inhales, and it
	    can only catch you a short random moment (0.3-0.8 s) after you heard
	    it. Once you have, it takes you the instant it reaches you: it never
	    stands at your side counting down (that made the catch predictable)
	  * the dark helps it (faster, bolder) and blackouts invite it out
	Catches play one of several death cinematics chosen from the situation:
	behind, beside, in front, in the dark, through a door, in a mirror, or
	wearing a teammate's face.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)
local Registry = require(script.Parent.Parent.Registry)
local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)
local Mimic = require(script.Parent.Parent.Mimic.Mimic)

local ObserverService = {}

ObserverService.StateChanged = Signal.new() -- (state)
ObserverService.Caught = Signal.new() -- (player)

local S = Enums.ObserverState

local model: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local breath: Sound? = nil
local state = S.Dormant
local mode: string? = nil -- "sighting" | "hunt" | "escape"
local target: Player? = nil
local huntEndsAt = 0
local sightingData = nil
local stareTime: { [Player]: number } = {}
local blinkingUntil: { [Player]: number } = {}
local metThisRound: { [Player]: boolean } = {}
local guardianAwarded: { [Player]: boolean } = {}
local waypoints = {}
local waypointIndex = 0
local lastPathAt = 0
local lastPathGoal = Vector3.zero
local lastProgressPos = Vector3.zero
local lastProgressAt = 0
local unwatchedSince = 0
local lastBlinkStepAt = 0
local pathFailures = 0
local pathPending = false
local behavior: string? = nil
local align: AlignOrientation? = nil
local attackLock = false
local active = false
local warned: { [Player]: number } = {} -- when it last breathed near them
local strikeAfter: { [Player]: number } = {} -- seconds after that breath it may strike
local lastVariant: { [Player]: string } = {}
local lastSequence: { [Player]: string } = {}
-- which death cinematics fit each situation (see ScareController)
local SEQUENCES_FOR = {
	behind = { "turn", "drop" },
	side = { "turn", "peek" },
	front = { "stillness", "drop" },
	dark = { "lightsout" },
	door = { "peek", "turn" },
	mirror = { "mirror" },
	mimic = { "mimic" },
}

------------------------------------------------------------------------------------
-- Model management
------------------------------------------------------------------------------------

local function ensureModel()
	if model then
		return
	end
	model = ObserverRig.build(CFrame.new(0, -500, 0))
	local m = model :: Model
	humanoid = m:FindFirstChildOfClass("Humanoid")
	root = m.PrimaryPart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Observer"
		end
	end
	local head = m:FindFirstChild("Head") :: BasePart
	breath = SoundFactory.create("ObserverBreath", head)
	-- it turns deliberately: the Humanoid no longer snaps it round; an
	-- AlignOrientation turns it toward where it is going at a limited rate
	if humanoid and root then
		humanoid.AutoRotate = false
		local att = Instance.new("Attachment")
		att.Name = "TurnAttachment"
		att.Parent = root
		local a = Instance.new("AlignOrientation")
		a.Name = "Turn"
		a.Mode = Enum.OrientationAlignmentMode.OneAttachment
		a.Attachment0 = att
		a.MaxAngularVelocity = math.rad(140)
		a.MaxTorque = 1e7
		a.Responsiveness = 12
		a.PrimaryAxisOnly = false
		a.CFrame = root.CFrame.Rotation
		a.Parent = root
		align = a
	end
	m.Parent = ServerStorage
end

-- What it is doing, for the clients' animation (ObserverFX): OBSERVING,
-- REPOSITIONING, STALKING, ATTACKING, RECOVERY (or nil).
local function setBehavior(b: string?)
	if behavior == b then
		return
	end
	behavior = b
	if model then
		model:SetAttribute("Behavior", b)
	end
end

-- Turn (smoothly, rate-limited) to face a direction on the ground plane.
local function faceToward(dir: Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if align and flat.Magnitude > 0.05 then
		align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

-- After a teleport the turn target must match, or it would spin back.
local function syncTurn()
	if align and root then
		align.CFrame = root.CFrame.Rotation
	end
end

local function setState(newState: string)
	if state == newState then
		return
	end
	state = newState
	if model then
		model:SetAttribute("State", newState)
	end
	workspace:SetAttribute("ObserverState", newState)
	ObserverService.StateChanged:Fire(newState)
end

local function headPos(): Vector3
	local head = model and model:FindFirstChild("Head") :: BasePart?
	if head then
		return head.Position
	end
	return if root then root.Position + Vector3.new(0, 4, 0) else Vector3.zero
end

local function samplePoints(): { Vector3 }
	local list = { headPos() }
	if root then
		table.insert(list, root.Position + Vector3.new(0, 1, 0))
		table.insert(list, root.Position - Vector3.new(0, 3, 0))
	end
	return list
end

local function park()
	if not model then
		return
	end
	if breath then
		breath:Stop()
	end
	Registry.PlayerService:RemovePerceptionExclusion(model)
	model.Parent = ServerStorage
	if root then
		root.Anchored = true
	end
	mode = nil
	target = nil
	sightingData = nil
	waypoints = {}
	pathFailures = 0
	setBehavior(nil)
	setState(S.Dormant)
end

local function place(cf: CFrame)
	ensureModel()
	local m = model :: Model
	m:PivotTo(cf * CFrame.new(0, ObserverRig.HipHeight + 1, 0))
	m.Parent = workspace
	Registry.PlayerService:AddPerceptionExclusion(m)
	if root then
		root.Anchored = false
		pcall(function()
			(root :: BasePart):SetNetworkOwner(nil)
		end)
	end
	if humanoid then
		humanoid.WalkSpeed = 0
	end
	if breath then
		breath:Play()
	end
	lastProgressPos = cf.Position
	lastProgressAt = os.clock()
	syncTurn()
end

------------------------------------------------------------------------------------
-- Perception
------------------------------------------------------------------------------------

local function isBlinking(player: Player): boolean
	return (blinkingUntil[player] or 0) > os.clock()
end

-- In the dark it is only made out up close, or where a light reaches it: a
-- player staring into a black corridor does not hold it in place.
local function canMakeOut(viewer: Player, point: Vector3): boolean
	if not Registry.LightingService:IsDark(point) then
		return true
	end
	local eye = Registry.PlayerService:GetEye(viewer)
	if eye and (eye - point).Magnitude <= GameConfig.Perception.DarkSightRange then
		return true
	end
	return Registry.LightingService:IsLit(point)
end

-- Players currently holding the Observer in place.
local function watchers(): { Player }
	local list = {}
	if not model or model.Parent ~= workspace then
		return list
	end
	local points = samplePoints()
	for _, p in Registry.PlayerService:GetAlive() do
		if not isBlinking(p) then
			for _, pt in points do
				if Registry.PlayerService:IsLookingAt(p, pt, "screen", 140, model) and canMakeOut(p, pt) then
					table.insert(list, p)
					break
				end
			end
		end
	end
	return list
end

local totalStare: { [Player]: number } = {}

local function updateStare(watching: { Player }, dt: number)
	local blinkAfter = Registry.RoundService:GetDifficultyConfig().BlinkAfter
	for _, p in Players:GetPlayers() do
		if table.find(watching, p) then
			stareTime[p] = (stareTime[p] or 0) + dt
			totalStare[p] = (totalStare[p] or 0) + dt
			if totalStare[p] >= 30 then
				Registry.ProgressionService:Award(p, "THE_TALL_MAN")
			end
			if stareTime[p] >= blinkAfter then
				stareTime[p] = 0
				blinkingUntil[p] = os.clock() + GameConfig.Observer.StareForcedBlinkDuration
				Net.fire(p, "Effect", { name = "Blink", duration = GameConfig.Observer.StareForcedBlinkDuration })
			end
		else
			stareTime[p] = math.max(0, (stareTime[p] or 0) - dt * 2)
		end
	end
end

local function firstSight(player: Player)
	if metThisRound[player] then
		return
	end
	metThisRound[player] = true
	Registry.ProgressionService:ObserverSighted(player)
	Registry.AnalyticsService:MonsterEncounter(player)
	Net.fire(player, "Effect", { name = "ObserverSeen" })
end

------------------------------------------------------------------------------------
-- Spot finding
------------------------------------------------------------------------------------

local function candidateSpots(minD: number, maxD: number, from: Vector3, sameFloorOnly: boolean?): { Vector3 }
	local map = Registry.MapService:GetMap()
	local list = {}
	if not map then
		return list
	end
	for _, room in map.Rooms do
		if not room.secret then
			for _, spot in room.floorSpots do
				local d = (spot - from).Magnitude
				if d >= minD and d <= maxD and (not sameFloorOnly or math.abs(spot.Y - (from.Y - 3)) < 6) then
					table.insert(list, spot)
				end
			end
		end
	end
	return list
end

local function unseenAt(spot: Vector3): boolean
	local pts = { spot + Vector3.new(0, 8.5, 0), spot + Vector3.new(0, 4, 0) }
	return not Registry.PlayerService:CanAnyoneSee(pts, "periphery", 240)
end

-- Is there a walkable path between two points? (true when pathfinding is unavailable)
local function pathOk(a: Vector3, b: Vector3): boolean
	local okCreate, path = pcall(function()
		return PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 9, AgentCanJump = false })
	end)
	if not okCreate or not path then
		return true
	end
	local ok = pcall(function()
		path:ComputeAsync(a, b)
	end)
	return ok and path.Status == Enum.PathStatus.Success
end

-- A hunt start: out of sight, at a fair distance, with a real way to the target.
local function findHuntSpot(target: Vector3, minD: number, maxD: number): Vector3?
	local spots = candidateSpots(minD, maxD, target, true)
	table.sort(spots, function(a, b)
		return (a - target).Magnitude < (b - target).Magnitude
	end)
	local tries = 0
	for _, spot in spots do
		if unseenAt(spot) then
			tries += 1
			if pathOk(spot, target) then
				return spot
			end
			if tries >= 4 then
				break
			end
		end
	end
	return nil
end

local function findHiddenSpot(near: Vector3, minD: number, maxD: number, pivot: Vector3?): Vector3?
	local spots = candidateSpots(minD, maxD, near, true)
	-- closest-first so the Observer doesn't appear on the other side of the map
	table.sort(spots, function(a, b)
		return (a - near).Magnitude < (b - near).Magnitude
	end)
	for _, spot in spots do
		if unseenAt(spot) and (not pivot or (spot - pivot).Magnitude > 6) then
			return spot
		end
	end
	return nil
end

------------------------------------------------------------------------------------
-- Movement
------------------------------------------------------------------------------------

-- The first waypoint still ahead of `pos` (paths are computed asynchronously
-- from where it WAS; restarting at waypoint 2 made it turn back for a step).
local function firstAhead(list, pos: Vector3): number
	local best, bestD = 1, math.huge
	for i, wp in list do
		local d = Util.flat(wp.Position - pos).Magnitude
		if d < bestD then
			best, bestD = i, d
		end
	end
	return math.min(#list, best + 1)
end

local PATH_PARAMS = { AgentRadius = 1.6, AgentHeight = 9, AgentCanJump = false, WaypointSpacing = 4 }

local function computePath(goal: Vector3)
	if not root or pathPending then
		return
	end
	lastPathAt = os.clock()
	lastPathGoal = goal
	pathPending = true
	local from = root.Position
	task.spawn(function()
		local p = PathfindingService:CreatePath(PATH_PARAMS)
		local ok = pcall(function()
			p:ComputeAsync(from, goal)
		end)
		pathPending = false
		if ok and p.Status == Enum.PathStatus.Success then
			local list = p:GetWaypoints()
			waypoints = list
			waypointIndex = if root then firstAhead(list, root.Position) else math.min(2, #list)
			pathFailures = 0
		else
			-- keep the old route (if any) and try again soon; never walk a
			-- straight line through a wall
			pathFailures += 1
		end
	end)
end

-- Straight-line fallback only when nothing solid is in the way.
local function clearLine(a: Vector3, b: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if model then
		table.insert(ignore, model)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local from = a + Vector3.new(0, 1, 0)
	local to = b + Vector3.new(0, 1, 0)
	return workspace:Raycast(from, to - from, params) == nil
end

local function moveToward(goal: Vector3, speed: number)
	if not humanoid or not root then
		return
	end
	humanoid.WalkSpeed = speed
	local atEnd = waypointIndex >= #waypoints
	if os.clock() - lastPathAt > (if pathFailures > 0 then 0.6 else 2.5) or (goal - lastPathGoal).Magnitude > 6 or (atEnd and os.clock() - lastPathAt > 0.8) then
		computePath(goal)
	end
	local wp = waypoints[waypointIndex]
	local pos: Vector3? = nil
	if wp then
		pos = wp.Position
		if Util.flat((pos :: Vector3) - root.Position).Magnitude < 2.5 and waypointIndex < #waypoints then
			waypointIndex += 1
			pos = waypoints[waypointIndex].Position
		end
	elseif clearLine(root.Position, goal) then
		pos = goal
	end
	if pos then
		humanoid:MoveTo(pos)
		faceToward((pos :: Vector3) - root.Position)
	else
		-- no route yet: wait for one (it stands and watches; it does not
		-- press into a wall)
		humanoid:Move(Vector3.zero)
		faceToward(goal - root.Position)
	end
	Registry.DoorService:OpenNear(root.Position, 7)
end

local function freeze()
	if humanoid and root then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero)
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
		-- frozen means frozen: it does not finish turning while watched
		syncTurn()
	end
end

-- Teleport step along the path while nobody watches: the uncanny "it got closer".
local function blinkStep(goal: Vector3)
	if not root then
		return
	end
	local dir = Util.flat(goal - root.Position)
	local dist = dir.Magnitude
	if dist < 22 then
		return
	end
	local stepTo = nil
	local wp = waypoints[math.min(#waypoints, waypointIndex + 2)]
	if wp then
		stepTo = wp.Position
	else
		stepTo = root.Position + dir.Unit * 10
	end
	if unseenAt(stepTo) then
		lastBlinkStepAt = os.clock()
		local look = Util.flat(goal - stepTo)
		local cf = if look.Magnitude > 0.1 then CFrame.lookAt(stepTo, stepTo + look.Unit) else CFrame.new(stepTo)
		model:PivotTo(cf * CFrame.new(0, ObserverRig.HipHeight + 1 - 0, 0))
		waypointIndex = math.min(#waypoints, waypointIndex + 2)
		syncTurn()
		Registry.AudioService:PlayAt("ObserverStep", stepTo, { volume = 0.8 })
	end
end

------------------------------------------------------------------------------------
-- Attack
------------------------------------------------------------------------------------

-- Picks how this catch plays out for the victim (never the same twice in a row).
local function chooseVariant(victim: Player, vroot: BasePart)
	local rng = Registry.HorrorDirector:Rng()
	local look = Registry.PlayerService:GetLook(victim)
	local lookDir = Util.flat(if look then look.dir else vroot.CFrame.LookVector)
	lookDir = if lookDir.Magnitude > 0.01 then lookDir.Unit else Vector3.new(0, 0, -1)
	local options = {}
	local data = {}
	-- a mirror in front of them
	for _, mirror in CollectionService:GetTagged("Mirror") do
		local glass = mirror:FindFirstChild("Glass")
		if glass and glass:IsA("BasePart") and mirror:IsDescendantOf(workspace) then
			local to = glass.Position - vroot.Position
			if to.Magnitude < 14 and Util.flat(to).Magnitude > 0.1 and Util.flat(to).Unit:Dot(lookDir) > 0.55 then
				table.insert(options, { item = "mirror", weight = 3 })
				data.mirror = glass.Position
				break
			end
		end
	end
	-- darkness
	local dark = Registry.LightingService:IsDark(vroot.Position) and not Registry.InventoryService:IsLightOn(victim)
	if dark then
		table.insert(options, { item = "dark", weight = 2.5 })
	end
	-- a doorway close by
	local map = Registry.MapService:GetMap()
	if map then
		local bestDoor, bestD = nil, 9
		for _, door in map.Doors do
			local d = Util.flat(door.center - vroot.Position).Magnitude
			if d < bestD and d > 2.5 and door.model and not door.model:GetAttribute("Locked") then
				bestDoor, bestD = door, d
			end
		end
		if bestDoor then
			table.insert(options, { item = "door", weight = 1.5 })
			data.door = bestDoor.center
			data.doorDir = bestDoor.passageDir
		end
	end
	-- wearing a teammate
	for _, p in Registry.PlayerService:GetAlive() do
		if p ~= victim and p.Character then
			table.insert(options, { item = "mimic", weight = 1.2 })
			data.mimicUserId = p.UserId
			data.mimicName = p.DisplayName
			break
		end
	end
	-- from where it actually is
	local toObs = if root then Util.flat(root.Position - vroot.Position) else -lookDir
	local angle = if toObs.Magnitude > 0.01 then math.deg(math.acos(math.clamp(toObs.Unit:Dot(lookDir), -1, 1))) else 180
	if angle > 110 then
		table.insert(options, { item = "behind", weight = 2.2 })
	elseif angle > 50 then
		table.insert(options, { item = "side", weight = 2.2 })
		data.side = if lookDir:Cross(toObs).Y > 0 then -1 else 1
	else
		table.insert(options, { item = "front", weight = 2.2 })
	end
	if #options > 1 then
		for i, o in options do
			if o.item == lastVariant[victim] then
				table.remove(options, i)
				break
			end
		end
	end
	local variant = rng:Weighted(options) or "behind"
	lastVariant[victim] = variant
	data.variant = variant
	-- the cinematic's sequence and rhythm (ScareController): several fit
	-- each situation; never the same sequence twice in a row for a player,
	-- and the beat (0..1) changes how long each false calm lasts
	local fits = SEQUENCES_FOR[variant] or { "turn" }
	local choices = {}
	for _, seq in fits do
		if seq ~= lastSequence[victim] then
			table.insert(choices, seq)
		end
	end
	if #choices == 0 then
		choices = fits
	end
	data.sequence = choices[rng:Int(1, #choices)]
	data.beat = rng:Number()
	lastSequence[victim] = data.sequence
	data.side = data.side or (if rng:Chance(0.5) then 1 else -1)
	return variant, data, lookDir
end

local function attack(victim: Player)
	if attackLock or not model or not root then
		return
	end
	attackLock = true
	setState(S.Attacking)
	setBehavior("ATTACKING")
	freeze()
	local vroot = Util.getRoot(victim)
	-- a Ward breaks instead of you
	if Registry.InventoryService:Has(victim, "WARD") then
		if vroot then
			local face = vroot.Position + Util.flat(vroot.CFrame.LookVector).Unit * 3.2
			root.Anchored = true
			model:PivotTo(CFrame.lookAt(Vector3.new(face.X, vroot.Position.Y - 3, face.Z), Vector3.new(vroot.Position.X, vroot.Position.Y - 3, vroot.Position.Z)) * CFrame.new(0, ObserverRig.HipHeight + 1, 0))
		end
		Registry.InventoryService:Remove(victim, "WARD", 1)
		Registry.AudioService:PlayAt("WardBreak", headPos())
		Net.fire(victim, "Effect", { name = "WardBreak" })
		Net.fire(victim, "Notify", { kind = "danger", text = "The ward snaps. You are still here." })
		Registry.ProgressionService:Award(victim, "SAVED_BY_WARD")
		task.delay(0.6, function()
			park()
			attackLock = false
		end)
		return
	end
	local info = { variant = "behind" }
	if vroot then
		local variant, data, lookDir = chooseVariant(victim, vroot)
		info = data
		-- where everyone else sees it standing
		local offset
		if variant == "behind" or variant == "mirror" then
			offset = -lookDir * 2.8
		elseif variant == "side" then
			offset = Vector3.new(-lookDir.Z, 0, lookDir.X) * (data.side or 1) * 2.8
		elseif variant == "door" and data.door then
			offset = Util.flat(data.door - vroot.Position)
			offset = if offset.Magnitude > 3 then offset.Unit * (offset.Magnitude - 1.5) else lookDir * 2.4
		else
			offset = lookDir * 2.2
		end
		local spot = vroot.Position + offset
		local floorY = vroot.Position.Y - 3
		root.Anchored = true
		model:PivotTo(CFrame.lookAt(Vector3.new(spot.X, floorY, spot.Z), Vector3.new(vroot.Position.X, floorY, vroot.Position.Z)) * CFrame.new(0, ObserverRig.HipHeight + 1, 0))
		-- the victim stops where they stand
		local humanoid = Util.getHumanoid(victim)
		if humanoid then
			humanoid.WalkSpeed = 0
		end
	end
	-- everyone else hears the catch; the victim hears nothing until the impact
	-- (their client plays it on the exact frame), so nothing gives it away
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= victim then
			table.insert(others, p)
		end
	end
	Registry.AudioService:PlayAtFor(others, "ObserverScreech", headPos(), { volume = 0.55 })
	ObserverService.Caught:Fire(victim)
	Registry.RoundService:KillPlayer(victim, model:GetPivot(), info)
	Registry.AnalyticsService:Event(victim, "ObserverCatch", 1, { variant = info.variant })
	task.delay(3, function()
		attackLock = false
		if mode == "escape" then
			-- keep coming during the escape, but from somewhere else
			park()
			task.delay(4, function()
				if Registry.RoundService:IsEscape() then
					ObserverService:StartEscapeChase()
				end
			end)
		else
			park()
		end
	end)
end

------------------------------------------------------------------------------------
-- Behaviours
------------------------------------------------------------------------------------

function ObserverService:IsActive(): boolean
	return mode ~= nil
end

function ObserverService:GetMode(): string?
	return mode
end

function ObserverService:GetState(): string
	return state
end

function ObserverService:GetPosition(): Vector3?
	if model and model.Parent == workspace and root then
		return root.Position
	end
	return nil
end

-- A hunt that ends with its target alive: that is surviving it.
local function huntSurvived()
	if mode ~= "hunt" then
		return
	end
	for p in metThisRound do
		if p.Parent and Registry.PlayerService:IsAlive(p) then
			Registry.ProgressionService:Award(p, "FIRST_CONTACT")
			if p == target then
				Registry.ProgressionService:Award(p, "DONT_BLINK")
			end
		end
	end
end

function ObserverService:Vanish()
	if mode == nil then
		return
	end
	huntSurvived()
	setState(S.Disappearing)
	local pos = self:GetPosition()
	if pos then
		Registry.AudioService:PlayAt("ObserverVanish", pos)
		Net.fireAll("Effect", { name = "ObserverVanish", at = pos })
	end
	task.delay(0.25, park)
end

-- Appear far away, wait to be seen, leave when they look away.
function ObserverService:Sighting(player: Player): boolean
	if mode or not active then
		return false
	end
	local proot = Util.getRoot(player)
	local look = Registry.PlayerService:GetLook(player)
	if not proot or not look then
		return false
	end
	-- spots the player could see if they turned a little, but cannot see right now;
	-- it likes doorways best (half in a frame, half in the dark)
	local best, bestDoor = nil, nil
	local map = Registry.MapService:GetMap()
	for _, spot in candidateSpots(GameConfig.Observer.SightingMinDistance, GameConfig.Observer.SightingMaxDistance, proot.Position, true) do
		local head = spot + Vector3.new(0, 8.5, 0)
		if Registry.PlayerService:HasLineOfSight(look.origin, head) and unseenAt(spot) then
			local dir = (head - look.origin).Unit
			local angle = math.deg(math.acos(math.clamp(dir:Dot(look.dir), -1, 1)))
			if angle > 75 and angle < 150 then
				best = best or spot
				if map and not bestDoor then
					for _, door in map.Doors do
						if Util.flat(door.center - spot).Magnitude < 4.5 then
							bestDoor = spot
							break
						end
					end
				end
				if bestDoor then
					break
				end
			end
		end
	end
	if bestDoor and Registry.HorrorDirector:Rng():Chance(0.7) then
		best = bestDoor
	end
	if not best then
		return false
	end
	ensureModel()
	local face = Util.flat(proot.Position - best)
	place(CFrame.lookAt(best, best + (if face.Magnitude > 0.1 then face.Unit else Vector3.new(0, 0, 1))))
	if root then
		root.Anchored = true
	end
	mode = "sighting"
	target = player
	sightingData = { seenAt = nil :: number?, lookAwayFor = 0, spawnedAt = os.clock() }
	setState(S.Watched)
	setBehavior("OBSERVING")
	return true
end

function ObserverService:StartHunt(player: Player, opts: { [string]: any }?)
	if not active then
		return false
	end
	opts = opts or {}
	if mode == "hunt" or mode == "escape" then
		target = player
		return true
	end
	if mode then
		park()
	end
	local proot = Util.getRoot(player)
	if not proot then
		return false
	end
	local spot = nil
	if opts.behind then
		local back = -Util.flat(proot.CFrame.LookVector)
		if back.Magnitude > 0.1 then
			local candidate = proot.Position + back.Unit * 14
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { player.Character :: Instance }
			if not workspace:Raycast(proot.Position, back.Unit * 15, params) then
				local ground = workspace:Raycast(candidate, Vector3.new(0, -10, 0), params)
				if ground then
					spot = ground.Position
				end
			end
		end
	end
	if not spot and opts.near then
		spot = findHiddenSpot(opts.near, 4, 70, proot.Position)
	end
	spot = spot or findHuntSpot(proot.Position, 26, 80) or findHuntSpot(proot.Position, 20, 140)
	if not spot then
		return false
	end
	local face = Util.flat(proot.Position - spot)
	place(CFrame.lookAt(spot, spot + (if face.Magnitude > 0.1 then face.Unit else Vector3.new(0, 0, 1))))
	mode = "hunt"
	target = player
	local cfg = Registry.RoundService:GetDifficultyConfig()
	huntEndsAt = os.clock() + Registry.HorrorDirector:Rng():Range(cfg.HuntDuration)
	unwatchedSince = os.clock()
	setState(S.Hunting)
	Registry.AudioService:PlayAt("ObserverAppear", spot + Vector3.new(0, 6, 0))
	Net.fireAll("Director", { cue = "hunt", reason = opts.reason })
	Registry.HorrorDirector:OnHuntStarted(player)
	return true
end

function ObserverService:StartEscapeChase()
	if not active then
		return
	end
	if mode then
		park()
	end
	local alive = Registry.PlayerService:GetAlive()
	if #alive == 0 then
		return
	end
	-- chase whoever is furthest from the exit: it herds the stragglers
	local map = Registry.MapService:GetMap()
	local exitPos = map and map.ExitCenter or Vector3.zero
	table.sort(alive, function(a, b)
		local ra, rb = Util.getRoot(a), Util.getRoot(b)
		local da = if ra then (ra.Position - exitPos).Magnitude else 0
		local db = if rb then (rb.Position - exitPos).Magnitude else 0
		return da > db
	end)
	local victim = alive[1]
	local proot = Util.getRoot(victim)
	if not proot then
		return
	end
	local spot = findHiddenSpot(proot.Position, 30, 80, proot.Position) or findHiddenSpot(proot.Position, 16, 160)
	if not spot then
		return
	end
	place(CFrame.new(spot))
	mode = "escape"
	target = victim
	unwatchedSince = os.clock()
	setState(S.Hunting)
	Registry.AudioService:PlayAt("ObserverAppear", spot + Vector3.new(0, 6, 0))
end

------------------------------------------------------------------------------------
-- Mimic (Server/Mimic: MimicBrain decides, Mimic drives). One creation path for
-- the director and the admin command.
------------------------------------------------------------------------------------

Mimic.init({
	candidateSpots = candidateSpots,
	unseenAt = unseenAt,
	-- in reach and checked by the server: its face, in the viewer's
	onAttack = function(viewer: Player, m: Model)
		Net.fire(viewer, "Effect", { name = "Jumpscare", kind = "mimic", model = m })
	end,
	-- after a lunge, sometimes The Observer is right behind you
	onLunge = function(viewer: Player)
		if Registry.HorrorDirector:Rng():Chance(0.5) then
			task.delay(2, function()
				ObserverService:StartHunt(viewer, { behind = true, reason = "mimic" })
			end)
		end
	end,
})

-- Spawns a mimic near `viewer` wearing `imitated`'s clothes. Returns (ok, why).
function ObserverService:SpawnMimic(viewer: Player, imitated: Player?): (boolean, string)
	if not active then
		return false, "no round running"
	end
	return Mimic.spawn(viewer, imitated or viewer)
end

function ObserverService:Mimic(viewer: Player, imitated: Player?): boolean
	local ok = self:SpawnMimic(viewer, imitated)
	return ok
end

function ObserverService:MimicStatus(): string
	return Mimic.status()
end

function ObserverService:DespawnMimic()
	Mimic.finish(false, "admin")
end

-- A real ping near a mimic: it stares at whoever pinged, or goes to look.
function ObserverService:OnPing(from: Player, position: Vector3)
	Mimic.onPing(from, position)
end

-- Reporting a mimic unmasks it. Returns true if the report was aimed at one.
function ObserverService:ReportMimic(player: Player, origin: Vector3, dir: Vector3): boolean
	local found = Mimic.get()
	if not found or not found.PrimaryPart then
		return false
	end
	local m = found :: Model
	local target = m.PrimaryPart.Position + Vector3.new(0, 1, 0)
	local to = target - origin
	if to.Magnitude > 80 or to.Magnitude < 0.1 then
		return false
	end
	local angle = math.deg(math.acos(math.clamp(to.Unit:Dot(dir.Unit), -1, 1)))
	local tolerance = math.deg(math.atan2(2.6, to.Magnitude)) + 4
	if angle > tolerance or not Registry.PlayerService:HasLineOfSight(origin, target, m) then
		return false
	end
	local imitated = Mimic.imitated()
	local name = if imitated then imitated.DisplayName else "you"
	Net.fire(player, "Notify", { kind = "anomaly", text = "THAT WASN'T " .. string.upper(name), sub = "MIMIC UNMASKED" })
	Net.fire(player, "Effect", { name = "RealitySnap" })
	Registry.ProgressionService:Award(player, "NOT_MY_FRIEND")
	Registry.ProgressionService:MimicSpotted(player)
	Mimic.unmask()
	return true
end

------------------------------------------------------------------------------------
-- Inspect (admin): it stands in front of you, watching, so you can look at it
------------------------------------------------------------------------------------

function ObserverService:Inspect(player: Player): (boolean, string)
	if not active then
		return false, "no round running"
	end
	local proot = Util.getRoot(player)
	if not proot then
		return false, "no character"
	end
	if mode then
		park()
	end
	local look = Util.flat(proot.CFrame.LookVector)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local dist = 12
	local hit = workspace:Raycast(proot.Position, look * 14, params)
	if hit then
		dist = math.max(4, (hit.Position - proot.Position).Magnitude - 2)
	end
	local ground = workspace:Raycast(proot.Position + look * dist + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local spot = if ground then ground.Position else proot.Position + look * dist - Vector3.new(0, 3, 0)
	place(CFrame.lookAt(spot, spot - look))
	if root then
		root.Anchored = true
	end
	mode = "inspect"
	target = player
	huntEndsAt = os.clock() + 45
	setState(S.Watched)
	setBehavior("OBSERVING")
	return true, string.format("observer standing %.0f studs in front of you for 45 s (Vanish Observer to remove)", dist)
end

------------------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------------------

local function tick(dt: number)
	Mimic.tick(dt)
	if not mode or not model or model.Parent ~= workspace or not root then
		return
	end
	if mode == "inspect" then
		-- frozen, watching its target; only its eyes and head follow (client)
		if os.clock() > huntEndsAt or not target or not Registry.PlayerService:IsAlive(target) then
			ObserverService:Vanish()
		end
		return
	end
	if mode == "sighting" then
		local data = sightingData
		if not data or not target then
			park()
			return
		end
		local tr = Util.getRoot(target)
		if not tr or not Registry.PlayerService:IsAlive(target) then
			ObserverService:Vanish()
			return
		end
		local seen = Registry.PlayerService:IsLookingAt(target, headPos(), "focus", 200, model) and canMakeOut(target, headPos())
		if seen then
			if not data.seenAt then
				data.seenAt = os.clock()
				firstSight(target)
			end
			data.lookAwayFor = 0
		elseif data.seenAt then
			data.lookAwayFor += dt
			-- gone the moment they look away. Never let them see it leave.
			if data.lookAwayFor > 0.3 and not Registry.PlayerService:CanAnyoneSee(samplePoints(), "periphery", 240, model) then
				park()
				return
			end
		end
		if (tr.Position - root.Position).Magnitude < 16 or os.clock() - data.spawnedAt > 26 then
			ObserverService:Vanish()
		end
		return
	end

	-- hunt / escape
	if attackLock then
		return
	end
	local list = watchers()
	updateStare(list, dt)
	if not target or not Registry.PlayerService:IsAlive(target) then
		local alive = Registry.PlayerService:GetAlive()
		if #alive == 0 then
			park()
			return
		end
		target = alive[1]
	end
	local tr = Util.getRoot(target :: Player)
	if not tr then
		return
	end
	for _, p in list do
		firstSight(p)
	end
	if #list > 0 then
		freeze()
		setState(S.Watched)
		setBehavior("OBSERVING")
		unwatchedSince = os.clock()
		-- guarding a teammate
		for _, p in list do
			if p ~= target and not guardianAwarded[p] and (tr.Position - root.Position).Magnitude < 30 then
				guardianAwarded[p] = true
				Registry.ProgressionService:Award(p, "GUARDIAN")
			end
		end
		-- a hunt can end while it is being watched; it dissolves into the dark
		if mode == "hunt" and os.clock() > huntEndsAt + 6 then
			ObserverService:Vanish()
		end
		return
	end
	if mode == "hunt" and os.clock() > huntEndsAt then
		ObserverService:Vanish()
		return
	end
	local targetDist = (tr.Position - root.Position).Magnitude
	setState(if targetDist < 40 then S.Hunting else S.Moving)
	local cfg = Registry.RoundService:GetDifficultyConfig()
	-- no tell before a catch: it keeps coming at the same gait
	setBehavior(if targetDist < 40 then "STALKING" else "REPOSITIONING")
	-- the dark is on its side
	local dark = Registry.LightingService:IsDark(root.Position)
	local cunning = cfg.ObserverCunning or 0
	local speed = cfg.ObserverSpeed
	if mode == "escape" then
		speed *= 0.9
	end
	if dark then
		speed *= 1 + 0.06 * (cunning + 1)
	end
	if threatening then
		speed *= 0.55
	end
	-- warnings first: you always hear it with time to turn round. It breathes
	-- once it is one reaction time (per difficulty) from reaching you, and it
	-- cannot strike until that time is up, whatever its speed or a blink step
	local reach = GameConfig.Observer.CatchDistance + 1.5
	local reaction = cfg.ReactionTime or 1
	local warnRadius = reach + speed * reaction
	for _, p in Registry.PlayerService:GetAlive() do
		local pr = Util.getRoot(p)
		if pr then
			local d = (pr.Position - root.Position).Magnitude
			if d < warnRadius and (warned[p] or 0) < os.clock() - 8 then
				warned[p] = os.clock()
				strikeAfter[p] = reaction + Registry.HorrorDirector:Rng():Number(0, 0.25)
				Registry.AudioService:PlayAtFor({ p }, "ObserverInhale", headPos(), { volume = 1 })
				Net.fire(p, "Effect", { name = "ObserverClose" })
			end
			-- catch anyone in reach who has heard it breathe and had their time
			-- to turn: at once, never standing beside them waiting
			local heard = warned[p] and os.clock() - warned[p] >= (strikeAfter[p] or reaction)
			if d <= reach and heard then
				attack(p)
				return
			end
		end
	end
	moveToward(tr.Position, speed)
	-- "it got closer": a jump along its path, only while nobody watches, and
	-- rarely (it used to be ~0.6 per second: it read as erratic teleporting)
	local blinkChance = 0.03 * (1 + cunning * 0.35) * (if dark then 1.4 else 1)
	if os.clock() - unwatchedSince > 2.5 and os.clock() - lastBlinkStepAt > 4.5 and Registry.HorrorDirector:Rng():Chance(blinkChance) then
		blinkStep(tr.Position)
	end
	-- unstick
	if (root.Position - lastProgressPos).Magnitude > 3 then
		lastProgressPos = root.Position
		lastProgressAt = os.clock()
	elseif os.clock() - lastProgressAt > 5 then
		lastProgressAt = os.clock()
		local spot = findHiddenSpot(tr.Position, 18, 60, tr.Position)
		if spot then
			model:PivotTo(CFrame.new(spot) * CFrame.new(0, ObserverRig.HipHeight + 1, 0))
			waypoints = {}
			syncTurn()
			setBehavior("RECOVERY")
		end
	end
end

function ObserverService:BeginRound()
	active = true
	metThisRound = {}
	totalStare = {}
	guardianAwarded = {}
	stareTime = {}
	blinkingUntil = {}
	attackLock = false
	ensureModel()
	park()
end

function ObserverService:EndRound()
	active = false
	Mimic.clear()
	park()
end

function ObserverService:GetMimic(): Model?
	return Mimic.get()
end

-- One line for the admin panel.
function ObserverService:Status(): string
	return string.format(
		"observer mode %s, state %s, behavior %s, path %d wp%s, failures %d",
		tostring(mode),
		state,
		tostring(behavior),
		#waypoints,
		if pathPending then " (planning)" else "",
		pathFailures
	)
end

function ObserverService:GetModel(): Model?
	return model
end

--[[
	Proximity states, per player, for the client's presence layers (audio,
	breathing, light, vignette) and the director (no scares on top of it):
	  FAR        nothing
	  AWARE      it is in the building's attention: the air thins out
	  NEAR       heartbeat, lights near you stutter
	  VERY_NEAR  breathing, the world goes quiet
	  HUNT       it is coming for you
	Decided here (only the server knows targets); a player attribute.
]]
local PROX_ORDER = { "FAR", "AWARE", "NEAR", "VERY_NEAR", "HUNT" }
ObserverService.ProximityOrder = PROX_ORDER

function ObserverService:Proximity(player: Player, observerPos: Vector3?): string
	local pr = Util.getRoot(player)
	if not pr or not observerPos or not mode then
		return "FAR"
	end
	local d = (pr.Position - observerPos).Magnitude
	if (mode == "hunt" or mode == "escape") and (player == target or mode == "escape") and d < 90 then
		return "HUNT"
	elseif d < 14 then
		return "VERY_NEAR"
	elseif d < 32 then
		return "NEAR"
	elseif d < 75 then
		return "AWARE"
	end
	return "FAR"
end

-- Index of a proximity state (FAR = 1 .. HUNT = 5), handy for comparisons.
function ObserverService:ProximityLevel(player: Player): number
	return table.find(PROX_ORDER, player:GetAttribute("ObserverProx") or "FAR") or 1
end

local function updateProximity()
	local pos = if mode and model and model.Parent == workspace and root then root.Position else nil
	for _, p in Players:GetPlayers() do
		local state = if Registry.PlayerService:IsAlive(p) then ObserverService:Proximity(p, pos) else "FAR"
		if p:GetAttribute("ObserverProx") ~= state then
			p:SetAttribute("ObserverProx", state)
		end
	end
end

function ObserverService:Start()
	ensureModel()
	-- sculpted meshes (if uploaded) load in the background; the rig built above
	-- is dressed as soon as they arrive, later copies are dressed on creation
	task.spawn(function()
		local wanted = ObserverRig.configuredMeshes()
		if wanted == 0 then
			return
		end
		print(string.format("[ObserverService] loading sculpted Observer (%d meshes)...", wanted))
		local count = ObserverRig.loadMeshes()
		if count < wanted then
			-- name the real cause: an old upload, an id of no segment, or a load
			-- error (only a permission error means the place must be the
			-- published experience, or group, that owns the meshes)
			local r = ObserverRig.LastLoadReport
			local causes = {}
			if #r.stale > 0 then
				table.insert(causes, string.format("%d from an older build, re-upload them (%s)", #r.stale, table.concat(r.stale, ", ")))
			end
			if #r.unmatched > 0 then
				table.insert(causes, string.format("%d ids match no segment's size (%s)", #r.unmatched, table.concat(r.unmatched, ", ")))
			end
			if #r.failed > 0 then
				local denied = false
				for _, e in r.failed do
					local lower = string.lower(e)
					if string.find(lower, "not authorized", 1, true) or string.find(lower, "permission", 1, true) or string.find(lower, "not allowed", 1, true) or string.find(lower, "access", 1, true) then
						denied = true
					end
				end
				table.insert(causes, string.format("%d failed to load%s (first: %s)", #r.failed, if denied then ": the place must be the published experience (or group) that owns them" else "", r.failed[1]))
			end
			warn(string.format("[ObserverService] only %d of %d Observer meshes loaded; the rest stay part-built. %s", count, wanted, if #causes > 0 then table.concat(causes, "; ") else "see the [ObserverRig] warnings above"))
		end
		if count > 0 then
			print(string.format("[ObserverService] sculpted Observer: %d meshes loaded", count))
			if model then
				ObserverRig.dress(model)
			end
		end
	end)
	local acc, proxAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		proxAcc += dt
		if proxAcc >= 0.4 then
			proxAcc = 0
			pcall(updateProximity)
		end
		acc += dt
		if acc < 0.12 then
			return
		end
		local step = acc
		acc = 0
		local ok, err = pcall(tick, step)
		if not ok then
			warn("[ObserverService] tick error:", err)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		stareTime[player] = nil
		blinkingUntil[player] = nil
		metThisRound[player] = nil
		guardianAwarded[player] = nil
		warned[player] = nil
		strikeAfter[player] = nil
		lastVariant[player] = nil
		lastSequence[player] = nil
		if target == player then
			target = nil
		end
	end)
end

return ObserverService
