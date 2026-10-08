--[[
	E · GLITCH & MESSAGES — black cards, words on walls, footage that should
	not exist. Text uses Titles (cinematic) and Titles.surface (on a wall).
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

return {
	Category = "E · MESSAGES",
	Scenes = {
		{
			Name = "Scene_DontLookAway",
			Description = "Black. Breathing. DON'T... LOOK... the eye opens behind the words... AWAY. Cut.",
			Duration = 9,
			Light = false,
			Build = function()
				return Shots.join(Shots.black({ volume = 0.45 }), {
					{ at = 0.4, action = "PlaySound", sound = "Breath", volume = 0.8 },
					{ at = 1.8, action = "ShowText", id = "w1", text = "DON'T", style = "title", position = UDim2.fromScale(0.5, 0.36), size = 0.06, fadeIn = 0.1 },
					{ at = 1.8, action = "PlaySound", sound = "TitleHit", volume = 0.6 },
					{ at = 3.1, action = "Glitch", duration = 0.18, intensity = 0.6 },
					{ at = 3.6, action = "ShowText", id = "w2", text = "LOOK", style = "title", position = UDim2.fromScale(0.5, 0.5), size = 0.06, fadeIn = 0.1 },
					{ at = 3.6, action = "PlaySound", sound = "TitleHit", volume = 0.7, speed = 0.9 },
					{ at = 4.6, action = "ShowEye", mode = "screen", scale = 0.85, open = 0.1, fade = 1.0, look = "camera", recreate = true },
					{ at = 4.8, action = "SetEye", open = 1, duration = 1.4, ease = "inOutCubic" },
					{ at = 6.8, action = "ShowText", id = "w3", text = "AWAY", style = "warning", position = UDim2.fromScale(0.5, 0.64), size = 0.065, fadeIn = 0.05 },
					{ at = 6.8, action = "PlaySound", sound = "ObserverSting", volume = 0.5, duration = 0.5, fadeOut = 0.1 },
				}, Shots.cut(7.6))
			end,
		},
		{
			Name = "Scene_TheMessageChanges",
			Description = "YOU ARE ALONE written on the wall. Closer. Interference: NO, YOU ARE NOT. A sound behind you.",
			Duration = 11,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local wallCf = CFrame.lookAt(set.at(-6, 6.8, -11.93), set.at(-6, 6.8, 0))
				local cam = CFrame.lookAt(set.at(-6, 6, 2), set.at(-6, 6.6, -12))
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD", lamp = 0.75 }), {
					{ at = 0, action = "SurfaceText", id = "msg", cframe = wallCf, size = Vector2.new(7, 3.2), color = Color3.fromRGB(120, 16, 14) },
					{ at = 0.1, action = "WriteText", id = "msg", text = "YOU ARE ALONE" },
					{ at = 1.2, action = "MoveCamera", to = cam * CFrame.new(0, 0.2, -6), duration = 6, ease = "creep" },
					{ at = 6.2, action = "Glitch", duration = 0.25, intensity = 0.8 },
					{ at = 6.3, action = "WriteText", id = "msg", text = "NO, YOU ARE NOT" },
					{ at = 8.4, action = "PlaySound", sound = "FootstepsBehind", position = Shots.behind(cam * CFrame.new(0, 0, -6), 3), volume = 0.9 },
				}, Shots.cut(9.6))
			end,
		},
		{
			Name = "Scene_ThisVideoIsWrong",
			Description = "Ordinary footage with a timestamp; two frames of the eye; THIS RECORDING SHOULD NOT EXIST; a figure at the lens.",
			Duration = 10,
			Build = function(L)
				local from = L.corridor("G")
				local close = (from * CFrame.new(0, -5.4, -3.2)).Position
				return Shots.join(Shots.open({ grade = "cctv", fade = 0.2 }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HANDHELD" },
					{ at = 0, action = "CCTV", on = true, label = "VID_0047.MOV" },
					{ at = 0, action = "MoveCamera", to = from * CFrame.new(0, 0, -6), duration = 8, ease = "linear" },
					{ at = 2.2, action = "ShowEye", mode = "screen", scale = 0.95, fade = 0, look = "camera", recreate = true },
					{ at = 2.27, action = "HideEye", fade = 0 },
					{ at = 2.27, action = "Glitch", duration = 0.1, intensity = 0.4, sound = false },
					{ at = 4.1, action = "ShowEye", mode = "screen", scale = 1.1, fade = 0, look = "camera", recreate = true },
					{ at = 4.16, action = "HideEye", fade = 0 },
					{ at = 6.0, action = "ShowText", id = "t", text = "THIS RECORDING SHOULD NOT EXIST", style = "cctv", size = 0.026, fadeIn = 0.2, duration = 2.4 },
					{ at = 8.7, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(close, from.Position), ash = false },
				}, Shots.cut(9.0))
			end,
		},
		{
			Name = "Scene_TheCameraNoticesYou",
			Description = "CCTV starts tracking a figure; it vanishes; the security camera turns, slowly, to you. IT KNOWS YOU'RE HERE.",
			Duration = 14,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local camCorner = CFrame.lookAt(set.at(10.5, 11, 10.5), set.at(-2, 2, -4))
				local mount = CFrame.lookAt(set.at(11.6, 11, -11.4), set.at(-2, 2, 4))
				local device = Sets.cctvCamera(mount)
				local viewer = set.at(2, 5.4, 4)
				local watch = CFrame.lookAt(viewer, mount.Position)
				local walkA, walkB = set.at(-8, 0, -6), set.at(6, 0, -2)
				return Shots.join(Shots.room(set, { lamp = 0.6 }), Shots.cctv(camCorner, "CAM_09  ·  IDLE"), {
					{ at = 0, action = "AdoptObject", name = "device", model = device },
					{ at = 0, action = "SpawnEffect", kind = "person", name = "p", cframe = facing(walkA, walkB) },
					{ at = 1.0, action = "MoveObject", name = "p", to = facing(walkB, walkB + (walkB - walkA)), duration = 4.6 },
					{ at = 1.8, action = "CCTV", on = true, label = "CAM_09  ·  ● TRACKING" },
					{ at = 1.8, action = "PlaySound", sound = "KeypadBeep", volume = 0.6 },
					{ at = 1.8, action = "TrackTarget", target = "figure:p", smooth = 3 },
					{ at = 5.4, action = "Glitch", duration = 0.2, intensity = 0.7 },
					{ at = 5.5, action = "DestroyEffect", name = "p" },
					{ at = 5.5, action = "StopTracking" },
					-- now we are looking at the camera itself, and it turns to us
					{ at = 6.6, action = "CCTV", on = false },
					{ at = 6.6, action = "Grade", grade = "dread" },
					{ at = 6.6, action = "Cut", cframe = watch, preset = "CLOSE_UP", fov = 38 },
					{ at = 7.2, action = "MoveObject", name = "device", to = CFrame.lookAt(mount.Position, viewer), duration = 3.2, ease = "inOutSine" },
					{ at = 7.2, action = "PlaySound", sound = "DeviceTick", position = mount.Position, volume = 0.8, speed = 0.7 },
					{ at = 10.8, action = "ShowText", id = "t", text = "IT KNOWS YOU'RE HERE", style = "cctv", position = "lower", size = 0.03, fadeIn = 0.3 },
				}, Shots.cut(13.2))
			end,
		},
		{
			Name = "Scene_YouMissedSomething",
			Description = "A normal room. Something changes for a fraction of a second. WATCH AGAIN. A second, different anomaly.",
			Duration = 9.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("center")
				local chair = set.chair:GetPivot()
				return Shots.join(Shots.room(set, { camera = cam, preset = "STATIC" }), {
					{ at = 0, action = "AdoptObject", name = "chair", model = set.chair },
					{ at = 2.0, action = "PlaceObject", name = "chair", to = chair * CFrame.Angles(0, math.rad(160), 0) },
					{ at = 2.12, action = "PlaceObject", name = "chair", to = chair },
					{ at = 3.6, action = "ShowText", id = "w", text = "WATCH AGAIN", style = "cctv", size = 0.03, fadeIn = 0.15, duration = 1.4 },
					{ at = 5.4, action = "FadeToBlack", duration = 0.15 },
					{ at = 5.6, action = "FadeFromBlack", duration = 0.15 },
					{ at = 7.2, action = "SpawnEffect", kind = "shine", name = "e", cframe = CFrame.new(set.at(9.3, 5.8, -9.3)), size = 0.09, gap = 0.3 },
					{ at = 7.32, action = "DestroyEffect", name = "e" },
				}, Shots.cut(8.8))
			end,
		},
		{
			Name = "Scene_TheFinalWarning",
			Description = "Black. YOU SHOULD NOT BE HERE. A blow behind you. The eye, briefly. DON'T LOOK AWAY.",
			Duration = 9.5,
			Light = false,
			Build = function(_L, Config)
				return Shots.join(Shots.black({ volume = 0.45 }), {
					{ at = 0.8, action = "ShowText", id = "w", text = "YOU SHOULD NOT BE HERE", style = "whisper", size = 0.03, fadeIn = 0.5, duration = 2.4 },
					{ at = 4.0, action = "PlaySound", sound = "Thud", volume = 1, speed = 0.8 },
					{ at = 4.0, action = "Jolt", amount = 0.6 },
					{ at = 4.5, action = "ShowEye", mode = "screen", scale = 0.8, fade = 0.05, look = "camera", recreate = true },
					{ at = 4.95, action = "HideEye", fade = 0 },
					{ at = 5.6, action = "ShowImage", id = "title", imageKey = "title", position = UDim2.fromScale(0.5, 0.5), width = 0.98, aspect = 1.6, fadeIn = 0.3, flicker = 0.1,
						fallbackText = Config.Text.Title, fallbackStyle = "warning", size = 0.055 },
					{ at = 5.6, action = "PlaySound", sound = "TitleHit", volume = 0.9 },
				}, Shots.cut(8.6))
			end,
		},
	},
}
