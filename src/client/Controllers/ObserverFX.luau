--[[
	ObserverFX
	Procedural animation for The Observer (client-side Motor6D transforms).
	Nothing about the way it moves is natural:
	  WATCHED     absolute stillness. No breathing, no sway. Frozen mid-motion.
	              Up close, the seam of its face sometimes parts a little.
	  idle        deep, slow breathing that lifts the ribs and shoulders, and a
	              cycle of behaviours: LISTEN (the head sweeps, stops, sweeps),
	              SWAY, NECK (the head rolls past where a neck allows, then
	              snaps back) and HANG (it folds forward, arms dangling, and
	              slowly straightens). Nearby and unwatched, its head turns
	              toward you - up to almost backwards - so when you look again it
	              is already looking at you.
	  moving      STALK: slow, high-kneed, arms hanging and swaying late
	              LOPE (hunting): hunched, long strides, arms reaching ahead
	              CHASE (fast): folded almost onto all fours, clawing forward
	              strides stutter and freeze for a frame; one leg drags
	  ATTACKING   arms rise, the head pushes forward, the face opens
	Poses blend smoothly; twitches and snaps are instant, never eased. It sheds
	black ash when it appears or leaves. Mimics give themselves away: when they
	stop, the head keeps turning; when someone pings beside them, they stare at
	that person.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local ObserverFX = {}

type Rig = {
	model: Model,
	motors: { [string]: Motor6D },
	phase: number,
	twitch: CFrame,
	twitchUntil: number,
	nextTwitch: number,
	lastStep: number,
	stutterUntil: number,
	nextStutter: number,
	tilt: number,
	nextSnap: number,
	faceOpen: number,
	wasInWorld: boolean,
	targets: { [string]: CFrame },
	pose: { [string]: CFrame },
	snap: boolean,
	act: string,
	actStart: number,
	actUntil: number,
	snapped: boolean,
	owl: number,
}

local rigs: { [Model]: Rig } = {}
local mimicTurn: { [Model]: number } = {}
local random = Random.new()

local function collect(model: Model): Rig
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return {
		model = model,
		motors = motors,
		phase = 0,
		twitch = CFrame.new(),
		twitchUntil = 0,
		nextTwitch = os.clock() + 2,
		lastStep = 0,
		stutterUntil = 0,
		nextStutter = os.clock() + 3,
		tilt = 18,
		nextSnap = os.clock() + 6,
		faceOpen = 0,
		wasInWorld = false,
		targets = {},
		pose = {},
		snap = false,
		act = "BREATHE",
		actStart = os.clock(),
		actUntil = os.clock() + 6,
		snapped = false,
		owl = 0,
	}
end

-- Pose targets are blended toward each frame (see apply); jaws are driven directly.
local function set(rig: Rig, name: string, cf: CFrame)
	rig.targets[name] = cf
end

local function apply(rig: Rig, dt: number, rate: number)
	local alpha = if rig.snap then 1 else 1 - math.exp(-rate * dt)
	rig.snap = false
	for name, motor in rig.motors do
		if string.sub(name, 1, 3) ~= "Jaw" then
			local target = rig.targets[name] or CFrame.identity
			local current = rig.pose[name] or CFrame.identity
			current = current:Lerp(target, alpha)
			rig.pose[name] = current
			motor.Transform = current
		end
	end
	table.clear(rig.targets)
end

local function ash(model: Model, count: number)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "Ash" then
			d:Emit(count)
		end
	end
end

local function setFace(rig: Rig, open: number)
	rig.faceOpen = open
	local jl, jr = rig.motors.JawL, rig.motors.JawR
	if jl then
		jl.Transform = CFrame.Angles(0, math.rad(-55 * open), 0)
	end
	if jr then
		jr.Transform = CFrame.Angles(0, math.rad(55 * open), 0)
	end
	for _, side in { "L", "R" } do
		local eye = rig.model:FindFirstChild("Eye" .. side, true)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = 1 - math.clamp(open * 1.4, 0, 1)
		end
	end
end

local function animate(rig: Rig, dt: number)
	local model = rig.model
	local state = model:GetAttribute("State")
	local now = os.clock()
	local root = model.PrimaryPart
	if not root then
		return
	end
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local dist = (root.Position - camPos).Magnitude
	if state == "WATCHED" then
		-- hold the last pose exactly; that is what makes it wrong.
		-- Very close, its face parts for a moment.
		if dist < 12 and State.status == "ALIVE" then
			local open = if math.noise(now * 0.7, 9) > 0.35 then 0.25 else 0
			setFace(rig, open)
		end
		return
	end
	if state == "ATTACKING" then
		set(rig, "LeftShoulder", CFrame.Angles(math.rad(-95), 0, math.rad(-10)))
		set(rig, "RightShoulder", CFrame.Angles(math.rad(-95), 0, math.rad(10)))
		set(rig, "NeckJoint", CFrame.Angles(math.rad(20), 0, 0))
		set(rig, "HeadJoint", CFrame.Angles(math.rad(10), 0, math.rad(60 + math.sin(now * 40) * 4)))
		set(rig, "Waist", CFrame.Angles(math.rad(14), 0, 0))
		rig.snap = true
		apply(rig, dt, 30)
		setFace(rig, 1)
		return
	end
	setFace(rig, 0)
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	-- twitches: instant, small, then still again
	if now > rig.nextTwitch then
		rig.nextTwitch = now + random:NextNumber(1.4, 4)
		rig.twitchUntil = now + random:NextNumber(0.12, 0.5)
		rig.twitch = CFrame.Angles(math.rad(random:NextNumber(-14, 14)), math.rad(random:NextNumber(-40, 40)), math.rad(random:NextNumber(-30, 30)))
		local head = model:FindFirstChild("Head") :: BasePart?
		if head and dist < 40 then
			Registry.AudioController:Play("ObserverTwitch", head.Position, { volume = 0.5 })
		end
	end
	local twitching = now < rig.twitchUntil
	local headTwitch = if twitching then rig.twitch else CFrame.new()
	-- the head drifts past a natural tilt and snaps back
	if now > rig.nextSnap then
		rig.nextSnap = now + random:NextNumber(5, 11)
		rig.tilt = if rig.tilt > 30 then 6 else random:NextNumber(38, 62)
		if dist < 30 then
			Registry.AudioController:Play("ObserverCrack", (model:FindFirstChild("Head") :: BasePart? or root).Position, { volume = 0.4 })
		end
	end
	-- owl: unwatched and near, the head turns toward the camera (almost backwards)
	local owlTarget = 0
	if dist < 36 and State.status == "ALIVE" and speed < 0.6 then
		local rel = root.CFrame:PointToObjectSpace(camPos)
		owlTarget = math.clamp(math.deg(math.atan2(-rel.X, -rel.Z)), -170, 170)
	end
	rig.owl += (owlTarget - rig.owl) * (1 - math.exp(-1.1 * dt))
	local owl = CFrame.Angles(0, math.rad(rig.owl), 0)

	if speed > 0.6 then
		-- stutter: the stride freezes for a frame or two
		if now > rig.nextStutter then
			rig.nextStutter = now + random:NextNumber(1.5, 4)
			rig.stutterUntil = now + random:NextNumber(0.08, 0.2)
		end
		if now < rig.stutterUntil then
			return
		end
		local gait = if speed > 13 then "CHASE" elseif state == "HUNTING" or speed > 7 then "LOPE" else "STALK"
		local cadence = if gait == "CHASE" then 0.5 elseif gait == "LOPE" then 0.4 else 0.32
		rig.phase += dt * speed * cadence
		local p = rig.phase
		local s = math.sin(p)
		local c = math.cos(p)
		if gait == "CHASE" then
			-- folded almost onto all fours, clawing forward
			set(rig, "RootJoint", CFrame.new(0, -1.5 + math.abs(c) * 0.25, 0) * CFrame.Angles(math.rad(-20), 0, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(48), s * 0.08, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(-38), 0, 0))
			set(rig, "HeadJoint", CFrame.Angles(math.rad(-18), 0, math.rad(rig.tilt * 0.3)) * headTwitch)
			set(rig, "LeftShoulder", CFrame.Angles(math.rad(-80) + s * 0.9, 0, math.rad(-8)))
			set(rig, "RightShoulder", CFrame.Angles(math.rad(-80) - s * 0.9, 0, math.rad(8)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(-20 - math.max(0, -s) * 50), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(-20 - math.max(0, s) * 50), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(math.rad(-30) + s * 0.7, 0, 0))
			set(rig, "RightHip", CFrame.Angles(math.rad(-30) - s * 0.7, 0, 0))
			set(rig, "LeftKnee", CFrame.Angles(math.rad(40) + math.max(0, -c) * 0.6, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(math.rad(40) + math.max(0, c) * 0.6, 0, 0))
		elseif gait == "LOPE" then
			-- hunched, long strides, arms reaching ahead out of step
			local hunch = if dist < 30 then 1 else 0.6
			set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.15 - 0.45 * hunch, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(10 + 20 * hunch), s * 0.06, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(-18 * hunch), 0, 0))
			set(rig, "HeadJoint", CFrame.Angles(0, 0, math.rad(rig.tilt * 0.4)) * headTwitch)
			set(rig, "LeftShoulder", CFrame.Angles(math.rad(-25) - math.sin(p - 1.1) * 0.5, 0, math.rad(-4)))
			set(rig, "RightShoulder", CFrame.Angles(math.rad(-25) + math.sin(p - 1.1) * 0.5, 0, math.rad(4)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(-10 - math.max(0, s) * 20), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(-10 - math.max(0, -s) * 20), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(s * 0.55, 0, 0))
			-- the right leg drags
			set(rig, "RightHip", CFrame.Angles(-s * 0.38, 0, math.rad(4)))
			set(rig, "LeftKnee", CFrame.Angles(math.max(0, -c) * 0.7, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(math.max(0, c) * 0.35, 0, 0))
		else
			-- stalk: slow, high-kneed, arms hanging and swinging late and too far
			set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.12, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(6), s * 0.05, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(-6), 0, 0))
			set(rig, "HeadJoint", CFrame.Angles(0, 0, math.rad(rig.tilt * 0.5)) * headTwitch)
			set(rig, "LeftShoulder", CFrame.Angles(-math.sin(p - 0.9) * 0.32, 0, math.rad(-3)))
			set(rig, "RightShoulder", CFrame.Angles(math.sin(p - 0.9) * 0.32, 0, math.rad(3)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(-6 - math.max(0, s) * 8), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(-6 - math.max(0, -s) * 8), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(math.max(0, s) * 0.75 - math.max(0, -s) * 0.25, 0, 0))
			set(rig, "RightHip", CFrame.Angles(math.max(0, -s) * 0.5 - math.max(0, s) * 0.2, 0, math.rad(4)))
			set(rig, "LeftKnee", CFrame.Angles(-math.max(0, s) * 1.1, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(-math.max(0, -s) * 0.6, 0, 0))
		end
		-- heavy, slow footsteps
		if math.abs(s) > 0.97 and now - rig.lastStep > 0.35 then
			rig.lastStep = now
			Registry.AudioController:Play("ObserverStep", root.Position - Vector3.new(0, 4, 0), { volume = if gait == "CHASE" then 0.9 else 0.7 })
		end
		apply(rig, dt, if gait == "CHASE" then 14 else 9)
		return
	end

	-- idle: a cycle of behaviours over deep breathing
	if now > rig.actUntil then
		local roll = random:NextNumber()
		rig.act = if roll < 0.32 then "BREATHE" elseif roll < 0.55 then "LISTEN" elseif roll < 0.72 then "SWAY" elseif roll < 0.88 then "NECK" else "HANG"
		rig.actStart = now
		rig.snapped = false
		rig.actUntil = now + (if rig.act == "NECK" then 3.2 elseif rig.act == "HANG" then 7 else random:NextNumber(5, 10))
	end
	local t = now - rig.actStart
	local breath = math.sin(now * 1.9) -- ~0.3 Hz
	local chest = breath * 0.035
	local shoulderLift = breath * 0.05
	local waistPitch, waistYaw, waistRoll = math.rad(2) + chest, 0, 0
	local neck = CFrame.Angles(0, 0, math.sin(now * 0.3) * 0.08)
	local head = CFrame.Angles(0, 0, math.rad(rig.tilt))
	local arms = 0
	if rig.act == "LISTEN" then
		-- the head sweeps, stops dead, sweeps again
		local step = math.floor(t / 1.6)
		local target = math.sin(step * 2.3) * 55
		head = CFrame.Angles(math.rad(-6), math.rad(target), math.rad(rig.tilt * 0.4))
	elseif rig.act == "SWAY" then
		waistRoll = math.sin(t * 0.8) * 0.1
		waistPitch += math.sin(t * 0.55) * 0.08
	elseif rig.act == "NECK" then
		-- rolls far past where a neck allows ... then snaps back
		if t < 2.6 then
			head = CFrame.Angles(0, math.rad(20 * t), math.rad(rig.tilt + 45 * t))
		else
			head = CFrame.Angles(0, 0, math.rad(6))
			if not rig.snapped then
				rig.snapped = true
				rig.snap = true
				if dist < 30 then
					Registry.AudioController:Play("ObserverCrack", (model:FindFirstChild("Head") :: BasePart? or root).Position, { volume = 0.6 })
				end
			end
		end
	elseif rig.act == "HANG" then
		-- folds forward, arms dangling, then slowly straightens
		local fold = if t < 1.5 then t / 1.5 elseif t > 4.5 then math.max(0, 1 - (t - 4.5) / 2.5) else 1
		waistPitch += math.rad(42) * fold
		neck = CFrame.Angles(math.rad(25) * fold, 0, 0)
		arms = fold
	end
	set(rig, "Waist", CFrame.Angles(waistPitch, waistYaw, waistRoll))
	set(rig, "LeftHip", CFrame.new())
	set(rig, "RightHip", CFrame.new())
	set(rig, "LeftKnee", CFrame.new())
	set(rig, "RightKnee", CFrame.new())
	set(rig, "LeftShoulder", CFrame.new(0, shoulderLift, 0) * CFrame.Angles(math.rad(-40) * arms - chest, 0, math.rad(-2)))
	set(rig, "RightShoulder", CFrame.new(0, shoulderLift, 0) * CFrame.Angles(math.rad(-40) * arms + chest, 0, math.rad(2)))
	set(rig, "LeftElbow", CFrame.Angles(math.rad(-4), 0, 0))
	set(rig, "RightElbow", CFrame.Angles(math.rad(-4), 0, 0))
	set(rig, "NeckJoint", neck)
	set(rig, "HeadJoint", owl * head * headTwitch)
	set(rig, "RootJoint", CFrame.new(0, chest * 0.5, 0))
	if twitching then
		rig.snap = true
	end
	apply(rig, dt, if rig.act == "NECK" then 2.2 else 4)
end

local function track(model: Instance)
	if model:IsA("Model") then
		rigs[model] = collect(model)
	end
end

-- Mimics: when they stop, the head keeps turning; when stared at by request
-- (a ping beside them) they look at that person; unmasked, they turn all the way.
local function animateMimics()
	for _, m in Workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Mimic") then
			local head = m:FindFirstChild("Head")
			local neck = head and head:FindFirstChild("Neck")
			if neck and neck:IsA("Motor6D") then
				local target = 0
				if m:GetAttribute("Reveal") then
					target = 165
				elseif m:GetAttribute("Pause") then
					target = 120
				end
				local stare = m:GetAttribute("StareAt")
				if typeof(stare) == "Vector3" and m:GetAttribute("Pause") and m.PrimaryPart then
					local rel = m.PrimaryPart.CFrame:PointToObjectSpace(stare)
					target = math.deg(math.atan2(-rel.X, -rel.Z))
				end
				local cur = mimicTurn[m] or 0
				cur += (target - cur) * 0.06
				mimicTurn[m] = cur
				neck.Transform = CFrame.Angles(math.rad(-6 * math.abs(cur) / 165), math.rad(cur), math.rad(14 * math.abs(cur) / 165))
			end
		end
	end
	for m in mimicTurn do
		if not m.Parent then
			mimicTurn[m] = nil
		end
	end
end

function ObserverFX:Start()
	for _, m in CollectionService:GetTagged("Observer") do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal("Observer"):Connect(function(m)
		task.defer(track, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Observer"):Connect(function(m)
		rigs[m :: Model] = nil
	end)
	Net.event("Effect").OnClientEvent:Connect(function(p)
		if type(p) == "table" and p.name == "ObserverVanish" then
			for model in rigs do
				if model:IsDescendantOf(Workspace) then
					ash(model, 40)
				end
			end
		end
	end)
	RunService.Stepped:Connect(function(_, dt)
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			else
				local inWorld = model:IsDescendantOf(Workspace)
				if inWorld and not rig.wasInWorld then
					-- it arrives in a breath of ash
					ash(model, 30)
				end
				rig.wasInWorld = inWorld
				if inWorld then
					animate(rig, dt)
				end
			end
		end
		animateMimics()
	end)
end

return ObserverFX
