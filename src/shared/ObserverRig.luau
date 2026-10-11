--[[
	ObserverRig
	Builds THE OBSERVER, after the reference silhouette: a black figure,
	extremely tall and thin, with
	  * a head that is a wide horizontal blade (about 4.6 studs, two and a half
	    times its shoulders): the top edge almost straight, the lower edge
	    rising to a point at each end, and a narrow point in the middle that
	    runs down into the neck
	  * two small pale eyes with dark pupils, close to the middle, that turn to
	    whoever it is watching
	  * a long thin neck, sloping angular shoulders, a narrow torso with no
	    anatomy
	  * arms far too long, hanging to the middle of the shins, plain hands
	  * long straight legs
	  * a uniform matte black that swallows light: no clothes, no ribs, no
	    teeth, no shine. It is frightening by its shape and its stillness.
	The eyes are the only light thing on it; they are a dim self-lit grey (not
	a glow) so they read in the dark, as in the reference.

	Parts and Motor6D joints keep the names every system uses (RootJoint,
	Waist, NeckJoint, HeadJoint, shoulders, elbows, wrists, hips, knees,
	ankles, EyeTurnL/R), so the server pathing, ObserverFX, the jumpscare and
	the marketing figures work unchanged. It carries a Humanoid so the server
	can path it through the map. Shared so clients can build a local copy for
	death cinematics, framed exactly against their own camera.
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
-- Part-built pieces the smooth meshes replace (fused into Head / UpperTorso).
local MESH_DETAILS = { WingL = true, WingR = true, Chin = true, Flank = true, ShoulderPlate = true }

local TEMPLATE_FOLDER = "ObserverMeshes"

-- (exposed for offline renders: tools/observer_shot.luau)
ObserverRig.SegmentMesh = SEGMENT_MESH
ObserverRig.MeshDetails = MESH_DETAILS

-- matte, near-black: it absorbs light (SmoothPlastic, no reflectance)
local SKIN = Color3.fromRGB(9, 9, 10)
-- the eyes: a pale grey that is self-lit but dim (no bloom, no halo)
local EYE = Color3.fromRGB(104, 102, 96)
local PUPIL = Color3.fromRGB(2, 2, 2)

-- The smooth body (tools/blender/build_observer.py): one flowing mesh per
-- segment, welded over the rig parts once uploaded. Until then the
-- part-built body below is the fallback (same silhouette, hard edges).
ObserverRig.UseSculptedBody = true

ObserverRig.Height = 9.6

-- Eye centres in head space (must match EYE_L / EYE_R in
-- tools/blender/build_observer.py: the sockets are carved around them).
ObserverRig.EyeOffsets = {
	L = CFrame.new(-0.19, 0.12, -0.23),
	R = CFrame.new(0.21, 0.05, -0.22),
}
ObserverRig.HipHeight = 4.0

local function part(model, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or SKIN
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = 0
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

-- A wedge from its world axes: the wedge's thin edge is at its local -Z,
-- its full height at +Z; `along` points from the full end to the thin tip.
local function wedge(model, name, height: number, length: number, depth: number, centre: CFrame, along: Vector3, up: Vector3)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = Vector3.new(depth, height, length)
	local z = -along.Unit
	local y = up.Unit
	local x = y:Cross(z)
	w.CFrame = CFrame.fromMatrix(centre.Position, centre:VectorToWorldSpace(x), centre:VectorToWorldSpace(y), centre:VectorToWorldSpace(z))
	w.Color = SKIN
	w.Material = Enum.Material.SmoothPlastic
	w.Reflectance = 0
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Massless = true
	w.CastShadow = true
	w.Parent = model
	return w
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

	-- feet at y = 0, front is -Z; hips at 4.6, shoulders at 7.35, the head's
	-- blade at 9.05
	local hipY = 4.6
	local lowerTorso = part(model, "LowerTorso", Vector3.new(0.85, 0.8, 0.45), at(0, hipY + 0.3, 0))
	-- the torso: narrow at the waist, widening into sloped, angular shoulders
	-- (a core plus two flank wedges that taper to nothing at the waist)
	local upperTorso = part(model, "UpperTorso", Vector3.new(0.86, 2.3, 0.46), at(0, hipY + 1.85, 0))
	for _, s in { -1, 1 } do
		local flank = wedge(model, "Flank", 0.34, 2.0, 0.44, upperTorso.CFrame * CFrame.new(s * (0.43 + 0.17), 0.15, 0), Vector3.new(0, -1, 0), Vector3.new(s, 0, 0))
		weld(upperTorso, flank)
		-- the shoulder slopes down from the neck to the top of the arm
		local shoulder = part(model, "ShoulderPlate", Vector3.new(0.9, 0.36, 0.44), at(s * 0.68, 7.4, 0, 0, 0, -s * 19))
		weld(upperTorso, shoulder)
	end
	local neck = part(model, "Neck", Vector3.new(0.3, 1.0, 0.3), at(0, 8.05, 0))
	local head = part(model, "Head", Vector3.new(0.7, 0.62, 0.5), at(0, 9.0, 0))

	-- the blade of the head: two tapering wings, each an upper wedge (low, so
	-- the top edge stays almost straight) and a lower wedge (deep, so the
	-- lower edge rises to the tip)
	local bladeY = 9.08
	local wingLen = 2.0
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		local along = Vector3.new(s, 0, 0)
		local midX = s * (0.3 + wingLen / 2)
		local upper = wedge(model, "Wing" .. side, 0.2, wingLen, 0.42, head.CFrame * CFrame.new(midX, bladeY - 9.0 + 0.1, 0), along, Vector3.new(0, 1, 0))
		weld(head, upper)
		local lower = wedge(model, "Wing" .. side, 0.5, wingLen, 0.42, head.CFrame * CFrame.new(midX, bladeY - 9.0 - 0.25, 0), along, Vector3.new(0, -1, 0))
		weld(head, lower)
	end
	-- the narrow point under the middle of the head, running into the neck
	local chin = part(model, "Chin", Vector3.new(0.5, 0.5, 0.42), head.CFrame * CFrame.new(0, -0.42, 0) * CFrame.Angles(0, 0, math.rad(45)))
	weld(head, chin)

	-- two small pale eyes with dark pupils, a little above the blade's line,
	-- close to the middle; they turn (EyeTurnL / EyeTurnR)
	for _, s in { -1, 1 } do
		local side = if s < 0 then "L" else "R"
		-- asymmetric: the left eye sits higher and a little smaller, each in
		-- its own deep socket (carved in the sculpted head)
		local eyeAt = head.CFrame * ObserverRig.EyeOffsets[side]
		local d = if side == "L" then 0.105 else 0.115
		local ball = part(model, "Eyeball" .. side, Vector3.new(d, d, d), eyeAt, EYE, Enum.Material.Neon)
		ball.Shape = Enum.PartType.Ball
		ball.CastShadow = false
		motor("EyeTurn" .. side, head, ball, eyeAt)
		local pupil = ellipsoid(model, "Pupil", Vector3.new(d * 0.58, d * 0.64, 0.025), ball.CFrame * CFrame.new(0, d * 0.05, -d * 0.44), PUPIL)
		pupil.CastShadow = false
		weld(ball, pupil)
	end

	motor("RootJoint", root, lowerTorso, at(0, hipY + 0.3, 0))
	motor("Waist", lowerTorso, upperTorso, at(0, hipY + 0.7, 0))
	motor("NeckJoint", upperTorso, neck, at(0, 7.6, 0))
	motor("HeadJoint", neck, head, at(0, 8.55, 0))

	for _, s in { -1, 1 } do
		local side = if s < 0 then "Left" else "Right"
		-- arms: far too long, hanging to the middle of the shins
		local sx = s * 1.1
		local upperArm = part(model, side .. "UpperArm", Vector3.new(0.28, 2.9, 0.28), at(sx, 7.35 - 1.45, 0))
		local lowerArm = part(model, side .. "LowerArm", Vector3.new(0.24, 2.6, 0.24), at(sx + s * 0.03, 4.45 - 1.3, 0))
		local hand = part(model, side .. "Hand", Vector3.new(0.2, 0.6, 0.13), at(sx + s * 0.04, 1.85 - 0.3, 0))
		motor(side .. "Shoulder", upperTorso, upperArm, at(sx, 7.35, 0))
		motor(side .. "Elbow", upperArm, lowerArm, at(sx + s * 0.02, 4.45, 0))
		motor(side .. "Wrist", lowerArm, hand, at(sx + s * 0.04, 1.85, 0))
		-- legs: long and straight
		local lx = s * 0.27
		local upperLeg = part(model, side .. "UpperLeg", Vector3.new(0.36, 2.3, 0.36), at(lx, hipY - 1.15, 0))
		local lowerLeg = part(model, side .. "LowerLeg", Vector3.new(0.3, 2.1, 0.3), at(lx, 2.3 - 1.05, 0))
		local foot = part(model, side .. "Foot", Vector3.new(0.3, 0.2, 0.75), at(lx, 0.1, -0.15))
		motor(side .. "Hip", lowerTorso, upperLeg, at(lx, hipY, 0))
		motor(side .. "Knee", upperLeg, lowerLeg, at(lx, 2.3, 0))
		motor(side .. "Ankle", lowerLeg, foot, at(lx, 0.2, 0))
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
	if not ObserverRig.UseSculptedBody then
		return false
	end
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not folder or #folder:GetChildren() == 0 or model:GetAttribute("Sculpted") then
		return false
	end
	local dressed = false
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
		end
	end
	if dressed then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and MESH_DETAILS[p.Name] then
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
	if not ObserverRig.UseSculptedBody then
		return 0
	end
	local n = #(AssetIds.Observer.pool or {})
	for meshName in MeshMeta do
		if AssetIds.url(AssetIds.Observer.meshes[meshName]) or AssetIds.url(AssetIds.Observer.models[meshName]) then
			n += 1
		end
	end
	return n
end

-- The segment's baked skin (src/shared/ObserverSkins, written by
-- tools/sync_assets.py: scripts may not set SurfaceAppearance maps).
local function applySkin(mesh: BasePart, meshName: string)
	mesh.Color = SKIN
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Reflectance = 0
	mesh.CastShadow = true
	local skins = script.Parent:FindFirstChild("ObserverSkins")
	local skin = skins and skins:FindFirstChild(meshName)
	if skin and not mesh:FindFirstChildWhichIsA("SurfaceAppearance") then
		skin:Clone().Parent = mesh
	end
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
				return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri(meshUrl :: string), {
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
				for _, d in mesh:GetChildren() do
					d:Destroy()
				end
				applySkin(mesh, meshName)
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
	-- unnamed uploads (Studio may call every mesh "default"): recognised by
	-- their exact size (the upper and lower arm share proportions, so shape
	-- alone cannot tell them apart; Studio keeps OBJ studs as they are)
	local taken = {}
	if folder then
		for _, t in (folder :: Folder):GetChildren() do
			taken[t.Name] = true
		end
	end
	for _, id in AssetIds.Observer.pool or {} do
		local ok, mesh = pcall(function()
			return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. string.format("%d", id)), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
		end)
		if ok and mesh then
			local okSize, native = pcall(function()
				return mesh.MeshSize
			end)
			local size = if okSize and typeof(native) == "Vector3" and native.Magnitude > 0 then native else mesh.Size
			local best, bestD = nil, 0.06
			for meshName, meta in MeshMeta do
				local d = (size - meta.size).Magnitude
				if not taken[meshName] and d < bestD then
					best, bestD = meshName, d
				end
			end
			if best then
				taken[best] = true
				print(string.format("[ObserverRig] mesh %d -> %s (size difference %.3f)", id, best, bestD))
				for _, d in mesh:GetChildren() do
					d:Destroy()
				end
				mesh.Name = best
				mesh.Size = MeshMeta[best].size
				applySkin(mesh, best)
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = TEMPLATE_FOLDER
					folder.Parent = ReplicatedStorage
				end
				mesh.Parent = folder
				loaded += 1
			else
				warn(string.format("[ObserverRig] mesh %d (size %.2f x %.2f x %.2f) matches no Observer segment", id, size.X, size.Y, size.Z))
				mesh:Destroy()
			end
		else
			warn("[ObserverRig] could not load mesh " .. tostring(id) .. ": " .. tostring(mesh))
		end
	end
	return loaded
end

------------------------------------------------------------------------------------
-- Posing without physics (cinematic framing, tests, offline renders)
------------------------------------------------------------------------------------

-- Between the eyes, on the face: what a jumpscare frames (head space).
ObserverRig.FaceAnchor = CFrame.new(0, 0.08, -0.3)

-- The jumpscare frames the whole head: its face this far from the lens, with
-- this vertical field of view (the 4.6-stud blade fits across the screen).
ObserverRig.ScareDistance = 3.0
ObserverRig.ScareFov = 62

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
	Waist = CFrame.Angles(math.rad(-3), 0, 0),
}
local LUNGE = {
	-- folded down to eye level, leaning in; waist + neck + head pitch sum to
	-- zero, so the face is level and looks straight into the lens
	RootJoint = CFrame.new(0, -3.1, 0),
	Waist = CFrame.Angles(math.rad(-16), 0, 0),
	NeckJoint = CFrame.Angles(math.rad(12), 0, 0),
	HeadJoint = CFrame.Angles(math.rad(4), 0, math.rad(9)),
	-- the long arms come up and open wide around you: the hands frame the
	-- head, never cover it
	LeftShoulder = CFrame.Angles(math.rad(34), 0, math.rad(-74)),
	RightShoulder = CFrame.Angles(math.rad(34), 0, math.rad(74)),
	LeftElbow = CFrame.Angles(math.rad(22), 0, 0),
	RightElbow = CFrame.Angles(math.rad(22), 0, 0),
	-- crouched: thighs forward (+X swings a hanging limb forward), shins back
	LeftHip = CFrame.Angles(math.rad(50), 0, 0),
	RightHip = CFrame.Angles(math.rad(50), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-80), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-80), 0, 0),
}

-- (kept for callers: the reference design has no opening face)
ObserverRig.FaceOpenAngle = 0

function ObserverRig.faceOpen(_open: number): { [string]: CFrame }
	return {}
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
