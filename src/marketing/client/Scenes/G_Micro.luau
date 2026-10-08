--[[
	G · MICRO — 4 to 6 second vertical hooks. No intro: the anomaly is in the
	first seconds, easy to catch on a rewatch, abrupt ending.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

return {
	Category = "G · MICRO",
	Scenes = {
		{
			Name = "Scene_MicroEyeReveal",
			Description = "A dark doorway; the eye opens in it, looks at you, blinks. Cut.",
			Duration = 5,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				return Shots.join(Shots.doorway(set, { door = 1, fade = 0.25 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(13, 5.9), preset = "CINEMATIC", fov = 46 },
					{ at = 0, action = "MoveCamera", to = set.camera(11, 6), duration = 4.5, ease = "linear" },
					{ at = 0.3, action = "ShowEye", mode = "anchored", position = set.eyeAt, scale = 4, brightness = 0.85, open = 0.2, fade = 0.8, look = "camera", recreate = true },
					{ at = 0.6, action = "SetEye", open = 1, pupil = 0.3, duration = 1.1, ease = "inOutCubic" },
					{ at = 3.3, action = "BlinkEye", duration = 0.3 },
				}, Shots.cut(4.2))
			end,
		},
		{
			Name = "Scene_MicroDoorMovement",
			Description = "A door ajar opens a little more by itself, then slams.",
			Duration = 4.6,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				local doorAt = (set.origin * CFrame.new(0, 5, -0.6)).Position
				return Shots.join(Shots.doorway(set, { door = 0.12, fade = 0.2 }), {
					{ at = 0, action = "SetCamera", cframe = set.camera(10, 5.9), preset = "DOOR_SHOT", fov = 44 },
					{ at = 1.0, action = "OpenDoor", amount = 0.4, duration = 1.6, ease = "inOutSine" },
					{ at = 1.0, action = "PlaySound", sound = "DoorOpen", position = doorAt, volume = 0.6, speed = 0.6 },
					{ at = 3.1, action = "CloseDoor", amount = 0, duration = 0.12, ease = "inQuad" },
					{ at = 3.2, action = "PlaySound", sound = "DoorSlam", position = doorAt, volume = 1 },
					{ at = 3.2, action = "Jolt", amount = 0.5 },
				}, Shots.cut(3.45))
			end,
		},
		{
			Name = "Scene_MicroCAM04",
			Description = "CCTV: someone in the corridor; static; IT is there instead; static; nobody.",
			Duration = 6,
			Build = function(L)
				local cam, walkFrom, walkTo = L.cctvShot("G")
				local mid = walkFrom:Lerp(walkTo, 0.5)
				return Shots.join(Shots.cctv(cam, "CAM_04  ·  CORRIDOR G"), {
					{ at = 0, action = "SpawnEffect", kind = "actor", name = "staff", cframe = facing(mid, cam.Position) },
					{ at = 2.0, action = "Glitch", duration = 0.2, intensity = 0.8 },
					{ at = 2.05, action = "DestroyEffect", name = "staff" },
					{ at = 2.05, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(mid, cam.Position), ash = false },
					{ at = 3.1, action = "Glitch", duration = 0.2, intensity = 0.9 },
					{ at = 3.15, action = "DestroyEffect", name = "it" },
					{ at = 4.6, action = "Static", alpha = 1, duration = 0.1 },
				}, Shots.cut(5.4))
			end,
		},
		{
			Name = "Scene_MicroShadow",
			Description = "A shadow crosses the back wall; it comes back closer.",
			Duration = 5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local backWall = CFrame.lookAt(set.at(6, 0, -11.95), set.at(6, 0, 0))
				return Shots.join(Shots.room(set, { camera = set.shot("center"), preset = "STATIC", fade = 0.2 }), {
					{ at = 0.6, action = "SpawnEffect", kind = "shadow", name = "s", cframe = backWall, height = 7 },
					{ at = 0.6, action = "MoveObject", name = "s", to = backWall * CFrame.new(12, 0, 0), duration = 1.2, ease = "linear" },
					{ at = 1.85, action = "DestroyEffect", name = "s" },
					{ at = 2.9, action = "SpawnEffect", kind = "shadow", name = "s2", cframe = CFrame.lookAt(set.at(-1, 0, -11.95), set.at(-1, 0, 0)), height = 10.5, transparency = 0.3 },
					{ at = 2.9, action = "PlaySound", sound = "ObserverInhale", volume = 0.45 },
				}, Shots.cut(4.2))
			end,
		},
		{
			Name = "Scene_MicroFigureBehindCamera",
			Description = "A sound behind; whip round; nothing; back: it is standing in the room.",
			Duration = 5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("center")
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD", fade = 0.2 }), {
					{ at = 0.8, action = "PlaySound", sound = "FootstepsBehind", position = Shots.behind(cam, 2), volume = 1 },
					{ at = 1.1, action = "MoveCamera", to = Shots.turn(cam, 180), duration = 0.35, ease = "outCubic" },
					{ at = 1.9, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(set.at(1, 0, -5), cam.Position), ash = false },
					{ at = 2.2, action = "MoveCamera", to = cam, duration = 0.45, ease = "inOutSine" },
				}, Shots.cut(3.8))
			end,
		},
		{
			Name = "Scene_MicroOneFrameAnomaly",
			Description = "A calm room; two frames of the eye; nothing.",
			Duration = 4.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				return Shots.join(Shots.room(set, { camera = set.shot("window"), preset = "HANDHELD", fade = 0.2 }), {
					{ at = 1.6, action = "ShowEye", mode = "anchored", position = set.at(0.3, 7.2, -12.7), scale = 1.6, brightness = 0.7, fade = 0, look = "camera", recreate = true },
					{ at = 1.67, action = "HideEye", fade = 0 },
					{ at = 1.67, action = "Glitch", duration = 0.06, intensity = 0.3, sound = false },
				}, Shots.cut(4.1))
			end,
		},
		{
			Name = "Scene_MicroFinalWarning",
			Description = "YOU SHOULD NOT BE HERE. A blow. The eye. DON'T LOOK AWAY.",
			Duration = 5,
			Light = false,
			Build = function(_L, Config)
				return Shots.join(Shots.black({ volume = 0.4 }), {
					{ at = 0.2, action = "ShowText", id = "w", text = "YOU SHOULD NOT BE HERE", style = "whisper", size = 0.03, fadeIn = 0.3, duration = 1.5 },
					{ at = 2.0, action = "PlaySound", sound = "Thud", volume = 1 },
					{ at = 2.0, action = "Jolt", amount = 0.5 },
					{ at = 2.2, action = "ShowEye", mode = "screen", scale = 0.8, fade = 0, look = "camera", recreate = true },
					{ at = 2.6, action = "HideEye", fade = 0 },
					{ at = 2.9, action = "ShowImage", id = "title", imageKey = "title", position = UDim2.fromScale(0.5, 0.5), width = 0.98, aspect = 1.6, fadeIn = 0.15,
						fallbackText = Config.Text.Title, fallbackStyle = "warning", size = 0.055 },
					{ at = 2.9, action = "PlaySound", sound = "TitleHit", volume = 0.9 },
				}, Shots.cut(4.6))
			end,
		},
		{
			Name = "Scene_MicroDidYouSeeIt",
			Description = "Walking a corridor; for a few frames, something at the end. DID YOU SEE IT?",
			Duration = 5,
			Build = function(L)
				local from = L.corridor("G")
				return Shots.join(Shots.open({ grade = "dread", fade = 0.2 }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HANDHELD" },
					{ at = 0, action = "MoveCamera", to = from * CFrame.new(0, 0, -6), duration = 4.5, ease = "linear" },
					{ at = 1.7, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(L.corridorPoint("G", 0.7), from.Position), ash = false },
					{ at = 1.85, action = "DestroyEffect", name = "it" },
					{ at = 2.9, action = "ShowText", id = "q", text = "DID YOU SEE IT?", style = "whisper", size = 0.034, fadeIn = 0.2 },
				}, Shots.cut(4.6))
			end,
		},
		{
			Name = "Scene_MicroTheWrongReflection",
			Description = "An eye in the mirror; look at where it should be: nothing; back to the mirror: closer.",
			Duration = 5.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local shot = set.shot("mirror")
				local inMirror = (set.mirrorCf * CFrame.new(0.3, 0.35, -0.1)).Position
				return Shots.join(Shots.room(set, { camera = shot, preset = "HANDHELD", fade = 0.2 }), {
					{ at = 0.4, action = "ShowEye", mode = "anchored", position = inMirror, scale = 0.9, brightness = 0.7, fade = 0.5, look = "camera", recreate = true },
					{ at = 2.2, action = "HideEye", fade = 0, destroy = false },
					{ at = 2.2, action = "MoveCamera", to = CFrame.lookAt(shot.Position, set.at(9, 6.5, 2.5)), duration = 0.6, ease = "outCubic" },
					{ at = 3.4, action = "MoveCamera", to = shot, duration = 0.5, ease = "inOutSine" },
					{ at = 3.9, action = "SetEye", scale = 1.5, duration = 0 },
					{ at = 3.9, action = "ShowEye", mode = "anchored", fade = 0.05, look = "camera" },
				}, Shots.cut(5.0))
			end,
		},
		{
			Name = "Scene_MicroTheDoorWasOpen",
			Description = "A closed door; look away; back: it is open, no sound; something passes inside.",
			Duration = 5.5,
			Build = function(L)
				local door, doorFloor, cam = L.doorShot({ "G_b", "G_a", "G_m", "U_o" }, 8)
				local inside = (doorFloor * CFrame.new(-2.5, 0, -4)).Position
				return Shots.join(Shots.open({ grade = "dread", fade = 0.2 }), {
					{ at = 0, action = "UseDoor", model = door, floorCf = doorFloor, amount = 0 },
					{ at = 0, action = "SetCamera", cframe = cam, preset = "HANDHELD" },
					{ at = 0.8, action = "MoveCamera", to = Shots.turn(cam, 70), duration = 0.7, ease = "inOutSine" },
					{ at = 1.8, action = "OpenDoor", amount = 0.6, duration = 0 },
					{ at = 2.0, action = "MoveCamera", to = cam, duration = 0.7, ease = "inOutSine" },
					{ at = 3.4, action = "SpawnEffect", kind = "person", name = "shade", cframe = facing(inside, inside + doorFloor.RightVector), coat = Color3.fromRGB(8, 8, 9), skin = Color3.fromRGB(10, 10, 11) },
					{ at = 3.45, action = "MoveObject", name = "shade", to = facing(inside + doorFloor.RightVector * 5, inside + doorFloor.RightVector * 9), duration = 0.5 },
				}, Shots.cut(4.8))
			end,
		},
	},
}
