--[[
	A · THE EYE — the brand's symbol. Built on the key-art doorway set and the
	room set (Effects/Sets), so every take looks the same and needs no round.
	The eye is drawn on the screen layer, pinned to a point in the set
	("anchored"); in narrow gaps it is scaled with the gap.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

return {
	Category = "A · THE EYE",
	Scenes = {
		{
			Name = "Scene_EyeInTheDark",
			Description = "A dim room, a doorway; a glint in the dark becomes an eye. One blink.",
			Duration = 12,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				local o = set.origin
				return Shots.join(Shots.doorway(set, { door = 0.85, lamp = 0.45 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(19, 5.6), preset = "CINEMATIC", fov = 46 },
					{ at = 0, action = "MoveCamera", to = set.camera(11.5, 6.0), duration = 10, ease = "creep" },
					-- a point of light where there should be nothing
					{ at = 3, action = "SpawnEffect", kind = "shine", name = "glint", cframe = o * CFrame.new(0.25, 6.4, -2.6), gap = 0, size = 0.07 },
					{ at = 5.4, action = "ShowEye", mode = "anchored", position = set.eyeAt, scale = 3.8, brightness = 0.8, open = 0.35, fade = 3, look = "camera", recreate = true },
					{ at = 5.6, action = "DestroyEffect", name = "glint" },
					{ at = 6.4, action = "SetEye", open = 1, pupil = 0.32, duration = 2.2, ease = "inOutCubic" },
					{ at = 8.8, action = "Silence", level = 0, fade = 0.6 },
					{ at = 8.8, action = "StopSound", name = "buzz", fadeOut = 0.6 },
					{ at = 10.4, action = "BlinkEye", duration = 0.36 },
				}, Shots.cut(11.1))
			end,
		},
		{
			Name = "Scene_EyeBehindDoor",
			Description = "Three soft knocks, a door ajar, an eye in the gap watching until it shuts.",
			Duration = 10,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				local o = set.origin
				local gap = (o * CFrame.new(-1.85, 6.4, -0.9)).Position
				local doorAt = (o * CFrame.new(0, 5, -0.6)).Position
				return Shots.join(Shots.doorway(set, { door = 0.32 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(9.5, 6.1), preset = "DOOR_SHOT", fov = 42 },
				}, Shots.knocks(1.0, doorAt, 3, 0.55, { volume = 0.35 }), {
					{ at = 3.0, action = "OpenDoor", amount = 0.45, duration = 0.6, ease = "outQuad" },
					{ at = 3.0, action = "PlaySound", sound = "WoodCreak", position = doorAt, volume = 0.6 },
					{ at = 3.7, action = "ShowEye", mode = "anchored", position = gap, scale = 0.85, brightness = 0.75, fade = 0.5, look = "camera", recreate = true },
					-- the door closes; the eye keeps looking until the last moment
					{ at = 6.0, action = "CloseDoor", amount = 0, duration = 2.0, ease = "inQuad" },
					{ at = 6.0, action = "SetEye", scale = 0.12, duration = 2.0, ease = "inQuad" },
					{ at = 7.95, action = "HideEye", fade = 0 },
					{ at = 8.0, action = "PlaySound", sound = "DoorSlam", position = doorAt, volume = 0.9 },
					{ at = 8.0, action = "Jolt", amount = 0.4 },
				}, Shots.cut(8.25))
			end,
		},
		{
			Name = "Scene_EyeTracksCamera",
			Description = "The camera pans across a room; an eye in the window follows it, and keeps moving after it stops.",
			Duration = 12.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local eyeAt = set.at(0.4, 7.4, -12.7)
				local from = CFrame.lookAt(set.at(-8, 5.6, 9), set.at(0, 6.8, -12.5))
				local to = CFrame.lookAt(set.at(8, 5.6, 9), set.at(0, 6.8, -12.5))
				return Shots.join(Shots.room(set, { camera = from, lamp = 0.55 }), {
					{ at = 0.5, action = "ShowEye", mode = "anchored", position = eyeAt, scale = 1.25, brightness = 0.55, fade = 1.5, look = "follow", recreate = true },
					{ at = 0.6, action = "EyeLook", target = "follow" },
					{ at = 1.2, action = "MoveCamera", to = to, duration = 7, ease = "inOutSine" },
					{ at = 9.6, action = "Silence", level = 0, fade = 0.4 },
				}, Shots.cut(11.6))
			end,
		},
		{
			Name = "Scene_TheWrongBlink",
			Description = "Close-up of the eye: a blink, a slower blink, one that lasts too long, and it opens much closer.",
			Duration = 8,
			Light = false,
			Build = function()
				return Shots.join(Shots.black({ volume = 0.5 }), {
					{ at = 0.3, action = "ShowEye", mode = "screen", scale = 0.62, fade = 0.8, look = "camera", recreate = true },
					{ at = 2.0, action = "BlinkEye", duration = 0.3 },
					{ at = 3.5, action = "BlinkEye", duration = 0.75 },
					{ at = 4.9, action = "SetEye", open = 0, duration = 0.18 },
					{ at = 4.9, action = "Silence", level = 0.1, fade = 0.3 },
					-- it opens much closer
					{ at = 6.3, action = "SetEye", scale = 1.35, duration = 0 },
					{ at = 6.3, action = "SetEye", open = 1, pupil = 0.22, duration = 0.12 },
					{ at = 6.3, action = "Unsilence", fade = 0 },
					{ at = 6.3, action = "PlaySound", sound = "ObserverSting", volume = 0.6, speed = 1.3, duration = 0.45, fadeOut = 0.1 },
					{ at = 6.32, action = "Glitch", duration = 0.12, intensity = 0.6, sound = false },
				}, Shots.cut(6.9))
			end,
		},
		{
			Name = "Scene_EyeInTheReflection",
			Description = "A mirror in a normal room holds an eye that is not in the room. Look away, look back.",
			Duration = 12,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local mirrorShot = set.shot("mirror")
				local inMirror = (set.mirrorCf * CFrame.new(0.3, 0.35, -0.1)).Position
				-- where a reflection there would come from: across the room
				local realSpot = set.at(9, 6.5, 2.5)
				local lookReal = CFrame.lookAt(mirrorShot.Position, realSpot)
				return Shots.join(Shots.room(set, { camera = mirrorShot, preset = "HANDHELD" }), {
					{ at = 1.8, action = "ShowEye", mode = "anchored", position = inMirror, scale = 0.95, brightness = 0.7, fade = 1.2, look = Vector2.new(-0.4, 0), recreate = true },
					{ at = 3.4, action = "MoveCamera", to = Shots.turn(mirrorShot, 7) * CFrame.new(0.8, 0, 0), duration = 2.4, ease = "inOutSine" },
					{ at = 6.0, action = "HideEye", fade = 0.05, destroy = false },
					{ at = 6.0, action = "MoveCamera", to = lookReal, duration = 0.9, ease = "outCubic" },
					{ at = 8.2, action = "MoveCamera", to = mirrorShot, duration = 0.8, ease = "inOutSine" },
					{ at = 9.1, action = "ShowEye", mode = "anchored", position = inMirror, scale = 1.05, brightness = 0.75, fade = 0.15, look = "camera" },
					{ at = 9.2, action = "SetEye", pupil = 0.55, duration = 0.4 },
					{ at = 9.1, action = "PlaySound", sound = "ObserverInhale", volume = 0.4 },
				}, Shots.cut(10.8))
			end,
		},
		{
			Name = "Scene_EyeAppearsForOneFrame",
			Description = "A normal room, a barely-there interference, the eye for an instant. DID YOU SEE IT?",
			Duration = 7,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				return Shots.join(Shots.room(set, { camera = set.shot("center"), preset = "HANDHELD" }), {
					{ at = 2.4, action = "Glitch", duration = 0.08, intensity = 0.25, sound = false },
					{ at = 2.42, action = "ShowEye", mode = "anchored", position = set.at(9.5, 5, -9.2), scale = 1.6, brightness = 0.7, fade = 0, look = "camera", recreate = true },
					{ at = 2.5, action = "HideEye", fade = 0 },
					{ at = 5.0, action = "ShowText", id = "q", text = "DID YOU SEE IT?", style = "whisper", size = 0.034, fadeIn = 0.3, duration = 1.4 },
				}, Shots.cut(6.6))
			end,
		},
	},
}
