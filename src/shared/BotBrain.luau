--!strict

-- The computer opponent. It is a pure function of the simulation state and a frame counter, with no memory of its own,
-- so the server and every predicting client compute the same inputs from the same state and nothing about the bot has
-- to be replicated or rolled back. "Randomness" is a hash of the frame, so choices are stable for a few frames at a time
-- instead of flickering.
--
-- It plays by what a person could see: another fighter's state and how long it has been in it. A reaction delay keeps it
-- from blocking an attack it has not had time to notice, so quick attacks have to be guessed and slow ones can be read.
-- The three levels differ in reaction time, how much they pressure, how well they punish mistakes and how often they make
-- one themselves. The stronger ones also play the neutral game: they fire at an opponent walking into range, aimed at
-- where it will be, hit one that cannot defend itself, come out of a stun with the guard up and follow a helpless
-- opponent in. Without that a player who just mashes the jab beats every level. They also mind the guard bars: they
-- grab an opponent who hides behind its guard, lean on one whose bar runs low, punish a broken guard, break throws in
-- time, and stop blocking once a block would break their own guard.

local FightConfig = require(script.Parent.FightConfig)
local FightSim = require(script.Parent.FightSim)

export type Level = {
	name: string,
	-- Frames an attack has been running before the bot notices it.
	reaction: number,
	-- Frames between decisions about moving and attacking.
	think: number,
	-- Chance per decision to throw an attack when one reaches.
	aggression: number,
	-- Chance to block an attack it noticed, or to back-dash out of a slow one.
	guardSeen: number,
	dodgeSeen: number,
	-- Chance to interrupt a slow attack with a quicker one.
	counter: number,
	-- Chance per decision to put its guard up on a hunch.
	preGuard: number,
	-- Chance to punish an attack that was blocked or missed.
	punish: number,
	-- Chance an attack is thrown at the wrong moment or distance.
	mistake: number,
	-- Chance per decision to dash to close a gap, and to strafe.
	dash: number,
	strafe: number,
	-- How much of a walking opponent's advance the bot aims ahead of, from 0 (where it stands) to 1 (where it will be
	-- when the attack lands), and how often it fires at an opponent walking into range.
	lead: number,
	snipe: number,
	-- Chance to keep the guard up on a hunch while the opponent is attacking nearby.
	wary: number,
	-- Chance to come out of a stun with the guard already up when the opponent is still next to it, and to keep a
	-- guard that is up while the opponent keeps attacking.
	guardOut: number,
	stick: number,
	-- Chance to hit an opponent that cannot defend itself: just hit into hitstun, or recovering from a dash.
	follow: number,
	-- Chance per decision to grab an opponent hiding behind its guard close by, and to walk in for one.
	grab: number,
	-- Chance to grab back in time when it is caught, once it has noticed (after `reaction` frames).
	breakThrow: number,
	-- Whether it minds the guard bars: it lets its guard down when its own bar is low, and leans on an opponent whose bar
	-- is. 0 never, 1 always.
	guardSense: number,
	-- Relative weights of jab, straight, snap kick and power kick.
	mix: { number },
}

local BotBrain = {}

