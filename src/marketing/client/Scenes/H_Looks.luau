--[[
	H · LOOKS — the lighting + composition presets (Utilities/Looks) on real
	shots. A reference reel: every look is labelled so a shot can be matched
	to the preset that made it.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

local function label(at: number, text: string): { any }
	return {
		{ at = at, action = "ShowText", id = "look", text = text, style = "whisper", size = 0.022, position = UDim2.fromScale(0.5, 0.9), fadeIn = 0.2, duration = 2.1 },
	}
end

return {
	Category = "H · LOOKS",
	Scenes = {
		{
			Name = "Scene_LookBook",
			Description = "Reference reel of the eight looks: normal room, long corridor, figure at the back, door ajar, CCTV, anomaly reveal, eye close-up, cut to black.",
			Duration = 20,
			Light = 1,
			Build = function(L)
				local set = Sets.room()
				local corridorCam = L.corridor("G")
				local corridorMid = L.corridorPoint("G", 0.55)
				local center = set.shot("center")
				local corner = set.shot("corner")
				local doorShot = set.shot("door")
				local figureAt = set.at(3, 0, -10)
				local doorPos = set.door:GetPivot().Position
				local eyeAt = set.at(0.3, 7.2, -12.7)
				local high = CFrame.lookAt(set.at(-11, 11, 10), set.at(2, 2, -6))
				return Shots.join(
					Shots.room(set, { camera = center, fade = 0.4 }),
					-- 1 normal room
					{ { at = 0, action = "LookPreset", preset = "NormalRoom", subject = set.at(0, 4, -6), duration = 0 } },
					label(0.3, "NORMAL ROOM"),
					-- 2 long corridor (the real building)
					{
						{ at = 2.6, action = "SetCamera", cframe = corridorCam, preset = "STATIC" },
						{ at = 2.6, action = "LookPreset", preset = "LongCorridor", subject = corridorMid, duration = 0.2 },
						{ at = 2.6, action = "MoveCamera", to = corridorCam * CFrame.new(0, 0, -3), duration = 2.4, ease = "linear" },
					},
					label(2.8, "LONG CORRIDOR"),
					-- 3 figure at the back (backlit)
					{
						{ at = 5.2, action = "SetCamera", cframe = CFrame.lookAt(corner.Position, figureAt + Vector3.new(0, 4, 0)), preset = "HANDHELD" },
						{ at = 5.2, action = "SpawnEffect", kind = "person", name = "figure", cframe = facing(figureAt, corner.Position), coat = Color3.fromRGB(14, 14, 16), skin = Color3.fromRGB(30, 30, 32) },
						{ at = 5.2, action = "LookPreset", preset = "FigureAtBack", subject = figureAt + Vector3.new(0, 3, 0), camera = corner, duration = 0.3 },
						{ at = 7.7, action = "DestroyEffect", name = "figure" },
					},
					label(5.4, "FIGURE AT THE BACK"),
					-- 4 door ajar
					{
						{ at = 7.8, action = "SetCamera", cframe = doorShot, preset = "DOOR_SHOT" },
						{ at = 7.8, action = "OpenDoor", model = set.door, amount = 0.18, duration = 0 },
						{ at = 7.8, action = "LookPreset", preset = "DoorAjar", subject = doorPos, camera = doorShot, duration = 0.3 },
					},
					label(8.0, "DOOR AJAR"),
					-- 5 CCTV
					{
						{ at = 10.4, action = "SetCamera", cframe = high, preset = "CCTV" },
						{ at = 10.4, action = "CCTV", on = true, label = "CAM_02  ·  ROOM" },
						{ at = 10.4, action = "LookPreset", preset = "CCTV", duration = 0 },
						{ at = 12.9, action = "CCTV", on = false },
					},
					label(10.6, "CCTV"),
					-- 6 anomaly reveal: hard top light on the far wall, the eye opens in it
					{
						{ at = 13.0, action = "SetCamera", cframe = set.shot("window"), preset = "CINEMATIC" },
						{ at = 13.0, action = "LookPreset", preset = "AnomalyReveal", subject = eyeAt, camera = set.shot("window"), duration = 0.4 },
						{ at = 13.4, action = "ShowEye", mode = "anchored", position = eyeAt, scale = 1.5, brightness = 0.8, fade = 0.4, look = "camera", recreate = true },
					},
					label(13.2, "ANOMALY REVEAL"),
					-- 7 eye close-up
					{
						{ at = 15.8, action = "SetCamera", cframe = CFrame.lookAt(eyeAt + Vector3.new(0, 0, 6), eyeAt), preset = "CINEMATIC" },
						{ at = 15.8, action = "MoveCamera", to = CFrame.lookAt(eyeAt + Vector3.new(0, 0, 4.5), eyeAt), duration = 2.4, ease = "outCubic" },
						{ at = 15.8, action = "LookPreset", preset = "EyeCloseUp", subject = eyeAt, camera = CFrame.lookAt(eyeAt + Vector3.new(0, 0, 6), eyeAt), duration = 0.3 },
						{ at = 17.4, action = "BlinkEye", duration = 0.3 },
					},
					label(16.0, "EYE CLOSE-UP"),
					-- 8 cut to black
					{
						{ at = 18.2, action = "HideEye", fade = 0 },
						{ at = 18.2, action = "LookPreset", preset = "CutToBlack", duration = 0.05 },
					},
					label(18.3, "CUT TO BLACK"),
					Shots.cut(19.5)
				)
			end,
		},
		{
			Name = "Scene_DoorAjarToEye",
			Description = "A door ajar with warm light leaking through; the look tightens to the eye close-up inside the gap; cut.",
			Duration = 8,
			Light = false,
			Isolated = true,
			Build = function()
				local set = Sets.doorway()
				local cam = set.camera(12, 5.9)
				local close = set.camera(7.5, 6)
				return Shots.join(Shots.doorway(set, { door = 0.15, fade = 0.4 }), {
					{ at = 0, action = "SetCamera", cframe = cam, preset = "CINEMATIC", fov = 44 },
					{ at = 0, action = "LookPreset", preset = "DoorAjar", subject = set.eyeAt, camera = cam, duration = 0 },
					{ at = 1.8, action = "OpenDoor", amount = 0.45, duration = 1.6, ease = "inOutSine" },
					{ at = 2.6, action = "ShowEye", mode = "anchored", position = set.eyeAt, scale = 3.6, brightness = 0.85, open = 0.3, fade = 0.6, look = "camera", recreate = true },
					{ at = 3.4, action = "MoveCamera", to = close, duration = 3, ease = "inOutSine" },
					{ at = 3.4, action = "LookPreset", preset = "EyeCloseUp", subject = set.eyeAt, camera = close, duration = 1.4 },
					{ at = 3.8, action = "SetEye", open = 1, pupil = 0.25, duration = 1, ease = "inOutCubic" },
					{ at = 6.3, action = "BlinkEye", duration = 0.3 },
				}, Shots.cut(7.2))
			end,
		},
	},
}
