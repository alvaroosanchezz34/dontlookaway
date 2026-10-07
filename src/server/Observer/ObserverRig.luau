--[[
	ObserverRig
	Builds THE OBSERVER: a very tall, impossibly thin humanoid with arms that hang
	below its knees, a small featureless head pushed forward on a long neck, and
	a hunched, listening posture. It is built from parts with Motor6D joints so
	clients can animate it procedurally (twitches, unnatural stillness, slow
	strides), and it carries a Humanoid so the server can path it through the map.
]]

local ObserverRig = {}

local SKIN = Color3.fromRGB(16, 16, 18)
local FACE = Color3.fromRGB(46, 44, 44)

ObserverRig.Height = 9.6
ObserverRig.HipHeight = 4.0

local function part(model, name, size, cf, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or SKIN
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.04
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function motor(name, part0, part1, jointWorld: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * jointWorld
	m.C1 = part1.CFrame:Inverse() * jointWorld
	m.Parent = part1
	return m
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Builds the rig standing at `base` (feet on the ground at base.Position).
function ObserverRig.build(base: CFrame?): Model
	base = base or CFrame.new()
	local model = Instance.new("Model")
	model.Name = "TheObserver"

	local at = function(x, y, z, rx, ry, rz)
		return base * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	end

	local rootY = ObserverRig.HipHeight + 1
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), at(0, rootY, 0))
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	root.CastShadow = false

	-- legs: hips at y = 4.6
	local hipY = 4.6
	local lowerTorso = part(model, "LowerTorso", Vector3.new(1.3, 0.9, 0.6), at(0, hipY + 0.35, 0))
	local upperTorso = part(model, "UpperTorso", Vector3.new(1.55, 2.3, 0.62), at(0, hipY + 0.8 + 1.1, -0.25, -12, 0, 0))
	local neck = part(model, "Neck", Vector3.new(0.28, 1.0, 0.28), at(0, hipY + 3.25, -0.65, -28, 0, 0))
	local head = part(model, "Head", Vector3.new(0.85, 1.25, 0.95), at(0, hipY + 3.95, -1.0, -8, 0, 6), FACE)
	-- a faint vertical seam where a face should be
	local seam = part(model, "Seam", Vector3.new(0.05, 0.8, 0.04), head.CFrame * CFrame.new(0, -0.05, -0.48), Color3.fromRGB(8, 8, 8))
	weld(head, seam)

	motor("RootJoint", root, lowerTorso, at(0, hipY + 0.35, 0))
	motor("Waist", lowerTorso, upperTorso, at(0, hipY + 0.8, -0.1))
	motor("NeckJoint", upperTorso, neck, at(0, hipY + 2.85, -0.45))
	motor("HeadJoint", neck, head, at(0, hipY + 3.6, -0.85))

	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		-- shoulders are narrow and high, arms impossibly long
		local shoulderY = hipY + 2.75
		local sx = s * 0.95
		local upperArm = part(model, side .. "UpperArm", Vector3.new(0.32, 2.5, 0.32), at(sx, shoulderY - 1.2, -0.45, 6, 0, s * 4))
		local lowerArm = part(model, side .. "LowerArm", Vector3.new(0.27, 2.5, 0.27), at(sx + s * 0.12, shoulderY - 3.65, -0.3, -4, 0, s * 2))
		local hand = part(model, side .. "Hand", Vector3.new(0.34, 0.5, 0.18), at(sx + s * 0.16, shoulderY - 5.15, -0.32))
		for f = -1, 1 do
			local finger = part(model, side .. "Finger", Vector3.new(0.07, 1.15, 0.07), hand.CFrame * CFrame.new(f * 0.1, -0.78, 0) * CFrame.Angles(math.rad(f * 4), 0, math.rad(f * 5)))
			weld(hand, finger)
		end
		motor(side .. "Shoulder", upperTorso, upperArm, at(sx, shoulderY, -0.45))
		motor(side .. "Elbow", upperArm, lowerArm, at(sx + s * 0.1, shoulderY - 2.42, -0.35))
		motor(side .. "Wrist", lowerArm, hand, at(sx + s * 0.16, shoulderY - 4.9, -0.32))

		local lx = s * 0.4
		local upperLeg = part(model, side .. "UpperLeg", Vector3.new(0.4, 2.35, 0.4), at(lx, hipY - 1.15, 0))
		local lowerLeg = part(model, side .. "LowerLeg", Vector3.new(0.34, 2.15, 0.34), at(lx, hipY - 3.3, 0.05))
		local foot = part(model, side .. "Foot", Vector3.new(0.36, 0.22, 1.1), at(lx, 0.11, -0.25))
		motor(side .. "Hip", lowerTorso, upperLeg, at(lx, hipY, 0))
		motor(side .. "Knee", upperLeg, lowerLeg, at(lx, hipY - 2.3, 0.02))
		motor(side .. "Ankle", lowerLeg, foot, at(lx, 0.25, 0.05))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = ObserverRig.HipHeight
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Parent = model

	-- presence: slow breathing that only carries a short distance
	local breath = Instance.new("Attachment")
	breath.Name = "Voice"
	breath.Parent = head

	model.PrimaryPart = root
	model:SetAttribute("State", "DORMANT")
	model:AddTag("Observer")
	return model
end

return ObserverRig
