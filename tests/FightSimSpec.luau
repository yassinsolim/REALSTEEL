--!strict

-- Headless checks for the pure fight simulation and frame data. Run from Studio's command bar or the Studio MCP:
--   local passed, failures = require(game.ReplicatedStorage.Tests.FightSimSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FightSim = require(ReplicatedStorage.Shared.FightSim)
local FrameData = require(ReplicatedStorage.Shared.FrameData)
local Loadout = require(ReplicatedStorage.Shared.Loadout)

local State = FightSim.State
local jab = FightConfig.Moves[FightConfig.JabMoveId]
local straight = FightConfig.Moves[FightConfig.StraightMoveId]
local snapKick = FightConfig.Moves[FightConfig.SnapKickMoveId]
local powerKick = FightConfig.Moves[FightConfig.PowerKickMoveId]
local dash = FightConfig.Dash

type InputSpec = {
	moveX: number?,
	moveZ: number?,
	jab: boolean?,
	straight: boolean?,
	leftKick: boolean?,
	rightKick: boolean?,
	guard: boolean?,
	dash: boolean?,
	grab: boolean?,
}

local function input(spec: InputSpec?): FightSim.Input
	local given: InputSpec = spec or {}
	return {
		moveX = given.moveX or 0,
		moveZ = given.moveZ or 0,
		jab = given.jab or false,
		straight = given.straight or false,
		leftKick = given.leftKick or false,
		rightKick = given.rightKick or false,
		guard = given.guard or false,
		dash = given.dash or false,
		grab = given.grab or false,
	}
end

local neutral = input()

local function pair(ax: number, bx: number): (FightSim.Fighter, FightSim.Fighter)
	return FightSim.newFighter(ax, 0), FightSim.newFighter(bx, 0)
end

local function stepMany(
	a: FightSim.Fighter,
	b: FightSim.Fighter,
	frames: number,
	inputA: FightSim.Input?,
	inputB: FightSim.Input?,
	options: FightSim.Options?
)
	for _ = 1, frames do
		FightSim.step(a, b, inputA or neutral, inputB or neutral, options)
	end
end

local function sameFighter(a: FightSim.Fighter, b: FightSim.Fighter): boolean
	return a.x == b.x
		and a.z == b.z
		and a.vx == b.vx
		and a.vz == b.vz
		and a.hp == b.hp
		and a.state == b.state
		and a.stateFrame == b.stateFrame
		and a.moveId == b.moveId
		and a.hitDone == b.hitDone
		and a.hitstop == b.hitstop
		and a.stun == b.stun
		and a.prevJab == b.prevJab
		and a.prevStraight == b.prevStraight
		and a.prevLeftKick == b.prevLeftKick
		and a.prevRightKick == b.prevRightKick
		and a.prevDash == b.prevDash
		and a.action == b.action
		and a.actionBuffer == b.actionBuffer
		and a.aimX == b.aimX
		and a.aimZ == b.aimZ
		and a.dashFwd == b.dashFwd
		and a.dashSide == b.dashSide
		and a.healDelay == b.healDelay
		and a.guard == b.guard
		and a.guardDelay == b.guardDelay
		and a.jabAge == b.jabAge
		and a.straightAge == b.straightAge
		and a.prevGrab == b.prevGrab
end

-- Plays an exchange where A attacks with the given button and B reacts, recording history to measure the advantage.
local function exchange(
	attackInput: FightSim.Input,
	defenderInput: FightSim.Input,
	defenderX: number
): FrameData.Exchange?
	local history = FrameData.newHistory(180)
	local a, b = pair(0, defenderX)
	local frame = 0
	for step = 1, 120 do
		frame += 1
		FightSim.step(a, b, if step == 1 then attackInput else neutral, defenderInput)
		FrameData.record(history, frame, a, b)
	end
	return FrameData.lastExchange(history)
end

local function attackTimeline(press: FightSim.Input, move: FightConfig.MoveData): (number?, number?, number?)
	local a, b = pair(-6, 6)
	FightSim.step(a, b, press, neutral)
	local firstActive, lastActive, idleAt = nil, nil, nil
	for frame = 1, move.startup + move.active + move.recovery + 5 do
		FightSim.step(a, b, neutral, neutral)
		local phase = FightSim.attackPhase(a)
		if phase == "active" then
			firstActive = firstActive or frame
			lastActive = frame
		elseif phase == nil and idleAt == nil then
			idleAt = frame
		end
	end
	return firstActive, lastActive, idleAt
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

	-- Controls: the stick reads like the screen, and each attack button starts its own move.
	do
		local function stickWalk(x: number, y: number): FightSim.Fighter
			local a, b = pair(-6, 6)
			local side, forward = FightSim.moveFromStick(x, y)
			stepMany(a, b, 30, input({ moveX = side, moveZ = forward }), neutral)
			return a
		end
		local side, forward = FightSim.moveFromStick(1, 0)
		check("stick right reads as forward", side == 0 and forward == 1)
		side, forward = FightSim.moveFromStick(-1, 0)
		check("stick left reads as back", side == 0 and forward == -1)
		side, forward = FightSim.moveFromStick(0, 1)
		check("stick up reads as a sidestep to the left", side == -1 and forward == 0)
		side, forward = FightSim.moveFromStick(0, -1)
		check("stick down reads as a sidestep to the right", side == 1 and forward == 0)

		local toward = stickWalk(1, 0)
		check("stick right walks toward the opponent", toward.x > -6 + 2.5 and math.abs(toward.z) < 1e-3, toward.x)
		local away = stickWalk(-1, 0)
		check("stick left backs away", away.x < -6 - 1.5 and math.abs(away.z) < 1e-3, away.x)
		-- The camera sits on the fighter's right, at +Z when facing +X, so up is away from it.
		local up = stickWalk(0, 1)
		check("stick up sidesteps away from the camera", up.z < -2 and math.abs(up.x - -6) < 0.5, up.z)
		local down = stickWalk(0, -1)
		check("stick down sidesteps toward the camera", down.z > 2 and math.abs(down.x - -6) < 0.5, down.z)

		type ButtonCase = { name: string, press: InputSpec, moveId: number }
		local cases: { ButtonCase } = {
			{ name = "jab", press = { jab = true }, moveId = FightConfig.JabMoveId },
			{ name = "straight", press = { straight = true }, moveId = FightConfig.StraightMoveId },
			{ name = "left kick", press = { leftKick = true }, moveId = FightConfig.SnapKickMoveId },
			{ name = "right kick", press = { rightKick = true }, moveId = FightConfig.PowerKickMoveId },
		}
		for _, case in cases do
			local a, b = pair(-6, 6)
			FightSim.step(a, b, input(case.press), neutral)
			check(`{case.name} button starts its move`, a.state == State.Attack and a.moveId == case.moveId, a.moveId)
		end
	end

	-- Frame data timelines.
	do
		local firstActive, lastActive, idleAt = attackTimeline(input({ jab = true }), jab)
		check("jab startup frames", firstActive == jab.startup + 1, firstActive)
		check("jab active frames", lastActive == jab.startup + jab.active, lastActive)
		check("jab returns to idle", idleAt == jab.startup + jab.active + jab.recovery + 1, idleAt)
		local a, b = pair(-6, 6)
		FightSim.step(a, b, input({ jab = true }), neutral)
		check(
			"attack starts on press",
			a.state == State.Attack and a.stateFrame == 0 and a.moveId == FightConfig.JabMoveId
		)
	end

	do
		local firstActive, lastActive, idleAt = attackTimeline(input({ straight = true }), straight)
		check("straight startup frames", firstActive == straight.startup + 1, firstActive)
		check("straight active frames", lastActive == straight.startup + straight.active, lastActive)
		check("straight returns to idle", idleAt == straight.startup + straight.active + straight.recovery + 1, idleAt)
	end

	do
		local firstActive, lastActive, idleAt = attackTimeline(input({ leftKick = true }), snapKick)
		check("snap kick startup frames", firstActive == snapKick.startup + 1, firstActive)
		check("snap kick active frames", lastActive == snapKick.startup + snapKick.active, lastActive)
		check("snap kick returns to idle", idleAt == snapKick.startup + snapKick.active + snapKick.recovery + 1, idleAt)
		firstActive, lastActive, idleAt = attackTimeline(input({ rightKick = true }), powerKick)
		check("power kick startup frames", firstActive == powerKick.startup + 1, firstActive)
		check("power kick active frames", lastActive == powerKick.startup + powerKick.active, lastActive)
		check(
			"power kick returns to idle",
			idleAt == powerKick.startup + powerKick.active + powerKick.recovery + 1,
			idleAt
		)
	end

	-- Hits, hitstop and knockback.
	do
		local a, b = pair(0, 3)
		FightSim.step(a, b, input({ jab = true }), neutral)
		local hitFrame = nil
		for frame = 1, 20 do
			FightSim.step(a, b, neutral, neutral)
			if b.hp < FightConfig.MaxHp and hitFrame == nil then
				hitFrame = frame
			end
		end
		check("hit lands on first active frame", hitFrame == jab.startup + 1, hitFrame)
		check("damage applied exactly once", b.hp == FightConfig.MaxHp - jab.damage, b.hp)
		check("attacker marked hitDone", a.hitDone)
	end

	do
		local a, b = pair(0, 3)
		FightSim.step(a, b, input({ jab = true }), neutral)
		stepMany(a, b, jab.startup + 1)
		check("defender in hitstun", b.state == State.Hitstun, b.state)
		check("hitstop set on both", a.hitstop == jab.hitstop and b.hitstop == jab.hitstop)
		local frozenX = b.x
		stepMany(a, b, jab.hitstop)
		check("positions frozen during hitstop", b.x == frozenX, b.x)
		stepMany(a, b, 3)
		check("knockback pushes defender away", b.x > frozenX + 0.05, b.x)
		stepMany(a, b, jab.hitstun + 2)
		check("defender recovers to idle", b.state == State.Idle, b.state)
	end

	do
		local a, b = pair(-3, 4)
		FightSim.step(a, b, input({ jab = true }), neutral)
		stepMany(a, b, 30)
		check("out of range whiffs", b.hp == FightConfig.MaxHp, b.hp)
	end

	do
		local a, b = pair(-1.5, 1.5)
		FightSim.step(a, b, input({ jab = true }), input({ jab = true }))
		stepMany(a, b, 14)
		check("trade damages both", a.hp == FightConfig.MaxHp - jab.damage and b.hp == FightConfig.MaxHp - jab.damage)
	end

	do
		-- B starts a slow straight, A's faster jab lands during its startup and interrupts it.
		local a, b = pair(0, 3)
		FightSim.step(a, b, neutral, input({ straight = true }))
		stepMany(a, b, 1)
		FightSim.step(a, b, input({ jab = true }), neutral)
		stepMany(a, b, 9)
		check("startup is interrupted by a faster hit", b.state == State.Hitstun and b.moveId == 0, b.state)
		stepMany(a, b, 60)
		check("interrupted attack never hits", a.hp == FightConfig.MaxHp, a.hp)
	end

	-- Block.
	do
		local a, b = pair(0, 3)
		local guarding = input({ guard = true })
		FightSim.step(a, b, input({ jab = true }), guarding)
		stepMany(a, b, jab.startup + 1, nil, guarding)
		check("guarding defender enters blockstun", b.state == State.Blockstun and b.stun == jab.blockstun, b.state)
		check("block takes chip damage only", b.hp == FightConfig.MaxHp - jab.chip, b.hp)
		check("block pushes the defender back", b.vx > 0)
		stepMany(a, b, 60, nil, guarding)
		check("holding guard returns to guard", b.state == State.Guard, b.state)
	end

	do
		local a, b = pair(0, 3)
		local guarding = input({ guard = true })
		FightSim.step(a, b, input({ jab = true }), guarding)
		stepMany(a, b, 12, nil, guarding)
		stepMany(a, b, 60)
		check("releasing guard after a block returns to idle", b.state == State.Idle, b.state)
	end

	do
		local a, b = pair(0, 3)
		b.hp = 1
		local guarding = input({ guard = true })
		FightSim.step(a, b, input({ straight = true }), guarding)
		stepMany(a, b, straight.startup + 1, nil, guarding)
		check("chip damage cannot knock out", b.hp == 1 and b.state == State.Blockstun, b.state)
	end

	do
		local a, b = pair(-6, 6)
		FightSim.step(a, b, neutral, input({ guard = true, moveZ = 1 }))
		stepMany(a, b, 30, nil, input({ guard = true, moveZ = 1 }))
		check("guarding fighter does not walk", b.x == 6 and b.state == State.Guard, b.x)
		FightSim.step(a, b, neutral, input({ guard = true, straight = true }))
		check(
			"attack can start out of guard",
			b.state == State.Attack and b.moveId == FightConfig.StraightMoveId,
			b.state
		)
	end

	-- Dash.
	do
		local a, b = pair(0, 8)
		FightSim.step(a, b, input({ dash = true }), neutral)
		check("dash starts", a.state == State.Dash)
		stepMany(a, b, dash.startup + dash.travel + dash.recovery - 1)
		check("dash is committed until its recovery ends", a.state == State.Dash, a.state)
		stepMany(a, b, 2)
		check("dash returns to idle", a.state == State.Idle, a.state)
		local expected = dash.travel * dash.speed / FightConfig.SimHz
		check("neutral dash backs off", math.abs(a.x - -expected) < 0.05, a.x)
	end

	do
		local a, b = pair(0, 8)
		FightSim.step(a, b, input({ dash = true, moveZ = 1 }), neutral)
		stepMany(a, b, 30)
		check("forward dash closes distance", math.abs(a.x - dash.travel * dash.speed / FightConfig.SimHz) < 0.05, a.x)
		local c, d = pair(0, 8)
		FightSim.step(c, d, input({ dash = true, moveX = 1 }), neutral)
		stepMany(c, d, 30)
		check("sidestep dash moves sideways", math.abs(c.z) > 2.4 and math.abs(c.x) < 1, c.z)
	end

	do
		-- A's jab travels along the line locked at the start, so a sidestep dodges it; standing still does not.
		local a, b = pair(0, 4.3)
		FightSim.step(a, b, input({ jab = true }), input({ dash = true, moveX = 1 }))
		stepMany(a, b, 30)
		check("sidestep dodges a linear attack", b.hp == FightConfig.MaxHp, b.hp)
		local c, d = pair(0, 4.3)
		FightSim.step(c, d, input({ jab = true }), neutral)
		stepMany(c, d, 30)
		check("same jab hits without the sidestep", d.hp == FightConfig.MaxHp - jab.damage, d.hp)
	end

	-- Frame data model: measured advantage matches the numbers derived from the move table.
	do
		local jabData = FrameData.forMove(FightConfig.JabMoveId)
		local straightData = FrameData.forMove(FightConfig.StraightMoveId)
		check(
			"jab frame data",
			jabData.onHit == 4 and jabData.onBlock == -1 and jabData.total == jab.startup + jab.active + jab.recovery
		)
		check(
			"straight frame data",
			straightData.onHit == 2
				and straightData.onBlock == -9
				and straightData.total == straight.startup + straight.active + straight.recovery
		)

		local jabHit = exchange(input({ jab = true }), neutral, 3)
		check("jab hit exchange found", jabHit ~= nil and jabHit.attacker == 1 and not jabHit.blocked)
		check(
			"jab measured on-hit advantage matches data",
			jabHit ~= nil and jabHit.advantage == jabData.onHit,
			jabHit and jabHit.advantage
		)

		local jabBlock = exchange(input({ jab = true }), input({ guard = true }), 3)
		check("jab block exchange found", jabBlock ~= nil and jabBlock.blocked)
		check(
			"jab measured on-block advantage matches data",
			jabBlock ~= nil and jabBlock.advantage == jabData.onBlock,
			jabBlock and jabBlock.advantage
		)

		local straightHit = exchange(input({ straight = true }), neutral, 3)
		check(
			"straight measured on-hit advantage matches data",
			straightHit ~= nil and straightHit.advantage == straightData.onHit,
			straightHit and straightHit.advantage
		)

		local straightBlock = exchange(input({ straight = true }), input({ guard = true }), 3)
		check(
			"straight measured on-block advantage matches data",
			straightBlock ~= nil and straightBlock.advantage == straightData.onBlock,
			straightBlock and straightBlock.advantage
		)
	end

	-- Kicks hit for their own damage and reach, and trade speed for power against the punches.
	do
		local a, b = pair(0, 3)
		FightSim.step(a, b, input({ leftKick = true }), neutral)
		stepMany(a, b, snapKick.startup + 1)
		check(
			"snap kick hits for its damage",
			b.hp == FightConfig.MaxHp - snapKick.damage and b.state == State.Hitstun and b.stun == snapKick.hitstun,
			b.hp
		)
		local c, d = pair(0, 3)
		FightSim.step(c, d, input({ rightKick = true }), neutral)
		stepMany(c, d, powerKick.startup + 1)
		check(
			"power kick hits for its damage",
			d.hp == FightConfig.MaxHp - powerKick.damage and d.stun == powerKick.hitstun,
			d.hp
		)
		check(
			"power kick knocks the target back harder than a jab",
			d.vx == powerKick.knockback and d.vx > jab.knockback
		)

		-- At 4.5 studs a snap kick falls short and a power kick still lands.
		local e, f = pair(0, 4.5)
		FightSim.step(e, f, input({ leftKick = true }), neutral)
		stepMany(e, f, 40)
		check("snap kick whiffs beyond its reach", f.hp == FightConfig.MaxHp, f.hp)
		local g, h = pair(0, 4.5)
		FightSim.step(g, h, input({ rightKick = true }), neutral)
		stepMany(g, h, 50)
		check("power kick reaches farther than a snap kick", h.hp == FightConfig.MaxHp - powerKick.damage, h.hp)

		local guarding = input({ guard = true })
		local i, j = pair(0, 3)
		FightSim.step(i, j, input({ leftKick = true }), guarding)
		stepMany(i, j, snapKick.startup + 1, nil, guarding)
		check(
			"snap kick is blocked for chip damage",
			j.state == State.Blockstun and j.stun == snapKick.blockstun and j.hp == FightConfig.MaxHp - snapKick.chip,
			j.hp
		)
		local k, l = pair(0, 3)
		FightSim.step(k, l, input({ rightKick = true }), guarding)
		stepMany(k, l, powerKick.startup + 1, nil, guarding)
		check(
			"power kick is blocked for chip damage",
			l.state == State.Blockstun and l.stun == powerKick.blockstun and l.hp == FightConfig.MaxHp - powerKick.chip,
			l.hp
		)

		-- A guarding fighter can start a kick, and a faster jab still beats a power kick's startup.
		local m, n = pair(-6, 6)
		FightSim.step(m, n, neutral, input({ guard = true, rightKick = true }))
		check(
			"kick can start out of guard",
			n.state == State.Attack and n.moveId == FightConfig.PowerKickMoveId,
			n.state
		)
		local o, p = pair(0, 3)
		FightSim.step(o, p, neutral, input({ rightKick = true }))
		stepMany(o, p, 5)
		FightSim.step(o, p, input({ jab = true }), neutral)
		stepMany(o, p, 9)
		check("a jab interrupts a power kick's startup", p.state == State.Hitstun and p.moveId == 0, p.state)
	end

	do
		local snapData = FrameData.forMove(FightConfig.SnapKickMoveId)
		local powerData = FrameData.forMove(FightConfig.PowerKickMoveId)
		check(
			"snap kick frame data",
			snapData.onHit == 2
				and snapData.onBlock == -7
				and snapData.total == snapKick.startup + snapKick.active + snapKick.recovery
		)
		check(
			"power kick frame data",
			powerData.onHit == 3
				and powerData.onBlock == -14
				and powerData.total == powerKick.startup + powerKick.active + powerKick.recovery
		)

		local snapHit = exchange(input({ leftKick = true }), neutral, 3)
		check(
			"snap kick measured on-hit advantage matches data",
			snapHit ~= nil and snapHit.advantage == snapData.onHit and not snapHit.blocked,
			snapHit and snapHit.advantage
		)
		local snapBlock = exchange(input({ leftKick = true }), input({ guard = true }), 3)
		check(
			"snap kick measured on-block advantage matches data",
			snapBlock ~= nil and snapBlock.advantage == snapData.onBlock and snapBlock.blocked,
			snapBlock and snapBlock.advantage
		)
		local powerHit = exchange(input({ rightKick = true }), neutral, 3)
		check(
			"power kick measured on-hit advantage matches data",
			powerHit ~= nil and powerHit.advantage == powerData.onHit and not powerHit.blocked,
			powerHit and powerHit.advantage
		)
		local powerBlock = exchange(input({ rightKick = true }), input({ guard = true }), 3)
		check(
			"power kick measured on-block advantage matches data",
			powerBlock ~= nil and powerBlock.advantage == powerData.onBlock and powerBlock.blocked,
			powerBlock and powerBlock.advantage
		)
	end

	do
		local history = FrameData.newHistory(60)
		local a, b = pair(0, 3)
		for frame = 1, 50 do
			FrameData.record(history, frame, a, b)
		end
		check(
			"history keeps recent frames",
			FrameData.indexOf(history, 50) ~= nil and FrameData.indexOf(history, 10) ~= nil
		)
		a.state = State.Dash
		FrameData.record(history, 40, a, b)
		check("rollback invalidates later frames", FrameData.indexOf(history, 41) == nil and history.latest == 40)
		FrameData.record(history, 41, a, b)
		local index = FrameData.indexOf(history, 41)
		check("resimulated frame replaces the old one", index ~= nil and history.stateA[index or 1] == State.Dash)
		check("old frames fall out of the window", FrameData.indexOf(history, 41 - 60) == nil)
	end

	do
		check(
			"cell kinds",
			FrameData.cellKind(State.Attack, 1, 3) == "startup"
				and FrameData.cellKind(State.Attack, 1, jab.startup + 1) == "active"
				and FrameData.cellKind(State.Attack, 1, jab.startup + jab.active + 1) == "recovery"
				and FrameData.cellKind(State.Guard, 0, 0) == "guard"
				and FrameData.cellKind(State.Blockstun, 0, 0) == "blockstun"
				and FrameData.cellKind(State.Hitstun, 0, 0) == "hitstun"
				and FrameData.cellKind(State.Dash, 0, 0) == "dash"
				and FrameData.cellKind(State.Idle, 0, 0) == "idle"
		)
	end

	-- Round flow and training.
	do
		local a, b = pair(0, 3)
		b.hp = jab.damage
		FightSim.step(a, b, input({ jab = true }), neutral)
		stepMany(a, b, jab.startup + 1)
		check("KO when hp reaches 0", b.state == State.KO and b.hp == 0, b.state)
		check(
			"the knockout blow freezes the fight",
			a.hitstop == FightConfig.KoFreezeFrames - 1 or b.hitstop > 0,
			b.hitstop
		)
		stepMany(a, b, FightConfig.KoResetFrames + FightConfig.KoFreezeFrames + 10)
		check(
			"round resets after KO",
			b.hp == FightConfig.MaxHp
				and b.state == State.Idle
				and a.x == -FightConfig.StartHalfDistance
				and b.x == FightConfig.StartHalfDistance
		)
	end

	do
		local training: FightSim.Options = { training = true }
		local a, b = pair(0, 3)
		b.hp = jab.damage
		b.healDelay = FightConfig.TrainingHealDelay
		FightSim.step(a, b, input({ jab = true }), neutral, training)
		stepMany(a, b, jab.startup + 1, nil, nil, training)
		check("training hit never knocks out", b.hp == 1 and b.state == State.Hitstun, b.state)
		stepMany(a, b, FightConfig.TrainingHealDelay + jab.hitstun + jab.hitstop + 5, nil, nil, training)
		check("training damage heals back", b.hp == FightConfig.MaxHp, b.hp)
	end

	-- Scripted dummy.
	do
		local function observe(mode: number): { [number]: boolean }
			local a, b = pair(-3, 3)
			local seen: { [number]: boolean } = {}
			local training: FightSim.Options = { training = true }
			local inputB = FightSim.newInput()
			for frame = 1, 600 do
				FightSim.dummyInput(frame, b, a, inputB, mode)
				FightSim.step(a, b, neutral, inputB, training)
				seen[b.state] = true
				if b.state == State.Attack then
					seen[100 + b.moveId] = true
				end
			end
			return seen
		end
		local idle = observe(0)
		check(
			"dummy mode 0 stays idle",
			idle[State.Attack] == nil and idle[State.Guard] == nil and idle[State.Dash] == nil
		)
		check("dummy mode 1 guards", observe(1)[State.Guard] == true)
		check("dummy mode 2 jabs", observe(2)[100 + FightConfig.JabMoveId] == true)
		check("dummy mode 3 throws straights", observe(3)[100 + FightConfig.StraightMoveId] == true)
		check("dummy mode 5 throws snap kicks", observe(5)[100 + FightConfig.SnapKickMoveId] == true)
		check("dummy mode 6 throws power kicks", observe(6)[100 + FightConfig.PowerKickMoveId] == true)
		check("dummy mode 7 grabs", observe(7)[State.Grab] == true)
		local mixed = observe(4)
		check(
			"dummy mode 4 mixes guard, every attack and dash",
			mixed[State.Guard] == true
				and mixed[100 + FightConfig.JabMoveId] == true
				and mixed[100 + FightConfig.StraightMoveId] == true
				and mixed[100 + FightConfig.SnapKickMoveId] == true
				and mixed[100 + FightConfig.PowerKickMoveId] == true
				and mixed[State.Dash] == true
		)
	end

	-- The guard bar: holding the guard and blocking drain it, it refills once the guard comes down, and an empty bar
	-- breaks the guard wide open.
	do
		local guard = FightConfig.Guard
		local guarding = input({ guard = true })

		local a, b = pair(-6, 6)
		stepMany(a, b, 60, nil, guarding)
		check("holding the guard drains the bar", b.guard == guard.max - 60 * guard.holdDrain, b.guard)
		stepMany(a, b, guard.regenDelay)
		check("the bar waits before it refills", b.guard == guard.max - 60 * guard.holdDrain, b.guard)
		stepMany(a, b, 3)
		check("then it refills", b.guard == guard.max - 60 * guard.holdDrain + 3 * guard.regen, b.guard)
		stepMany(a, b, 200)
		check("but never past full", b.guard == guard.max, b.guard)

		local c, d = pair(0, 3)
		FightSim.step(c, d, input({ jab = true }), guarding)
		stepMany(c, d, jab.startup + 1, nil, guarding)
		check(
			"a blocked move takes its guard damage",
			d.state == State.Blockstun and d.guard == guard.max - (jab.startup + 2) * guard.holdDrain - jab.guard,
			d.guard
		)

		local e, f = pair(0, 3)
		f.guard = straight.guard - 1
		FightSim.step(e, f, input({ straight = true }), guarding)
		stepMany(e, f, straight.startup + 1, nil, guarding)
		check(
			"blocking with too little left breaks the guard",
			f.state == State.GuardBreak and f.guard == 0 and f.stun == guard.breakFrames,
			f.state
		)
		check("the break takes only chip damage", f.hp == FightConfig.MaxHp - straight.chip, f.hp)
		check("and freezes the moment longer", f.hitstop == straight.hitstop + guard.breakHitstop, f.hitstop)
		-- The straight that broke it is followed by the slowest attack there is, which still lands.
		local landed = false
		for frame = 1, 90 do
			FightSim.step(e, f, input({ rightKick = frame % 2 == 1 }), guarding)
			if f.state == State.Hitstun or f.state == State.KO then
				landed = true
				break
			end
		end
		check("a broken guard is open to a power kick", landed and f.hp < FightConfig.MaxHp - straight.chip, f.state)
		check("a hit during the break restarts the bar at the refill", f.guard == guard.refill, f.guard)

		local g, h = pair(-6, 6)
		h.guard = 3 * guard.holdDrain
		stepMany(g, h, 3, nil, guarding)
		check("holding the guard until the bar is empty breaks it", h.state == State.GuardBreak, h.state)
		stepMany(g, h, guard.breakFrames - 1, nil, guarding)
		check("a break lasts its frames", h.state == State.GuardBreak, h.state)
		FightSim.step(g, h, neutral, neutral)
		check("and ends with the bar at the refill", h.state == State.Idle and h.guard == guard.refill, h.guard)

		local bulwark = FightSim.newFighter(6, 0)
		bulwark.stats = Loadout.stats(Loadout.encode({ chassis = 2, arms = 1, core = 1, legs = 1 }))
		local other = FightSim.newFighter(-6, 0)
		stepMany(other, bulwark, 60, nil, guarding)
		check(
			"BULWARK's guard drains slower",
			bulwark.guard == guard.max - 60 * guard.holdDrain * bulwark.stats.guardTaken
				and bulwark.stats.guardTaken < 1,
			bulwark.guard
		)
	end

	-- Throws: both punches grab, a grab beats a guard and loses to any attack, and grabbing back in time breaks free.
	do
		local throw = FightConfig.Throw
		local both = input({ jab = true, straight = true })
		local guarding = input({ guard = true })

		local a, b = pair(-6, 6)
		FightSim.step(a, b, both, neutral)
		check("both punches together grab", a.state == State.Grab, a.state)
		local c, d = pair(-6, 6)
		FightSim.step(c, d, input({ jab = true }), neutral)
		FightSim.step(c, d, input({ jab = true }), neutral)
		FightSim.step(c, d, input({ jab = true, straight = true }), neutral)
		check("the second punch two frames later turns the jab into a grab", c.state == State.Grab, c.state)
		local e, f = pair(-6, 6)
		FightSim.step(e, f, input({ jab = true }), neutral)
		stepMany(e, f, 2, input({ jab = true }), neutral)
		FightSim.step(e, f, input({ jab = true, straight = true }), neutral)
		check(
			"three frames later it is a jab and a straight",
			e.state == State.Attack and e.moveId == FightConfig.JabMoveId and e.action == FightSim.Action.Straight,
			e.state
		)
		local g, h = pair(-6, 6)
		FightSim.step(g, h, input({ grab = true }), neutral)
		check("the grab button grabs", g.state == State.Grab, g.state)

		-- A guard is no defence.
		local p, q = pair(0, 2.6)
		FightSim.step(p, q, both, guarding)
		local caughtAt = nil
		for frame = 1, throw.startup + throw.active + 2 do
			FightSim.step(p, q, neutral, guarding)
			if caughtAt == nil and q.state == State.Thrown then
				caughtAt = frame
			end
		end
		check("a grab catches a guarding opponent", caughtAt == throw.startup + 1 and p.state == State.Throw, caughtAt)
		check("the catch does no damage yet", q.hp == FightConfig.MaxHp, q.hp)
		local throwerFree, thrownFree = nil, nil
		for frame = 1, 120 do
			FightSim.step(p, q, neutral, neutral)
			if throwerFree == nil and p.state == State.Idle then
				throwerFree = frame
			end
			if thrownFree == nil and q.state == State.Idle then
				thrownFree = frame
			end
		end
		check("the slam deals the throw's damage", q.hp == FightConfig.MaxHp - throw.damage, q.hp)
		check(
			"the thrower is up first",
			throwerFree ~= nil and thrownFree ~= nil and thrownFree - throwerFree == throw.down - throw.hold,
			`{throwerFree} {thrownFree}`
		)
		check("the one thrown lands farther away", q.x - p.x > 2.6 + 0.5, q.x - p.x)

		local r, s = pair(0, 4.5)
		FightSim.step(r, s, both, guarding)
		local whiffEnd = nil
		for frame = 1, 60 do
			FightSim.step(r, s, neutral, guarding)
			if whiffEnd == nil and r.state == State.Idle then
				whiffEnd = frame
			end
		end
		check(
			"out of range the grab whiffs for its whole length",
			s.state == State.Guard and whiffEnd == throw.startup + throw.active + throw.recovery + 1,
			whiffEnd
		)

		-- Grabbing back in time breaks free; too late does nothing.
		local function thrownWith(breakAt: number): (FightSim.Fighter, FightSim.Fighter)
			local x, y = pair(0, 2.6)
			FightSim.step(x, y, both, neutral)
			while y.state ~= State.Thrown do
				FightSim.step(x, y, neutral, neutral)
			end
			local frames = 0
			while x.state == State.Throw and frames < 200 do
				frames += 1
				local press = y.stateFrame + 1 == breakAt and y.hitstop == 0
				FightSim.step(x, y, neutral, if press then both else neutral)
			end
			return x, y
		end
		local x1, y1 = thrownWith(throw.breakWindow)
		check(
			"grabbing back in time breaks free",
			x1.state == State.ThrowBreak and y1.state == State.ThrowBreak and y1.hp == FightConfig.MaxHp,
			`{x1.state} {y1.state}`
		)
		check("a broken throw shoves both apart", y1.vx > 0 and x1.vx < 0)
		local _, y2 = thrownWith(throw.breakWindow + 1)
		check("grabbing back too late does nothing", y2.hp == FightConfig.MaxHp - throw.damage, y2.hp)

		-- Any attack beats a grab: a strike on its way cannot be caught, and the grab's whiff is punished.
		local t, u = pair(0, 2.6)
		FightSim.step(t, u, both, input({ jab = true }))
		stepMany(t, u, jab.startup + 1)
		check("a jab beats a grab started with it", t.state == State.Hitstun and u.state ~= State.Thrown, t.state)
		local v, w = pair(0, 2.6)
		FightSim.step(v, w, both, input({ rightKick = true }))
		stepMany(v, w, powerKick.startup + 1)
		check(
			"even a power kick beats a grab, since it cannot be caught on its way",
			v.state == State.Hitstun and w.hp == FightConfig.MaxHp,
			v.state
		)

		-- An attack that is over can be caught, a stun cannot.
		local function grabbedWhile(setup: (FightSim.Fighter) -> ()): boolean
			local m, n = pair(0, 2.6)
			m.state = State.Grab
			m.stateFrame = throw.startup
			m.aimX = 1
			setup(n)
			FightSim.step(m, n, neutral, neutral)
			return n.state == State.Thrown
		end
		check(
			"a fighter finishing an attack can be caught",
			grabbedWhile(function(n)
				n.state = State.Attack
				n.moveId = FightConfig.JabMoveId
				n.stateFrame = jab.startup + jab.active + 1
			end)
		)
		check("a fighter in hitstun cannot", not grabbedWhile(function(n)
			n.state = State.Hitstun
			n.stun = 20
		end))
		check("nor one in blockstun", not grabbedWhile(function(n)
			n.state = State.Blockstun
			n.stun = 20
		end))
		check("a grab only catches in front", not grabbedWhile(function(n)
			n.x = -2.6
		end))

		local i, j = pair(0, 2.6)
		FightSim.step(i, j, both, both)
		stepMany(i, j, throw.startup + 1)
		check(
			"two grabs that catch each other break apart",
			i.state == State.ThrowBreak and j.state == State.ThrowBreak,
			`{i.state} {j.state}`
		)

		local k, l = pair(0, 2.6)
		l.hp = 5
		l.healDelay = FightConfig.TrainingHealDelay
		FightSim.step(k, l, both, neutral, { training = true })
		stepMany(k, l, 90, nil, nil, { training = true })
		check("a throw in training never knocks out", l.hp == 1 and l.state ~= State.KO, l.hp)
		local o, z = pair(0, 2.6)
		z.hp = 5
		FightSim.step(o, z, both, neutral, { training = false, rounds = true })
		stepMany(o, z, 60, nil, nil, { training = false, rounds = true })
		check("a throw can knock out", z.state == State.KO and z.hp == 0, z.state)

		check(
			"a grab's frames read as startup, active and recovery",
			FrameData.cellKind(State.Grab, 0, throw.startup) == "startup"
				and FrameData.cellKind(State.Grab, 0, throw.startup + 1) == "active"
				and FrameData.cellKind(State.Grab, 0, throw.startup + throw.active + 1) == "recovery"
				and FrameData.cellKind(State.GuardBreak, 0, 0) == "broken"
				and FrameData.cellKind(State.Thrown, 0, 0) == "throw"
		)
	end

	-- Movement limits and input buffering.
	do
		local a, b = pair(0, 3)
		stepMany(a, b, 600, input({ moveZ = -1 }), neutral)
		local radius = math.sqrt(a.x * a.x + a.z * a.z)
		check("fighter stays inside ring", radius <= FightConfig.RingRadius - FightConfig.BodyRadius, radius)
		local c, d = pair(0, 1)
		FightSim.step(c, d, neutral, neutral)
		check("fighters pushed apart to minimum separation", d.x - c.x >= FightConfig.MinSeparation - 1e-3, d.x - c.x)
	end

	do
		local a, b = pair(-6, 6)
		FightSim.step(a, b, input({ jab = true }), neutral)
		local total = jab.startup + jab.active + jab.recovery
		for frame = 1, total - 3 do
			FightSim.step(a, b, if frame == total - 3 then input({ jab = true }) else neutral, neutral)
		end
		local startedSecond = false
		for _ = 1, 10 do
			FightSim.step(a, b, neutral, neutral)
			if a.state == State.Attack and a.stateFrame == 0 then
				startedSecond = true
			end
		end
		check("buffered jab starts after recovery", startedSecond)
	end

	do
		local function run(): (FightSim.Fighter, FightSim.Fighter)
			local a, b = pair(-3, 3)
			for frame = 1, 1200 do
				local forward = if frame % 90 < 45 then 1 else -1
				local strafe = if (frame // 60) % 2 == 0 then 1 else -1
				FightSim.step(
					a,
					b,
					input({
						moveZ = forward,
						jab = frame % 37 == 0,
						straight = frame % 71 == 0,
						leftKick = frame % 43 == 0,
						rightKick = frame % 59 == 0,
						guard = frame % 100 < 20,
						dash = frame % 83 == 0,
						grab = frame % 89 == 0,
					}),
					input({
						moveX = strafe,
						jab = frame % 53 == 0 or frame % 101 == 0,
						straight = frame % 97 == 0 or frame % 101 == 1,
						leftKick = frame % 47 == 0,
						rightKick = frame % 67 == 0,
						guard = frame % 130 < 30,
						dash = frame % 61 == 0,
					})
				)
			end
			return a, b
		end
		local a1, b1 = run()
		local a2, b2 = run()
		check("simulation is deterministic with every action", sameFighter(a1, a2) and sameFighter(b1, b2))
	end

	return passed, failures
end
