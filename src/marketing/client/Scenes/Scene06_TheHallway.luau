--[[
	Scene06_TheHallway  (≈12 s)
	A long corridor. The camera walks it slowly. Nothing. A light flickers.
	The camera stops. Something is standing at the far end. Cut.
]]

return {
	Name = "Scene06_TheHallway",
	Category = "0 · ORIGINALS",
	Description = "Something at the end of the corridor",
	Duration = 12,
	Build = function(L)
		local from, _, length = L.corridor("G")
		local push = math.min(length * 0.3, 14)
		local stopCam = from * CFrame.new(0, 0, -push)
		local farPos = L.corridorPoint("G", 0.92)
		local camGround = Vector3.new(stopCam.Position.X, farPos.Y, stopCam.Position.Z)
		local entityFeet = CFrame.lookAt(farPos, camGround)
		local flickerAt = L.corridorPoint("G", 0.45, 12)
		return {
			{ at = 0, action = "SetCamera", cframe = from, preset = "HALLWAY" },
			{ at = 0, action = "Grade", grade = "dread" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1.4 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.8 },
			{ at = 0, action = "PlayAmbience", sound = "Ventilation", name = "air", volume = 0.6 },
			{ at = 0, action = "MoveCamera", to = stopCam, duration = 8, ease = "creep" },
			{ at = 5.0, action = "FlickerLights", position = flickerAt, radius = 16, duration = 1.4, depth = 1.6 },
			-- the camera stops; the building holds its breath
			{ at = 8.0, action = "Silence", level = 0.1, fade = 0.8 },
			{ at = 9.0, action = "SpawnEffect", kind = "entity", name = "it", cframe = entityFeet, ash = false },
			{ at = 9.0, action = "FadeObject", name = "it", from = 1, to = 0.1, duration = 0.5 },
			{ at = 9.0, action = "KeyLight", name = "rim", kind = "point", cframe = entityFeet * CFrame.new(0, 9, 3), range = 12, brightness = 1.4, color = Color3.fromRGB(170, 190, 255), fadeIn = 0.6 },
			{ at = 9.1, action = "Unsilence", fade = 0.05 },
			{ at = 9.1, action = "PlaySound", sound = "ObserverInhale", position = farPos + Vector3.new(0, 8, 0), volume = 0.6 },
			{ at = 10.7, action = "CutToBlack" },
			{ at = 10.7, action = "StopSound" },
		}
	end,
}
