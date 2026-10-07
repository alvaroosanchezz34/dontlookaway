--[[
	MusicController
	Original, generative score. No music track is ever looped: phrases are
	composed at runtime from a few instruments (bell, low tone, pulse, pads,
	strings) on a minor pentatonic scale, so the score is copyright free and
	never repeats. States: MENU, EXPLORATION, TENSION, CHASE, ESCAPE, DEATH,
	RESULTS. Long stretches of silence are part of the composition.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)
local AudioLibrary = require(ReplicatedStorage.Shared.Config.AudioLibrary)
local State = require(script.Parent.Parent.State)

local MusicController = {}

local SCALE = { 0, 3, 5, 7, 10, 12, 15 }
local random = Random.new()

local current = "NONE"
local forced: string? = nil
local forcedUntil = 0
local pads: { [string]: Sound } = {}
local enteredAt = os.clock()

local function semitone(n: number): number
	return 2 ^ (n / 12)
end

local function note(key: string, semis: number, volume: number?)
	local def = AudioLibrary.Sounds[key]
	local base = def and (type(def.speed) == "number" and def.speed or 1) or 1
	local sound = SoundFactory.create(key, SoundService, { volume = volume or 1 })
	if not sound then
		return
	end
	sound.PlaybackSpeed = base * semitone(semis)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function padTo(key: string, volume: number, time: number?)
	local pad = pads[key]
	if not pad then
		return
	end
	local def = AudioLibrary.Sounds[key]
	TweenService:Create(pad, TweenInfo.new(time or 3, Enum.EasingStyle.Sine), { Volume = (def and def.volume or 0.3) * volume }):Play()
end

local PAD_MIX = {
	NONE = { MusicPad = 0, MusicChasePad = 0 },
	MENU = { MusicPad = 0.7, MusicChasePad = 0 },
	EXPLORATION = { MusicPad = 0.22, MusicChasePad = 0 },
	TENSION = { MusicPad = 0.45, MusicChasePad = 0.15 },
	CHASE = { MusicPad = 0.2, MusicChasePad = 0.85 },
	ESCAPE = { MusicPad = 0.4, MusicChasePad = 1 },
	DEATH = { MusicPad = 0, MusicChasePad = 0 },
	RESULTS = { MusicPad = 0.6, MusicChasePad = 0 },
}

local function setState(s: string)
	if s == current then
		return
	end
	current = s
	enteredAt = os.clock()
	local mix = PAD_MIX[s] or PAD_MIX.NONE
	for key, v in mix do
		padTo(key, v, if s == "CHASE" or s == "DEATH" then 1.2 else 4)
	end
	if s == "DEATH" then
		note("MusicLow", -12, 1.4)
		note("MusicString", -5, 1.2)
	end
end

-- Force a state briefly (death sting, escape).
function MusicController:Force(s: string, duration: number)
	forced = s
	forcedUntil = os.clock() + duration
	setState(s)
end

function MusicController:GetState(): string
	return current
end

local function decide(): string
	if forced and os.clock() < forcedUntil then
		return forced
	end
	forced = nil
	local round = State.round.state
	if State.status == "MENU" then
		return "MENU"
	end
	if round == "RESULTS" or round == "RETURNING" then
		return "RESULTS"
	end
	if State.status == "LOBBY" or State.status == "WAITING" then
		return "MENU"
	end
	if round == "ESCAPE" then
		return "ESCAPE"
	end
	if State.status ~= "ALIVE" then
		return "EXPLORATION"
	end
	local observerState = workspace:GetAttribute("ObserverState")
	if (observerState == "HUNTING" or observerState == "MOVING" or observerState == "WATCHED" or observerState == "ATTACKING") and State.observerDistance < 80 then
		return "CHASE"
	end
	if State.phase == "TENSION" or State.phase == "FEAR" then
		return "TENSION"
	end
	if State.phase == "RELIEF" then
		return "NONE"
	end
	return "EXPLORATION"
end

-- One "bar" of generative music for the current state. Returns seconds to wait.
local function compose(): number
	local s = current
	if s == "MENU" then
		note("MusicBell", SCALE[random:NextInteger(1, #SCALE)] + random:NextInteger(0, 1) * 12, 0.8)
		if random:NextNumber() < 0.3 then
			note("MusicLow", SCALE[random:NextInteger(1, 4)] - 12, 0.6)
		end
		return random:NextNumber(2.4, 4.8)
	elseif s == "EXPLORATION" then
		-- a short phrase, then a long silence
		if os.clock() - enteredAt < 6 then
			return 2
		end
		local count = random:NextInteger(2, 4)
		local root = SCALE[random:NextInteger(1, 4)]
		for i = 1, count do
			task.delay((i - 1) * random:NextNumber(1.1, 1.9), function()
				if current == "EXPLORATION" then
					note("MusicBell", root + SCALE[random:NextInteger(1, #SCALE)] - (if i == count then 12 else 0), 0.55)
				end
			end)
		end
		return random:NextNumber(24, 44)
	elseif s == "TENSION" then
		note("MusicPulse", -12, 0.5)
		if random:NextNumber() < 0.3 then
			note("MusicLow", random:NextInteger(0, 1) - 12, 0.7)
		end
		if random:NextNumber() < 0.12 then
			note("MusicString", 0, 0.7)
		end
		return 1.25
	elseif s == "CHASE" then
		note("MusicPulse", -12, 0.9)
		task.delay(0.22, function()
			if current == "CHASE" then
				note("MusicPulse", -12, 0.55)
			end
		end)
		if random:NextNumber() < 0.25 then
			note("MusicLow", 1 - 12, 0.8)
		end
		return 0.72
	elseif s == "ESCAPE" then
		local t = os.clock() - enteredAt
		note("MusicPulse", -12 + math.min(5, math.floor(t / 25)), 1)
		if random:NextNumber() < 0.35 then
			note("MusicBell", SCALE[random:NextInteger(3, #SCALE)], 0.6)
		end
		return math.max(0.32, 0.55 - t / 400)
	elseif s == "RESULTS" then
		note("MusicBell", SCALE[random:NextInteger(1, #SCALE)], 0.6)
		return random:NextNumber(3, 5.5)
	end
	return 1
end

function MusicController:Start()
	task.wait(1.2)
	for _, key in { "MusicPad", "MusicChasePad" } do
		local s = SoundFactory.create(key, SoundService, { looped = true })
		if s then
			s.Volume = 0
			s:Play()
			pads[key] = s
		end
	end
	task.spawn(function()
		while true do
			setState(decide())
			local wait = compose()
			local waited = 0
			while waited < wait do
				task.wait(0.25)
				waited += 0.25
				local d = decide()
				if d ~= current then
					break
				end
			end
		end
	end)
end

return MusicController
