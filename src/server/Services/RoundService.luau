--[[
	RoundService
	Server-authoritative match flow:
	  LOBBY -> STARTING -> EXPLORING -> OBJECTIVE -> ESCAPE -> RESULTS -> RETURNING
	Owns the round seed, difficulty, participants, deaths, escapes and endings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local RoundService = {}

RoundService.StateChanged = Signal.new() -- (state)

local RS = Enums.RoundState
local Status = Enums.PlayerStatus

local state = RS.Lobby
local seed = 0
local difficulty = Enums.Difficulty.Normal
local participants: { [number]: { player: Player?, name: string, outcome: string?, escapedAt: number?, diedAt: number?, witness: boolean?, lowBattery: boolean?, stats: any } } = {}
local exploringStartedAt = 0
local escapeStartedAt = 0
local endingReason: string? = nil
local roundToken = 0

function RoundService:GetState(): string
	return state
end

function RoundService:GetSeed(): number
	return seed
end

function RoundService:GetDifficulty(): string
	return difficulty
end

function RoundService:GetDifficultyConfig()
	return GameConfig.Difficulty[difficulty] or GameConfig.Difficulty.NORMAL
end

function RoundService:GetQuota(playerCount: number): number
	local c = self:GetDifficultyConfig()
	return c.AnomalyQuotaBase + c.AnomalyQuotaPerExtraPlayer * math.max(0, playerCount - 1)
end

function RoundService:GetElapsed(): number
	if exploringStartedAt == 0 then
		return 0
	end
	return os.clock() - exploringStartedAt
end

function RoundService:IsEscape(): boolean
	return state == RS.Escape
end

function RoundService:IsRunning(): boolean
	return state == RS.Starting or state == RS.Exploring or state == RS.Objective or state == RS.Escape
end

function RoundService:GetParticipants()
	return participants
end

function RoundService:IsParticipant(player: Player): boolean
	return participants[player.UserId] ~= nil
end

local function setState(newState: string, data: { [string]: any }?)
	state = newState
	workspace:SetAttribute("RoundState", newState)
	local payload = data or {}
	payload.state = newState
	payload.difficulty = difficulty
	payload.seed = seed
	payload.elapsed = RoundService:GetElapsed()
	Net.fireAll("RoundState", payload)
	RoundService.StateChanged:Fire(newState)
	if Registry.AdminService then
		Registry.AdminService:Log("round state -> " .. newState)
	end
end

function RoundService:BroadcastState(player: Player?)
	local payload = { state = state, difficulty = difficulty, seed = seed, elapsed = self:GetElapsed(), escapeRemaining = if state == RS.Escape then math.max(0, GameConfig.Round.EscapeWindow - (os.clock() - escapeStartedAt)) else nil }
	if player then
		Net.fire(player, "RoundState", payload)
	else
		Net.fireAll("RoundState", payload)
	end
end

local function aliveParticipants(): { Player }
	local list = {}
	for _, rec in participants do
		if rec.player and rec.player.Parent and Registry.PlayerService:IsAlive(rec.player) then
			table.insert(list, rec.player)
		end
	end
	return list
end

------------------------------------------------------------------------------------
-- Deaths & escapes
------------------------------------------------------------------------------------

-- info: how it happened (death cinematic variant and its context)
function RoundService:KillPlayer(player: Player, killerCF: CFrame?, info: { [string]: any }?)
	if not Registry.PlayerService:IsAlive(player) then
		return
	end
	local rec = participants[player.UserId]
	if rec then
		rec.outcome = "DEAD"
		rec.diedAt = self:GetElapsed()
	end
	Registry.PlayerService:SetStatus(player, Status.Dead)
	Registry.InventoryService:SetFlashlight(player, false)
	Registry.ProgressionService:PlayerDied(player)
	Registry.AnalyticsService:Death(player, self:GetElapsed())
	local root = Util.getRoot(player)
	local position = root and root.Position or Vector3.zero
	local payload = { killer = killerCF, position = position }
	for k, v in info or {} do
		payload[k] = v
	end
	Net.fire(player, "Death", payload)
	for _, p in Players:GetPlayers() do
		if p ~= player and Registry.PlayerService:IsAlive(p) then
			Net.fire(p, "Notify", { kind = "danger", text = player.DisplayName .. " was taken." })
		end
	end
	Registry.AudioService:PlayAt("DeathFall", position)
	local humanoid = Util.getHumanoid(player)
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
	end
	if root then
		root.AssemblyAngularVelocity = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	end
	local token = roundToken
	task.delay(3.6, function()
		if token ~= roundToken then
			return
		end
		if player.Parent then
			Registry.PlayerService:RemoveCharacter(player)
		end
	end)
end

function RoundService:PlayerEscaped(player: Player)
	if not Registry.PlayerService:IsAlive(player) or state ~= RS.Escape then
		return
	end
	local rec = participants[player.UserId]
	local battery = Registry.InventoryService:GetBattery(player)
	if rec then
		rec.outcome = "ESCAPED"
		rec.escapedAt = self:GetElapsed()
		rec.witness = Registry.InventoryService:Has(player, "PHOTOGRAPH")
		rec.lowBattery = battery < 10
		rec.stats = Registry.InventoryService:GetRoundStats(player)
	end
	Registry.PlayerService:SetStatus(player, Status.Escaped)
	Registry.InventoryService:SetFlashlight(player, false)
	Registry.AnalyticsService:Escape(player, self:GetElapsed())
	local map = Registry.MapService:GetMap()
	Net.fire(player, "Effect", { name = "Escaped", camera = map and map.EscapeCamera, witness = rec and rec.witness })
	Registry.AudioService:Play2D({ player }, "EscapeSuccess")
	for _, p in Players:GetPlayers() do
		if p ~= player and Registry.PlayerService:IsAlive(p) then
			Net.fire(p, "Notify", { kind = "team", text = player.DisplayName .. " made it out." })
		end
	end
	task.delay(0.4, function()
		if player.Parent then
			Registry.PlayerService:RemoveCharacter(player)
		end
	end)
end

function RoundService:FailRound(reason: string)
	if not self:IsRunning() or endingReason then
		return
	end
	endingReason = reason
	for _, p in aliveParticipants() do
		Net.fire(p, "Effect", { name = "RealityCollapse" })
		Registry.PlayerService:SetStatus(p, Status.Dead)
		local rec = participants[p.UserId]
		if rec then
			rec.outcome = "LOST"
		end
	end
	Registry.AudioService:Play2DAll("DeathHit", { volume = 0.6 })
	task.delay(3, function()
		for _, rec in participants do
			if rec.player and rec.player.Parent and rec.player.Character and rec.outcome == "LOST" then
				Registry.PlayerService:RemoveCharacter(rec.player)
			end
		end
	end)
end

------------------------------------------------------------------------------------
-- Endings
------------------------------------------------------------------------------------

local function computeEndings()
	local count, escaped = 0, 0
	for _, rec in participants do
		count += 1
		if rec.outcome == "ESCAPED" then
			escaped += 1
		end
	end
	local personal = {}
	for userId, rec in participants do
		local ending
		if rec.outcome == "ESCAPED" then
			if rec.witness then
				ending = Enums.Ending.Witness
			elseif count > 1 and escaped == count then
				ending = Enums.Ending.EveryoneSurvived
			elseif escaped == 1 then
				ending = Enums.Ending.EscapedAlone
			else
				ending = Enums.Ending.Escaped
			end
		elseif rec.outcome == "DEAD" then
			ending = Enums.Ending.ObserverCaughtYou
		else
			ending = Enums.Ending.FailedToIdentify
		end
		personal[userId] = ending
	end
	local team
	if escaped == 0 then
		team = if endingReason == Enums.Ending.FailedToIdentify then Enums.Ending.FailedToIdentify else Enums.Ending.ObserverCaughtYou
	elseif count > 1 and escaped == count then
		team = Enums.Ending.EveryoneSurvived
	elseif escaped == 1 then
		team = Enums.Ending.EscapedAlone
	else
		team = Enums.Ending.Escaped
	end
	return personal, team, count, escaped
end

------------------------------------------------------------------------------------
-- Flow
------------------------------------------------------------------------------------

local function everyoneDone(): boolean
	return #aliveParticipants() == 0
end

local function startEscape()
	if state == RS.Escape or not RoundService:IsRunning() then
		return
	end
	escapeStartedAt = os.clock()
	setState(RS.Escape, { escapeRemaining = GameConfig.Round.EscapeWindow })
	local map = Registry.MapService:GetMap()
	if map then
		Registry.DoorService:SetOpen(map.ExitShutter, true)
	end
	workspace:SetAttribute("Escape", true)
	Registry.LightingService:ApplyPreset("ESCAPE", 3)
	Registry.AudioService:Play2DAll("ExitUnlocked")
	Net.fireAll("Effect", { name = "EscapeStart" })
	Registry.HorrorDirector:BeginEscape()
	Registry.ObjectiveService:Push()
	-- the building fights back: geometry and light shift, doors move
	task.spawn(function()
		local token = roundToken
		for _, id in { "CORRIDOR_LONGER", "LIGHTS_CHANGE", "FLOOR_CHANGE", "ROOM_BIGGER" } do
			if token ~= roundToken or state ~= RS.Escape then
				return
			end
			Registry.AnomalyService:TrySpawn(id, { scope = Enums.AnomalyScope.Global, ignoreVisibility = true })
			task.wait(4)
		end
	end)
	task.delay(6, function()
		if state == RS.Escape then
			Registry.ObserverService:StartEscapeChase()
		end
	end)
	task.spawn(function()
		local token = roundToken
		while token == roundToken and state == RS.Escape do
			task.wait(math.random(6, 11))
			if token ~= roundToken or state ~= RS.Escape then
				break
			end
			local alive = aliveParticipants()
			local p = alive[math.random(1, math.max(1, #alive))]
			local root = p and Util.getRoot(p)
			if root then
				if not Registry.DoorService:SlamNear(root.Position, 30) then
					Registry.DoorService:OpenNear(root.Position, 30)
				end
				Net.fireAll("Effect", { name = "Shake", strength = 0.35 })
			end
		end
	end)
end

local function results()
	local personal, team, count, escaped = computeEndings()
	local duration = RoundService:GetElapsed()
	setState(RS.Results, { ending = team })
	Registry.LightingService:ApplyPreset("RESULTS", 2)
	Registry.ObserverService:EndRound()
	Registry.HorrorDirector:EndRound()
	local anomalyStats = Registry.AnomalyService:GetRoundStats()
	local summary = {
		duration = duration,
		difficulty = difficulty,
		playerCount = count,
		escapedCount = escaped,
		team = team,
		seed = seed,
		anomaliesFound = anomalyStats.found,
		anomaliesMissed = anomalyStats.missed,
		quota = (Registry.ObjectiveService:GetState() or { quota = 0 }).quota,
	}
	local teamMisreports = 0
	for _, n in anomalyStats.misreports do
		teamMisreports += n
	end
	local locksReleased = 0
	local objective = Registry.ObjectiveService:GetState()
	if objective then
		for _, v in objective.locks do
			if v then
				locksReleased += 1
			end
		end
	end
	summary.locksReleased = locksReleased
	for userId, rec in participants do
		local player = rec.player
		if player and player.Parent then
			local reward = Registry.ProgressionService:RoundEnded(player, {
				ending = personal[userId],
				team = team,
				outcome = rec.outcome,
				escapedAt = rec.escapedAt,
				witness = rec.witness,
				lowBattery = rec.lowBattery,
				lightSeconds = rec.stats and rec.stats.lightSeconds or Registry.InventoryService:GetRoundStats(player).lightSeconds,
				duration = duration,
				difficulty = difficulty,
				playerCount = count,
				escapedCount = escaped,
				misreports = anomalyStats.misreports[player] or 0,
				teamMisreports = teamMisreports,
				anomaliesMissed = anomalyStats.missed,
				locksReleased = locksReleased,
				diedAt = rec.diedAt,
			})
			local roster = {}
			for _, other in participants do
				table.insert(roster, { name = other.name, outcome = other.outcome or "LOST" })
			end
			Net.fire(player, "Results", { ending = personal[userId], team = team, summary = summary, reward = reward, roster = roster })
		end
	end
	Registry.AnalyticsService:RoundComplete(Players:GetPlayers(), duration, team)
end

local function returnToLobby()
	setState(RS.Returning)
	Registry.AnomalyService:EndRound()
	Registry.PuzzleService:Clear()
	Registry.ObjectiveService:Clear()
	Registry.InventoryService:ClearPickups()
	Registry.EquipmentService:EndRound()
	workspace:SetAttribute("Escape", false)
	Registry.LightingService:EndBlackout(true)
	Registry.LightingService:SetPower(false, true)
	task.wait(GameConfig.Round.ReturningDuration)
	participants = {}
	exploringStartedAt = 0
	endingReason = nil
	Registry.LightingService:ApplyPreset("LOBBY", 1.5)
	for _, p in Players:GetPlayers() do
		local status = Registry.PlayerService:GetStatus(p)
		if status ~= Status.Menu then
			Registry.LobbyService:SendToLobby(p)
		end
	end
	setState(RS.Lobby)
end

function RoundService:StartRound(players: { Player }, chosenDifficulty: string)
	if state ~= RS.Lobby or #players == 0 then
		return false
	end
	-- a failure while starting must never leave the server stuck in STARTING
	local ok, result = pcall(self._startRound, self, players, chosenDifficulty)
	if ok then
		return result
	end
	warn("[RoundService] round failed to start: " .. tostring(result))
	roundToken += 1
	pcall(returnToLobby)
	return false
end

function RoundService:_startRound(players: { Player }, chosenDifficulty: string)
	roundToken += 1
	local token = roundToken
	difficulty = if GameConfig.Difficulty[chosenDifficulty] then chosenDifficulty else Enums.Difficulty.Normal
	seed = Random.new():NextInteger(1, 2147483646)
	participants = {}
	endingReason = nil
	for _, p in players do
		participants[p.UserId] = { player = p, name = p.DisplayName, outcome = nil }
	end
	setState(RS.Starting)
	Registry.MapService:Rebuild(seed)
	local map = Registry.MapService:GetMap()
	if not map then
		warn("[RoundService] map failed to build; aborting round")
		setState(RS.Lobby)
		return false
	end
	-- the building still has power when you arrive; it fails later (HorrorDirector)
	Registry.LightingService:EndBlackout(true)
	Registry.LightingService:SetPower(true, true)
	Registry.LightingService:ApplyPreset("OUTSIDE", 1)
	Registry.AnomalyService:BeginRound(seed)
	Registry.ObserverService:BeginRound()
	Registry.ObjectiveService:Plan(map, SeededRandom.new(seed, "objectives"), #players)
	-- arrive outside, in the rain
	for i, p in players do
		Registry.InventoryService:Reset(p, Registry.EquipmentService:PrepareRound(p))
		local spawn = map.CourtyardSpawns[(i - 1) % #map.CourtyardSpawns + 1]
		task.spawn(function()
			Registry.PlayerService:SpawnAt(p, spawn)
			Registry.PlayerService:SetStatus(p, Status.Alive)
			Registry.InventoryService:Push(p)
		end)
	end
	for _, door in map.EntranceDoors do
		Registry.DoorService:SetOpen(door, true, { silent = true })
	end
	Registry.AnalyticsService:RoundStart(players, difficulty)
	Net.fireAll("Objective", { list = { { text = "ENTER THE BUILDING", done = false, primary = true } }, found = 0, quota = 0 })
	-- wait until everyone is inside (or the timer runs out)
	local deadline = os.clock() + GameConfig.Round.StartingDuration
	task.wait(2)
	while token == roundToken and os.clock() < deadline do
		local allInside = true
		for _, p in aliveParticipants() do
			local root = Util.getRoot(p)
			if not root or not map:isInsideBuilding(root.Position) then
				allInside = false
			end
		end
		if allInside and #aliveParticipants() > 0 then
			break
		end
		task.wait(0.5)
	end
	if token ~= roundToken then
		return false
	end
	-- stragglers are pulled in as the doors close
	local vestibule = map.Rooms.G_e
	for _, p in aliveParticipants() do
		local root = Util.getRoot(p)
		if root and not map:isInsideBuilding(root.Position) and vestibule then
			Registry.PlayerService:Teleport(p, CFrame.lookAt(vestibule.center + Vector3.new(0, 3, 0), vestibule.center + Vector3.new(0, 3, -10)))
		end
	end
	task.wait(0.4)
	for i, door in map.EntranceDoors do
		Registry.DoorService:SetOpen(door, false, { slam = true, silent = i > 1 })
	end
	Registry.LightingService:ApplyPreset("POWERED", 2)
	exploringStartedAt = os.clock()
	Registry.HorrorDirector:BeginRound(seed)
	Registry.GuidanceService:BeginRound()
	setState(RS.Exploring)
	Net.fireAll("Effect", { name = "Intro" })
	Registry.ObjectiveService:Push()
	-- the very first anomaly is always readable for newcomers
	local hasNewcomer = false
	for _, p in aliveParticipants() do
		local data = Registry.DataService:Get(p)
		if data and not data.flags.tutorialDone then
			hasNewcomer = true
		end
	end
	if hasNewcomer then
		task.delay(25, function()
			if token == roundToken then
				Registry.AnomalyService:SpawnTutorial()
			end
		end)
	end
	-- round loop
	task.spawn(function()
		while token == roundToken and self:IsRunning() do
			task.wait(0.25)
			if token ~= roundToken then
				return
			end
			-- escapes
			if state == RS.Escape and map.EscapeZone then
				local zone = map.EscapeZone
				for _, p in aliveParticipants() do
					local root = Util.getRoot(p)
					if root then
						local rel = zone.CFrame:PointToObjectSpace(root.Position)
						local half = zone.Size / 2
						if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
							self:PlayerEscaped(p)
						end
					end
				end
				if os.clock() - escapeStartedAt > GameConfig.Round.EscapeWindow then
					-- the shutter comes down
					Registry.DoorService:SetOpen(map.ExitShutter, false, { slam = true })
					for _, p in aliveParticipants() do
						self:KillPlayer(p, nil)
					end
				end
			end
			if self:GetElapsed() > GameConfig.Round.MaxRoundTime and state ~= RS.Escape then
				self:FailRound(Enums.Ending.FailedToIdentify)
			end
			if everyoneDone() then
				task.wait(4.5)
				if token ~= roundToken then
					return
				end
				results()
				task.wait(GameConfig.Round.ResultsDuration)
				if token ~= roundToken then
					return
				end
				returnToLobby()
				return
			end
		end
	end)
	return true
end

-- Admin / emergency: stop whatever is happening and go back to the lobby.
function RoundService:ForceEnd()
	if not self:IsRunning() and state ~= RS.Results then
		return
	end
	roundToken += 1
	Registry.ObserverService:EndRound()
	Registry.HorrorDirector:EndRound()
	task.spawn(returnToLobby)
end

function RoundService:Init()
	Registry.ObjectiveService.LockReleased:Connect(function(name)
		if name == "POWER" and state == RS.Exploring then
			setState(RS.Objective)
		end
	end)
	Registry.ObjectiveService.AllLocksReleased:Connect(function()
		startEscape()
	end)
end

function RoundService:Start()
	workspace:SetAttribute("RoundState", state)
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		self:BroadcastState(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local rec = participants[player.UserId]
		if rec then
			-- keep the record so a rejoining player can continue
			rec.player = nil
			rec.leftAlive = Registry.PlayerService:GetStatus(player) == Status.Alive
		end
	end)
end

-- Rejoin support: a participant who left while alive comes back into the round.
function RoundService:TryRejoin(player: Player): boolean
	local rec = participants[player.UserId]
	if not rec or not self:IsRunning() or state == RS.Starting then
		return false
	end
	rec.player = player
	if rec.leftAlive and not rec.outcome then
		local map = Registry.MapService:GetMap()
		local vestibule = map and map.Rooms.G_e
		if vestibule then
			Registry.InventoryService:Reset(player, Registry.EquipmentService:PrepareRound(player))
			task.spawn(function()
				Registry.PlayerService:SpawnAt(player, CFrame.lookAt(vestibule.center + Vector3.new(0, 3, 0), vestibule.center + Vector3.new(0, 3, -10)))
				Registry.PlayerService:SetStatus(player, Status.Alive)
				self:BroadcastState(player)
				Registry.ObjectiveService:Push(player)
			end)
			return true
		end
	end
	Registry.PlayerService:SetStatus(player, Status.Dead)
	self:BroadcastState(player)
	return true
end

return RoundService
