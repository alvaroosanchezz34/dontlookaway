--[[
	AudioService (server)
	* creates the SoundGroups (replicated) so client volume settings can scale them
	* places world ambience emitters after each map build (boilers, servers, drips)
	* triggers positional or 2D sounds on clients (all or a subset), which keeps
	  identity sounds crisp and lets player-specific anomalies stay private
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)

local AudioService = {}

local function payload(key: string, at: any, opts: { [string]: any }?)
	return { key = key, at = at, volume = opts and opts.volume, speed = opts and opts.speed }
end

-- Positional sound for everyone. `at` is a Vector3 or an Instance.
function AudioService:PlayAt(key: string, at: Vector3 | Instance, opts: { [string]: any }?)
	Net.fireAll("Sound", payload(key, at, opts))
end

function AudioService:PlayAtFor(players: { Player }, key: string, at: Vector3 | Instance, opts: { [string]: any }?)
	Net.fireList(players, "Sound", payload(key, at, opts))
end

-- Non-positional (2D) sound for a player list.
function AudioService:Play2D(players: { Player }, key: string, opts: { [string]: any }?)
	Net.fireList(players, "Sound", payload(key, nil, opts))
end

function AudioService:Play2DAll(key: string, opts: { [string]: any }?)
	Net.fireAll("Sound", payload(key, nil, opts))
end

-- Creates a looping world sound owned by the server (replicates to everyone).
function AudioService:CreateLoop(key: string, parent: Instance, volume: number?): Sound?
	local sound = SoundFactory.create(key, parent, { volume = volume, looped = true })
	if sound then
		sound:Play()
	end
	return sound
end

-- Static ambience emitters for a freshly built map.
function AudioService:DecorateMap(map)
	local root = map.Root
	for _, src in CollectionService:GetTagged("SteamSource") do
		if src:IsDescendantOf(root) then
			self:CreateLoop("SteamHiss", src, 0.8)
		end
	end
	for _, boiler in root:GetDescendants() do
		if boiler:IsA("Model") and boiler.Name == "Boiler" then
			local tank = boiler:FindFirstChild("Tank")
			if tank then
				self:CreateLoop("BoilerRumble", tank)
			end
		end
	end
	for _, room in map.Rooms do
		if room.kind == "server" then
			local holder = room.floorParts[1]
			if holder then
				self:CreateLoop("ServerFans", holder, 0.9)
			end
		elseif room.kind == "maintenance" then
			local holder = room.floorParts[1]
			if holder then
				self:CreateLoop("ElectricBuzz", holder, 0.7)
			end
		elseif room.kind == "breakroom" then
			local holder = room.floorParts[1]
			if holder then
				self:CreateLoop("Fridge", holder)
			end
		end
	end
	-- dripping water in the basement
	for _, room in map.Rooms do
		if room.zone == "BASEMENT" and room.ceilingParts[1] and not room.secret then
			local s = SoundFactory.create("Drip", room.ceilingParts[1])
			if s then
				s.Looped = true
				s.PlaybackSpeed *= 0.35
				s.Volume *= 0.6
				s:Play()
			end
		end
	end
	-- clocks tick quietly
	for _, clock in CollectionService:GetTagged("Clock") do
		if clock:IsDescendantOf(root) then
			local face = clock:FindFirstChild("Face")
			if face then
				local tick = SoundFactory.create("ClockTick", face, { looped = true })
				if tick then
					tick.PlaybackSpeed = 0.5
					tick:Play()
				end
			end
		end
	end
end

function AudioService:Init()
	SoundFactory.ensureGroups()
end

return AudioService
