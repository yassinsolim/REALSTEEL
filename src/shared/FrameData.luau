--!strict

-- Frame data for the training mode: numbers derived from the move table, a rolling history of simulation states, and a
-- frame advantage measured from that history so the table can be checked against what really happened.

local FightConfig = require(script.Parent.FightConfig)
local FightSim = require(script.Parent.FightSim)

export type MoveFrameData = {
	name: string,
	startup: number,
	active: number,
	recovery: number,
	total: number,
	onHit: number,
	onBlock: number,
	damage: number,
	chip: number,
}

export type History = {
	size: number,
	latest: number,
	frames: { number },
	stateA: { number },
	stateB: { number },
	stateFrameA: { number },
	stateFrameB: { number },
	moveA: { number },
	moveB: { number },
	hitDoneA: { boolean },
	hitDoneB: { boolean },
}

export type Exchange = {
	attacker: number,
	moveId: number,
	blocked: boolean,
	-- Positive when the attacker can act first.
	advantage: number,
	hitFrame: number,
}

local State = FightSim.State

local FrameData = {}

-- The numbers for one of the attacker's moves, as they work against a defender with the given stats (stock when omitted).
function FrameData.forMove(moveId: number, attacker: FightConfig.Stats?, defender: FightConfig.Stats?): MoveFrameData
	local move = (attacker or FightConfig.BaseStats).moves[moveId]
	local suffered = defender or FightConfig.BaseStats
	local committed = move.active + move.recovery
	return {
		name = move.name,
		startup = move.startup,
		active = move.active,
		recovery = move.recovery,
		total = move.startup + move.active + move.recovery,
		onHit = FightSim.hitstunFor(move, suffered) - committed,
		onBlock = FightSim.blockstunFor(move, suffered) - committed,
		damage = move.damage,
		chip = FightSim.chipFor(move, suffered),
	}
end

function FrameData.newHistory(size: number): History
	return {
		size = size,
		latest = -1,
		frames = table.create(size, -1),
		stateA = table.create(size, 0),
		stateB = table.create(size, 0),
		stateFrameA = table.create(size, 0),
		stateFrameB = table.create(size, 0),
		moveA = table.create(size, 0),
		moveB = table.create(size, 0),
		hitDoneA = table.create(size, false),
		hitDoneB = table.create(size, false),
	}
end

-- Entries are keyed by frame number, so a resimulated frame overwrites what was recorded before the rollback.
function FrameData.record(history: History, frame: number, a: FightSim.Fighter, b: FightSim.Fighter)
	local index = frame % history.size + 1
	history.frames[index] = frame
	history.stateA[index] = a.state
	history.stateB[index] = b.state
	history.stateFrameA[index] = a.stateFrame
	history.stateFrameB[index] = b.stateFrame
	history.moveA[index] = a.moveId
	history.moveB[index] = b.moveId
	history.hitDoneA[index] = a.hitDone
	history.hitDoneB[index] = b.hitDone
	history.latest = frame
end

-- Index of a frame's entry, or nil if it is too old or has been invalidated by a rollback.
local function indexOf(history: History, frame: number): number?
	if frame > history.latest or frame <= history.latest - history.size then
		return nil
	end
	local index = frame % history.size + 1
	if history.frames[index] ~= frame then
		return nil
	end
	return index
end

function FrameData.indexOf(history: History, frame: number): number?
	return indexOf(history, frame)
end

local function isStun(state: number): boolean
	return state == State.Hitstun or state == State.Blockstun
end

-- Measures how many frames sooner the attacker could act than the defender after the contact at hitFrame.
local function measure(history: History, hitFrame: number, attacker: number): Exchange?
	local attackerStates = if attacker == 1 then history.stateA else history.stateB
	local defenderStates = if attacker == 1 then history.stateB else history.stateA
	local moves = if attacker == 1 then history.moveA else history.moveB

	local hitIndex = indexOf(history, hitFrame)
	if hitIndex == nil then
		return nil
	end
	local attackerFree: number? = nil
	local defenderFree: number? = nil
	for frame = hitFrame + 1, history.latest do
		local index = indexOf(history, frame)
		if index == nil then
			return nil
		end
		if attackerFree == nil and FightSim.isActionable(attackerStates[index]) then
			attackerFree = frame
		end
		if defenderFree == nil and FightSim.isActionable(defenderStates[index]) then
			defenderFree = frame
		end
		if attackerFree ~= nil and defenderFree ~= nil then
			return {
				attacker = attacker,
				moveId = moves[hitIndex],
				blocked = defenderStates[hitIndex] == State.Blockstun,
				advantage = defenderFree - attackerFree,
				hitFrame = hitFrame,
			}
		end
	end
	return nil
end

-- The most recent completed exchange where one fighter's attack landed or was blocked, if any is still in history.
function FrameData.lastExchange(history: History): Exchange?
	for frame = history.latest, history.latest - history.size + 2, -1 do
		local index = indexOf(history, frame)
		local previous = indexOf(history, frame - 1)
		if index ~= nil and previous ~= nil then
			if
				isStun(history.stateB[index])
				and not isStun(history.stateB[previous])
				and history.stateA[index] == State.Attack
				and history.hitDoneA[index]
			then
				local exchange = measure(history, frame, 1)
				if exchange ~= nil then
					return exchange
				end
			end
			if
				isStun(history.stateA[index])
				and not isStun(history.stateA[previous])
				and history.stateB[index] == State.Attack
				and history.hitDoneB[index]
			then
				local exchange = measure(history, frame, 2)
				if exchange ~= nil then
					return exchange
				end
			end
		end
	end
	return nil
end

-- Which phase a recorded frame was in, for drawing the frame meter.
function FrameData.cellKind(state: number, moveId: number, stateFrame: number, moves: { FightConfig.MoveData }?): string
	if state == State.Attack then
		local move: FightConfig.MoveData? = (moves or FightConfig.Moves)[moveId]
		if move == nil then
			return "idle"
		end
		if stateFrame <= move.startup then
			return "startup"
		elseif stateFrame <= move.startup + move.active then
			return "active"
		end
		return "recovery"
	elseif state == State.Hitstun then
		return "hitstun"
	elseif state == State.Blockstun then
		return "blockstun"
	elseif state == State.Guard then
		return "guard"
	elseif state == State.Dash then
		return "dash"
	elseif state == State.KO then
		return "ko"
	end
	return "idle"
end

return FrameData
