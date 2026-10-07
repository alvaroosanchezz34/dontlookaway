--[[
	DataService
	Persistent player data with:
	  * session locking (a profile is owned by one server at a time)
	  * retries with exponential backoff on every DataStore call
	  * schema validation + reconciliation (corrupt or missing fields are repaired)
	  * autosave, save on leave and BindToClose shutdown saving
	  * an in-memory fallback in Studio when API access is disabled

	The client never writes data. All mutations happen through DataService:Update
	called by other server services.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local Achievements = require(ReplicatedStorage.Shared.Catalog.Achievements)
local Equipment = require(ReplicatedStorage.Shared.Catalog.Equipment)
local Challenges = require(ReplicatedStorage.Shared.Catalog.Challenges)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataService = {}

DataService.Loaded = Signal.new() -- (player, data)
DataService.Changed = Signal.new() -- (player, data)

-- v1: launch. v2: equipment, loadout, upgrades, challenges, gloves & badges.
local SCHEMA_VERSION = 2

local TEMPLATE = {
	version = SCHEMA_VERSION,
	echoes = 0,
	xp = 0,
	stats = {
		rounds = 0,
		escapes = 0,
		deaths = 0,
		anomaliesReported = 0,
		falseReports = 0,
		bestTime = 0,
		soloEscapes = 0,
		hardEscapes = 0,
		nightmareEscapes = 0,
		blackoutsSurvived = 0,
		mimicsSpotted = 0,
		roundsWithFriends = 0,
		creditsEarned = 0,
		timePlayed = 0,
		observerSightings = 0,
		secretEndings = 0,
		legendaryReports = 0,
	},
	journal = {},
	achievements = {},
	owned = {},
	equipped = {
		FLASHLIGHT = Cosmetics.Defaults.FLASHLIGHT,
		BEAM = Cosmetics.Defaults.BEAM,
		GLOVES = Cosmetics.Defaults.GLOVES,
		BADGE = Cosmetics.Defaults.BADGE,
		TRAIL = Cosmetics.Defaults.TRAIL,
		TITLE = Cosmetics.Defaults.TITLE,
		UI = Cosmetics.Defaults.UI,
	},
	gear = {
		owned = {},
		flashlight = Equipment.Defaults.FLASHLIGHT,
		battery = Equipment.Defaults.BATTERY,
		loadout = {},
	},
	upgrades = {},
	challenges = {
		day = 0,
		week = 0,
		daily = {},
		weekly = {},
		dailiesDone = 0,
		weekliesDone = 0,
	},
	settings = {
		master = 1,
		music = 0.7,
		sfx = 1,
		ambient = 1,
		ui = 0.8,
		sensitivity = GameConfig.Camera.DefaultSensitivity,
		fov = GameConfig.Camera.DefaultFOV,
		headBob = true,
		cameraShake = true,
		reducedEffects = false,
		flashingAccepted = false,
		subtitles = true,
		invertY = false,
		brightness = 0.5,
		subtitleSize = 0.5,
		flashlightEffects = true,
		audioIndicators = false,
		reduceMotion = false,
		graphics = "AUTO",
		colorMode = "NORMAL",
	},
	flags = {
		tutorialDone = false,
		hardUnlocked = false,
		nightmareUnlocked = false,
	},
	puzzlesSolved = {},
	lastSeen = 0,
}

DataService.Template = TEMPLATE

------------------------------------------------------------------------------------
-- Store access (real or mock)
------------------------------------------------------------------------------------

local MockStore = {}
MockStore.__index = MockStore

function MockStore.new()
	return setmetatable({ _data = {} }, MockStore)
end

function MockStore:GetAsync(key)
	return Util.deepCopy(self._data[key])
end

function MockStore:UpdateAsync(key, transform)
	local result = transform(Util.deepCopy(self._data[key]))
	if result ~= nil then
		self._data[key] = Util.deepCopy(result)
	end
	return result
end

local store = nil
local usingMock = false

local function retry(label: string, fn: () -> any): (boolean, any)
	local attempts = GameConfig.Data.MaxRetries
	local lastErr = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(math.min(2 ^ attempt, 16))
		end
	end
	return false, lastErr
end

local function initStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)
	if ok and result then
		-- probe write access; Studio without API access throws here
		local probeOk = pcall(function()
			result:GetAsync("__probe")
		end)
		if probeOk then
			store = result
			return
		end
	end
	usingMock = true
	store = MockStore.new()
	if RunService:IsStudio() then
		warn("[DataService] DataStore unavailable (enable Studio API access to persist). Using in-memory data.")
	else
		warn("[DataService] DataStore unavailable. Using in-memory data for this server.")
	end
end

------------------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------------------

local function num(value, default, min, max)
	if not Util.isFinite(value) then
		return default
	end
	return math.clamp(value, min or -math.huge, max or math.huge)
end

-- Upgrades older saves in place. Never removes anything a player earned.
local function migrate(data)
	local from = if type(data.version) == "number" then data.version else 1
	if from < 2 then
		-- v2 adds gear, upgrades and challenges: reconcile fills them with defaults.
		-- Echoes, XP, journal, achievements and cosmetics carry over untouched.
		data.gear = data.gear or Util.deepCopy(TEMPLATE.gear)
	end
	return data
end

local function validate(data)
	if type(data) ~= "table" then
		return Util.deepCopy(TEMPLATE)
	end
	migrate(data)
	Util.reconcile(data, TEMPLATE)
	data.version = SCHEMA_VERSION
	data.echoes = math.floor(num(data.echoes, 0, 0, 1e9))
	data.xp = math.floor(num(data.xp, 0, 0, 1e10))
	for key, default in TEMPLATE.stats do
		data.stats[key] = num(data.stats[key], default, 0, 1e12)
	end
	-- journal: only known anomaly ids, sane counts
	local journal = {}
	if type(data.journal) == "table" then
		for id, entry in data.journal do
			if JournalCatalog.ById[id] and type(entry) == "table" then
				journal[id] = { c = math.floor(num(entry.c, 1, 1, 1e9)), f = num(entry.f, os.time(), 0, 1e11), l = num(entry.l, os.time(), 0, 1e11) }
			end
		end
	end
	data.journal = journal
	local achievements = {}
	if type(data.achievements) == "table" then
		for id, t in data.achievements do
			if Achievements.ById[id] then
				achievements[id] = num(t, os.time(), 0, 1e11)
			end
		end
	end
	data.achievements = achievements
	local owned = {}
	if type(data.owned) == "table" then
		for id, v in data.owned do
			if Cosmetics.ById[id] and v == true then
				owned[id] = true
			end
		end
	end
	data.owned = owned
	if type(data.equipped) ~= "table" then
		data.equipped = Util.deepCopy(TEMPLATE.equipped)
	end
	for category, default in TEMPLATE.equipped do
		local id = data.equipped[category]
		local item = type(id) == "string" and Cosmetics.ById[id]
		if not item or item.category ~= category then
			data.equipped[category] = default
		end
	end
	-- gear: only known, owned pieces; the loadout fits the slots it has
	local gear = data.gear
	local ownedGear = {}
	if type(gear.owned) == "table" then
		for id, v in gear.owned do
			local item = Equipment.get(id)
			if item and v == true and not item.default then
				ownedGear[id] = true
			end
		end
	end
	gear.owned = ownedGear
	local function ownsGear(id: any, kind: string): boolean
		local item = type(id) == "string" and Equipment.get(id)
		return item ~= nil and item.kind == kind and (item.default == true or ownedGear[id] == true)
	end
	if not ownsGear(gear.flashlight, "FLASHLIGHT") then
		gear.flashlight = Equipment.Defaults.FLASHLIGHT
	end
	if not ownsGear(gear.battery, "BATTERY") then
		gear.battery = Equipment.Defaults.BATTERY
	end
	local upgrades = {}
	if type(data.upgrades) == "table" then
		for id, level in data.upgrades do
			local def = Equipment.UpgradesById[id]
			if def and Util.isFinite(level) then
				upgrades[id] = math.clamp(math.floor(level), 0, #def.levels)
			end
		end
	end
	data.upgrades = upgrades
	local slots = Equipment.loadoutSlots(upgrades)
	local loadout, seen = {}, {}
	if type(gear.loadout) == "table" then
		for _, id in gear.loadout do
			if #loadout < slots and type(id) == "string" and not seen[id] and ownsGear(id, "TOOL") then
				seen[id] = true
				table.insert(loadout, id)
			end
		end
	end
	gear.loadout = loadout
	-- challenges: known ids, sane progress
	local ch = data.challenges
	ch.day = math.floor(num(ch.day, 0, 0, 1e7))
	ch.week = math.floor(num(ch.week, 0, 0, 1e7))
	ch.dailiesDone = math.floor(num(ch.dailiesDone, 0, 0, 1e7))
	ch.weekliesDone = math.floor(num(ch.weekliesDone, 0, 0, 1e7))
	for _, bucket in { "daily", "weekly" } do
		local clean = {}
		if type(ch[bucket]) == "table" then
			for id, rec in ch[bucket] do
				local def = Challenges.ById[id]
				if def and type(rec) == "table" then
					clean[id] = { p = math.floor(num(rec.p, 0, 0, def.goal)), done = rec.done == true }
				end
			end
		end
		ch[bucket] = clean
	end
	local s = data.settings
	s.master = num(s.master, 1, 0, 1)
	s.music = num(s.music, 0.7, 0, 1)
	s.sfx = num(s.sfx, 1, 0, 1)
	s.ambient = num(s.ambient, 1, 0, 1)
	s.ui = num(s.ui, 0.8, 0, 1)
	s.sensitivity = num(s.sensitivity, GameConfig.Camera.DefaultSensitivity, 0.05, 2)
	s.fov = num(s.fov, GameConfig.Camera.DefaultFOV, GameConfig.Camera.MinFOV, GameConfig.Camera.MaxFOV)
	s.brightness = num(s.brightness, 0.5, 0, 1)
	s.subtitleSize = num(s.subtitleSize, 0.5, 0, 1)
	for _, b in { "headBob", "cameraShake", "reducedEffects", "flashingAccepted", "subtitles", "invertY", "flashlightEffects", "audioIndicators", "reduceMotion" } do
		if type(s[b]) ~= "boolean" then
			s[b] = TEMPLATE.settings[b]
		end
	end
	if s.graphics ~= "AUTO" and s.graphics ~= "LOW" and s.graphics ~= "MEDIUM" and s.graphics ~= "HIGH" then
		s.graphics = "AUTO"
	end
	if s.colorMode ~= "NORMAL" and s.colorMode ~= "DEUTERANOPIA" and s.colorMode ~= "PROTANOPIA" and s.colorMode ~= "TRITANOPIA" and s.colorMode ~= "HIGH_CONTRAST" then
		s.colorMode = "NORMAL"
	end
	for k, v in data.flags do
		if type(v) ~= "boolean" then
			data.flags[k] = false
		end
	end
	if type(data.puzzlesSolved) ~= "table" then
		data.puzzlesSolved = {}
	end
	return data
end

DataService.validate = validate

------------------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------------------

local profiles: { [Player]: { data: any, key: string, dirty: boolean, loadedAt: number, released: boolean } } = {}
local loading: { [Player]: boolean } = {}

local function keyFor(userId: number)
	return "u_" .. tostring(userId)
end

local function loadProfile(player: Player)
	local key = keyFor(player.UserId)
	local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
	DataService.JobId = DataService.JobId or jobId
	local result = nil
	for attempt = 1, 6 do
		local blocked = false
		local ok, data = retry("load " .. key, function()
			return store:UpdateAsync(key, function(current)
				current = current or {}
				local lock = current.lock
				local now = os.time()
				if type(lock) == "table" and lock.job ~= DataService.JobId and type(lock.time) == "number" and now - lock.time < GameConfig.Data.SessionLockTimeout and attempt < 6 then
					blocked = true
					return nil -- leave untouched, try again
				end
				current.lock = { job = DataService.JobId, time = now }
				return current
			end)
		end)
		if not ok then
			return nil
		end
		if not blocked then
			result = data
			break
		end
		-- another server still owns the profile; give it time to release
		task.wait(3 + attempt * 2)
		if not player.Parent then
			return nil
		end
	end
	if result == nil then
		return nil
	end
	result.lock = nil
	return validate(result)
end

local function saveProfile(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or profile.released then
		return true
	end
	local data = profile.data
	data.lastSeen = os.time()
	local now = os.clock()
	data.stats.timePlayed += math.max(0, now - (profile.lastTimeSync or profile.loadedAt))
	profile.lastTimeSync = now
	local snapshot = Util.deepCopy(data)
	local ok = retry("save " .. profile.key, function()
		return store:UpdateAsync(profile.key, function(current)
			current = current or {}
			local lock = current.lock
			if type(lock) == "table" and lock.job ~= DataService.JobId then
				-- the profile was taken over by another server: never overwrite it
				return nil
			end
			local out = snapshot
			out.lock = if release then nil else { job = DataService.JobId, time = os.time() }
			return out
		end)
	end)
	if ok then
		profile.dirty = false
		if release then
			profile.released = true
		end
	end
	return ok
end

function DataService:Get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService:WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not profiles[player] and os.clock() < deadline do
		task.wait(0.2)
	end
	return self:Get(player)
end

-- Mutates a profile through a callback. Never yields.
function DataService:Update(player: Player, fn: (any) -> ())
	local profile = profiles[player]
	if not profile then
		return false
	end
	local ok, err = pcall(fn, profile.data)
	if not ok then
		warn("[DataService] update error:", err)
		return false
	end
	profile.dirty = true
	DataService.Changed:Fire(player, profile.data)
	return true
end

function DataService:IsMock(): boolean
	return usingMock
end

function DataService:Init()
	initStore()
end

function DataService:Start()
	local function onPlayerAdded(player: Player)
		if loading[player] then
			return
		end
		loading[player] = true
		local data = loadProfile(player)
		loading[player] = nil
		if not player.Parent then
			if data then
				-- player left during load: release the lock we just took
				profiles[player] = { data = data, key = keyFor(player.UserId), dirty = false, loadedAt = os.clock(), released = false }
				saveProfile(player, true)
				profiles[player] = nil
			end
			return
		end
		if not data then
			-- DataStore is failing: play with defaults, but never save over real data
			warn("[DataService] could not load data for " .. player.Name .. "; using a temporary profile")
			data = Util.deepCopy(TEMPLATE)
			profiles[player] = { data = data, key = keyFor(player.UserId), dirty = false, loadedAt = os.clock(), released = true }
		else
			profiles[player] = { data = data, key = keyFor(player.UserId), dirty = false, loadedAt = os.clock(), released = false }
		end
		DataService.Loaded:Fire(player, data)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			saveProfile(player, true)
			profiles[player] = nil
		end
	end)
	-- autosave
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player, profile in profiles do
				if player.Parent and not profile.released then
					task.spawn(saveProfile, player, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
