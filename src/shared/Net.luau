--[[
	Net
	Declares every remote in the game in one place. The server creates them, the
	client waits for them. Server handlers are wrapped with per-player rate limiting
	and error isolation so a malformed or spammed request can never break a service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- name = { rate = max calls per second (token bucket), burst = bucket size }
Net.Events = {
	-- client -> server
	LookUpdate = { rate = 12, burst = 16 },
	Interact = { rate = 8, burst = 10 },
	Report = { rate = 2, burst = 3 },
	Flashlight = { rate = 4, burst = 6 },
	Ping = { rate = 1, burst = 3 },
	Inventory = { rate = 6, burst = 8 },
	Puzzle = { rate = 8, burst = 12 },
	Lobby = { rate = 4, burst = 8 },
	Shop = { rate = 3, burst = 6 },
	Settings = { rate = 1, burst = 4 },
	Emote = { rate = 1, burst = 2 },
	Admin = { rate = 6, burst = 10 },
	Movement = { rate = 6, burst = 10 },
	ClientFlag = { rate = 2, burst = 6 },

	-- server -> client
	RoundState = {},
	Notify = {},
	Objective = {},
	InventoryState = {},
	Reality = {},
	Sound = {},
	Director = {},
	Effect = {},
	Death = {},
	Results = {},
	PingShow = {},
	Profile = {},
	Unlock = {},
	Caption = {},
	AdminData = {},
	PuzzleState = {},
	Document = {},
	PlayerStates = {},
	LobbyState = {},
}

Net.Functions = {
	GetProfile = { rate = 2, burst = 4 },
	GetShop = { rate = 2, burst = 4 },
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local cache: { [string]: Instance } = {}

local function get(name: string, className: string): any
	local existing = cache[name]
	if existing then
		return existing
	end
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name, 30)
			if not remote then
				error("[Net] remote missing: " .. name)
			end
		end
	end
	cache[name] = remote
	return remote
end

function Net.event(name: string): RemoteEvent
	assert(Net.Events[name], "[Net] unknown event " .. name)
	return get(name, "RemoteEvent")
end

function Net.func(name: string): RemoteFunction
	assert(Net.Functions[name], "[Net] unknown function " .. name)
	return get(name, "RemoteFunction")
end

-- Server: create every remote up front so clients never wait on lazily created ones.
function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	for name in Net.Events do
		get(name, "RemoteEvent")
	end
	for name in Net.Functions do
		get(name, "RemoteFunction")
	end
end

-- Token bucket rate limiting -----------------------------------------------------

local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}
local violationCallback: ((Player, string) -> ())? = nil

function Net.onViolation(callback: (Player, string) -> ())
	violationCallback = callback
end

local function allow(player: Player, name: string, spec): boolean
	local rate = spec.rate or 10
	local burst = spec.burst or rate
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		if violationCallback then
			violationCallback(player, name)
		end
		return false
	end
	bucket.tokens -= 1
	return true
end

function Net.clearPlayer(player: Player)
	buckets[player] = nil
end

-- Server: connect a rate limited, error isolated handler.
function Net.on(name: string, handler: (Player, ...any) -> ())
	local spec = Net.Events[name]
	Net.event(name).OnServerEvent:Connect(function(player, ...)
		if not allow(player, name, spec) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s handler error for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

function Net.handle(name: string, handler: (Player, ...any) -> any)
	local spec = Net.Functions[name]
	Net.func(name).OnServerInvoke = function(player, ...)
		if not allow(player, name, spec) then
			return nil
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s invoke error for %s: %s", name, player.Name, tostring(result)))
			return nil
		end
		return result
	end
end

function Net.fire(player: Player, name: string, ...)
	Net.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...)
	Net.event(name):FireAllClients(...)
end

function Net.fireList(players: { Player }, name: string, ...)
	local remote = Net.event(name)
	for _, player in players do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

return Net
