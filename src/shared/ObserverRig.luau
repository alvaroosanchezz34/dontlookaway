--[[
	ObserverRig
	Builds THE OBSERVER: a very tall, impossibly thin humanoid with arms that hang
	below its knees, a small featureless head pushed forward on a long neck, and
	a hunched, listening posture.

	Details that make it wrong even when it is perfectly still:
	  * a spine that shows through the back, ribs pressing through the chest
	  * a faintly wet sheen that catches flashlights
	  * its face: a long, pale, waxy face set into a black skull, split down
	    the middle by a seam. Two huge lidless eyes sit in dark sockets and
	    always turn to the nearest person (it OBSERVES). No mouth. During an
	    attack the face parts along the seam: the halves swing open like
	    doors, carrying the eyes apart, and show a wet red maw lined with
	    small teeth, with two pale points deep inside.
	    The face is what you remember: pale against the dark body, it reads at
	    the end of a corridor, and it is lit and framed in every jumpscare.
	  * long, many-jointed fingers

	It is built from parts with Motor6D joints so clients can animate it
	procedurally (twitches, unnatural stillness, slow strides, the face
	opening), and it carries a Humanoid so the server can path it through the
	map. Shared so clients can build a local copy for death cinematics, framed
	exactly against their own camera.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(script.Parent.Config.AssetIds)
local MeshMeta = require(script.Parent.Config.ObserverMeshMeta)

local ObserverRig = {}

-- Rig part -> generated mesh (tools/gen_observer.py). Both sides share a mesh.
local SEGMENT_MESH = {
	UpperTorso = "UpperTorso",
	LowerTorso = "LowerTorso",
	Neck = "Neck",
	Head = "Head",
	-- FaceL / FaceR keep their part-built pale face (see the face below): the
	-- sculpted face halves were dark and featureless
	LeftUpperArm = "UpperArm",
	RightUpperArm = "UpperArm",
	LeftLowerArm = "LowerArm",
	RightLowerArm = "LowerArm",
	LeftHand = "Hand",
	RightHand = "Hand",
	LeftUpperLeg = "UpperLeg",
	RightUpperLeg = "UpperLeg",
	LeftLowerLeg = "LowerLeg",
	RightLowerLeg = "LowerLeg",
	LeftFoot = "Foot",
	RightFoot = "Foot",
}

-- Part-built details that the meshes already sculpt (ribs, spine, fingers...).
local MESH_DETAILS = { Spine = true, Rib = true, Blade = true, LeftFinger = true, RightFinger = true }

local TEMPLATE_FOLDER = "ObserverMeshes"

local SKIN = Color3.fromRGB(20, 19, 21)
local FACE = Color3.fromRGB(34, 31, 31) -- the skull around the face
local BONE = Color3.fromRGB(30, 28, 29)
-- the face itself: pale and waxy, so it reads against the black body and in
-- the dark (albedo ~0.55, about the brightest thing in a lit corridor)
local PALE = Color3.fromRGB(156, 148, 132)
local PALE_SHADE = Color3.fromRGB(112, 102, 90)
local SOCKET = Color3.fromRGB(22, 14, 14)
local MAW = Color3.fromRGB(64, 8, 10)
local TOOTH = Color3.fromRGB(206, 196, 168)

ObserverRig.Height = 9.6
ObserverRig.HipHeight = 4.0

local function part(model, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or SKIN
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = 0.07
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- An ellipsoid: a part with a sphere SpecialMesh scaled to `size`.
local function ellipsoid(model, name, size: Vector3, cf: CFrame, color: Color3, material: any?)
	local p = part(model, name, size, cf, color, material)
	p.Reflectance = 0
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
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
	-- the rest offset, for posing without physics (ObserverRig.solve)
	b:SetAttribute("RestOffset", a.CFrame:ToObjectSpace(b.CFrame))
end

-- Builds the rig standing at `base` (feet on the ground at base.Position).
-- opts.local: client-side copy for cinematics (no Humanoid, anchored root)
function ObserverRig.build(base: CFrame?, opts: { [string]: any }?): Model
	base = base or CFrame.new()
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = if opts.localCopy then "ObserverScare" else "TheObserver"

	local at = function(x, y, z, rx, ry, rz)
		return base * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	end

	local rootY = ObserverRig.HipHeight + 1
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), at(0, rootY, 0))
	root.Transparency = 1
	root.CanCollide = not opts.localCopy
	root.CanQuery = false
	root.Massless = false
	root.CastShadow = false
	root.Anchored = opts.localCopy == true

	-- legs: hips at y = 4.6
	local hipY = 4.6
	local lowerTorso = part(model, "LowerTorso", Vector3.new(1.3, 0.9, 0.6), at(0, hipY + 0.35, 0))
	local upperTorso = part(model, "UpperTorso", Vector3.new(1.55, 2.3, 0.62), at(0, hipY + 0.8 + 1.1, -0.25, -12, 0, 0))
	local neck = part(model, "Neck", Vector3.new(0.28, 1.0, 0.28), at(0, hipY + 3.25, -0.65, -28, 0, 0))
	local head = part(model, "Head", Vector3.new(0.85, 1.25, 0.95), at(0, hipY + 3.95, -1.0, -8, 0, 6), FACE)

	-- the spine shows through the back, the ribs through the chest
	for i = 0, 6 do
		local node = part(model, "Spine", Vector3.new(0.16, 0.12, 0.1), upperTorso.CFrame * CFrame.new(0, 1.0 - i * 0.32, 0.33), BONE)
		weld(upperTorso, node)
	end
	for i = 0, 4 do
		for _, s in { -1, 1 } do
			local rib = part(model, "Rib", Vector3.new(0.62, 0.07, 0.06), upperTorso.CFrame * CFrame.new(s * 0.36, 0.75 - i * 0.28, -0.32) * CFrame.Angles(0, 0, math.rad(s * (18 + i * 3))), BONE)
			weld(upperTorso, rib)
		end
	end
	for _, s in { -1, 1 } do
		local blade = part(model, "Blade", Vector3.new(0.45, 0.6, 0.08), upperTorso.CFrame * CFrame.new(s * 0.45, 0.7, 0.33) * CFrame.Angles(0, 0, math.rad(s * 12)), BONE)
		weld(upperTorso, blade)
	end

	-- the skull is an egg, not a box (the sculpted head mesh replaces it)
	local skullShape = Instance.new("SpecialMesh")
	skullShape.MeshType = Enum.MeshType.Sphere
	skullShape.Parent = head

	-- THE FACE (head space: front is -Z). One long, pale, waxy oval split by a
	-- hairline seam: two heavily overlapping halves, each hinged at its outer
	-- edge. Deep black sockets with no whites, only a small wet glint far
	-- inside that turns to follow you. A thin mouth, too wide and too low.
	-- When the face opens, the halves swing back into the skull from the
	-- seam and the gap shows a wet red maw lined with needle teeth.
	local function hs(x, y, z)
		return head.CFrame * CFrame.new(x, y, z)
	end
	local maw = ellipsoid(model, "Maw", Vector3.new(0.44, 0.86, 0.16), hs(0, -0.04, -0.4), MAW)
	maw.Reflectance = 0.18
	weld(head, maw)
	local throat = ellipsoid(model, "Throat", Vector3.new(0.16, 0.44, 0.05), hs(0, -0.02, -0.455), Color3.fromRGB(14, 2, 3))
	weld(head, throat)
	local halves = {}
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		-- needle teeth lining the gap (on the maw: they show when it opens),
		-- uneven in length, angle and spacing
		for i = 0, 8 do
			local k = (i * 37 + (if s < 0 then 17 else 0)) % 7
			local len = 0.07 + k * 0.012
			local y = 0.3 - i * 0.075 + (k % 3) * 0.01
			local tilt = (k - 3) * 7 + s * 6
			local tooth = ellipsoid(model, "Tooth", Vector3.new(len, 0.02, 0.02), hs(s * (0.15 - len / 2), y, -0.455) * CFrame.Angles(0, 0, math.rad(tilt)), TOOTH)
			weld(head, tooth)
		end
		local half = ellipsoid(model, "Face" .. side, Vector3.new(0.6, 1.24, 0.34), hs(s * 0.105, -0.04, -0.36), PALE)
		half.Reflectance = 0.06
		motor("Jaw" .. side, head, half, hs(s * 0.4, -0.04, -0.42))
		halves[s] = half
		-- hollows under the cheekbones and at the temples
		local hollow = ellipsoid(model, "Cheek", Vector3.new(0.17, 0.42, 0.08), hs(s * 0.26, -0.2, -0.47), PALE_SHADE)
		weld(half, hollow)
		local temple = ellipsoid(model, "Cheek", Vector3.new(0.12, 0.3, 0.08), hs(s * 0.3, 0.3, -0.42), PALE_SHADE)
		weld(half, temple)
		-- a long, deep, black socket that droops at the outer corner; far
		-- inside it, a small wet eye with a pale glint that turns to follow you
		local socket = ellipsoid(model, "Socket", Vector3.new(0.19, 0.34, 0.1), hs(s * 0.165, 0.17, -0.5) * CFrame.Angles(0, 0, math.rad(s * -14)), SOCKET)
		weld(half, socket)
		local eyeAt = hs(s * 0.165, 0.17, -0.535)
		local ball = part(model, "Eyeball" .. side, Vector3.new(0.1, 0.1, 0.1), eyeAt, Color3.fromRGB(26, 22, 22))
		ball.Shape = Enum.PartType.Ball
		ball.Reflectance = 0.35
		motor("EyeTurn" .. side, half, ball, eyeAt)
		local iris = ellipsoid(model, "Iris", Vector3.new(0.045, 0.045, 0.02), ball.CFrame * CFrame.new(0, 0, -0.046), Color3.fromRGB(196, 190, 170))
		iris.Reflectance = 0.3
		weld(ball, iris)
		local pupil = ellipsoid(model, "Pupil", Vector3.new(0.018, 0.018, 0.01), ball.CFrame * CFrame.new(0, 0, -0.056), Color3.fromRGB(3, 3, 3))
		weld(ball, pupil)
		-- two slits for a nose, too close together
		local slit = ellipsoid(model, "Slit", Vector3.new(0.022, 0.09, 0.03), hs(s * 0.032, -0.08, -0.525), SOCKET)
		weld(half, slit)
		-- two pale points deep inside, lit only when it attacks
		local eye = part(model, "Eye" .. side, Vector3.new(0.07, 0.07, 0.03), hs(s * 0.07, 0.12, -0.49), Color3.fromRGB(230, 226, 214), Enum.Material.Neon)
		eye.Transparency = 1
		eye.CastShadow = false
		weld(head, eye)
	end
	-- the seam: a hairline on the left half (it goes with the face when it opens)
	local seam = part(model, "Seam", Vector3.new(0.016, 1.04, 0.02), hs(0, -0.03, -0.527), Color3.fromRGB(46, 30, 28))
	weld(halves[-1], seam)

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
			-- two segments per finger, the second bent slightly inward
			local first = part(model, side .. "Finger", Vector3.new(0.07, 0.75, 0.07), hand.CFrame * CFrame.new(f * 0.1, -0.6, 0) * CFrame.Angles(math.rad(f * 4), 0, math.rad(f * 5)))
			weld(hand, first)
			local second = part(model, side .. "Finger", Vector3.new(0.06, 0.6, 0.06), first.CFrame * CFrame.new(0, -0.62, -0.05) * CFrame.Angles(math.rad(-14), 0, 0))
			weld(first, second)
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

	-- appearing / vanishing: a burst of black ash (emitted on demand)
	local ash = Instance.new("ParticleEmitter")
	ash.Name = "Ash"
	ash.Rate = 0
	ash.Lifetime = NumberRange.new(0.6, 1.4)
	ash.Speed = NumberRange.new(1, 4)
	ash.SpreadAngle = Vector2.new(180, 180)
	ash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) })
	ash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	ash.Color = ColorSequence.new(Color3.fromRGB(8, 8, 10))
	ash.LightInfluence = 1
	ash.Drag = 3
	ash.Parent = upperTorso

	if not opts.localCopy then
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
	end

	-- presence: slow breathing that only carries a short distance
	local breath = Instance.new("Attachment")
	breath.Name = "Voice"
	breath.Parent = head

	model.PrimaryPart = root
	ObserverRig.dress(model)
	model:SetAttribute("State", "DORMANT")
	if not opts.localCopy then
		model:AddTag("Observer")
	end
	return model
