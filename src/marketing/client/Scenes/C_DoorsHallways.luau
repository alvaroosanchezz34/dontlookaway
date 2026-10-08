--[[
	C · DOORS & HALLWAYS — the key-art doorway set for single doors, the real
	Ashgrove corridors (or the virtual set) for hallways. Map doors are moved
	locally and put back by the cleanup.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

return {
	Category = "C · DOORS & HALLWAYS",
	Scenes = {
		{
			Name = "Scene_DoorOpensByItself",
			Description = "Silence. Three knocks from the other side. The handle rattles, the door opens a crack, breathing. Slam.",
			Duration = 10,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				local o = set.origin
				local doorAt = (o * CFrame.new(0, 5, -0.6)).Position
				return Shots.join(Shots.doorway(set, { lamp = 0.85 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(10.5, 5.9), preset = "DOOR_SHOT", fov = 44 },
					{ at = 0, action = "Silence", level = 0.25, fade = 0 },
				}, Shots.knocks(2.0, doorAt, 3, 0.5, { volume = 0.45 }), {
					{ at = 2.0, action = "Unsilence", fade = 0.1 },
					{ at = 3.8, action = "PlaySound", sound = "DoorLocked", position = doorAt, volume = 0.7 },
					{ at = 3.8, action = "OpenDoor", amount = 0.015, duration = 0.12 },
					{ at = 3.95, action = "CloseDoor", amount = 0, duration = 0.12 },
					{ at = 4.7, action = "OpenDoor", amount = 0.1, duration = 1.4, ease = "inOutSine" },
					{ at = 4.7, action = "PlaySound", sound = "DoorOpen", position = doorAt, volume = 0.6, speed = 0.65 },
					{ at = 6.4, action = "PlaySound", sound = "BreathHeavy", position = doorAt, volume = 0.75 },
					{ at = 8.4, action = "CloseDoor", amount = 0, duration = 0.14, ease = "inQuad" },
					{ at = 8.5, action = "PlaySound", sound = "DoorSlam", position = doorAt, volume = 1 },
					{ at = 8.5, action = "Jolt", amount = 0.5 },
				}, Shots.cut(8.75))
			end,
		},
		{
			Name = "Scene_SomethingAtTheEnd",
			Description = "A long corridor; a silhouette at the end; each flicker it is closer, then gone; movement right by the lens.",
			Duration = 12,
			Build = function(L)
				local from, _, length = L.corridor("G")
				local stop = from * CFrame.new(0, 0, -math.min(length * 0.35, 16))
				local function point(a: number): Vector3
					return L.corridorPoint("G", a)
				end
				local close = (stop * CFrame.new(-2.2, -5.4, -4.5)).Position
				return Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HALLWAY" },
					{ at = 0, action = "MoveCamera", to = stop, duration = 11, ease = "linear" },
					{ at = 2.4, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(point(0.94), from.Position), ash = false },
					{ at = 2.4, action = "FadeObject", name = "it", from = 1, to = 0.5, duration = 1 },
					{ at = 5.0, action = "FlickerLights", position = point(0.5) + Vector3.new(0, 12, 0), radius = 40, duration = 0.7, depth = 2.4 },
					{ at = 5.4, action = "PlaceObject", name = "it", to = facing(point(0.72), from.Position) },
					{ at = 7.4, action = "FlickerLights", position = point(0.5) + Vector3.new(0, 12, 0), radius = 40, duration = 0.7, depth = 2.6 },
					{ at = 7.8, action = "DestroyEffect", name = "it" },
					-- right by the lens
					{ at = 10.2, action = "SpawnEffect", kind = "person", name = "pass", cframe = facing(close, close + stop.RightVector), coat = Color3.fromRGB(10, 10, 12), skin = Color3.fromRGB(14, 14, 16) },
					{ at = 10.25, action = "MoveObject", name = "pass", to = facing(close + stop.RightVector * 5, close + stop.RightVector * 10), duration = 0.4 },
					{ at = 10.25, action = "PlaySound", sound = "FootstepsBehind", volume = 0.9 },
				}, Shots.cut(10.6))
			end,
		},
		{
			Name = "Scene_TheDoorWasOpen",
			Description = "A closed door. The camera looks away. When it looks back the door is open, silently; a shadow inside.",
			Duration = 12,
			Build = function(L)
				local door, doorFloor, cam = L.doorShot({ "G_b", "G_a", "G_m", "U_o", "U_j" }, 8)
				local away = Shots.turn(cam, 75)
				local inside = (doorFloor * CFrame.new(-2.5, 0, -4)).Position
				return Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "UseDoor", model = door, floorCf = doorFloor, amount = 0 },
					{ at = 0, action = "SetCamera", cframe = cam, preset = "HANDHELD" },
					{ at = 3.2, action = "MoveCamera", to = away, duration = 1.4, ease = "inOutSine" },
					{ at = 5.4, action = "OpenDoor", amount = 0.65, duration = 0 },
					{ at = 6.2, action = "MoveCamera", to = cam, duration = 1.3, ease = "inOutSine" },
					{ at = 8.0, action = "SpawnEffect", kind = "person", name = "shade", cframe = facing(inside, inside + doorFloor.RightVector), coat = Color3.fromRGB(8, 8, 9), skin = Color3.fromRGB(10, 10, 11) },
					{ at = 8.05, action = "MoveObject", name = "shade", to = facing(inside + doorFloor.RightVector * 5, inside + doorFloor.RightVector * 9), duration = 0.6 },
					{ at = 8.7, action = "DestroyEffect", name = "shade" },
					{ at = 9.2, action = "MoveCamera", to = cam * CFrame.new(0, 0, 2.2), duration = 2, ease = "inOutSine" },
				}, Shots.cut(11.3))
			end,
		},
		{
			Name = "Scene_TheHallwayChanges",
			Description = "Walking a corridor while the light slowly turns; look back and it is not the same corridor; a clock ticks wrong.",
			Duration = 15,
			Build = function(L)
				local from, _, length = L.corridor("G")
				local mid = from * CFrame.new(0, 0, -math.min(length * 0.3, 14))
				local back = Shots.turn(mid, 180)
				return Shots.join(Shots.open({ grade = "cold" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HALLWAY" },
					{ at = 0, action = "PlayAmbience", sound = "ClockTick", name = "clock", volume = 0.5 },
					{ at = 0, action = "MoveCamera", to = mid, duration = 7, ease = "inOutSine" },
					{ at = 2.0, action = "Grade", grade = "dread", duration = 5 },
					{ at = 3.0, action = "Fog", density = 0.35, duration = 5, color = Color3.fromRGB(70, 60, 60) },
					{ at = 7.4, action = "MoveCamera", to = back, duration = 1.8, ease = "inOutSine" },
					{ at = 8.4, action = "Grade", grade = "red", duration = 0.4 },
					{ at = 8.4, action = "SetLighting", exposure = -0.6, duration = 0.4 },
					{ at = 8.4, action = "StopSound", name = "clock" },
					{ at = 8.6, action = "PlayAmbience", sound = "ClockTick", name = "clock2", volume = 0.6, speed = 0.55 },
					{ at = 10.0, action = "FlickerLights", position = (back * CFrame.new(0, 6, -14)).Position, radius = 30, duration = 0.8, depth = 1.6 },
				}, Shots.cut(13.8))
			end,
		},
		{
			Name = "Scene_TheDoorBehindYou",
			Description = "A door slams behind you. Nothing there. Turn back: a door that was not there, ajar, whispering.",
			Duration = 12,
			Build = function(L)
				local from, _, length = L.corridor("G")
				local walk = from * CFrame.new(0, 0, -math.min(length * 0.2, 9))
				local back = Shots.turn(walk, 180)
				-- the new door, on the side wall a little ahead
				local wall = L.corridorWall("G", 0.42, 1)
				return Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HANDHELD" },
					{ at = 0, action = "MoveCamera", to = walk, duration = 3, ease = "inOutSine" },
					{ at = 3.1, action = "PlaySound", sound = "DoorSlam", position = Shots.behind(walk, 12), volume = 0.9 },
					{ at = 3.6, action = "MoveCamera", to = back, duration = 1.0, ease = "inOutSine" },
					{ at = 5.0, action = "UseDoor", floorCf = wall, amount = 0.15 },
					{ at = 5.6, action = "MoveCamera", to = CFrame.lookAt(walk.Position, (wall * CFrame.new(0, 5, 0)).Position), duration = 1.3, ease = "inOutSine" },
					{ at = 7.4, action = "PlaySound", sound = "Whisper", position = (wall * CFrame.new(0, 5, -1)).Position, volume = 0.45 },
					{ at = 8.6, action = "MoveCamera", to = CFrame.lookAt(walk.Position, (wall * CFrame.new(0, 5, 0)).Position) * CFrame.new(0, 0, -1.2), duration = 2.4, ease = "creep" },
				}, Shots.cut(11.2))
			end,
		},
		{
			Name = "Scene_TheEndlessHallway",
			Description = "The same stretch of corridor, again and again, darker each time; at the end, a figure takes one step.",
			Duration = 15,
			Build = function(L)
				local from, _, length = L.corridor("G")
				local stretch = from * CFrame.new(0, 0, -math.min(length * 0.25, 12))
				local farFeet = facing(L.corridorPoint("G", 0.88), from.Position)
				local list = Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HALLWAY" },
				})
				for i, t in { 0, 3.1, 6.2, 9.3 } do
					if i > 1 then
						table.insert(list, { at = t, action = "Cut", cframe = from, preset = "HALLWAY" })
						table.insert(list, { at = t, action = "SetLighting", exposure = -0.35 * (i - 1), duration = 0.1 })
						table.insert(list, { at = t, action = "FlickerLights", position = L.corridorPoint("G", 0.3, 12), radius = 30, duration = 0.3, depth = 1, sound = false })
					end
					if i < 4 then
						table.insert(list, { at = t + 0.05, action = "MoveCamera", to = stretch, duration = 3, ease = "linear" })
					end
				end
				return Shots.join(list, {
					-- the last time: it stays still... and there is someone at the end
					{ at = 9.3, action = "SpawnEffect", kind = "entity", name = "it", cframe = farFeet, ash = false },
					{ at = 9.4, action = "MoveCamera", to = from * CFrame.new(0, 0, -2), duration = 2.4, ease = "outCubic" },
					{ at = 12.4, action = "MoveObject", name = "it", to = farFeet * CFrame.new(0, 0, -1.4), duration = 0.5, ease = "inOutSine" },
					{ at = 12.4, action = "PlaySound", sound = "StepConcrete", position = farFeet.Position, volume = 0.9, speed = 0.7 },
				}, Shots.cut(13.6))
			end,
		},
	},
}
