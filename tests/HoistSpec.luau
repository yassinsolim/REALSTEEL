--!strict

-- Headless checks for the winches that hang, drop and hoist the rings' robots (Hoist). Run from Studio's command bar, or
-- without Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.HoistSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local Hoist = require(ReplicatedStorage.Shared.Hoist)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)

local Phase = MatchFlow.Phase
local DT = 1 / FightConfig.SimHz
local EPSILON = 1e-6

local function moment(phase: number, frame: number?, round: number?, wins: number?): Hoist.Moment
	return { phase = phase, phaseFrame = frame or 0, round = round or 1, winsA = wins or 0, winsB = 0 }
end

local function lobby(_frame: number): Hoist.Moment
	return moment(Phase.Lobby)
end

local function intro(frame: number): Hoist.Moment
	return moment(Phase.Intro, frame)
end

local function free(_frame: number): Hoist.Moment
	return moment(Phase.Free)
end

local function fight(frame: number): Hoist.Moment
	return moment(Phase.Fight, frame)
end

type Run = {
	-- The frames the robot touched down on, the most it moved between two frames, whether it ever went up, and how far
	-- it ever was from where it should hang.
	landings: { number },
	jump: number,
	rose: boolean,
	lag: number,
	-- The most the hook moved between two frames while it held no robot, and the furthest it ever was from the head of a
	-- robot it held.
	hookJump: number,
	slip: number,
}

-- Steps a winch through frames `from` to `to` of `at`, with a robot of `scale` under winches at `hookY`. `freshOn`
-- names the frame its robot is new to the seat, if any.
local function run(
	winch: Hoist.Winch,
	at: (number) -> Hoist.Moment,
	from: number,
	to: number,
	hookY: number,
	scale: number,
	freshOn: number?
): Run
	local result: Run = { landings = {}, jump = 0, rose = false, lag = 0, hookJump = 0, slip = 0 }
	for frame = from, to do
		local lift, reach = winch.lift, winch.reach
		local now = at(frame)
		if Hoist.step(winch, now, hookY, scale, DT, frame == freshOn) then
			table.insert(result.landings, frame)
		end
		if frame ~= freshOn then
			result.jump = math.max(result.jump, math.abs(winch.lift - lift))
			result.rose = result.rose or winch.lift > lift + EPSILON
			if lift == 0 and winch.lift == 0 then
				result.hookJump = math.max(result.hookJump, math.abs(winch.reach - reach))
			end
		end
		result.lag = math.max(result.lag, math.abs(winch.lift - Hoist.target(now, hookY, scale)))
		if winch.lift > 0 then
			result.slip = math.max(result.slip, math.abs(winch.reach - Hoist.grip(hookY, scale, winch.lift)))
		end
	end
	return result
end

-- A winch that has been stepped in `at` for long enough to settle there.
local function settled(at: (number) -> Hoist.Moment, hookY: number, scale: number): Hoist.Winch
	local winch = Hoist.new()
	run(winch, at, 0, 600, hookY, scale)
	return winch
end

