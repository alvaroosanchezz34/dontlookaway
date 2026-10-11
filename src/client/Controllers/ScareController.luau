--[[
	ScareController
	Death cinematics and short scares, played with a LOCAL copy of The Observer
	framed exactly against your own camera (no network lag). The real,
	replicated Observer is hidden locally while a death cinematic runs. The
	server decides the catch (and the death, once); this only presents it.

	The rules (each one exists because the old version broke it):
	  * Instant. The frame the death arrives is already the hit: no false calm,
	    no turn, no warning. The server's warning inhale before a catch stays:
	    that is the game's fair rule, not part of the scare.
	  * The camera never moves. Same position, same orientation (looking at
	    the floor or the ceiling too), same field of view, no shake, no zoom,
	    the mouse does nothing. It is the one that moves: its face is put
	    right in front of wherever you were looking (ObserverRig.placeFace,
	    pitch included).
	  * Everything else is black on that same frame: every light that could
	    reach its face and your flashlight off, Lighting's ambient and
	    environment light at zero, no HUD, no other players, and a local box
	    of black Neon around the lens (black Neon stays black whatever light
	    hits it; it hides the sky and the emissive signs and screens of the
	    building). All of it comes back exactly as it was afterwards.
	  * Its face fills two thirds of the screen's height at your own field of
	    view (ObserverRig.scareDistance, from the measured head).
	  * One cold light on its head, low and to one side, with a short reach,
	    and the exposure up while its face is there: the lit half of the
	    charcoal face reads, the other half stays in the black. It breathes
	    slowly like a dying bulb, never strobes (steady with reduced effects).
	  * It moves, not you: dry jerks of the head and neck, pose jumps with no
	    interpolation, the eyes on you the whole time, a tilt no neck allows
	    held frozen for a moment, then in at you.
	  * No hitch: the local rig is built ahead of time and reused, a pose is
	    solved and moved in one go (Workspace:BulkMoveTo) only when it jumps,
	    and between jumps a frame only touches the light.
	  * Silence on the hit frame except the hit (ObserverImpact, ObserverScreech
	    and JumpSting together, loud, through their own group). Nothing else
	    sounds until the cut. Reduced effects never lowers the hit.
	  * 1.25-1.45 s of its face, then a hard cut to black, a ringing, a line.
	  * No glitch, red flash, blur or shake.
	The short scare (Flash) follows the same rules for half a second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local ScareController = {}

-- Measured on the hit frame of the last scare (tests, admin scare test).
ScareController.LastFrame = nil :: { [string]: any }?

local LINES = {
	behind = "It was behind you the whole time.",
	side = "You only looked away for a second.",
	front = "You blinked.",
	dark = "It doesn't need the light.",
	door = "Some doors should stay closed.",
	mirror = "The reflection was right.",
	mimic = "That wasn't %s.",
}

-- its face in front of you (the beat adds up to BEAT_HOLD), then black
local DEATH_HOLD = 1.25
local BEAT_HOLD = 0.2
local FLASH_HOLD = 0.5

-- The light on its head (head space: to its left and a little below, so it
-- rakes up one side of the face and the other half stays black). Chosen over
-- a light from straight below (only lights the jaw) and a plain side light
-- (loses the face) in tools/observer_shot.luau renders.
ScareController.Light = {
	offset = CFrame.new(-0.9, -0.4, -0.45),
	range = 4.5,
	brightness = 7,
	color = Color3.fromRGB(196, 212, 255),
}
-- the camera's exposure while its face is up: the lit half of a charcoal
-- face reads, and the black (nothing lit, the black Neon box) stays black
local SCARE_EXPOSURE = 1.3

-- half the size of the black box around the lens (its face is ~1 stud away)
local BOX = 3

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

--[[
	What it does, as poses held until the next key: no interpolation, every
	change is a jump. head / neck multiply onto ScarePose(1) (joint frames:
	-X pitch leans toward you, Z rolls in the plane of the face). A few
	deliberate jumps: fast flickering ones read as the game stuttering.
]]
type Key = { at: number, head: CFrame?, neck: CFrame? }
local DEATH_KEYS: { Key } = {
	{ at = 0 }, -- the hit: dead level, both eyes on you
	{ at = 0.15, head = deg(-6, 0, 26) }, -- a dry jerk to one side
	{ at = 0.27, neck = deg(0, 10, -16), head = deg(4, -8, -34) }, -- and the other, from the neck
	{ at = 0.4, neck = deg(0, 0, -18), head = deg(0, 0, 98) }, -- folded flat on its side, frozen
	{ at = 0.76, head = deg(-4, 0, 6) }, -- back, all at once
	{ at = 1.02, neck = deg(-14, 0, 0), head = deg(10, 0, -4) }, -- and in, at you
}
local FLASH_KEYS: { Key } = {
	{ at = 0 },
	{ at = 0.2, head = deg(-6, 0, 30) },
	{ at = 0.34, neck = deg(0, 0, -14), head = deg(0, 0, -24) },
}
ScareController.DeathKeys = DEATH_KEYS

local function reduced(): boolean
	return State.settings.reducedEffects == true
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

------------------------------------------------------------------------------------
-- Holding properties: set for the scare, given back exactly afterwards
------------------------------------------------------------------------------------

type Held = { inst: Instance, prop: string, value: any, saved: any }

local function hold(list: { Held }, inst: Instance, prop: string, value: any)
	local ok, current = pcall(function()
		return (inst :: any)[prop]
	end)
	if not ok then
		return
	end
	table.insert(list, { inst = inst, prop = prop, value = value, saved = current })
	pcall(function()
		(inst :: any)[prop] = value
	end)
end

-- Every frame: whatever someone else set meanwhile (a server tween of the
-- Lighting, a controller) is what comes back afterwards; ours goes back on.
local function enforce(list: { Held })
	for _, h in list do
		pcall(function()
			local inst = h.inst :: any
			if inst[h.prop] ~= h.value then
				h.saved = inst[h.prop]
				inst[h.prop] = h.value
			end
		end)
	end
end

local function release(list: { Held })
	for i = #list, 1, -1 do
		local h = list[i]
		pcall(function()
			(h.inst :: any)[h.prop] = h.saved
		end)
	end
	table.clear(list)
end

------------------------------------------------------------------------------------
-- The black
------------------------------------------------------------------------------------

-- Every light in the workspace, kept up to date from the start so the hit
-- frame never has to walk the whole map.
local lights: { [Light]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function track(d: Instance)
	if d:IsA("Light") then
		lights[d :: Light] = true
	end
end

local function darkPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Color = Color3.new(0, 0, 0)
	p.Material = Enum.Material.Neon
	p.Parent = parent
	return p
end

-- Six walls of black Neon around the lens.
local function blackBox(at: Vector3): Model
	local box = Instance.new("Model")
	box.Name = "ScareDark"
	local span = BOX * 2 + 0.4
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		local size = Vector3.new(span, span, span) - axis * (span - 0.2)
		for _, s in { -1, 1 } do
			darkPart("Wall", size, CFrame.new(at + axis * s * BOX), box)
		end
	end
	box.Parent = Workspace
	return box
end

--[[
	Turns everything but its face to black, locally, on this frame. Returns
	the held properties (enforce them every frame) and the function that
	gives everything back. `keep`: instances the scare itself owns.
]]
local function blackout(eye: Vector3, keep: { Instance }): ({ Held }, () -> ())
	local held: { Held } = {}
	local box: Model?, grade: ColorCorrectionEffect? = nil, nil
	local function undo()
		State.scareDark = false
		release(held)
		if box then
			box:Destroy()
		end
		if grade then
			grade:Destroy()
		end
		Registry.AudioController:ApplyVolumes()
	end
	local ok, err = pcall(function()
		local black = Color3.new(0, 0, 0)
		hold(held, Lighting, "Ambient", black)
		hold(held, Lighting, "OutdoorAmbient", black)
		hold(held, Lighting, "Brightness", 0)
		hold(held, Lighting, "EnvironmentDiffuseScale", 0)
		hold(held, Lighting, "EnvironmentSpecularScale", 0)
		hold(held, Lighting, "ExposureCompensation", SCARE_EXPOSURE)
		local effects = Lighting:GetChildren()
		local camera = Workspace.CurrentCamera
		if camera then
			for _, d in camera:GetChildren() do
				table.insert(effects, d)
			end
		end
		for _, d in effects do
			-- (the sky stays: the black box hides it, and swapping the sky
			-- makes the engine relight the whole environment, a hitch)
			if d:IsA("Atmosphere") then
				hold(held, d, "Density", 0)
			elseif d:IsA("ColorCorrectionEffect") or d:IsA("BlurEffect") or d:IsA("DepthOfFieldEffect") then
				-- grades lift the black (dark adaptation, the presets); no blur
				hold(held, d, "Enabled", false)
			end
		end
		-- every light that could reach its face (it is within a stud or two of
		-- the lens); the rest of the map is behind the black box anyway
		for light in lights do
			local ok, near = pcall(function()
				if not light:IsDescendantOf(Workspace) then
					return false
				end
				local holder = light.Parent
				local at = if holder and holder:IsA("BasePart")
					then holder.CFrame.Position
					elseif holder and holder:IsA("Attachment") then holder.WorldPosition
					else nil
				return at == nil or (at - eye).Magnitude < light.Range + BOX * 2
			end)
			if ok and near then
				hold(held, light, "Enabled", false)
			end
		end
		-- the HUD (the overlay stays: it carries the cut to black and the line)
		local localPlayer = Players.LocalPlayer
		local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			for _, g in playerGui:GetChildren() do
				if g:IsA("LayerCollector") and g.Name ~= "Overlay" then
					hold(held, g, "Enabled", false)
				end
			end
		end
		-- the others
		for _, p in Players:GetPlayers() do
			if p ~= localPlayer and p.Character then
				for _, d in p.Character:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						hold(held, d, "LocalTransparencyModifier", 1)
					elseif d:IsA("LayerCollector") then
						hold(held, d, "Enabled", false)
					end
				end
			end
		end
		-- a wall or a door right in front of the lens would stand between you and
		-- its face: whatever is inside the box goes (engine query: not in Lune)
		pcall(function()
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = table.clone(keep)
			if localPlayer and localPlayer.Character then
				table.insert(exclude, localPlayer.Character)
			end
			params.FilterDescendantsInstances = exclude
			for _, part in Workspace:GetPartBoundsInBox(CFrame.new(eye), Vector3.one * BOX * 2, params) do
				hold(held, part, "LocalTransparencyModifier", 1)
				for _, d in part:GetChildren() do
					if d:IsA("Decal") then
						hold(held, d, "LocalTransparencyModifier", 1)
					end
				end
			end
		end)
		box = blackBox(eye)
		-- the scare's own grade: cold, black stays black (no brightness, and no
		-- contrast: it would sink the dark skin into the black)
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "ScareGrade"
		g.Contrast = 0
		g.Saturation = -0.45
		g.TintColor = Color3.fromRGB(228, 236, 255)
		g.Parent = Lighting
		grade = g
		State.scareDark = true
		Registry.AudioController:ApplyVolumes()
	end)
	if not ok then
		-- whatever was already held goes back
		undo()
		error(err, 0)
	end
	return held, undo
end

------------------------------------------------------------------------------------
-- The rig
------------------------------------------------------------------------------------

local function setServerObserverHidden(hidden: boolean)
	for _, m in CollectionService:GetTagged("Observer") do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

--[[
	The local copy, posed by hand: every part anchored, the joints off, the
	CFrames solved from the pose (ObserverRig.solver) and moved in one go. It
	is built ahead of time and reused (parked outside the workspace between
	scares): building ~70 parts and 16 meshes on the hit frame was a hitch.
	The server adds the sculpted meshes to ReplicatedStorage.ObserverMeshes
	one at a time, so the rig is rebuilt (away from the hit) whenever more
	have arrived than it wears: a rig built with the first ones kept the
	part-built box for a head.
]]
type ScareRig = {
	model: Model,
	motors: { [string]: Motor6D },
	solve: (CFrame, { [string]: CFrame }) -> ({ BasePart }, { CFrame }),
	head: BasePart,
	lightPart: BasePart,
	light: PointLight,
	meshes: number, -- sculpted meshes available when it was built
}
local cachedRig: ScareRig? = nil

local function meshesAvailable(): number
	local folder = ReplicatedStorage:FindFirstChild("ObserverMeshes")
	return if folder then #folder:GetChildren() else 0
end

local function scareRig(): ScareRig
	local cached = cachedRig
	if cached and cached.model.Parent == nil and cached.meshes == meshesAvailable() then
		return cached
	end
	if cached and cached.model.Parent == nil then
		cached.model:Destroy()
	end
	local meshes = meshesAvailable()
	local rig = ObserverRig.build(CFrame.new(), { localCopy = true })
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = true
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d.Enabled = false
		end
	end
	local lightPart = darkPart("ScareLight", Vector3.new(0.1, 0.1, 0.1), CFrame.new(), rig)
	lightPart.Transparency = 1
	lightPart.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = ScareController.Light.range
	light.Color = ScareController.Light.color
	light.Shadows = true
	light.Parent = lightPart
	rig.Parent = nil
	local built: ScareRig = {
		model = rig,
		motors = ObserverRig.motors(rig),
		solve = ObserverRig.solver(rig),
		head = rig:FindFirstChild("Head") :: BasePart,
		lightPart = lightPart,
		light = light,
		meshes = meshes,
	}
	cachedRig = built
	return built
end

-- Moves the rig's parts in one call where the engine has it.
local canBulkMove = pcall(function()
	return (Workspace :: any).BulkMoveTo
end)
local function moveParts(parts: { BasePart }, cframes: { CFrame })
	if canBulkMove then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for i, part in parts do
			part.CFrame = cframes[i]
		end
	end
end

local function keyAt(keys: { Key }, t: number): Key
	local key = keys[1]
	for _, k in keys do
		if k.at <= t then
			key = k
		end
	end
	return key
end

-- The joint transforms of a key: ScarePose(1) with the key on top.
local function poseOf(base: { [string]: CFrame }, key: Key): { [string]: CFrame }
	local transforms = table.clone(base)
	if key.neck then
		transforms.NeckJoint = (base.NeckJoint or CFrame.identity) * key.neck
	end
	transforms.HeadJoint = (base.HeadJoint or CFrame.identity) * (key.head or CFrame.identity)
	return transforms
end

------------------------------------------------------------------------------------
-- Profiling (debug): Workspace attribute ScareProfile = true prints, after
-- each scare, how long every phase took and the worst frame during it
------------------------------------------------------------------------------------

type Profile = { on: boolean, marks: { { any } }, frames: number, dtSum: number, dtMax: number, enforceMax: number, frameMax: number, held: number, head: string }

local function newProfile(): Profile
	return { on = Workspace:GetAttribute("ScareProfile") == true, marks = {}, frames = 0, dtSum = 0, dtMax = 0, enforceMax = 0, frameMax = 0, held = 0, head = "?" }
end

local function mark(prof: Profile, label: string)
	if prof.on then
		table.insert(prof.marks, { label, os.clock() })
	end
end

local function report(prof: Profile, name: string)
	if not prof.on or #prof.marks == 0 then
		return
	end
	local parts = {}
	for i = 2, #prof.marks do
		table.insert(parts, string.format("%s %.1f ms", prof.marks[i][1], (prof.marks[i][2] - prof.marks[i - 1][2]) * 1000))
	end
	print(string.format("[ScareProfile] %s | head: %s | hit frame: %s | %d properties held", name, prof.head, table.concat(parts, ", "), prof.held))
	if prof.frames > 0 then
		print(string.format(
			"[ScareProfile] %s | %d frames, average %.1f ms, worst %.1f ms | per frame: enforce worst %.2f ms, pose worst %.2f ms",
			name,
			prof.frames,
			prof.dtSum / prof.frames * 1000,
			prof.dtMax * 1000,
			prof.enforceMax * 1000,
			prof.frameMax * 1000
		))
	end
end

------------------------------------------------------------------------------------
-- The scare
------------------------------------------------------------------------------------

local current: (() -> ())? = nil -- stops the scare on screen

function ScareController:IsActive(): boolean
	return current ~= nil
end

--[[
	Puts its face in front of the camera right now, on this frame, with the
	world gone black, and animates it by `keys`. The camera override `name`
	holds the view still (a death keeps it: DeathController lets go of it
	behind the black). Returns the function that ends it (idempotent): the
	rig and the light go, everything held comes back.
]]
local function present(name: string, keys: { Key }, seed: number, info: { [string]: any }): () -> ()
	if current then
		current()
	end
	local prof = newProfile()
	mark(prof, "start")
	local cam = Registry.CameraController
	local camera = Workspace.CurrentCamera
	local camCf = cam:GetCFrame()
	local fov = camera.FieldOfView
	local eye = camCf.Position
	local hadRig = cachedRig
	local sr = scareRig()
	mark(prof, if cachedRig == hadRig then "rig (cached)" else "rig (BUILT NOW)")
	prof.head = if sr.model:FindFirstChild("HeadMesh") then "sculpted mesh" else "PART-BUILT BOX"
	local rig, m, light = sr.model, sr.motors, sr.light
	local headPart = sr.head
	local base = ObserverRig.ScarePose(1, 0)
	local distance = ObserverRig.scareDistance(fov)
	local rootCf = ObserverRig.placeFace(m, base, eye + camCf.LookVector * distance, camCf)
	light.Range = ScareController.Light.range
	light.Color = ScareController.Light.color

	local held, restore
	local start = os.clock()
	local shown: Key? = nil
	local function frame()
		local t = os.clock() - start
		local key = keyAt(keys, t)
		if key ~= shown then
			-- a jump: the new pose, both eyes on you, the light on its head
			shown = key
			local transforms = poseOf(base, key)
			local headCf = rootCf * ObserverRig.headFromRoot(m, transforms)
			for k, v in ObserverRig.eyesAt(rig, m, eye, 40, headCf) do
				transforms[k] = v
			end
			moveParts(sr.solve(rootCf, transforms))
			sr.lightPart.CFrame = headCf * ScareController.Light.offset
		end
		-- a bulb that will not quite die: slow, uneven, never a strobe
		local breathe = if reduced() then 1 else 0.8 + 0.2 * math.clamp(0.5 + math.noise(t * 1.3, seed * 3.1), 0, 1)
		light.Brightness = ScareController.Light.brightness * breathe
	end
	local ok, err = pcall(function()
		held, restore = blackout(eye, { rig })
		mark(prof, "blackout")
		frame()
		mark(prof, "first pose")
	end)
	if not ok then
		if restore then
			restore()
		end
		cachedRig = nil
		rig:Destroy()
		error(err, 0)
	end
	rig.Parent = Workspace
	-- the camera stays exactly where it was: same place, same angle, same lens
	cam:SetOverride(name, 50, function()
		return camCf, fov
	end)
	mark(prof, "show")
	prof.held = #held

	-- what the player sees on the hit frame
	local anchor = headPart.CFrame * ObserverRig.FaceAnchor
	local toCam = eye - anchor.Position
	local frameInfo = {
		distance = toCam.Magnitude,
		expected = distance,
		facing = anchor.LookVector:Dot(toCam.Unit),
		centred = camCf.LookVector:Dot(-toCam.Unit),
		inFront = camCf:PointToObjectSpace(anchor.Position).Z < 0,
		impactAt = 0,
		camera = camCf,
		fov = fov,
	}
	for k, v in info do
		frameInfo[k] = v
	end
	ScareController.LastFrame = frameInfo

	local stopped = false
	local conn: RBXScriptConnection
	local function stop()
		if stopped then
			return
		end
		stopped = true
		if conn then
			conn:Disconnect()
		end
		restore()
		-- parked for the next scare
		rig.Parent = nil
		report(prof, name)
		if name ~= "Death" then
			cam:ClearOverride(name)
		end
		if current == stop then
			current = nil
		end
	end
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if stopped then
			return
		end
		local t0 = os.clock()
		enforce(held)
		local t1 = os.clock()
		local ok, err = pcall(frame)
		if prof.on then
			prof.frames += 1
			prof.dtSum += dt
			prof.dtMax = math.max(prof.dtMax, dt)
			prof.enforceMax = math.max(prof.enforceMax, t1 - t0)
			prof.frameMax = math.max(prof.frameMax, os.clock() - t1)
		end
		if not ok then
			warn("[ScareController] " .. tostring(err))
			stop()
		end
	end)
	current = stop
	return stop
end

-- The hit: silence and these three, loud, together.
local function hit(keys: { string })
	for _, key in keys do
		Registry.AudioController:Play(key, nil, { volume = 1.3, hit = true })
	end
end

--[[
	Plays the death cinematic. payload: variant (picks the last line), beat
	(0..1: how long its face stays), position, mimicName, test; the server's
	`sequence` is only echoed in the report. Calls `done()` once the screen
	is black.
]]
function ScareController:Death(payload, done: () -> ())
	local fx = Registry.EffectsController
	local audio = Registry.AudioController
	local variant = payload.variant or "behind"
	local beat = math.clamp(tonumber(payload.beat) or 0.5, 0, 1)
	setServerObserverHidden(true)
	local stop = present("Death", DEATH_KEYS, beat * 10 + 1, { variant = variant, sequence = payload.sequence })
	hit({ "ObserverImpact", "ObserverScreech", "JumpSting" })

	-- a hard cut to black, a ringing, a line
	task.delay(DEATH_HOLD + BEAT_HOLD * beat, function()
		fx:Fade(1, 0)
		-- the world comes back behind the black
		task.delay(0.1, function()
			stop()
			setServerObserverHidden(false)
			audio:Silence(2.2)
			audio:Play("TinnitusRing", nil, { volume = 0.8 })
		end)
		if not payload.test then
			task.delay(0.9, function()
				local line = LINES[variant] or "The building took you."
				if variant == "mimic" then
					line = string.format(line, payload.mimicName or "them")
				end
				fx:Title("YOU WERE TAKEN", line, 3, Kit.F.Title)
			end)
		end
		done()
	end)
end

-- A short, non-lethal scare: its face, right there, for half a second, by
-- the same rules as the death.
function ScareController:Flash(_kind: string?)
	if current then
		return
	end
	local stop = present("Scare", FLASH_KEYS, math.random() * 10, { variant = "flash" })
	hit({ "ObserverImpact", "JumpSting" })
	task.delay(FLASH_HOLD, stop)
end

------------------------------------------------------------------------------------
-- The mimic's lunge (unchanged: its own face, not The Observer's)
------------------------------------------------------------------------------------

