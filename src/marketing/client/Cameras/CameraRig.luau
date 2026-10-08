--[[
	CameraRig
	The Marketing Studio camera. It runs in its own render step AFTER the game's
	camera, so it never goes through the game's camera code (which reports the
	view to the server for perception): the server keeps seeing the player's
	real view while the screen shows the shot. When the scene ends the render
	step is removed and the game's camera takes over on the next frame.

	A shot = base CFrame + preset (lens/operator) + optional tracking target,
	plus shake. Moves and FOV changes are spans on the scene timeline.
]]

local Workspace = game:GetService("Workspace")

local Presets = require(script.Parent.Presets)
local Runtime = require(script.Parent.Parent.Runtime)

local CameraRig = {}

local base = CFrame.new()
local fov = 70
local presetName = "STATIC"
local forced: string? = nil -- panel override
local trackTarget: any = nil
local trackSmooth = 6
local trackedLook: Vector3? = nil
local trauma = 0
local traumaDecay = 1.5
local jolt = 0
local clock = 0
local final = CFrame.new()
local lastStep = -math.huge
local active = false
local moveAlpha = 0 -- 0..1 progress of the current move (for footstep bob)

function CameraRig.presetName(): string
	return forced or presetName
end

function CameraRig.preset()
	return Presets[CameraRig.presetName()] or Presets.STATIC
end

function CameraRig.force(name: string?)
	forced = if name and Presets[name] then name else nil
end

function CameraRig.begin()
	local camera = Workspace.CurrentCamera
	active = true
	base = camera.CFrame
	final = base
	fov = camera.FieldOfView
	presetName = "STATIC"
	trackTarget, trackedLook = nil, nil
	trauma, jolt, clock, lastStep = 0, 0, 0, -math.huge
	local saved = { type = camera.CameraType, cf = camera.CFrame, fov = camera.FieldOfView, subject = camera.CameraSubject }
	Runtime.onCleanup(function()
		active = false
		local cam = Workspace.CurrentCamera
		-- the game's own camera rewrites all of this next frame; without one, restore it
		cam.CameraType = saved.type
		cam.CFrame = saved.cf
		cam.FieldOfView = saved.fov
		if saved.subject and saved.subject.Parent then
			cam.CameraSubject = saved.subject
		end
	end)
end

function CameraRig.isActive(): boolean
	return active
end

-- Hard cut to a new shot.
function CameraRig.cut(cf: CFrame, preset: string?, newFov: number?)
	base = cf
	if preset and Presets[preset] then
		presetName = preset
	end
	fov = newFov or CameraRig.preset().fov
	trackedLook = nil
	lastStep = -math.huge
end

function CameraRig.getBase(): CFrame
	return base
end

function CameraRig.setBase(cf: CFrame)
	base = cf
end

function CameraRig.setFov(value: number)
	fov = value
end

function CameraRig.getFov(): number
	return fov
end

function CameraRig.setMoveAlpha(a: number)
	moveAlpha = a
end

-- Keep looking at a point / part / model (nil to stop).
function CameraRig.track(target: any, smooth: number?)
	trackTarget = target
	trackSmooth = smooth or 6
	if not target then
		trackedLook = nil
	end
end

function CameraRig.shake(amount: number, decay: number?)
	trauma = math.clamp(trauma + amount, 0, 1)
	traumaDecay = decay or 1.5
end

function CameraRig.jolt(amount: number)
	jolt = math.max(jolt, amount)
end

local function targetPosition(): Vector3?
	local t = trackTarget
	if typeof(t) == "Vector3" then
		return t
	elseif typeof(t) == "Instance" then
		if t:IsA("BasePart") then
			return t.CFrame.Position
		elseif t:IsA("Model") then
			return t:GetPivot().Position
		elseif t:IsA("Attachment") then
			return t.WorldPosition
		end
	end
	return nil
end

-- Called by the timeline every (unpaused) frame.
function CameraRig.update(dt: number)
	clock += dt
	local p = CameraRig.preset()
	-- low frame-rate recording look
	if p.fps and clock - lastStep < 1 / p.fps then
		return
	end
	lastStep = clock
	local cf = base
	local look = targetPosition()
	if look then
		local want = (look - cf.Position)
		if want.Magnitude > 0.01 then
			want = want.Unit
			trackedLook = if trackedLook then trackedLook:Lerp(want, math.min(1, dt * trackSmooth)) else want
			cf = CFrame.lookAt(cf.Position, cf.Position + (trackedLook :: Vector3))
		end
	end
	-- operator: slow drift + handheld sway (smooth noise, never jittery)
	local t = clock * (p.freq or 0.5)
	local sway = p.handheld or 0
	local drift = p.breathe or 0
	local offset = Vector3.new(math.noise(t, 11.3) * sway + math.sin(clock * 0.37) * drift, math.noise(t, 27.1) * sway + math.sin(clock * 0.53) * drift * 0.6, math.noise(t, 41.7) * sway * 0.5)
	local r = math.rad(p.rot or 0)
	local rot = CFrame.Angles(math.noise(t, 3.1) * r, math.noise(t, 5.9) * r, math.noise(t, 8.2) * r * 0.6)
	if p.bob then
		local walk = math.sin(moveAlpha * math.pi * 14)
		offset += Vector3.new(0, math.abs(walk) * 0.06, 0)
	end
	-- shake (trauma^2 so small values stay subtle)
	trauma = math.max(0, trauma - traumaDecay * dt)
	jolt = math.max(0, jolt - 6 * dt)
	local s = trauma * trauma + jolt
	local st = clock * 28
	local shake = CFrame.Angles(math.noise(st, 1) * 0.06 * s, math.noise(st, 2) * 0.06 * s, math.noise(st, 3) * 0.05 * s)
	final = cf * CFrame.new(offset) * rot * shake
end

-- Called from the render step (also while paused, so the frame holds).
function CameraRig.apply()
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = final
	camera.FieldOfView = math.clamp(fov, 1, 120)
end

return CameraRig
