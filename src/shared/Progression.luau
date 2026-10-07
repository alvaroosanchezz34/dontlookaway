--[[
	Progression
	Light level curve. Levels only unlock cosmetics and titles.
]]

local Progression = {}

Progression.MaxLevel = 50

function Progression.xpForLevel(level: number): number
	-- XP required to go from `level` to `level + 1`
	return math.floor(120 + (level - 1) * 45 + (level - 1) ^ 1.35 * 8)
end

-- Returns level, xpIntoLevel, xpNeededForNext from a total XP amount.
function Progression.fromTotal(totalXP: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))
	while level < Progression.MaxLevel do
		local need = Progression.xpForLevel(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return Progression.MaxLevel, 0, 0
end

return Progression
