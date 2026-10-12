--[[
	Rng
	The one random source of Marketing Studio. Every take of a scene draws
	the same numbers in the same order (PlayScene reseeds it from the scene's
	Seed, or from its name), so glitches, flickers, grain and scratched text
	repeat identically between takes and an edit can be re-recorded.

	Drop-in for a Random object:  random:NextNumber(a?, b?)  random:NextInteger(a, b)
]]

local Rng = {}

local current = Random.new(1)

function Rng.seed(n: number)
	current = Random.new(n)
end

-- A stable seed from a scene name.
function Rng.hash(name: string): number
	local h = 2166136261
	for i = 1, #name do
		h = (bit32.bxor(h, string.byte(name, i)) * 16777619) % 4294967296
	end
	return h % 2147483647
end

function Rng.NextNumber(_self: any, a: number?, b: number?): number
	if a and b then
		return current:NextNumber(a, b)
	end
	return current:NextNumber()
end

function Rng.NextInteger(_self: any, a: number, b: number): number
	return current:NextInteger(a, b)
end

return Rng
