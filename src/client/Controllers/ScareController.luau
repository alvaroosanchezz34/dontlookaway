--[[
	ScareController
	Death cinematics and short scares, played with a LOCAL copy of The Observer
	so it is framed exactly against your own camera (no network lag, no clipping
	into walls you cannot see). The real, replicated Observer is hidden locally
	while a cinematic runs.

	Every catch is SUDDEN - you must never see it coming - and follows the same
	grammar, with a different sentence each time:
	  1  the sound cuts out and the grade goes cold, all at once
	  2  (gone: no breathing build-up)
	  3  the camera is whipped round to it in about a tenth of a second
	  4  it is there, much too close, already lunging
	  5  THE IMPACT. It crosses the last metres in a blink and folds down to
	     your eye level, its face two studs from the lens, looking straight
	     into it, its arms spread around you. The face is placed by forward
	     kinematics (ObserverRig.placeFace), not guessed: it is always in the
	     middle of the screen, level, turned to the camera, never behind it.
	     On that exact frame a cold light snaps on from your camera onto its
	     face (and a low warm one from below), so you SEE it even in a level 4
	     blackout; it flickers but never goes dark. Its eyes are on you. Then
	     the face splits open along the seam. One loud hit and a scream; the
	     shake and effects are kept small so they never hide the face.
	  6  a hard cut to black, a ringing in your ears, a short line, then you
	     watch the others

	Variants (chosen by the server from the situation)
	  behind   you turn around slowly. It was there all along.
	  side     a sharp turn to the side
	  front    it stands ahead of you, perfectly still, then is not still
	  dark     the light dies; when it comes back, it is at your face
	  door     it leans out of a doorway beside you
	  mirror   you see it in the mirror first, then you turn around
	  mimic    a teammate stands with their back to you; their head turns all
	           the way round; it is not them
	Reduced effects removes flashes and strobing and softens the motion.
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
local LUNGE = 0.2 -- the last metres: a blink
local HOLD = 0.9 -- its face, lit, in yours (long enough to see it)
local FRAME_DIST = 2.0 -- studs from the lens to its face at the impact
local FRAME_FOV = 50 -- the face fills about two thirds of the screen
local SPOT = 3.2 -- the scare light at full strength (brighter washes the face out)
local UNDER = 1.1

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

-- The inner eyes light up as the face opens.
local function innerEyes(rig: Model, open: number)
	for _, side in { "L", "R" } do
		local eye = rig:FindFirstChild("Eye" .. side)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = 1 - math.clamp(open, 0, 1)
		end
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

--[[
	Plays the death cinematic. payload: variant, position (victim root), and
	variant context (door, doorDir, mirror, side, mimicUserId, mimicName).
	Calls `done()` once the screen is black.
]]
function ScareController:Death(payload, done: () -> ())
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local audio = Registry.AudioController
	local variant = payload.variant or "behind"
	active = true
	local start = os.clock()
	local from = cam:GetCFrame()
	local eye = from.Position
	local flatLook = Util.flat(from.LookVector)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local floorY = if typeof(payload.position) == "Vector3" then payload.position.Y - 3 else eye.Y - 4.5
	local function feetAt(p: Vector3): Vector3
		return Vector3.new(p.X, floorY, p.Z)
	end
	setServerObserverHidden(true)

	-- where it stands, where we look first. No build-up: the camera is
	-- WHIPPED round (about a tenth of a second) and it is already lunging.
	local rigFeet: Vector3
	local firstLook: Vector3? = nil
	local turnStart, turnTime = 0, 0.12
	local lungeAt = 0.14
	if variant == "behind" then
		rigFeet = feetAt(eye - flatLook * 3)
		turnTime = 0.13
	elseif variant == "side" then
		rigFeet = feetAt(eye + right * (payload.side or 1) * 2.8)
		turnTime, lungeAt = 0.09, 0.1
	elseif variant == "front" then
		rigFeet = feetAt(eye + flatLook * 5)
		lungeAt = 0.05
	elseif variant == "dark" then
		-- the light dies for a breath, then it is at your face
		rigFeet = feetAt(eye + flatLook * 1.7)
		lungeAt = 0.22
	elseif variant == "door" and typeof(payload.door) == "Vector3" then
		local to = Util.flat(payload.door - eye)
		local d = math.clamp(to.Magnitude, 2.5, 6)
		rigFeet = feetAt(eye + (if to.Magnitude > 0.01 then to.Unit else flatLook) * d)
	elseif variant == "mirror" then
		-- a glimpse in the glass, then the whip round
		rigFeet = feetAt(eye - flatLook * 3)
		firstLook = if typeof(payload.mirror) == "Vector3" then payload.mirror else nil
		turnStart, turnTime = 0.2, 0.1
		lungeAt = 0.3
	elseif variant == "mimic" then
		-- its head spins round, and it is on you
		rigFeet = feetAt(eye + flatLook * 4)
		lungeAt = 0.32
	else
		rigFeet = feetAt(eye - flatLook * 3)
	end
	local rig, m = spawnRig(rigFeet, eye)
	local teammate: Model? = nil
	if variant == "mimic" then
		teammate = cloneTeammate(payload.mimicUserId)
		if teammate then
			-- back turned, standing where it will be
			local root = teammate:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local away = Util.flat(rigFeet - eye)
				teammate:PivotTo(CFrame.lookAt(rigFeet + Vector3.new(0, 3, 0), rigFeet + Vector3.new(0, 3, 0) + away.Unit))
			end
			teammate.Parent = Workspace
			rig.Parent = nil
		end
	elseif variant == "dark" then
		rig.Parent = nil
	end
	local rigAlive = true
	-- the face, wherever the rig is: solved from the pose (no physics lag)
	local currentPose: { [string]: CFrame } = scarePose(rig, m, 0, 0, eye)
	local function facePoint(): Vector3
		local root = rig.PrimaryPart
		if not root then
			return rigFeet + Vector3.new(0, 8.6, 0)
		end
		return (root.CFrame * ObserverRig.headFromRoot(m, currentPose) * ObserverRig.FaceAnchor).Position
	end
	local lookTarget = firstLook or (eye + flatLook * 10)
	-- where the face starts (standing) and where it ends (in your face)
	local startFace = facePoint()
	local toRig = Util.flat(startFace - eye)
	local frameDir = if toRig.Magnitude > 0.01 then toRig.Unit else flatLook
	local endFace = eye + frameDir * FRAME_DIST
	local framedFace = startFace

	-- 1. the sound drops out at once, the grade turns cold (no slow build-up)
	audio:Silence(2.2)
	Kit.tween(fx:GetGrade(), 0.06, { TintColor = if variant == "dark" then Color3.fromRGB(255, 205, 200) else Color3.fromRGB(205, 220, 255), Saturation = -0.5 })
	if variant == "dark" then
		fx:Fade(0.95, 0.03)
		audio:Play("FlashlightDead", nil, { volume = 0.8 })
		task.delay(lungeAt - 0.03, function()
			rig.Parent = Workspace
			fx:Fade(0, 0.03)
		end)
	elseif variant == "mirror" then
		task.delay(0.02, function()
			-- the figure shows in the glass first
			for _, mirror in CollectionService:GetTagged("Mirror") do
				local glass = mirror:FindFirstChild("Glass")
				local figure = glass and glass:FindFirstChild("Figure", true)
				if figure and glass:IsA("BasePart") and typeof(payload.mirror) == "Vector3" and (glass.Position - payload.mirror).Magnitude < 1 then
					(figure :: GuiObject).Visible = true
					task.delay(0.5, function()
						(figure :: GuiObject).Visible = false
					end)
				end
			end
		end)
	end

	local mimicSwapped = false
	local impactDone = false
	local impactAt: number? = nil
	local light = makeScareLight()
	ScareController.LastFrame = nil
	cam:SetOverride("Death", 50, function()
		local t = os.clock() - start
		local target = lookTarget
		local turn = ease((t - turnStart) / turnTime)
		if variant == "mimic" then
			target = rigFeet + Vector3.new(0, 4.5, 0)
		elseif variant == "front" or variant == "dark" then
			target = framedFace
		else
			target = lookTarget:Lerp(framedFace, turn)
		end
		local fov = 70
		local shake = CFrame.identity
		-- 4/5: the lunge: the view settles on its face as it arrives
		if t >= lungeAt then
			local l = ease(math.clamp((t - lungeAt) / LUNGE, 0, 1))
			target = framedFace
			fov = 70 + (FRAME_FOV - 70) * l
			if impactAt then
				-- a small jolt that dies out fast: never enough to lose the face
				local h = os.clock() - impactAt
				local jolt = math.exp(-h * 6) * (if reduced() then 0.3 else 1)
				shake = CFrame.Angles(math.noise(h * 40, 1) * 0.012 * jolt, math.noise(h * 40, 2) * 0.016 * jolt, math.noise(h * 30, 3) * 0.02 * jolt)
			end
		end
		return CFrame.lookAt(eye, target) * shake, fov
	end)

	-- animate the rig (and the mimic) frame by frame
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if not active or not rigAlive then
			conn:Disconnect()
			return
		end
		if teammate and not mimicSwapped then
			-- its head turns all the way round, too slowly
			local head = teammate:FindFirstChild("Head")
			local neck = head and head:FindFirstChild("Neck")
			if neck and neck:IsA("Motor6D") then
				local h = ease(t / 0.26)
				neck.Transform = CFrame.Angles(math.rad(-10 * h), math.rad(178 * h), math.rad(16 * h))
			end
			if t >= lungeAt - 0.04 then
				mimicSwapped = true
				teammate:Destroy()
				teammate = nil
				rig.Parent = Workspace
			end
		end
		if t < lungeAt then
			-- standing, head tilted, its eyes already on you
			currentPose = scarePose(rig, m, 0, 0, eye)
			applyPose(m, currentPose)
			moveRig(rig, rigFeet, eye)
			framedFace = facePoint()
			aimScareLight(light, eye, framedFace, 0)
			return
		end
		local l = math.clamp((t - lungeAt) / LUNGE, 0, 1)
		local a = ease(l)
		local open, extra = 0, nil
		if impactAt then
			local h = os.clock() - impactAt
			-- the face splits open just after the hit, then holds
			open = ease(math.clamp((h - 0.08) / 0.22, 0, 1))
			-- a short shudder of the head, dying out (no constant jitter)
			local shudder = math.exp(-h * 5) * (if reduced() then 0.3 else 1)
			extra = { HeadJoint = CFrame.Angles(0, math.rad(math.sin(h * 70) * 2.5 * shudder), math.rad(math.sin(h * 55) * 2 * shudder)) }
		end
		currentPose = scarePose(rig, m, a, open, eye, extra)
		applyPose(m, currentPose)
		innerEyes(rig, open)
		-- the face travels from where it stood to two studs from the lens; the
		-- body is placed around it so it is always level and facing the camera
		framedFace = startFace:Lerp(endFace, a)
		rig:PivotTo(ObserverRig.placeFace(m, currentPose, framedFace, eye))
		if l >= 1 and not impactDone then
			impactDone = true
			impactAt = os.clock()
			-- 5: THE IMPACT - light, hit and scream on the same frame
			audio:Play("ObserverImpact", nil, { volume = 1 })
			audio:Play("ObserverScreech", nil, { volume = 1 })
			audio:Play("JumpSting", nil, { volume = 1 })
			cam:Shake(if reduced() then 0.2 else 0.45)
			fx:Glitch(if reduced() then 0.08 else 0.2, 0.15)
			if not reduced() then
				-- a faint red edge for a heartbeat: the face stays clear
				fx:Flash(Color3.fromRGB(150, 10, 10), 0.1, 0.2)
			end
			-- what the player sees, for tests and the admin scare test
			local camCf = CFrame.lookAt(eye, framedFace)
			local root = rig.PrimaryPart :: BasePart
			local head = root.CFrame * ObserverRig.headFromRoot(m, currentPose) * ObserverRig.FaceAnchor
			local toCam = eye - head.Position
			ScareController.LastFrame = {
				variant = variant,
				distance = toCam.Magnitude,
				facing = head.LookVector:Dot(toCam.Unit), -- 1 = looking straight into the lens
				centred = camCf.LookVector:Dot((head.Position - eye).Unit), -- 1 = dead centre
				inFront = camCf:PointToObjectSpace(head.Position).Z < 0,
			}
		end
		-- the light: dark until the impact, then on, flickering a little but
		-- never going out (the face must stay readable)
		local level = 0
		if impactAt then
			local h = os.clock() - impactAt
			if reduced() then
				level = 0.8
			else
				local frame = math.floor(h * 20)
				level = if h < 0.05 then 1 elseif frame % 5 == 3 then 0.78 else 0.96
			end
		end
		aimScareLight(light, eye, framedFace, level)
	end)

	-- 6: a hard cut to black, a ringing, a line
	task.delay(lungeAt + LUNGE + HOLD, function()
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
	innerEyes(rig, 0.6)
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