end

------------------------------------------------------------------------------------
-- Sculpted meshes
------------------------------------------------------------------------------------

--[[
	Swaps the part-built body for the sculpted meshes when they are available
	(uploaded and loaded by loadMeshes). Each mesh is welded to its rig part, so
	every Motor6D animation keeps working; the original part becomes invisible.
	Segments without a mesh keep their parts, so a partial upload still works.
]]
function ObserverRig.dress(model: Model): boolean
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not folder or #folder:GetChildren() == 0 or model:GetAttribute("Sculpted") then
		return false
	end
	local dressed = false
	local hasHand = false
	for _, p in model:GetChildren() do
		local meshName = SEGMENT_MESH[p.Name]
		local template = meshName and folder:FindFirstChild(meshName)
		local meta = meshName and MeshMeta[meshName]
		if p:IsA("BasePart") and template and meta then
			local mesh = template:Clone()
			mesh.Name = p.Name .. "Mesh"
			mesh.Size = meta.size
			mesh.CFrame = p.CFrame * CFrame.new(meta.offset)
			mesh.Anchored = false
			mesh.Massless = true
			mesh.CanCollide = false
			mesh.CanTouch = false
			mesh.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = mesh
			weld.Parent = mesh
			mesh.Parent = model
			p.Transparency = 1
			dressed = true
			if meshName == "Hand" then
				hasHand = true
			end
		end
	end
	if dressed then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and MESH_DETAILS[p.Name] and (hasHand or not string.find(p.Name, "Finger")) then
				p.Transparency = 1
			end
		end
		model:SetAttribute("Sculpted", true)
	end
	return dressed
