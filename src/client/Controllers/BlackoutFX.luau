--[[
	BlackoutFX
	What a blackout brings with it besides the light (LightController and
	Shared/LightingRules do the lamps). Each level is darker and more macabre:

	  1 FAILS     a lamp near you clicks and buzzes for a moment
	  2 BREATHES  a door close by eases open on its own, creaking (locally:
	              the server's door stays shut); for a moment, the shadow of
	              someone standing in a pool of light who is not there
	  3 BEATS     a heartbeat you can hear, in time with the lamps; between two
	              beats a figure stands at the edge of a pool for one frame;
	              whispers
	  4 WATCHES   The Observer's own eyes, white, in the dark at the edge of
	              the light (a local copy of its rig with only the eyes
	              showing), gone the moment you look straight at them; the
	              heartbeat

	All of it is paranoia, not anomalies: local to this player, never
	reported, never counted, gone within seconds. With reduced effects there
	are no one-frame figures and the heartbeat is slower.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ObserverRig = require(ReplicatedStorage.Shared.ObserverRig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local BlackoutFX = {}

local player = Players.LocalPlayer
local random = Random.new()
local folder: Folder? = nil
local nextEventAt = 0
local lastBeat = -1

local FIGURE_COLOR = Color3.fromRGB(8, 8, 9)
local EYE_COLOR = Color3.fromRGB(235, 238, 240)

local function camera(): Camera
	return Workspace.CurrentCamera
end

local function level(): number
	local b = Workspace:GetAttribute("Blackout")
	return if type(b) == "number" and Workspace:GetAttribute("Power") == true then b else 0
end

local function holder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "BlackoutFX"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Parent = holder()
	return p
end

-- Is this point on screen, with nothing in between?
local function seen(at: Vector3, cone: number): boolean
	local cf = camera().CFrame
	local offset = at - cf.Position
	if offset.Magnitude < 1 or offset.Unit:Dot(cf.LookVector) < cone then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, holder() }
	return Workspace:Raycast(cf.Position, offset * 0.97, params) == nil
end

-- A pool of light in view, 12-34 studs away: where a figure can stand.
local function poolInView(): Vector3?
	local lamps = Registry.LightController:LitLamps(40)
	local options = {}
	for _, lamp in lamps do
		local floor = lamp - Vector3.new(0, lamp.Y - (camera().CFrame.Position.Y - 5.5), 0)
		local d = (floor - camera().CFrame.Position).Magnitude
		if d > 12 and d < 34 and seen(floor + Vector3.new(0, 3, 0), 0.6) then
			table.insert(options, floor)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[random:NextInteger(1, #options)]
end

-- A tall, thin dark figure (a silhouette, nothing more), for `duration` s.
local function figure(at: Vector3, duration: number)
	local look = camera().CFrame.Position
	local cf = CFrame.lookAt(at + Vector3.new(0, 3.3, 0), Vector3.new(look.X, at.Y + 3.3, look.Z))
	local body = part("Figure", Vector3.new(1.3, 5.6, 0.6), cf, FIGURE_COLOR)
	local head = part("FigureHead", Vector3.new(0.8, 1.1, 0.7), cf * CFrame.new(0, 3.4, 0), FIGURE_COLOR)
	task.delay(duration, function()
		body:Destroy()
		head:Destroy()
	end)
end

-- The Observer's own eyes, from a local copy of its rig with everything but
-- the eyes hidden, made white for the dark (MONOCHROME's two white eyes).
-- Built once, kept out of the world until needed.
local eyeRig: Model? = nil
local eyeMid = Vector3.zero

local function buildEyes(): Model?
	if eyeRig then
		return eyeRig
	end
	local ok, rig = pcall(ObserverRig.build, CFrame.new(), { localCopy = true })
	if not ok or not rig then
		return nil
	end
	local sum, n = Vector3.zero, 0
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = true
			d.CastShadow = false
			local name = d.Name
			if string.find(name, "Eyeball") then
				d.Color = Color3.fromRGB(150, 152, 156)
				d.Material = Enum.Material.Neon
				sum += d.CFrame.Position
				n += 1
			elseif name == "Iris" then
				d.Color = EYE_COLOR
				d.Material = Enum.Material.Neon
			elseif name ~= "Pupil" then
				d.Transparency = 1
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	if n == 0 then
		rig:Destroy()
		return nil
	end
	-- where the eyes sit relative to the rig's pivot (built at the origin)
	eyeMid = rig:GetPivot():PointToObjectSpace(sum / n)
	eyeRig = rig
	return rig
end

-- Its eyes in the dark at the edge of the light ahead, at its height,
-- looking at you; gone when looked at straight or after a few seconds.
local function eyes()
	local cf = camera().CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flat.Magnitude < 0.2 then
		return
	end
	flat = flat.Unit
	local side = Vector3.new(-flat.Z, 0, flat.X) * random:NextNumber(-6, 6)
	local floor = cf.Position + flat * random:NextNumber(16, 24) + side - Vector3.new(0, 5.5, 0)
	local at = floor + Vector3.new(0, eyeMid.Y, 0)
	if not seen(at, 0.5) then
		return
	end
	local rig = buildEyes()
	if not rig or rig.Parent then
		return
	end
	local facing = CFrame.lookAt(floor, Vector3.new(cf.Position.X, floor.Y, cf.Position.Z))
	local rot = facing - facing.Position
	rig:PivotTo(CFrame.new(at - rot * eyeMid) * rot)
	rig.Parent = holder()
	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local view = camera().CFrame
		local straight = (at - view.Position).Unit:Dot(view.LookVector) > 0.995
		if straight or os.clock() - born > 4 or level() < 4 or not rig.Parent then
			conn:Disconnect()
			rig.Parent = nil
		end
	end)
end

local function sound(key: string, at: Vector3?)
	local audio = Registry.AudioController
	if audio then
		audio:Play(key, at)
	end
end

local function nearbyLamp(): Vector3?
	local lamps = Registry.LightController:LitLamps(30)
	return if #lamps > 0 then lamps[random:NextInteger(1, #lamps)] else nil
end

local function event(lv: number, reduced: boolean)
	if lv == 1 then
		local at = nearbyLamp()
		if at then
			sound("LightFlicker", at)
			-- and buzzes for a moment
			local audio = Registry.AudioController
			local buzz = audio and audio:Play("ElectricBuzz", at)
			if buzz then
				task.delay(random:NextNumber(1.2, 2.4), function()
					buzz:Stop()
				end)
			end
		end
	elseif lv == 2 then
		local door = Registry.DoorController and Registry.DoorController:NearestClosed(camera().CFrame.Position, 26)
		if random:NextNumber() < 0.5 and door and Registry.DoorController:Creak(door) then
			-- a door nearby eases open on its own, creaking
			sound("WoodCreak", door:GetPivot().Position)
		else
			local at = poolInView()
			if at then
				figure(at, 0.45)
			end
		end
	elseif lv == 3 then
		if random:NextNumber() < 0.4 then
			local cf = camera().CFrame
			sound("Whisper", cf.Position - cf.LookVector * 5 + Vector3.new(0, 2, 0))
		elseif not reduced then
			-- between two beats, for one frame
			local at = poolInView()
			if at then
				figure(at, 1 / 50)
			end
		end
	elseif lv >= 4 then
		eyes()
	end
end

-- The eyes' rig (built on first use; tests look at it).
function BlackoutFX:EyesRig(): Model?
	return buildEyes()
end

function BlackoutFX:Level(): number
	return level()
end

function BlackoutFX:Start()
	RunService.Heartbeat:Connect(function()
		local lv = level()
		if lv == 0 or State.status ~= "ALIVE" or State.scareDark then
			return
		end
		local now = os.clock()
		local reduced = State.settings.reducedEffects == true
		-- the heartbeat you hear, in time with the lamps (LightingRules.heartbeat)
		if lv >= 3 then
			local period = if reduced then 2.3 else 1.15
			local beat = math.floor(now / period)
			if beat ~= lastBeat then
				lastBeat = beat
				sound(if lv >= 4 and not reduced then "HeartbeatFast" else "Heartbeat")
			end
		end
		if now >= nextEventAt then
			nextEventAt = now + random:NextNumber(5, 10) / math.max(1, lv * 0.6)
			pcall(event, lv, reduced)
		end
	end)
	-- a blackout's end takes everything with it
	Workspace:GetAttributeChangedSignal("Blackout"):Connect(function()
		if level() == 0 and folder then
			if eyeRig then
				eyeRig.Parent = nil
			end
			folder:ClearAllChildren()
		end
	end)
end

return BlackoutFX
