--!strict

-- Pure, deterministic 1v1 fight simulation. No Roblox APIs, so it behaves identically on the server and on a
-- predicting client, and can be unit tested without a place.

local FightConfig = require(script.Parent.FightConfig)

export type Fighter = {
	x: number,
	z: number,
	vx: number,
	vz: number,
	hp: number,
	state: number,
	stateFrame: number,
	moveId: number,
	hitDone: boolean,
	hitstop: number,
	stun: number,
	prevJab: boolean,
	prevStraight: boolean,
	prevLeftKick: boolean,
	prevRightKick: boolean,
	prevDash: boolean,
	action: number,
	actionBuffer: number,
	-- Direction the current attack travels. Locked when it starts, so a sidestep can dodge it.
	aimX: number,
	aimZ: number,
	-- Dash direction relative to the opponent: forward and to the right.
	dashFwd: number,
	dashSide: number,
	healDelay: number,
	-- The guard bar (see FightConfig.Guard), and frames left before it starts filling again.
	guard: number,
	guardDelay: number,
	-- Frames since each punch was last pressed (counting stops at AGE_CAP), so both pressed together read as a grab.
	jabAge: number,
	straightAge: number,
	prevGrab: boolean,
	-- What this fighter's chassis and modules change: health, speeds, frame data. Shared by every fighter that has the same
	-- build, and never modified by the simulation.
	stats: FightConfig.Stats,
}

