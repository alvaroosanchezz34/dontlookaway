--[[
	State
	Client-side mirror of what the server has told us. Read-only for gameplay
	purposes: the server stays authoritative, this only drives UI and effects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local State = {
	profile = nil,
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
		filmGrain = true,
		grainIntensity = 0.3,
		graphics = "AUTO",
		colorMode = "NORMAL",
	},
	round = { state = "LOBBY", difficulty = "NORMAL", seed = 0, elapsed = 0 },
	lobby = nil,
	inventory = { slots = {}, selected = 1, battery = 100, light = false },
	objectives = { list = {}, found = 0, quota = 0 },
	players = {},
	status = "MENU",
	stamina = 100,
	sprinting = false,
	fear = 0, -- 0..1, how scared the local player should feel (drives UI fade, heartbeat)
	observerDistance = math.huge,
	prox = "FAR", -- FAR | AWARE | NEAR | VERY_NEAR | HUNT (server-decided, see ObserverService)
	notes = {}, -- documents read this round
	inputType = "Keyboard", -- Keyboard | Gamepad | Touch
	uiOpen = false, -- a menu panel has focus (mouse unlocked)
	scareDark = false, -- a jumpscare owns the screen: lights, HUD, sound and look input are off (ScareController)
	distortion = nil :: string?, -- a reality distortion this player is living (DistortionController)
	distortionPhase = nil :: string?, -- arrive | notice | wake | chase | taken (the music follows it)
	phase = "CALM",
	storyPhase = "ARRIVAL",
	tools = { tools = {}, selected = 0 }, -- this round's equipment belt
	gear = nil, -- owned equipment / loadout / upgrades (from EquipmentService)
	challenges = nil, -- daily / weekly challenge snapshot

	ProfileChanged = Signal.new(),
	SettingsChanged = Signal.new(),
	RoundChanged = Signal.new(),
	LobbyChanged = Signal.new(),
	InventoryChanged = Signal.new(),
	ObjectivesChanged = Signal.new(),
	StatusChanged = Signal.new(),
	InputTypeChanged = Signal.new(),
	UIOpenChanged = Signal.new(),
	GearChanged = Signal.new(),
	ChallengesChanged = Signal.new(),
}

-- Reasons the mouse cursor is free besides an open panel (the case file,
-- the player's own Alt toggle): the camera only locks it when none is held.
local mouseHolders: { [string]: boolean } = {}
State.MouseFreeChanged = Signal.new()

function State.holdMouse(reason: string, on: boolean)
	local was = next(mouseHolders) ~= nil
	if on then
		mouseHolders[reason] = true
	else
		mouseHolders[reason] = nil
	end
	if was ~= (next(mouseHolders) ~= nil) then
		State.MouseFreeChanged:Fire(not was)
	end
end

function State.isMouseHeld(reason: string): boolean
	return mouseHolders[reason] == true
end

-- Should the cursor be free (and the view stop following the mouse)?
function State.mouseFree(): boolean
	return State.uiOpen or next(mouseHolders) ~= nil
end

function State.setUIOpen(open: boolean)
	if State.uiOpen ~= open then
		State.uiOpen = open
		State.UIOpenChanged:Fire(open)
	end
end

function State.isPlaying(): boolean
	return State.status == "ALIVE"
end

return State