end

--[[
	Server: turns the uploaded mesh ids (Config/AssetIds) into MeshPart templates
	in ReplicatedStorage.ObserverMeshes, with the PBR skin. Rigs built afterwards
	(server and client copies) are dressed automatically. Safe to call when no
	ids are set (does nothing).
]]
-- How many Observer meshes have an id configured (mesh or model).
function ObserverRig.configuredMeshes(): number
	local n = 0
	for meshName in MeshMeta do
		if AssetIds.url(AssetIds.Observer.meshes[meshName]) or AssetIds.url(AssetIds.Observer.models[meshName]) then
			n += 1
		end
	end
	return n
end

function ObserverRig.loadMeshes(): number
	if not RunService:IsServer() then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	local loaded = 0
	for meshName in MeshMeta do
		local meshUrl = AssetIds.url(AssetIds.Observer.meshes[meshName])
		local modelId = AssetIds.Observer.models[meshName]
		local ok, mesh = false, nil
		if meshUrl then
			ok, mesh = pcall(function()
				return game:GetService("AssetService"):CreateMeshPartAsync(meshUrl, {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Precise,
				})
			end)
		elseif AssetIds.url(modelId) then
			-- the imported model (owned by the experience's creator) holds the MeshPart
			ok, mesh = pcall(function()
				local container = game:GetService("InsertService"):LoadAsset(modelId)
				local found = container:FindFirstChildWhichIsA("MeshPart", true)
				local copy = if found then found:Clone() else nil
				container:Destroy()
				if not copy then
					error("no MeshPart inside model " .. tostring(modelId))
				end
				for _, d in copy:GetChildren() do
					d:Destroy()
				end
				return copy
			end)
		end
		if meshUrl or AssetIds.url(modelId) then
			if ok and mesh then
				mesh.Name = meshName
				mesh.Size = MeshMeta[meshName].size
				mesh.Color = SKIN
				mesh.Material = Enum.Material.SmoothPlastic
				mesh.Reflectance = 0.06
				mesh.CastShadow = true
				-- the PBR skin is a SurfaceAppearance placed in the game by Rojo
				-- (scripts may not set its maps): ReplicatedStorage.Shared.ObserverSkin
				local skinTemplate = script.Parent:FindFirstChild("ObserverSkin")
				if skinTemplate then
					skinTemplate:Clone().Parent = mesh
				end
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = TEMPLATE_FOLDER
					folder.Parent = ReplicatedStorage
				end
				local old = (folder :: Folder):FindFirstChild(meshName)
				if old then
					old:Destroy()
				end
				mesh.Parent = folder
				loaded += 1
			else
				warn("[ObserverRig] could not load mesh " .. meshName .. ": " .. tostring(mesh))
			end
		end
	end
	return loaded
end

------------------------------------------------------------------------------------
-- Posing without physics (cinematic framing, tests, offline renders)
------------------------------------------------------------------------------------

-- Between the eyes, on the face: what a jumpscare frames (head space).
ObserverRig.FaceAnchor = CFrame.new(0, 0.05, -0.53)

local HEAD_CHAIN = { "RootJoint", "Waist", "NeckJoint", "HeadJoint" }

function ObserverRig.motors(model: Model): { [string]: Motor6D }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			list[d.Name] = d
		end
	end
	return list
end

-- The head's CFrame relative to the root for a set of joint transforms
-- (missing joints are at rest). Part1 = Part0 * C0 * Transform * C1^-1.
function ObserverRig.headFromRoot(motors: { [string]: Motor6D }, transforms: { [string]: CFrame }): CFrame
	local cf = CFrame.identity
	for _, name in HEAD_CHAIN do
		local m = motors[name]
		if m then
			cf = cf * m.C0 * (transforms[name] or CFrame.identity) * m.C1:Inverse()
		end
	end
	return cf
end

--[[
	Where to put the root so that the face (FaceAnchor) sits exactly at
	`facePoint` and looks horizontally at `camPos`, for the given pose. The
	root only turns about Y (the body stays upright); the pose decides how
	level the face is (ScarePose keeps it level). Used by every jumpscare so
	the face can never end up behind the camera, off screen or turned away.
]]
function ObserverRig.placeFace(motors: { [string]: Motor6D }, transforms: { [string]: CFrame }, facePoint: Vector3, camPos: Vector3): CFrame
	local h = ObserverRig.headFromRoot(motors, transforms) * ObserverRig.FaceAnchor
	local f = h.LookVector
	local faceYaw = math.atan2(-f.X, -f.Z)
	local d = camPos - facePoint
	local wantYaw = if Vector3.new(d.X, 0, d.Z).Magnitude > 1e-3 then math.atan2(-d.X, -d.Z) else faceYaw
	local turn = CFrame.Angles(0, wantYaw - faceYaw, 0)
	return CFrame.new(facePoint - turn:VectorToWorldSpace(h.Position)) * turn
end

-- World CFrames of every part for a root CFrame and joint transforms, from
-- the joints and the welds' rest offsets (no physics needed).
function ObserverRig.solve(model: Model, rootCf: CFrame, transforms: { [string]: CFrame }): { [BasePart]: CFrame }
	local world: { [BasePart]: CFrame } = {}
	local root = model.PrimaryPart :: BasePart
	world[root] = rootCf
	local motors, welds = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(motors, d)
		elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
			table.insert(welds, d)
		end
	end
	local progress = true
	while progress do
		progress = false
		for _, m in motors do
			local p0, p1 = m.Part0 :: BasePart, m.Part1 :: BasePart
			if world[p0] and not world[p1] then
				world[p1] = world[p0] * m.C0 * (transforms[m.Name] or CFrame.identity) * m.C1:Inverse()
				progress = true
			end
		end
		for _, w in welds do
			local p0, p1 = w.Part0 :: BasePart, w.Part1 :: BasePart
			local rest = p1:GetAttribute("RestOffset")
			if world[p0] and not world[p1] and typeof(rest) == "CFrame" then
				world[p1] = world[p0] * rest
				progress = true
			end
		end
	end
	return world
end

local function lerpPose(a: { [string]: CFrame }, b: { [string]: CFrame }, t: number): { [string]: CFrame }
	local out = {}
	for k, v in a do
		out[k] = v:Lerp(b[k] or CFrame.identity, t)
	end
	for k, v in b do
		if not out[k] then
			out[k] = CFrame.identity:Lerp(v, t)
		end
	end
	return out
end

--[[
	The jumpscare pose, blended by `a` (0 = standing, head tilted; 1 = folded
	down to eye level, leaning in, arms spread wide around the camera) and
	`open` (0..1, the face parting). Joint frames: +X rotation tips a part
	BACK (+Z is behind the creature), so leaning toward the camera is a
	negative pitch, while a hanging limb swings FORWARD with a positive one
	(arms reach with +X, knees bend with -X). The net pitch of waist + neck + head cancels the head's
	built-in -8 degrees, so the face is level: it looks straight into the lens.
]]
local STAND = {
	HeadJoint = CFrame.Angles(0, 0, math.rad(14)),
	Waist = CFrame.Angles(math.rad(-4), 0, 0),
}
local LUNGE = {
	RootJoint = CFrame.new(0, -3.1, 0),
	Waist = CFrame.Angles(math.rad(-16), 0, 0),
	NeckJoint = CFrame.Angles(math.rad(14), 0, 0),
	HeadJoint = CFrame.Angles(math.rad(10), 0, math.rad(12)),
	-- arms forward and wide: the hands frame the face, never cover it
	LeftShoulder = CFrame.Angles(math.rad(58), 0, math.rad(-48)),
	RightShoulder = CFrame.Angles(math.rad(58), 0, math.rad(48)),
	LeftElbow = CFrame.Angles(math.rad(34), 0, 0),
	RightElbow = CFrame.Angles(math.rad(34), 0, 0),
	-- crouched: thighs forward (+X swings a hanging limb forward), shins back
	LeftHip = CFrame.Angles(math.rad(50), 0, 0),
	RightHip = CFrame.Angles(math.rad(50), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-80), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-80), 0, 0),
}

