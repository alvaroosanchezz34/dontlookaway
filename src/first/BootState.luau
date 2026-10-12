--[[
	BootState
	What the client has really finished preparing, phase by phase. The
	loading screen (Loading.client) reads it; the systems that do the work
	write it:
	  world     the experience's content has arrived (game.Loaded)
	  systems   every controller ran Init and started (Client/Main)
	  records   the player's record arrived from the server (NetController)
	  assets    the menu's sounds and the building's textures were preloaded
	            (Loading.client, ContentProvider:PreloadAsync)
	  building  the server finished building tonight's building (MapReady)

	Each phase is "pending", "active", "done", "failed" (it went wrong: the
	game goes on without it) or "skipped" (it took too long: the game goes on
	and it finishes in the background). Nothing here fakes progress: a phase
	is only "done" when whatever does the work says so.

	It also guards the client's start: claim("client") is true only once, so
	the controllers can never be started twice.

	It lives in ReplicatedFirst and requires nothing: it runs before the
	rest of the game has arrived.
]]

local BootState = {}

export type Phase = { id: string, text: string, required: boolean }

BootState.PHASES = {
	{ id = "world", text = "Opening the building", required = true },
	{ id = "systems", text = "Waking the systems", required = true },
	{ id = "records", text = "Synchronising your records", required = false },
	{ id = "assets", text = "Checking the lights and sounds", required = false },
	{ id = "building", text = "Preparing tonight's building", required = false },
} :: { Phase }

-- How long the screen waits for each phase before going on without it.
BootState.TIMEOUT = { world = 60, systems = 45, records = 20, assets = 15, building = 25 }

local VALID = { pending = true, active = true, done = true, failed = true, skipped = true }

local status: { [string]: string } = {}
local notes: { [string]: string? } = {}
local claimed: { [string]: boolean } = {}
-- a tiny signal of its own (nothing else exists yet when this runs)
local listeners: { (string, string, string?) -> () } = {}
BootState.Changed = {
	Connect = function(_, fn: (string, string, string?) -> ())
		table.insert(listeners, fn)
		return {
			Disconnect = function()
				local i = table.find(listeners, fn)
				if i then
					table.remove(listeners, i)
				end
			end,
		}
	end,
} -- (id, status, note)

for _, phase in BootState.PHASES do
	status[phase.id] = "pending"
end

function BootState.set(id: string, newStatus: string, note: string?)
	if status[id] == nil or not VALID[newStatus] then
		return
	end
	-- a finished phase stays finished (a late "active" never undoes it)
	local current = status[id]
	if (current == "done" or current == "failed") and newStatus == "active" then
		return
	end
	if current == newStatus and notes[id] == note then
		return
	end
	status[id] = newStatus
	notes[id] = note
	for _, fn in table.clone(listeners) do
		task.spawn(fn, id, newStatus, note)
	end
end

function BootState.get(id: string): (string?, string?)
	return status[id], notes[id]
end

function BootState.isFinished(id: string): boolean
	local s = status[id]
	return s == "done" or s == "failed" or s == "skipped"
end

-- Every required phase finished (done or failed), every other one finished
-- or given up on.
function BootState.ready(): boolean
	for _, phase in BootState.PHASES do
		if not BootState.isFinished(phase.id) then
			return false
		end
	end
	return true
end

-- True the first time only: the guard against starting something twice.
function BootState.claim(name: string): boolean
	if claimed[name] then
		return false
	end
	claimed[name] = true
	return true
end

-- Tests: back to the start.
function BootState.reset()
	for _, phase in BootState.PHASES do
		status[phase.id] = "pending"
		notes[phase.id] = nil
	end
	table.clear(claimed)
end

return BootState