return function(): (number, { string })
	local passed = 0
	local failures: { string } = {}

	local function check(name: string, condition: boolean, detail: any?)
		if condition then
			passed += 1
		else
			table.insert(failures, if detail ~= nil then `{name} ({detail})` else name)
		end
	end

	local MAIN = FoundryLayout.Rings[1].hookY
	local PIT = FoundryLayout.Rings[2].hookY
	local scales: { number } = {}
	for _, chassis in Loadout.Chassis do
		table.insert(scales, chassis.scale)
	end
	local INTRO = FightConfig.Match.introFrames
	local LAND = Hoist.LandFrames

	-- How high, and the hook by the robot's head.
	do
		local hang = Hoist.hang(MAIN, 1)
		check("a hoisted robot hangs clear of the canvas", hang > 2, hang)
		check(
			"its hook holds it by the head, a slack's length under the winch",
			math.abs(Hoist.grip(MAIN, 1, hang) - Hoist.Slack) < EPSILON
		)
		check("a bigger build hangs lower", Hoist.hang(MAIN, 1.1) < Hoist.hang(MAIN, 0.94))
		check("the hook rides with the robot", math.abs(Hoist.grip(MAIN, 1, 0) - Hoist.grip(MAIN, 1, 2) - 2) < EPSILON)
		check("a robot too big to hoist stays on its mark", Hoist.hang(MAIN, 3) == 0)
	end

	-- Where a robot should hang.
	do
		local hang = Hoist.hang(PIT, 1)
		check("an idle ring's robots hang", Hoist.target(moment(Phase.Lobby), PIT, 1) == hang)
		check("a match starts with them hanging", Hoist.target(intro(0), PIT, 1) == hang)
		local half = Hoist.target(intro(LAND / 2), PIT, 1)
		check("and lowers them, slowly at first", half > hang / 2 and half < hang, half)
		check("onto their marks by the landing", Hoist.target(intro(LAND), PIT, 1) == 0)
		check("which comes before the bell", LAND < INTRO)
		check("later rounds start on the marks", Hoist.target(moment(Phase.Intro, 0, 2), PIT, 1) == 0)
		check("as does any round after one is won", Hoist.target(moment(Phase.Intro, 0, 1, 1), PIT, 1) == 0)
		local standing = true
		for _, phase in { Phase.Free, Phase.Fight, Phase.RoundEnd, Phase.MatchEnd } do
			standing = standing and Hoist.target(moment(phase), PIT, 1) == 0
		end
		check("training, fights and their ends stand them on their marks", standing)
	end

	-- The drop never outruns the winch, and is over with the hooks home before the bell, in every ring and build.
	do
		local fastest = 0
		local alwaysLanded, alwaysHome, alwaysFollowed, alwaysHeld = true, true, true, true
		for _, spec in FoundryLayout.Rings do
			for _, scale in scales do
				local before = Hoist.target(intro(0), spec.hookY, scale)
				for frame = 1, LAND do
					local now = Hoist.target(intro(frame), spec.hookY, scale)
					fastest = math.max(fastest, (before - now) / DT)
					before = now
				end
				local winch = settled(lobby, spec.hookY, scale)
				-- The client first sees a match some frames in.
				local drop = run(winch, intro, 7, INTRO, spec.hookY, scale)
				alwaysLanded = alwaysLanded and #drop.landings == 1 and drop.landings[1] == LAND
				alwaysFollowed = alwaysFollowed and drop.lag < EPSILON
				alwaysHeld = alwaysHeld and drop.slip < EPSILON
				alwaysHome = alwaysHome and winch.reach == 0
			end
		end
		check("the drop never outruns the winch", fastest < Hoist.LowerSpeed, fastest)
		check("a hanging pair is dropped in time with the match", alwaysFollowed)
		check("held by the head all the way down", alwaysHeld)
		check("and lands once, on the landing frame", alwaysLanded)
		check("the hooks are home by the bell", alwaysHome)
	end

	-- The first time a winch is seen, it is put where it should be.
	do
		local hanging = Hoist.new()
		Hoist.step(hanging, moment(Phase.Lobby), PIT, 1, DT, false)
		check(
			"an idle ring is first seen with its robots hanging",
			hanging.lift == Hoist.hang(PIT, 1) and math.abs(hanging.reach - Hoist.Slack) < EPSILON
		)
		local dropping = Hoist.new()
		Hoist.step(dropping, intro(35), PIT, 1, DT, false)
		check("a drop is first seen part way down", dropping.lift == Hoist.target(intro(35), PIT, 1))
		local fighting = Hoist.new()
		local landed = Hoist.step(fighting, fight(0), PIT, 1, DT, false)
		check("a fight is first seen with its robots on their marks", fighting.lift == 0 and fighting.reach == 0)
		check("which is no landing", not landed)
	end

	-- A rematch starts on the marks; a new robot at the start of a match is dropped in.
	do
		local winch = settled(fight, MAIN, 1)
		local rematch = run(winch, intro, 6, INTRO, MAIN, 1)
		check("a rematch keeps its robots on their marks", winch.lift == 0 and not rematch.rose)
		check("with no landing", #rematch.landings == 0)
		check("and the hooks stay home", winch.reach == 0)

		local newcomer = settled(fight, MAIN, 1.08)
		local arrival = run(newcomer, intro, 6, INTRO, MAIN, 1.08, 6)
		check(
			"a new robot at the start of a match comes in on the hook",
			arrival.lag < EPSILON and #arrival.landings == 1 and arrival.landings[1] == LAND,
			#arrival.landings
		)
		local trainee = settled(fight, MAIN, 1)
		run(trainee, free, 0, 30, MAIN, 1, 0)
		check("a new robot in training starts on its mark", trainee.lift == 0)

		-- One that turns up after the landing is already on its mark, and the hook winding home carries on.
		local late = settled(lobby, MAIN, 1)
		run(late, intro, 7, LAND + 5, MAIN, 1)
		local reach = late.reach
		Hoist.step(late, intro(LAND + 6), MAIN, 1, DT, true)
		check("a new robot after the landing leaves the hook winding home", late.lift == 0 and late.reach < reach)
		check(
			"without a jump",
			reach - late.reach <= Hoist.HookSpeed * DT + EPSILON and late.reach > 0,
			reach - late.reach
		)
	end

	-- Training lowers a hanging robot at once; an idle ring hoists it back up, the hook coming down for it first.
	do
		local hang = Hoist.hang(PIT, 0.94)
		local winch = settled(lobby, PIT, 0.94)
		local lowering = run(winch, free, 0, 120, PIT, 0.94)
		-- The frames are counted from 0.
		local steps = math.ceil(hang / (Hoist.LowerSpeed * DT) - EPSILON)
		check("training lowers a hanging robot straight away", lowering.landings[1] == steps - 1, lowering.landings[1])
		check("and lands it once", #lowering.landings == 1)
		check("at a capped speed", lowering.jump <= Hoist.LowerSpeed * DT + EPSILON, lowering.jump)
		check("and its hook winds home", winch.reach == 0)

		local grip = Hoist.grip(PIT, 0.94, 0)
		local waited = 0
		while winch.lift == 0 and waited < 300 do
			-- Going idle empties the seat, so the robot is new to it, and still waits for the hook.
			Hoist.step(winch, moment(Phase.Lobby), PIT, 0.94, DT, waited == 0)
			waited += 1
		end
		check(
			"idle again, the robot waits for its hook",
			waited >= math.ceil(grip / (Hoist.HookSpeed * DT)) - 1,
			waited
		)
		check("which comes down to its head", math.abs(winch.reach - Hoist.grip(PIT, 0.94, winch.lift)) < EPSILON)
		local hoist = run(winch, lobby, 0, 180, PIT, 0.94)
		check("then hoists it all the way", winch.lift == hang and #hoist.landings == 0)
		check("by the head", hoist.slip < EPSILON, hoist.slip)
		check("at a capped speed", hoist.jump <= Hoist.RaiseSpeed * DT + EPSILON, hoist.jump)
		check("an empty hook moves at a capped speed", lowering.hookJump <= Hoist.HookSpeed * DT + EPSILON)

		-- A robot swapped for a taller one while its hook comes down for it: the hook goes back up to the new head, without
		-- a jump, and then hoists it.
		local swapped = settled(fight, PIT, 0.94)
		local tall = Hoist.grip(PIT, 1.1, 0)
		for _ = 1, 300 do
			if swapped.reach > tall + 0.5 then
				break
			end
			Hoist.step(swapped, moment(Phase.Lobby), PIT, 0.94, DT, false)
		end
		local reach = swapped.reach
		Hoist.step(swapped, moment(Phase.Lobby), PIT, 1.1, DT, true)
		local moved = reach - swapped.reach
		check(
			"a robot swapped under a coming hook does not make it jump",
			swapped.lift == 0 and moved > 0 and moved <= Hoist.HookSpeed * DT + EPSILON,
			moved
		)
		run(swapped, lobby, 0, 240, PIT, 1.1)
		check(
			"and the taller robot is hoisted by its head",
			swapped.lift == Hoist.hang(PIT, 1.1) and math.abs(swapped.reach - Hoist.Slack) < EPSILON
		)
	end

	-- Changes of mind: nothing jumps.
	do
		local winch = settled(lobby, MAIN, 1)
		run(winch, intro, 7, 30, MAIN, 1)
		local back = run(winch, lobby, 0, 120, MAIN, 1)
		check("a drop called off is hoisted back", winch.lift == Hoist.hang(MAIN, 1) and #back.landings == 0)
		check("without a jump", back.jump <= Hoist.RaiseSpeed * DT + EPSILON, back.jump)

		local partway = settled(fight, MAIN, 1)
		for _ = 1, 300 do
			if partway.lift >= 2 then
				break
			end
			Hoist.step(partway, moment(Phase.Lobby), MAIN, 1, DT, false)
		end
		local caught = run(partway, intro, 7, INTRO, MAIN, 1)
		check("a match that starts mid-hoist only lowers its robot", partway.lift == 0 and not caught.rose)
		check("and lands it with the drop", #caught.landings == 1 and caught.landings[1] == LAND)

		local replayed = settled(lobby, MAIN, 1)
		run(replayed, intro, 7, 60, MAIN, 1)
		local rollback = run(replayed, function(frame: number)
			return intro(if frame < 10 then 50 + frame else 60 + frame)
		end, 0, 20, MAIN, 1)
		check("a rollback never lifts a dropping robot", not rollback.rose)
		check("nor lands it twice", #rollback.landings == 1)

		local hitch = settled(lobby, MAIN, 1)
		Hoist.step(hitch, intro(10), MAIN, 1, DT, false)
		local before = hitch.lift
		Hoist.step(hitch, intro(40), MAIN, 1, 0.5, false)
		check("a long frame follows the drop", hitch.lift == Hoist.target(intro(40), MAIN, 1), before - hitch.lift)
	end

	return passed, failures
end
