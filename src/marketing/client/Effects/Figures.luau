--[[
	Figures
	Local figures for shots. Nothing here exists for anyone but the recorder.

	  Figures.person(feetCf)      an anonymous staff member (plain parts, dark
	                              coat, no face): walks, stops, turns
	  Figures.entity(feetCf)      THE OBSERVER's silhouette, built by the game's
	                              own ObserverRig (sculpted meshes when they are
	                              loaded) as a local copy: no tag, no humanoid,
	                              invisible to every game system
	  Figures.pose / walk         driven by the scene timeline
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runtime = require(script.Parent.Parent.Runtime)

local Figures = {}

export type Figure = { model: Model, kind: string, feet: CFrame, phase: number, parts: { [string]: BasePart }, offset: CFrame?, motors: { [string]: Motor6D }? }

local figures: { [string]: Figure } = {}

function Figures.reset()
	table.clear(figures)
end

function Figures.get(name: string): Figure?
	local f = figures[name]
	if f and f.model.Parent then
		return f
	end
	return nil
end

local function part(model: Model, name: string, size: Vector3, color: Color3, material: any): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.Parent = model
	return p
end

-- Lay out the mannequin for a walk phase (radians) at `feet`.
local function layoutPerson(f: Figure)
	local p = f.parts
	local feet = f.feet
	local swing = math.sin(f.phase) * 0.45
	local bob = math.abs(math.cos(f.phase)) * 0.08
	local hips = feet * CFrame.new(0, 3.1 + bob, 0)
	p.Torso.CFrame = hips * CFrame.new(0, 1.55, 0)
	p.Head.CFrame = hips * CFrame.new(0, 3.55, 0)
	p.Hair.CFrame = hips * CFrame.new(0, 3.8, 0.08)
	for side, s in { L = -1, R = 1 } do
		local legSwing = swing * s
		p["Leg" .. side].CFrame = hips * CFrame.new(0.42 * s, 0, 0) * CFrame.Angles(legSwing, 0, 0) * CFrame.new(0, -1.5, 0)
		p["Arm" .. side].CFrame = hips * CFrame.new(1.1 * s, 2.55, 0) * CFrame.Angles(-legSwing * 0.8, 0, 0) * CFrame.new(0, -1.25, 0)
	end
end

function Figures.person(name: string, feet: CFrame, opts: { [string]: any }?): Figure
	opts = opts or {}
	Figures.remove(name)
	local model = Instance.new("Model")
	model.Name = "Person_" .. name
	local coat = opts.coat or Color3.fromRGB(38, 40, 46)
	local skin = opts.skin or Color3.fromRGB(176, 150, 130)
	local parts = {
		Torso = part(model, "Torso", Vector3.new(1.9, 2.4, 1), coat),
		Head = part(model, "Head", Vector3.new(1.05, 1.15, 1.05), skin, Enum.Material.SmoothPlastic),
		Hair = part(model, "Hair", Vector3.new(1.1, 0.5, 1.1), Color3.fromRGB(30, 26, 24)),
		LegL = part(model, "LegL", Vector3.new(0.8, 3, 0.85), Color3.fromRGB(30, 30, 34)),
		LegR = part(model, "LegR", Vector3.new(0.8, 3, 0.85), Color3.fromRGB(30, 30, 34)),
		ArmL = part(model, "ArmL", Vector3.new(0.65, 2.5, 0.7), coat),
		ArmR = part(model, "ArmR", Vector3.new(0.65, 2.5, 0.7), coat),
	}
	model.PrimaryPart = parts.Torso
	local f: Figure = { model = model, kind = "person", feet = feet, phase = 0, parts = parts }
	layoutPerson(f)
	model.Parent = Runtime.folder()
	figures[name] = f
	return f
end

--[[
	A real Roblox character: a local copy of your own avatar (clothes,
	accessories, face), with no scripts, its root anchored and its joints posed
	from here (a procedural walk, no animation assets). Falls back to the
	mannequin when there is no character to copy.
]]
local WALK_JOINTS = {
	-- R15
	LeftHip = { axis = "X", amp = 0.5, sign = 1 },
	RightHip = { axis = "X", amp = 0.5, sign = -1 },
	LeftKnee = { axis = "X", amp = 0.45, sign = 1, bend = true },
	RightKnee = { axis = "X", amp = 0.45, sign = -1, bend = true },
	LeftShoulder = { axis = "X", amp = 0.35, sign = -1 },
	RightShoulder = { axis = "X", amp = 0.35, sign = 1 },
	LeftElbow = { axis = "X", amp = 0.2, sign = -1, bend = true },
	RightElbow = { axis = "X", amp = 0.2, sign = 1, bend = true },
	-- R6
	["Left Hip"] = { axis = "Z", amp = 0.5, sign = 1 },
	["Right Hip"] = { axis = "Z", amp = 0.5, sign = 1 },
	["Left Shoulder"] = { axis = "Z", amp = 0.35, sign = 1 },
	["Right Shoulder"] = { axis = "Z", amp = 0.35, sign = 1 },
}

local function poseActor(f: Figure)
	local motors = f.motors
	if not motors then
		return
	end
	for jointName, motor in motors do
		local j = WALK_JOINTS[jointName]
		if j then
			local wave = math.sin(f.phase) * j.amp * j.sign
			if j.bend then
				-- knees and elbows only bend one way
				wave = -math.abs(wave)
			end
			motor.Transform = if j.axis == "X" then CFrame.Angles(wave, 0, 0) else CFrame.Angles(0, 0, wave)
		end
	end
end

function Figures.actor(name: string, feet: CFrame, opts: { [string]: any }?): Figure
	Figures.remove(name)
	local Players = game:GetService("Players")
	local source = Players.LocalPlayer.Character
	local copy: Model? = nil
	if source then
		local was = source.Archivable
		local ok = pcall(function()
			source.Archivable = true
			copy = source:Clone()
		end)
		pcall(function()
			source.Archivable = was
		end)
		if not ok then
			copy = nil
		end
	end
	if not copy then
		return Figures.person(name, feet, opts)
	end
	local m = copy :: Model
	m.Name = "Actor_" .. name
	-- a puppet: no scripts, no physics of its own, nothing that talks to the game
	local motors: { [string]: Motor6D } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d.Name == "HumanoidRootPart"
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Motor6D") then
			motors[d.Name] = d
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			pcall(function()
				d.EvaluateStateMachine = false
			end)
		end
	end
	for _, tag in m:GetTags() do
		m:RemoveTag(tag)
	end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		m:Destroy()
		return Figures.person(name, feet, opts)
	end
	m.PrimaryPart = root
	-- where the feet are relative to the root
	local boxCf, boxSize = m:GetBoundingBox()
	local bottom = boxCf.Position.Y - boxSize.Y / 2
	local rootHeight = root.CFrame.Position.Y - bottom
	local f: Figure = { model = m, kind = "actor", feet = feet, phase = 0, parts = {}, offset = CFrame.new(0, rootHeight, 0), motors = motors }
	m:PivotTo(feet * (f.offset :: CFrame))
	m.Parent = Runtime.folder()
	figures[name] = f
	return f
end

function Figures.entity(name: string, feet: CFrame, opts: { [string]: any }?): Figure
	opts = opts or {}
	Figures.remove(name)
	local model: Model? = nil
	local ok = pcall(function()
		local ObserverRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ObserverRig")) :: any
		model = ObserverRig.build(feet, { localCopy = true })
	end)
	if not ok or not model then
		-- fallback: a very tall, very thin dark figure
		local m = Instance.new("Model")
		local body = part(m, "Body", Vector3.new(1.3, 8.6, 0.7), Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic)
		body.CFrame = feet * CFrame.new(0, 4.3, 0)
		local head = part(m, "Head", Vector3.new(0.9, 1.3, 0.9), Color3.fromRGB(14, 14, 16), Enum.Material.SmoothPlastic)
		head.CFrame = feet * CFrame.new(0, 9.2, 0)
		m.PrimaryPart = body
		model = m
	end
	local m = model :: Model
	m.Name = "Entity_" .. name
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("ParticleEmitter") and opts.ash == false then
			d.Enabled = false
		end
	end
	-- it never looks back at you with lit eyes unless the shot asks
	for _, side in { "L", "R" } do
		local eye = m:FindFirstChild("Eye" .. side, true)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = if opts.eyes then 0.1 else 1
		end
	end
	m.Parent = Runtime.folder()
	local f: Figure = { model = m, kind = "entity", feet = feet, phase = 0, parts = {}, offset = feet:ToObjectSpace(m:GetPivot()) }
	figures[name] = f
	return f
end

-- Move a figure's feet (walk phase advances with distance for people).
function Figures.place(name: string, feet: CFrame)
	local f = Figures.get(name)
	if not f then
		return
	end
	local moved = (feet.Position - f.feet.Position).Magnitude
	f.feet = feet
	if f.kind == "person" then
		f.phase += moved * 1.15
		layoutPerson(f)
	elseif f.kind == "actor" then
		f.phase += moved * 1.3
		f.model:PivotTo(feet * (f.offset or CFrame.new()))
		poseActor(f)
	else
		-- keep the rig's root where it was relative to its feet
		f.model:PivotTo(feet * (f.offset or CFrame.new()))
	end
end

-- Stand still (settle the legs).
function Figures.settle(name: string)
	local f = Figures.get(name)
	if f and f.kind == "person" then
		f.phase = 0
		layoutPerson(f)
	elseif f and f.kind == "actor" then
		f.phase = 0
		poseActor(f)
	end
end

function Figures.setTransparency(name: string, t: number)
	local f = Figures.get(name)
	if not f then
		return
	end
	for _, d in f.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not string.match(d.Name, "^Eye") then
			local base = d:GetAttribute("MarketingBaseT")
			if base == nil then
				base = d.Transparency
				d:SetAttribute("MarketingBaseT", base)
			end
			d.Transparency = base + (1 - base) * t
		end
	end
end

function Figures.remove(name: string)
	local f = figures[name]
	if f then
		f.model:Destroy()
		figures[name] = nil
	end
end

return Figures
