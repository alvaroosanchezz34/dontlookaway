--[[
	ObserverFX
	Procedural animation for The Observer (client-side Motor6D transforms):
	  WATCHED     absolute stillness. No breathing, no sway. Frozen mid-motion.
	  MOVING /
	  HUNTING     long, slow, too-even strides; arms hang and swing late;
	              the head twitches toward you without the body following
	  idle        barely-there breathing, a slow listening tilt
	  ATTACKING   arms rise, the head pushes forward
	Mimics reveal themselves by turning their head much further than a person can.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Registry = require(script.Parent.Parent.Registry)

local ObserverFX = {}

type Rig = { model: Model, motors: { [string]: Motor6D }, phase: number, twitch: CFrame, twitchUntil: number, nextTwitch: number, lastStep: number }

local rigs: { [Model]: Rig } = {}
local mimicReveal: { [Model]: number } = {}
local random = Random.new()

local function collect(model: Model): Rig
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return { model = model, motors = motors, phase = 0, twitch = CFrame.new(), twitchUntil = 0, nextTwitch = os.clock() + 2, lastStep = 0 }
end

local function set(rig: Rig, name: string, cf: CFrame)
	local m = rig.motors[name]
	if m then
		m.Transform = cf
	end
end

local function animate(rig: Rig, dt: number)
	local model = rig.model
	local state = model:GetAttribute("State")
	if state == "WATCHED" then
		-- hold the last pose exactly; that is what makes it wrong
		return
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	local now = os.clock()
	if state == "ATTACKING" then
		set(rig, "LeftShoulder", CFrame.Angles(math.rad(-95), 0, math.rad(-10)))
		set(rig, "RightShoulder", CFrame.Angles(math.rad(-95), 0, math.rad(10)))
		set(rig, "NeckJoint", CFrame.Angles(math.rad(20), 0, 0))
		set(rig, "HeadJoint", CFrame.Angles(math.rad(10), 0, math.rad(math.sin(now * 40) * 4)))
		set(rig, "Waist", CFrame.Angles(math.rad(14), 0, 0))
		return
	end
	-- twitches: sudden, small, then still again
	if now > rig.nextTwitch then
		rig.nextTwitch = now + random:NextNumber(1.6, 4.5)
		rig.twitchUntil = now + random:NextNumber(0.25, 0.7)
		rig.twitch = CFrame.Angles(math.rad(random:NextNumber(-12, 12)), math.rad(random:NextNumber(-35, 35)), math.rad(random:NextNumber(-25, 25)))
		local head = model:FindFirstChild("Head") :: BasePart?
		if head and (head.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude < 40 then
			Registry.AudioController:Play("ObserverTwitch", head.Position, { volume = 0.5 })
		end
	end
	local headTwitch = if now < rig.twitchUntil then rig.twitch else CFrame.new()
	if speed > 0.6 then
		rig.phase += dt * speed * 0.42
		local p = rig.phase
		local s = math.sin(p)
		local c = math.cos(p)
		set(rig, "LeftHip", CFrame.Angles(s * 0.42, 0, 0))
		set(rig, "RightHip", CFrame.Angles(-s * 0.42, 0, 0))
		set(rig, "LeftKnee", CFrame.Angles(math.max(0, -c) * 0.55, 0, 0))
		set(rig, "RightKnee", CFrame.Angles(math.max(0, c) * 0.55, 0, 0))
		-- arms lag behind the legs and swing too far
		set(rig, "LeftShoulder", CFrame.Angles(-math.sin(p - 0.9) * 0.28, 0, math.rad(-3)))
		set(rig, "RightShoulder", CFrame.Angles(math.sin(p - 0.9) * 0.28, 0, math.rad(3)))
		set(rig, "LeftElbow", CFrame.Angles(math.rad(-6 - math.max(0, s) * 8), 0, 0))
		set(rig, "RightElbow", CFrame.Angles(math.rad(-6 - math.max(0, -s) * 8), 0, 0))
		set(rig, "Waist", CFrame.Angles(math.rad(4), s * 0.05, 0))
		set(rig, "RootJoint", CFrame.new(0, math.abs(c) * 0.12, 0))
		set(rig, "HeadJoint", headTwitch)
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
		set(rig, "HeadJoint", CFrame.Angles(0, 0, math.rad(14) + math.sin(now * 0.25) * 0.1) * headTwitch)
		set(rig, "RootJoint", CFrame.new())
	end
end

local function track(model: Instance)
	if model:IsA("Model") then
		rigs[model] = collect(model)
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
	RunService.Stepped:Connect(function(_, dt)
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			elseif model:IsDescendantOf(Workspace) then
				animate(rig, dt)
			end
		end
		-- mimic reveal: the head keeps turning
		for _, m in Workspace:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Mimic") and m:GetAttribute("Reveal") then
				local start = mimicReveal[m]
				if not start then
					start = os.clock()
					mimicReveal[m] = start
				end
				local head = m:FindFirstChild("Head")
				local neck = head and head:FindFirstChild("Neck")
				if neck and neck:IsA("Motor6D") then
					local t = math.clamp((os.clock() - start) / 0.5, 0, 1)
					neck.Transform = CFrame.Angles(math.rad(-10 * t), math.rad(165 * t), math.rad(20 * t))
				end
			end
		end
		for m in mimicReveal do
			if not m.Parent then
				mimicReveal[m] = nil
			end
		end
	end)
end

return ObserverFX
