--[[
	LightingRules
	The one place that decides whether a fixture is lit, how bright and in
	what colour, from the building's state (workspace attributes) and the
	fixture's own attributes. The client paints with it (LightController); the
	server reads it to know where it is dark (LightingService:IsDark), so what
	the players see and what the game believes they can see are the same.

	Pure: no instances are changed here, only read.

	World (workspace attributes)
	  Power, Blackout (0-4), BlackoutZone, BlackoutSeed, Escape, and the
	  blackout's phase (BlackoutPhase, BlackoutPhaseAt, BlackoutSpan,
	  BlackoutStyle, BlackoutFrom: see the phases below)
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
-- the red of the emergency lamps at levels 3-4 with power: a little less
-- saturated than the alarm red. An accent in the dark, not the light you
-- walk by: the gain keeps the red pools well under the white lamps
LightingRules.ALARM_LIT = Color3.fromRGB(255, 96, 80)
LightingRules.ALARM_LIT_GAIN = 1.2
-- the colour the light drains to when the building breathes (level 2)
LightingRules.SICKLY = Color3.fromRGB(214, 226, 200)

--[[
	Blackouts: each level is darker and more macabre (docs/LIGHTING_MONOCHROME.md)
	With main power no level switches lamps off: every lamp that works gives
	less light on average the deeper the blackout (LEVEL_MEAN, what the
	server's steady reading uses), and how that light behaves changes too:
	  1 FAILS     a third of the lamps stutter and buzz, then come back
	  2 BREATHES  every lamp swells and sinks together, slowly (~0.25 Hz),
	              and the light drains to a sick, pale white
	  3 BEATS     every lamp beats like a heart (a double pulse); the
	              emergency lamps turn red, the only colour on screen
	  4 WATCHES   lamps go out one by one, far to near, and come back
	              (LightController, it depends on where you stand); red
	              emergency light pulses
	Without main power the emergency lamps are all there is, and the total
	blackout of the collapse (level 4) takes half of them.
	reduced: the player's reduced-effects setting: no pulse over 1 Hz.
]]
LightingRules.LEVEL_MEAN = { [0] = 1, [1] = 0.8, [2] = 0.55, [3] = 0.45, [4] = 0.35 }

-- A heart's double beat, 0..1, period ~1.15 s.
function LightingRules.heartbeat(t: number): number
	local p = (t % 1.15) / 1.15
	return math.exp(-((p - 0.08) / 0.04) ^ 2) + 0.6 * math.exp(-((p - 0.3) / 0.05) ^ 2)
end

--[[
	Blackout phases (Blackout 4): how the light fails and how it comes back.
	World attributes, written by LightingService:
	  BlackoutPhase   "ONSET" | "HOLD" | "RESTORE" | nil
	  BlackoutPhaseAt server time the phase began (workspace:GetServerTimeNow)
	  BlackoutSpan    the phase's length in seconds (ONSET, RESTORE)
	  BlackoutStyle   which onset this one is (1-4, never twice in a row)
	  BlackoutFrom    the level a RESTORE comes back from
	ONSET: the lamps go from full light to the level's behaviour, in one of
	four ways, so a blackout never announces itself the same way twice:
	  1 BROWNOUT  every lamp sags together, deep, and settles into the level
	  2 CASCADE   lamp by lamp, each at its own moment, a short stutter each
	  3 SURGE     a small swell (never a flash) then a hard sag and a stutter
	  4 STUTTER   lamps stutter on their own, less and less, then settle
	RESTORE: the level is over (the game reads full light) but the lamps come
	back one by one at their own moment, each striking like a tube that
	catches (two or three blinks), so the building wakes rather than pops.
	Reduced effects: no blinking at all, only smooth changes.
	Never brighter than ONSET_PEAK times the lamp's own brightness.
	The server's steady reading ignores the phases.
]]
LightingRules.ONSET_STYLES = { "BROWNOUT", "CASCADE", "SURGE", "STUTTER" }
LightingRules.ONSET_PEAK = 1.25

export type World = {
	power: boolean,
	level: number,
	zone: string,
	seed: number,
	escape: boolean,
	phase: string?,
	phaseT: number?,
	span: number?,
	style: number?,
	from: number?,
}
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

-- Server time, the clock the phases are stamped with (both sides read the
-- same one). Falls back to os.clock where the engine has none (tests).
function LightingRules.serverNow(ws: Instance): number
	local ok, t = pcall(function()
		return (ws :: any):GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

function LightingRules.world(ws: Instance, serverNow: number?): World
	local level = ws:GetAttribute("Blackout")
	local zone = ws:GetAttribute("BlackoutZone")
	local seed = ws:GetAttribute("BlackoutSeed")
	local phase = ws:GetAttribute("BlackoutPhase")
	local w: World = {
		power = ws:GetAttribute("Power") == true,
		level = if type(level) == "number" then level else 0,
		zone = if type(zone) == "string" then zone else "",
		seed = if type(seed) == "number" then seed else 0,
		escape = ws:GetAttribute("Escape") == true,
	}
	if phase == "ONSET" or phase == "HOLD" or phase == "RESTORE" then
		local at = ws:GetAttribute("BlackoutPhaseAt")
		local span = ws:GetAttribute("BlackoutSpan")
		local style = ws:GetAttribute("BlackoutStyle")
		local from = ws:GetAttribute("BlackoutFrom")
		w.phase = phase
		w.phaseT = if type(at) == "number" then (serverNow or LightingRules.serverNow(ws)) - at else 0
		w.span = if type(span) == "number" and span > 0 then span else 1
		w.style = if type(style) == "number" then style else 1
		w.from = if type(from) == "number" then from else 0
	end
	return w
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- A lamp's own blink while it fails or catches: on / dim / off from noise.
-- Reduced effects never blink (returns 1).
local function blink(now: number, seed: number, rate: number, reduced: boolean): number
	if reduced then
		return 1
	end
	local n = math.noise(now * rate, seed * 0.29 + 3.1)
	if n < -0.12 then
		return 0
	elseif n < 0.08 then
		return 0.35
	end
	return 1
end

--[[
	The light of a working main-circuit lamp during a blackout phase, from its
	full brightness (`full`) and what the level gives it now (`settled`).
	Returns the brightness to use. Pure; exported for the tests.
]]
function LightingRules.phaseBrightness(w: World, f: Fixture, full: number, settled: number, now: number, reduced: boolean): number
	local phase = w.phase
	if phase ~= "ONSET" and phase ~= "RESTORE" then
		return settled
	end
	local t = w.phaseT or 0
	local span = w.span or 1
	local u = t / span
	if u >= 1 or u < 0 then
		return settled
	end
	local frac = LightingRules.hashFrac(f.seed, (w.style or 1) * 31 + 7)
	local out
	if phase == "RESTORE" then
		-- each lamp comes back at its own moment, dim until then
		local dim = full * (LightingRules.LEVEL_MEAN[w.from or 0] or 1)
		local back = 0.08 + frac * 0.72
		if u < back then
			out = dim
		elseif u < back + 0.12 then
			-- the strike: a tube catching (a smooth rise with reduced effects)
			local k = (u - back) / 0.12
			out = if reduced then dim + (full - dim) * smooth(k) else full * blink(now, f.seed, 14, false) * (0.7 + 0.3 * k)
		else
			out = full
		end
		return math.min(out, full * LightingRules.ONSET_PEAK)
	end
	-- ONSET: from full light to the level's behaviour
	local style = w.style or 1
	local mix = smooth(u)
	local base = full + (settled - full) * mix
	if style == 1 then
		-- BROWNOUT: all together, a deep sag halfway, with a slow wobble
		local sag = 1 - 0.6 * math.sin(math.pi * math.clamp(u * 1.15, 0, 1)) ^ 2
		out = base * sag * (if reduced then 1 else 0.92 + 0.08 * math.sin(now * 5.5))
	elseif style == 2 then
		-- CASCADE: steady, then its own short stutter, then the level
		local at = frac * 0.7
		if u < at then
			out = full
		elseif u < at + 0.22 then
			out = full * 0.6 * blink(now, f.seed, 11, reduced)
		else
			out = settled
		end
	elseif style == 3 then
		-- SURGE: a small swell, then the sag and a stutter
		if u < 0.14 then
			out = full * (1 + (LightingRules.ONSET_PEAK - 1) * math.sin(math.pi * u / 0.14))
		elseif u < 0.55 then
			out = base * 0.45 * blink(now, f.seed, 9, reduced)
		else
			out = base
		end
	else
		-- STUTTER: lamps stutter on their own, fewer and fewer
		local chance = (1 - u) * 0.8
		out = if frac < chance then base * blink(now, f.seed, 10, reduced) else base
	end
	return math.clamp(out, 0, full * LightingRules.ONSET_PEAK)
end

-- How far a RESTORE has come (0..1), 1 when no restore is running: what the
-- building's hum and fans follow (AudioController).
function LightingRules.restoreProgress(w: World): number
	if w.phase ~= "RESTORE" then
		return 1
	end
	return math.clamp((w.phaseT or 0) / (w.span or 1), 0, 1)
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

function LightingRules.evaluate(f: Fixture, w: World, now: number, opts: { steady: boolean?, flicker: boolean?, reduced: boolean? }?): (boolean, number, Color3)
	local steady = opts ~= nil and opts.steady == true
	local reduced = opts ~= nil and opts.reduced == true
	local level = w.level
	local frac = LightingRules.hashFrac(f.seed, w.seed)

	-- does this fixture have current? Main power is all it takes: a blackout
	-- changes how the light behaves, not whether it is there
	local mainOn = w.power
	local blackoutFlicker = level == 1 and frac < 0.35
	local emergencyOn = f.emergency and not (level >= 4 and frac < 0.5)
	local lit = f.mode ~= "dead" and not f.off and (f.forceOn or (if f.emergency then (mainOn or emergencyOn) else mainOn))
	local color = f.tint or f.base
	local base = f.baseBrightness
	local brightness = base * (if mainOn then LightingRules.LEVEL_MEAN[level] or 1 else 1)
	if lit and mainOn and not steady then
		if level == 2 or (level == 3 and reduced) then
			-- breathing, all together (also level 3's beat when effects are reduced)
			brightness *= 1 + 0.16 * math.sin(now * math.pi * 2 * 0.25)
		elseif level == 3 then
			-- the heart: a low light that jumps twice a beat; the beat curve
			-- averages ~0.124, so the mean stays LEVEL_MEAN (under 2 pulses/s)
			brightness *= 0.75 + 2 * LightingRules.heartbeat(now)
		end
	end
	-- how the light fails and comes back (the blackout's phases)
	if lit and mainOn and not steady and not f.emergency and w.phase then
		brightness = LightingRules.phaseBrightness(w, f, base, brightness, now, reduced)
	end
	if lit and mainOn and level == 2 and not f.tint then
		color = color:Lerp(LightingRules.SICKLY, 0.5)
	end
	if lit and f.emergency and not f.forceOn and (level >= 3 or not mainOn) then
		-- emergency lighting on its own battery: dim and warm, red when
		-- things are serious; at levels 3-4 red even with power
		if level >= 3 or w.escape then
			color = f.tint or (if mainOn then LightingRules.ALARM_LIT else LightingRules.ALARM_COLOR)
			local rate = if reduced then 0.8 elseif level >= 4 then 3.2 else 1.6
			local pulse = if steady then 0.7 else 0.7 + 0.3 * math.sin(now * rate + f.seed)
			brightness = base * (if mainOn then LightingRules.ALARM_LIT_GAIN else 0.5) * pulse
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
			local n = math.noise(now * (if reduced then 3 else 9), f.seed * 0.37)
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
