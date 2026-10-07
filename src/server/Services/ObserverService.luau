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
	  Mimic     it wears a player's appearance near someone separated from them.
	            Tells: no flashlight, silent steps, a name tag that glitches, a
	            head that turns too far, pauses mid-stride, a wave that is too
	            slow. It may even ping you. Report it to unmask it.
	  Escape    during the escape it never stops coming.

	Fairness
	  * it is never seen moving or teleporting: every jump happens unseen
	  * a hunt starts out of sight, at a distance, with a real path to its target
	  * before it can catch anyone it must have been close for a few seconds
	    (difficulty WarningTime): you always hear it breathe first
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
local attackLock = false
local mimic: Model? = nil
local mimicData = nil
local active = false
local closeTime: { [Player]: number } = {}
local warned: { [Player]: number } = {}
local lastVariant: { [Player]: string } = {}

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
	m.Parent = ServerStorage
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
end

------------------------------------------------------------------------------------
-- Perception
------------------------------------------------------------------------------------

local function isBlinking(player: Player): boolean
	return (blinkingUntil[player] or 0) > os.clock()
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
				if Registry.PlayerService:IsLookingAt(p, pt, GameConfig.Observer.WatchFOV, 140, model) then
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
	return not Registry.PlayerService:CanAnyoneSee(pts, 70, 240)
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

local function computePath(goal: Vector3)
	if not root then
		return
	end
	lastPathAt = os.clock()
	lastPathGoal = goal
	local from = root.Position
	task.spawn(function()
		local p = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 9, AgentCanJump = false, WaypointSpacing = 4 })
		local ok = pcall(function()
			p:ComputeAsync(from, goal)
		end)
		if ok and p.Status == Enum.PathStatus.Success then
			waypoints = p:GetWaypoints()
			waypointIndex = math.min(2, #waypoints)
		else
			waypoints = { { Position = goal } }
			waypointIndex = 1
		end
	end)
end

local function moveToward(goal: Vector3, speed: number)
	if not humanoid or not root then
		return
	end
	humanoid.WalkSpeed = speed
	if os.clock() - lastPathAt > 1.1 or (goal - lastPathGoal).Magnitude > 8 then
		computePath(goal)
	end
	local wp = waypoints[waypointIndex]
	if wp then
		local pos = wp.Position
		if (Util.flat(pos - root.Position)).Magnitude < 2.5 and waypointIndex < #waypoints then
			waypointIndex += 1
			wp = waypoints[waypointIndex]
			pos = wp.Position
		end
		humanoid:MoveTo(pos)
	else
		humanoid:MoveTo(goal)
	end
	Registry.DoorService:OpenNear(root.Position, 7)
end

local function freeze()
	if humanoid and root then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero)
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
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
		local look = Util.flat(goal - stepTo)
		local cf = if look.Magnitude > 0.1 then CFrame.lookAt(stepTo, stepTo + look.Unit) else CFrame.new(stepTo)
		model:PivotTo(cf * CFrame.new(0, ObserverRig.HipHeight + 1 - 0, 0))
		waypointIndex = math.min(#waypoints, waypointIndex + 2)
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
	local dark = Registry.LightingService:GetBlackout() >= 3 or (not Registry.LightingService:IsPowered() and not Registry.InventoryService:IsLightOn(victim))
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
	data.side = data.side or (if rng:Chance(0.5) then 1 else -1)
	return variant, data, lookDir
end

local function attack(victim: Player)
	if attackLock or not model or not root then
		return
	end
	attackLock = true
	setState(S.Attacking)
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
	Registry.AudioService:PlayAt("ObserverScreech", headPos(), { volume = 0.55 })
	ObserverService.Caught:Fire(victim)
	Registry.RoundService:KillPlayer(victim, model:GetPivot(), info)
	Registry.AnalyticsService:Event(victim, "ObserverCatch", 1, { variant = info.variant })
	task.delay(3, function()
		attackLock = false
		closeTime[victim] = 0
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
-- Mimic
------------------------------------------------------------------------------------

local WALK_ANIM = "rbxassetid://507777826"

function ObserverService:Mimic(viewer: Player, imitated: Player?): boolean
	if not active or mimic then
		return false
	end
	imitated = imitated or viewer
	local source = (imitated :: Player).Character
	local sourceHumanoid = source and source:FindFirstChildOfClass("Humanoid")
	local vroot = Util.getRoot(viewer)
	local look = Registry.PlayerService:GetLook(viewer)
	if not sourceHumanoid or not vroot or not look then
		return false
	end
	-- somewhere the viewer will notice soon, but cannot see right now
	local spot = nil
	for _, s in candidateSpots(22, 60, vroot.Position, true) do
		local head = s + Vector3.new(0, 4.5, 0)
		if unseenAt(s) and Registry.PlayerService:HasLineOfSight(look.origin, head) then
			spot = s
			break
		end
	end
	if not spot then
		return false
	end
	local ok, desc = pcall(function()
		return sourceHumanoid:GetAppliedDescription()
	end)
	if not ok or not desc then
		return false
	end
	local okM, double = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not okM or not double then
		return false
	end
	local m = double :: Model
	m.Name = "Mimic"
	m:SetAttribute("PlayerName", (imitated :: Player).DisplayName)
	m:SetAttribute("Title", (imitated :: Player):GetAttribute("Title"))
	m:SetAttribute("Mimic", true)
	m:AddTag("NameTagged")
	local away = Util.flat(spot - vroot.Position)
	m:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 3, 0), spot + Vector3.new(0, 3, 0) + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1))))
	local mh = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	mh.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	mh.WalkSpeed = 5
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Observer"
		end
	end
	m.Parent = workspace
	if m.PrimaryPart then
		pcall(function()
			(m.PrimaryPart :: BasePart):SetNetworkOwner(nil)
		end)
	end
	local animator = mh:FindFirstChildOfClass("Animator") or Instance.new("Animator", mh)
	local anim = Instance.new("Animation")
	anim.AnimationId = WALK_ANIM
	local okA, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if okA and track then
		track.Looped = true
		track:Play(0.3, 1, 0.6)
	end
	mimic = m
	local rng = Registry.HorrorDirector:Rng()
	mimicData = {
		viewer = viewer,
		imitated = imitated,
		spawned = os.clock(),
		seenFor = 0,
		walkTo = spot + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)) * 20,
		nextPauseAt = os.clock() + rng:Number(2.5, 5),
		pausedUntil = 0,
		waved = false,
		pinged = false,
		pingAt = if imitated ~= viewer and rng:Chance(0.35) then os.clock() + rng:Number(2.5, 5) else math.huge,
	}
	mh:MoveTo(mimicData.walkTo)
	Registry.PlayerService:AddPerceptionExclusion(m)
	return true