type ScareLight = { holder: Part, spot: SpotLight, underPart: Part, under: PointLight, alive: boolean }

local function lightPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = Workspace
	return p
end

local function makeScareLight(): ScareLight
	local holder = lightPart("ScareLight")
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 18
	spot.Brightness = 0
	spot.Color = Color3.fromRGB(226, 234, 255)
	spot.Shadows = true
	spot.Parent = holder
	local underPart = lightPart("ScareUnderLight")
	local under = Instance.new("PointLight")
	under.Range = 7
	under.Brightness = 0
	under.Color = Color3.fromRGB(255, 206, 180)
	under.Shadows = false
	under.Parent = underPart
	return { holder = holder, spot = spot, underPart = underPart, under = under, alive = true }
end

-- Aim the light from the camera at the face; `level` 0 = off.
local function aimScareLight(light: ScareLight, camPos: Vector3, face: Vector3, level: number)
	if not light.alive then
		return
	end
	local dir = face - camPos
	local back = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	light.holder.CFrame = CFrame.lookAt(camPos - back * 0.4, face)
	light.underPart.Position = face - Vector3.new(0, 1.8, 0) - back * 0.6
	light.spot.Brightness = 2.2 * level
	light.under.Brightness = 0.5 * level
end

local function destroyScareLight(light: ScareLight)
	light.alive = false
	light.holder:Destroy()
	light.underPart:Destroy()
