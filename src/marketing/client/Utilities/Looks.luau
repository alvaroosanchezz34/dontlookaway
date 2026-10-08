--[[
	Looks
	Lighting + composition presets for shots (Visual Overhaul V2). A look sets,
	together: the grade, an exposure offset, fog density, the lens (FOV), the
	vignette and up to two key lights placed relative to the camera and the
	subject. Everything goes through LightFX / Screen / CameraRig, so the scene
	cleanup restores the game exactly as before.

	Key placement
	  from = "camera"   offset is in the camera's space (x right, y up, -z ahead)
	  from = "subject"  offset is in a frame at the subject facing the camera
	                    (so +z is toward the camera, -z behind the subject)
	  aim  = "subject" | "camera" | "down"
]]

local Looks = {}

local WARM = Color3.fromRGB(255, 214, 170)
local COLD = Color3.fromRGB(176, 196, 236)
local SODIUM = Color3.fromRGB(255, 186, 120)

Looks.Presets = {
	-- the eye in a doorway or a crack: tight lens, a low warm key from the side,
	-- a cold rim from behind, everything else falls off into black
	EyeCloseUp = {
		grade = "keyart", exposure = -0.15, fog = 0.06, fov = 26, vignette = true,
		keys = {
			{ name = "lookKey", from = "camera", offset = CFrame.new(-3, -0.6, -1), aim = "subject", angle = 30, range = 22, brightness = 2.6, color = WARM },
			{ name = "lookRim", from = "subject", offset = CFrame.new(1.6, 1.8, -2.6), aim = "subject", angle = 40, range = 10, brightness = 1.8, color = COLD },
		},
	},
	-- one-point perspective down a corridor: cold, deep fog so the far end
	-- dissolves, a single practical pool half way down
	LongCorridor = {
		grade = "cold", exposure = 0, fog = 0.4, fov = 52, vignette = true,
		keys = {
			{ name = "lookPool", from = "subject", offset = CFrame.new(0, 6, 0), aim = "down", angle = 70, range = 16, brightness = 1.6, color = COLD },
		},
	},
	-- a door ajar: warm light leaking through the gap toward the lens
	DoorAjar = {
		grade = "dread", exposure = -0.1, fog = 0.22, fov = 42, vignette = true,
		keys = {
			{ name = "lookLeak", from = "subject", offset = CFrame.new(0.4, 2, -3), aim = "camera", angle = 22, range = 30, brightness = 2.4, color = SODIUM },
		},
	},
	-- security camera: wide, flat, over-exposed a touch, no vignette
	CCTV = {
		grade = "cctv", exposure = 0.3, fog = 0.12, fov = 74, vignette = false,
		keys = {},
	},
	-- a figure at the back of a room: backlit so it reads as a silhouette
	FigureAtBack = {
		grade = "dread", exposure = -0.05, fog = 0.3, fov = 40, vignette = true,
		keys = {
			{ name = "lookBack", from = "subject", offset = CFrame.new(0, 5, -3.5), aim = "camera", angle = 35, range = 34, brightness = 2.2, color = COLD },
		},
	},
	-- an ordinary room: soft and readable (the calm before)
	NormalRoom = {
		grade = "neutral", exposure = 0.12, fog = 0.12, fov = 60, vignette = false,
		keys = {
			{ name = "lookFill", from = "camera", offset = CFrame.new(2, 2, 1), aim = "subject", angle = 70, range = 40, brightness = 0.9, color = WARM },
		},
	},
	-- the reveal: hard top light straight down on the subject, crushed blacks
	AnomalyReveal = {
		grade = "dark", exposure = -0.25, fog = 0.24, fov = 34, vignette = true,
		keys = {
			{ name = "lookTop", from = "subject", offset = CFrame.new(0, 9, 0.5), aim = "down", angle = 28, range = 16, brightness = 3, color = Color3.fromRGB(236, 238, 255) },
		},
	},
	-- cut to black: nothing left
	CutToBlack = {
		grade = "blackout", exposure = -4, fog = 0.5, vignette = true,
		keys = {},
	},
}

Looks.Order = { "EyeCloseUp", "LongCorridor", "DoorAjar", "CCTV", "FigureAtBack", "NormalRoom", "AnomalyReveal", "CutToBlack" }

-- World CFrame of a key light, or nil when it needs a subject that is missing.
function Looks.keyCFrame(key, camera: CFrame, subject: Vector3?): CFrame?
	local origin: CFrame
	if key.from == "subject" then
		if not subject then
			return nil
		end
		local flat = Vector3.new(camera.Position.X, subject.Y, camera.Position.Z)
		if (flat - subject).Magnitude < 0.01 then
			flat = subject + Vector3.new(0, 0, 1)
		end
		origin = CFrame.lookAt(subject, flat)
	else
		origin = camera
	end
	local pos = (origin * key.offset).Position
	local target: Vector3
	if key.aim == "camera" then
		target = camera.Position
	elseif key.aim == "down" then
		target = pos - Vector3.new(0, 10, 0) + Vector3.new(0.01, 0, 0)
	else
		target = subject or (camera * CFrame.new(0, 0, -10)).Position
	end
	return CFrame.lookAt(pos, target)
end

return Looks
