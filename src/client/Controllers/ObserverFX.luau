--[[
	ObserverFX
	Procedural animation for The Observer (client-side Motor6D transforms).
	Nothing about the way it moves is natural:
	  WATCHED     absolute stillness. No breathing, no sway. Frozen mid-motion.
	              Up close, the seam of its face sometimes parts a little.
	  MOVING /
	  HUNTING     long, too-even strides that stutter and freeze for a frame;
	              one leg drags; arms swing late and too far; close to its
	              target it hunches forward
	  idle        barely-there breathing, the head tipped past where a neck
	              would allow, snapping back upright now and then
	  ATTACKING   arms rise, the head pushes forward, the face opens
	Twitches are instant, never eased. It sheds black ash when it appears or
	leaves. Mimics give themselves away: when they stop, the head keeps turning;
	when someone pings beside them, they stare at that person.
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
	}
end

local function set(rig: Rig, name: string, cf: CFrame)
	local m = rig.motors[name]
	if m then
		m.Transform = cf
	end
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
	set(rig, "JawL", CFrame.Angles(0, math.rad(-55 * open), 0))
	set(rig, "JawR", CFrame.Angles(0, math.rad(55 * open), 0))
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
	local headTwitch = if now < rig.twitchUntil then rig.twitch else CFrame.new()
	-- the head drifts past a natural tilt and snaps back
	if now > rig.nextSnap then
		rig.nextSnap = now + random:NextNumber(5, 11)
		rig.tilt = if rig.tilt > 30 then 6 else random:NextNumber(38, 62)
		if dist < 30 then
			Registry.AudioController:Play("ObserverCrack", (model:FindFirstChild("Head") :: BasePart? or root).Position, { volume = 0.4 })
		end
	end
	if speed > 0.6 then
		-- stutter: the stride freezes for a frame or two
		if now > rig.nextStutter then
			rig.nextStutter = now + random:NextNumber(1.5, 4)
			rig.stutterUntil = now + random:NextNumber(0.08, 0.2)
		end
		if now < rig.stutterUntil then
			return
		end
		rig.phase += dt * speed * 0.42
		local p = rig.phase
		local s = math.sin(p)
		local c = math.cos(p)
		local hunch = if state == "HUNTING" and dist < 30 then 1 else 0
		set(rig, "LeftHip", CFrame.Angles(s * 0.42, 0, 0))
		-- the right leg drags
		set(rig, "RightHip", CFrame.Angles(-s * 0.3, 0, math.rad(4)))
		set(rig, "LeftKnee", CFrame.Angles(math.max(0, -c) * 0.55, 0, 0))
		set(rig, "RightKnee", CFrame.Angles(math.max(0, c) * 0.3, 0, 0))
		-- arms lag behind the legs and swing too far
		set(rig, "LeftShoulder", CFrame.Angles(-math.sin(p - 0.9) * 0.32, 0, math.rad(-3)))
		set(rig, "RightShoulder", CFrame.Angles(math.sin(p - 0.9) * 0.32, 0, math.rad(3)))
		set(rig, "LeftElbow", CFrame.Angles(math.rad(-6 - math.max(0, s) * 8), 0, 0))
		set(rig, "RightElbow", CFrame.Angles(math.rad(-6 - math.max(0, -s) * 8), 0, 0))
		set(rig, "Waist", CFrame.Angles(math.rad(4 + 22 * hunch), s * 0.05, 0))
		set(rig, "NeckJoint", CFrame.Angles(math.rad(-14 * hunch), 0, 0))
		set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.12 - 0.5 * hunch, 0))
		set(rig, "HeadJoint", CFrame.Angles(0, 0, math.rad(rig.tilt * 0.5)) * headTwitch)
		-- heavy, slow footsteps
		if math.abs(s) > 0.97 and now - rig.lastStep > 0.35 then
			rig.lastStep = now
			Registry.AudioController:Play("ObserverStep", root.Position - Vector3.new(0, 4, 0), { volume = 0.7 })
		end
	else
		local b = math.sin(now * 0.9) * 0.012
		set(rig, "Waist", CFrame.Angles(math.rad(2) + b, 0, 0))
		set(rig, "LeftHip", CFrame.new())
		set(rig, "RightHip", CFrame.new())
		set(rig, "LeftKnee", CFrame.new())
		set(rig, "RightKnee", CFrame.new())
		set(rig, "LeftShoulder", CFrame.Angles(b, 0, math.rad(-2)))
		set(rig, "RightShoulder", CFrame.Angles(-b, 0, math.rad(2)))
		set(rig, "NeckJoint", CFrame.Angles(0, 0, math.sin(now * 0.3) * 0.1))
		set(rig, "HeadJoint", CFrame.Angles(0, 0, math.rad(rig.tilt)) * headTwitch)
		set(rig, "RootJoint", CFrame.new())
	end
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
