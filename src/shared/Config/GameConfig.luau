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
	ResultsDuration = 18,
	ReturningDuration = 4,
	MaxRoundTime = 15 * 60, -- hard limit before the building takes everyone
	EscapeWindow = 150, -- seconds to reach the exit once it opens
	CalmOpening = 50, -- guaranteed quiet time at the start of a round
}

GameConfig.Difficulty = {
	EASY = {
		AnomalyQuotaBase = 4,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 12,
		AnomalyLifetime = 200,
		SpawnInterval = { 38, 55 },
		FirstSightingAt = 200,
		FirstHuntAt = 330,
		HuntInterval = { 190, 260 },
		HuntDuration = { 22, 32 },
		ObserverSpeed = 13,
		BlinkAfter = 12,
		MisreportDread = 3,
		BatteryDrain = 0.18,
		DangerousWeight = 0.4,
	},
	NORMAL = {
		AnomalyQuotaBase = 6,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 9,
		AnomalyLifetime = 160,
		SpawnInterval = { 28, 44 },
		FirstSightingAt = 150,
		FirstHuntAt = 260,
		HuntInterval = { 150, 210 },
		HuntDuration = { 28, 40 },
		ObserverSpeed = 15,
		BlinkAfter = 9,
		MisreportDread = 5,
		BatteryDrain = 0.24,
		DangerousWeight = 1,
	},
	HARD = {
		AnomalyQuotaBase = 8,
		AnomalyQuotaPerExtraPlayer = 1,
		MaxMissed = 6,
		AnomalyLifetime = 125,
		SpawnInterval = { 22, 34 },
		FirstSightingAt = 110,
		FirstHuntAt = 190,
		HuntInterval = { 110, 160 },
		HuntDuration = { 34, 48 },
		ObserverSpeed = 17,
		BlinkAfter = 7,
		MisreportDread = 7,
		BatteryDrain = 0.3,
		DangerousWeight = 1.6,
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
