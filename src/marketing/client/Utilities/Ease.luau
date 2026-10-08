--[[
	Ease
	Easing curves by name, for camera moves, fades and every timed change.
]]

local Ease = {}

local CURVES: { [string]: (number) -> number } = {
	linear = function(t)
		return t
	end,
	inQuad = function(t)
		return t * t
	end,
	outQuad = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	inOutQuad = function(t)
		return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
	end,
	inCubic = function(t)
		return t * t * t
	end,
	outCubic = function(t)
		return 1 - (1 - t) ^ 3
	end,
	inOutCubic = function(t)
		return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
	end,
	inOutSine = function(t)
		return -(math.cos(math.pi * t) - 1) / 2
	end,
	inExpo = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end,
	outExpo = function(t)
		return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
	end,
	-- a slow creep that never quite settles (dread dolly)
	creep = function(t)
		return t ^ 1.6
	end,
}

function Ease.get(name: string?): (number) -> number
	return CURVES[name or "inOutSine"] or CURVES.inOutSine
end

function Ease.apply(name: string?, t: number): number
	return Ease.get(name)(math.clamp(t, 0, 1))
end

function Ease.names(): { string }
	local list = {}
	for k in CURVES do
		table.insert(list, k)
	end
	table.sort(list)
	return list
end

return Ease
