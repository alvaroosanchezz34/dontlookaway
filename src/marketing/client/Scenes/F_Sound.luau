--[[
	F · SOUND — horror carried by sound: breathing, steps, whispers, silence,
	a noise that follows. All positional (3D) so the direction reads on
	headphones; the picture stays calm and visible.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

return {
	Category = "F · SOUND",
	Scenes = {
		{
			Name = "Scene_TheBreathingRoom",
			Description = "A dark but readable room; faint breathing grows, comes from behind the camera; silence; a whisper.",
			Duration = 14,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local start = CFrame.lookAt(set.at(-6, 5.6, 8), set.at(-2, 4, -12))
				local stop = CFrame.lookAt(set.at(4, 5.6, 7), set.at(6, 4, -12))
				local list = Shots.join(Shots.room(set, { camera = start, lamp = 0.4, exposure = 0 }), {
					{ at = 0.5, action = "MoveCamera", to = stop, duration = 8, ease = "inOutSine" },
				})
				-- breaths: far and faint, then louder, then from behind the camera
				for i = 0, 6 do
					local t = 1.0 + i * 1.25
					local from = set.at(-10 + i * 2.5, 4, -10 + i * 2)
					table.insert(list, { at = t, action = "PlaySound", sound = "Breath", position = from, volume = 0.25 + i * 0.1 })
				end
				return Shots.join(list, {
					{ at = 9.4, action = "PlaySound", sound = "BreathHeavy", position = Shots.behind(stop, 1.5), volume = 1 },
					{ at = 11.0, action = "Silence", level = 0, fade = 0.15 },
					{ at = 12.3, action = "Unsilence", fade = 0 },
					{ at = 12.3, action = "PlaySound", sound = "Whisper", position = Shots.behind(stop, 0.8), volume = 0.7 },
				}, Shots.cut(13.2))
			end,
		},
		{
			Name = "Scene_FootstepsApproaching",
			Description = "An empty corridor; steps far away, coming closer; nobody; they stop just out of frame. One more, very close.",
			Duration = 11,
			Build = function(L)
				local from = L.corridor("G")
				local farPoint = L.corridorPoint("G", 0.95, 1)
				local nearSide = (from * CFrame.new(2.6, -4.4, 1.2)).Position
				return Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "STATIC" },
				}, Shots.steps(farPoint, nearSide, 1.2, 12, 0.55, { grow = true, volume = 1 }), {
					{ at = 8.0, action = "Silence", level = 0.15, fade = 0.3 },
					{ at = 9.2, action = "Unsilence", fade = 0 },
					{ at = 9.2, action = "PlaySound", sound = "StepConcrete", position = Shots.behind(from, 0.8), volume = 1.3, speed = 0.75 },
				}, Shots.cut(9.45))
			end,
		},
		{
			Name = "Scene_TheSilence",
			Description = "Normal room sound; layer by layer it disappears; the camera slows; total silence; something moves at the back. Cut, no sting.",
			Duration = 9.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local start = set.shot("center")
				return Shots.join(Shots.room(set, { camera = start }), {
					{ at = 0, action = "PlayAmbience", sound = "ClockTick", name = "clock", volume = 0.6, position = set.at(-6, 7.5, -11.5) },
					{ at = 0, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.5, position = set.lamp.bulb.CFrame.Position },
					{ at = 0, action = "PlayAmbience", sound = "AmbientRain", name = "rain", volume = 0.6 },
					{ at = 0.2, action = "MoveCamera", to = start * CFrame.new(0, 0, -5), duration = 7, ease = "outExpo" },
					{ at = 1.8, action = "StopSound", name = "rain", fadeOut = 0.6 },
					{ at = 3.0, action = "StopSound", name = "buzz", fadeOut = 0.6 },
					{ at = 4.2, action = "StopSound", name = "clock", fadeOut = 0.4 },
					{ at = 5.2, action = "StopSound", name = "ambience", fadeOut = 0.6 },
					{ at = 6.4, action = "OpenDoor", model = set.door, amount = 0.3, duration = 0 },
					{ at = 6.6, action = "SpawnEffect", kind = "person", name = "shade", cframe = facing(set.at(13.5, 0, -0.2), set.at(13.5, 0, 4)), coat = Color3.fromRGB(8, 8, 9), skin = Color3.fromRGB(10, 10, 11) },
					{ at = 6.65, action = "MoveObject", name = "shade", to = facing(set.at(13.5, 0, 4.2), set.at(13.5, 0, 8)), duration = 0.9 },
				}, { { at = 8.4, action = "CutToBlack" } })
			end,
		},
		{
			Name = "Scene_WhisperFromTheWall",
			Description = "In front of a wall; whispers from inside it; the camera gets closer; they stop when it stops. One more, very near.",
			Duration = 11,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = CFrame.lookAt(set.at(-4, 5.8, 4), set.at(-12.4, 5.4, 4))
				local close = cam * CFrame.new(0, 0, -5.5)
				local inWall = set.at(-12.6, 5.6, 4)
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD", lamp = 0.55 }), {
					{ at = 1.0, action = "PlaySound", sound = "Whisper", position = inWall, volume = 0.35 },
					{ at = 2.0, action = "MoveCamera", to = close, duration = 5, ease = "inOutSine" },
					{ at = 3.1, action = "PlaySound", sound = "Whisper", position = inWall, volume = 0.45, speed = 0.9 },
					{ at = 4.7, action = "PlaySound", sound = "Whisper", position = inWall, volume = 0.55, speed = 1.05 },
					{ at = 6.1, action = "PlaySound", sound = "Whisper", position = inWall, volume = 0.6 },
					{ at = 7.0, action = "Silence", level = 0, fade = 0.2 },
					{ at = 9.0, action = "Unsilence", fade = 0 },
					{ at = 9.0, action = "PlaySound", sound = "Whisper", volume = 0.9, speed = 0.85 },
				}, Shots.cut(9.8))
			end,
		},
		{
			Name = "Scene_TheSoundFollows",
			Description = "A noise in one corner; the camera turns; now it comes from the other side; it follows the camera; then stops dead.",
			Duration = 12,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("center")
				local leftCam = Shots.turn(cam, 55)
				local rightCam = Shots.turn(cam, -55)
				local function side(c: CFrame, dx: number): Vector3
					return (c * CFrame.new(dx, -1, 1)).Position
				end
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD" }), {
					{ at = 1.4, action = "PlaySound", sound = "KnockDoor", position = set.at(-11, 3, -10), volume = 0.7 },
					{ at = 2.1, action = "MoveCamera", to = leftCam, duration = 1.0, ease = "inOutSine" },
					{ at = 4.2, action = "PlaySound", sound = "KnockDoor", position = side(leftCam, 7), volume = 0.75 },
					{ at = 4.8, action = "MoveCamera", to = rightCam, duration = 1.3, ease = "inOutSine" },
					{ at = 6.9, action = "PlaySound", sound = "KnockDoor", position = side(rightCam, -5), volume = 0.85 },
					{ at = 7.4, action = "MoveCamera", to = cam, duration = 0.9, ease = "inOutSine" },
					{ at = 9.0, action = "PlaySound", sound = "FootstepsBehind", position = Shots.behind(cam, 1.2), volume = 1 },
					{ at = 9.6, action = "Silence", level = 0, fade = 0 },
				}, Shots.cut(10.6))
			end,
		},
	},
}
