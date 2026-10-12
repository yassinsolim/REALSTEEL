--!strict

-- Roblox adapter for FightSim. Fighter state lives in attributes on each fighter's Core part, which is what the
-- server authority system compares and rolls back. Runs on both the server and the predicting client. Every ring in the
-- hall is a fight of its own (see addRing); each step advances them all, and none reads another's state.

local RunService = game:GetService("RunService")

local BotBrain = require(script.Parent.BotBrain)
local FightConfig = require(script.Parent.FightConfig)
local FightSim = require(script.Parent.FightSim)
local FrameData = require(script.Parent.FrameData)
local InputSetup = require(script.Parent.InputSetup)
local Loadout = require(script.Parent.Loadout)
local MatchFlow = require(script.Parent.MatchFlow)

export type Metrics = {
	steps: number,
	resimSteps: number,
	rollbacks: number,
}

type Slot = {
	index: number,
	core: Instance,
	actions: InputSetup.Actions?,
}

-- One ring's fight: its fighters' cores and its match core, and the working state each step reuses.
type Ring = {
	slots: { Slot },
	match: Instance,
	fighterA: FightSim.Fighter,
	fighterB: FightSim.Fighter,
	inputA: FightSim.Input,
	inputB: FightSim.Input,
	options: FightSim.Options,
	matchState: MatchFlow.Match,
}

local Simulation = {}

local metrics: Metrics = { steps = 0, resimSteps = 0, rollbacks = 0 }
local wasResimulating = false
local rings: { Ring } = {}
local recorder: FrameData.History? = nil
local recordRing = 0

-- Simulation code may only touch synchronized APIs, so keep everything here to attributes and plain Luau.
local function readNumber(core: Instance, name: string): number
	local value = core:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return 0
end

local function readBool(core: Instance, name: string): boolean
	return core:GetAttribute(name) == true
end

function Simulation.readState(core: Instance, into: FightSim.Fighter): boolean
	if type(core:GetAttribute("PosX")) ~= "number" then
		return false
	end
	into.x = readNumber(core, "PosX")
	into.z = readNumber(core, "PosZ")
	into.vx = readNumber(core, "VelX")
	into.vz = readNumber(core, "VelZ")
	into.hp = readNumber(core, "Hp")
	into.state = readNumber(core, "State")
	into.stateFrame = readNumber(core, "StateFrame")
	into.moveId = readNumber(core, "MoveId")
	into.hitDone = readBool(core, "HitDone")
	into.hitstop = readNumber(core, "Hitstop")
	into.stun = readNumber(core, "Stun")
	into.prevJab = readBool(core, "PrevJab")
	into.prevStraight = readBool(core, "PrevStraight")
	into.prevLeftKick = readBool(core, "PrevLeftKick")
	into.prevRightKick = readBool(core, "PrevRightKick")
	into.prevDash = readBool(core, "PrevDash")
	into.action = readNumber(core, "Action")
	into.actionBuffer = readNumber(core, "ActionBuffer")
	into.aimX = readNumber(core, "AimX")
	into.aimZ = readNumber(core, "AimZ")
	into.dashFwd = readNumber(core, "DashFwd")
	into.dashSide = readNumber(core, "DashSide")
	into.healDelay = readNumber(core, "HealDelay")
	-- The server sets the loadout before it starts a match, so it is a command like AiMode, not something the step writes.
	into.stats = Loadout.stats(core:GetAttribute("Loadout"))
	return true
end

function Simulation.writeState(core: Instance, from: FightSim.Fighter)
	core:SetAttribute("PosX", from.x)
	core:SetAttribute("PosZ", from.z)
	core:SetAttribute("VelX", from.vx)
	core:SetAttribute("VelZ", from.vz)
	core:SetAttribute("Hp", from.hp)
	core:SetAttribute("State", from.state)
	core:SetAttribute("StateFrame", from.stateFrame)
	core:SetAttribute("MoveId", from.moveId)
	core:SetAttribute("HitDone", from.hitDone)
	core:SetAttribute("Hitstop", from.hitstop)
	core:SetAttribute("Stun", from.stun)
	core:SetAttribute("PrevJab", from.prevJab)
	core:SetAttribute("PrevStraight", from.prevStraight)
	core:SetAttribute("PrevLeftKick", from.prevLeftKick)
	core:SetAttribute("PrevRightKick", from.prevRightKick)
	core:SetAttribute("PrevDash", from.prevDash)
	core:SetAttribute("Action", from.action)
	core:SetAttribute("ActionBuffer", from.actionBuffer)
	core:SetAttribute("AimX", from.aimX)
	core:SetAttribute("AimZ", from.aimZ)
	core:SetAttribute("DashFwd", from.dashFwd)
	core:SetAttribute("DashSide", from.dashSide)
	core:SetAttribute("HealDelay", from.healDelay)
