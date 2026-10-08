--[[
	Scene05_TheMessage  (≈8.8 s)
	The door from the key art, shut, under its hanging lamp. Something on the
	other side starts scratching words into it, stroke by stroke:
	DON'T ... LOOK ... AW—  and the lamp dies before the last word. In the dark,
	the scratching goes on. Cut.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)

return {
	Name = "Scene05_TheMessage",
	Description = "Words scratched into the door, the lamp dies before AWAY",
	Duration = 8.8,
	Light = false,
	Isolated = true,
	Build = function(_L, _Config)
		local set = Sets.doorway()
		local o = set.origin
		local lampPos = set.lamp.bulb.CFrame.Position
		-- the writing sits on the camera side of the door leaf
		local writeAt = (o * CFrame.new(0, 5.0, -0.34)).Position
		local writeCf = CFrame.lookAt(writeAt, writeAt + o.LookVector * -1)
		local doorAt = (o * CFrame.new(0, 5, -0.5)).Position
		local cam = CFrame.lookAt((o * CFrame.new(0.15, 5.3, 8.2)).Position, (o * CFrame.new(0, 5.6, 0)).Position)
		local close = CFrame.lookAt((o * CFrame.new(0.1, 5.2, 6.3)).Position, (o * CFrame.new(0, 5.2, 0)).Position)
		return {
			{ at = 0, action = "SetLighting", exposure = 0, ambient = Color3.fromRGB(8, 8, 9), brightness = 0 },
			{ at = 0, action = "Grade", grade = "keyart" },
			{ at = 0, action = "Vignette", on = true },
			{ at = 0, action = "FilmGrain", on = true },
			{ at = 0, action = "AdoptLight", name = "lamp", part = set.lamp.bulb, light = set.lamp.light },
			{ at = 0, action = "UseDoor", model = set.door, amount = 0 },
			{ at = 0, action = "SetCamera", cframe = cam, preset = "DOOR_SHOT", fov = 46 },
			{ at = 0, action = "FadeFromBlack", from = 1, duration = 1.2 },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.75 },
			{ at = 0, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.7, position = lampPos },
			{ at = 0, action = "ScratchSurface", id = "door", cframe = writeCf, size = Vector2.new(4.0, 5.8) },
			-- something on the other side
			{ at = 1.0, action = "PlaySound", sound = "KnockDoor", position = doorAt, volume = 0.45, speed = 0.8 },
			{ at = 1.6, action = "ScratchWrite", id = "door", text = "DON'T", line = 0, height = 0.19, top = 0.08, center = true, strokeTime = 0.15, position = doorAt },
			{ at = 3.2, action = "FlickerLights", key = "lamp", duration = 0.35, world = false, sound = "LightFlicker", position = lampPos },
			{ at = 3.6, action = "DimKey", name = "lamp", ratio = 0.7, duration = 0.2 },
			{ at = 3.6, action = "ScratchWrite", id = "door", text = "LOOK", line = 1, height = 0.19, top = 0.08, center = true, strokeTime = 0.14, position = doorAt },
			{ at = 4.6, action = "MoveCamera", to = close, duration = 3.4, ease = "creep" },
			{ at = 4.9, action = "FlickerLights", key = "lamp", duration = 0.5, world = false, sound = "LightFlicker", position = lampPos },
			{ at = 5.4, action = "DimKey", name = "lamp", ratio = 0.45, duration = 0.2 },
			{ at = 5.5, action = "ScratchWrite", id = "door", text = "AW", line = 2, height = 0.19, top = 0.08, x = 0.18, strokeTime = 0.13, position = doorAt, volume = 0.9 },
			-- the lamp dies before the last word; the scratching goes on in the dark
			{ at = 6.0, action = "FlickerLights", key = "lamp", duration = 0.25, world = false, sound = "BulbPop", position = lampPos },
			{ at = 6.25, action = "DimKey", name = "lamp", ratio = 0, duration = 0.05 },
			{ at = 6.25, action = "StopSound", name = "buzz" },
			{ at = 6.6, action = "PlaySound", sound = "PaperRustle", position = doorAt, volume = 0.9, speed = 0.5 },
			{ at = 7.0, action = "PlaySound", sound = "PaperRustle", position = doorAt, volume = 1, speed = 0.45 },
			{ at = 7.3, action = "PlaySound", sound = "Whisper", position = doorAt, volume = 0.3 },
			{ at = 7.9, action = "CutToBlack" },
			{ at = 7.9, action = "StopSound" },
		}
	end,
}
