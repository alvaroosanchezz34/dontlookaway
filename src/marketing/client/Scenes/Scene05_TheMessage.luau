--[[
	Scene05_TheMessage  (≈9 s)
	A mirror (or a wall). Words appear on it, one at a time:
	DON'T ... LOOK ... AW—  Cut before the last word.
]]

return {
	Name = "Scene05_TheMessage",
	Description = "Words written on a mirror, cut before the last one",
	Duration = 9,
	Build = function(L)
		local glass = L.mirror()
		local writeCf, cam, size, backing
		if glass then
			-- on the glass, facing the room
			writeCf = glass.CFrame * CFrame.new(0, 0, -(glass.Size.Z / 2 + 0.03))
			size = Vector2.new(glass.Size.X * 0.9, glass.Size.Y * 0.8)
			local eye = (glass.CFrame * CFrame.new(0, -0.2, -7.5)).Position
			cam = CFrame.lookAt(eye, glass.Position)
			backing = false
		else
			local ref = L.reference()
			local wallCenter = (ref * CFrame.new(0, 5.6, -8)).Position
			writeCf = CFrame.lookAt(wallCenter, wallCenter - ref.LookVector)
			size = Vector2.new(4, 3.4)
			cam = CFrame.lookAt((ref * CFrame.new(0, 5.4, 0)).Position, wallCenter)
			backing = true
		end
		local at = writeCf.Position
		return {
			{ at = 0, action = "SetCamera", cframe = cam, preset = "CINEMATIC", fov = 42 },
			{ at = 0, action = "Grade", grade = "cold" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.7 },
			{ at = 0, action = "PlayAmbience", sound = "Drip", name = "drip", volume = 0.5, position = at },
			{ at = 0, action = "SurfaceText", id = "msg", cframe = writeCf, size = size, backing = backing },
			{ at = 0, action = "MoveCamera", to = cam * CFrame.new(0, 0, -1.6), duration = 7, ease = "creep" },
			{ at = 2.0, action = "WriteText", id = "msg", text = "DON'T" },
			{ at = 2.0, action = "PlaySound", sound = "RealityShift", volume = 0.35 },
			{ at = 4.2, action = "WriteText", id = "msg", text = "DON'T\nLOOK" },
			{ at = 4.2, action = "PlaySound", sound = "RealityShift", volume = 0.45, speed = 0.9 },
			{ at = 6.3, action = "WriteText", id = "msg", text = "DON'T\nLOOK\nAW" },
			{ at = 6.3, action = "FlickerLights", position = at + Vector3.new(0, 4, 0), radius = 18, duration = 0.5, depth = 2 },
			{ at = 6.7, action = "Glitch", duration = 0.18, intensity = 0.7 },
			{ at = 6.9, action = "CutToBlack" },
			{ at = 6.9, action = "StopSound" },
		}
	end,
}
