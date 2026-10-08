--[[
	Scene02_DidYouSeeIt  (≈9.8 s)
	An ordinary room. The camera creeps forward. For a few frames the eye is
	there, in the back of the room. Gone. DID YOU SEE IT?
]]

return {
	Name = "Scene02_DidYouSeeIt",
	Description = "A few frames of the eye in an ordinary room",
	Duration = 9.8,
	Build = function(L)
		local cam, far = L.roomShot({ "G_k", "U_o", "G_a", "U_j" })
		local dir = (far - cam.Position).Unit
		local eyeAt = far - dir * 1.8 + cam.RightVector * 2.4 + Vector3.new(0, 0.6, 0)
		return {
			{ at = 0, action = "SetCamera", cframe = cam, preset = "HANDHELD" },
			{ at = 0, action = "Grade", grade = "dread" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1.1 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.7 },
			{ at = 0.4, action = "PlayAmbience", sound = "ClockTick", name = "clock", volume = 0.5, position = far },
			{ at = 0, action = "MoveCamera", to = cam * CFrame.new(0, -0.1, -4), duration = 7.6, ease = "creep" },
			-- four frames
			{ at = 5.3, action = "ShowEye", mode = "world", position = eyeAt, scale = 1.5, intensity = 0.5, fade = 0, look = "camera", recreate = true },
			{ at = 5.3, action = "PlaySound", sound = "Whisper", volume = 0.12 },
			{ at = 5.4, action = "HideEye", fade = 0 },
			{ at = 7.4, action = "CutToBlack" },
			{ at = 7.4, action = "StopSound" },
			{ at = 7.8, action = "ShowText", id = "q", text = "DID YOU SEE IT?", style = "whisper", size = 0.036, fadeIn = 0.5, duration = 1.6 },
		}
	end,
}