BotBrain.Levels = {
	{
		name = "EASY",
		reaction = 24,
		think = 32,
		aggression = 0.46,
		guardSeen = 0.3,
		dodgeSeen = 0,
		counter = 0,
		preGuard = 0.08,
		punish = 0.15,
		mistake = 0.22,
		dash = 0.05,
		strafe = 0.2,
		lead = 0,
		snipe = 0,
		wary = 0,
		guardOut = 0,
		stick = 0,
		follow = 0,
		grab = 0.04,
		breakThrow = 0,
		guardSense = 0,
		mix = { 6, 2, 2, 1 },
	},
	{
		name = "MEDIUM",
		reaction = 13,
		think = 26,
		aggression = 0.5,
		guardSeen = 0.6,
		dodgeSeen = 0.15,
		counter = 0.15,
		preGuard = 0.1,
		punish = 0.55,
		mistake = 0.1,
		dash = 0.12,
		strafe = 0.25,
		lead = 0.5,
		snipe = 0.25,
		wary = 0.3,
		guardOut = 0.25,
		stick = 0.2,
		follow = 0.5,
		grab = 0.18,
		breakThrow = 0.35,
		guardSense = 0.5,
		mix = { 4, 3, 2, 2 },
	},
	{
		name = "HARD",
		reaction = 11,
		think = 18,
		aggression = 0.8,
		guardSeen = 0.75,
		dodgeSeen = 0.25,
		counter = 0.25,
		preGuard = 0.25,
		punish = 0.7,
		mistake = 0.08,
		dash = 0.18,
		strafe = 0.3,
		lead = 0.6,
		snipe = 0.35,
		wary = 0.15,
		guardOut = 0.6,
		stick = 0.3,
		follow = 0.6,
		grab = 0.32,
		breakThrow = 0.6,
		guardSense = 1,
		mix = { 4, 3, 2, 3 },
	},
} :: { Level }
BotBrain.LevelCount = #BotBrain.Levels

local State = FightSim.State
local MODULUS = 4294967296
local EDGE_MARGIN = 3.4

-- A repeatable value in [0, 1) for a pair of integers. The multipliers keep every product under 2^53, so the result is
-- identical on every machine.
local function hash(a: number, b: number): number
	local x = (a * 2654435 + b * 40503 + 977) % MODULUS
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = (x * 1664525 + 1013904223) % MODULUS
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 214013 + 2531011) % MODULUS
	x = bit32.bxor(x, bit32.rshift(x, 17))
	return x / MODULUS
end

-- Center-to-center distance at which a move connects, measured along its line.
local function connectDistance(move: FightConfig.MoveData): number
	return move.reach + move.hitRadius + FightConfig.BodyRadius
end

-- The farthest center-to-center distance at which any of a fighter's moves connects.
local function longestReach(stats: FightConfig.Stats): number
	local best = 0
	for _, move in stats.moves do
		best = math.max(best, connectDistance(move))
	end
	return best
end

-- How close the bot likes to stand when poking: just inside its jab, rounded so a stock robot gets the same 4.7 as ever.
local function idealDistance(stats: FightConfig.Stats): number
	return math.floor((connectDistance(stats.moves[FightConfig.JabMoveId]) - 0.1) * 100 + 0.5) / 100
end

-- Steps from pressing the button to the first frame that can hit.
local function hitDelay(move: FightConfig.MoveData): number
	return move.startup + 1
end

-- How far away the opponent will be when `move` lands, if it keeps walking in at `closing` studs per second.
local function aimedDistance(level: Level, dist: number, closing: number, move: FightConfig.MoveData): number
	if closing <= 0 or level.lead <= 0 then
		return dist
	end
	return math.max(dist - closing * level.lead * hitDelay(move) / FightConfig.SimHz, FightConfig.MinSeparation)
end

local function pressMove(into: FightSim.Input, moveId: number)
	if moveId == FightConfig.JabMoveId then
		into.jab = true
	elseif moveId == FightConfig.StraightMoveId then
		into.straight = true
	elseif moveId == FightConfig.SnapKickMoveId then
		into.leftKick = true
	else
		into.rightKick = true
	end
end

local function clear(into: FightSim.Input)
	into.moveX = 0
	into.moveZ = 0
	into.jab = false
	into.straight = false
	into.leftKick = false
	into.rightKick = false
	into.guard = false
	into.dash = false
	into.grab = false
end

-- Picks one of the moves that reaches `dist`, weighted by the level's mix. `roll` is a value in [0, 1). A foe closing
-- in at `closing` studs per second is aimed at where it will be when the move lands, as far as the level leads it.
local function chooseReaching(
	moves: { FightConfig.MoveData },
	level: Level,
	dist: number,
	slack: number,
	roll: number,
	closing: number
): number?
	local total = 0
	for moveId, move in moves do
		if aimedDistance(level, dist, closing, move) <= connectDistance(move) - slack then
			total += level.mix[moveId] or 1
		end
	end
	if total <= 0 then
		return nil
	end
	local pick = roll * total
	for moveId, move in moves do
		if aimedDistance(level, dist, closing, move) <= connectDistance(move) - slack then
			pick -= level.mix[moveId] or 1
			if pick <= 0 then
				return moveId
			end
		end
	end
	return nil
