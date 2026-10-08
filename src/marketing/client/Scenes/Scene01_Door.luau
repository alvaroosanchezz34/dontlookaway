--[[
	Scene01_Door  (≈9.5 s)
	A fixed camera watches a door. Nothing happens for a long time. The door
	moves, barely. A sound behind it. It opens a few centimetres. Cut.
]]

return {
	Name = "Scene01_Door",
	Description = "A door that is not quite shut",
	Duration = 9.6,
	Build = function(L)
		local door, doorFloor, cam = L.doorShot({ "G_b", "G_a", "G_m", "U_o", "U_n", "U_j" }, 9)
		local at = doorFloor.Position + Vector3.new(0, 5, 0)
		return {
			{ at = 0, action = "UseDoor", model = door, floorCf = doorFloor, amount = 0 },
			{ at = 0, action = "SetCamera", cframe = cam, preset = "DOOR_SHOT" },
			{ at = 0, action = "Grade", grade = "cold" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1.4 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.8 },
			{ at = 0.2, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.5 },
			-- the long nothing
			{ at = 2.7, action = "OpenDoor", amount = 0.025, duration = 0.45, ease = "outQuad" },
			{ at = 2.7, action = "PlaySound", sound = "WoodCreak", position = at, volume = 0.6 },
			{ at = 3.2, action = "CloseDoor", amount = 0.01, duration = 0.5 },
			{ at = 4.3, action = "Silence", level = 0.15, fade = 1.4 },
			-- something on the other side
			{ at = 5.7, action = "Unsilence", fade = 0.05 },
			{ at = 5.7, action = "PlaySound", sound = "KnockDoor", position = at, volume = 0.35, speed = 0.85 },
			{ at = 6.7, action = "PlaySound", sound = "DoorOpen", position = at, volume = 0.75, speed = 0.7 },
			{ at = 6.7, action = "OpenDoor", amount = 0.13, duration = 2.2, ease = "creep" },
			{ at = 6.7, action = "MoveCamera", to = cam * CFrame.new(0, 0, -0.7), duration = 2.4, ease = "inQuad" },
			{ at = 8.9, action = "CutToBlack" },
			{ at = 8.9, action = "Silence", level = 0, fade = 0.05 },
		}
	end,
}