-- How wide the face halves swing open (degrees) at open = 1.
ObserverRig.FaceOpenAngle = 34

-- Jaw transforms for the face opening (0 = closed .. 1 = wide open). Each
-- half turns about its outer hinge so its inner edge swings back into the
-- skull: the seam becomes a gap and the maw shows straight ahead.
function ObserverRig.faceOpen(open: number): { [string]: CFrame }
	local o = math.rad(math.clamp(open, 0, 1) * ObserverRig.FaceOpenAngle)
	return { JawL = CFrame.Angles(0, -o, 0), JawR = CFrame.Angles(0, o, 0) }
end

function ObserverRig.ScarePose(a: number, open: number?): { [string]: CFrame }
	local pose = lerpPose(STAND, LUNGE, math.clamp(a, 0, 1))
	for k, v in ObserverRig.faceOpen(open or 0) do
		pose[k] = v
	end
	return pose
end

-- Eye turn (EyeTurnL/R transforms) so both eyes look at `point`, clamped.
function ObserverRig.eyesAt(model: Model, motors: { [string]: Motor6D }, point: Vector3, maxDeg: number?): { [string]: CFrame }
	local out = {}
	local limit = math.rad(maxDeg or 35)
	for _, side in { "L", "R" } do
		local m = motors["EyeTurn" .. side]
		local half = m and m.Part0
		if m and half then
			-- the eye's rest frame in the world
			local rest = (half :: BasePart).CFrame * m.C0
			local rel = rest:PointToObjectSpace(point)
			local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -limit, limit)
			local pitch = math.clamp(math.atan2(rel.Y, math.sqrt(rel.X * rel.X + rel.Z * rel.Z)), -limit, limit)
			out["EyeTurn" .. side] = CFrame.Angles(pitch, yaw, 0)
		end
	end
	return out
end

return ObserverRig
