--[[
	MatchService
	Lobby + matchmaking across two places (GameConfig.Places):
	  * lobby place: the Field Office for up to 30. When a countdown ends, the
	    ready players leave in groups of 1-MaxPlayers, each to its own reserved
	    server of the match place
	  * match place: waits for its group (ArrivalWait at most), plays one night,
	    then sends everyone back to the lobby place
	Every profile is saved and its session lock released right before a
	teleport (DataService:Release), so the next server loads it at once; a
	failed teleport takes the lock back (DataService:Reclaim).
	With either id at 0, in Studio, or in any other place: mode "single", one
	server does everything as before.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)

local MatchService = {}

local places = GameConfig.Places
local mode = "single"
if not RunService:IsStudio() and places.Lobby ~= 0 and places.Match ~= 0 then
	if game.PlaceId == places.Lobby then
		mode = "lobby"
	elseif game.PlaceId == places.Match then
		mode = "match"
	end
end

-- players on their way out, so nobody is sent twice
local leaving: { [Player]: boolean } = {}

function MatchService:IsLobby(): boolean
	return mode == "lobby"
end

function MatchService:IsMatch(): boolean
	return mode == "match"
end

function MatchService:IsLeaving(player: Player): boolean
	return leaving[player] == true
end

-- Groups of at most MaxPlayers, in the order given (the lobby's join order).
-- ponytail: no party/friends grouping, add it here if players ask for it
function MatchService.split(list: { any }, size: number): { { any } }
	local groups = {}
	for i, p in list do
		local g = math.ceil(i / size)
		groups[g] = groups[g] or {}
		table.insert(groups[g], p)
	end
	return groups
end

-- A player who could not leave. In the lobby they stay (lock taken back); a
-- match server only ever plays one night, so there they are asked to rejoin
-- (their profile is saved and released already, or saved again on leaving).
local function fail(p: Player, text: string)
	leaving[p] = nil
	if not p.Parent then
		return
	end
	if mode == "match" then
		p:Kick("The night is over. Join again to return to the Field Office.")
		return
	end
	task.spawn(function()
		Registry.DataService:Reclaim(p)
	end)
	Net.fire(p, "Notify", { kind = "danger", text = text })
end

-- Saves and releases every profile, then teleports. Anyone whose save failed
-- does not leave unsaved.
local function teleport(players: { Player }, placeId: number, options: TeleportOptions)
	local going = {}
	for _, p in players do
		if p.Parent and not leaving[p] then
			leaving[p] = true
			if Registry.DataService:Release(p) then
				table.insert(going, p)
			else
				fail(p, "Couldn't save your progress, so you stay here. Try again in a moment.")
			end
		end
	end
	if #going == 0 then
		return
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, going, options)
	end)
	if not ok then
		warn("[MatchService] teleport failed: " .. tostring(err))
		for _, p in going do
			fail(p, "The trip failed. Try again.")
		end
	end
end

-- Lobby place: one group to a fresh reserved match server.
function MatchService:SendGroup(players: { Player }, difficulty: string)
	local okReserve, code = pcall(function()
		return TeleportService:ReserveServer(places.Match)
	end)
	if not okReserve then
		warn("[MatchService] ReserveServer failed: " .. tostring(code))
		for _, p in players do
			Net.fire(p, "Notify", { kind = "danger", text = "No building is free right now. Try again." })
		end
		return
	end
	local party = {}
	for _, p in players do
		table.insert(party, p.UserId)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData({ difficulty = difficulty, party = party })
	for _, p in players do
		Net.fire(p, "Notify", { kind = "info", text = "On your way to the building…" })
	end
	teleport(players, places.Match, options)
end

-- Match place: everyone back to the lobby place.
function MatchService:ReturnHome(players: { Player })
	teleport(players, places.Lobby, Instance.new("TeleportOptions"))
end

-- Match place: wait for the group, then start the night.
local function runMatch()
	local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local data = first:GetJoinData().TeleportData
	local difficulty = if type(data) == "table" and GameConfig.Difficulty[data.difficulty] then data.difficulty else Enums.Difficulty.Normal
	local expected = if type(data) == "table" and type(data.party) == "table" then #data.party else 1
	local deadline = os.clock() + places.ArrivalWait
	local function arrived(): { Player }
		local list = {}
		for _, p in Players:GetPlayers() do
			if Registry.DataService:IsLoaded(p) then
				table.insert(list, p)
			end
		end
		return list
	end
	while #arrived() < expected and os.clock() < deadline do
		task.wait(0.5)
	end
	local list = arrived()
	if #list == 0 then
		return -- everyone left before the night began; the server closes empty
	end
	Registry.RoundService:StartRound(list, difficulty)
end

function MatchService:Start()
	Players.PlayerRemoving:Connect(function(player)
		leaving[player] = nil
	end)
	-- a teleport that fails after it started (the place is full, it timed out...)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if leaving[player] then
			warn(string.format("[MatchService] teleport of %s failed: %s %s", player.Name, tostring(result), tostring(message)))
			fail(player, "The trip failed. Try again.")
		end
	end)
	if mode == "match" then
		runMatch()
	end
end

return MatchService
