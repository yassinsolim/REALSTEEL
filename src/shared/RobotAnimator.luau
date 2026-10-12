--!strict

-- Turns a fighter's simulation state into a robot pose. Attack poses are keyed by the move's own startup, active and
-- recovery phases, so animation timing follows the frame data automatically. Nothing here feeds back into the
-- simulation; it only decides how the robot looks.

local FightConfig = require(script.Parent.FightConfig)
local FightSim = require(script.Parent.FightSim)
local RobotSkeleton = require(script.Parent.RobotSkeleton)

export type Animator = {
	rig: RobotSkeleton.Rig,
	clips: { [string]: RobotSkeleton.Clip },
	-- What is playing, for tests and debugging: Idle, Walk, Guard, a move's clip, HitLight, HitHeavy, Block, Dash, Ko or
	-- an emote.
	clipKey: string,
	pose: RobotSkeleton.Pose,
	from: RobotSkeleton.Pose,
	target: RobotSkeleton.Pose,
	scratch: RobotSkeleton.Pose,
	blendTime: number,
	blendDuration: number,
	walkPhase: number,
	idleTime: number,
}

local RobotAnimator = {}

-- Distance covered per full walk cycle (two steps), in studs.
local STRIDE = 3.4
local WALK_SPEED_MIN = 0.4
-- A hit that stuns at least this long reacts as a heavy one: everything but a jab.
local HEAVY_STUN = 20
local PHASE_INDEX = { startup = 0, active = 1, recovery = 2 }

-- Seconds to crossfade from the previous pose when a clip starts. Hits snap in so the impact reads immediately.
local BLEND = {
	Idle = 0.14,
	Walk = 0.1,
	Guard = 0.08,
	HitLight = 0.03,
	HitHeavy = 0.03,
	Block = 0.03,
	Ko = 0.04,
	Dash = 0.05,
	Attack = 0.05,
	Intro = 0.25,
	Victory = 0.18,
	Slump = 0.4,
}

local DASH_CLIPS = { "DashF", "DashB", "DashL", "DashR" }
local WALK_CLIPS = { "WalkF", "WalkB", "WalkL", "WalkR" }

function RobotAnimator.new(rig: RobotSkeleton.Rig, clips: { [string]: RobotSkeleton.Clip }): Animator
	return {
		rig = rig,
		clips = clips,
		clipKey = "Idle",
		pose = RobotSkeleton.newPose(rig),
		from = RobotSkeleton.newPose(rig),
		target = RobotSkeleton.newPose(rig),
		scratch = RobotSkeleton.newPose(rig),
		blendTime = 0,
		blendDuration = 0,
		walkPhase = 0,
		idleTime = 0,
	}
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Four directional clips blended by how much of the movement points that way. weights: forward, back, left, right.
local function sampleDirectional(self: Animator, names: { string }, weights: { number }, u: number)
	RobotSkeleton.clear(self.target)
	local total = weights[1] + weights[2] + weights[3] + weights[4]
	if total < 1e-5 then
		RobotSkeleton.copy(self.clips.Idle.keys[1].pose, self.target)
		return
	end
	for index, name in names do
		if weights[index] > 0 then
			RobotSkeleton.sample(self.clips[name], u, self.scratch)
			RobotSkeleton.accumulate(self.target, self.scratch, weights[index] / total)
		end
	end
end

local function directionWeights(forward: number, side: number): { number }
	return { math.max(forward, 0), math.max(-forward, 0), math.max(-side, 0), math.max(side, 0) }
end

-- Poses the robot for one render frame and returns the extra yaw (radians) to turn the whole robot toward the aim an
-- attack locked in. facingX/facingZ is the unit direction the fighter faces, toward the opponent. `emote` names a clip
-- (Intro, Victory or Slump) to play while the fighter is standing still and free; moving or fighting overrides it.
function RobotAnimator.update(
	self: Animator,
	fighter: FightSim.Fighter,
	facingX: number,
	facingZ: number,
	dt: number,
	emote: string?
): (RobotSkeleton.Pose, number)
	local rightX = -facingZ
	local rightZ = facingX
	local state = fighter.state
	local key = "Idle"
	local aimYaw = 0

	if state == FightSim.State.KO then
		key = "Ko"
		RobotSkeleton.sample(self.clips.Ko, fighter.stateFrame / FightConfig.SimHz, self.target)
	elseif state == FightSim.State.Hitstun then
		key = if fighter.stun >= HEAVY_STUN then "HitHeavy" else "HitLight"
		RobotSkeleton.sample(self.clips[key], fighter.stateFrame / math.max(fighter.stun, 1), self.target)
	elseif state == FightSim.State.Blockstun then
		key = "Block"
		RobotSkeleton.sample(self.clips.Block, fighter.stateFrame / math.max(fighter.stun, 1), self.target)
	elseif state == FightSim.State.Guard then
		key = "Guard"
		RobotSkeleton.sample(self.clips.Guard, 0, self.target)
	elseif state == FightSim.State.Dash then
		key = "Dash"
		local dash = fighter.stats.dash
		local u = fighter.stateFrame / (dash.startup + dash.travel + dash.recovery)
		sampleDirectional(self, DASH_CLIPS, directionWeights(fighter.dashFwd, fighter.dashSide), u)
	elseif state == FightSim.State.Attack and fighter.stats.moves[fighter.moveId] ~= nil then
		local move = fighter.stats.moves[fighter.moveId]
		key = move.clip
		local phase, progress = FightSim.attackPhase(fighter)
		local u = (PHASE_INDEX[phase :: string] or 0) + progress
		RobotSkeleton.sample(self.clips[key] or self.clips.Jab, u, self.target)

		-- The punch follows the aim locked when it started: turn toward it as the move builds, back out as it recovers.
		local aimForward = fighter.aimX * facingX + fighter.aimZ * facingZ
		local aimRight = fighter.aimX * rightX + fighter.aimZ * rightZ
		local weight = if u < 1 then smooth(u) elseif u <= 2 then 1 else 1 - smooth(u - 2)
		aimYaw = math.atan2(-aimRight, aimForward) * weight
	else
		local forward = fighter.vx * facingX + fighter.vz * facingZ
		local side = fighter.vx * rightX + fighter.vz * rightZ
		local speed = math.sqrt(forward * forward + side * side)
		if speed > WALK_SPEED_MIN then
			key = "Walk"
			self.walkPhase = (self.walkPhase + speed * dt / STRIDE) % 1
			sampleDirectional(self, WALK_CLIPS, directionWeights(forward, side), self.walkPhase)
		elseif emote ~= nil and self.clips[emote] ~= nil then
			key = emote
			self.idleTime += dt
			local clip = self.clips[emote]
			RobotSkeleton.sample(clip, self.idleTime / clip.period, self.target)
		else
			self.idleTime += dt
			local clip = self.clips.Idle
			RobotSkeleton.sample(clip, self.idleTime / clip.period, self.target)
		end
	end

	if key ~= self.clipKey then
		-- Walk and idle share a stance, so only restart the fade when the kind of motion changes.
		RobotSkeleton.copy(self.pose, self.from)
		self.blendTime = 0
		self.blendDuration = BLEND[key] or BLEND.Attack
		self.clipKey = key
	end

	if self.blendTime < self.blendDuration then
		self.blendTime += dt
		RobotSkeleton.lerp(self.from, self.target, smooth(math.min(self.blendTime / self.blendDuration, 1)), self.pose)
	else
		RobotSkeleton.copy(self.target, self.pose)
	end
	return self.pose, aimYaw
end

return RobotAnimator
