--!strict

-- Headless checks for the round flow and the bot. Run from Studio's command bar or the Studio MCP:
--   local passed, failures = require(game.ReplicatedStorage.Tests.BotSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FightSim = require(ReplicatedStorage.Shared.FightSim)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)

local State = FightSim.State
local Phase = MatchFlow.Phase
local Mode = MatchFlow.Mode
local Result = MatchFlow.Result
local Reason = MatchFlow.Reason
local rules = FightConfig.Match

local EASY, MEDIUM, HARD = 1, 2, 3

local function pair(ax: number, bx: number): (FightSim.Fighter, FightSim.Fighter)
	return FightSim.newFighter(ax, 0), FightSim.newFighter(bx, 0)
end

-- Steps the flow `frames` times with the fighters untouched.
local function flowFrames(match: MatchFlow.Match, a: FightSim.Fighter, b: FightSim.Fighter, frames: number): boolean
	local reset = false
	for _ = 1, frames do
		reset = MatchFlow.step(match, a, b) or reset
	end
	return reset
end

-- Starts a round match and skips the intro, leaving it in the fight.
local function inFight(): (MatchFlow.Match, FightSim.Fighter, FightSim.Fighter)
	local match = MatchFlow.new()
	local a, b = pair(-3, 3)
	MatchFlow.start(match, Mode.Rounds)
	flowFrames(match, a, b, rules.introFrames)
	return match, a, b
end

-- One round between two controllers, ended by a KO or the clock. Returns 1, 2 or 0 for a draw.
local function playRound(levelA: number, levelB: number, seed: number): number
	local a, b = pair(-3, 3)
	FightSim.reset(a, b)
	local inputA, inputB = FightSim.newInput(), FightSim.newInput()
	local options: FightSim.Options = { training = false, rounds = true, combat = true }
	local tick = seed * 7919 + 13
	for _ = 1, rules.roundSeconds * FightConfig.SimHz do
		tick += 1
		BotBrain.input(tick, a, b, inputA, levelA, 1)
		BotBrain.input(tick, b, a, inputB, levelB, 2)
		FightSim.step(a, b, inputA, inputB, options)
		if a.state == State.KO or b.state == State.KO then
			break
		end
	end
	if a.state == State.KO and b.state == State.KO then
		return 0
	elseif a.state == State.KO then
		return 2
	elseif b.state == State.KO then
		return 1
	elseif a.hp > b.hp then
		return 1
	elseif b.hp > a.hp then
		return 2
	end
	return 0
end

-- How often `levelX` wins a round against `levelY`, taking each side alternately.
local function winRate(levelX: number, levelY: number, rounds: number): number
	local wins, decided = 0, 0
	for index = 1, rounds do
		local winner
		if index % 2 == 0 then
			local result = playRound(levelY, levelX, index)
			winner = if result == 1 then 2 elseif result == 2 then 1 else 0
		else
			winner = playRound(levelX, levelY, index)
		end
		if winner ~= 0 then
			decided += 1
			if winner == 1 then
				wins += 1
			end
		end
	end
	return wins / math.max(decided, 1)
end

-- A player who walks in and mashes the jab, which is the first thing most people try.
local function jabMasher(tick: number, me: FightSim.Fighter, foe: FightSim.Fighter, into: FightSim.Input)
	local dx = foe.x - me.x
	local dz = foe.z - me.z
	local dist = math.sqrt(dx * dx + dz * dz)
	into.moveX = 0
	into.moveZ = if dist > 4.6 then 1 elseif dist < 4.0 then -1 else 0
	into.jab = dist <= 4.7 and tick % 2 == 0
	into.straight = false
	into.leftKick = false
	into.rightKick = false
	into.guard = false
	into.dash = false
	into.grab = false
end

