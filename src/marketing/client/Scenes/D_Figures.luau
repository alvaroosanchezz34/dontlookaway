--[[
	D · FIGURES — the Observer (ObserverRig local copy), wall shadows with
	nothing to cast them, eyeshine in the dark. Mostly in the room set.
]]

local Sets = require(script.Parent.Parent.Effects.Sets)
local Shots = require(script.Parent.Parent.Utilities.Shots)

local function facing(at: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))
end

-- a CFrame on a wall of the room set, facing into the room, at floor level
local function wall(set, x: number, z: number, nx: number, nz: number): CFrame
	local p = set.at(x, 0, z)
	return CFrame.lookAt(p, p + Vector3.new(nx, 0, nz))
end

return {
	Category = "D · FIGURES",
	Scenes = {
		{
			Name = "Scene_TheFigureAtTheWindow",
			Description = "A tap on the glass, a silhouette outside; it is gone, but its reflection is still in the room.",
			Duration = 11.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local shot = set.shot("window")
				local glassCf = CFrame.lookAt(set.at(-1.2, 4.05, -12.52), set.at(-1.2, 4.05, 0))
				return Shots.join(Shots.room(set, { camera = shot, lamp = 0.5 }), {
					{ at = 1.4, action = "PlaySound", sound = "KnockDoor", position = set.at(0, 7, -12.6), volume = 0.4, speed = 1.3 },
					{ at = 1.9, action = "SpawnEffect", kind = "entity", name = "it", cframe = set.outsideFeet, ash = false },
					{ at = 3.0, action = "MoveCamera", to = shot * CFrame.new(0, 0.2, -5), duration = 4, ease = "creep" },
					{ at = 6.2, action = "FlickerLights", key = "lamp", duration = 0.4, world = false, sound = "LightFlicker", position = set.lamp.bulb.CFrame.Position },
					{ at = 6.4, action = "DestroyEffect", name = "it" },
					-- the reflection on the glass: someone standing in the room, behind you
					{ at = 7.6, action = "SpawnEffect", kind = "shadow", name = "reflection", cframe = glassCf, height = 5.6, transparency = 0.62 },
					{ at = 7.6, action = "FadeObject", name = "reflection", from = 1, to = 0, duration = 0.8 },
					{ at = 8.6, action = "PlaySound", sound = "ObserverInhale", position = Shots.behind(shot, 4), volume = 0.4 },
				}, Shots.cut(10.4))
			end,
		},
		{
			Name = "Scene_TheFigureDoesNotMove",
			Description = "A still figure at the end of the corridor. Every time it leaves the frame it is closer. It never moves.",
			Duration = 13,
			Build = function(L)
				local from = L.corridor("G")
				local function at(a: number): CFrame
					return facing(L.corridorPoint("G", a), from.Position)
				end
				local left, right = Shots.turn(from, 55), Shots.turn(from, -55)
				return Shots.join(Shots.open({ grade = "dread" }), {
					{ at = 0, action = "SetCamera", cframe = from, preset = "HANDHELD" },
					{ at = 0, action = "SpawnEffect", kind = "entity", name = "it", cframe = at(0.9), ash = false },
					{ at = 2.4, action = "MoveCamera", to = left, duration = 1.1, ease = "inOutSine" },
					{ at = 3.6, action = "PlaceObject", name = "it", to = at(0.66) },
					{ at = 4.0, action = "MoveCamera", to = from, duration = 1.1, ease = "inOutSine" },
					{ at = 6.2, action = "MoveCamera", to = right, duration = 1.1, ease = "inOutSine" },
					{ at = 7.4, action = "PlaceObject", name = "it", to = at(0.42) },
					{ at = 7.8, action = "MoveCamera", to = from, duration = 1.1, ease = "inOutSine" },
					{ at = 9.9, action = "MoveCamera", to = left, duration = 1.0, ease = "inOutSine" },
					{ at = 11.0, action = "PlaceObject", name = "it", to = at(0.16) },
					{ at = 11.3, action = "MoveCamera", to = from, duration = 0.8, ease = "inOutSine" },
					{ at = 11.6, action = "Silence", level = 0, fade = 0.2 },
				}, Shots.cut(12.4))
			end,
		},
		{
			Name = "Scene_TheEmptyRoom",
			Description = "A shadow on the wall that nothing casts; it moves the wrong way; gone; then on the ceiling.",
			Duration = 11.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local backWall = wall(set, -7, -11.95, 0, 1)
				local ceiling = CFrame.lookAt(set.at(3, 12.95, -4), set.at(3, 0, -4)) * CFrame.Angles(0, 0, math.rad(180))
				return Shots.join(Shots.room(set, { camera = set.shot("center"), preset = "STATIC" }), {
					{ at = 2.4, action = "SpawnEffect", kind = "shadow", name = "s", cframe = backWall, height = 7.5 },
					{ at = 2.4, action = "FadeObject", name = "s", from = 1, to = 0, duration = 1 },
					-- the lamp is in the middle: a real shadow would slide away from it, this one slides towards it
					{ at = 4.0, action = "MoveObject", name = "s", to = backWall * CFrame.new(-4, 0, 0), duration = 2.2, ease = "inOutSine" },
					{ at = 6.4, action = "FadeObject", name = "s", from = 0, to = 1, duration = 0.5 },
					{ at = 8.6, action = "SpawnEffect", kind = "shadow", name = "c", cframe = ceiling, height = 7.5 },
					{ at = 8.6, action = "PlaySound", sound = "WoodCreak", position = set.at(3, 12, -4), volume = 0.6, speed = 0.7 },
				}, Shots.cut(10.6))
			end,
		},
		{
			Name = "Scene_TheObserverIsWatching",
			Description = "The camera tries to keep a figure in frame; each time it slips out it is somewhere else. It looks at you. DID YOU SEE IT?",
			Duration = 14,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("center")
				local function at(x: number, z: number): CFrame
					return facing(set.at(x, 0, z), cam.Position)
				end
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD", lamp = 0.7 }), {
					{ at = 0.8, action = "SpawnEffect", kind = "entity", name = "it", cframe = at(8, -9), ash = false },
					{ at = 2.4, action = "MoveCamera", to = CFrame.lookAt(cam.Position, set.at(8, 5, -9)), duration = 1.2, ease = "inOutSine" },
					{ at = 3.8, action = "MoveCamera", to = Shots.turn(CFrame.lookAt(cam.Position, set.at(8, 5, -9)), -50), duration = 0.7, ease = "inOutSine" },
					{ at = 4.2, action = "PlaceObject", name = "it", to = at(-8, -8) },
					{ at = 5.0, action = "MoveCamera", to = CFrame.lookAt(cam.Position, set.at(-8, 5, -8)), duration = 1.0, ease = "inOutSine" },
					{ at = 6.6, action = "MoveCamera", to = Shots.turn(CFrame.lookAt(cam.Position, set.at(-8, 5, -8)), 55), duration = 0.7, ease = "inOutSine" },
					{ at = 7.0, action = "PlaceObject", name = "it", to = at(0, -9.5) },
					{ at = 7.8, action = "MoveCamera", to = CFrame.lookAt(cam.Position, set.at(0, 6, -9.5)), duration = 1.0, ease = "inOutSine" },
					{ at = 9.4, action = "Silence", level = 0, fade = 0.1 },
					{ at = 10.4, action = "DestroyEffect", name = "it" },
					{ at = 11.0, action = "ShowText", id = "q", text = "DID YOU SEE IT?", style = "whisper", size = 0.034, fadeIn = 0.3, duration = 2 },
				}, Shots.cut(13.2))
			end,
		},
		{
			Name = "Scene_TheFigureBehindTheCamera",
			Description = "A noise behind the camera; it spins round: nothing; it turns back: a figure that was not there.",
			Duration = 9.5,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("center")
				return Shots.join(Shots.room(set, { camera = cam, preset = "HANDHELD" }), {
					{ at = 2.2, action = "PlaySound", sound = "FootstepsBehind", position = Shots.behind(cam, 2.5), volume = 0.9 },
					{ at = 2.7, action = "MoveCamera", to = Shots.turn(cam, 180), duration = 0.4, ease = "outCubic" },
					{ at = 2.7, action = "ShakeCamera", amount = 0.3, decay = 1.5 },
					{ at = 3.6, action = "SpawnEffect", kind = "entity", name = "it", cframe = facing(set.at(-3, 0, -8), cam.Position), ash = false },
					{ at = 4.3, action = "MoveCamera", to = cam, duration = 0.7, ease = "inOutSine" },
					{ at = 5.1, action = "Silence", level = 0.1, fade = 0.3 },
				}, Shots.cut(8.4))
			end,
		},
		{
			Name = "Scene_TheWrongShadow",
			Description = "Someone stands still; their shadow does not. It turns to the camera. The light stutters: both gone.",
			Duration = 11,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local cam = set.shot("left")
				local personAt = set.at(-8, 0, -8.5)
				local shadowCf = wall(set, -6.2, -11.95, 0, 1)
				return Shots.join(Shots.room(set, { camera = cam, preset = "STATIC" }), {
					{ at = 0, action = "SpawnEffect", kind = "person", name = "p", cframe = facing(personAt, set.at(-8, 0, 0)) },
					{ at = 0, action = "SpawnEffect", kind = "shadow", name = "s", cframe = shadowCf, height = 7.2 },
					{ at = 2.8, action = "MoveObject", name = "s", to = shadowCf * CFrame.new(-3.2, 0, 0), duration = 2.2, ease = "inOutSine" },
					-- its head turns: two points of light in the shadow, looking out
					{ at = 5.6, action = "SpawnEffect", kind = "shine", name = "eyes", cframe = shadowCf * CFrame.new(-3.2, 6.6, -0.08), size = 0.1, gap = 0.36 },
					{ at = 5.6, action = "PlaySound", sound = "ObserverInhale", volume = 0.35 },
					{ at = 7.6, action = "FlickerLights", key = "lamp", duration = 0.6, world = false, sound = "LightFlicker", position = set.lamp.bulb.CFrame.Position },
					{ at = 8.0, action = "DestroyEffect", name = "p" },
					{ at = 8.0, action = "DestroyEffect", name = "s" },
					{ at = 8.0, action = "DestroyEffect", name = "eyes" },
				}, Shots.cut(10.2))
			end,
		},
		{
			Name = "Scene_TheRoomIsWatching",
			Description = "A slow pan: eyeshine in the dark corners. Pan back: nothing. Then one right in front of the lens.",
			Duration = 12,
			Light = 1,
			Isolated = true,
			Build = function()
				local set = Sets.room()
				local start = CFrame.lookAt(set.at(-9, 5.6, 9), set.at(-10, 3, -11))
				local finish = CFrame.lookAt(set.at(-9, 5.6, 9), set.at(11, 3, -6))
				return Shots.join(Shots.room(set, { camera = start, lamp = 0.35, exposure = 0 }), {
					{ at = 0, action = "OpenDoor", model = set.door, amount = 0.12, duration = 0 },
					{ at = 0.4, action = "MoveCamera", to = finish, duration = 6, ease = "inOutSine" },
					{ at = 0.6, action = "SpawnEffect", kind = "shine", name = "e1", cframe = CFrame.new(set.at(-10.6, 1.1, -10.2)), size = 0.08, gap = 0.3 },
					{ at = 1.8, action = "SpawnEffect", kind = "shine", name = "e2", cframe = CFrame.new(set.at(4.2, 1.2, -6.4)), size = 0.08, gap = 0.28 },
					{ at = 3.0, action = "SpawnEffect", kind = "shine", name = "e3", cframe = CFrame.new(set.at(8.2, 5.8, -9.3)), size = 0.08, gap = 0.3 },
					{ at = 4.2, action = "SpawnEffect", kind = "shine", name = "e4", cframe = CFrame.new(set.at(12.7, 6.2, -0.2)), size = 0.09, gap = 0.32 },
					{ at = 7.0, action = "MoveCamera", to = start, duration = 2.2, ease = "inOutSine" },
					{ at = 7.4, action = "DestroyEffect", name = "e1" },
					{ at = 7.4, action = "DestroyEffect", name = "e2" },
					{ at = 7.4, action = "DestroyEffect", name = "e3" },
					{ at = 7.4, action = "DestroyEffect", name = "e4" },
					{ at = 10.2, action = "SpawnEffect", kind = "shine", name = "close", cframe = start * CFrame.new(0.3, -0.2, -2.4), size = 0.16, gap = 0.62 },
					{ at = 10.2, action = "PlaySound", sound = "ObserverInhale", volume = 0.5 },
				}, Shots.cut(10.75))
			end,
		},
	},
}
