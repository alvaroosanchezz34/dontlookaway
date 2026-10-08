--[[
	Timeline
	The clock of one scene. Events fire when the clock reaches their `at`;
	anything that changes over time (a camera move, a fade, a door) is a span
	driven by this clock, so PAUSE freezes everything at once and TimeScale
	gives slow motion for free.

	  local tl = Timeline.new(events, duration, runEvent)
	  tl:step(dt)                         -- every frame
	  tl:span(duration, ease, fn, start?) -- fn(alpha 0..1) each frame, then fn(1)
	  tl:every(fn)                        -- fn(dt, clock) every frame until the scene ends
]]

local Ease = require(script.Parent.Utilities.Ease)

local Timeline = {}
Timeline.__index = Timeline

export type Event = { at: number, action: string, [string]: any }

type Span = { start: number, duration: number, ease: (number) -> number, fn: (number) -> (), id: string? }

function Timeline.new(events: { Event }, duration: number, runEvent: (any, Event) -> ())
	local list = table.clone(events)
	-- stable order: by time, then by declaration
	for i, e in list do
		(e :: any)._order = i
	end
	table.sort(list, function(a, b)
		if a.at == b.at then
			return (a :: any)._order < (b :: any)._order
		end
		return a.at < b.at
	end)
	local self = setmetatable({
		clock = 0,
		duration = duration,
		events = list,
		nextIndex = 1,
		spans = {} :: { Span },
		updaters = {} :: { (number, number) -> () },
		paused = false,
		speed = 1,
		runEvent = runEvent,
		data = {}, -- per-scene scratch for actions
	}, Timeline)
	return self
end

function Timeline:span(duration: number, ease: string?, fn: (number) -> (), start: number?, id: string?)
	local s: Span = { start = start or self.clock, duration = math.max(duration, 0), ease = Ease.get(ease), fn = fn, id = id }
	if id then
		-- a new span with the same id replaces the old one (e.g. two camera moves)
		for i = #self.spans, 1, -1 do
			if self.spans[i].id == id then
				table.remove(self.spans, i)
			end
		end
	end
	table.insert(self.spans, s)
	if s.duration == 0 then
		fn(1)
		table.remove(self.spans, table.find(self.spans, s) :: number)
	end
end

function Timeline:every(fn: (number, number) -> ())
	table.insert(self.updaters, fn)
end

function Timeline:isFinished(): boolean
	return self.clock >= self.duration
end

function Timeline:step(dt: number)
	if self.paused then
		return
	end
	dt *= self.speed
	self.clock += dt
	while self.nextIndex <= #self.events and self.events[self.nextIndex].at <= self.clock do
		local e = self.events[self.nextIndex]
		self.nextIndex += 1
		local ok, err = pcall(self.runEvent, self, e)
		if not ok then
			warn(string.format("[Marketing] event %s at %.2fs failed: %s", tostring(e.action), e.at, tostring(err)))
		end
	end
	local i = 1
	while i <= #self.spans do
		local s = self.spans[i]
		local alpha = if s.duration <= 0 then 1 else math.clamp((self.clock - s.start) / s.duration, 0, 1)
		local ok, err = pcall(s.fn, s.ease(alpha))
		if not ok then
			warn("[Marketing] span failed:", err)
		end
		if alpha >= 1 or not ok then
			table.remove(self.spans, i)
		else
			i += 1
		end
	end
	for _, fn in self.updaters do
		local ok, err = pcall(fn, dt, self.clock)
		if not ok then
			warn("[Marketing] updater failed:", err)
		end
	end
end

return Timeline