end

-- The round and match state shares the match core with the commands. The simulation owns these attributes.
function Simulation.readMatch(core: Instance, into: MatchFlow.Match)
	into.phase = readNumber(core, "Phase")
	into.phaseFrame = readNumber(core, "PhaseFrame")
	into.tick = readNumber(core, "Tick")
	into.round = math.max(readNumber(core, "Round"), 1)
	into.winsA = readNumber(core, "WinsA")
	into.winsB = readNumber(core, "WinsB")
	into.timer = readNumber(core, "Timer")
	into.result = readNumber(core, "Result")
	into.reason = readNumber(core, "Reason")
end

function Simulation.writeMatch(core: Instance, from: MatchFlow.Match)
	core:SetAttribute("Phase", from.phase)
	core:SetAttribute("PhaseFrame", from.phaseFrame)
	core:SetAttribute("Tick", from.tick)
	core:SetAttribute("Round", from.round)
	core:SetAttribute("WinsA", from.winsA)
	core:SetAttribute("WinsB", from.winsB)
	core:SetAttribute("Timer", from.timer)
	core:SetAttribute("Result", from.result)
	core:SetAttribute("Reason", from.reason)
end

-- Adds a ring's fight: its two fighters' cores in slot order, and the match core that carries its commands (training
-- mode, dummy behavior, reset requests) as replicated attributes, so every peer applies them on the same simulation
-- frame. Returns the ring's number, which the server and every client must give the same ring.
function Simulation.addRing(cores: { Part }, match: Instance): number
	local slots: { Slot } = {}
	for index, core in cores do
		slots[index] = { index = index, core = core, actions = nil }
	end
	table.insert(rings, {
		slots = slots,
		match = match,
		fighterA = FightSim.newFighter(0, 0),
		fighterB = FightSim.newFighter(0, 0),
		inputA = FightSim.newInput(),
		inputB = FightSim.newInput(),
		options = { training = false, rounds = false, combat = true },
		matchState = MatchFlow.new(),
	})
	return #rings
end

-- Whose Input Action System states drive a seat, or nil for whatever the seat's AiMode says.
function Simulation.setInputs(ring: number, index: number, actions: InputSetup.Actions?)
	local entry = rings[ring]
	local slot = if entry ~= nil then entry.slots[index] else nil
	if slot ~= nil then
		slot.actions = actions
	end
end

-- Client-side only: keeps a rolling record of one ring's states for the frame meter (ring 0 records nothing).
function Simulation.setRecorder(history: FrameData.History?, ring: number)
	recorder = history
	recordRing = ring
end

function Simulation.getMetrics(): Metrics
	return metrics
end

-- AiMode 0: neutral. 1: scripted dummy computed inside the simulation. 2: inputs fed through attributes by the
-- server, which behaves like an unpredictable remote player. 3: the bot, computed inside the simulation from the
-- fighters' states, so every peer agrees on it without any input being sent.
local function readInput(
	slot: Slot,
	me: FightSim.Fighter,
	foe: FightSim.Fighter,
	into: FightSim.Input,
	frame: number,
	dummyMode: number,
	botLevel: number,
	tick: number
)
	local actions = slot.actions
	if actions ~= nil then
		local direction = actions.move:GetState() :: Vector2
		into.moveX, into.moveZ = FightSim.moveFromStick(direction.X, direction.Y)
		into.jab = actions.jab:GetState() :: boolean
		into.straight = actions.straight:GetState() :: boolean
		into.leftKick = actions.leftKick:GetState() :: boolean
		into.rightKick = actions.rightKick:GetState() :: boolean
		into.guard = actions.guard:GetState() :: boolean
		into.dash = actions.dash:GetState() :: boolean
		return
	end

	local mode = readNumber(slot.core, "AiMode")
	if mode == 1 then
		FightSim.dummyInput(frame, me, foe, into, dummyMode)
	elseif mode == 3 then
		BotBrain.input(tick, me, foe, into, botLevel, slot.index)
	elseif mode == 2 then
		into.moveX = readNumber(slot.core, "InMoveX")
		into.moveZ = readNumber(slot.core, "InMoveZ")
		into.jab = readBool(slot.core, "InJab")
		into.straight = readBool(slot.core, "InStraight")
		into.leftKick = readBool(slot.core, "InLeftKick")
		into.rightKick = readBool(slot.core, "InRightKick")
		into.guard = readBool(slot.core, "InGuard")
		into.dash = readBool(slot.core, "InDash")
	else
		into.moveX = 0
		into.moveZ = 0
		into.jab = false
		into.straight = false
		into.leftKick = false
		into.rightKick = false
		into.guard = false
		into.dash = false
	end