end

-- Fills `into` with what the bot presses this frame. `tick` is the session's frame counter, `levelIndex` picks the
-- difficulty and `salt` keeps two bots from making identical choices.
function BotBrain.input(
	tick: number,
	me: FightSim.Fighter,
	foe: FightSim.Fighter,
	into: FightSim.Input,
	levelIndex: number,
	salt: number
)
	clear(into)
	if me.state == State.KO or foe.state == State.KO then
		return
	end
	local level = BotBrain.Levels[math.clamp(math.floor(levelIndex), 1, BotBrain.LevelCount)]
	local throw = FightConfig.Throw

	-- Caught by a grab: once it has noticed, grab back, if it is quick enough to make the window and sure enough to try.
	if me.state == State.Thrown then
		local seed = tick - me.stateFrame
		local react = level.reaction + math.floor(hash(seed, salt + 53) * 5) - 2
		if me.stateFrame == react and react < throw.breakWindow and hash(seed, salt + 57) < level.breakThrow then
			into.grab = true
		end
		return
	end

	local dx = foe.x - me.x
	local dz = foe.z - me.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local ux = 1
	local uz = 0
	if dist > 1e-4 then
		ux = dx / dist
		uz = dz / dist
	end
	local acting = FightSim.isActionable(me.state)
	local stunned = me.state == State.Hitstun or me.state == State.Blockstun
	-- A button pressed a few frames early is remembered, so the bot may press while its own recovery is nearly over.
	local mineLeft = if stunned then me.stun - me.stateFrame else 0
	local ready = acting or (mineLeft > 0 and mineLeft <= FightConfig.InputBufferFrames - 1)
	local foeFree = FightSim.isActionable(foe.state)
	-- Studs per second the opponent is walking toward the bot; negative while it backs away. The bot's own motion stops
	-- the moment it attacks, so it does not count.
	local closing = -(foe.vx * ux + foe.vz * uz)
	local myMoves = me.stats.moves
	local jab = myMoves[FightConfig.JabMoveId]
	local foeDash = foe.stats.dash
	-- How close the opponent has to be to threaten the bot with something.
	local threatRange = longestReach(foe.stats)
	-- A bot that minds the guard bars stops leaning on its guard once its own bar runs low, and leans on an opponent
	-- whose bar is.
	local guardMax = FightConfig.Guard.max
	local guardLow = me.guard < guardMax * 0.3 and hash(tick // 30, salt + 61) < level.guardSense
	local foeGuardLow = foe.guard < guardMax * 0.45 and level.guardSense > 0

	-- Reading what the opponent is doing.
	if foe.state == State.Attack then
		local move = foe.stats.moves[foe.moveId]
		local f = foe.stateFrame
		local activeEnd = move.startup + move.active
		local seed = tick - f + foe.moveId * 31

		if f <= activeEnd and not foe.hitDone then
			local hx = me.x - (foe.x + foe.aimX * move.reach)
			local hz = me.z - (foe.z + foe.aimZ * move.reach)
			local threatened = math.sqrt(hx * hx + hz * hz) <= move.hitRadius + FightConfig.BodyRadius + 1
			if threatened then
				-- Nobody reacts after exactly the same delay every time.
				local react = level.reaction + math.floor(hash(seed, salt + 3) * 5) - 2
				if f >= react then
					local r = hash(seed, salt)
					-- A block that would empty the bar is worse than the hit, so a bot that minds the bar backs off
					-- instead while there is time, and otherwise takes it.
					local wouldBreak = level.guardSense > 0
						and me.guard <= FightSim.guardDamageFor(move, me.stats) + (move.startup - f + 2)
					if r < level.guardSeen and wouldBreak then
						if move.startup - f >= 5 then
							into.dash = true
							return
						end
					elseif r < level.guardSeen then
						into.guard = true
						return
					elseif r < level.guardSeen + level.dodgeSeen and move.startup - f >= 5 then
						into.dash = true
						return
					end
				end

				-- A quicker attack lands first and interrupts a slow one.
				local theirs = hitDelay(move) - f
				if
					ready
					and hitDelay(jab) < theirs
					and dist <= connectDistance(jab) - 0.3
					and hash(seed, salt + 11) < level.counter
				then
					into.jab = true
					return
				end
			end
		elseif f > activeEnd and hash(seed, salt + 7) < level.punish then
			-- It is recovering, from a miss or from a block. Hit it with the strongest move that lands in time.
			local total = move.startup + move.active + move.recovery
			local window = total - f
			local best: number? = nil
			local bestDamage = 0
			for moveId, candidate in myMoves do
				if
					hitDelay(candidate) <= window
					and dist <= connectDistance(candidate) - 0.4
					and candidate.damage > bestDamage
				then
					best = moveId
					bestDamage = candidate.damage
				end
			end
			if best ~= nil and ready then
				pressMove(into, best)
				return
			end
		end
	end

	local epoch = tick // level.think
	local inEpoch = tick % level.think
	local attackAt = math.floor(hash(epoch, salt + 404) * level.think)
	local foeBusy = foe.state == State.Hitstun or foe.state == State.Blockstun
	local foeGuarding = foe.state == State.Guard or foe.state == State.Blockstun

	-- The opponent cannot defend itself, because it was just hit, its guard broke or it is recovering from a dash: land
	-- the strongest move that arrives before it is back on its feet, or a jab to keep it under pressure.
	if ready and level.follow > 0 then
		local left = 0
		local seed = 0
		if foe.state == State.Hitstun then
			left = foe.stun - foe.stateFrame
			seed = tick - foe.stateFrame
		elseif foe.state == State.GuardBreak then
			left = foe.stun - foe.stateFrame
			seed = tick - foe.stateFrame + 13
		elseif foe.state == State.Dash and foe.stateFrame > foeDash.startup + foeDash.travel then
			left = foeDash.startup + foeDash.travel + foeDash.recovery - foe.stateFrame
			seed = tick - foe.stateFrame + 7
		end
		if left > 0 and hash(seed, salt + 31) < level.follow then
			local best: number? = nil
			local bestDamage = 0
			for moveId, candidate in myMoves do
				if
					mineLeft + hitDelay(candidate) <= left
					and dist <= connectDistance(candidate) - 0.4
					and candidate.damage > bestDamage
				then
					best = moveId
					bestDamage = candidate.damage
				end
			end
			if best == nil and left <= 6 and dist <= connectDistance(jab) - 0.4 then
				best = FightConfig.JabMoveId
			end
			if best ~= nil then
				pressMove(into, best)
				return
			end
		end
	end

	-- An opponent walking into range is hit on its way in. The attack goes out early enough to land where the opponent
	-- is about to be: the jab once that is close, the straight while it is still far.
	if ready and foe.state == State.Idle and closing > 1 and level.snipe > 0 then
		local window = tick // 6
		if hash(window, salt + 41) < level.snipe then
			local straight = myMoves[FightConfig.StraightMoveId]
			if aimedDistance(level, dist, closing, jab) <= connectDistance(jab) - 0.3 then
				into.jab = true
				return
			elseif aimedDistance(level, dist, closing, straight) <= connectDistance(straight) - 0.3 then
				into.straight = true
				return
			end
		end
	end

	-- Keeping the guard up: coming out of a hit or a block with the opponent still on top of it, so the follow-up that
	-- was timed for the gap is blocked, and once it is up, for as long as the opponent keeps attacking. Not with the
	-- bar nearly empty: a broken guard costs more than a hit.
	if dist <= threatRange + 0.6 and not guardLow then
		local hold = 0
		local key = 0
		if stunned and (foe.state == State.Attack or foeFree) then
			hold = level.guardOut
			key = tick - me.stateFrame
		elseif me.state == State.Guard and foe.state == State.Attack then
			hold = level.stick
			key = epoch
		end
		if hold > 0 and hash(key, salt + 909) < hold then
			into.guard = true
			return
		end
	end

	-- Anticipation: when the opponent is free and close, or attacking from close by, sometimes just keep the guard up
	-- for a while.
	local hunch = if foeFree then level.preGuard elseif foe.state == State.Attack then level.wary else 0
	if hunch > 0 and dist <= threatRange + 0.4 and not guardLow then
		if hash(epoch, salt + 303) < hunch then
			into.guard = true
			return
		end
	end

	-- An opponent hiding behind its guard is grabbed once it is close enough.
	if
		ready
		and foe.state == State.Guard
		and dist <= throw.range - 0.25
		and inEpoch == attackAt
		and hash(epoch, salt + 71) < level.grab
	then
		into.grab = true
		return
	end

	-- Attacking. Strikes into a guard are wasted unless its bar is running out, and an opponent being thrown cannot be
	-- hit at all.
	local intoGuard = if foeGuardLow then 1.2 else 0.55
	local chance = level.aggression * (if foeGuarding then intoGuard else 1) * (if foeBusy then 1.3 else 1)
	if ready and inEpoch == attackAt and foe.state ~= State.Thrown and hash(epoch, salt) < chance then
		local moveId: number?
		if hash(epoch, salt + 505) < level.mistake then
			-- A wasted attack: any move, whether or not it reaches.
			moveId = math.floor(hash(epoch, salt + 606) * #myMoves) + 1
		else
			moveId = chooseReaching(myMoves, level, dist, 0.3, hash(epoch, salt + 202), closing)
		end
		if moveId ~= nil then
			pressMove(into, moveId)
			return
		end
	end

	-- Moving: hold a poking distance, drift sideways now and then, and dash across a big gap.
	local pace = hash(epoch, salt + 101)
	local ideal = idealDistance(me.stats)
	local forward = 0
	if dist > ideal + 1.1 then
		forward = if pace < 0.85 then 1 else 0
	elseif dist < ideal - 1.5 then
		forward = if pace < 0.6 then -1 else 0
	elseif dist > ideal + 0.3 then
		forward = if pace < level.aggression then 1 else 0
	end
	-- An opponent that cannot hit back for a moment is followed in, so the next exchange starts on the bot's terms.
	if level.follow > 0 and dist > ideal - 0.9 then
		local helpless = foe.state == State.Hitstun
			or foe.state == State.Blockstun
			or foe.state == State.GuardBreak
			or foe.state == State.Thrown
			or (foe.state == State.Dash and foe.stateFrame > foeDash.startup + foeDash.travel)
		if foe.state == State.Attack then
			local move = foe.stats.moves[foe.moveId]
			helpless = foe.stateFrame > move.startup + move.active
		end
		if helpless then
			forward = 1
		end
	end
	-- An opponent sitting behind its guard just out of reach of a grab is walked in on.
	if foe.state == State.Guard and dist > throw.range - 0.4 and hash(epoch, salt + 73) < level.grab * 2 then
		forward = 1
	end
	local side = 0
	local drift = hash(epoch, salt + 707)
	if drift < level.strafe then
		side = if drift < level.strafe / 2 then 1 else -1
	end

	if dist > 6.8 and forward == 1 and ready and inEpoch == attackAt and hash(epoch, salt + 808) < level.dash then
		into.dash = true
	end

	-- Stay off the ropes: lean toward the middle of the ring.
	local radius = math.sqrt(me.x * me.x + me.z * me.z)
	if radius > FightConfig.RingRadius - EDGE_MARGIN then
		local cx = -me.x / radius
		local cz = -me.z / radius
		local towardFoe = cx * ux + cz * uz
		local toRight = cx * -uz + cz * ux
		if math.abs(towardFoe) > 0.35 then
			forward = if towardFoe > 0 then 1 else -1
		end
		if math.abs(toRight) > 0.35 then
			side = if toRight > 0 then 1 else -1
		end
	end

	into.moveZ = forward
	into.moveX = side
end

return BotBrain
