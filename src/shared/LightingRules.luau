--[[
	LightingRules
	The one place that decides whether a fixture is lit, how bright and in
	what colour, from the building's state (workspace attributes) and the
	fixture's own attributes. The client paints with it (LightController); the
	server reads it to know where it is dark (LightingService:IsDark), so what
	the players see and what the game believes they can see are the same.

	Pure: no instances are changed here, only read.

	World (workspace attributes)
	  Power, Blackout (0-4), BlackoutZone, BlackoutSeed, Escape
	Fixture (model attributes)
	  Mode (on | flicker | dead), Circuit (MAIN | EMERGENCY), ForceOn,
	  Override ("off"), Tint, BaseColor, BaseBrightness, Seed, Room

	evaluate(fixture, world, now, opts) -> (lit, brightness, color)
	  opts.steady   ignore everything that changes from frame to frame
	                (flicker, pulses): what the server uses to decide where
	                light is. A flickering lamp counts as lit.
	  opts.flicker  an extra "flicker now" (room flickers, scares) from the client
]]

local LightingRules = {}

LightingRules.EMERGENCY_COLOR = Color3.fromRGB(255, 176, 120)
LightingRules.ALARM_COLOR = Color3.fromRGB(255, 64, 52)

-- Share of its brightness a fixture that still has main current keeps at each
-- blackout level, so the states read apart at a glance, from brightest to
-- darkest: normal > 1 > 2 > 3 / no power > 4. Emergency lamps running on
-- their own battery are dimmed separately.
LightingRules.BLACKOUT_SAG = { [1] = 0.7, [2] = 0.45, [3] = 0.7 }

export type World = { power: boolean, level: number, zone: string, seed: number, escape: boolean }
export type Fixture = {
	seed: number,
	floor: string,
	mode: string,
	emergency: boolean,
	forceOn: boolean,
	off: boolean,
	tint: Color3?,
	base: Color3,
	baseBrightness: number,
}

function LightingRules.hashFrac(a: number, b: number): number
	local h = (a * 7919 + b * 104729 + 1013) % 100003
	return (h % 1000) / 1000
end

function LightingRules.world(ws: Instance): World
	local level = ws:GetAttribute("Blackout")
	local zone = ws:GetAttribute("BlackoutZone")
	local seed = ws:GetAttribute("BlackoutSeed")
	return {
		power = ws:GetAttribute("Power") == true,
		level = if type(level) == "number" then level else 0,
		zone = if type(zone) == "string" then zone else "",
		seed = if type(seed) == "number" then seed else 0,
		escape = ws:GetAttribute("Escape") == true,
	}
end

-- seed: the fixture's own (LightController keeps a random one for fixtures
-- that have none; the server falls back to 0 for those)
function LightingRules.fixture(m: Instance, seed: number?): Fixture
	local room = m:GetAttribute("Room")
	local tint = m:GetAttribute("Tint")
	local base = m:GetAttribute("BaseColor")
	local own = m:GetAttribute("Seed")
	return {
		seed = seed or (if type(own) == "number" then own else 0),
		floor = if type(room) == "string" then room:sub(1, 1) else "",
		mode = m:GetAttribute("Mode") or "on",
		emergency = m:GetAttribute("Circuit") == "EMERGENCY",
		forceOn = m:GetAttribute("ForceOn") == true,
		off = m:GetAttribute("Override") == "off",
		tint = if typeof(tint) == "Color3" then tint else nil,
		base = if typeof(base) == "Color3" then base else Color3.new(1, 1, 1),
		baseBrightness = m:GetAttribute("BaseBrightness") or 1,
	}
end

function LightingRules.evaluate(f: Fixture, w: World, now: number, opts: { steady: boolean?, flicker: boolean? }?): (boolean, number, Color3)
	local steady = opts ~= nil and opts.steady == true
	local level = w.level
	local frac = LightingRules.hashFrac(f.seed, w.seed)

	-- does this fixture have current?
	local mainOn = w.power
	local blackoutFlicker = false
	if level == 1 then
		blackoutFlicker = frac < 0.35
	elseif level == 2 then
		if f.floor == w.zone then
			mainOn = false
		end
	elseif level == 3 then
		if frac < 0.85 then
			mainOn = false
		else
			blackoutFlicker = true
		end
	elseif level >= 4 then
		mainOn = false
	end
	local emergencyOn = f.emergency and not (level >= 4 and frac < 0.5)
	local lit = f.mode ~= "dead" and not f.off and (f.forceOn or (if f.emergency then (mainOn or emergencyOn) else mainOn))
	local color = f.tint or f.base
	local base = f.baseBrightness
	local brightness = base * (LightingRules.BLACKOUT_SAG[level] or 1)
	if lit and f.emergency and not mainOn and not f.forceOn then
		-- emergency lighting: dim and warm, red when things are serious
		if level >= 3 or w.escape then
			color = f.tint or LightingRules.ALARM_COLOR
			local pulse = if steady then 0.7 else 0.7 + 0.3 * math.sin(now * (if level >= 4 then 3.2 else 1.6) + f.seed)
			brightness = base * 0.5 * pulse
		else
			color = f.tint or LightingRules.EMERGENCY_COLOR
			brightness = base * 0.55
		end
	end
	if lit and w.escape and not (f.emergency and not mainOn) and not steady then
		-- the building is failing: slow, uneasy pulse
		brightness *= 0.55 + 0.35 * math.sin(now * 2.2 + f.seed)
	end
	if not steady then
		local flickering = lit and (f.mode == "flicker" or blackoutFlicker or (opts ~= nil and opts.flicker == true))
		if flickering then
			local n = math.noise(now * 9, f.seed * 0.37)
			if n < -0.15 then
				lit = false
			elseif n < 0.05 then
				brightness *= 0.4
			end
		end
	end
	return lit, brightness, color
end

return LightingRules
