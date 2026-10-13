--!strict

-- Tuning for the fight spike. Timings are in simulation frames (60 per second).

export type MoveData = {
	-- Shown in the training overlay.
	name: string,
	-- Key of the robot's animation clip in RobotClips.
	clip: string,
	-- The robot joint that strikes: HandL, HandR, FootL or FootR. The robot checks measure its reach.
	striker: string,
	startup: number,
	active: number,
	recovery: number,
	damage: number,
	chip: number,
	-- What it takes off the guard bar when it is blocked (see Guard).
	guard: number,
	reach: number,
	hitRadius: number,
	hitstun: number,
	blockstun: number,
	knockback: number,
	blockPush: number,
	hitstop: number,
}

export type DashData = {
	startup: number,
	travel: number,
	recovery: number,
	speed: number,
}

-- The guard bar, so nobody can hold the guard up forever. It loses `holdDrain` points every frame the guard is held and a
-- move's `guard` points every time one is blocked. Once nothing has been guarded for `regenDelay` frames it fills back
-- up by `regen` points a frame. When it runs out the guard breaks: the fighter is wide open for `breakFrames` frames
-- (the blow that broke it freezes the pair `breakHitstop` frames longer), and the bar starts again at `refill`.
export type GuardData = {
	max: number,
	holdDrain: number,
	regenDelay: number,
	regen: number,
	breakFrames: number,
	breakHitstop: number,
	refill: number,
}

-- The throw, which beats a guard. Pressing both punches together grabs: startup, active and recovery frames like an
-- attack, catching an opponent no farther than `range` (center to center) in front. Any attack beats it, since an
-- opponent who is attacking cannot be caught until the attack is over, and so does a stun: an opponent in hitstun or
-- blockstun cannot be caught either. Once caught, the thrower throws for `hold` frames; on the `slam`th the one thrown
-- hits the canvas for `damage` and slides away at `knockback`, and gets up after `down` frames in all. Grabbing back
-- within `breakWindow` frames of the catch breaks free: both are shoved apart at `breakPush` for `breakFrames` frames.
-- The second punch may come up to `chord` frames after the first, and a jab or straight up to `cancel` frames into its
-- startup still turns into the grab.
export type ThrowData = {
	startup: number,
	active: number,
	recovery: number,
	range: number,
	damage: number,
	hold: number,
	slam: number,
	down: number,
	knockback: number,
	breakWindow: number,
	breakFrames: number,
	breakPush: number,
	catchHitstop: number,
	slamHitstop: number,
	chord: number,
	cancel: number,
}

-- Everything about a fighter that a chassis or a module can change. Each fighter carries one of these, so the same
-- simulation plays every build. The last five values describe what the fighter suffers rather than what it does, and stay
-- at their neutral values unless a build says otherwise.
export type Stats = {
	maxHp: number,
	-- Studs per second.
	walkForward: number,
	walkBack: number,
	strafe: number,
	dash: DashData,
	moves: { MoveData },
	-- Multiplier on the chip damage taken while blocking (0 takes none).
	chipTaken: number,
	-- Multiplier on what the guard bar loses, to blocked moves and to holding the guard up.
	guardTaken: number,
	-- Frames added to the blockstun and the hitstun suffered, and the multiplier on the knockback suffered.
	blockstunTaken: number,
	hitstunTaken: number,
	knockbackTaken: number,
}

local MAX_HP = 100
-- Studs per second. Quick enough that closing a gap is a decision, not a chore.
local WALK_FORWARD_SPEED = 8
local WALK_BACK_SPEED = 5.5
local STRAFE_SPEED = 6.5
local DASH: DashData = {
	startup = 2,
	travel = 8,
	recovery = 7,
	speed = 24,
}

-- Frame advantage is hitstun (or blockstun) minus active + recovery, since the attacker is committed to the move
-- from the first active frame on.
--   Jab: +4 on hit, -1 on block.          Straight: +2 on hit, -9 on block.
--   Snap Kick: +2 on hit, -7 on block.    Power Kick: +3 on hit, -14 on block.
-- The punches reach farthest. The kicks are slower and shorter but hit harder and push the target away.
local MOVES = {
	{
		name = "Jab",
		clip = "Jab",
		striker = "HandL",
		startup = 7,
		active = 3,
		recovery = 11,
		damage = 8,
		chip = 1,
		guard = 70,
		reach = 2.6,
		hitRadius = 1.1,
		hitstun = 18,
		blockstun = 13,
		knockback = 10,
		blockPush = 7,
		hitstop = 5,
	},
	{
		name = "Straight",
		clip = "Straight",
		striker = "HandR",
		startup = 12,
		active = 3,
		recovery = 17,
		damage = 16,
		chip = 2,
		guard = 170,
		reach = 3.3,
		hitRadius = 1.2,
		hitstun = 22,
		blockstun = 11,
		knockback = 16,
		blockPush = 12,
		hitstop = 8,
	},
	{
		name = "Snap Kick",
		clip = "SnapKick",
		striker = "FootL",
		startup = 10,
		active = 3,
		recovery = 15,
		damage = 11,
		chip = 1,
		guard = 130,
		reach = 2.2,
		hitRadius = 1.0,
		hitstun = 20,
		blockstun = 11,
		knockback = 13,
		blockPush = 9,
		hitstop = 6,
	},
	{
		name = "Power Kick",
		clip = "PowerKick",
		striker = "FootR",
		startup = 15,
		active = 4,
		recovery = 22,
		damage = 24,
		chip = 3,
		guard = 260,
		reach = 2.4,
		hitRadius = 1.1,
		hitstun = 29,
		blockstun = 12,
		knockback = 26,
		blockPush = 16,
		hitstop = 12,
	},
} :: { MoveData }