end

-- The mimic lunges (non-lethal): the view snaps to ITS face, wrong and too
-- close, lit from the camera, for a moment. `model` is the replicated mimic.
function ScareController:MimicLunge(model: Model)
	if current then
		return
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		self:Flash("mimic")
		return
	end
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local start = os.clock()
	local eye = cam:GetCFrame().Position
	local light = makeScareLight()
	cam:SetOverride("MimicLunge", 45, function()
		local t = os.clock() - start
		local face = if head.Parent then head.Position else eye + cam:GetCFrame().LookVector * 3
		aimScareLight(light, eye, face, if t < 0.05 then 1 else 0.9)
		return CFrame.lookAt(eye, face), 70 - 22 * ease(t / 0.12)
	end)
	cam:Shake(if reduced() then 0.2 else 0.5)
	fx:Glitch(if reduced() then 0.08 else 0.2, 0.15)
	Registry.AudioController:Play("JumpSting", nil, { volume = 1 })
	task.delay(0.7, function()
		cam:ClearOverride("MimicLunge")
		destroyScareLight(light)
	end)
end

function ScareController:Start()
	for _, d in Workspace:GetDescendants() do
		track(d)
	end
	Workspace.DescendantAdded:Connect(track)
	-- the rig is ready long before anyone is caught, and again once the
	-- sculpted meshes arrive (the server loads them after start)
	task.defer(scareRig)
	local function watch(folder: Instance)
		if folder.Name == "ObserverMeshes" then
			folder.ChildAdded:Connect(function()
				task.defer(scareRig)
			end)
			task.defer(scareRig)
		end
	end
	for _, c in ReplicatedStorage:GetChildren() do
		watch(c)
	end
	ReplicatedStorage.ChildAdded:Connect(watch)
end

return ScareController
