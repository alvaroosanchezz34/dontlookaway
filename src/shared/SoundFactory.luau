--[[
	SoundFactory
	Builds Sound instances from AudioLibrary entries (effects, groups, rolloff).
	Used by the server for world-anchored sounds and by clients for local audio.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local AudioLibrary = require(script.Parent.Config.AudioLibrary)

local SoundFactory = {}

local random = Random.new()

-- Built-in sound files differ between client builds. Any id that fails to load is
-- remapped to this one, which every Roblox client ships (default character sounds).
local FALLBACK_ID = "rbxasset://sounds/action_footsteps_plastic.mp3"
local failed: { [string]: boolean } = {}

function SoundFactory.resolve(id: string): string
	return if failed[id] then FALLBACK_ID else id
end

-- Preloads every id in the library; failures are remapped and any existing
-- sounds using them are swapped in place. Safe to call on server and client.
function SoundFactory.validate()
	local ids = {}
	local seen = {}
	for _, def in AudioLibrary.Sounds do
		if def.id and not seen[def.id] then
			seen[def.id] = true
			local probe = Instance.new("Sound")
			probe.SoundId = def.id
			table.insert(ids, probe)
		end
	end
	local newlyFailed = {}
	pcall(function()
		ContentProvider:PreloadAsync(ids, function(contentId, status)
			if status == Enum.AssetFetchStatus.Failure and contentId ~= FALLBACK_ID then
				failed[contentId] = true
				newlyFailed[contentId] = true
			end
		end)
	end)
	for _, probe in ids do
		probe:Destroy()
	end
	if next(newlyFailed) then
		-- sounds created elsewhere (e.g. replicated from the server) are fixed on arrival
		workspace.DescendantAdded:Connect(function(d)
			if d:IsA("Sound") and failed[d.SoundId] then
				d.SoundId = FALLBACK_ID
			end
		end)
		for _, d in game:GetDescendants() do
			local ok, isSound = pcall(function()
				return d:IsA("Sound") and newlyFailed[(d :: Sound).SoundId] == true
			end)
			if ok and isSound then
				pcall(function()
					(d :: Sound).SoundId = FALLBACK_ID
				end)
			end
		end
	end
end

function SoundFactory.getGroup(name: string): SoundGroup?
	return SoundService:FindFirstChild(name) :: SoundGroup?
end

function SoundFactory.ensureGroups()
	for _, name in AudioLibrary.Groups do
		if not SoundService:FindFirstChild(name) then
			local g = Instance.new("SoundGroup")
			g.Name = name
			g.Volume = 1
			g.Parent = SoundService
		end
	end
end

function SoundFactory.speedOf(def): number
	local speed = def.speed or 1
	if type(speed) == "table" then
		return random:NextNumber(speed[1], speed[2])
	end
	return speed
end

-- Creates (but does not play) a sound for `key`. opts: volume, speed, looped, parent
function SoundFactory.create(key: string, parent: Instance?, opts: { [string]: any }?): Sound?
	local def = AudioLibrary.Sounds[key]
	if not def then
		warn("[SoundFactory] unknown sound", key)
		return nil
	end
	opts = opts or {}
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = SoundFactory.resolve(def.id)
	sound.Volume = (def.volume or 0.5) * (opts.volume or 1)
	sound.PlaybackSpeed = SoundFactory.speedOf(def) * (opts.speed or 1)
	sound.Looped = if opts.looped ~= nil then opts.looped else (def.looped == true)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = def.min or 6
	sound.RollOffMaxDistance = def.max or 80
	sound.SoundGroup = SoundFactory.getGroup(def.group or "Interaction")
	if def.effects then
		for i, effect in def.effects do
			local ok, instance = pcall(Instance.new, effect[1])
			if ok and instance then
				for prop, value in effect[2] do
					pcall(function()
						(instance :: any)[prop] = value
					end)
				end
				;(instance :: any).Priority = i
				instance.Parent = sound
			end
		end
	end
	sound.Parent = parent
	return sound
end

return SoundFactory
