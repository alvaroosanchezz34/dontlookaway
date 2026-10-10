--[[
	MimicBrain
	The Mimic's decisions, as a pure state machine (no instances, no physics):
	the driver (Mimic.luau) measures the world into a context table, asks for
	the next state, and acts. Pure so it can be tested without Roblox.

	States
	  SPAWNING       the model is checked (rig, root, floor, not in a wall)
	  IDLE           it stands like a person waiting; the head turns too far
	  PATROLLING     it walks, unhurried, to a reachable spot near its viewer
	  INVESTIGATING  someone pinged near it: it goes to look
	  STALKING       its viewer is close and not looking: it follows, a few
	                 metres behind. Looked at, it stops and acts natural
	                 (the tells: no flashlight, the slow wave, the head)
	  CHASING        noticed up close, it drops the act and runs at its viewer
	  ATTACKING      within reach: it lunges (server-checked range)
	  RECOVERING     a route failed or it got stuck: it picks another
	                 destination instead of pushing into a wall
	  DESPAWNING     it leaves (unseen if possible) and is cleaned up

	Context (ctx), all measured by the driver every tick:
	  valid, now, stateTime, lifetime, viewerAlive, dist, los, seen, seenFor,
	  unseenFor, arrived, routeFailed, stuck, ping (Vector3?), recoveries,
	  recovered
]]

local MimicBrain = {}

MimicBrain.States = {
	SPAWNING = "SPAWNING",
	IDLE = "IDLE",
	PATROLLING = "PATROLLING",
	INVESTIGATING = "INVESTIGATING",
	STALKING = "STALKING",
	CHASING = "CHASING",
	ATTACKING = "ATTACKING",
	RECOVERING = "RECOVERING",
	DESPAWNING = "DESPAWNING",
}
local S = MimicBrain.States

MimicBrain.Config = {
	Lifetime = 60, -- seconds before it gives up and leaves
	IdleFor = 2.5, -- standing still between walks
	StalkRange = 36, -- it starts following within this distance (with sight)
	StalkLoseAfter = 6, -- seconds without sight before it goes back to walking
	NoticedRange = 12, -- seen this close for NoticedFor -> it drops the act
	NoticedFor = 1.4,
	StaredDownAfter = 6, -- seen this long from further away -> it leaves
	ChaseFor = 7, -- a chase lasts at most this long
	ChaseLoseAfter = 2.5, -- seconds without sight before a chase gives up
	AttackRange = 4.5,
	InvestigateFor = 10,
	MaxRecoveries = 3,
	AttackHold = 0.6, -- the lunge, before it leaves
}
local C = MimicBrain.Config

-- Returns the next state and a short reason (for logs and the admin status).
function MimicBrain.decide(state: string, ctx: { [string]: any }): (string, string?)
	if state == S.DESPAWNING then
		return state, nil
	end
	if state == S.SPAWNING then
		if ctx.valid then
			return S.IDLE, "spawned"
		end
		return S.DESPAWNING, "invalid spawn: " .. tostring(ctx.invalidReason or "unknown")
	end
	if not ctx.viewerAlive then
		return S.DESPAWNING, "viewer gone"
	end
	if ctx.lifetime > C.Lifetime and state ~= S.CHASING and state ~= S.ATTACKING then
		return S.DESPAWNING, "lifetime"
	end
	if state == S.ATTACKING then
		if ctx.stateTime >= C.AttackHold then
			return S.DESPAWNING, "attacked"
		end
		return state, nil
	end
	if state == S.CHASING then
		if ctx.dist <= C.AttackRange then
			return S.ATTACKING, "in reach"
		end
		if ctx.stateTime > C.ChaseFor then
			return S.RECOVERING, "chase timed out"
		end
		if ctx.unseenFor > C.ChaseLoseAfter and not ctx.los then
			return S.RECOVERING, "lost its viewer"
		end
		if ctx.stuck or ctx.routeFailed then
			return S.RECOVERING, if ctx.stuck then "stuck while chasing" else "no route to its viewer"
		end
		return state, nil
	end
	if state == S.RECOVERING then
		if ctx.recoveries >= C.MaxRecoveries then
			return S.DESPAWNING, "could not recover a route"
		end
		if ctx.recovered then
			return S.PATROLLING, "new route"
		end
		return state, nil
	end
	-- noticed up close: the act is over
	if ctx.seen and ctx.dist < C.NoticedRange and ctx.seenFor >= C.NoticedFor then
		return S.CHASING, "noticed up close"
	end
	-- stared at from a distance for long enough: it leaves
	if ctx.seen and ctx.seenFor >= C.StaredDownAfter then
		return S.DESPAWNING, "stared down"
	end
	if state ~= S.STALKING and ctx.ping then
		return S.INVESTIGATING, "heard a ping"
	end
	if state == S.IDLE then
		if ctx.los and not ctx.seen and ctx.dist < C.StalkRange then
			return S.STALKING, "viewer close, not looking"
		end
		if ctx.stateTime >= C.IdleFor and not ctx.seen then
			return S.PATROLLING, "done waiting"
		end
		return state, nil
	end
	if state == S.PATROLLING or state == S.INVESTIGATING then
		if ctx.stuck or ctx.routeFailed then
			return S.RECOVERING, if ctx.stuck then "stuck" else "no route"
		end
		if ctx.los and not ctx.seen and ctx.dist < C.StalkRange then
			return S.STALKING, "viewer close, not looking"
		end
		if ctx.arrived then
			return S.IDLE, "arrived"
		end
		if state == S.INVESTIGATING and ctx.stateTime > C.InvestigateFor then
			return S.IDLE, "nothing there"
		end
		return state, nil
	end
	if state == S.STALKING then
		if ctx.stuck or ctx.routeFailed then
			return S.RECOVERING, if ctx.stuck then "stuck while stalking" else "no route to follow"
		end
		if not ctx.los and ctx.unseenFor > C.StalkLoseAfter then
			return S.PATROLLING, "lost sight of its viewer"
		end
		return state, nil
	end
	return state, nil
end

-- Walk speed for each state (studs/s). Watched, it stops: the driver handles
-- that (it "acts natural").
function MimicBrain.speed(state: string): number
	if state == S.CHASING then
		return 17
	elseif state == S.STALKING then
		return 9
	elseif state == S.PATROLLING or state == S.INVESTIGATING or state == S.RECOVERING then
		return 7
	end
	return 0
end

return MimicBrain
