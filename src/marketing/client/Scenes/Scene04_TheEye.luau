--[[
	Scene04_TheEye  (≈13 s)  — the key art, moving.
	A grimy wall, a doorway, a lamp hanging above it. The lamp stutters. The
	door unlatches and swings into the dark. Something in there opens its eye,
	finds you, and does not look away. DON'T LOOK AWAY, scratched in.

	Built as its own small set (Effects/Sets.doorway), far from the map, so it
	looks the same every take and needs no round running.
	Photographic eye: MarketingConfig.EyeImages. Scratched title:
	MarketingConfig.TitleImage (both from assets/marketing, see README).
]]

local Sets = require(script.Parent.Parent.Effects.Sets)

return {
	Name = "Scene04_TheEye",
	Description = "Key art: a door opens on the eye in the dark, scratched title",
	Duration = 13,
	Light = false, -- the hanging lamp is the only light
	Isolated = true,
	Build = function(_L, Config)
		local set = Sets.doorway()
		local far = set.camera(17.5, 5.6)
		local near = set.camera(12.8, 5.9)
		local lampPos = set.lamp.bulb.CFrame.Position
		return {
			-- the look of the key art
			{ at = 0, action = "SetLighting", exposure = 0, ambient = Color3.fromRGB(8, 8, 9), brightness = 0 },
			{ at = 0, action = "Grade", grade = "keyart" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FilmGrain", on = true },
			{ at = 0, action = "AdoptLight", name = "lamp", part = set.lamp.bulb, light = set.lamp.light },
			{ at = 0, action = "SetCamera", cframe = far, preset = "CINEMATIC", fov = 50 },
			{ at = 0, action = "UseDoor", model = set.door, amount = 0 },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1.6 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.75 },
			{ at = 0, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.7, position = lampPos },
			-- the lamp stutters
			{ at = 0.9, action = "FlickerLights", key = "lamp", duration = 0.7, world = false, sound = "LightFlicker", position = lampPos },
			-- the latch gives, then the door swings into the dark
			{ at = 2.4, action = "OpenDoor", amount = 0.06, duration = 0.5, ease = "outQuad" },
			{ at = 2.4, action = "PlaySound", sound = "DoorOpen", position = set.origin.Position + Vector3.new(0, 5, 0), volume = 0.7, speed = 0.6 },
			{ at = 3.5, action = "OpenDoor", amount = 1, duration = 3.4, ease = "inOutSine" },
			{ at = 3.5, action = "PlaySound", sound = "WoodCreak", position = set.origin.Position + Vector3.new(2, 5, -1), volume = 0.8, speed = 0.8 },
			-- something is in there
			{ at = 4.2, action = "ShowEye", mode = "surface", position = set.eyeAt, facing = far.Position, scale = 4.6, brightness = 0.85, intensity = 0, open = 0, fade = 2.6, look = Vector2.new(0.35, 0.2), recreate = true },
			{ at = 6.3, action = "SetEye", open = 1, duration = 1.5, ease = "inOutCubic" },
			{ at = 6.6, action = "PlaySound", sound = "ObserverInhale", position = set.eyeAt, volume = 0.5 },
			{ at = 7.2, action = "EyeLook", target = "camera" },
			{ at = 7.4, action = "SetEye", pupil = 0.3, duration = 0.35 },
			{ at = 7.0, action = "MoveCamera", to = near, duration = 5.6, ease = "creep" },
			{ at = 8.5, action = "FlickerLights", key = "lamp", duration = 0.45, world = false, sound = "LightFlicker", position = lampPos },
			-- the title, scratched in over the doorway
			{ at = 9.0, action = "ShowImage", id = "title", imageKey = "title", position = UDim2.fromScale(0.5, 0.7), width = 0.98, aspect = 1.6, fadeIn = 0.4, flicker = 0.12,
				fallbackText = Config.Text.Title, fallbackStyle = "warning", size = 0.055 },
			{ at = 9.0, action = "PlaySound", sound = "TitleHit", volume = 0.9 },
			{ at = 9.05, action = "Glitch", duration = 0.12, intensity = 0.5, sound = false },
			{ at = 11.4, action = "BlinkEye", duration = 0.4 },
			{ at = 12.4, action = "CutToBlack" },
			{ at = 12.4, action = "StopSound" },
		}
	end,
}
