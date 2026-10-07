--[[
	AudioController
	* volume settings per category (SoundGroups)
	* server-triggered sounds (positional or 2D)
	* ambient beds that crossfade between outside / building / basement / lobby
	* dynamic silence: the director can duck the world before something happens
	* body sounds: heartbeat and breathing driven by fear, stamina and the
	  Observer's proximity
	* the building reacts: ventilation and electrical hum die with the power,
	  emergency alarms sound during major blackouts, and everything drains away
	  as The Observer gets close (silence is the loudest warning)
	* personal distant sounds placed around the listener in 3D (something
	  settling behind you, a radio two rooms away, steps on another floor)
	* accessibility: captions for meaningful sounds and on-screen direction
	  indicators (Settings > Audio indicators)
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
local Registry = require(script.Parent.Parent.Registry)

local AudioController = {}

local beds: { [string]: Sound } = {}
local bedTargets: { [string]: number } = {}
local duck = 1 -- 0..1 multiplier on the ambient group (silence)
local duckTween: Tween? = nil
local duckValue = Instance.new("NumberValue")
duckValue.Value = 1
local lastHeartbeat = 0
local lastBreath = 0
local nextDistantAt = 0
local random = Random.new()

-- Meaningful sounds get a caption (when subtitles are on) and an on-screen
-- direction indicator (when audio indicators are on).
local CAPTIONS = {
	DoorSlam = "door slams",
	KnockDoor = "knocking",
	ObserverStep = "heavy footsteps",
	ObserverAppear = "something arrives",
	ObserverScreech = "a shriek",
	ObserverInhale = "a slow breath",
	ObserverCrack = "joints cracking",
	Whisper = "whispering",
	PhoneRing = "phone ringing",
	FootstepsBehind = "footsteps behind you",
	DistantGroan = "a distant groan",
	DistantFootsteps = "distant footsteps",
	DistantRadio = "radio static",
	Thud = "a heavy thud",
	BulbPop = "a bulb bursts",
	BoardsBreak = "wood splinters",
	MusicBox = "a music box",
	Falsetto = "someone humming",
	BreathingCloset = "breathing",
	ShutterOpen = "the shutter opens",
	PowerDown = "the power fails",
	ElectricSurge = "electricity crackles",
	EmergencyAlarm = "emergency alarm",
	ElevatorGroan = "cables groan",
	MotionAlert = "motion sensor",
}
local lastCaption: { [string]: number } = {}

local DISTANT = { "BuildingSettle", "ElevatorGroan", "DistantRadio", "BuildingSettle", "DistantFootsteps", "WoodCreak", "DistantPipe" }

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
	if typeof(at) == "Vector3" or (typeof(at) == "Instance" and at:IsA("BasePart")) then
		local position = if typeof(at) == "Vector3" then at else (at :: BasePart).Position
		AudioController:Describe(key, position)
	elseif at == nil and (key == "PowerDown" or key == "ElectricSurge") then
		AudioController:Describe(key, nil)
	end
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

-- Captions and direction indicators for a sound the player should know about.
function AudioController:Describe(key: string, position: Vector3?)
	local text = CAPTIONS[key]
	if not text or State.status ~= "ALIVE" then
		return
	end
	local camera = Workspace.CurrentCamera
	if position and camera and (position - camera.CFrame.Position).Magnitude > 70 then
		return
	end
	local now = os.clock()
	if lastCaption[key] and now - lastCaption[key] < 2.5 then
		return
	end
	lastCaption[key] = now
	local hud = Registry.HUDController
	if not hud or not hud.Caption then
		return
	end
	local direction = ""
	if position and camera then
		local rel = camera.CFrame:PointToObjectSpace(position)
		if rel.Z > 0 and math.abs(rel.X) < rel.Z then
			direction = "behind"
		elseif rel.X > 4 then
			direction = "right"
		elseif rel.X < -4 then
			direction = "left"
		elseif position.Y - camera.CFrame.Position.Y > 8 then
			direction = "above"
		elseif position.Y - camera.CFrame.Position.Y < -8 then
			direction = "below"
		end
	end
	if State.settings.subtitles then
		hud:Caption("[" .. text .. (if direction ~= "" then ", " .. direction else "") .. "]", 2.4, "sound")
	end
	if State.settings.audioIndicators and position then
		hud:SoundIndicator(position, text)
	end
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
	lobby = { AmbientRain = 0.25, AmbientAir = 0.2, AmbientHum = 0.3 },
	outside = { AmbientRain = 1, Wind = 0.9, AmbientDrone = 0.25 },
	building = { AmbientDrone = 0.8, AmbientAir = 0.7, AmbientHum = 0.5, AmbientRain = 0.18, Ventilation = 0.7, EmergencyAlarm = 1 },
	basement = { AmbientDrone = 1, AmbientAir = 0.4, AmbientHum = 0.25, Ventilation = 0.4, EmergencyAlarm = 0.7 },
}

-- beds that only exist while the building has power
local POWERED_BEDS = { AmbientHum = true, Ventilation = true }

local function updateBeds(dt: number)
	local z = zone()
	local inMenu = State.status == "MENU"
	local mix = MIX[z] or {}
	local inRound = State.round.state ~= "LOBBY" and z ~= "lobby"
	local power = workspace:GetAttribute("Power") == true
	local blackout = workspace:GetAttribute("Blackout")
	blackout = if type(blackout) == "number" then blackout else 0
	local observer = State.observerDistance
	for key, sound in beds do
		local target = mix[key] or 0
		if inMenu then
			target *= 0.7
		end
		if inRound and POWERED_BEDS[key] and (not power or blackout >= 3) then
			target *= 0.05
		elseif inRound and POWERED_BEDS[key] and blackout >= 1 then
			target *= 0.5
		end
		if key == "EmergencyAlarm" then
			target *= if inRound and (blackout >= 3 or workspace:GetAttribute("Escape") == true) then 1 else 0
		elseif key == "AmbientDrone" and inRound and (not power or blackout >= 2) then
			target *= 1.25
		end
		-- the world holds its breath as The Observer gets close
		if key ~= "EmergencyAlarm" and observer < 40 and State.status == "ALIVE" then
			target *= 0.25 + 0.75 * (observer / 40)
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

-- Personal sounds placed around the listener so the building feels alive in 3D.
local function distantLife()
	local now = os.clock()
	if State.status ~= "ALIVE" or now < nextDistantAt then
		return
	end
	nextDistantAt = now + random:NextNumber(14, 34)
	local z = zone()
	if z ~= "building" and z ~= "basement" then
		return
	end
	if State.observerDistance < 50 then
		return
	end
	local camera = Workspace.CurrentCamera
	local angle = random:NextNumber(0, math.pi * 2)
	local dist = random:NextNumber(22, 55)
	local pos = camera.CFrame.Position + Vector3.new(math.cos(angle) * dist, random:NextNumber(-10, 12), math.sin(angle) * dist)
	local key = DISTANT[random:NextInteger(1, #DISTANT)]
	if key == "DistantRadio" and random:NextNumber() < 0.5 then
		key = "BuildingSettle"
	end
	AudioController:Play(key, pos)
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
	for _, key in { "AmbientDrone", "AmbientAir", "AmbientHum", "AmbientRain", "Wind", "Ventilation", "EmergencyAlarm" } do
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
			distantLife()
		end
	end)
end

return AudioController
