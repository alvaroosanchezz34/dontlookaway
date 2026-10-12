--[[
	I · CAMPAIGN — the five launch videos (docs/CAMPAIGN_VIDEOS.md).

	Vertical first (9:16, 1080x1920), 12-17 s each, every take identical:
	no random placement, a fixed Seed for the screen effects, positions and
	times written out below. Built on the game's own pieces: the impossible
	hallway (Shared/HallwayBuilder, local copy), the Observer rig
	(ObserverRig, local copy), the room and doorway sets.

	  Scene_Campaign01_ItHasntMoved          V1  NO SE HA MOVIDO
	  Scene_Campaign02_TheHallwayNeverEnds   V2  EL PASILLO NO TERMINA
	  Scene_Campaign03_SecurityFootage       V4  LA GRABACIÓN DE SEGURIDAD
	  Scene_Campaign04_ThisFrameShouldNotExist  V7  ESTE FOTOGRAMA NO DEBERÍA EXISTIR
	  Scene_Campaign05_ItHasSeenYou          V10 THE OBSERVER TE HA VISTO

	Every scene ends on black and starts from black, so a platform's
	autoplay loop reads as one more take.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

-- the picture of a total blackout, as the distortion grades it, a little harder
local HALL_GRADE = { Brightness = -0.02, Contrast = 0.2, Saturation = -0.22, TintColor = Color3.fromRGB(255, 206, 200) }
local HALL_EXPOSURE = -0.1

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

-- Opener for the red hallway: grade, grain, the dark, the tubes' buzz.
local function hallOpen(set, cam: CFrame, preset: string, fov: number?): { any }
	return {
		{ at = 0, action = "Grade", grade = HALL_GRADE },
		{ at = 0, action = "Vignette", on = true },
		{ at = 0, action = "FilmGrain", on = true },
		{ at = 0, action = "FadeFromBlack", from = 1, duration = 0.5 },
		{ at = 0, action = "SetLighting", exposure = HALL_EXPOSURE, ambient = Color3.fromRGB(9, 5, 5), brightness = 0 },
		{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.7 },
		{ at = 0, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.3, position = cam.Position },
		{ at = 0, action = "SetCamera", cframe = cam, preset = preset, fov = fov },
	}
end

-- The hallway's power fails for `len` seconds (and comes back unless `stay`).
local function powerCut(set, t: number, len: number, stay: boolean?): { any }
	local list = {
		{ at = t, action = "RunCallback", fn = function()
			set.power(false)
		end },
		{ at = t, action = "PlaySound", sound = "PowerDown", volume = 0.45, speed = 1.8 },
	}
	if not stay then
		table.insert(list, { at = t + len, action = "RunCallback", fn = function()
			set.power(true)
		end })
		table.insert(list, { at = t + len, action = "PlaySound", sound = "LightFlicker", volume = 0.7 })
	end
	return list
end

-- After a cut to black: a black card under the text (the fade layer sits
-- above every title, so it is lifted once the card is in place).
local function card(at: number): { any }
	return {
		{ at = at, action = "Backdrop", on = true, alpha = 1, duration = 0 },
		{ at = at, action = "FadeFromBlack", from = 0, duration = 0 },
	}
end

local function title(at: number, Config): { any }
	return Shots.join(card(at), {
		{ at = at, action = "ShowImage", id = "title", imageKey = "title", position = UDim2.fromScale(0.5, 0.5), width = 0.9, aspect = 1.6, fadeIn = 0.25,
			fallbackText = Config.Text.Title, fallbackStyle = "warning", size = 0.05 },
		{ at = at, action = "PlaySound", sound = "TitleHit", volume = 0.85 },
	})
end

return {
	Category = "I · CAMPAIGN",
	Scenes = {
		--------------------------------------------------------------------------
		-- V1 · NO SE HA MOVIDO
		-- A tripod down the red hallway. Under the last white tube, far away, it
		-- stands still. Every time the power fails it is one lamp closer, never
		-- caught moving. The last time, the lights do not come back: two eyes.
		--------------------------------------------------------------------------
		{
			Name = "Scene_Campaign01_ItHasntMoved",
			Description = "V1 · A tripod down the red hallway. Each power cut, it is one lamp closer. It never moves.",
			Duration = 16,
			Format = "SOCIAL_VERTICAL",
			Seed = 101,
			Light = false,
			Isolated = true,
			Build = function(_L, Config)
				local set = Sets.hallway()
				local CAM_Z = -334
				local cam = set.view(CAM_Z, -430, 5.4, 5.4)
				local function it(z: number): CFrame
					return set.feet(z, CAM_Z)
				end
				return Shots.join(hallOpen(set, cam, "STATIC", 44), {
					-- under the white tube, 92 studs away
					{ at = 0, action = "SpawnEffect", kind = "entity", name = "it", cframe = it(set.SPOT_Z), ash = false },
					{ at = 0.4, action = "ShowText", id = "a", text = "IT HASN'T MOVED.", style = "whisper", position = "upper", size = 0.034, fadeIn = 0.4, duration = 2.6 },
				}, powerCut(set, 4.0, 0.35), {
					{ at = 4.15, action = "PlaceObject", name = "it", to = it(-390) },
				}, powerCut(set, 7.0, 0.3), {
					{ at = 7.12, action = "PlaceObject", name = "it", to = it(-366) },
					{ at = 7.6, action = "ShowText", id = "b", text = "IT ONLY MOVES IN THE DARK.", style = "whisper", position = "lower", size = 0.03, fadeIn = 0.3, duration = 2.2 },
					{ at = 8.0, action = "PlayAmbience", sound = "Heartbeat", name = "heart", volume = 0.5, fadeIn = 1 },
				}, powerCut(set, 9.8, 0.25), {
					{ at = 9.9, action = "PlaceObject", name = "it", to = it(-350) },
				}, powerCut(set, 11.8, 0, true), {
					-- the lights do not come back: it is right there
					{ at = 11.9, action = "PlaceObject", name = "it", to = it(CAM_Z - 8) },
					-- in the black the tripod is knocked upward: the frame its eyes will be in
					{ at = 11.9, action = "SetCamera", cframe = cam * CFrame.Angles(math.rad(17), 0, 0), preset = "STATIC", fov = 44 },
					{ at = 11.9, action = "StopSound", name = "buzz", fadeOut = 0 },
					{ at = 11.9, action = "StopSound", name = "heart", fadeOut = 0.2 },
					{ at = 12.5, action = "EyesGlow", name = "it", on = true },
					{ at = 12.5, action = "PlaySound", sound = "ObserverInhale", position = set.at(0, 8, CAM_Z - 8), volume = 0.8 },
				}, Shots.cut(13.7), title(14.0, Config))
			end,
		},

		--------------------------------------------------------------------------
		-- V2 · EL PASILLO NO TERMINA
		-- First person, walking. Door after door: B-13, B-13, B-13. The power
		-- dies ahead. Footsteps that are not yours. Turn round.
		--------------------------------------------------------------------------
		{
			Name = "Scene_Campaign02_TheHallwayNeverEnds",
			Description = "V2 · Walking the red hallway: every door is B-13. The dark. Steps behind you. Turn round.",
			Duration = 16.5,
			Format = "SOCIAL_VERTICAL",
			Seed = 102,
			Light = false,
			Isolated = true,
			Build = function(_L, Config)
				local set = Sets.hallway()
				local FROM, TO = -60, -252 -- 192 studs at 16 studs/s: 12 s
				local start = set.view(FROM, FROM - 60, 5.2, 5.0)
				local stop = set.view(TO, TO - 60, 5.2, 5.0)
				-- turning round, the eyes go up to its face
				local behind = Shots.turn(stop, 180) * CFrame.Angles(math.rad(22), 0, 0)
				return Shots.join(hallOpen(set, start, "FIRST_PERSON", 70), {
					{ at = 0, action = "MoveCamera", to = stop, duration = 12, ease = "linear" },
				}, Shots.steps(set.at(0, 0, FROM), set.at(0, 0, TO), 0.2, 28, 0.42, { sound = "StepConcrete", volume = 0.45, speed = 0.9 }), {
					-- the doors on the left, as they pass (2.5 s, 5.5 s, 8.5 s)
					{ at = 1.6, action = "ShowText", id = "d1", text = "ROOM B-13", style = "cctv", position = "lower", size = 0.03, fadeIn = 0.2, duration = 1.4 },
					{ at = 4.6, action = "ShowText", id = "d2", text = "ROOM B-13", style = "cctv", position = "lower", size = 0.03, fadeIn = 0.2, duration = 1.4 },
					{ at = 7.6, action = "ShowText", id = "d3", text = "ROOM B-13", style = "cctv", position = "lower", size = 0.03, fadeIn = 0.2, duration = 1.4 },
					{ at = 9.4, action = "PlaySound", sound = "DistantGroan", volume = 0.5 },
				}, powerCut(set, 10.6, 0, true), {
					{ at = 10.6, action = "StopSound", name = "buzz", fadeOut = 0 },
					{ at = 10.9, action = "ShowText", id = "end", text = "IT DOESN'T END.", style = "title", size = 0.045, fadeIn = 0.3, duration = 1.6 },
					-- steps that are not yours, then nothing
					{ at = 12.3, action = "PlaySound", sound = "FootstepsBehind", position = Shots.behind(stop, 3), volume = 0.9 },
					{ at = 12.6, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(set.at(0, 0, TO + 6), stop.Position), ash = false, eyes = true },
					{ at = 13.0, action = "MoveCamera", to = behind, duration = 0.42, ease = "outCubic" },
					{ at = 13.0, action = "RunCallback", fn = function()
						set.power(true)
					end },
					{ at = 13.42, action = "Jolt", amount = 0.45 },
					{ at = 13.42, action = "PlaySound", sound = "ObserverSting", volume = 0.9 },
				}, Shots.cut(14.2), title(14.5, Config))
			end,
		},

		--------------------------------------------------------------------------
		-- V4 · LA GRABACIÓN DE SEGURIDAD
		-- CAM_04, a corner camera over an empty room, 12 fps. The tape skips
		-- hours at a time. Each skip, something is different. The last skip
		-- is one second long.
		--------------------------------------------------------------------------
		{
			Name = "Scene_Campaign03_SecurityFootage",
			Description = "V4 · CAM_04 over an empty room. The tape skips hours; each skip, it is nearer. The last skip is one second.",
			Duration = 17,
			Format = "SOCIAL_VERTICAL",
			Seed = 103,
			Light = 1,
			Isolated = true,
			Build = function(_L, Config)
				local set = Sets.room()
				local cam = set.shot("corner")
				local seat = (set.chair :: Model).PrimaryPart :: BasePart
				local seatAt = seat.CFrame.Position
				local T0 = 3 * 3600 + 17 * 60 + 4
				local function skip(t: number, to: number): { any }
					return {
						{ at = t, action = "Static", alpha = 0.85, duration = 0, sound = "RadioStatic", soundDuration = 0.3 },
						{ at = t, action = "CCTV", on = true, label = "CAM_04  ROOM B-13", start = to },
						{ at = t + 0.18, action = "Static", alpha = 0, duration = 0.08, sound = false },
					}
				end
				return Shots.join(Shots.room(set, { lamp = 0.8 }), Shots.cctv(cam, "CAM_04  ROOM B-13"), {
					{ at = 0, action = "CCTV", on = true, label = "CAM_04  ROOM B-13", start = T0 },
					{ at = 0, action = "AdoptObject", name = "chair", model = set.chair },
					{ at = 0.3, action = "ShowText", id = "a", text = "ASHGROVE · SECURITY FOOTAGE · 1987", style = "cctv", position = "lower", size = 0.026, fadeIn = 0.2, duration = 2.2 },
				}, skip(2.8, T0 + 2 * 3600 + 45 * 60 + 47), {
					-- the chair has turned to face the camera
					{ at = 2.85, action = "PlaceObject", name = "chair", to = CFrame.lookAt(seatAt, Vector3.new(cam.Position.X, seatAt.Y, cam.Position.Z)) },
				}, skip(5.9, T0 + 3 * 3600 + 22 * 60 + 8), {
					-- someone in the far corner, facing the wall
					{ at = 5.95, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(set.at(-9.5, 0, -9.5), set.at(-14, 0, -14)), ash = false },
				}, skip(9.0, T0 + 3 * 3600 + 54 * 60 + 36), {
					-- in the middle of the room, facing the camera
					{ at = 9.05, action = "PlaceObject", name = "it", to = facing(set.at(0.5, 0, -1.5), cam.Position) },
					{ at = 9.05, action = "DimKey", name = "lamp", ratio = 0.45, duration = 0 },
				}, skip(12.0, T0 + 3 * 3600 + 54 * 60 + 37), {
					-- one second later: right under the lens, looking up into it
					{ at = 12.05, action = "PlaceObject", name = "it", to = facing(set.at(8.3, 0, 8.0), cam.Position) },
					{ at = 12.05, action = "EyesGlow", name = "it", on = true },
					{ at = 13.3, action = "Static", alpha = 1, duration = 0.1, sound = "RadioStatic", soundDuration = 1.4 },
					{ at = 13.4, action = "DestroyEffect", name = "it" },
					{ at = 14.0, action = "ShowText", id = "z", text = "THE RECORDING ENDS HERE.", style = "cctv", size = 0.03, fadeIn = 0.2, duration = 1.2 },
				}, Shots.cut(15.3), title(15.5, Config))
			end,
		},

		--------------------------------------------------------------------------
		-- V7 · ESTE FOTOGRAMA NO DEBERÍA EXISTIR
		-- "Nothing happens in this video." A quiet handheld shot of a room.
		-- For 0.05 s (one frame at 30 fps, guaranteed) it stands in front of
		-- the lens. Then the video tells you so.
		--------------------------------------------------------------------------
		{
			Name = "Scene_Campaign04_ThisFrameShouldNotExist",
			Description = "V7 · 'Nothing happens in this video.' One frame of it, face to the lens. Then: go back.",
			Duration = 12,
			Format = "SOCIAL_VERTICAL",
			Seed = 104,
			Light = 1,
			Isolated = true,
			Build = function(_L, Config)
				local set = Sets.room()
				local cam = set.shot("window")
				-- about 8 studs ahead, a little left of the lens, facing it: close
				-- enough to fill the frame, far enough for its eyes to be in it
				local closeAt = facing(set.at(0.8, 0, -3.0), cam.Position)
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD", lamp = 0.85, grain = true, fade = 0.3, ambience = "AmbientHum", volume = 0.9 }), {
					{ at = 0.2, action = "MoveCamera", to = cam * CFrame.new(0, 0.1, -2.5), duration = 9, ease = "creep" },
					{ at = 0.2, action = "ShowText", id = "a", text = "nothing happens in this video.", style = "whisper", position = "upper", size = 0.032, fadeIn = 0.3, duration = 2.4 },
					{ at = 3.4, action = "SpawnEffect", kind = "entity", name = "it", cframe = closeAt, ash = false, eyes = true },
					{ at = 3.4, action = "DimKey", name = "lamp", ratio = 0.3, duration = 0 },
					{ at = 3.45, action = "DestroyEffect", name = "it" },
					{ at = 3.45, action = "DimKey", name = "lamp", ratio = 0.85, duration = 0 },
					{ at = 6.2, action = "ShowText", id = "b", text = "THERE IS ONE FRAME IN THIS VIDEO", style = "title", position = "upper", size = 0.034, fadeIn = 0.2, duration = 3.4 },
					{ at = 7.4, action = "ShowText", id = "c", text = "THAT SHOULD NOT EXIST.", style = "warning", position = "lower", size = 0.036, fadeIn = 0.2, duration = 2.2 },
					{ at = 7.4, action = "PlaySound", sound = "ObserverInhale", position = Shots.behind(cam, 2), volume = 0.4 },
				}, Shots.cut(9.8), card(10.0), {
					{ at = 10.0, action = "ShowText", id = "d", text = "GO BACK.", style = "whisper", size = 0.04, fadeIn = 0.2, duration = 1.6 },
				})
			end,
		},

		--------------------------------------------------------------------------
		-- V10 · THE OBSERVER TE HA VISTO
		-- A slow push toward a doorway onto black. Two pale points light up in
		-- the dark: it has been standing there all along. The lamp stutters:
		-- the whole of it, for an instant. The lamp dies. Its eye.
		--------------------------------------------------------------------------
		{
			Name = "Scene_Campaign05_ItHasSeenYou",
			Description = "V10 · A push toward a black doorway. Its eyes light up: it was there all along. It has seen you.",
			Duration = 15,
			Format = "SOCIAL_VERTICAL",
			Seed = 105,
			Light = false,
			Isolated = true,
			Build = function(_L, Config)
				local set = Sets.doorway()
				local o = set.origin
				return Shots.join(Shots.doorway(set, { door = 0.92, lamp = 0.55 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(20, 5.8), preset = "CINEMATIC", fov = 40 },
					{ at = 0, action = "MoveCamera", to = set.camera(8.5, 6.6), duration = 10.5, ease = "creep" },
					-- it is there from the first frame, in the black
					{ at = 0, action = "SpawnEffect", kind = "entity", name = "it", cframe = o * CFrame.new(0, 0, -2.6), ash = false },
					{ at = 4.2, action = "EyesGlow", name = "it", on = true },
					{ at = 4.2, action = "PlaySound", sound = "ObserverInhale", position = set.eyeAt, volume = 0.6 },
					{ at = 4.6, action = "ShowText", id = "a", text = "IT WAS THERE ALL ALONG.", style = "whisper", position = "lower", size = 0.03, fadeIn = 0.4, duration = 2.4 },
					{ at = 7.6, action = "FlickerLights", key = "lamp", duration = 0.5, world = false, sound = "LightFlicker", position = set.lamp.bulb.CFrame.Position },
					{ at = 9.0, action = "DimKey", name = "lamp", ratio = 0, duration = 0.08 },
					{ at = 9.0, action = "StopSound", name = "buzz", fadeOut = 0 },
					{ at = 9.0, action = "PlaySound", sound = "BulbPop", volume = 0.8 },
					{ at = 9.6, action = "ShowText", id = "b", text = "IT HAS SEEN YOU.", style = "warning", size = 0.045, fadeIn = 0.15, duration = 1.8 },
					{ at = 11.6, action = "ShowEye", mode = "screen", scale = 0.85, fade = 0, look = "camera", recreate = true },
					{ at = 11.6, action = "PlaySound", sound = "ObserverSting", volume = 0.8 },
					{ at = 12.2, action = "BlinkEye", duration = 0.3 },
					{ at = 12.5, action = "HideEye", fade = 0 },
				}, Shots.cut(12.5), title(12.8, Config))
			end,
		},
	},
}