end

local function clearInput(input: FightSim.Input)
	input.moveX = 0
	input.moveZ = 0
	input.jab = false
	input.straight = false
	input.leftKick = false
	input.rightKick = false
	input.guard = false
	input.dash = false
end

-- One step of one ring's fight. `frame` is the step's clock for the scripted dummy.
local function stepRing(index: number, ring: Ring, frame: number)
	local slotA = ring.slots[1]
	local slotB = ring.slots[2]
	if slotA == nil or slotB == nil then
		return
	end
	local fighterA, fighterB = ring.fighterA, ring.fighterB
	if not Simulation.readState(slotA.core, fighterA) or not Simulation.readState(slotB.core, fighterB) then
		return
	end

	local match = ring.match
	local matchState = ring.matchState
	Simulation.readMatch(match, matchState)
	local lobby = readBool(match, "Lobby")
	local training = readBool(match, "TrainingMode")
	local mode = if lobby then MatchFlow.Mode.Lobby elseif training then MatchFlow.Mode.Free else MatchFlow.Mode.Rounds
	local dummyMode = readNumber(match, "DummyMode")
	local botLevel = readNumber(match, "BotLevel")
	-- A reset request, or a mode the current phase does not belong to, starts the match over on the marks.
	local token = readNumber(match, "ResetToken")
	local requested = token ~= readNumber(match, "AppliedReset")
	if requested or not MatchFlow.fits(matchState, mode) then
		FightSim.reset(fighterA, fighterB)
		MatchFlow.start(matchState, mode)
		if requested then
			match:SetAttribute("AppliedReset", token)
		end
	end

	-- Training and the menu never knock anyone out; rounds do, and own the resets.
	local options = ring.options
	options.training = mode ~= MatchFlow.Mode.Rounds
	options.rounds = mode == MatchFlow.Mode.Rounds
	local acting = MatchFlow.canAct(matchState)
	options.combat = acting

	local inputA, inputB = ring.inputA, ring.inputB
	if acting then
		readInput(slotA, fighterA, fighterB, inputA, frame, dummyMode, botLevel, matchState.tick)
		readInput(slotB, fighterB, fighterA, inputB, frame, dummyMode, botLevel, matchState.tick)
	else
		-- Between rounds and in the menu the fighters stand still whatever is pressed.
		clearInput(inputA)
		clearInput(inputB)
	end
	FightSim.step(fighterA, fighterB, inputA, inputB, options)
	if MatchFlow.step(matchState, fighterA, fighterB) then
		FightSim.reset(fighterA, fighterB)
	end
	Simulation.writeState(slotA.core, fighterA)
	Simulation.writeState(slotB.core, fighterB)
	Simulation.writeMatch(match, matchState)

	local history = recorder
	if history ~= nil and index == recordRing then
		FrameData.record(history, frame, fighterA, fighterB)
	end
end

local function onStep(_deltaTime: number)
	local resimulating = RunService:IsResimulating()
	metrics.steps += 1
	if resimulating then
		metrics.resimSteps += 1
		if not wasResimulating then
			metrics.rollbacks += 1
		end
	end
	wasResimulating = resimulating

	local frame = math.floor(time() * FightConfig.SimHz + 0.5)
	for index, ring in rings do
		stepRing(index, ring, frame)
	end
end

function Simulation.start(): RBXScriptConnection
	return RunService:BindToSimulation(onStep, Enum.StepFrequency.Hz60)
end

return Simulation
