--[[
	B · CCTV — security footage. Corridors use the real Ashgrove building when a
	round is running (Locations.cctvShot) and a virtual set otherwise; rooms use
	the room set with the camera high in a corner. CCTV look: 12 fps, mono
	grade, scanlines, REC, label and a running timestamp.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

return {
	Category = "B · CCTV",
	Scenes = {
		{
			Name = "Scene_CAM04_Anomaly",
			Description = "Someone crosses the corridor, the lights fail, they are gone; a silhouette at the end. SIGNAL LOST.",
			Duration = 15,
			Build = function(L)
				local cam, walkFrom, walkTo = L.cctvShot("G")
				local across = walkFrom:Lerp(walkTo, 0.2)
				local far = walkFrom + (walkFrom - walkTo).Unit * 6
				return Shots.join(Shots.cctv(cam, "CAM_04  ·  CORRIDOR G"), {
					{ at = 0, action = "SpawnEffect", kind = "actor", name = "staff", cframe = facing(walkTo, across) },
					{ at = 0.5, action = "MoveObject", name = "staff", to = facing(across, walkFrom), duration = 4 },
					{ at = 0.5, action = "PlaySound", sound = "DistantFootsteps", position = across, volume = 0.6 },
					{ at = 5.0, action = "FlickerLights", position = across + Vector3.new(0, 10, 0), radius = 32, duration = 1.4, depth = 2.6 },
					{ at = 5.9, action = "DestroyEffect", name = "staff" },
					{ at = 7.2, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(far, cam.Position), ash = false },
					{ at = 7.2, action = "FadeObject", name = "it", from = 1, to = 0.25, duration = 1.2 },
					{ at = 10.2, action = "Glitch", duration = 0.3, intensity = 0.8 },
					{ at = 10.4, action = "DestroyEffect", name = "it" },
					{ at = 11.2, action = "Static", alpha = 1, duration = 0.25 },
					{ at = 11.4, action = "ShowText", id = "lost", text = "CAMERA SIGNAL LOST", style = "cctv", size = 0.032, fadeIn = 0.1 },
				}, Shots.cut(14.2))
			end,
		},
		{
			Name = "Scene_CAM07_ImpossibleMovement",
			Description = "An empty room on CCTV: a chair moves in the static, the door opens alone, a figure faces the lens.",
			Duration = 13,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("corner")
				local chair = set.chair:GetPivot()
				return Shots.join(Shots.room(set, { lamp = 0.6 }), Shots.cctv(cam, "CAM_07  ·  ROOM 1-03"), {
					{ at = 0, action = "AdoptObject", name = "chair", model = set.chair },
					{ at = 3.0, action = "Glitch", duration = 0.2, intensity = 0.6 },
					{ at = 3.08, action = "PlaceObject", name = "chair", to = chair * CFrame.new(2.6, 0, 1.4) * CFrame.Angles(0, math.rad(70), 0) },
					{ at = 6.0, action = "OpenDoor", model = set.door, amount = 0.4, duration = 2.6, ease = "inOutSine" },
					{ at = 6.0, action = "PlaySound", sound = "WoodCreak", position = set.at(12, 5, 1.5), volume = 0.5 },
					{ at = 11.4, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(set.at(4.5, 0, 4.5), cam.Position), ash = false },
					{ at = 11.95, action = "Glitch", duration = 0.15, intensity = 0.9 },
				}, Shots.cut(12.1))
			end,
		},
		{
			Name = "Scene_CCTV_LookBehindYou",
			Description = "A figure far down the corridor; every interference it is closer. It turns its head to the lens. DO NOT WATCH.",
			Duration = 14,
			Build = function(L)
				local cam, walkFrom, walkTo = L.cctvShot("G")
				local far = walkFrom + (walkFrom - walkTo).Unit * 8
				local away = walkFrom + (walkFrom - walkTo).Unit * 30
				local function spot(a: number): Vector3
					return far:Lerp(walkTo, a)
				end
				return Shots.join(Shots.cctv(cam, "CAM_02  ·  CORRIDOR G"), {
					{ at = 0.8, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(spot(0), away), ash = false },
					{ at = 3.4, action = "Glitch", duration = 0.15, intensity = 0.5 },
					{ at = 3.45, action = "PlaceObject", name = "it", to = facing(spot(0.3), away) },
					{ at = 5.8, action = "Glitch", duration = 0.15, intensity = 0.55 },
					{ at = 5.85, action = "PlaceObject", name = "it", to = facing(spot(0.55), away) },
					{ at = 7.9, action = "Glitch", duration = 0.15, intensity = 0.6 },
					{ at = 7.95, action = "PlaceObject", name = "it", to = facing(spot(0.75), away) },
					-- it turns to the camera, slowly
					{ at = 9.0, action = "MoveObject", name = "it", to = facing(spot(0.75), cam.Position), duration = 1.6, ease = "inOutSine" },
					{ at = 10.9, action = "FreezeFrame", on = true },
					{ at = 11.1, action = "ShowText", id = "warn", text = "DO NOT WATCH", style = "cctv", size = 0.036, fadeIn = 0.05 },
					{ at = 12.5, action = "Static", alpha = 1, duration = 0.2 },
				}, Shots.cut(13.4))
			end,
		},
		{
			Name = "Scene_CCTV_TheExtraPerson",
			Description = "Three still figures in a watched room; a fourth at the back; gone; then somewhere it cannot be.",
			Duration = 12,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("corner")
				local window = set.at(0, 0, -12)
				return Shots.join(Shots.room(set, { lamp = 0.65 }), Shots.cctv(cam, "CAM_05  ·  STAFF ROOM"), {
					{ at = 0, action = "SpawnEffect", kind = "person", name = "a", cframe = facing(set.at(-5, 0, -2), window) },
					{ at = 0, action = "SpawnEffect", kind = "person", name = "b", cframe = facing(set.at(-1, 0, -4), window), coat = Color3.fromRGB(60, 52, 44) },
					{ at = 0, action = "SpawnEffect", kind = "person", name = "c", cframe = facing(set.at(3, 0, -1.5), window), coat = Color3.fromRGB(46, 50, 58) },
					{ at = 2.8, action = "SpawnEffect", kind = "entity", name = "extra", cframe = facing(set.at(-7.5, 0, -10), cam.Position), ash = false },
					{ at = 5.6, action = "Glitch", duration = 0.2, intensity = 0.6 },
					{ at = 5.65, action = "DestroyEffect", name = "extra" },
					-- impossible: standing on the table, right in the middle of them
					{ at = 8.2, action = "Glitch", duration = 0.2, intensity = 0.7 },
					{ at = 8.25, action = "SpawnEffect", kind = "entity", name = "extra2", cframe = facing(set.at(4, 3.15, -6), cam.Position), ash = false },
				}, Shots.cut(11.2))
			end,
		},
		{
			Name = "Scene_CCTV_TheCameraTurns",
			Description = "A noise off-screen; the security camera turns to it; nothing; it turns back: a figure right at the lens.",
			Duration = 12,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = CFrame.lookAt(set.at(-10.5, 11, 10.5), set.at(10, 3, 1.5)) -- watching the door
				local turned = CFrame.lookAt(cam.Position, set.at(0, 3, -12)) -- the window side
				local close = (cam * CFrame.new(0, -4, -5.5)).Position
				return Shots.join(Shots.room(set, { lamp = 0.6 }), Shots.cctv(cam, "CAM_03  ·  ROOM 1-02"), {
					{ at = 2.5, action = "PlaySound", sound = "Thud", position = set.at(-3, 2, -11), volume = 0.9 },
					{ at = 3.1, action = "MoveCamera", to = turned, duration = 1.6, ease = "inOutSine" },
					{ at = 3.1, action = "PlaySound", sound = "DeviceTick", volume = 0.5 },
					{ at = 6.4, action = "MoveCamera", to = cam, duration = 2.4, ease = "inOutSine" },
					{ at = 7.2, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(Vector3.new(close.X, set.origin.Position.Y, close.Z), cam.Position), ash = false },
					{ at = 9.8, action = "Glitch", duration = 0.3, intensity = 1 },
				}, Shots.cut(10.3))
			end,
		},
		{
			Name = "Scene_CCTV_TimeLoop",
			Description = "Someone crosses the corridor. The tape repeats. Something is wrong the second time; the third, they look at the lens.",
			Duration = 16,
			Build = function(L)
				local cam, walkFrom, walkTo = L.cctvShot("G")
				local mid = walkFrom:Lerp(walkTo, 0.55)
				local far = walkFrom + (walkFrom - walkTo).Unit * 9
				local start = facing(walkFrom, walkTo)
				local function pass(t0: number): { any }
					return {
						{ at = t0, action = "PlaceObject", name = "staff", to = start },
						{ at = t0 + 0.05, action = "MoveObject", name = "staff", to = facing(walkTo, walkTo + (walkTo - walkFrom)), duration = 3.2 },
					}
				end
				local function rewind(at: number): { any }
					return {
						{ at = at, action = "Glitch", duration = 0.25, intensity = 0.7 },
						{ at = at, action = "Static", alpha = 0.6, duration = 0 },
						{ at = at + 0.25, action = "Static", alpha = 0, duration = 0, sound = false },
					}
				end
				return Shots.join(Shots.cctv(cam, "CAM_04  ·  CORRIDOR G"), {
					{ at = 0, action = "SpawnEffect", kind = "actor", name = "staff", cframe = start },
				}, pass(0.4), rewind(3.9), pass(4.2), {
					-- the second time, someone else is standing at the end
					{ at = 4.6, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(far, cam.Position), ash = false },
					{ at = 7.35, action = "DestroyEffect", name = "it" },
				}, rewind(7.4), {
					{ at = 7.7, action = "PlaceObject", name = "staff", to = start },
					{ at = 7.75, action = "MoveObject", name = "staff", to = facing(mid, walkTo), duration = 1.9 },
					{ at = 9.8, action = "MoveObject", name = "staff", to = facing(mid, cam.Position), duration = 1.2, ease = "inOutSine" },
					{ at = 11.6, action = "FreezeFrame", on = true },
					{ at = 11.8, action = "ShowText", id = "loop", text = "THIS HAS HAPPENED BEFORE", style = "cctv", size = 0.03, fadeIn = 0.1 },
				}, Shots.cut(15.2))
			end,
		},
	},
}
