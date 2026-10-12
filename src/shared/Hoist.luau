--!strict

-- Pure: the winches over the rings' marks and the robots on them. While a ring stands idle its robots hang from the
-- winches, hoisted clear of the canvas. The first round of a match lowers them over its intro, faster as they go, so they
-- land with a thud, and the hooks wind home before the bell; a robot new to its seat at the start of a match comes in on
-- the hook, so every new pair is dropped in, while a rematch starts on the marks. Training lowers them straight away, and
-- once the ring is idle again each hook comes down for its robot and hoists it back up. Where a robot should hang comes
-- from its match's phase and frame count, so every client sees the drop at the same moment, and robots and hooks only
-- ever move toward it at capped speeds, so no change of mode or rollback makes them jump. It is only a sight: in the
-- fight the fighters stand on their marks from the first frame. The client draws it (see Cranes).

local FightConfig = require(script.Parent.FightConfig)
local MatchFlow = require(script.Parent.MatchFlow)

-- One winch and the robot under it.
export type Winch = {
	-- How far the robot is drawn above its mark, and how far below the winch its hook hangs.
	lift: number,
	reach: number,
	-- Whether it has been stepped: the first step puts both where they should be.
	started: boolean,
}

-- What a winch follows of its ring's match (MatchView's view on the client).
export type Moment = {
	phase: number,
	phaseFrame: number,
	round: number,
	winsA: number,
	winsB: number,
}

local Hoist = {}

-- The first round's intro lowers the robots over this many frames.
Hoist.LandFrames = 70
-- How far above its feet the hook holds a robot of scale 1: the top of its head as it hangs powered down, and half the
-- hook. And the slack between a hoisted robot's hook and its winch.
Hoist.RobotTop = 6.7
Hoist.Slack = 1
-- How far the underside of a winch is below its ring's hook height (see Foundry's buildWinches).
Hoist.WinchDrop = 0.7
-- In studs a second: a robot going up, a robot coming down, and an empty hook. Coming down is quicker than the drop ever
-- moves, so the drop keeps its timing.
Hoist.RaiseSpeed = 7
Hoist.LowerSpeed = 20
Hoist.HookSpeed = 16

function Hoist.new(): Winch
	return { lift = 0, reach = 0, started = false }
end

-- How far above its mark a robot of `scale` hangs when it is hoisted all the way, under winches at `hookY` above the
-- ring's floor.
function Hoist.hang(hookY: number, scale: number): number
	return math.max(hookY - Hoist.WinchDrop - Hoist.Slack - FightConfig.GroundY - Hoist.RobotTop * scale, 0)
end

-- How far below its winch the hook hangs when it holds a robot of `scale` `lift` above its mark, by the top of its head.
function Hoist.grip(hookY: number, scale: number, lift: number): number
	return math.max(hookY - Hoist.WinchDrop - FightConfig.GroundY - Hoist.RobotTop * scale - lift, 0)
end

-- Whether a match is just starting: the intro to its first round, before anyone has won one.
local function opening(moment: Moment): boolean
	return moment.phase == MatchFlow.Phase.Intro and moment.round == 1 and moment.winsA + moment.winsB == 0
end

-- Where a robot of `scale` should hang above its mark now: hoisted all the way while its ring stands idle, coming down
-- over the first round's intro, and on its mark the rest of the time.
function Hoist.target(moment: Moment, hookY: number, scale: number): number
	if moment.phase == MatchFlow.Phase.Lobby then
		return Hoist.hang(hookY, scale)
	elseif opening(moment) then
		local t = math.clamp(moment.phaseFrame / Hoist.LandFrames, 0, 1)
		return Hoist.hang(hookY, scale) * (1 - t * t)
	end
	return 0
end

local function approach(current: number, target: number, step: number): number
	if math.abs(target - current) <= step then
		return target
	end
	return if target > current then current + step else current - step
end

-- Moves a winch on by `dt` seconds, for a robot of `scale` under winches at `hookY`. `fresh` says the robot is new to
-- its seat this frame. Returns true on the frame the robot touches down.
function Hoist.step(winch: Winch, moment: Moment, hookY: number, scale: number, dt: number, fresh: boolean): boolean
	local want = Hoist.target(moment, hookY, scale)
	if not winch.started then
		-- Seen for the first time, everything is where it should be.
		winch.started = true
		winch.lift = want
		winch.reach = if want > 0 then Hoist.grip(hookY, scale, want) else 0
		return false
	end
	if fresh and want > 0 and opening(moment) then
		-- A new robot at the start of a match comes in on the hook.
		winch.lift = want
		winch.reach = Hoist.grip(hookY, scale, want)
		return false
	end
	if opening(moment) then
		-- A match only lowers its robots: a rematch, which starts with them on their marks, keeps them there.
		want = math.min(want, winch.lift)
	end
	if winch.lift > 0 then
		-- On the hook: the robot goes toward where it should hang, and the hook goes with it.
		local speed = if want > winch.lift then Hoist.RaiseSpeed else Hoist.LowerSpeed
		winch.lift = approach(winch.lift, want, speed * dt)
		winch.reach = Hoist.grip(hookY, scale, winch.lift)
		return winch.lift == 0
	end
	if want > 0 then
		-- On its mark and wanted up: the hook goes to its head first (from above, or from below should the robot have
		-- been swapped for a taller one on the way), then hoists it.
		local grip = Hoist.grip(hookY, scale, 0)
		if winch.reach ~= grip then
			winch.reach = approach(winch.reach, grip, Hoist.HookSpeed * dt)
		else
			winch.lift = approach(0, want, Hoist.RaiseSpeed * dt)
			winch.reach = Hoist.grip(hookY, scale, winch.lift)
		end
		return false
	end
	-- On its mark: the hook winds home.
	winch.reach = approach(winch.reach, 0, Hoist.HookSpeed * dt)
	return false
end

return Hoist
