--[[
	AdminService
	Private owner tools. Authorization is decided ONLY here, from the UserId:
	  * the place creator (user-owned places)
	  * the group owner (rank 255) for group-owned places
	  * GameConfig.AdminUserIds
	  * anyone in Roblox Studio (local testing)
	Non-admins never receive admin data and every command is re-checked.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)

local AdminService = {}

local admins: { [Player]: boolean } = {}
local logs: { string } = {}
local MAX_LOGS = 250

function AdminService:Log(text: string)
	table.insert(logs, string.format("[%s] %s", os.date("!%H:%M:%S"), text))
	if #logs > MAX_LOGS then
		table.remove(logs, 1)
	end
end

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(GameConfig.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		-- the group's owner is an admin
		local ok, info = pcall(function()
			return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId)
		end)
		if ok and type(info) == "table" and type(info.Owner) == "table" and info.Owner.Id == player.UserId then
			return true
		end
	end
	return false
end

function AdminService:IsAdmin(player: Player): boolean
	return admins[player] == true
end

local function snapshot()
	local players = {}
	for _, p in Players:GetPlayers() do
		local root = Util.getRoot(p)
		local map = Registry.MapService:GetMap()
		local room = root and map and map:roomAt(root.Position)
		table.insert(players, {
			name = p.Name,
			userId = p.UserId,
			status = Registry.PlayerService:GetStatus(p),
			room = room and room.name or "-",
			battery = math.floor(Registry.InventoryService:GetBattery(p)),
			light = Registry.InventoryService:IsLightOn(p),
		})
	end
	local active = {}
	for id, inst in Registry.AnomalyService:GetActive() do
		table.insert(active, { id = id, scope = inst.scope, remaining = math.floor(inst.expiresAt - os.clock()), players = #inst.players })
	end
	local objective = Registry.ObjectiveService:GetState()
	return {
		round = Registry.RoundService:GetState(),
		seed = Registry.RoundService:GetSeed(),
		mapSeed = workspace:GetAttribute("MapSeed"),
		difficulty = Registry.RoundService:GetDifficulty(),
		elapsed = math.floor(Registry.RoundService:GetElapsed()),
		phase = Registry.HorrorDirector:GetPhase(),
		story = Registry.HorrorDirector:GetStoryPhase(),
		guidance = Registry.GuidanceService:GetLevel(),
		blackout = Registry.LightingService:GetBlackout(),
		power = Registry.LightingService:IsPowered(),
		dread = math.floor(Registry.HorrorDirector:GetDread()),
		observer = Registry.ObserverService:GetState(),
		observerMode = Registry.ObserverService:GetMode(),
		players = players,
		active = active,
		stats = Registry.AnomalyService:GetRoundStats() and {
			spawned = Registry.AnomalyService:GetRoundStats().spawned,
			found = Registry.AnomalyService:GetRoundStats().found,
			missed = Registry.AnomalyService:GetRoundStats().missed,
		},
		objective = objective and { puzzles = objective.puzzles, locks = objective.locks, quota = objective.quota, found = objective.found, code = objective.code } or nil,
		analytics = Registry.AnalyticsService:GetAggregates(),
		logs = table.move(logs, math.max(1, #logs - 60), #logs, 1, {}),
		anomalyIds = (function()
			local ids = {}
			for _, e in JournalCatalog.List do
				table.insert(ids, e.id)
			end
			return ids
		end)(),
		dataMock = Registry.DataService:IsMock(),
	}
end

local function findPlayer(userId: any): Player?
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local COMMANDS = {}

COMMANDS.refresh = function() end

COMMANDS.startRound = function(admin)
	if Registry.RoundService:GetState() ~= Enums.RoundState.Lobby then
		return "a round is already running"
	end
	local list = {}
	for _, p in Players:GetPlayers() do
		local s = Registry.PlayerService:GetStatus(p)
		if s == Enums.PlayerStatus.Lobby then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		list = { admin }
	end
	task.spawn(function()
		Registry.RoundService:StartRound(list, Registry.RoundService:GetDifficulty())
	end)
	return "starting round with " .. #list .. " player(s)"
end

COMMANDS.endRound = function()
	Registry.RoundService:ForceEnd()
	return "round ended"
end

COMMANDS.resetRound = function(admin)
	Registry.RoundService:ForceEnd()
	task.delay(Registry.RoundService:GetState() == Enums.RoundState.Lobby and 0.5 or 6, function()
		COMMANDS.startRound(admin)
	end)
	return "resetting round"
end

COMMANDS.forceAnomaly = function(_admin, id)
	if type(id) ~= "string" or not JournalCatalog.ById[id] then
		return "unknown anomaly"
	end
	if not Registry.AnomalyService:IsEnabled() then
		return "no round running"
	end
	local inst = Registry.AnomalyService:TrySpawn(id, { ignoreVisibility = true })
	return if inst then "spawned " .. id else "could not place " .. id .. " (conditions not met)"
end

COMMANDS.spawnObserver = function(admin, userId)
	local target = findPlayer(userId) or admin
	if not Registry.PlayerService:IsAlive(target) then
		return "target is not alive in a round"
	end
	return if Registry.ObserverService:StartHunt(target, { reason = "admin" }) then "hunt started" else "no valid spawn spot"
end

COMMANDS.sighting = function(admin, userId)
	local target = findPlayer(userId) or admin
	return if Registry.ObserverService:Sighting(target) then "sighting placed" else "no valid sighting spot"
end

COMMANDS.mimic = function(admin, userId)
	local target = findPlayer(userId) or admin
	local other = nil
	for _, p in Registry.PlayerService:GetAlive() do
		if p ~= target then
			other = p
		end
	end
	return if Registry.ObserverService:Mimic(target, other) then "mimic placed" else "no valid mimic spot"
end

local PARANOIA = { micro = true, glimpse = true, shadow = true, silence = true }
COMMANDS.paranoia = function(admin, kind)
	if type(kind) ~= "string" or not PARANOIA[kind] then
		return "unknown paranoia kind"
	end
	Registry.HorrorDirector:Paranoia(admin, kind)
	return "paranoia: " .. kind .. " (budget " .. math.floor(Registry.HorrorDirector:GetBudget()) .. ")"
end

COMMANDS.vanishObserver = function()
	Registry.ObserverService:Vanish()
	return "observer gone"
end

COMMANDS.teleport = function(admin, roomId)
	local map = Registry.MapService:GetMap()
	if type(roomId) == "number" then
		local target = findPlayer(roomId)
		local root = target and Util.getRoot(target)
		if root and admin.Character then
			Registry.PlayerService:Teleport(admin, root.CFrame * CFrame.new(0, 0, 4))
			return "teleported to " .. target.Name
		end
		return "player not found"
	end
	if not map or type(roomId) ~= "string" or not map.Rooms[roomId] then
		return "unknown room"
	end
	local room = map.Rooms[roomId]
	local spot = room.floorSpots[1] or room.center
	Registry.PlayerService:Teleport(admin, CFrame.new(spot + Vector3.new(0, 3, 0)))
	return "teleported to " .. room.name
end

COMMANDS.releaseLock = function(_admin, name)
	if type(name) ~= "string" then
		return "?"
	end
	if name == "POWER" then
		Registry.LightingService:SetPower(true)
	end
	Registry.ObjectiveService:ReleaseLock(name)
	return "released " .. name
end

COMMANDS.difficulty = function(_admin, value)
	return "difficulty is chosen by the lobby host; current " .. Registry.RoundService:GetDifficulty() .. " (" .. tostring(value) .. ")"
end

local geometryDebug: Folder? = nil

-- Development: audit the current map's geometry and outline every prop
-- (RED intersection, YELLOW suspicious, BLUE floating, GREEN correct). Toggles.
COMMANDS.geometryCheck = function()
	if geometryDebug then
		geometryDebug:Destroy()
		geometryDebug = nil
		return "geometry debug off"
	end
	local map = Registry.MapService:GetMap()
	if not map then
		return "no map built"
	end
	local GeometryValidator = require(script.Parent.Parent.Map.GeometryValidator)
	local report = GeometryValidator.run(map)
	geometryDebug = GeometryValidator.visualize(report, workspace)
	for i, issue in report.issues do
		if i > 25 then
			break
		end
		AdminService:Log(string.format("[%s] %s %s in %s: %s", issue.severity, issue.kind, issue.name, tostring(issue.room), issue.detail))
	end
	return GeometryValidator.summary(report)
end

COMMANDS.advancePhase = function()
	if not Registry.RoundService:IsRunning() then
		return "no round running"
	end
	Registry.HorrorDirector:AdvanceStory()
	return "story phase: " .. Registry.HorrorDirector:GetStoryPhase()
end

COMMANDS.blackout = function(_admin, level)
	if type(level) ~= "number" then
		return "?"
	end
	if level <= 0 then
		Registry.LightingService:EndBlackout()
		return "blackout ended"
	end
	Registry.LightingService:Blackout(level, 30)
	return "blackout level " .. level .. " for 30s"
end

COMMANDS.killSelf = function(admin)
	Registry.RoundService:KillPlayer(admin, nil)
	return "you died"
end

local function onAdmin(player: Player, command: any, arg: any)
	if not admins[player] then
		AdminService:Log("non-admin admin request from " .. player.Name)
		return
	end
	if type(command) ~= "string" or not COMMANDS[command] then
		return
	end
	local ok, result = pcall(COMMANDS[command], player, arg)
	local message = if ok then (result or "ok") else ("error: " .. tostring(result))
	if command ~= "refresh" then
		AdminService:Log(player.Name .. " > " .. command .. " " .. tostring(arg or "") .. " : " .. tostring(message))
	end
	Net.fire(player, "AdminData", { snapshot = snapshot(), message = message })
end

function AdminService:Init()
	Net.on("Admin", onAdmin)
end

function AdminService:Start()
	local function added(player: Player)
		admins[player] = isAdmin(player)
		if admins[player] then
			player:SetAttribute("IsAdmin", true)
			task.delay(3, function()
				if player.Parent then
					Net.fire(player, "AdminData", { snapshot = snapshot(), message = "admin tools ready (F8)" })
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)
end

return AdminService
