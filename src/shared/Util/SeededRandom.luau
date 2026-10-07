--[[
	SeededRandom
	Deterministic random helpers built on Random.new(seed). Every random decision
	inside a round goes through a stream derived from the round seed so a round can
	be reproduced exactly from its seed (debugging, statistics, consistent events).
]]

local SeededRandom = {}
SeededRandom.__index = SeededRandom

local function hashString(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- FNV prime 16777619 = 2^24 + 403, split to stay inside double precision.
		h = (h * 403 + bit32.lshift(h, 24)) % 4294967296
	end
	return h
end

function SeededRandom.new(seed: number, stream: string?)
	local mixed = seed
	if stream then
		mixed = (seed + hashString(stream)) % 2147483647
	end
	return setmetatable({ Seed = seed, Stream = stream, _rng = Random.new(mixed) }, SeededRandom)
end

function SeededRandom:Derive(stream: string)
	return SeededRandom.new(self.Seed, (self.Stream or "") .. "/" .. stream)
end

function SeededRandom:Int(min: number, max: number): number
	if max < min then
		return min
	end
	return self._rng:NextInteger(min, max)
end

function SeededRandom:Number(min: number?, max: number?): number
	return self._rng:NextNumber(min or 0, max or 1)
end

function SeededRandom:Chance(p: number): boolean
	return self._rng:NextNumber() < p
end

function SeededRandom:Pick(list)
	if #list == 0 then
		return nil
	end
	return list[self._rng:NextInteger(1, #list)]
end

function SeededRandom:Shuffle(list)
	for i = #list, 2, -1 do
		local j = self._rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- entries: { {item = x, weight = n}, ... }
function SeededRandom:Weighted(entries)
	local total = 0
	for _, entry in entries do
		total += math.max(0, entry.weight)
	end
	if total <= 0 then
		return nil
	end
	local roll = self._rng:NextNumber() * total
	for _, entry in entries do
		roll -= math.max(0, entry.weight)
		if roll <= 0 then
			return entry.item
		end
	end
	return entries[#entries].item
end

function SeededRandom:Range(range)
	return self:Number(range[1], range[2])
end

SeededRandom.HashString = hashString

return SeededRandom
