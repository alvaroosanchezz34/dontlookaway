--[[
	PlayerService
	Player lifecycle (status, character spawning, cleanup) and PERCEPTION: the
	server's model of where every player is looking. Clients report their camera
	at a fixed rate; the server validates it against the character (origin near
	the head, yaw consistent with the body) and answers questions such as
	"can anyone see this point?" with line-of-sight raycasts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Registry = require(script.Parent.Parent.Registry)

local PlayerService = {}

PlayerService.CharacterSpawned = Signal.new() -- (player, character)
PlayerService.StatusChanged = Signal.new() -- (player, status)

type Look = { origin: Vector3, dir: Vector3, time: number }

local looks: { [Player]: Look } = {}
local statuses: { [Player]: string } = {}
local lastPitchPush: { [Player]: number } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true

local excluded: { Instance } = {}

local function refreshExclusions()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, inst in excluded do
		if inst.Parent then
			table.insert(list, inst)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

function PlayerService:AddPerceptionExclusion(instance: Instance)
	table.insert(excluded, instance)
	refreshExclusions()
end

function PlayerService:RemovePerceptionExclusion(instance: Instance)
	local i = table.find(excluded, instance)
	if i then
		table.remove(excluded, i)
	end
	refreshExclusions()
end

------------------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------------------

function PlayerService:SetStatus(player: Player, status: string)
	if statuses[player] == status then
		return
	end
	statuses[player] = status
	player:SetAttribute("Status", status)
	PlayerService.StatusChanged:Fire(player, status)
	self:BroadcastStates()
end

function PlayerService:GetStatus(player: Player): string
	return statuses[player] or Enums.PlayerStatus.Menu
end

function PlayerService:IsAlive(player: Player): boolean
	return statuses[player] == Enums.PlayerStatus.Alive and player.Character ~= nil
end

function PlayerService:GetWithStatus(status: string): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if statuses[p] == status then
			table.insert(list, p)
		end
	end
	return list
end

function PlayerService:GetAlive(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if self:IsAlive(p) then
			table.insert(list, p)
		end
	end
	return list
end

function PlayerService:BroadcastStates()
	local payload = {}
	for _, p in Players:GetPlayers() do
		table.insert(payload, { userId = p.UserId, name = p.DisplayName, status = statuses[p] or Enums.PlayerStatus.Menu })
	end
	Net.fireAll("PlayerStates", payload)
end

------------------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------------------

local function configureCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = GameConfig.Movement.WalkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	-- the game controls death itself (cinematic); never let physics kill players
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end)
	local tag = player:GetAttribute("Title")
	character:SetAttribute("Title", tag)
	character:SetAttribute("Badge", player:GetAttribute("Badge"))
	character:SetAttribute("PlayerName", player.DisplayName)
end

-- Spawns (or respawns) the character at a CFrame. Yields until spawned.
function PlayerService:SpawnAt(player: Player, cframe: CFrame)
	if not player.Parent then
		return nil
	end
	Registry.AntiExploitService:Allow(player, 3)
	local ok, err = pcall(function()
		local async = (player :: any).LoadCharacterAsync
		if async then
			async(player)
		else
			(player :: any):LoadCharacter()
		end
	end)
	if not ok then
		warn("[PlayerService] LoadCharacter failed:", err)
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return nil
	end
	configureCharacter(player, character)
	character:PivotTo(cframe)
	refreshExclusions()
	PlayerService.CharacterSpawned:Fire(player, character)
	return character
end

function PlayerService:Teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	Registry.AntiExploitService:Allow(player, 2)
	character:PivotTo(cframe)
end

function PlayerService:RemoveCharacter(player: Player)
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
	refreshExclusions()
end

------------------------------------------------------------------------------------
-- Perception
------------------------------------------------------------------------------------

function PlayerService:GetLook(player: Player): Look?
	local look = looks[player]
	if not look then
		return nil
	end
	if os.clock() - look.time > 1.5 then
		-- stale report: fall back to the head's facing
		local head = Util.getHead(player)
		if head then
			return { origin = head.Position, dir = head.CFrame.LookVector, time = os.clock() }
		end
	end
	return look
end

function PlayerService:GetEye(player: Player): Vector3?
	local look = self:GetLook(player)
	if look then
		return look.origin
	end
	local head = Util.getHead(player)
	return head and head.Position
end

-- Line of sight from `origin` to `point`; ignore = extra instances to skip.
function PlayerService:HasLineOfSight(origin: Vector3, point: Vector3, ignore: Instance?): boolean
	local delta = point - origin
	local dist = delta.Magnitude
	if dist < 0.5 then
		return true
	end
	local result = workspace:Raycast(origin, delta, rayParams)
	if not result then
		return true
	end
	if ignore and result.Instance:IsDescendantOf(ignore) then
		return true
	end
	return (result.Position - origin).Magnitude >= dist - 1.2
end

-- Is `player` looking at `point` within halfAngle degrees and maxDist, with LOS?
function PlayerService:IsLookingAt(player: Player, point: Vector3, halfAngle: number?, maxDist: number?, ignore: Instance?): boolean
	if not self:IsAlive(player) then
		return false
	end
	local look = self:GetLook(player)
	if not look then
		return false
	end
	local delta = point - look.origin
	local dist = delta.Magnitude
	if dist > (maxDist or 200) then
		return false
	end
	if dist > 0.01 then
		local cos = look.dir:Dot(delta / dist)
		if cos < math.cos(math.rad(halfAngle or GameConfig.Observer.WatchFOV)) then
			return false
		end
	end
	return self:HasLineOfSight(look.origin, point, ignore)
end

-- Any alive player able to see any of the sample points.
function PlayerService:CanAnyoneSee(points: { Vector3 }, halfAngle: number?, maxDist: number?, ignore: Instance?, players: { Player }?): (boolean, Player?)
	for _, player in players or self:GetAlive() do
		for _, point in points do
			if self:IsLookingAt(player, point, halfAngle, maxDist, ignore) then
				return true, player
			end
		end
	end
	return false, nil
end

local function onLookUpdate(player: Player, origin: any, dir: any)
	if not Util.isFiniteVector(origin) or not Util.isFiniteVector(dir) then
		return
	end
	if dir.Magnitude < 0.5 or dir.Magnitude > 1.5 then
		return
	end
	dir = dir.Unit
	local head = Util.getHead(player)
	local root = Util.getRoot(player)
	if not head or not root then
		return
	end
	-- origin must be near the head
	if (origin - head.Position).Magnitude > 4 then
		origin = head.Position
	end
	-- yaw must roughly agree with the body (first person: body follows camera yaw)
	local flatDir = Util.flat(dir)
	local flatLook = Util.flat(root.CFrame.LookVector)
	if flatDir.Magnitude > 0.2 and flatLook.Magnitude > 0.2 then
		if flatDir.Unit:Dot(flatLook.Unit) < 0.2 then
			-- implausible: trust the body instead
			dir = (flatLook.Unit + Vector3.new(0, dir.Y, 0)).Unit
		end
	end
	looks[player] = { origin = origin, dir = dir, time = os.clock() }
	-- replicate pitch for other clients' flashlight beams (throttled)
	local now = os.clock()
	if not lastPitchPush[player] or now - lastPitchPush[player] > 0.2 then
		lastPitchPush[player] = now
		local character = player.Character
		if character then
			character:SetAttribute("LookPitch", math.floor(math.asin(math.clamp(dir.Y, -1, 1)) * 100) / 100)
		end
	end
end

------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------

function PlayerService:Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:RegisterCollisionGroup("Observer")
		PhysicsService:RegisterCollisionGroup("Doors")
		PhysicsService:RegisterCollisionGroup("Ghost")
	end)
	PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Observer", "Doors", false)
	PhysicsService:CollisionGroupSetCollidable("Observer", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Doors", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Observer", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Ghost", false)
	Net.on("LookUpdate", onLookUpdate)
end

function PlayerService:Start()
	local function added(player: Player)
		statuses[player] = Enums.PlayerStatus.Menu
		player:SetAttribute("Status", Enums.PlayerStatus.Menu)
		Registry.AnalyticsService:SessionStart(player)
		player.CharacterAdded:Connect(function()
			task.defer(refreshExclusions)
		end)
		self:BroadcastStates()
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		looks[player] = nil
		statuses[player] = nil
		lastPitchPush[player] = nil
		Net.clearPlayer(player)
		task.defer(function()
			refreshExclusions()
			self:BroadcastStates()
		end)
	end)
end

return PlayerService
