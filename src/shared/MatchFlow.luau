--!strict

-- Pure round and match flow on top of FightSim: intro, fight with a clock, round end, and a first-to-N match. Like
-- FightSim it has no Roblox APIs, so the server and every predicting client step it identically and it can be unit
-- tested without a place. Its state lives on the match core as attributes, which the engine rolls back with the rest.

local FightConfig = require(script.Parent.FightConfig)
local FightSim = require(script.Parent.FightSim)

export type Match = {
	phase: number,
	-- Frames spent in the current phase.
	phaseFrame: number,
	-- Simulation frames since the session began. Never reset, so AI can seed its choices from it.
	tick: number,
	round: number,
	winsA: number,
	winsB: number,
	-- Frames left on the round clock.
	timer: number,
	-- Who won the last round and how it ended.
	result: number,
	reason: number,
}

local MatchFlow = {}

-- Lobby: a menu is up, nobody acts. Free: training, no rounds. The rest are a round match.
MatchFlow.Phase = {
	Lobby = 0,
	Free = 1,
	Intro = 2,
	Fight = 3,
	RoundEnd = 4,
	MatchEnd = 5,
}

-- What the server asks for, independent of where the match currently is.
MatchFlow.Mode = {
	Lobby = 0,
	Free = 1,
	Rounds = 2,
}

MatchFlow.Result = {
	None = 0,
	A = 1,
	B = 2,
	Draw = 3,
}

MatchFlow.Reason = {
	None = 0,
	KO = 1,
	Time = 2,
	DoubleKO = 3,
}

local Phase = MatchFlow.Phase
local Mode = MatchFlow.Mode
local Result = MatchFlow.Result
local Reason = MatchFlow.Reason

local function roundFrames(): number
	return FightConfig.Match.roundSeconds * FightConfig.SimHz
end

function MatchFlow.new(): Match
	return {
		phase = Phase.Lobby,
		phaseFrame = 0,
		tick = 0,
		round = 1,
		winsA = 0,
		winsB = 0,
		timer = roundFrames(),
		result = Result.None,
		reason = Reason.None,
	}
end

-- Begins a fresh match (or the menu, or training) without touching the session tick.
function MatchFlow.start(match: Match, mode: number)
	match.phase = if mode == Mode.Lobby then Phase.Lobby elseif mode == Mode.Free then Phase.Free else Phase.Intro
	match.phaseFrame = 0
	match.round = 1
	match.winsA = 0
	match.winsB = 0
	match.timer = roundFrames()
	match.result = Result.None
	match.reason = Reason.None
end

-- Whether the current phase belongs to the requested mode. When it does not, the caller restarts the match.
function MatchFlow.fits(match: Match, mode: number): boolean
	if mode == Mode.Lobby then
		return match.phase == Phase.Lobby
	elseif mode == Mode.Free then
		return match.phase == Phase.Free
	end
	return match.phase >= Phase.Intro
end

-- Inputs only count, and hits only land, while the fight is on.
function MatchFlow.canAct(match: Match): boolean
	return match.phase == Phase.Free or match.phase == Phase.Fight
end

function MatchFlow.isDecided(match: Match): boolean
	local needed = FightConfig.Match.roundsToWin
	return match.winsA >= needed or match.winsB >= needed
end

-- The fighter (1 or 2) who has won a match with these wins, in this phase: once it has reached its end, or, while it is
-- being torn down (`final`: someone leaves, the server shuts down), as soon as its last round has been won, even with
-- the knockout still playing out. nil while it is undecided.
function MatchFlow.winner(phase: number, winsA: number, winsB: number, final: boolean): number?
	local needed = FightConfig.Match.roundsToWin
	if winsA < needed and winsB < needed then
		return nil
	elseif phase ~= Phase.MatchEnd and not final then
		return nil
	end
	return if winsA > winsB then 1 else 2
end

local function endRound(match: Match, a: FightSim.Fighter, b: FightSim.Fighter)
	local knockedA = a.state == FightSim.State.KO
	local knockedB = b.state == FightSim.State.KO
	if knockedA and knockedB then
		match.result = Result.Draw
		match.reason = Reason.DoubleKO
	elseif knockedA then
		match.result = Result.B
		match.reason = Reason.KO
	elseif knockedB then
		match.result = Result.A
		match.reason = Reason.KO
	else
		match.reason = Reason.Time
		-- The health bars are what the players see, so the fuller one wins, whatever each build's maximum is. Comparing the
		-- fractions by cross-multiplying keeps it exact.
		local healthA = a.hp * b.stats.maxHp
		local healthB = b.hp * a.stats.maxHp
		if healthA > healthB then
			match.result = Result.A
		elseif healthB > healthA then
			match.result = Result.B
		else
			match.result = Result.Draw
		end
	end

	if match.result == Result.A then
		match.winsA += 1
	elseif match.result == Result.B then
		match.winsB += 1
	end
	match.phase = Phase.RoundEnd
	match.phaseFrame = 0
end

-- Call once per simulation frame after FightSim.step. Returns true when the fighters must be put back on their marks.
function MatchFlow.step(match: Match, a: FightSim.Fighter, b: FightSim.Fighter): boolean
	match.tick += 1
	local phase = match.phase

	if phase == Phase.Intro then
		match.phaseFrame += 1
		if match.phaseFrame >= FightConfig.Match.introFrames then
			match.phase = Phase.Fight
			match.phaseFrame = 0
			match.timer = roundFrames()
		end
	elseif phase == Phase.Fight then
		match.phaseFrame += 1
		match.timer = math.max(match.timer - 1, 0)
		if a.state == FightSim.State.KO or b.state == FightSim.State.KO or match.timer <= 0 then
			endRound(match, a, b)
		end
	elseif phase == Phase.RoundEnd then
		match.phaseFrame += 1
		if match.phaseFrame >= FightConfig.Match.roundEndFrames then
			match.phaseFrame = 0
			if MatchFlow.isDecided(match) then
				match.phase = Phase.MatchEnd
				return false
			end
			-- A drawn round is replayed under the same number.
			if match.result ~= Result.Draw then
				match.round += 1
			end
			match.phase = Phase.Intro
			match.timer = roundFrames()
			return true
		end
	elseif phase == Phase.MatchEnd then
		match.phaseFrame += 1
	end
	return false
end

-- Whole seconds left on the clock, for display.
function MatchFlow.secondsLeft(match: Match): number
	return math.ceil(match.timer / FightConfig.SimHz)
end

return MatchFlow
