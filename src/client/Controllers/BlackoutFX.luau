--[[
	BlackoutFX
	What a blackout brings with it besides the light (LightController and
	Shared/LightingRules do the lamps). Each level is more macabre, not darker:

	  1 FAILS     a lamp near you buzzes and clicks now and then
	  2 BREATHES  a door creaks somewhere close; for a moment, the shadow of
	              someone standing in a pool of light who is not there
	  3 BEATS     a heartbeat you can hear, in time with the lamps; between two
	              beats a figure stands at the edge of a pool for one frame;
	              whispers
	  4 WATCHES   two white eyes in the dark at the edge of the light, gone
	              the moment you look straight at them; the heartbeat

	All of it is paranoia, not anomalies: local to this player, never
	reported, never counted, gone within seconds. With reduced effects there
	are no one-frame figures and the heartbeat is slower.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

-- Two white eyes in the dark, at a tall thing's height, at the edge of the
-- light ahead; gone when looked at straight or after a few seconds.
local function eyes()
	local cf = camera().CFrame
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if flat.Magnitude < 0.2 then
		return
	end
	flat = flat.Unit
	local side = Vector3.new(-flat.Z, 0, flat.X) * random:NextNumber(-6, 6)
	local at = cf.Position + flat * random:NextNumber(16, 24) + side + Vector3.new(0, 2.6, 0)
	if not seen(at, 0.5) then
		return
	end
	local face = CFrame.lookAt(at, cf.Position)
	local left = part("Eye", Vector3.new(0.16, 0.12, 0.05), face * CFrame.new(-0.2, 0, 0), EYE_COLOR, Enum.Material.Neon)
	local right = part("Eye", Vector3.new(0.16, 0.12, 0.05), face * CFrame.new(0.2, 0.03, 0), EYE_COLOR, Enum.Material.Neon)
	left.CastShadow = false
	right.CastShadow = false
	local born = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local view = camera().CFrame
		local straight = (at - view.Position).Unit:Dot(view.LookVector) > 0.995
		if straight or os.clock() - born > 4 or level() < 4 then
			conn:Disconnect()
			left:Destroy()
			right:Destroy()
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
		end
	elseif lv == 2 then
		if random:NextNumber() < 0.5 then
			local cf = camera().CFrame
			sound("WoodCreak", cf.Position + Vector3.new(random:NextNumber(-12, 12), 2, random:NextNumber(-12, 12)))
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
			folder:ClearAllChildren()
		end
	end)
end

return BlackoutFX
