--[[
	ScareController
	Death cinematics and short scares, played with a LOCAL copy of The Observer
	so it is framed exactly against your own camera (no network lag, no clipping
	into walls you cannot see). The real, replicated Observer is hidden locally
	while a cinematic runs.

	Every catch is 2-4 seconds and follows the same grammar, with a different
	sentence each time:
	  1  the light changes, the sound drops out for a moment
	  2  breathing, very close; the view starts to tremble
	  3  you look (or are made to look)
	  4  it is there, much too close; its head moves the wrong way, its face
	     opens along the seam
	  5  the field of view collapses, the view is pushed back, a flash,
	     distortion, a single loud hit
	  6  black, a ringing in your ears, a short line, then you watch the others

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

local function pose(m: { [string]: Motor6D }, name: string, cf: CFrame)
	local motor = m[name]
	if motor then
		motor.Transform = cf
	end
end

-- The attack pose: arms rising, the head tipping, the face parting.
local function attackPose(rig: Model, m: { [string]: Motor6D }, t: number)
	local a = ease(t)
	pose(m, "LeftShoulder", CFrame.Angles(math.rad(-100 * a), 0, math.rad(-12 * a)))
	pose(m, "RightShoulder", CFrame.Angles(math.rad(-100 * a), 0, math.rad(12 * a)))
	pose(m, "LeftElbow", CFrame.Angles(math.rad(-30 * a), 0, 0))
	pose(m, "RightElbow", CFrame.Angles(math.rad(-30 * a), 0, 0))
	pose(m, "Waist", CFrame.Angles(math.rad(18 * a), 0, 0))
	pose(m, "NeckJoint", CFrame.Angles(math.rad(28 * a), 0, 0))
	-- the head snaps sideways in steps, never smoothly
	local snap = math.floor(t * 6) / 6
	pose(m, "HeadJoint", CFrame.Angles(math.rad(8), 0, math.rad(68 * snap)) * CFrame.Angles(0, 0, math.rad(math.sin(os.clock() * 55) * 3 * a)))
	pose(m, "JawL", CFrame.Angles(0, math.rad(-55 * a), 0))
	pose(m, "JawR", CFrame.Angles(0, math.rad(55 * a), 0))
	for _, side in { "L", "R" } do
		local eye = rig:FindFirstChild("Eye" .. side, true)
		if eye and eye:IsA("BasePart") then
			eye.Transparency = 1 - a
		end
	end
end

local function idlePose(m: { [string]: Motor6D }, tilt: number)
	pose(m, "HeadJoint", CFrame.Angles(0, 0, math.rad(tilt)))
	pose(m, "Waist", CFrame.Angles(math.rad(6), 0, 0))
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

	-- where it stands, where we look first
	local rigFeet: Vector3
	local firstLook: Vector3? = nil
	local turnStart, turnTime = 0.55, 0.8
	local lungeAt = 1.35
	if variant == "behind" then
		rigFeet = feetAt(eye - flatLook * 3)
		turnTime = 0.95
	elseif variant == "side" then
		rigFeet = feetAt(eye + right * (payload.side or 1) * 2.8)
		turnStart, turnTime = 0.75, 0.22
	elseif variant == "front" then
		rigFeet = feetAt(eye + flatLook * 7)
	elseif variant == "dark" then
		rigFeet = feetAt(eye + flatLook * 1.7)
	elseif variant == "door" and typeof(payload.door) == "Vector3" then
		local to = Util.flat(payload.door - eye)
		local d = math.clamp(to.Magnitude, 2.5, 6)
		rigFeet = feetAt(eye + (if to.Magnitude > 0.01 then to.Unit else flatLook) * d)
	elseif variant == "mirror" then
		rigFeet = feetAt(eye - flatLook * 3)
		firstLook = if typeof(payload.mirror) == "Vector3" then payload.mirror else nil
		turnStart, turnTime = 1.0, 0.65
		lungeAt = 1.75
	elseif variant == "mimic" then
		rigFeet = feetAt(eye + flatLook * 5)
		lungeAt = 1.7
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
	local lastHead = rigFeet + Vector3.new(0, 8.6, 0)
	local rigHead = function(): Vector3
		if rigAlive then
			local head = rig:FindFirstChild("Head") :: BasePart?
			if head then
				lastHead = head.CFrame.Position
			end
		end
		return lastHead
	end
	local lookTarget = firstLook or (eye + flatLook * 10)

	-- 1. the light changes, the sound drops out
	audio:Silence(2.2)
	fx:Blur(2, 0.4)
	Kit.tween(fx:GetGrade(), 0.5, { TintColor = if variant == "dark" then Color3.fromRGB(255, 205, 200) else Color3.fromRGB(205, 220, 255), Saturation = -0.5 })
	-- 2. breathing, very close
	task.delay(0.3, function()
		audio:Play("ObserverInhale", nil, { volume = 1 })
	end)
	task.delay(0.55, function()
		audio:Play("HeartbeatFast", nil, { volume = 1 })
	end)
	if variant == "dark" then
		task.delay(0.25, function()
			fx:Fade(0.95, 0.06)
			audio:Play("FlashlightDead", nil, { volume = 0.8 })
		end)
		task.delay(lungeAt - 0.12, function()
			rig.Parent = Workspace
			fx:Fade(0, 0.05)
		end)
	elseif variant == "mirror" then
		task.delay(0.25, function()
			-- the figure shows in the glass first
			for _, mirror in CollectionService:GetTagged("Mirror") do
				local glass = mirror:FindFirstChild("Glass")
				local figure = glass and glass:FindFirstChild("Figure", true)
				if figure and glass:IsA("BasePart") and typeof(payload.mirror) == "Vector3" and (glass.Position - payload.mirror).Magnitude < 1 then
					(figure :: GuiObject).Visible = true
					task.delay(1.4, function()
						(figure :: GuiObject).Visible = false
					end)
				end
			end
			audio:Play("JumpSting", nil, { volume = 0.6 })
		end)
	end

	local mimicSwapped = false
	local impactDone = false
	cam:SetOverride("Death", 50, function()
		local t = os.clock() - start
		local tremble = math.clamp((t - 0.35) / 1.2, 0, 1) * (if reduced() then 0.3 else 1)
		local shake = CFrame.Angles(math.noise(t * 22, 1) * 0.01 * tremble, math.noise(t * 22, 2) * 0.014 * tremble, 0)
		-- what we are looking at
		local target = lookTarget
		local turn = ease((t - turnStart) / turnTime)
		if variant ~= "front" and variant ~= "dark" and variant ~= "mimic" then
			target = lookTarget:Lerp(rigHead(), turn)
		elseif variant == "mimic" then
			target = rigFeet + Vector3.new(0, 4.5, 0)
		elseif variant == "front" or variant == "dark" then
			target = rigHead()
		end
		local fov = 70
		local camPos = eye
		-- 4/5: the lunge, the field of view collapsing, the push back
		if t >= lungeAt then
			local l = math.clamp((t - lungeAt) / 0.32, 0, 1)
			local headTo = rigHead()
			target = headTo
			fov = 70 - 26 * ease(l)
			camPos = eye - (headTo - eye).Unit * 0.7 * ease(l)
		end
		return CFrame.lookAt(camPos, target) * shake, fov
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
				local h = ease((t - 0.6) / 0.9)
				neck.Transform = CFrame.Angles(math.rad(-10 * h), math.rad(178 * h), math.rad(16 * h))
			end
			if t >= lungeAt - 0.15 then
				mimicSwapped = true
				teammate:Destroy()
				teammate = nil
				rig.Parent = Workspace
			end
		end
		if t < lungeAt then
			idlePose(m, if variant == "door" then 70 * ease((t - 0.6) / 0.5) else 22)
		else
			local l = (t - lungeAt) / 0.32
			attackPose(rig, m, l)
			-- it closes the distance in a blink
			local toward = Util.flat(eye - rigFeet)
			local dist = toward.Magnitude
			local closeTo = math.max(0.9, dist - (dist - 1.1) * ease(l))
			local feet = eye - (if dist > 0.01 then toward.Unit else -flatLook) * closeTo
			moveRig(rig, Vector3.new(feet.X, floorY, feet.Z), eye)
			if l >= 0.55 and not impactDone then
				impactDone = true
				-- 5: flash, distortion, one loud hit
				audio:Play("ObserverImpact", nil, { volume = 1 })
				audio:Play("ObserverScreech", nil, { volume = 0.8 })
				fx:Glitch(1, 0.4)
				if not reduced() then
					fx:Flash(if variant == "dark" then Color3.fromRGB(150, 20, 20) else Color3.fromRGB(235, 235, 255), 0.75, 0.45)
				end
				cam:Shake(1)
				fx:Blur(14, 0.2)
			end
		end
	end)

	-- 6: black, a ringing, a line
	task.delay(lungeAt + 0.32, function()
		fx:Fade(1, 0.08)
		audio:Play("TinnitusRing", nil, { volume = 0.8 })
		task.delay(0.15, function()
			rigAlive = false
			rig:Destroy()
			if teammate then
				teammate:Destroy()
			end
			setServerObserverHidden(false)
			active = false
		end)
		task.delay(0.9, function()
			local line = LINES[variant] or "The building took you."
			if variant == "mimic" then
				line = string.format(line, payload.mimicName or "them")
			end
			fx:Title("YOU WERE TAKEN", line, 3, Kit.F.Title)
		end)
		done()
	end)
end

-- A short, non-lethal scare: it is right there for a fraction of a second.
function ScareController:Flash(kind: string?)
	if active then
		return
	end
	local cam = Registry.CameraController
	local fx = Registry.EffectsController
	local from = cam:GetCFrame()
	local look = Util.flat(from.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local feet = from.Position + look * 1.6 - Vector3.new(0, 7.2, 0)
	local rig, m = spawnRig(feet, from.Position)
	attackPose(rig, m, 0.8)
	cam:Shake(0.9)
	fx:Glitch(1, 0.3)
	if not reduced() then
		fx:Flash(Color3.fromRGB(220, 220, 235), 0.4, 0.35)
	end
	Registry.CameraController:SetFovEffect(-14)
	task.delay(if reduced() then 0.15 else 0.28, function()
		rig:Destroy()
		Registry.CameraController:SetFovEffect(0)
	end)
end

return ScareController
