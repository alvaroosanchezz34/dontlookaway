--[[
	Scene03_CAM04  (≈12 s)
	Security camera, CAM_04. Someone walks into the corridor and stops. The
	lights fail. In the static, for one second, IT is standing where they were.
	Then nobody. The camera keeps recording.

	The someone is a real Roblox character (a local copy of your avatar).
]]

return {
	Name = "Scene03_CAM04",
	Description = "Security footage: someone who is no longer there",
	Duration = 12,
	Build = function(L)
		local cam, walkFrom, walkTo = L.cctvShot("G")
		local stop = walkFrom:Lerp(walkTo, 0.5)
		local feet = CFrame.lookAt(walkFrom, Vector3.new(walkTo.X, walkFrom.Y, walkTo.Z))
		local stopCf = CFrame.lookAt(stop, Vector3.new(walkTo.X, stop.Y, walkTo.Z))
		-- it faces the camera
		local camGround = Vector3.new(cam.Position.X, stop.Y, cam.Position.Z)
		local itCf = CFrame.lookAt(stop, camGround)
		local away = walkFrom + (walkFrom - walkTo).Unit * 18
		return {
			{ at = 0, action = "SetCamera", cframe = cam, preset = "CCTV" },
			{ at = 0, action = "CCTV", on = true, label = "CAM_04  ·  CORRIDOR G" },
			{ at = 0, action = "Grade", grade = "cctv" },
			{ at = 0, action = "PlayAmbience", sound = "AmbientHum", volume = 1.4 },
			{ at = 0, action = "PlayAmbience", sound = "TapeHiss", name = "hiss", volume = 0.5 },
			{ at = 0, action = "SpawnEffect", kind = "actor", name = "staff", cframe = feet },
			{ at = 0.6, action = "MoveObject", name = "staff", to = stopCf, duration = 4.2 },
			{ at = 0.6, action = "PlaySound", sound = "DistantFootsteps", position = stop, volume = 0.6 },
			-- they stop; the lights go
			{ at = 5.3, action = "FlickerLights", position = stop + Vector3.new(0, 10, 0), radius = 30, duration = 1.3, depth = 2.4 },
			{ at = 6.4, action = "Glitch", duration = 0.3, intensity = 0.9 },
			{ at = 6.5, action = "DestroyEffect", name = "staff" },
			-- one second: IT, where they were
			{ at = 6.5, action = "SpawnEffect", kind = "entity", name = "it", cframe = itCf, ash = false },
			{ at = 6.5, action = "PlaySound", sound = "ObserverSting", volume = 0.55 },
			{ at = 7.3, action = "Glitch", duration = 0.25, intensity = 1 },
			{ at = 7.45, action = "DestroyEffect", name = "it" },
			{ at = 7.8, action = "PlaySound", sound = "Thud", position = away, volume = 0.9 },
			-- nothing. the tape keeps rolling.
			{ at = 9.9, action = "Glitch", duration = 0.15, intensity = 0.4, sound = false },
			{ at = 11.4, action = "CutToBlack" },
			{ at = 11.4, action = "StopSound" },
		}
	end,
}