-- How often a bot of `level` beats the jab masher over `rounds` rounds, taking each side alternately; a draw counts half.
local function winRateAgainstMasher(level: number, rounds: number): number
	local score = 0
	for index = 1, rounds do
		local a, b = pair(-3, 3)
		FightSim.reset(a, b)
		local botIsA = index % 2 == 1
		local inputA, inputB = FightSim.newInput(), FightSim.newInput()
		local options: FightSim.Options = { training = false, rounds = true, combat = true }
		local tick = index * 7919 + 13
		for _ = 1, rules.roundSeconds * FightConfig.SimHz do
			tick += 1
			if botIsA then
				BotBrain.input(tick, a, b, inputA, level, 1)
				jabMasher(tick, b, a, inputB)
			else
				jabMasher(tick, a, b, inputA)
				BotBrain.input(tick, b, a, inputB, level, 2)
			end
			FightSim.step(a, b, inputA, inputB, options)
			if a.state == State.KO or b.state == State.KO then
				break
			end
		end
		local bot = if botIsA then a else b
		local masher = if botIsA then b else a
		if bot.state == State.KO or masher.state == State.KO then
			-- A knockout decides it, and knocking each other out is a draw.
			score += if masher.state ~= State.KO then 0 elseif bot.state ~= State.KO then 1 else 0.5
		else
			score += if bot.hp > masher.hp then 1 elseif bot.hp == masher.hp then 0.5 else 0
		end
	end
	return score / rounds
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

	-- Starting a match.
	do
		local match = MatchFlow.new()
		check("a new match starts in the lobby", match.phase == Phase.Lobby)
		MatchFlow.start(match, Mode.Rounds)
		check("rounds begin with the intro", match.phase == Phase.Intro and match.round == 1)
		check(
			"the clock starts full",
			match.timer == rules.roundSeconds * FightConfig.SimHz and MatchFlow.secondsLeft(match) == rules.roundSeconds
		)
		MatchFlow.start(match, Mode.Free)
		check("training has no rounds", match.phase == Phase.Free)
		MatchFlow.start(match, Mode.Lobby)
		check("the menu freezes the fight", match.phase == Phase.Lobby and not MatchFlow.canAct(match))

		check("lobby fits only the lobby", MatchFlow.fits(match, Mode.Lobby) and not MatchFlow.fits(match, Mode.Rounds))
		MatchFlow.start(match, Mode.Free)
		check("free fits only training", MatchFlow.fits(match, Mode.Free) and not MatchFlow.fits(match, Mode.Lobby))
		MatchFlow.start(match, Mode.Rounds)
		check(
			"every round phase fits rounds",
			MatchFlow.fits(match, Mode.Rounds) and not MatchFlow.fits(match, Mode.Free)
		)
		check(
			"training allows action",
			(function()
				MatchFlow.start(match, Mode.Free)
				return MatchFlow.canAct(match)
			end)()
		)
	end

	-- The intro, the fight and the clock.
	do
		local match = MatchFlow.new()
		local a, b = pair(-3, 3)
		MatchFlow.start(match, Mode.Rounds)
		check("nobody acts during the intro", not MatchFlow.canAct(match))
		flowFrames(match, a, b, rules.introFrames - 1)
		check("the intro is still on one frame early", match.phase == Phase.Intro)
		flowFrames(match, a, b, 1)
		check("the fight begins after the intro", match.phase == Phase.Fight and MatchFlow.canAct(match))
		flowFrames(match, a, b, FightConfig.SimHz)
		check("the clock runs one second a second", MatchFlow.secondsLeft(match) == rules.roundSeconds - 1, match.timer)
		check("ticks only go up", match.tick >= rules.introFrames + FightConfig.SimHz)
	end

	-- A knockout ends the round for the other fighter.
	do
		local match, a, b = inFight()
		b.hp = 0
		b.state = State.KO
		MatchFlow.step(match, a, b)
		check("a KO ends the round", match.phase == Phase.RoundEnd and match.reason == Reason.KO)
		check("the survivor wins the round", match.result == Result.A and match.winsA == 1 and match.winsB == 0)
		check("nobody acts after the bell", not MatchFlow.canAct(match))

		local match2, c, d = inFight()
		c.state = State.KO
		MatchFlow.step(match2, c, d)
		check("fighter B takes the round when A is knocked out", match2.result == Result.B and match2.winsB == 1)

		local match3, e, f = inFight()
		e.state = State.KO
		f.state = State.KO
		MatchFlow.step(match3, e, f)
		check(
			"a double KO is a draw that scores nothing",
			match3.result == Result.Draw
				and match3.reason == Reason.DoubleKO
				and match3.winsA == 0
				and match3.winsB == 0
		)
	end

	-- The clock decides by health.
	do
		local match, a, b = inFight()
		match.timer = 1
		a.hp = 70
		b.hp = 40
		MatchFlow.step(match, a, b)
		check(
			"time up with more health wins the round",
			match.phase == Phase.RoundEnd and match.reason == Reason.Time and match.result == Result.A
		)

		local match2, c, d = inFight()
		match2.timer = 1
		c.hp = 30
		d.hp = 55
		MatchFlow.step(match2, c, d)
		check("the fighter with more health wins on time", match2.result == Result.B and match2.winsB == 1)

		local match3, e, f = inFight()
		match3.timer = 1
		MatchFlow.step(match3, e, f)
		check("equal health on time is a draw", match3.result == Result.Draw and match3.winsA + match3.winsB == 0)
	end

	-- Between rounds and the end of the match.
	do
		local match, a, b = inFight()
		b.state = State.KO
		MatchFlow.step(match, a, b)
		check(
			"the round-end banner lasts",
			not flowFrames(match, a, b, rules.roundEndFrames - 1) and match.phase == Phase.RoundEnd
		)
		local reset = flowFrames(match, a, b, 1)
		check("the next round starts after the banner", reset and match.phase == Phase.Intro and match.round == 2)
		check("the clock is refilled for the next round", match.timer == rules.roundSeconds * FightConfig.SimHz)

		-- Win the second round as well: the match is over.
		flowFrames(match, a, b, rules.introFrames)
		check(
			"an undecided match has no winner yet",
			MatchFlow.winner(match.phase, match.winsA, match.winsB, true) == nil
		)
		b.state = State.KO
		MatchFlow.step(match, a, b)
		check("first to the target takes the match", match.winsA == rules.roundsToWin and MatchFlow.isDecided(match))
		check(
			"while its knockout plays out the match is not over",
			match.phase == Phase.RoundEnd and MatchFlow.winner(match.phase, match.winsA, match.winsB, false) == nil
		)
		check(
			"but a match torn down then goes to whoever won it",
			MatchFlow.winner(match.phase, match.winsA, match.winsB, true) == 1
		)
		check("from either side", MatchFlow.winner(match.phase, match.winsB, match.winsA, true) == 2)
		local resetAgain = flowFrames(match, a, b, rules.roundEndFrames)
		check("the match ends instead of starting another round", not resetAgain and match.phase == Phase.MatchEnd)
		check("and has its winner", MatchFlow.winner(match.phase, match.winsA, match.winsB, false) == 1)
		flowFrames(match, a, b, 500)
		check("the result screen stays until a rematch", match.phase == Phase.MatchEnd and match.winsA == 2)
		MatchFlow.start(match, Mode.Rounds)
		check("a rematch starts clean", match.phase == Phase.Intro and match.winsA == 0 and match.round == 1)

		local drawn, c, d = inFight()
		drawn.timer = 1
		MatchFlow.step(drawn, c, d)
		flowFrames(drawn, c, d, rules.roundEndFrames)
		check("a drawn round is replayed under the same number", drawn.phase == Phase.Intro and drawn.round == 1)
	end

	-- FightSim cooperates with the flow.
	do
		local a, b = pair(-3, 3)
		b.state = State.KO
		b.hp = 0
		local neutral = FightSim.newInput()
		local options: FightSim.Options = { training = false, rounds = true, combat = true }
		for _ = 1, FightConfig.KoResetFrames + 20 do
			FightSim.step(a, b, neutral, neutral, options)
		end
		check("with a round system a KO does not reset by itself", b.state == State.KO)

		local c, d = pair(-1.5, 1.5)
		local jab = FightSim.newInput()
		jab.jab = true
		local quiet: FightSim.Options = { training = false, rounds = true, combat = false }
		FightSim.step(c, d, jab, neutral, quiet)
		for _ = 1, 40 do
			FightSim.step(c, d, neutral, neutral, quiet)
		end
		check("nothing lands while combat is off", d.hp == FightConfig.MaxHp and d.state == State.Idle)
	end

	-- The bot is a pure function of its arguments.
	do
		local function run(): { string }
			local a, b = pair(-3, 3)
			local inputA, inputB = FightSim.newInput(), FightSim.newInput()
			local log = {}
			for tick = 1, 600 do
				BotBrain.input(tick, a, b, inputA, HARD, 1)
				BotBrain.input(tick, b, a, inputB, MEDIUM, 2)
				FightSim.step(a, b, inputA, inputB, { training = false, rounds = true, combat = true })
				table.insert(log, string.format("%.4f,%.4f,%d,%d,%.0f", a.x, b.x, a.state, b.state, a.hp + b.hp))
			end
			return log
		end
		local first, second = run(), run()
		check("the same states give the same bot inputs", table.concat(first, ";") == table.concat(second, ";"))

		-- Asking out of order changes nothing: there is no hidden state.
		local a, b = pair(-3, 3)
		local into = FightSim.newInput()
		BotBrain.input(500, a, b, into, HARD, 1)
		local reference = `{into.moveX},{into.moveZ},{into.jab},{into.straight},{into.guard},{into.dash}`
		BotBrain.input(7, a, b, into, EASY, 2)
		BotBrain.input(500, a, b, into, HARD, 1)
		check(
			"asking again gives the same answer",
			reference == `{into.moveX},{into.moveZ},{into.jab},{into.straight},{into.guard},{into.dash}`
		)

		check("every level has a name", BotBrain.LevelCount == 3 and BotBrain.Levels[1].name == "EASY")
		BotBrain.input(1, a, b, into, 0, 1)
		BotBrain.input(1, a, b, into, 99, 1)
		BotBrain.input(1, a, b, into, 2.7, 1)
		check("odd levels are clamped instead of failing", true)

		local down = FightSim.newFighter(-3, 0)
		down.state = State.KO
		BotBrain.input(1, down, b, into, HARD, 1)
		check(
			"a knocked-out bot presses nothing",
			not into.jab and not into.straight and not into.guard and not into.dash and into.moveZ == 0
		)
	end

	-- Reading the opponent.
	do
		-- B is mid-straight, six frames before it can hit, with A standing where it will land.
		local function guardsAgainst(level: number, attackFrame: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-2.4, 2.4)
				b.state = State.Attack
				b.moveId = FightConfig.StraightMoveId
				b.stateFrame = attackFrame
				b.aimX = -1
				b.aimZ = 0
				local into = FightSim.newInput()
				BotBrain.input(tick * 37, a, b, into, level, 1)
				if into.guard then
					count += 1
				end
			end
			return count
		end
		check("easy never reads a straight in time", guardsAgainst(EASY, 13) == 0, guardsAgainst(EASY, 13))
		check("hard blocks most straights it can read", guardsAgainst(HARD, 13) >= 40, guardsAgainst(HARD, 13))
		check(
			"hard only guesses at a straight on its first frame",
			guardsAgainst(HARD, 2) <= 24,
			guardsAgainst(HARD, 2)
		)
		check(
			"hard reads more than medium",
			guardsAgainst(HARD, 12) > guardsAgainst(MEDIUM, 12),
			`{guardsAgainst(HARD, 12)} vs {guardsAgainst(MEDIUM, 12)}`
		)

		-- B has thrown a jab and is stuck in its recovery next to A.
		local function punishes(level: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-2.6, 2.6)
				b.state = State.Attack
				b.moveId = FightConfig.JabMoveId
				b.stateFrame = 8 + 3 + 2
				b.aimX = -1
				b.aimZ = 0
				local into = FightSim.newInput()
				BotBrain.input(tick * 53, a, b, into, level, 1)
				if into.jab or into.straight or into.leftKick or into.rightKick then
					count += 1
				end
			end
			return count
		end
		check(
			"hard punishes a recovering opponent far more than easy",
			punishes(HARD) > punishes(EASY) * 2,
			`{punishes(HARD)} vs {punishes(EASY)}`
		)
	end

	-- The guard bars and throws: the stronger levels break throws, grab an opponent who only guards, punish a broken
	-- guard and stop guarding when their own bar is nearly gone.
	do
		local throw = FightConfig.Throw
		-- A grabs B, the bot, from close by; how many of `trials` throws the bot breaks.
		local function breaksThrows(level: number, trials: number): number
			local broken = 0
			for trial = 1, trials do
				local a, b = pair(0, 2.6)
				local both = FightSim.newInput()
				both.jab = true
				both.straight = true
				local inputB = FightSim.newInput()
				local tick = trial * 101 + 7
				local escaped = false
				for frame = 1, 80 do
					tick += 1
					BotBrain.input(tick, b, a, inputB, level, 2)
					FightSim.step(a, b, if frame == 1 then both else FightSim.newInput(), inputB)
					if b.state == State.ThrowBreak then
						escaped = true
						break
					end
				end
				if escaped then
					broken += 1
				end
			end
			return broken
		end
		local easyBreaks, mediumBreaks, hardBreaks =
			breaksThrows(EASY, 40), breaksThrows(MEDIUM, 40), breaksThrows(HARD, 40)
		check("easy never breaks a throw", easyBreaks == 0, easyBreaks)
		check("medium breaks some throws", mediumBreaks >= 6 and mediumBreaks <= 24, mediumBreaks)
		check("hard breaks most throws", hardBreaks >= 16 and hardBreaks > mediumBreaks, hardBreaks)

		-- B only ever guards. Over 20 seconds, how much damage the bot at A deals it (all of it for a knockout) and how
		-- often it throws it, summed over three different starts.
		local function versusTurtle(level: number): (number, number)
			local damage, throws = 0, 0
			for salt = 1, 3 do
				local a, b = pair(-3, 3)
				local inputA = FightSim.newInput()
				local guarding = FightSim.newInput()
				guarding.guard = true
				local wasThrown = false
				for tick = 1, 1200 do
					BotBrain.input(tick + salt * 1000, a, b, inputA, level, 1)
					FightSim.step(a, b, inputA, guarding, { training = false, rounds = true, combat = true })
					local thrown = b.state == State.Thrown
					if thrown and not wasThrown then
						throws += 1
					end
					wasThrown = thrown
					if b.state == State.KO then
						break
					end
				end
				damage += FightConfig.MaxHp - b.hp
			end
			return damage, throws
		end
		local easyDamage = versusTurtle(EASY)
		local mediumDamage = versusTurtle(MEDIUM)
		local hardDamage, hardThrows = versusTurtle(HARD)
		check("hard takes apart an opponent who only guards", hardDamage >= 240, hardDamage)
		check("throwing it among other things", hardThrows >= 3, hardThrows)
		check(
			"each level does more to an opponent who only guards",
			easyDamage < mediumDamage and mediumDamage < hardDamage,
			`{easyDamage} {mediumDamage} {hardDamage}`
		)

		-- B's guard has just broken next to A; how often the bot at A lands an attack on it.
		local function punishesBreak(level: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-2.4, 2.4)
				b.state = State.GuardBreak
				b.stun = FightConfig.Guard.breakFrames
				b.stateFrame = 4
				b.guard = 0
				local into = FightSim.newInput()
				BotBrain.input(tick * 31, a, b, into, level, 1)
				if into.jab or into.straight or into.leftKick or into.rightKick then
					count += 1
				end
			end
			return count
		end
		check(
			"hard punishes a broken guard far more than easy",
			punishesBreak(HARD) >= 40 and punishesBreak(EASY) <= 10,
			`{punishesBreak(HARD)} vs {punishesBreak(EASY)}`
		)

		-- The straight from "Reading the opponent", read in time, with the bot's bar full or too low to block it.
		local function guardsWithBar(level: number, bar: number): number
			local guards = 0
			for tick = 1, 80 do
				local a, b = pair(-2.4, 2.4)
				a.guard = bar
				b.state = State.Attack
				b.moveId = FightConfig.StraightMoveId
				b.stateFrame = 13
				b.aimX = -1
				b.aimZ = 0
				local into = FightSim.newInput()
				BotBrain.input(tick * 37, a, b, into, level, 1)
				if into.guard then
					guards += 1
				end
			end
			return guards
		end
		local fullGuards, lowGuards = guardsWithBar(HARD, FightConfig.Guard.max), guardsWithBar(HARD, 60)
		check(
			"hard takes a hit rather than block with its bar nearly empty",
			fullGuards >= 40 and lowGuards == 0,
			`{fullGuards} -> {lowGuards}`
		)
		check(
			"hard reacts to a throw inside its break window, and easy never does",
			throw.breakWindow > BotBrain.Levels[HARD].reaction + 3
				and BotBrain.Levels[EASY].reaction - 2 >= throw.breakWindow
		)
	end

	-- Playing the neutral game: what the stronger levels do beyond reading a single attack.
	do
		-- B walks toward A from `dist` apart; how often, over 80 different moments, the bot at A throws a punch.
		local function firesAtWalker(level: number, dist: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-dist / 2, dist / 2)
				b.vx = -FightConfig.WalkForwardSpeed
				local into = FightSim.newInput()
				BotBrain.input(tick * 41, a, b, into, level, 1)
				if into.jab or into.straight then
					count += 1
				end
			end
			return count
		end
		check("easy hardly fires at a walker", firesAtWalker(EASY, 5) <= 3, firesAtWalker(EASY, 5))
		check(
			"medium and hard fire at a walker coming into range",
			firesAtWalker(MEDIUM, 5) >= 10 and firesAtWalker(HARD, 5) >= 15,
			`{firesAtWalker(MEDIUM, 5)} and {firesAtWalker(HARD, 5)}`
		)
		check("nothing is thrown at a walker still far off", firesAtWalker(HARD, 9) <= 8, firesAtWalker(HARD, 9))

		-- A is four frames from the end of a hitstun while B is three frames into a jab, right next to it.
		local function guardsOutOfStun(level: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-2.4, 2.4)
				a.state = State.Hitstun
				a.stun = 18
				a.stateFrame = 14
				b.state = State.Attack
				b.moveId = FightConfig.JabMoveId
				b.stateFrame = 3
				b.aimX = -1
				b.aimZ = 0
				local into = FightSim.newInput()
				BotBrain.input(tick * 29, a, b, into, level, 1)
				if into.guard then
					count += 1
				end
			end
			return count
		end
		check("hard comes out of a stun with the guard up", guardsOutOfStun(HARD) >= 35, guardsOutOfStun(HARD))
		check("easy does not", guardsOutOfStun(EASY) <= 3, guardsOutOfStun(EASY))

		-- B has dashed in and is recovering, close to A.
		local function jabsDashRecovery(level: number): number
			local count = 0
			for tick = 1, 80 do
				local a, b = pair(-1.8, 1.8)
				b.state = State.Dash
				b.stateFrame = FightConfig.Dash.startup + FightConfig.Dash.travel + 2
				local into = FightSim.newInput()
				BotBrain.input(tick * 17, a, b, into, level, 1)
				if into.jab then
					count += 1
				end
			end
			return count
		end
		check(
			"hard punishes a dash that ends next to it far more than easy",
			jabsDashRecovery(HARD) >= 30 and jabsDashRecovery(EASY) <= 5,
			`{jabsDashRecovery(HARD)} vs {jabsDashRecovery(EASY)}`
		)
	end

	-- It plays: it closes in, attacks, and stays in the ring.
	do
		local a, b = pair(-3, 3)
		local inputA, inputB = FightSim.newInput(), FightSim.newInput()
		local attacks = 0
		local wasAttacking = false
		local outside = false
		for tick = 1, 1800 do
			BotBrain.input(tick, a, b, inputA, MEDIUM, 1)
			FightSim.dummyInput(tick, b, a, inputB, 0)
			FightSim.step(a, b, inputA, inputB, { training = true, rounds = false, combat = true })
			if a.state == State.Attack and not wasAttacking then
				attacks += 1
			end
			wasAttacking = a.state == State.Attack
			if math.sqrt(a.x * a.x + a.z * a.z) > FightConfig.RingRadius then
				outside = true
			end
		end
		check("the bot attacks an idle opponent", attacks >= 5, attacks)
		check("the bot stays inside the ring", not outside)
	end

	-- The levels are different opponents.
	do
		local mediumOverEasy = winRate(MEDIUM, EASY, 24)
		local hardOverMedium = winRate(HARD, MEDIUM, 24)
		local hardOverEasy = winRate(HARD, EASY, 24)
		check("medium beats easy", mediumOverEasy >= 0.65, mediumOverEasy)
		check("hard beats medium", hardOverMedium >= 0.65, hardOverMedium)
		check(
			"hard beats easy by more than medium does",
			hardOverEasy >= mediumOverEasy - 0.05 and hardOverEasy >= 0.8,
			hardOverEasy
		)
		local mirror = winRate(MEDIUM, MEDIUM, 24)
		check("equal levels are an even fight", mirror >= 0.25 and mirror <= 0.75, mirror)
	end

	-- Mashing one button is the first thing a new player tries; it must not beat the hard bot, and it should beat the
	-- easy one.
	do
		local easy = winRateAgainstMasher(EASY, 24)
		local medium = winRateAgainstMasher(MEDIUM, 24)
		local hard = winRateAgainstMasher(HARD, 24)
		check("easy loses to a jab masher", easy <= 0.25, easy)
		check("hard holds its own against a jab masher", hard >= 0.4, hard)
		check("each level is harder to mash against", easy < medium and medium < hard, `{easy} {medium} {hard}`)
	end

	-- A whole match between two bots finishes with a winner.
	do
		local match = MatchFlow.new()
		local a, b = pair(-3, 3)
		local inputA, inputB = FightSim.newInput(), FightSim.newInput()
		local clear = FightSim.newInput()
		local options: FightSim.Options = { training = false, rounds = true, combat = true }
		MatchFlow.start(match, Mode.Rounds)
		FightSim.reset(a, b)
		local frames = 0
		while match.phase ~= Phase.MatchEnd and frames < 60 * 60 * 8 do
			frames += 1
			options.combat = MatchFlow.canAct(match)
			if options.combat then
				BotBrain.input(match.tick, a, b, inputA, HARD, 1)
				BotBrain.input(match.tick, b, a, inputB, HARD, 2)
			else
				inputA, inputB = clear, clear
			end
			FightSim.step(a, b, inputA, inputB, options)
			if MatchFlow.step(match, a, b) then
				FightSim.reset(a, b)
			end
			if options.combat then
				inputA, inputB = FightSim.newInput(), FightSim.newInput()
			end
		end
		check("two bots finish a match", match.phase == Phase.MatchEnd, frames)
		check(
			"someone reached the target",
			match.winsA == rules.roundsToWin or match.winsB == rules.roundsToWin,
			`{match.winsA}-{match.winsB}`
		)
	end

	return passed, failures
end