-- A full bar lasts 20 seconds of holding the guard with nothing coming in, or about seven straights or fifteen jabs
-- blocked back to back, and fills back up in about four seconds once the guard comes down. A broken guard is open long
-- enough for any attack to land.
local GUARD: GuardData = {
	max = 1200,
	holdDrain = 1,
	regenDelay = 45,
	regen = 6,
	breakFrames = 60,
	breakHitstop = 10,
	refill = 600,
}

-- Slower than every attack (the jab hits on frame 8, the grab catches from frame 11) and a long whiff, so it only works
-- on a guard or on someone finishing a move. A throw leaves the thrower 18 frames ahead with the other robot still
-- getting up a few studs away.
local THROW: ThrowData = {
	startup = 10,
	active = 2,
	recovery = 26,
	range = 3.3,
	damage = 18,
	hold = 46,
	slam = 28,
	down = 64,
	knockback = 12,
	breakWindow = 18,
	breakFrames = 22,
	breakPush = 14,
	catchHitstop = 5,
	slamHitstop = 9,
	chord = 2,
	cancel = 3,
}

local FightConfig = {
	SimHz = 60,
	RingRadius = 15,
	GroundY = 0.6,
	StartHalfDistance = 3,
	BodyRadius = 1.1,
	MinSeparation = 2.2,
	MaxHp = MAX_HP,
	WalkForwardSpeed = WALK_FORWARD_SPEED,
	WalkBackSpeed = WALK_BACK_SPEED,
	StrafeSpeed = STRAFE_SPEED,
	InputBufferFrames = 6,
	KnockbackDecay = 0.82,
	KoResetFrames = 180,
	-- The knockout blow freezes both fighters this long, which the camera uses for a close-up.
	KoFreezeFrames = 26,
	-- In training, a damaged fighter heals this many frames after returning to neutral.
	TrainingHealDelay = 90,
	-- Positions snap to 1/Quantum studs so client and server states compare exactly.
	Quantum = 1024,
	-- Tag on the ring posts and ropes; the client fades the ones between the camera and the fighters.
	RingFadeTag = "RingFade",
	-- Tags on the venue parts the client animates: the LED ribbon around the barricade and the lights held up in the crowd.
	RibbonTag = "ArenaRibbon",
	CrowdLightTag = "ArenaCrowdLight",
	-- The camera never goes beyond this distance from the ring's center, so it stays in front of the stands.
	CameraMaxRadius = 24.5,
	-- The result card is at most 380 px wide. On a view at least this wide, and this much wider than tall, it sits on the
	-- right and the camera slides the pair to the left, so the winner is not hidden behind it. Phones in landscape
	-- qualify; a narrower view keeps the card centered.
	ResultMinAspect = 1.5,
	ResultMinWidth = 740,
	JabMoveId = 1,
	StraightMoveId = 2,
	SnapKickMoveId = 3,
	PowerKickMoveId = 4,
	Dash = DASH,
	Guard = GUARD,
	Throw = THROW,
	-- Rounds. A match is first to `roundsToWin`; a round ends on a KO or when the clock runs out (more health wins).
	Match = {
		roundsToWin = 2,
		roundSeconds = 60,
		-- Both fighters stand still while the ROUND and FIGHT! banners play.
		introFrames = 110,
		-- The KO or TIME banner and the winner's pose play before the next round starts.
		roundEndFrames = 170,
	},
	Moves = MOVES,
	-- The stats of a fighter with nothing changed: the numbers every chassis starts from.
	BaseStats = {
		maxHp = MAX_HP,
		walkForward = WALK_FORWARD_SPEED,
		walkBack = WALK_BACK_SPEED,
		strafe = STRAFE_SPEED,
		dash = DASH,
		moves = MOVES,
		chipTaken = 1,
		guardTaken = 1,
		blockstunTaken = 0,
		hitstunTaken = 0,
		knockbackTaken = 1,
	} :: Stats,
}

return FightConfig