export type Input = {
	-- Sidestep (positive is the fighter's right) and walk toward the opponent (positive is forward).
	moveX: number,
	moveZ: number,
	jab: boolean,
	straight: boolean,
	leftKick: boolean,
	rightKick: boolean,
	guard: boolean,
	dash: boolean,
	-- A grab of its own (the touch controls' GRAB button). Both punches pressed together grab too.
	grab: boolean,
}

export type Options = {
	training: boolean,
	-- A round system (MatchFlow) owns resets, so a KO does not reset the fighters by itself.
	rounds: boolean?,
	-- False between rounds: fighters keep animating but nothing can hit.
	combat: boolean?,
}

local State = {
	Idle = 0,
	Attack = 1,
	Hitstun = 2,
	KO = 3,
	Guard = 4,
	Blockstun = 5,
	Dash = 6,
	-- The guard bar ran out: wide open until the break is over (FightConfig.Guard).
	GuardBreak = 7,
	-- A grab on its way out, timed like an attack.
	Grab = 8,
	-- A grab caught: the one who grabbed throws, the other is thrown and gets up again.
	Throw = 9,
	Thrown = 10,
	-- The one caught grabbed back in time, and both were shoved apart.
	ThrowBreak = 11,
}

local Action = {
	None = 0,
	Jab = 1,
	Straight = 2,
	Dash = 3,
	LeftKick = 4,
	RightKick = 5,
	Grab = 6,
}

-- Which move each attack button starts.
local ATTACK_MOVES: { [number]: number } = {
	[Action.Jab] = FightConfig.JabMoveId,
	[Action.Straight] = FightConfig.StraightMoveId,
	[Action.LeftKick] = FightConfig.SnapKickMoveId,
	[Action.RightKick] = FightConfig.PowerKickMoveId,
}

local DEFAULT_OPTIONS: Options = { training = false }
-- A build can shorten the stun it suffers, but never to nothing.
local MIN_STUN = 6
-- How far back the punch presses are counted; anything older is as good as never.
local AGE_CAP = 30
-- A grab only catches an opponent in front of it: within about 60 degrees of where it reaches.
local GRAB_FACING = 0.5

local FightSim = {}
FightSim.State = State
FightSim.Action = Action
FightSim.AgeCap = AGE_CAP

local function quantize(value: number): number
	return math.floor(value * FightConfig.Quantum + 0.5) / FightConfig.Quantum
end

function FightSim.resetFighter(fighter: Fighter, x: number, z: number)
	fighter.x = x
	fighter.z = z
	fighter.vx = 0
	fighter.vz = 0
	fighter.hp = fighter.stats.maxHp
	fighter.state = State.Idle
	fighter.stateFrame = 0
	fighter.moveId = 0
	fighter.hitDone = false
	fighter.hitstop = 0
	fighter.stun = 0
	fighter.prevJab = false
	fighter.prevStraight = false
	fighter.prevLeftKick = false
	fighter.prevRightKick = false
	fighter.prevDash = false
	fighter.action = Action.None
	fighter.actionBuffer = 0
	fighter.aimX = if x <= 0 then 1 else -1
	fighter.aimZ = 0
	fighter.dashFwd = 0
	fighter.dashSide = 0
	fighter.healDelay = 0
	fighter.guard = FightConfig.Guard.max
	fighter.guardDelay = 0
	fighter.jabAge = AGE_CAP
	fighter.straightAge = AGE_CAP
	fighter.prevGrab = false
end

function FightSim.newFighter(x: number, z: number): Fighter
	local fighter: Fighter = {
		x = x,
		z = z,
		vx = 0,
		vz = 0,
		hp = FightConfig.BaseStats.maxHp,
		state = State.Idle,
		stateFrame = 0,
		moveId = 0,
		hitDone = false,
		hitstop = 0,
		stun = 0,
		prevJab = false,
		prevStraight = false,
		prevLeftKick = false,
		prevRightKick = false,
		prevDash = false,
		action = Action.None,
		actionBuffer = 0,
		aimX = 1,
		aimZ = 0,
		dashFwd = 0,
		dashSide = 0,
		healDelay = 0,
		guard = FightConfig.Guard.max,
		guardDelay = 0,
		jabAge = AGE_CAP,
		straightAge = AGE_CAP,
		prevGrab = false,
		stats = FightConfig.BaseStats,
	}
	return fighter
end

function FightSim.newInput(): Input
	return {
		moveX = 0,
		moveZ = 0,
		jab = false,
		straight = false,
		leftKick = false,
		rightKick = false,
		guard = false,
		dash = false,
		grab = false,
	}
end

-- Turns a movement stick or WASD reading (x right, y up on the screen) into the simulation's axes: sidestep and walk
-- toward the opponent. The camera keeps each player's fighter on the left of the screen facing right, so right is
-- always forward. Up is away from the camera, which is the fighter's left, so it comes out as a negative sidestep.
function FightSim.moveFromStick(stickX: number, stickY: number): (number, number)
	return -stickY, stickX
end

function FightSim.reset(a: Fighter, b: Fighter)
	FightSim.resetFighter(a, -FightConfig.StartHalfDistance, 0)
	FightSim.resetFighter(b, FightConfig.StartHalfDistance, 0)
end

-- True while a fighter can start something new.
function FightSim.isActionable(state: number): boolean
	return state == State.Idle or state == State.Guard
end

-- Unit vector from a to b and the distance between them.
local function direction(a: Fighter, b: Fighter): (number, number, number)
	local dx = b.x - a.x
	local dz = b.z - a.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-4 then
		return 1, 0, 0
	end
	return dx / dist, dz / dist, dist
end

-- Remembers the latest button press for a few frames so inputs a little early still count. Both punches pressed within
-- FightConfig.Throw.chord frames of each other are a grab.
local function registerInput(fighter: Fighter, input: Input)
	local jabPressed = input.jab and not fighter.prevJab
	local straightPressed = input.straight and not fighter.prevStraight
	fighter.jabAge = if jabPressed then 0 else math.min(fighter.jabAge + 1, AGE_CAP)
	fighter.straightAge = if straightPressed then 0 else math.min(fighter.straightAge + 1, AGE_CAP)
	local chord = FightConfig.Throw.chord
	local grabbed = (input.grab and not fighter.prevGrab)
		or (jabPressed and fighter.straightAge <= chord)
		or (straightPressed and fighter.jabAge <= chord)

	local pressed = Action.None
	if input.dash and not fighter.prevDash then
		pressed = Action.Dash
	end
	if jabPressed then
		pressed = Action.Jab
	end
	if straightPressed then
		pressed = Action.Straight
	end
	if input.leftKick and not fighter.prevLeftKick then
		pressed = Action.LeftKick
	end
	if input.rightKick and not fighter.prevRightKick then
		pressed = Action.RightKick
	end
	if grabbed then
		pressed = Action.Grab
	end

	if pressed ~= Action.None then
		fighter.action = pressed
		fighter.actionBuffer = FightConfig.InputBufferFrames
	elseif fighter.actionBuffer > 0 then
		fighter.actionBuffer -= 1
		if fighter.actionBuffer == 0 then
			fighter.action = Action.None
		end
	end

	fighter.prevJab = input.jab
	fighter.prevStraight = input.straight
	fighter.prevLeftKick = input.leftKick
	fighter.prevRightKick = input.rightKick
	fighter.prevDash = input.dash
	fighter.prevGrab = input.grab
end

local function startAttack(fighter: Fighter, moveId: number, dirX: number, dirZ: number)
	fighter.state = State.Attack
	fighter.stateFrame = 0
	fighter.moveId = moveId
	fighter.hitDone = false
	fighter.aimX = dirX
	fighter.aimZ = dirZ
	fighter.vx = 0
	fighter.vz = 0
	fighter.action = Action.None
	fighter.actionBuffer = 0
end

-- Dashes toward the held direction, or backs off when nothing is held.
local function startDash(fighter: Fighter, input: Input)
	local forward = math.clamp(input.moveZ, -1, 1)
	local side = math.clamp(input.moveX, -1, 1)
	local length = math.sqrt(forward * forward + side * side)
	if length < 0.3 then
		forward = -1
		side = 0
	else
		forward /= length
		side /= length
	end
	fighter.state = State.Dash
	fighter.stateFrame = 0
	fighter.moveId = 0
	fighter.dashFwd = forward
	fighter.dashSide = side
	fighter.vx = 0
	fighter.vz = 0
	fighter.action = Action.None
	fighter.actionBuffer = 0
end

-- Reaches out with both hands along the direction the fighter faces, which stays locked like an attack's aim.
local function startGrab(fighter: Fighter, dirX: number, dirZ: number)
	fighter.state = State.Grab
	fighter.stateFrame = 0
	fighter.moveId = 0
	fighter.hitDone = false
	fighter.aimX = dirX
	fighter.aimZ = dirZ
	fighter.vx = 0
	fighter.vz = 0
	fighter.action = Action.None
	fighter.actionBuffer = 0
end

-- The punches a grab's second button can still turn into the grab, early in their startup.
local function isPunch(moveId: number): boolean
	return moveId == FightConfig.JabMoveId or moveId == FightConfig.StraightMoveId
end

-- Leaving a broken guard by any way, back on its feet or knocked out of it, the bar starts again at the refill.
local function endBreak(fighter: Fighter)
	if fighter.state == State.GuardBreak then
		fighter.guard = FightConfig.Guard.refill
		fighter.guardDelay = FightConfig.Guard.regenDelay
	end
end

local function breakGuard(fighter: Fighter)
	fighter.state = State.GuardBreak
	fighter.stateFrame = 0
	fighter.stun = FightConfig.Guard.breakFrames
	fighter.guard = 0
	fighter.moveId = 0
	fighter.action = Action.None
	fighter.actionBuffer = 0
	fighter.vx = 0
	fighter.vz = 0
end

-- Moves the fighter's state machine forward one frame. dirX/dirZ is the direction the fighter is facing.
local function advance(fighter: Fighter, input: Input, dirX: number, dirZ: number)
	if fighter.state == State.KO then
		fighter.stateFrame += 1
		fighter.vx = 0
		fighter.vz = 0
		return
	end

	-- Every state that just runs its course: the stuns, a broken guard, being thrown and a broken throw.
	local state = fighter.state
	if
		state == State.Hitstun
		or state == State.Blockstun
		or state == State.GuardBreak
		or state == State.Thrown
		or state == State.ThrowBreak
	then
		fighter.stateFrame += 1
		if fighter.stateFrame >= fighter.stun then
			endBreak(fighter)
			fighter.state = if input.guard then State.Guard else State.Idle
			fighter.stateFrame = 0
			fighter.vx = 0
			fighter.vz = 0
		else
			fighter.vx *= FightConfig.KnockbackDecay
			fighter.vz *= FightConfig.KnockbackDecay
		end
		return
	end

	if state == State.Throw then
		fighter.stateFrame += 1
		fighter.vx = 0
		fighter.vz = 0
		if fighter.stateFrame >= fighter.stun then
			fighter.state = if input.guard then State.Guard else State.Idle
			fighter.stateFrame = 0
		end
		return
	end

	if state == State.Grab then
		fighter.stateFrame += 1
		fighter.vx = 0
		fighter.vz = 0
		local throw = FightConfig.Throw
		if fighter.stateFrame > throw.startup + throw.active + throw.recovery then
			fighter.state = State.Idle
			fighter.stateFrame = 0
		end
		return
	end

	if state == State.Attack then
		-- The second punch of a grab came a frame or two after the first: the punch that started becomes the grab.
		if
			fighter.action == Action.Grab
			and fighter.stateFrame < FightConfig.Throw.cancel
			and isPunch(fighter.moveId)
		then
			startGrab(fighter, dirX, dirZ)
			return
		end
		fighter.stateFrame += 1
		local move = fighter.stats.moves[fighter.moveId]
		if fighter.stateFrame > move.startup + move.active + move.recovery then
			fighter.state = State.Idle
			fighter.stateFrame = 0
			fighter.moveId = 0
		end
		fighter.vx = 0
		fighter.vz = 0
		return
	end

	if state == State.Dash then
		fighter.stateFrame += 1
		local dash = fighter.stats.dash
		fighter.vx = 0
		fighter.vz = 0
		if fighter.stateFrame > dash.startup and fighter.stateFrame <= dash.startup + dash.travel then
			local rightX = -dirZ
			local rightZ = dirX
			fighter.vx = (dirX * fighter.dashFwd + rightX * fighter.dashSide) * dash.speed
			fighter.vz = (dirZ * fighter.dashFwd + rightZ * fighter.dashSide) * dash.speed
		end
		if fighter.stateFrame > dash.startup + dash.travel + dash.recovery then
			fighter.state = State.Idle
			fighter.stateFrame = 0
		end
		return
	end

	-- Idle or Guard: the fighter can act.
	if fighter.action == Action.Grab then
		startGrab(fighter, dirX, dirZ)
		return
	end
	local attackMove = ATTACK_MOVES[fighter.action]
	if attackMove ~= nil then
		startAttack(fighter, attackMove, dirX, dirZ)
		return
	elseif fighter.action == Action.Dash then
		startDash(fighter, input)
		return
	end

	if input.guard then
		fighter.state = State.Guard
		fighter.vx = 0
		fighter.vz = 0
		return
	end
	fighter.state = State.Idle

	local forward = math.clamp(input.moveZ, -1, 1)
	local side = math.clamp(input.moveX, -1, 1)
	local length = math.sqrt(forward * forward + side * side)
	if length > 1 then
		forward /= length
		side /= length
	end
	local stats = fighter.stats
	local forwardSpeed = if forward >= 0 then stats.walkForward else stats.walkBack
	local rightX = -dirZ
	local rightZ = dirX
	fighter.vx = dirX * forward * forwardSpeed + rightX * side * stats.strafe
	fighter.vz = dirZ * forward * forwardSpeed + rightZ * side * stats.strafe
end

-- The guard bar for one frame: holding the guard drains it (and may break it), a block keeps it from refilling, and
-- otherwise it fills back up once the guard has been down for a while.
local function tickGuard(fighter: Fighter)
	local guard = FightConfig.Guard
	local state = fighter.state
	if state == State.Guard then
		fighter.guardDelay = guard.regenDelay
		fighter.guard -= guard.holdDrain * fighter.stats.guardTaken
		if fighter.guard <= 0 then
			breakGuard(fighter)
		end
	elseif state == State.Blockstun then
		fighter.guardDelay = guard.regenDelay
	elseif state ~= State.GuardBreak and fighter.guard < guard.max then
		if fighter.guardDelay > 0 then
			fighter.guardDelay -= 1
		else
			fighter.guard = math.min(fighter.guard + guard.regen, guard.max)
		end
	end
end

-- Returns the move if the attacker's active hitbox overlaps the defender this frame. A throw in progress cannot be hit.
local function connects(attacker: Fighter, defender: Fighter): FightConfig.MoveData?
	if attacker.state ~= State.Attack or attacker.hitDone or defender.state == State.KO then
		return nil
	end
	if defender.state == State.Thrown or defender.state == State.Throw then
		return nil
	end
	local move = attacker.stats.moves[attacker.moveId]
	if attacker.stateFrame <= move.startup or attacker.stateFrame > move.startup + move.active then
		return nil
	end
	local offsetX = defender.x - (attacker.x + attacker.aimX * move.reach)
	local offsetZ = defender.z - (attacker.z + attacker.aimZ * move.reach)
	local radius = move.hitRadius + FightConfig.BodyRadius
	if offsetX * offsetX + offsetZ * offsetZ > radius * radius then
		return nil
	end
	return move
end

-- What a move does to a defender with the given stats: the hitstun and blockstun it suffers and the chip damage it takes.
-- Shared with the frame data, so the table and the simulation cannot disagree.
function FightSim.hitstunFor(move: FightConfig.MoveData, suffered: FightConfig.Stats): number
	return math.max(move.hitstun + suffered.hitstunTaken, MIN_STUN)
end

function FightSim.blockstunFor(move: FightConfig.MoveData, suffered: FightConfig.Stats): number
	return math.max(move.blockstun + suffered.blockstunTaken, MIN_STUN)
end

function FightSim.chipFor(move: FightConfig.MoveData, suffered: FightConfig.Stats): number
	return math.floor(move.chip * suffered.chipTaken + 0.5)
end

-- What blocking a move takes off the guard bar of a defender with the given stats.
function FightSim.guardDamageFor(move: FightConfig.MoveData, suffered: FightConfig.Stats): number
	return move.guard * suffered.guardTaken
end

local function applyHit(attacker: Fighter, defender: Fighter, move: FightConfig.MoveData, training: boolean)
	local blocked = defender.state == State.Guard or defender.state == State.Blockstun
	endBreak(defender)
	attacker.hitDone = true
	attacker.hitstop = math.max(attacker.hitstop, move.hitstop)
	defender.hitstop = math.max(defender.hitstop, move.hitstop)
	defender.stateFrame = 0
	defender.moveId = 0
	defender.action = Action.None
	defender.actionBuffer = 0
	defender.healDelay = FightConfig.TrainingHealDelay

	-- Chip damage and training hits never finish a fighter off.
	local floorHp = if blocked or training then 1 else 0
	local suffered = defender.stats
	local damage = if blocked then FightSim.chipFor(move, suffered) else move.damage
	defender.hp = math.max(defender.hp - damage, floorHp)

	if blocked then
		defender.guard -= FightSim.guardDamageFor(move, suffered)
		defender.guardDelay = FightConfig.Guard.regenDelay
		if defender.guard <= 0 then
			-- The block that empties the bar breaks the guard, and the moment hangs a little longer.
			breakGuard(defender)
			local freeze = move.hitstop + FightConfig.Guard.breakHitstop
			attacker.hitstop = math.max(attacker.hitstop, freeze)
			defender.hitstop = math.max(defender.hitstop, freeze)
		else
			defender.state = State.Blockstun
			defender.stun = FightSim.blockstunFor(move, suffered)
		end
		defender.vx = attacker.aimX * move.blockPush * suffered.knockbackTaken
		defender.vz = attacker.aimZ * move.blockPush * suffered.knockbackTaken
	elseif defender.hp <= 0 then
		defender.state = State.KO
		defender.vx = 0
		defender.vz = 0
		-- The knockout blow hangs in the air for a moment.
		attacker.hitstop = math.max(attacker.hitstop, FightConfig.KoFreezeFrames)
		defender.hitstop = math.max(defender.hitstop, FightConfig.KoFreezeFrames)
	else
		defender.state = State.Hitstun
		defender.stun = FightSim.hitstunFor(move, suffered)
		defender.vx = attacker.aimX * move.knockback * suffered.knockbackTaken
		defender.vz = attacker.aimZ * move.knockback * suffered.knockbackTaken
	end
end

-- Whether a fighter can be caught by a grab: standing, guarding, dashing, wide open, grabbing itself, or finishing an
-- attack. An attack still on its way beats the grab, and a stun protects whoever is in it.
local function throwable(fighter: Fighter): boolean
	local state = fighter.state
	if
		state == State.Idle
		or state == State.Guard
		or state == State.Dash
		or state == State.GuardBreak
		or state == State.Grab
	then
		return true
	end
	if state == State.Attack then
		local move = fighter.stats.moves[fighter.moveId]
		return move ~= nil and fighter.stateFrame > move.startup + move.active
	end
	return false
end

-- Whether the attacker's grab catches the defender this frame: in its active frames, close enough, and in front of it.
local function catches(attacker: Fighter, defender: Fighter): boolean
	local throw = FightConfig.Throw
	if attacker.state ~= State.Grab or attacker.stateFrame <= throw.startup then
		return false
	end
	if attacker.stateFrame > throw.startup + throw.active or not throwable(defender) then
		return false
	end
	local dx = defender.x - attacker.x
	local dz = defender.z - attacker.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > throw.range then
		return false
	end
	return distance < 1e-4 or (dx * attacker.aimX + dz * attacker.aimZ) / distance >= GRAB_FACING
end

local function holdStill(fighter: Fighter, state: number, frames: number)
	endBreak(fighter)
	fighter.state = state
	fighter.stateFrame = 0
	fighter.stun = frames
	fighter.moveId = 0
	fighter.hitDone = false
	fighter.vx = 0
	fighter.vz = 0
	fighter.action = Action.None
	fighter.actionBuffer = 0
end

local function applyCatch(thrower: Fighter, thrown: Fighter)
	local throw = FightConfig.Throw
	holdStill(thrower, State.Throw, throw.hold)
	holdStill(thrown, State.Thrown, throw.down)
	thrown.healDelay = FightConfig.TrainingHealDelay
	thrower.hitstop = math.max(thrower.hitstop, throw.catchHitstop)
	thrown.hitstop = math.max(thrown.hitstop, throw.catchHitstop)
end

-- Both are shoved apart, out of a throw broken in time or out of two grabs that caught each other.
local function breakThrow(a: Fighter, b: Fighter)
	local throw = FightConfig.Throw
	local dirX, dirZ = direction(a, b)
	holdStill(a, State.ThrowBreak, throw.breakFrames)
	holdStill(b, State.ThrowBreak, throw.breakFrames)
	a.vx = -dirX * throw.breakPush
	a.vz = -dirZ * throw.breakPush
	b.vx = dirX * throw.breakPush
	b.vz = dirZ * throw.breakPush
	a.hitstop = math.max(a.hitstop, throw.catchHitstop)
	b.hitstop = math.max(b.hitstop, throw.catchHitstop)
end

-- A throw under way: the one thrown may still break free, and on the slam frame it hits the canvas. The damage only
-- counts while the fight is on, and like any hit in training it never knocks anyone out.
local function progressThrow(thrower: Fighter, thrown: Fighter, combat: boolean, training: boolean)
	if thrower.state ~= State.Throw or thrown.state ~= State.Thrown or thrower.hitDone then
		return
	end
	local throw = FightConfig.Throw
	if thrown.stateFrame <= throw.breakWindow and thrown.action == Action.Grab then
		breakThrow(thrower, thrown)
		return
	end
	if thrower.stateFrame < throw.slam then
		return
	end
	thrower.hitDone = true
	thrower.hitstop = math.max(thrower.hitstop, throw.slamHitstop)
	thrown.hitstop = math.max(thrown.hitstop, throw.slamHitstop)
	if not combat then
		return
	end
	thrown.hp = math.max(thrown.hp - throw.damage, if training then 1 else 0)
	thrown.healDelay = FightConfig.TrainingHealDelay
	if thrown.hp <= 0 then
		thrown.state = State.KO
		thrown.stateFrame = 0
		thrower.hitstop = math.max(thrower.hitstop, FightConfig.KoFreezeFrames)
		thrown.hitstop = math.max(thrown.hitstop, FightConfig.KoFreezeFrames)
		return
	end
	local dirX, dirZ = direction(thrower, thrown)
	local knockback = throw.knockback * thrown.stats.knockbackTaken
	thrown.vx = dirX * knockback
	thrown.vz = dirZ * knockback
end

local function clampToRing(fighter: Fighter)
	-- The margin keeps quantization rounding from nudging a fighter back outside the ring.
	local maxRadius = FightConfig.RingRadius - FightConfig.BodyRadius - 2 / FightConfig.Quantum
	local radius = math.sqrt(fighter.x * fighter.x + fighter.z * fighter.z)
	if radius > maxRadius then
		local scale = maxRadius / radius
		fighter.x *= scale
		fighter.z *= scale
	end
end

local function integrate(a: Fighter, b: Fighter)
	local dt = 1 / FightConfig.SimHz
	a.x += a.vx * dt
	a.z += a.vz * dt
	b.x += b.vx * dt
	b.z += b.vz * dt

	local dirX, dirZ, dist = direction(a, b)
	if dist < FightConfig.MinSeparation then
		local push = (FightConfig.MinSeparation - dist) / 2
		a.x -= dirX * push
		a.z -= dirZ * push
		b.x += dirX * push
		b.z += dirZ * push
	end

	clampToRing(a)
	clampToRing(b)
	a.x = quantize(a.x)
	a.z = quantize(a.z)
	b.x = quantize(b.x)
	b.z = quantize(b.z)
end

local function healInTraining(fighter: Fighter)
	if fighter.hp >= fighter.stats.maxHp then
		return
	end
	if FightSim.isActionable(fighter.state) then
		fighter.healDelay -= 1
		if fighter.healDelay <= 0 then
			fighter.hp = fighter.stats.maxHp
		end
	else
		fighter.healDelay = FightConfig.TrainingHealDelay
	end
end

-- Advances both fighters by one simulation frame. In training nobody is knocked out and damage heals back.
function FightSim.step(a: Fighter, b: Fighter, inputA: Input, inputB: Input, options: Options?)
	local settings = options or DEFAULT_OPTIONS
	local training = settings.training
	local dirX, dirZ = direction(a, b)

	registerInput(a, inputA)
	registerInput(b, inputB)

	-- Hitstop freezes both fighters so impacts read as heavy.
	if a.hitstop > 0 or b.hitstop > 0 then
		a.hitstop = math.max(a.hitstop - 1, 0)
		b.hitstop = math.max(b.hitstop - 1, 0)
		return
	end

	advance(a, inputA, dirX, dirZ)
	advance(b, inputB, -dirX, -dirZ)
	tickGuard(a)
	tickGuard(b)

	-- Resolve both attackers against the pre-hit states so trades are symmetric. A strike beats a grab: whoever is hit
	-- this frame catches nothing, and two grabs that catch each other cancel out.
	local combat = settings.combat ~= false
	if combat then
		local moveA = connects(a, b)
		local moveB = connects(b, a)
		local catchA = moveB == nil and catches(a, b)
		local catchB = moveA == nil and catches(b, a)
		if moveA ~= nil then
			applyHit(a, b, moveA, training)
		end
		if moveB ~= nil then
			applyHit(b, a, moveB, training)
		end
		if catchA and catchB then
			breakThrow(a, b)
		elseif catchA then
			applyCatch(a, b)
		elseif catchB then
			applyCatch(b, a)
		end
	end
	progressThrow(a, b, combat, training)
	progressThrow(b, a, combat, training)

	integrate(a, b)

	if training then
		healInTraining(a)
		healInTraining(b)
		return
	end

	if settings.rounds == true then
		return
	end

	local aDone = a.state == State.KO and a.stateFrame >= FightConfig.KoResetFrames
	local bDone = b.state == State.KO and b.stateFrame >= FightConfig.KoResetFrames
	if aDone or bDone then
		FightSim.reset(a, b)
	end
end

-- Walks toward or away from the foe to hold a distance.
local function holdSpacing(me: Fighter, foe: Fighter, target: number): number
	local dx = foe.x - me.x
	local dz = foe.z - me.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > target + 0.5 then
		return 1
	elseif dist < target - 0.5 then
		return -1
	end
	return 0
end

-- Scripted opponent. Modes: 0 idle, 1 guard, 2 jab loop, 3 straight loop, 4 mixed, 5 snap kick loop, 6 power kick
-- loop, 7 grab loop. Depends only on the frame number and fighter state, so the client and server compute the same
-- inputs.
function FightSim.dummyInput(frame: number, me: Fighter, foe: Fighter, into: Input, mode: number)
	into.moveX = 0
	into.moveZ = 0
	into.jab = false
	into.straight = false
	into.leftKick = false
	into.rightKick = false
	into.guard = false
	into.dash = false
	into.grab = false

	local segment = mode
	if mode == 4 then
		segment = 10 + (frame // 90) % 6
	end

	if segment == 1 or segment == 10 then
		into.guard = true
	elseif segment == 2 or segment == 11 then
		into.moveZ = holdSpacing(me, foe, 3.8)
		into.jab = frame % 60 == 30
	elseif segment == 3 or segment == 12 then
		into.moveZ = holdSpacing(me, foe, 4.4)
		into.straight = frame % 90 == 45
	elseif segment == 13 then
		into.moveZ = holdSpacing(me, foe, 3.8)
		into.dash = frame % 45 == 10
		into.jab = frame % 45 == 30
	elseif segment == 5 or segment == 14 then
		into.moveZ = holdSpacing(me, foe, 3.4)
		into.leftKick = frame % 70 == 35
	elseif segment == 6 or segment == 15 then
		into.moveZ = holdSpacing(me, foe, 3.9)
		into.rightKick = frame % 100 == 50
	elseif segment == 7 then
		into.moveZ = holdSpacing(me, foe, 2.6)
		into.grab = frame % 90 == 45
	end
end

-- Phase name and 0-1 progress through it while attacking, for animation.
function FightSim.attackPhase(fighter: Fighter): (string?, number)
	if fighter.state ~= State.Attack then
		return nil, 0
	end
	local move = fighter.stats.moves[fighter.moveId]
	local frame = fighter.stateFrame
	if frame <= move.startup then
		return "startup", frame / move.startup
	elseif frame <= move.startup + move.active then
		return "active", (frame - move.startup) / move.active
	end
	return "recovery", (frame - move.startup - move.active) / move.recovery
end

-- The same for a grab on its way out.
function FightSim.grabPhase(fighter: Fighter): (string?, number)
	if fighter.state ~= State.Grab then
		return nil, 0
	end
	local throw = FightConfig.Throw
	local frame = fighter.stateFrame
	if frame <= throw.startup then
		return "startup", frame / throw.startup
	elseif frame <= throw.startup + throw.active then
		return "active", (frame - throw.startup) / throw.active
	end
	return "recovery", (frame - throw.startup - throw.active) / throw.recovery
end

return FightSim
