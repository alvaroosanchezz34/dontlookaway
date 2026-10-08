--[[
	MarketingAudio
	Scene sound, built on the game's own SoundFactory and its 99 original
	sounds (AudioLibrary keys: "DoorOpen", "Whisper", "ObserverSting", ...).
	A sound can also be a raw "rbxassetid://..." you own.

	Each sound: Volume, PlaybackSpeed, StartTime (seconds into the sound),
	Duration, FadeIn, FadeOut, Loop, and a position (3D) or none (2D).
	Scene sounds play in their own SoundGroup, so the game's mix (ducking,
	settings) never touches them; "MuteGameAudio" silences the game's groups
	for the length of the scene and gives them back afterwards.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Runtime = require(script.Parent.Parent.Runtime)

local MarketingAudio = {}

type Entry = { sound: Sound, base: number, name: string }

local playing: { Entry } = {}
local named: { [string]: Entry } = {}
local group: SoundGroup? = nil
local speedScale = 1
local factory: any = nil

local function soundFactory()
	if factory == nil then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundFactory")) :: any
		end)
		factory = if ok then mod else false
	end
	return factory or nil
end

local function marketingGroup(): SoundGroup
	if not group or not group.Parent then
		local g = Instance.new("SoundGroup")
		g.Name = "MarketingAudio"
		g.Volume = 1
		g.Parent = SoundService
		group = Runtime.track(g)
	end
	return group :: SoundGroup
end

function MarketingAudio.reset()
	table.clear(playing)
	table.clear(named)
	group = nil
	speedScale = 1
end

--[[
	opts: { at = Vector3?, volume, speed, startTime, duration, fadeIn, fadeOut,
	        loop, name } ; `tl` is the scene timeline (fades follow its clock)
]]
function MarketingAudio.play(tl: any, key: string, opts: { [string]: any }?): Sound?
	opts = opts or {}
	local parent: Instance = marketingGroup()
	if typeof(opts.at) == "Vector3" then
		local holder = Instance.new("Part")
		holder.Name = "Emitter_" .. key
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Position = opts.at
		holder.Parent = Runtime.folder()
		parent = holder
	end
	local sound: Sound? = nil
	local sf = soundFactory()
	if string.find(key, "rbxassetid://", 1, true) == 1 then
		local s = Instance.new("Sound")
		s.SoundId = key
		s.Volume = 0.6 * (opts.volume or 1)
		s.PlaybackSpeed = opts.speed or 1
		s.Looped = opts.loop == true
		s.Parent = parent
		sound = s
	elseif sf then
		sound = sf.create(key, parent, { volume = opts.volume, speed = opts.speed, looped = opts.loop })
	end
	if not sound then
		return nil
	end
	local s = sound :: Sound
	s.SoundGroup = marketingGroup()
	if s.Parent == nil then
		s.Parent = parent
	end
	if parent == (marketingGroup() :: Instance) then
		Runtime.track(s)
	end
	local base = s.Volume
	local entry: Entry = { sound = s, base = base, name = opts.name or key }
	table.insert(playing, entry)
	if opts.name then
		named[opts.name] = entry
	end
	s.PlaybackSpeed *= speedScale
	-- start offset (inside a sheet region, if the sound is one)
	if opts.startTime and opts.startTime > 0 then
		local start = if s.PlaybackRegionsEnabled then s.PlaybackRegion.Min else 0
		s.TimePosition = start + opts.startTime
	end
	local fadeIn = opts.fadeIn or 0
	if fadeIn > 0 and tl then
		s.Volume = 0
		tl:span(fadeIn, "inOutSine", function(a)
			s.Volume = base * a
		end)
	end
	s:Play()
	if opts.duration and tl then
		local fadeOut = opts.fadeOut or 0
		tl:span(opts.duration, "linear", function(a)
			if a >= 1 then
				MarketingAudio.stopEntry(tl, entry, fadeOut)
			end
		end)
	end
	return s
end

function MarketingAudio.stopEntry(tl: any, entry: Entry, fadeOut: number?)
	local s = entry.sound
	if (entry :: any).stopping then
		return
	end
	(entry :: any).stopping = true
	local function kill()
		if s.Parent then
			s:Stop()
			local holder = s.Parent
			if holder and holder:IsA("BasePart") then
				holder:Destroy()
			else
				s:Destroy()
			end
		end
		local i = table.find(playing, entry)
		if i then
			table.remove(playing, i)
		end
		if named[entry.name] == entry then
			named[entry.name] = nil
		end
	end
	if fadeOut and fadeOut > 0 and tl then
		local from = s.Volume
		tl:span(fadeOut, "inOutSine", function(a)
			if not s.Parent then
				return
			end
			s.Volume = from * (1 - a)
			if a >= 1 then
				kill()
			end
		end)
	else
		kill()
	end
end

-- Stop by name (or every sound when name is nil).
function MarketingAudio.stop(tl: any, name: string?, fadeOut: number?)
	if name then
		local entry = named[name]
		if entry then
			MarketingAudio.stopEntry(tl, entry, fadeOut)
		end
		return
	end
	for i = #playing, 1, -1 do
		MarketingAudio.stopEntry(tl, playing[i], fadeOut)
	end
end

function MarketingAudio.pauseAll()
	for _, e in playing do
		if not (e :: any).paused then
			(e :: any).paused = true
			pcall(function()
				e.sound:Pause()
			end)
		end
	end
end

function MarketingAudio.resumeAll()
	for _, e in playing do
		if (e :: any).paused then
			(e :: any).paused = nil
			pcall(function()
				e.sound:Resume()
			end)
		end
	end
end

-- Slow motion: every scene sound follows the scene's time scale.
function MarketingAudio.setSpeedScale(scale: number)
	local ratio = scale / speedScale
	speedScale = scale
	for _, e in playing do
		e.sound.PlaybackSpeed *= ratio
	end
end

-- Silence the game's own audio (every SoundGroup but ours) for the scene.
function MarketingAudio.muteGame(tl: any, fade: number?)
	local groups = {}
	for _, g in SoundService:GetChildren() do
		if g:IsA("SoundGroup") and g.Name ~= "MarketingAudio" then
			table.insert(groups, { g = g, from = g.Volume })
		end
	end
	local function set(a: number)
		for _, e in groups do
			Runtime.setProp(e.g, "Volume", e.from * (1 - a))
		end
	end
	if fade and fade > 0 and tl then
		tl:span(fade, "inOutSine", set)
	else
		set(1)
	end
end

-- The scene's own mix dips to `level` (0 = silence, 1 = back).
function MarketingAudio.duck(tl: any, level: number, fade: number?)
	local g = marketingGroup()
	local from = g.Volume
	if tl and fade and fade > 0 then
		tl:span(fade, "inOutSine", function(a)
			g.Volume = from + (level - from) * a
		end, nil, "audio.duck")
	else
		g.Volume = level
	end
end

function MarketingAudio.count(): number
	return #playing
end

return MarketingAudio
