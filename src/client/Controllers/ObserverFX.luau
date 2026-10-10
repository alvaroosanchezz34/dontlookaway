--[[
	ObserverFX
	Procedural animation for The Observer (client-side Motor6D transforms).
	Its identity is OBSERVATION: it is deliberate, never random. Every
	movement has a reason and ends in stillness.
	  eyes        always on the nearest camera (the small wet glints in its
	              sockets turn, limited and smoothed). Even when it is frozen.
	  head        turns toward you slowly, at a limited speed, and holds there.
	              Every so often it changes the tilt of its head, slowly, and
	              holds that too. No twitches, no snaps.
	Behaviours (server attribute "Behavior", see ObserverService):
	  OBSERVING      watched: absolute stillness, frozen mid-motion; only the
	                 eyes follow you
	  REPOSITIONING  moving far away, unseen: a long, even, loping stride
	  STALKING       closing in: slow, high-kneed, arms hanging, head locked on
	                 its target
	  THREATENING    it straightens to its full height, its arms open a little
	                 and the seam of its face parts: you are about to be caught
	  ATTACKING      the face splits open, arms reaching (what others see)
	  (idle)         deep, slow breathing; the head follows you
	It sheds black ash when it appears or leaves. Mimics give themselves away:
	when they stop, the head keeps turning; when someone pings beside them,
	they stare at that person.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local ObserverFX = {}

type Rig = {
	model: Model,
	motors: { [string]: Motor6D },
	phase: number,
	lastStep: number,
	tilt: number,
	tiltTarget: number,
	nextTilt: number,
	faceOpen: number,
	wasInWorld: boolean,
	targets: { [string]: CFrame },
	pose: { [string]: CFrame },
	snap: boolean,
	lookYaw: number,
	lookPitch: number,
	eyes: { [string]: CFrame },
}

local rigs: { [Model]: Rig } = {}
local mimicTurn: { [Model]: number } = {}
local random = Random.new()

-- How fast the head may turn toward you (degrees per second): slow and sure.
local HEAD_TURN_RATE = 55
local HEAD_YAW_LIMIT = 100

local function collect(model: Model): Rig
	return {
		model = model,
		motors = ObserverRig.motors(model),
		phase = 0,
		lastStep = 0,
		tilt = 14,
		tiltTarget = 14,
		nextTilt = os.clock() + random:NextNumber(6, 10),
		faceOpen = 0,
		wasInWorld = false,
		targets = {},
		pose = {},
		snap = false,
		lookYaw = 0,
		lookPitch = 0,
		eyes = {},
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
		if string.sub(name, 1, 3) ~= "Jaw" and string.sub(name, 1, 7) ~= "EyeTurn" then
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

-- The face halves (0 closed .. 1 open) and the two points inside.
local function setFace(rig: Rig, open: number)
	rig.faceOpen = open
	for name, cf in ObserverRig.faceOpen(open) do
		local motor = rig.motors[name]
		if motor then
			motor.Transform = cf
		end
	end
	for _, side in { "L", "R" } do
		local eye = rig.model:FindFirstChild("Eye" .. side)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = 1 - math.clamp(open * 1.4, 0, 1)
		end
	end
end

-- The eyes follow the camera, smoothly and within their sockets.
local function trackEyes(rig: Rig, camPos: Vector3, dt: number)
	local want = ObserverRig.eyesAt(rig.model, rig.motors, camPos, 38)
	local alpha = 1 - math.exp(-8 * dt)
	for name, cf in want do
		local cur = rig.eyes[name] or CFrame.identity
		cur = cur:Lerp(cf, alpha)
		rig.eyes[name] = cur
		local motor = rig.motors[name]
		if motor then
			motor.Transform = cur
		end
	end
end

-- The head turns toward the camera at a limited rate and holds there.
local function headToward(rig: Rig, root: BasePart, camPos: Vector3, dt: number, enabled: boolean): CFrame
	local wantYaw, wantPitch = 0, 0
	if enabled then
		local rel = root.CFrame:PointToObjectSpace(camPos)
		wantYaw = math.clamp(math.deg(math.atan2(-rel.X, -rel.Z)), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
		wantPitch = math.clamp(math.deg(math.atan2(rel.Y - 4, math.sqrt(rel.X * rel.X + rel.Z * rel.Z))), -25, 20)
	end
	local step = HEAD_TURN_RATE * dt
	rig.lookYaw += math.clamp(wantYaw - rig.lookYaw, -step, step)
	rig.lookPitch += math.clamp(wantPitch - rig.lookPitch, -step * 0.5, step * 0.5)
	-- the tilt changes rarely and slowly
	local now = os.clock()
	if now > rig.nextTilt then
		rig.nextTilt = now + random:NextNumber(7, 13)
		rig.tiltTarget = if rig.tiltTarget > 20 then random:NextNumber(6, 14) else random:NextNumber(24, 34)
	end
	rig.tilt += (rig.tiltTarget - rig.tilt) * (1 - math.exp(-0.9 * dt))
	-- split the turn between neck and head so it reads as deliberate
	return CFrame.Angles(math.rad(-rig.lookPitch), math.rad(rig.lookYaw), math.rad(rig.tilt))
end

local function animate(rig: Rig, dt: number)
	local model = rig.model
	local state = model:GetAttribute("State")
	local behavior = model:GetAttribute("Behavior")
	local root = model.PrimaryPart
	if not root then
		return
	end
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local dist = (root.Position - camPos).Magnitude
	local alive = State.status == "ALIVE"
	-- it always watches you: the eyes move even when the body cannot
	trackEyes(rig, camPos, dt)
	if state == "WATCHED" or behavior == "OBSERVING" then
		-- frozen exactly where it was, face closed. Only the eyes.
		setFace(rig, rig.faceOpen + (0 - rig.faceOpen) * (1 - math.exp(-6 * dt)))
		return
	end
	if state == "ATTACKING" then
		for name, cf in ObserverRig.ScarePose(0.6, 0) do
			set(rig, name, cf)
		end
		apply(rig, dt, 12)
		setFace(rig, rig.faceOpen + (1 - rig.faceOpen) * (1 - math.exp(-10 * dt)))
		return
	end
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	local head = headToward(rig, root, camPos, dt, alive and dist < 60)
	if behavior == "THREATENING" then
		-- it straightens to its full height, arms open, the seam parts
		set(rig, "Waist", CFrame.Angles(math.rad(10), 0, 0))
		set(rig, "NeckJoint", CFrame.Angles(math.rad(8), 0, 0))
		set(rig, "HeadJoint", head)
		set(rig, "LeftShoulder", CFrame.Angles(math.rad(12), 0, math.rad(-26)))
		set(rig, "RightShoulder", CFrame.Angles(math.rad(12), 0, math.rad(26)))
		set(rig, "LeftElbow", CFrame.Angles(math.rad(18), 0, 0))
		set(rig, "RightElbow", CFrame.Angles(math.rad(18), 0, 0))
		set(rig, "RootJoint", CFrame.new(0, 0.25, 0))
		apply(rig, dt, 3)
		setFace(rig, rig.faceOpen + (0.18 - rig.faceOpen) * (1 - math.exp(-2 * dt)))
		return
	end
	setFace(rig, rig.faceOpen * math.exp(-4 * dt))
	if speed > 0.6 then
		local gait = if speed > 13 then "CHASE" elseif behavior == "REPOSITIONING" then "LOPE" else "STALK"
		local cadence = if gait == "CHASE" then 0.5 elseif gait == "LOPE" then 0.4 else 0.32
		rig.phase += dt * speed * cadence
		local p = rig.phase
		local s = math.sin(p)
		local c = math.cos(p)
		-- the head stays on its target while the body moves
		local headWhileMoving = CFrame.Angles(math.rad(-rig.lookPitch), math.rad(rig.lookYaw * 0.6), math.rad(rig.tilt * 0.5))
		if gait == "CHASE" then
			-- folded forward, long reaching strides (escape only)
			set(rig, "RootJoint", CFrame.new(0, -1.2 + math.abs(c) * 0.2, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(-30), s * 0.06, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(22), 0, 0))
			set(rig, "HeadJoint", headWhileMoving)
			set(rig, "LeftShoulder", CFrame.Angles(math.rad(40) - s * 0.7, 0, math.rad(-8)))
			set(rig, "RightShoulder", CFrame.Angles(math.rad(40) + s * 0.7, 0, math.rad(8)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(20 + math.max(0, -s) * 40), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(20 + math.max(0, s) * 40), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(math.rad(20) + s * 0.7, 0, 0))
			set(rig, "RightHip", CFrame.Angles(math.rad(20) - s * 0.7, 0, 0))
			set(rig, "LeftKnee", CFrame.Angles(-math.rad(30) - math.max(0, -c) * 0.6, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(-math.rad(30) - math.max(0, c) * 0.6, 0, 0))
		elseif gait == "LOPE" then
			-- hunched, long even strides, arms swinging late
			set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.12 - 0.3, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(-14), s * 0.05, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(10), 0, 0))
			set(rig, "HeadJoint", headWhileMoving)
			set(rig, "LeftShoulder", CFrame.Angles(math.rad(8) + math.sin(p - 1.1) * 0.4, 0, math.rad(-4)))
			set(rig, "RightShoulder", CFrame.Angles(math.rad(8) - math.sin(p - 1.1) * 0.4, 0, math.rad(4)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(10 + math.max(0, s) * 18), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(10 + math.max(0, -s) * 18), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(-s * 0.5, 0, 0))
			set(rig, "RightHip", CFrame.Angles(s * 0.5, 0, 0))
			set(rig, "LeftKnee", CFrame.Angles(-math.max(0, c) * 0.7, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(-math.max(0, -c) * 0.7, 0, 0))
		else
			-- stalk: slow, high-kneed, arms hanging, head locked on you
			set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.1, 0))
			set(rig, "Waist", CFrame.Angles(math.rad(-6), s * 0.04, 0))
			set(rig, "NeckJoint", CFrame.Angles(math.rad(4), 0, 0))
			set(rig, "HeadJoint", headWhileMoving)
			set(rig, "LeftShoulder", CFrame.Angles(math.sin(p - 0.9) * 0.22, 0, math.rad(-3)))
			set(rig, "RightShoulder", CFrame.Angles(-math.sin(p - 0.9) * 0.22, 0, math.rad(3)))
			set(rig, "LeftElbow", CFrame.Angles(math.rad(6 + math.max(0, s) * 8), 0, 0))
			set(rig, "RightElbow", CFrame.Angles(math.rad(6 + math.max(0, -s) * 8), 0, 0))
			set(rig, "LeftHip", CFrame.Angles(math.max(0, s) * 0.7 - math.max(0, -s) * 0.2, 0, 0))
			set(rig, "RightHip", CFrame.Angles(math.max(0, -s) * 0.7 - math.max(0, s) * 0.2, 0, 0))
			set(rig, "LeftKnee", CFrame.Angles(-math.max(0, s) * 1.0, 0, 0))
			set(rig, "RightKnee", CFrame.Angles(-math.max(0, -s) * 1.0, 0, 0))
		end
		-- heavy, slow footsteps
		if math.abs(s) > 0.97 and os.clock() - rig.lastStep > 0.35 then
			rig.lastStep = os.clock()
			Registry.AudioController:Play("ObserverStep", root.Position - Vector3.new(0, 4, 0), { volume = if gait == "CHASE" then 0.9 else 0.7 })
		end
		apply(rig, dt, if gait == "CHASE" then 12 else 8)
		return
	end

	-- idle: deep, slow breathing; the head follows you and holds
	local breath = math.sin(os.clock() * 1.9) -- ~0.3 Hz
	local chest = breath * 0.035
	set(rig, "Waist", CFrame.Angles(-math.rad(3) - chest, 0, 0))
	set(rig, "LeftHip", CFrame.new())
	set(rig, "RightHip", CFrame.new())
	set(rig, "LeftKnee", CFrame.new())
	set(rig, "RightKnee", CFrame.new())
	set(rig, "LeftShoulder", CFrame.new(0, breath * 0.04, 0) * CFrame.Angles(chest, 0, math.rad(-2)))
	set(rig, "RightShoulder", CFrame.new(0, breath * 0.04, 0) * CFrame.Angles(chest, 0, math.rad(2)))
	set(rig, "LeftElbow", CFrame.Angles(math.rad(4), 0, 0))
	set(rig, "RightElbow", CFrame.Angles(math.rad(4), 0, 0))
	set(rig, "NeckJoint", CFrame.new())
	set(rig, "HeadJoint", head)
	set(rig, "RootJoint", CFrame.new(0, chest * 0.5, 0))
	apply(rig, dt, 4)
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
				-- chasing: no turn, the head lolls hard to one side, face forward
				local loll = if m:GetAttribute("Chasing") and not m:GetAttribute("Reveal") then 32 else 0
				neck.Transform = CFrame.Angles(math.rad(-6 * math.abs(cur) / 165), math.rad(cur), math.rad(14 * math.abs(cur) / 165 + loll))
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
