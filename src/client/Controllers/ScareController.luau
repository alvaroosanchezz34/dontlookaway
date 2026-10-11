--[[
	ScareController
	Death cinematics and short scares, played with a LOCAL copy of The Observer
	so it is framed exactly against your own camera (no network lag, no clipping
	into walls you cannot see). The real, replicated Observer is hidden locally
	while a cinematic runs. The server decides the catch (and the death, once);
	this only presents it.

	Why the old one was predictable: every catch had the same grammar and the
	same timing - the sound cut out on the first frame (the tell), the camera
	whipped round, it lunged in 0.2 s, hit. You learned it after two deaths.

	Now each catch is a SEQUENCE with phases, chosen by the server from the
	situation, with its rhythm varied by a server-sent `beat` (0..1):
	  A  false resolution: you turn and there is nothing; the corridor is
	     quiet; it stands far away and does nothing
	  B  rupture: the lights die, something at the edge of the frame, a
	     shape coming down from above - short, and never the same
	  C  impact: its face, lit, three studs from the lens, level, both small
	     eyes on you (placed by ObserverRig.placeFace: always centred, always
	     facing you). It holds there; its head tilts, slowly. Then it pushes
	     in, once, with the scream
	  D  resolution: a hard cut to black, a ringing, a line
	Sequences
	  turn       (behind / side) you turn to it: nothing. A breath. As you
	             turn back, it is already in front of you
	  stillness  (front) it stands ahead, perfectly still, its head tilting;
	             then, without moving, it is at your face
	  drop       (front, other rhythm) nothing ahead... its face comes down
	             into the frame from above
	  lightsout  (dark) the light dies; two small eyes far off; the light
	             returns on nothing; it rises into your face from below
	  peek       (door) half its head leans into the edge of the frame and
	             withdraws; it comes from the other side
	  mirror     you see it in the mirror first, then you turn around
	  mimic      a teammate with their back to you turns their head all the
	             way round; it is not them
	The sound never announces the impact: the world keeps playing through the
	false resolution and only drops at the hit itself. The shake and effects
	are small so they never hide the face. Reduced effects softens motion and
	removes flicker.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local ScareController = {}

-- Measured at the impact of the last death cinematic (tests, admin scare test).
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

local active = false

-- impact timing (seconds)
local IMPACT_HOLD = 0.55 -- its face, lit, held: long enough to see it
local PUSH = 0.12 -- then it pushes in, once
local PUSH_DIST = 1.9 -- to this distance from the lens
local AFTER = 0.3 -- held after the push, then black
local FRAME_DIST = ObserverRig.ScareDistance -- studs from the lens to its face at the impact
local FRAME_FOV = ObserverRig.ScareFov -- the whole blade of its head fits across the screen
local SPOT = 2.2 -- the scare light at full strength: enough to read the head
-- and its eyes, low enough that the black stays black
local UNDER = 0.5

--[[
	The scare light: off until the exact frame of the impact, then a hard cold
	spot from the camera onto its face plus a low warm point light under its
	jaw. Purely local (the rig is local too), so it always reads, whatever the
	building's lights are doing.
]]
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
	light.spot.Brightness = SPOT * level
	light.under.Brightness = UNDER * level
end

local function destroyScareLight(light: ScareLight)
	light.alive = false
	light.holder:Destroy()
	light.underPart:Destroy()
end

local function reduced(): boolean
	return State.settings.reducedEffects == true
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function motors(model: Model): { [string]: Motor6D }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			list[d.Name] = d
		end
	end
	return list
end

local function setServerObserverHidden(hidden: boolean)
	for _, m in CollectionService:GetTagged("Observer") do
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

-- Builds the local rig standing on the floor at `feet`, facing `toward`.
local function spawnRig(feet: Vector3, toward: Vector3): (Model, { [string]: Motor6D })
	local flat = Vector3.new(toward.X - feet.X, 0, toward.Z - feet.Z)
	local face = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local rig = ObserverRig.build(CFrame.lookAt(feet, feet + face), { localCopy = true })
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") and d ~= rig.PrimaryPart then
			d.Anchored = false
		end
	end
	rig.Parent = Workspace
	return rig, motors(rig)
end

local function moveRig(rig: Model, feet: Vector3, toward: Vector3)
	local flat = Vector3.new(toward.X - feet.X, 0, toward.Z - feet.Z)
	local face = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	rig:PivotTo(CFrame.lookAt(feet, feet + face) * CFrame.new(0, ObserverRig.HipHeight + 1, 0))
end

-- Applies a pose (joint name -> transform); joints not named go to rest.
local function applyPose(m: { [string]: Motor6D }, transforms: { [string]: CFrame })
	for name, motor in m do
		motor.Transform = transforms[name] or CFrame.identity
	end
end

-- The pose for this frame, with both eyes turned to the camera.
local function scarePose(rig: Model, m: { [string]: Motor6D }, a: number, open: number, camPos: Vector3, extra: { [string]: CFrame }?)
	local transforms = ObserverRig.ScarePose(a, open)
	for k, v in ObserverRig.eyesAt(rig, m, camPos, 40) do
		transforms[k] = v
	end
	if extra then
		for k, v in extra do
			transforms[k] = (transforms[k] or CFrame.identity) * v
		end
	end
	return transforms
end

-- A local, frozen copy of a teammate's character for the mimic variant.
local function cloneTeammate(userId: number?): Model?
	local okP, p = pcall(function()
		return if userId then Players:GetPlayerByUserId(userId) else nil
	end)
	local character = okP and p and p.Character
	if not character then
		return nil
	end
	local ok, copy = pcall(function()
		character.Archivable = true
		return character:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.PlatformStand = true
	end
	return copy
end

function ScareController:IsActive(): boolean
	return active
end

-- The sequence for a variant when the server did not name one.
local DEFAULT_SEQUENCE = {
	behind = "turn",
	side = "turn",
	front = "stillness",
	dark = "lightsout",
	door = "peek",
	mirror = "mirror",
	mimic = "mimic",
}
ScareController.Sequences = { "turn", "stillness", "drop", "lightsout", "peek", "mirror", "mimic" }

-- Shows all of the local rig, none of it, or only its two eyes.
local function setRigVisible(rig: Model, mode: string)
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			local eyePart = string.find(d.Name, "Eyeball") ~= nil or d.Name == "Pupil"
			d.LocalTransparencyModifier = if mode == "all" or (mode == "eyes" and eyePart) then 0 else 1
		end
	end
end

local function yawOf(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function dirOfYaw(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Turns from yaw a toward yaw b by the shortest way, t in 0..1.
local function lerpYaw(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

--[[
	Plays the death cinematic. payload: variant, position (victim root),
	sequence (optional; else DEFAULT_SEQUENCE[variant]), beat (0..1: the
	rhythm of this catch), and variant context (door, mirror, side,
	mimicUserId, mimicName). Calls `done()` once the screen is black.
]]
function ScareController:Death(payload, done: () -> ())
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local audio = Registry.AudioController
	local variant = payload.variant or "behind"
	local sequence = if type(payload.sequence) == "string" and table.find(ScareController.Sequences, payload.sequence) then payload.sequence else (DEFAULT_SEQUENCE[variant] or "turn")
	local beat = math.clamp(tonumber(payload.beat) or 0.5, 0, 1)
	active = true
	local start = os.clock()
	local from = cam:GetCFrame()
	local eye = from.Position
	local flatLook = Util.flat(from.LookVector)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local floorY = if typeof(payload.position) == "Vector3" then payload.position.Y - 3 else eye.Y - 4.5
	local sideSign = if payload.side == -1 then -1 else 1
	local function feetAt(p: Vector3): Vector3
		return Vector3.new(p.X, floorY, p.Z)
	end
	setServerObserverHidden(true)

	-- where it came from (the turn) and where it will be (the impact)
	local forwardYaw = yawOf(flatLook)
	local turnDir = flatLook
	if variant == "behind" or variant == "mirror" then
		turnDir = -flatLook
	elseif variant == "side" then
		turnDir = right * sideSign
	elseif variant == "door" and typeof(payload.door) == "Vector3" then
		local to = Util.flat(payload.door - eye)
		if to.Magnitude > 0.01 then
			turnDir = to.Unit
		end
	end
	local turnYaw = yawOf(turnDir)

	-- the timeline of this sequence: when the impact comes, and what happens before
	local impactAt: number
	local T = {}
	if sequence == "turn" then
		T.turn = 0.42
		T.hold = 0.45 + 0.6 * beat
		T.back = 0.22
		-- it is there before the turn back is even finished
		impactAt = T.turn + T.hold + T.back * 0.55
	elseif sequence == "stillness" then
		T.hold = 0.9 + 0.8 * beat
		impactAt = T.hold
	elseif sequence == "drop" then
		T.hold = 0.45 + 0.5 * beat
		T.move = 0.16
		impactAt = T.hold + T.move
	elseif sequence == "lightsout" then
		T.dark = 0.55 + 0.45 * beat
		T.calm = 0.35 + 0.35 * beat
		T.move = 0.14
		impactAt = T.dark + T.calm + T.move
	elseif sequence == "peek" then
		T.peek = 0.45
		T.hold = 0.4 + 0.5 * beat
		T.move = 0.12
		impactAt = T.peek + T.hold + T.move
	elseif sequence == "mirror" then
		T.glimpse = 0.5
		T.turn = 0.16
		impactAt = T.glimpse + T.turn
	else -- mimic
		T.turn = 0.55
		impactAt = T.turn
	end

	-- where the impact is: straight ahead of where the camera will be looking
	local impactYaw = forwardYaw
	if sequence == "turn" then
		impactYaw = lerpYaw(turnYaw, forwardYaw, 0.55)
	elseif sequence == "mirror" then
		impactYaw = yawOf(-flatLook)
	end
	local impactDir = dirOfYaw(impactYaw)
	local impactFace = eye + impactDir * FRAME_DIST

	local rig, m = spawnRig(feetAt(eye + flatLook * 6), eye)
	setRigVisible(rig, "none")
	local teammate: Model? = nil
	if sequence == "mimic" then
		teammate = cloneTeammate(payload.mimicUserId)
		if teammate then
			-- back turned, standing ahead
			local at = feetAt(eye + flatLook * 4) + Vector3.new(0, 3, 0)
			teammate:PivotTo(CFrame.lookAt(at, at + flatLook))
			teammate.Parent = Workspace
		end
	end
	local rigAlive = true
	local currentPose: { [string]: CFrame } = scarePose(rig, m, 0, 0, eye)
	local function facePoint(): Vector3
		local root = rig.PrimaryPart
		if not root then
			return eye + flatLook * 6
		end
		return (root.CFrame * ObserverRig.headFromRoot(m, currentPose) * ObserverRig.FaceAnchor).Position
	end
	-- stands it on the floor at `feet`, facing you, head tilted by `tilt`
	local function stand(feet: Vector3, tilt: number)
		currentPose = scarePose(rig, m, 0, 0, eye, { HeadJoint = CFrame.Angles(0, 0, math.rad(tilt)) })
		applyPose(m, currentPose)
		moveRig(rig, feet, eye)
	end
	-- places its face exactly at `face`, facing you (pose blend a)
	local function frame(face: Vector3, a: number, extra: { [string]: CFrame }?)
		currentPose = scarePose(rig, m, a, 0, eye, extra)
		applyPose(m, currentPose)
		rig:PivotTo(ObserverRig.placeFace(m, currentPose, face, eye))
	end

	-- the camera: what it looks at and its field of view, set every frame
	local lookAt = eye + flatLook * 10
	local fov = 70
	local shake = CFrame.identity
	local impactStarted: number? = nil
	local pushed = false
	local light = makeScareLight()
	local lightLevel = 0
	local lightFace = eye + flatLook * 6
	ScareController.LastFrame = nil
	cam:SetOverride("Death", 50, function()
		return CFrame.lookAt(eye, lookAt) * shake, fov
	end)

	if sequence == "mirror" then
		task.delay(0.02, function()
			-- the figure shows in the glass first
			for _, mirror in CollectionService:GetTagged("Mirror") do
				local glass = mirror:FindFirstChild("Glass")
				local figure = glass and glass:FindFirstChild("Figure", true)
				if figure and glass:IsA("BasePart") and typeof(payload.mirror) == "Vector3" and (glass.Position - payload.mirror).Magnitude < 1 then
					(figure :: GuiObject).Visible = true
					task.delay(T.glimpse, function()
						(figure :: GuiObject).Visible = false
					end)
				end
			end
		end)
	end

	local function look(yaw: number)
		lookAt = eye + dirOfYaw(yaw) * 10
	end

	-- phases A and B: everything before the impact
	local darkStarted, lightBack = false, false
	local function before(t: number)
		if sequence == "turn" then
			if t < T.turn then
				look(lerpYaw(forwardYaw, turnYaw, ease(t / T.turn)))
			elseif t < T.turn + T.hold then
				look(turnYaw) -- nothing there. The world keeps going.
			else
				look(lerpYaw(turnYaw, forwardYaw, ease((t - T.turn - T.hold) / T.back)))
			end
		elseif sequence == "stillness" then
			-- far ahead, perfectly still; only its head tilts, slowly
			setRigVisible(rig, "all")
			stand(feetAt(eye + flatLook * 6), 24 * ease(t / T.hold))
			lookAt = facePoint()
			fov = 70 - 6 * ease(t / T.hold)
			lightLevel, lightFace = 0.3, facePoint()
		elseif sequence == "drop" then
			look(forwardYaw)
			if t >= T.hold then
				-- its face comes down into the frame from above
				local k = ease((t - T.hold) / T.move)
				setRigVisible(rig, "all")
				local face = impactFace + Vector3.new(0, 2.6 * (1 - k), 0)
				frame(face, 1, { HeadJoint = CFrame.Angles(0, 0, math.rad(-20 * (1 - k))) })
				lightLevel, lightFace = 0.6 * k, face
			end
		elseif sequence == "lightsout" then
			look(forwardYaw)
			if not darkStarted then
				darkStarted = true
				fx:Fade(0.96, 0.05)
				audio:Silence(T.dark)
				audio:Play("FlashlightDead", nil, { volume = 0.8 })
			end
			if t < T.dark then
				-- two small eyes, far off, for a moment
				local third = T.dark / 3
				setRigVisible(rig, if t > third and t < 2 * third then "eyes" else "none")
				stand(feetAt(eye + flatLook * 8), 6)
			elseif not lightBack then
				lightBack = true
				setRigVisible(rig, "none")
				fx:Fade(0, 0.08)
			end
			if t >= T.dark + T.calm then
				-- it rises into your face from below
				local k = ease((t - T.dark - T.calm) / T.move)
				setRigVisible(rig, "all")
				local face = impactFace - Vector3.new(0, 2.4 * (1 - k), 0)
				frame(face, 1)
				lightLevel, lightFace = 0.6 * k, face
			end
		elseif sequence == "peek" then
			look(forwardYaw)
			if t < T.peek then
				-- half its head leans into the edge of the frame...
				setRigVisible(rig, "all")
				local k = math.sin(math.clamp(t / T.peek, 0, 1) * math.pi)
				stand(feetAt(eye + flatLook * 4.5 + right * sideSign * (2.9 - 0.8 * k)), -sideSign * 30 * k)
				lightLevel, lightFace = 0.25, facePoint()
			elseif t < T.peek + T.hold then
				setRigVisible(rig, "none") -- ...and is gone
				lightLevel = 0
			else
				-- it comes from the other side
				local k = ease((t - T.peek - T.hold) / T.move)
				setRigVisible(rig, "all")
				local face = impactFace - right * sideSign * 2.4 * (1 - k)
				frame(face, 1)
				lightLevel, lightFace = 0.6 * k, face
			end
		elseif sequence == "mirror" then
			if t < T.glimpse then
				lookAt = if typeof(payload.mirror) == "Vector3" then payload.mirror else eye + flatLook * 10
			else
				look(lerpYaw(forwardYaw, impactYaw, ease((t - T.glimpse) / T.turn)))
			end
		else -- mimic: their head turns all the way round
			look(forwardYaw)
			if teammate then
				local head = teammate:FindFirstChild("Head")
				local neck = head and head:FindFirstChild("Neck")
				if neck and neck:IsA("Motor6D") then
					local h = ease(t / T.turn)
					neck.Transform = CFrame.Angles(math.rad(-10 * h), math.rad(178 * h), math.rad(16 * h))
				end
			end
		end
	end

	-- phase C: the impact
	local function impact(ti: number)
		if teammate then
			teammate:Destroy()
			teammate = nil
		end
		setRigVisible(rig, "all")
		-- held: its head tilts, slowly. Then one push, with the scream.
		local tilt = 12 * ease(ti / IMPACT_HOLD)
		local push = ease(math.clamp((ti - IMPACT_HOLD) / PUSH, 0, 1))
		local dist = FRAME_DIST + (PUSH_DIST - FRAME_DIST) * push
		local face = eye + impactDir * dist
		frame(face, 1, { HeadJoint = CFrame.Angles(math.rad(-6 * push), 0, math.rad(tilt)) })
		lookAt = face
		fov = FRAME_FOV - 4 * push
		local tremble = (if reduced() then 0.3 else 1) * (0.004 + 0.012 * math.exp(-math.max(0, ti - IMPACT_HOLD) * 8) * push)
		shake = CFrame.Angles(math.noise(ti * 30, 1) * tremble, math.noise(ti * 30, 2) * tremble, 0)
		lightFace = face
		lightLevel = if reduced() then 0.8 elseif ti < 0.05 then 1 elseif math.floor(ti * 20) % 6 == 4 then 0.8 else 0.96
		if not pushed and push > 0 then
			pushed = true
			audio:Play("ObserverScreech", nil, { volume = 1 })
			cam:Shake(if reduced() then 0.2 else 0.45)
			if not reduced() then
				fx:Flash(Color3.fromRGB(150, 10, 10), 0.1, 0.2)
			end
		end
	end

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if not active or not rigAlive then
			conn:Disconnect()
			return
		end
		if t < impactAt then
			before(t)
		else
			if not impactStarted then
				impactStarted = os.clock()
				-- the hit: light, sound and a cold grade on the same frame (the
				-- world only goes quiet now, never before)
				audio:Silence(2.2)
				audio:Play("ObserverImpact", nil, { volume = 1 })
				audio:Play("JumpSting", nil, { volume = 1 })
				fx:Fade(0, 0.02)
				Kit.tween(fx:GetGrade(), 0.06, { TintColor = Color3.fromRGB(205, 220, 255), Saturation = -0.5 })
				fx:Glitch(if reduced() then 0.05 else 0.12, 0.1)
			end
			local ti = os.clock() - (impactStarted :: number)
			impact(ti)
			if not ScareController.LastFrame then
				-- what the player sees on the frame of the hit
				local root = rig.PrimaryPart :: BasePart
				local head = root.CFrame * ObserverRig.headFromRoot(m, currentPose) * ObserverRig.FaceAnchor
				local toCam = eye - head.Position
				local camCf = CFrame.lookAt(eye, lookAt)
				ScareController.LastFrame = {
					variant = variant,
					sequence = sequence,
					distance = toCam.Magnitude,
					facing = head.LookVector:Dot(toCam.Unit),
					centred = camCf.LookVector:Dot((head.Position - eye).Unit),
					inFront = camCf:PointToObjectSpace(head.Position).Z < 0,
					impactAt = impactAt,
				}
			end
		end
		aimScareLight(light, eye, lightFace, lightLevel)
	end)

	-- phase D: a hard cut to black, a ringing, a line
	task.delay(impactAt + IMPACT_HOLD + PUSH + AFTER, function()
		fx:Fade(1, 0.02)
		audio:Play("TinnitusRing", nil, { volume = 0.8 })
		destroyScareLight(light)
		task.delay(0.15, function()
			rigAlive = false
			rig:Destroy()
			if teammate then
				teammate:Destroy()
			end
			setServerObserverHidden(false)
			active = false
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

-- The mimic lunges (non-lethal): the view snaps to ITS face, wrong and too
-- close, lit from the camera, for a moment. `model` is the replicated mimic.
function ScareController:MimicLunge(model: Model)
	if active then
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

-- A short, non-lethal scare: its face is right there for a fraction of a
-- second, framed exactly like the impact of a death cinematic.
function ScareController:Flash(kind: string?)
	if active then
		return
	end
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local from = cam:GetCFrame()
	local look = Util.flat(from.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local rig, m = spawnRig(from.Position + look * 3 - Vector3.new(0, 4.5, 0), from.Position)
	local transforms = scarePose(rig, m, 1, 0.6, from.Position)
	applyPose(m, transforms)
	local face = from.Position + look * (FRAME_DIST + 0.3) + Vector3.new(0, from.LookVector.Y * 1.5, 0)
	rig:PivotTo(ObserverRig.placeFace(m, transforms, face, from.Position))
	-- lit on the very frame it appears, so it reads even in a blackout
	local light = makeScareLight()
	aimScareLight(light, from.Position, face, if reduced() then 0.7 else 1)
	cam:Shake(if reduced() then 0.2 else 0.5)
	fx:Glitch(if reduced() then 0.08 else 0.2, 0.15)
	Registry.AudioController:Play("JumpSting", nil, { volume = 1 })
	Registry.CameraController:SetFovEffect(-10)
	task.delay(if reduced() then 0.2 else 0.35, function()
		rig:Destroy()
		destroyScareLight(light)
		Registry.CameraController:SetFovEffect(0)
	end)
end

return ScareController
