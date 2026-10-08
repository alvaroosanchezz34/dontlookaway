--[[
	MarketingConfig
	Settings of MARKETING STUDIO, the developer-only scene recorder used to make
	teasers, trailers and vertical clips (see src/marketing/README.md).

	It can never run on a public server: besides `Enabled`, the place must be
	running in Roblox Studio (or, if you allow it, a private server you own)
	and the player must be authorised. Everything it does is local to that
	player's screen; nothing replicates and no gameplay system is touched.
]]

local MarketingConfig = {}

-- Master switch. Even when true, Marketing Studio only exists where the
-- environment rules below allow it (never on public servers).
MarketingConfig.Enabled = true

-- Where it may run.
MarketingConfig.AllowInStudio = true
MarketingConfig.AllowInPrivateServers = false -- VIP servers owned by an authorised user

-- Who may use it. Add Roblox UserIds (numbers) here.
MarketingConfig.AdminUserIds = {}
-- The experience owner (user-owned places) is always authorised.
MarketingConfig.AllowPlaceOwner = true
-- Studio "local server" test players have UserIds <= 0.
MarketingConfig.AllowStudioTestPlayers = true

-- Panel
MarketingConfig.ToggleKey = Enum.KeyCode.F7
MarketingConfig.AltToggleKeys = { Enum.KeyCode.F6 } -- plus the 🎬 button, bottom right
MarketingConfig.DefaultFormat = "SOCIAL_VERTICAL"
MarketingConfig.DefaultCamera = "AUTO" -- AUTO = each shot's own preset

-- Scene defaults (the panel can change them)
MarketingConfig.Defaults = {
	HideHUD = true, -- hide the game's interface while a scene plays
	HideCharacter = true, -- hide your own character from the cinematic camera
	FreezeCharacter = true, -- keep your character still while recording
	MuteGameAudio = true, -- only the scene's own sounds are heard
	HidePanelWhilePlaying = true,
	Loop = false,
	TimeScale = 1, -- 0.5 = slow motion
	HoldAtEnd = 0.6,
	Light = 3, -- fill light / exposure lift: 0 = off .. 4 = bright (not used on black-card scenes) -- seconds held on the last frame before cleaning up
}

-- THE EYE, photographic version: the 7 images in assets/marketing/eye
-- (made by tools/gen_eye.py, original). Upload them as images and paste the ids.
-- While sclera/iris/pupil/socket are 0, the simple drawn eye is used instead.
MarketingConfig.EyeImages = {
	sclera = 125309156635474, -- eye_sclera.png
	iris = 123562452057138, -- eye_iris.png
	pupil = 117557984089460, -- eye_pupil.png
	glint = 84615934958847, -- eye_glint.png
	lidTop = 119064074922165, -- eye_lid_top.png
	lidBottom = 110901365964487, -- eye_lid_bot.png
	socket = 85762611587195, -- eye_socket.png
}

-- The scratched title image (assets/marketing/title_dla.png, made by
-- tools/gen_title.py). 0 = use the text title instead.
MarketingConfig.TitleImage = 94932983081889

-- Text used by the teaser scenes (edit for the campaign).
MarketingConfig.Text = {
	Title = "DON'T LOOK AWAY",
	Countdown = "3 DAYS.",
	Launch = "NOW PLAYING",
}

return MarketingConfig
