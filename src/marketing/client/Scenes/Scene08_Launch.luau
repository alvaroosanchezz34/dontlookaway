--[[
	Scene08_Launch  (≈18.5 s)
	The launch cut. A little more of the building, never the answers:
	a corridor, a door, a room that is watching, security footage with a
	shape in it, a rush down a hallway, then the title.
	No endings, no lore, the entity only as a silhouette for an instant.
]]

return {
	Name = "Scene08_Launch",
	Description = "Launch trailer cut: building, door, eye, CCTV, title",
	Duration = 18.5,
	Build = function(L, Config)
		local hallFrom, _, length = L.corridor("G")
		local door, doorFloor, doorCam = L.doorShot({ "G_b", "G_a", "G_m", "U_o" }, 8)
		local roomCam, roomFar = L.roomShot({ "U_o", "G_k", "U_j" })
		local cctv, walkFrom = L.cctvShot("U")
		local rushFrom, _, rushLength = L.corridor("U", true)
		local eyeAt = roomFar - (roomFar - roomCam.Position).Unit * 2 - roomCam.RightVector * 2.2 + Vector3.new(0, 0.5, 0)
		local shapeFeet = CFrame.lookAt(walkFrom, Vector3.new(cctv.Position.X, walkFrom.Y, cctv.Position.Z))
		local doorAt = doorFloor.Position + Vector3.new(0, 5, 0)
		return {
			-- A: the corridor
			{ at = 0, action = "SetCamera", cframe = hallFrom, preset = "HALLWAY" },
			{ at = 0, action = "Grade", grade = "dread" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 0.9 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.8 },
			{ at = 0.5, action = "PlayAmbience", sound = "MusicPad", name = "pad", volume = 0.9, fadeIn = 3 },
			{ at = 0, action = "MoveCamera", to = hallFrom * CFrame.new(0, 0, -math.min(length * 0.2, 8)), duration = 3.2, ease = "linear" },
			-- B: the door
			{ at = 3.2, action = "UseDoor", model = door, floorCf = doorFloor, amount = 0 },
			{ at = 3.2, action = "Cut", cframe = doorCam, preset = "DOOR_SHOT" },
			{ at = 3.2, action = "Grade", grade = "cold" },
			{ at = 3.6, action = "OpenDoor", amount = 0.16, duration = 2, ease = "creep" },
			{ at = 3.6, action = "PlaySound", sound = "DoorOpen", position = doorAt, volume = 0.7, speed = 0.7 },
			-- C: a room that is watching
			{ at = 5.8, action = "Cut", cframe = roomCam, preset = "HANDHELD" },
			{ at = 5.8, action = "Grade", grade = "dread" },
			{ at = 5.8, action = "MoveCamera", to = roomCam * CFrame.new(0, 0, -2.5), duration = 2.6, ease = "linear" },
			{ at = 6.4, action = "FlickerLights", position = roomFar + Vector3.new(0, 6, 0), radius = 20, duration = 1.2, depth = 1.8 },
			{ at = 7.4, action = "ShowEye", mode = "world", position = eyeAt, scale = 1.4, intensity = 0.5, look = "camera", recreate = true },
			{ at = 7.52, action = "HideEye", fade = 0 },
			-- D: security footage
			{ at = 8.4, action = "Cut", cframe = cctv, preset = "CCTV" },
			{ at = 8.4, action = "CCTV", on = true, label = "CAM_07  ·  CORRIDOR 1F" },
			{ at = 8.4, action = "Grade", grade = "cctv" },
			{ at = 9.5, action = "SpawnEffect", kind = "entity", name = "shape", cframe = shapeFeet, ash = false },
			{ at = 10.3, action = "Glitch", duration = 0.3, intensity = 0.9 },
			{ at = 10.4, action = "DestroyEffect", name = "shape" },
			{ at = 10.8, action = "CCTV", on = false },
			-- E: run
			{ at = 10.8, action = "Cut", cframe = rushFrom, preset = "FIRST_PERSON" },
			{ at = 10.8, action = "Grade", grade = "red" },
			{ at = 10.8, action = "MoveCamera", to = rushFrom * CFrame.new(0, 0, -math.min(rushLength * 0.5, 22)), duration = 1.8, ease = "linear" },
			{ at = 10.8, action = "ShakeCamera", amount = 0.35, decay = 0.2 },
			{ at = 10.8, action = "PlaySound", sound = "HeartbeatFast", volume = 0.9 },
			{ at = 11.4, action = "PlaySound", sound = "BreathHeavy", volume = 0.8 },
			-- F: impact
			{ at = 12.6, action = "Glitch", duration = 0.2, intensity = 1 },
			{ at = 12.7, action = "CutToBlack", sound = "ObserverSting", volume = 0.7 },
			{ at = 12.7, action = "StopSound", name = "pad", fadeOut = 0.3 },
			{ at = 12.7, action = "StopSound", name = "ambience" },
			-- G: title
			{ at = 13.1, action = "Backdrop", on = true },
			{ at = 13.1, action = "FadeFromBlack", from = 1, duration = 0 },
			{ at = 13.4, action = "ShowText", id = "title", text = Config.Text.Title, style = "title", size = 0.055, fadeIn = 0.9, tracking = { from = 2, to = 12 }, duration = 4.6 },
			{ at = 13.4, action = "PlaySound", sound = "TitleHit", volume = 0.9 },
			{ at = 15.6, action = "ShowText", id = "now", text = Config.Text.Launch, style = "cctv", position = "lower", size = 0.026, fadeIn = 0.6, duration = 2.4 },
		}
	end,
}
