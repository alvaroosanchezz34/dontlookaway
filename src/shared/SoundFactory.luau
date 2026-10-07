--[[
	SoundFactory
	Builds Sound instances from AudioLibrary entries (effects, groups, rolloff).
	Used by the server for world-anchored sounds and by clients for local audio.
]]

local SoundService = game:GetService("SoundService")

local AudioLibrary = require(script.Parent.Config.AudioLibrary)

local SoundFactory = {}

local random = Random.new()

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
	sound.SoundId = def.id
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
