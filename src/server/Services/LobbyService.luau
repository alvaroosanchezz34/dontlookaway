--[[
	LobbyService
	Menu -> Lobby -> Round. Players press PLAY in the main menu to enter the
	Field Office (the lobby). Anyone can start: the first ready player starts a countdown,
	which shortens when everyone present is ready. The host (longest in the lobby)
	may change difficulty; NORMAL is the default, HARD unlocks after an escape.
	Joining mid-round puts you in the lobby to wait or spectate; a participant who
	disconnected and rejoins is put back into the round.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)

local LobbyService = {}

local Status = Enums.PlayerStatus

local order: { Player } = {}
local ready: { [Player]: boolean } = {}
local difficulty = Enums.Difficulty.Normal
local countdownEndsAt: number? = nil

local function lobbyPlayers(): { Player }
	local list = {}
	for _, p in order do
		if p.Parent and Registry.PlayerService:GetStatus(p) == Status.Lobby then
			table.insert(list, p)
		end
	end
	return list
end

local function host(): Player?
	return lobbyPlayers()[1]
end

-- HARD unlocks after a first escape, NIGHTMARE after an escape on HARD.
local function canUse(player: Player?, value: string): boolean
	if value == Enums.Difficulty.Normal then
		return true
	end
	if not player then
		return false
	end
	local data = Registry.DataService:Get(player)
	if not data then
		return false
	end
	if value == Enums.Difficulty.Hard then
		return data.flags.hardUnlocked == true
	end
	return data.flags.nightmareUnlocked == true
end

-- The hardest difficulty, from `wanted` down, that every player in `list` has
-- unlocked: a newcomer in a public server is never dragged into NIGHTMARE.
local DIFFICULTY_LADDER = { Enums.Difficulty.Nightmare, Enums.Difficulty.Hard, Enums.Difficulty.Normal }
local function bestFor(list: { Player }, wanted: string): string
	local from = table.find(DIFFICULTY_LADDER, wanted) or #DIFFICULTY_LADDER
	for i = from, #DIFFICULTY_LADDER do
		local value = DIFFICULTY_LADDER[i]
		local all = true
		for _, p in list do
			if not canUse(p, value) then
				all = false
				break
			end
		end
		if all then
			return value
		end
	end
	return Enums.Difficulty.Normal
end

function LobbyService:Broadcast()
	local list = {}
	local h = host()
	for _, p in lobbyPlayers() do
		local data = Registry.DataService:Get(p)
		table.insert(list, {
			userId = p.UserId,
			name = p.DisplayName,
			ready = ready[p] == true,
			host = p == h,
			title = p:GetAttribute("Title"),
			level = p:GetAttribute("Level"),
			escapes = data and data.stats.escapes or 0,
		})
	end
	local running = Registry.RoundService:IsRunning() or Registry.RoundService:GetState() == Enums.RoundState.Results
	Net.fireAll("LobbyState", {
		players = list,
		difficulty = difficulty,
		hardAvailable = canUse(h, Enums.Difficulty.Hard),
		nightmareAvailable = canUse(h, Enums.Difficulty.Nightmare),
		countdown = if countdownEndsAt then math.max(0, countdownEndsAt - os.clock()) else nil,
		roundRunning = running,
		roundElapsed = Registry.RoundService:GetElapsed(),
		hostUserId = h and h.UserId,
		maxPlayers = GameConfig.MaxPlayers,
	})
end

function LobbyService:SendToLobby(player: Player)
	local lobby = Registry.MapService:GetLobby()
	if not lobby then
		return
	end
	ready[player] = false
	if not table.find(order, player) then
		table.insert(order, player)
	end
	local index = (#lobbyPlayers() % #lobby.Spawns) + 1
	task.spawn(function()
		Registry.PlayerService:SpawnAt(player, lobby.Spawns[index])
		Registry.PlayerService:SetStatus(player, Status.Lobby)
		Registry.EconomyService:ApplyCosmetics(player)
		self:Broadcast()
	end)
end

local function startCountdown(seconds: number)
	local target = os.clock() + seconds
	if not countdownEndsAt or target < countdownEndsAt then
		countdownEndsAt = target
	end
end

local function onLobby(player: Player, action: any, value: any)
	if type(action) ~= "string" then
		return
	end
	local status = Registry.PlayerService:GetStatus(player)
	if action == "play" then
		if status ~= Status.Menu then
			return
		end
		Registry.AnalyticsService:Onboarding(player, 2, "PressedPlay")
		if Registry.RoundService:IsRunning() and Registry.RoundService:TryRejoin(player) then
			return
		end
		LobbyService:SendToLobby(player)
	elseif action == "ready" then
		if status ~= Status.Lobby or Registry.RoundService:GetState() ~= Enums.RoundState.Lobby or Registry.MatchService:IsLeaving(player) then
			return
		end
		ready[player] = value == true
		local anyReady = false
		for _, p in lobbyPlayers() do
			if ready[p] then
				anyReady = true
			end
		end
		if anyReady then
			startCountdown(GameConfig.Round.LobbyCountdown)
		else
			countdownEndsAt = nil
		end
		LobbyService:Broadcast()
	elseif action == "difficulty" then
		if player ~= host() or type(value) ~= "string" or not GameConfig.Difficulty[value] then
			return
		end
		if not canUse(player, value) then
			Net.fire(player, "Notify", { kind = "info", text = if value == Enums.Difficulty.Hard then "HARD unlocks after your first escape." else "NIGHTMARE unlocks after an escape on HARD." })
			return
		end
		difficulty = value
		LobbyService:Broadcast()
	elseif action == "invite" then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	elseif action == "menu" then
		if status == Status.Lobby then
			ready[player] = false
			Registry.PlayerService:RemoveCharacter(player)
			Registry.PlayerService:SetStatus(player, Status.Menu)
			LobbyService:Broadcast()
		end
	end
end

-- Field Office stations: kiosk kind -> menu panel and tab.
local STATIONS = {
	JOURNAL = { "JOURNAL", "ALL" },
	RECORD = { "JOURNAL", "RECORD" },
	ARCHIVE = { "JOURNAL", "ARCHIVE" },
	SHOP = { "SHOP", "EQUIPMENT" },
	SUPPLY = { "SHOP", "EQUIPMENT" },
	LOADOUT = { "SHOP", "LOADOUT" },
	COSMETICS = { "SHOP", "COSMETICS" },
	CHALLENGES = { "SHOP", "CHALLENGES" },
	TUTORIAL = { "HOWTO" },
}

local function onKiosk(player: Player, target: Instance): boolean
	local station = STATIONS[target:GetAttribute("Kiosk")]
	if station then
		Net.fire(player, "Effect", { name = "OpenPanel", panel = station[1], tab = station[2] })
		if station[1] == "SHOP" then
			Registry.AnalyticsService:Milestone(player, "SHOP_OPEN")
		end
		return true
	end
	return false
end

function LobbyService:Init()
	Net.on("Lobby", onLobby)
	Registry.InteractionService:Register("Kiosk", onKiosk)
end

function LobbyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local i = table.find(order, player)
		if i then
			table.remove(order, i)
		end
		ready[player] = nil
		task.defer(function()
			LobbyService:Broadcast()
		end)
	end)
	Registry.PlayerService.StatusChanged:Connect(function()
		LobbyService:Broadcast()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			-- a match server starts its one night itself (MatchService)
			if Registry.RoundService:GetState() == Enums.RoundState.Lobby and not Registry.MatchService:IsMatch() then
				local players = lobbyPlayers()
				local readyList = {}
				for _, p in players do
					if ready[p] then
						table.insert(readyList, p)
					end
				end
				if #readyList == 0 then
					countdownEndsAt = nil
				elseif #readyList == #players then
					startCountdown(GameConfig.Round.AllReadyCountdown)
				end
				if countdownEndsAt and os.clock() >= countdownEndsAt and #readyList > 0 then
					countdownEndsAt = nil
					if not canUse(host(), difficulty) then
						difficulty = Enums.Difficulty.Normal
					end
					for _, p in readyList do
						ready[p] = false
					end
					-- lobby place: groups of up to MaxPlayers, each to its own match server
					local match = Registry.MatchService
					local groups = if match:IsLobby() then match.split(readyList, GameConfig.MaxPlayers) else { readyList }
					for _, group in groups do
						local chosen = bestFor(group, difficulty)
						if chosen ~= difficulty then
							for _, p in group do
								Net.fire(p, "Notify", { kind = "info", text = "Tonight runs on " .. chosen .. ": not everyone has unlocked " .. difficulty .. " yet." })
							end
						end
						task.spawn(function()
							if match:IsLobby() then
								match:SendGroup(group, chosen)
							else
								Registry.RoundService:StartRound(group, chosen)
							end
						end)
					end
				end
				LobbyService:Broadcast()
			end
		end
	end)
end

return LobbyService
