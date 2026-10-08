--[[
	Shots
	Small building blocks shared by the scene packs, so every scene starts,
	sounds and ends the same way and stays short to write:

	  Shots.join(a, b, ...)                 concatenate event lists
	  Shots.open(opts)                      mood opener: grade, vignette, grain, fade-in, ambience
	  Shots.room(set, opts)                 opener for Sets.room (lamp adopted as "lamp")
	  Shots.doorway(set, opts)              opener for Sets.doorway (key-art lamp)
	  Shots.cctv(cam, label, opts)          security-camera look
	  Shots.black(opts)                     black card opener
	  Shots.cut(at, opts)                   hard cut to black, sound off
	  Shots.steps(from, to, t0, n, gap, o)  footsteps walking from one point to another
	  Shots.knocks(at, pos, n, gap, o)      knocks
	  Shots.behind(camCf, distance)         a point behind the camera
	  Shots.turn(cf, degrees)               the same camera, turned (yaw)
]]

local Shots = {}

function Shots.join(...: { any }): { any }
	local out = {}
	for _, list in { ... } do
		for _, e in list do
			table.insert(out, e)
		end
	end
	return out
end

function Shots.open(opts: { [string]: any }?): { any }
	opts = opts or {}
	local list = {
		{ at = 0, action = "Grade", grade = opts.grade or "dread" },
		{ at = 0, action = "Vignette", on = opts.vignette ~= false },
		{ at = 0, action = "FadeFromBlack", from = 1, duration = opts.fade or 0.9 },
		{ at = 0, action = "PlayAmbience", sound = opts.ambience or "AmbientDrone", volume = opts.volume or 0.75 },
	}
	if opts.grain then
		table.insert(list, { at = 0, action = "FilmGrain", on = true })
	end
	return list
end

function Shots.room(set, opts: { [string]: any }?): { any }
	opts = opts or {}
	local list = Shots.open(opts)
	table.insert(list, { at = 0, action = "SetLighting", exposure = opts.exposure or 0.2, ambient = opts.ambient or Color3.fromRGB(34, 34, 40), brightness = 0 })
	table.insert(list, { at = 0, action = "AdoptLight", name = "lamp", part = set.lamp.bulb, light = set.lamp.light })
	if opts.lamp then
		table.insert(list, { at = 0, action = "DimKey", name = "lamp", ratio = opts.lamp, duration = 0 })
	end
	if opts.camera then
		table.insert(list, { at = 0, action = "SetCamera", cframe = opts.camera, preset = opts.preset or "CINEMATIC", fov = opts.fov })
	end
	return list
end

function Shots.doorway(set, opts: { [string]: any }?): { any }
	opts = opts or {}
	opts.grade = opts.grade or "keyart"
	opts.grain = opts.grain ~= false
	local list = Shots.open(opts)
	table.insert(list, { at = 0, action = "SetLighting", exposure = opts.exposure or 0, ambient = Color3.fromRGB(10, 10, 11), brightness = 0 })
	table.insert(list, { at = 0, action = "AdoptLight", name = "lamp", part = set.lamp.bulb, light = set.lamp.light })
	table.insert(list, { at = 0, action = "UseDoor", model = set.door, amount = opts.door or 0 })
	table.insert(list, { at = 0, action = "PlayAmbience", sound = "ElectricBuzz", name = "buzz", volume = 0.6, position = set.lamp.bulb.CFrame.Position })
	if opts.lamp then
		table.insert(list, { at = 0, action = "DimKey", name = "lamp", ratio = opts.lamp, duration = 0 })
	end
	return list
end

function Shots.cctv(cam: CFrame, label: string, opts: { [string]: any }?): { any }
	opts = opts or {}
	return {
		{ at = 0, action = "SetCamera", cframe = cam, preset = "CCTV" },
		{ at = 0, action = "CCTV", on = true, label = label },
		{ at = 0, action = "Grade", grade = "cctv" },
		{ at = 0, action = "PlayAmbience", sound = opts.ambience or "AmbientHum", volume = opts.volume or 1.3 },
		{ at = 0, action = "PlayAmbience", sound = "TapeHiss", name = "hiss", volume = 0.45 },
	}
end

function Shots.black(opts: { [string]: any }?): { any }
	opts = opts or {}
	local list = { { at = 0, action = "Backdrop", on = true } }
	if opts.ambience ~= false then
		table.insert(list, { at = 0, action = "PlayAmbience", sound = opts.ambience or "AmbientDrone", volume = opts.volume or 0.55, fadeIn = 1 })
	end
	return list
end

function Shots.cut(at: number, opts: { [string]: any }?): { any }
	opts = opts or {}
	return {
		{ at = at, action = "CutToBlack", sound = opts.sound, volume = opts.volume },
		{ at = at, action = "StopSound" },
	}
end

function Shots.steps(from: Vector3, to: Vector3, t0: number, count: number, gap: number, opts: { [string]: any }?): { any }
	opts = opts or {}
	local list = {}
	for i = 0, count - 1 do
		local a = if count > 1 then i / (count - 1) else 1
		table.insert(list, {
			at = t0 + i * gap,
			action = "PlaySound",
			sound = opts.sound or "StepConcrete",
			position = from:Lerp(to, a),
			volume = (opts.volume or 0.6) * (opts.grow and (0.4 + 0.6 * a) or 1),
			speed = opts.speed or 0.85,
		})
	end
	return list
end

function Shots.knocks(at: number, pos: Vector3, count: number, gap: number, opts: { [string]: any }?): { any }
	opts = opts or {}
	local list = {}
	for i = 0, count - 1 do
		table.insert(list, { at = at + i * gap, action = "PlaySound", sound = opts.sound or "KnockDoor", position = pos, volume = opts.volume or 0.4, speed = opts.speed or 0.85 })
	end
	return list
end

function Shots.behind(cam: CFrame, distance: number?): Vector3
	return (cam * CFrame.new(0, -0.5, distance or 3)).Position
end

function Shots.turn(cam: CFrame, degrees: number): CFrame
	return CFrame.new(cam.Position) * CFrame.Angles(0, math.rad(degrees), 0) * (cam - cam.Position)
end

return Shots
