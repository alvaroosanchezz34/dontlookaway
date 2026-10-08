--[[
	Scene04_TheEye  (≈11 s)
	Darkness. The eye opens, slowly. It finds the camera. It blinks.
	Silence. It is gone. DON'T LOOK AWAY.
]]

return {
	Name = "Scene04_TheEye",
	Description = "The eye opens, looks at you, blinks",
	Duration = 11,
	Build = function(_L, Config)
		return {
			{ at = 0, action = "Backdrop", on = true },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.6, fadeIn = 2 },
			{ at = 1.0, action = "ShowEye", mode = "screen", scale = 0.78, open = 0.08, fade = 2.4, look = Vector2.new(0.55, 0.15), recreate = true },
			{ at = 1.0, action = "SetEye", open = 1, pupil = 0.3, duration = 3.2, ease = "inOutCubic" },
			-- it finds you
			{ at = 4.2, action = "EyeLook", target = "camera" },
			{ at = 4.5, action = "SetEye", pupil = 0.58, duration = 0.45 },
			{ at = 4.5, action = "PlaySound", sound = "ObserverInhale", volume = 0.45 },
			{ at = 5.9, action = "BlinkEye", duration = 0.34 },
			{ at = 6.6, action = "Silence", level = 0, fade = 0.4 },
			{ at = 7.7, action = "Unsilence", fade = 0 },
			{ at = 7.7, action = "HideEye", fade = 0 },
			{ at = 7.7, action = "PlaySound", sound = "Thud", volume = 0.8 },
			{ at = 7.7, action = "StopSound", name = "ambience" },
			{ at = 8.3, action = "ShowText", id = "title", text = Config.Text.Title .. ".", style = "title", size = 0.05, fadeIn = 0.8, duration = 2.4, tracking = { from = 2, to = 14 } },
		}
	end,
}
