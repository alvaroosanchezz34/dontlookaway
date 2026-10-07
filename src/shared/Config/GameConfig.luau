--[[
	GameConfig
	Every gameplay tunable lives here so balancing never requires touching systems.
]]

local GameConfig = {}

GameConfig.GameName = "DON'T LOOK AWAY"
GameConfig.Tagline = "THE WORLD CHANGES WHEN YOU STOP LOOKING."
GameConfig.BuildingName = "THE ASHGROVE BUILDING"
GameConfig.Version = "1.0.0"

GameConfig.MaxPlayers = 4

-- Owner / admin access. The place creator (or group owner) is always an admin.
-- Additional trusted UserIds can be listed here.
GameConfig.AdminUserIds = {}

GameConfig.Round = {
	LobbyCountdown = 20, -- seconds after the first player readies up
	AllReadyCountdown = 5, -- seconds once everyone in the lobby is ready
	StartingDuration = 30, -- max time outside before the front doors slam
	ResultsDuration = 22,
	ReturningDuration = 4,
	MaxRoundTime = 22 * 60, -- hard limit before the building takes everyone
	EscapeWindow = 150, -- seconds to reach the exit once it opens
}

--[[
	Difficulty
	  NORMAL     a gentle first night: long arrival, more batteries, slower and
	             more readable Observer, generous hints
	  HARD       less light, more anomalies, a smarter Observer, fewer hints
	  NIGHTMARE  maximum tension: short arrival, scarce batteries, complex
	             anomalies, the Observer uses the dark and blinks closer; hints
	             stop at gentle nudges
	Phase durations are in seconds (ARRIVAL ends with the power failure; the
	later phases also advance early with progress).
]]
GameConfig.Difficulty = {
	NORMAL = {
		AnomalyQuotaBase = 5,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 12,
		AnomalyLifetime = 190,
		SpawnInterval = { 34, 50 },
		HuntInterval = { 170, 240 },
		HuntDuration = { 22, 32 },
		ObserverSpeed = 13.5,
		BlinkAfter = 11,
		MisreportDread = 3,
		BatteryDrain = 0.18,
		DangerousWeight = 0.5,
		ArrivalDuration = 200,
		PhaseDurations = { UNEASE = 150, DISTORTION = 170, DANGER = 210 },
		ExtraBatteries = 2,
		HintDelay = 70, -- seconds without progress before the first nudge
		HintMaxLevel = 5,
		ObserverCunning = 0, -- 0..2: use of darkness, blink steps, mimic frequency
		WarningTime = 2.2, -- seconds of audible warning before a catch is possible
		RewardMultiplier = 1,
	},
	HARD = {
		AnomalyQuotaBase = 7,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 8,
		AnomalyLifetime = 150,
		SpawnInterval = { 26, 40 },
		HuntInterval = { 130, 180 },
		HuntDuration = { 30, 42 },
		ObserverSpeed = 15.5,
		BlinkAfter = 8.5,
		MisreportDread = 6,
		BatteryDrain = 0.26,
		DangerousWeight = 1.2,
		ArrivalDuration = 150,
		PhaseDurations = { UNEASE = 120, DISTORTION = 140, DANGER = 170 },
		ExtraBatteries = 0,
		HintDelay = 120,
		HintMaxLevel = 4,
		ObserverCunning = 1,
		WarningTime = 1.6,
		RewardMultiplier = 1.4,
	},
	NIGHTMARE = {
		AnomalyQuotaBase = 9,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 5,
		AnomalyLifetime = 115,
		SpawnInterval = { 20, 32 },
		HuntInterval = { 95, 140 },
		HuntDuration = { 36, 50 },
		ObserverSpeed = 17.5,
		BlinkAfter = 6.5,
		MisreportDread = 8,
		BatteryDrain = 0.32,
		DangerousWeight = 1.8,
		ArrivalDuration = 100,
		PhaseDurations = { UNEASE = 90, DISTORTION = 110, DANGER = 140 },
		ExtraBatteries = -1,
		HintDelay = 200,
		HintMaxLevel = 2,
		ObserverCunning = 2,
		WarningTime = 1.1,
		RewardMultiplier = 2,
	},
}

GameConfig.Movement = {
	WalkSpeed = 10,
	SprintSpeed = 17,
	CrouchSpeed = 6,
	Acceleration = 7.5, -- higher = snappier
	Deceleration = 9,
	StaminaMax = 100,
	StaminaDrain = 16, -- per second while sprinting
	StaminaRegen = 13,
	StaminaRegenDelay = 1.1,
	StaminaMinToSprint = 18,
	-- Anti-exploit speed ceiling (studs/s, horizontal). Includes generous tolerance for lag.
	ServerSpeedLimit = 26,
}

GameConfig.Camera = {
	DefaultFOV = 74,
	MinFOV = 60,
	MaxFOV = 95,
	DefaultSensitivity = 0.55,
	HeadBobAmplitude = 0.075,
	HeadBobFrequency = 1.65,
	MaxPitch = 82,
}

GameConfig.Flashlight = {
	MaxBattery = 100,
	Brightness = 2.6,
	Range = 46,
	Angle = 52,
	LowBatteryThreshold = 20,
	BatteryItemRestore = 55,
}

GameConfig.Interaction = {
	MaxDistance = 9,
	ServerMaxDistance = 13,
}

GameConfig.Report = {
	HoldTime = 0.75,
	MaxDistance = 75,
	Cooldown = 1.4,
	ServerAngleTolerance = 0.2, -- extra radians allowed around the anomaly bounds
}

GameConfig.Inventory = {
	Slots = 4,
}

GameConfig.Ping = {
	Cooldown = 2.5,
	BurstLimit = 5,
	BurstWindow = 20,
	Duration = 9,
	MaxDistance = 140,
}

GameConfig.Observer = {
	CatchDistance = 4.2,
	WatchFOV = 64, -- half-angle in degrees used to decide whether a player is looking
	SightingMinDistance = 38,
	SightingMaxDistance = 110,
	PresenceRadius = 48, -- flashlight interference radius
	StareForcedBlinkDuration = 0.35,
}

GameConfig.Rewards = {
	EchoesPerMinute = 4,
	EchoesPerAnomaly = 6,
	EchoesEscape = 40,
	EchoesSurvivedTeamBonus = 15,
	XPPerMinute = 10,
	XPPerAnomaly = 18,
	XPEscape = 90,
	XPDeath = 20,
	FirstDiscoveryBonusEchoes = 10,
	EchoesPerLock = 8, -- each exit lock the team released
	EchoesPerEvidence = 4, -- each anomaly documented with the instant camera
	FriendsBonus = 0.1, -- +10% when you played with others
	XPPerLock = 25,
}

GameConfig.Data = {
	StoreName = "DLA_PlayerData_v1",
	AutosaveInterval = 90,
	SessionLockTimeout = 60 * 30,
	MaxRetries = 5,
}

-- Monetization: game pass ids are created on the Creator Dashboard. A value of 0
-- means "not configured" and the matching store entry is hidden automatically.
GameConfig.GamePasses = {
	VIP = 0,
	FlashlightCollection = 0,
	EmotePack = 0,
	ExtraLoadouts = 0,
}

return GameConfig
