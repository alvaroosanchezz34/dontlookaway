--[[
	AudioController
	* volume settings per category (SoundGroups)
	* server-triggered sounds (positional or 2D)
	* ambient beds that crossfade between outside / building / basement / lobby
	* dynamic silence: the director can duck the world before something happens
	* body sounds: heartbeat and breathing driven by fear, stamina and the
	  Observer's proximity
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)
local AudioLibrary = require(ReplicatedStorage.Shared.Config.AudioLibrary)
local State = require(script.Parent.Parent.State)

local AudioController = {}

local beds: { [string]: Sound } = {}
local bedTargets: { [string]: number } = {}
local duck = 1 -- 0..1 multiplier on the ambient group (silence)
local duckTween: Tween? = nil
local duckValue = Instance.new("NumberValue")
duckValue.Value = 1
local lastHeartbeat = 0
local lastBreath = 0

local GROUP_SETTING = {
	Ambient = "ambient",
	Footsteps = "sfx",
	Player = "sfx",
	Monster = "sfx",
	Anomaly = "sfx",
	Interaction = "sfx",
	UI = "ui",
	Music = "music",
}

function AudioController:ApplyVolumes()
	local s = State.settings
	for groupName, key in GROUP_SETTING do
		local group = SoundFactory.getGroup(groupName)
		if group then
			local v = (s[key] or 1) * (s.master or 1)
			if groupName == "Ambient" then
				v *= duck
			end
			group.Volume = v
		end
	end
end

-- Plays a sound. at: Vector3 (world), Instance (attached) or nil (2D).
function AudioController:Play(key: string, at: any, opts: { [string]: any }?): Sound?
	local parent: Instance = SoundService
	local temp: Instance? = nil
	if typeof(at) == "Vector3" then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = at
		attachment.Parent = Workspace.Terrain
		parent = attachment
		temp = attachment
	elseif typeof(at) == "Instance" and at.Parent then
		parent = at
	end
	local sound = SoundFactory.create(key, parent, opts)
	if not sound then
		if temp then
			temp:Destroy()
		end
		return nil
	end
	sound:Play()
	if not sound.Looped then
		local cleanup = temp or sound
		sound.Ended:Once(function()
			cleanup:Destroy()
		end)
		task.delay(20, function()
			if cleanup.Parent then
				cleanup:Destroy()
			end
		end)
	end
	return sound
end

function AudioController:PlayUI(key: string)
	self:Play(key, nil)
end

-- Silence: the world holds its breath for `duration` seconds.
function AudioController:Silence(duration: number)
	if duckTween then
		duckTween:Cancel()
	end
	duckTween = TweenService:Create(duckValue, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Value = 0.12 })
	duckTween:Play()
	task.delay(duration, function()
		local t = TweenService:Create(duckValue, TweenInfo.new(3, Enum.EasingStyle.Sine), { Value = 1 })
		duckTween = t
		t:Play()
	end)
end

local function bed(key: string)
	local s = SoundFactory.create(key, SoundService, { looped = true })
	if s then
		s.Volume = 0
		s:Play()
		beds[key] = s
	end
end

-- Where is the listener? "lobby" | "outside" | "building" | "basement"
local function zone(): string
	local camera = Workspace.CurrentCamera
	if not camera then
		return "lobby"
	end
	local p = camera.CFrame.Position
	if p.X < -150 then
		return "lobby"
	end
	local inside = p.X > 0 and p.X < 160 and p.Z > 0 and p.Z < 120 and p.Y < 40
	if not inside then
		return "outside"
	end
	if p.Y < -1 then
		return "basement"
	end
	return "building"
end

local MIX = {
	lobby = { AmbientRain = 0.25, AmbientAir = 0.2 },
	outside = { AmbientRain = 1, Wind = 0.9, AmbientDrone = 0.25 },
	building = { AmbientDrone = 0.8, AmbientAir = 0.7, AmbientHum = 0.5, AmbientRain = 0.18 },
	basement = { AmbientDrone = 1, AmbientAir = 0.4, AmbientHum = 0.25 },
}

local function updateBeds(dt: number)
	local z = zone()
	local inMenu = State.status == "MENU"
	local mix = MIX[z] or {}
	for key, sound in beds do
		local target = mix[key] or 0
		if inMenu then
			target *= 0.7
		end
		if workspace:GetAttribute("Escape") and z ~= "outside" then
			-- during the escape the building's hum drains away
			target *= if key == "AmbientDrone" then 1.2 else 0.3
		end
		local def = AudioLibrary.Sounds[key]
		local full = (def and def.volume or 0.4) * target
		bedTargets[key] = full
		sound.Volume += (full - sound.Volume) * math.min(1, dt * 1.2)
	end
end

local function updateBody()
	local now = os.clock()
	-- heartbeat when The Observer is close or fear is high
	local d = State.observerDistance
	local intensity = 0
	if d < 60 then
		intensity = 1 - d / 60
	end
	intensity = math.max(intensity, State.fear * 0.8)
	if State.status == "ALIVE" and intensity > 0.15 then
		local interval = 1.3 - intensity * 0.75
		if now - lastHeartbeat > interval then
			lastHeartbeat = now
			AudioController:Play("Heartbeat", nil, { volume = 0.35 + intensity * 0.65 })
			task.delay(0.22, function()
				AudioController:Play("Heartbeat", nil, { volume = (0.35 + intensity * 0.65) * 0.7, speed = 1.1 })
			end)
		end
	end
	-- breathing when exhausted or terrified
	if State.status == "ALIVE" and (State.stamina < 35 or intensity > 0.5) and now - lastBreath > 2.4 then
		lastBreath = now
		AudioController:Play(if State.stamina < 15 or intensity > 0.7 then "BreathHeavy" else "Breath", nil, { volume = 0.8 })
	end
end

function AudioController:Init()
	SoundFactory.ensureGroups()
	task.spawn(SoundFactory.validate)
	duckValue.Changed:Connect(function(v)
		duck = v
		self:ApplyVolumes()
	end)
	State.SettingsChanged:Connect(function()
		self:ApplyVolumes()
	end)
end

function AudioController:Start()
	-- groups are created by the server too; wait briefly so we use the replicated ones
	task.wait(1)
	SoundFactory.ensureGroups()
	self:ApplyVolumes()
	for _, key in { "AmbientDrone", "AmbientAir", "AmbientHum", "AmbientRain", "Wind" } do
		bed(key)
	end
	Net.event("Sound").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.key) ~= "string" then
			return
		end
		self:Play(payload.key, payload.at, { volume = payload.volume, speed = payload.speed })
	end)
	local bodyAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		updateBeds(dt)
		bodyAcc += dt
		if bodyAcc > 0.1 then
			bodyAcc = 0
			updateBody()
		end
	end)
end

return AudioController