end

local function endMimic(lunge: boolean)
	local m = mimic
	if not m then
		return
	end
	local viewer = mimicData and mimicData.viewer
	mimic = nil
	mimicData = nil
	m:SetAttribute("Reveal", true)
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		Registry.AudioService:PlayAt("ObserverTwitch", head.Position)
	end
	task.delay(if lunge then 0.35 else 0.9, function()
		if lunge and viewer then
			Net.fire(viewer, "Effect", { name = "Jumpscare", kind = "mimic" })
			Registry.AudioService:Play2D({ viewer }, "JumpSting")
		end
		Registry.PlayerService:RemovePerceptionExclusion(m)
		m:Destroy()
		if lunge and viewer and Registry.HorrorDirector:Rng():Chance(0.5) then
			task.delay(2, function()
				ObserverService:StartHunt(viewer, { behind = true, reason = "mimic" })
			end)
		end
	end)
end

local function updateMimic(dt: number)
	local m = mimic
	if not m or not mimicData then
		return
	end
	local viewer = mimicData.viewer
	local vroot = Util.getRoot(viewer)
	local mroot = m.PrimaryPart
	local mh = m:FindFirstChildOfClass("Humanoid")
	if not vroot or not mroot or not mh or not Registry.PlayerService:IsAlive(viewer) or os.clock() - mimicData.spawned > 35 then
		endMimic(false)
		return
	end
	local now = os.clock()
	local rng = Registry.HorrorDirector:Rng()
	local dist = (vroot.Position - mroot.Position).Magnitude
	if dist < 7 then
		endMimic(true)
		return
	end
	-- it walks almost right: it stops for no reason, then carries on
	if now < mimicData.pausedUntil then
		mh:Move(Vector3.zero)
		m:SetAttribute("Pause", true)
	else
		if now > mimicData.nextPauseAt then
			mimicData.pausedUntil = now + rng:Number(1, 2.4)
			mimicData.nextPauseAt = now + rng:Number(4, 8)
		end
		m:SetAttribute("Pause", false)
		mh:MoveTo(mimicData.walkTo)
	end
	local seen = Registry.PlayerService:IsLookingAt(viewer, mroot.Position + Vector3.new(0, 1.5, 0), 25, 90, m)
	if seen then
		mimicData.seenFor += dt
		-- noticed: it waves back, far too slowly
		if not mimicData.waved and dist < 45 then
			mimicData.waved = true
			mimicData.pausedUntil = now + 3
			m:SetAttribute("Emote", "wave")
			m:SetAttribute("EmoteSpeed", 0.35)
			m:SetAttribute("EmoteAt", workspace:GetServerTimeNow())
		end
		if mimicData.seenFor > 5 then
			endMimic(false)
		end
	end
	-- sometimes it calls you over, with your friend's name
	if not mimicData.pinged and now > mimicData.pingAt and not seen then
		mimicData.pinged = true
		local imitated = mimicData.imitated
		Registry.PingService:FakePing(viewer, "COME_HERE", mroot.Position + Vector3.new(0, 1, 0), if imitated then imitated.DisplayName else viewer.DisplayName, if imitated then imitated.UserId else 0)
	end
end

