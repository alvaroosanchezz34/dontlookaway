--[[
	PingService
	Text-first communication without voice: ANOMALY, COME HERE, DANGER, DOOR, ITEM.
	Validated (alive, cooldown, burst limit, distance, line of sight) and relayed
	to teammates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Pings = require(ReplicatedStorage.Shared.Catalog.Pings)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local PingService = {}

local history: { [Player]: { number } } = {}
local counter = 0

local function allowed(player: Player): boolean
	local now = os.clock()
	local h = history[player] or {}
	if #h > 0 and now - h[#h] < GameConfig.Ping.Cooldown then
		return false
	end
	local recent = 0
	for _, t in h do
		if now - t < GameConfig.Ping.BurstWindow then
			recent += 1
		end
	end
	if recent >= GameConfig.Ping.BurstLimit then
		return false
	end
	table.insert(h, now)
	while #h > 10 do
		table.remove(h, 1)
	end
	history[player] = h
	return true
end

local function onPing(player: Player, kind: any, position: any)
	if type(kind) ~= "string" or not Pings.List[kind] then
		return
	end
	if not Util.isFiniteVector(position) then
		return
	end
	if not Registry.PlayerService:IsAlive(player) then
		return
	end
	local head = Util.getHead(player)
	if not head then
		return
	end
	if (position - head.Position).Magnitude > GameConfig.Ping.MaxDistance then
		return
	end
	-- must be something the player can actually see
	local toward = position - head.Position
	if toward.Magnitude > 2 and not Registry.PlayerService:HasLineOfSight(head.Position, position - toward.Unit * 1.5) then
		return
	end
	if not allowed(player) then
		Net.fire(player, "Notify", { kind = "info", text = "Wait before pinging again." })
		return
	end
	counter += 1
	local payload = { id = "p" .. counter, kind = kind, position = position, from = player.DisplayName, userId = player.UserId, duration = GameConfig.Ping.Duration }
	local list = {}
	for _, p in Players:GetPlayers() do
		local status = Registry.PlayerService:GetStatus(p)
		if status == "ALIVE" or status == "DEAD" or status == "ESCAPED" then
			table.insert(list, p)
		end
	end
	Net.fireList(list, "PingShow", payload)
	Registry.ObserverService:OnPing(player, position)
end

-- A ping only one player sees, signed with someone else's name (the mimic).
function PingService:FakePing(viewer: Player, kind: string, position: Vector3, fromName: string, fromUserId: number)
	if not Pings.List[kind] then
		return
	end
	counter += 1
	Net.fire(viewer, "PingShow", { id = "p" .. counter, kind = kind, position = position, from = fromName, userId = fromUserId, duration = GameConfig.Ping.Duration })
end

function PingService:Init()
	Net.on("Ping", onPing)
end

function PingService:Start()
	Players.PlayerRemoving:Connect(function(player)
		history[player] = nil
	end)
end

return PingService
