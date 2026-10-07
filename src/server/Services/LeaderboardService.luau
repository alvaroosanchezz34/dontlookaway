--[[
	LeaderboardService
	Keeps the Field Office wall boards up to date:
	  MOST ESCAPES     a global top 10 (OrderedDataStore). When DataStores are not
	                   available (Studio without API access) it shows the people
	                   on this server instead.
	  TONIGHT'S ORDERS today's daily challenges (the same draw for everyone)
	The boards are SurfaceGuis built by Map/Lobby; this service only writes text.
	Writes are throttled: a player's score is only written when it changed.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Challenges = require(ReplicatedStorage.Shared.Catalog.Challenges)
local Registry = require(script.Parent.Parent.Registry)

local LeaderboardService = {}

local STORE_NAME = "DLA_Escapes_v1"
local REFRESH = 150

local ordered: any = nil
local written: { [number]: number } = {}
local names: { [number]: string } = {}
local lastDay = -1

local function boards()
	local lobby = Registry.MapService:GetLobby()
	return lobby and lobby.Boards
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and type(name) == "string" then name else ("Investigator " .. tostring(userId % 10000))
	return names[userId]
end

local function row(rank: number, name: string, value: number): string
	local left = string.format("%2d. %s", rank, string.sub(name, 1, 20))
	local right = tostring(value)
	return left .. string.rep(" ", math.max(2, 32 - #left - #right)) .. right
end

local function renderRows(entries: { { name: string, value: number } }, footer: string?)
	local b = boards()
	if not b then
		return
	end
	local rows = b.Leaderboard.rows
	for i, label in rows do
		local e = entries[i]
		if e then
			label.Text = row(i, e.name, e.value)
		elseif i == #rows and footer then
			label.Text = footer
		else
			label.Text = ""
		end
	end
end

-- Top players on this server only (fallback).
local function localBoard()
	local entries = {}
	for _, p in Players:GetPlayers() do
		local d = Registry.DataService:Get(p)
		if d then
			table.insert(entries, { name = p.DisplayName, value = d.stats.escapes or 0 })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	renderRows(entries, "  (records offline: this server)")
end

local function pushScores()
	if not ordered then
		return
	end
	for _, p in Players:GetPlayers() do
		local d = Registry.DataService:Get(p)
		local escapes = d and d.stats.escapes or 0
		if d and escapes > 0 and written[p.UserId] ~= escapes then
			local ok = pcall(function()
				ordered:SetAsync(tostring(p.UserId), escapes)
			end)
			if ok then
				written[p.UserId] = escapes
			end
		end
	end
end

local function refreshGlobal()
	if not ordered then
		localBoard()
		return
	end
	pushScores()
	local ok, page = pcall(function()
		return ordered:GetSortedAsync(false, 10):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		localBoard()
		return
	end
	local entries = {}
	for _, entry in page do
		local id = tonumber(entry.key)
		if id then
			table.insert(entries, { name = nameOf(id), value = tonumber(entry.value) or 0 })
		end
	end
	renderRows(entries, nil)
end

local function refreshChallenges()
	local b = boards()
	if not b then
		return
	end
	local day = Challenges.dayKey()
	if day == lastDay then
		return
	end
	lastDay = day
	local list = Challenges.draw(Challenges.Daily, day, Challenges.PerDay)
	local rows = b.Challenges.rows
	for i, label in rows do
		local def = list[i]
		if def then
			label.Text = string.format("%d. %s   +%d", i, def.text, def.echoes)
		elseif i == #rows then
			label.Text = "Weekly orders: see the board's terminal."
		else
			label.Text = ""
		end
	end
end

function LeaderboardService:Refresh()
	refreshChallenges()
	refreshGlobal()
end

function LeaderboardService:Start()
	if not Registry.DataService:IsMock() then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(STORE_NAME)
		end)
		if ok then
			ordered = store
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		written[p.UserId] = nil
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			local ok, err = pcall(LeaderboardService.Refresh, LeaderboardService)
			if not ok then
				warn("[LeaderboardService] " .. tostring(err))
			end
			task.wait(REFRESH)
		end
	end)
	-- a quick local refresh whenever someone's record loads, so the board is never empty
	Registry.DataService.Loaded:Connect(function()
		if not ordered then
			task.defer(localBoard)
		end
	end)
end

return LeaderboardService