-- A real ping right next to a mimic: it stops and turns to the one who pinged.
function ObserverService:OnPing(from: Player, position: Vector3)
	local m = mimic
	if not m or not mimicData or not m.PrimaryPart then
		return
	end
	if (m.PrimaryPart.Position - position).Magnitude < 7 then
		mimicData.pausedUntil = os.clock() + 3.5
		local froot = Util.getRoot(from)
		if froot then
			m:SetAttribute("StareAt", froot.Position)
		end
		local head = m:FindFirstChild("Head") :: BasePart?
		if head then
			Registry.AudioService:PlayAt("ObserverCrack", head.Position, { volume = 0.6 })
		end
	end
end

-- Reporting a mimic unmasks it. Returns true if the report was aimed at one.
function ObserverService:ReportMimic(player: Player, origin: Vector3, dir: Vector3): boolean
	local m = mimic
	if not m or not mimicData or not m.PrimaryPart then
		return false
	end
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
	local name = if mimicData.imitated then mimicData.imitated.DisplayName else "you"
	Net.fire(player, "Notify", { kind = "anomaly", text = "THAT WASN'T " .. string.upper(name), sub = "MIMIC UNMASKED" })
	Net.fire(player, "Effect", { name = "RealitySnap" })
	Registry.ProgressionService:Award(player, "NOT_MY_FRIEND")
	Registry.ProgressionService:MimicSpotted(player)
	endMimic(false)
	return true
end

------------------------------------------------------------------------------------
-- Main loop
------------------------------------------------------------------------------------

local function tick(dt: number)
	updateMimic(dt)
	if not mode or not model or model.Parent ~= workspace or not root then
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
		local seen = Registry.PlayerService:IsLookingAt(target, headPos(), 40, 200, model)
		if seen then
			if not data.seenAt then
				data.seenAt = os.clock()
				firstSight(target)
			end
			data.lookAwayFor = 0
		elseif data.seenAt then
			data.lookAwayFor += dt
			-- gone the moment they look away. Never let them see it leave.
			if data.lookAwayFor > 0.3 and not Registry.PlayerService:CanAnyoneSee(samplePoints(), 70, 240, model) then
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
	setState(if (tr.Position - root.Position).Magnitude < 40 then S.Hunting else S.Moving)
	local cfg = Registry.RoundService:GetDifficultyConfig()
	-- warnings first: you always hear it before it can reach you
	for _, p in Registry.PlayerService:GetAlive() do
		local pr = Util.getRoot(p)
		if pr then
			local d = (pr.Position - root.Position).Magnitude
			if d < 14 then
				closeTime[p] = (closeTime[p] or 0) + dt
				if (warned[p] or 0) < os.clock() - 8 then
					warned[p] = os.clock()
					Registry.AudioService:PlayAtFor({ p }, "ObserverInhale", headPos(), { volume = 1 })
					Net.fire(p, "Effect", { name = "ObserverClose" })
				end
			else
				closeTime[p] = math.max(0, (closeTime[p] or 0) - dt * 0.5)
			end
			-- catch anyone close who is not looking at it, once they have been warned
			if d <= GameConfig.Observer.CatchDistance + 1.5 and (closeTime[p] or 0) >= (cfg.WarningTime or 1.5) then
				attack(p)
				return
			end
		end
	end
	-- the dark is on its side
	local dark = Registry.LightingService:GetBlackout() >= 3 or not Registry.LightingService:IsPowered()
	local cunning = cfg.ObserverCunning or 0
	local speed = cfg.ObserverSpeed
	if mode == "escape" then
		speed *= 0.9
	end
	if dark then
		speed *= 1 + 0.06 * (cunning + 1)
	end
	moveToward(tr.Position, speed)
	local blinkChance = 0.08 * (1 + cunning * 0.35) * (if dark then 1.4 else 1)
	if os.clock() - unwatchedSince > 1.6 and Registry.HorrorDirector:Rng():Chance(blinkChance) then
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
		end
	end
end

function ObserverService:BeginRound()
	active = true
	metThisRound = {}
	totalStare = {}
	closeTime = {}
	guardianAwarded = {}
	stareTime = {}
	blinkingUntil = {}
	attackLock = false
	ensureModel()
	park()
end

function ObserverService:EndRound()
	active = false
	if mimic then
		mimic:Destroy()
		mimic = nil
		mimicData = nil
	end
	park()
end

function ObserverService:GetMimic(): Model?
	return mimic
end

function ObserverService:GetModel(): Model?
	return model
end

function ObserverService:Start()
	ensureModel()
	-- sculpted meshes (if uploaded) load in the background; the rig built above
	-- is dressed as soon as they arrive, later copies are dressed on creation
	task.spawn(function()
		if ObserverRig.loadMeshes() > 0 and model then
			ObserverRig.dress(model)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
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
		closeTime[player] = nil
		warned[player] = nil
		lastVariant[player] = nil
		if target == player then
			target = nil
		end
	end)
end

return ObserverService
