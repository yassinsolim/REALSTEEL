--!strict

-- Automated multiplayer checks. They run only inside a Studio test started with
-- StudioTestService:ExecuteMultiplayerTestAsync(players, { scenario = ..., duration = ... }) and do nothing in a normal
-- session. The server watches the authoritative state, tells the clients when to play and stop, collects their reports,
-- and ends the test with a result table. Scenarios:
--   pvp    two players queue for a 1v1 and trade a seeded mix of every action in the main ring; both clients must end up
--          matching the server
--   match  two players queue for a 1v1, one pummels the other through a whole match, then asks for a rematch
--   bot    one player sets a build in the garage, picks a bot level in the menu and fights it in the first pit while the
--          main ring's bots fight on, then leaves the pit and comes back to train
--   pits   two players queue for training at once and land in a pit each, while the main ring's bots fight on; each
--          client predicts the other's pit from that player's inputs
-- (level = 1 to 3 picks the bot's level in the bot scenario.)
-- Every client reports every ring. A ring that holds still at the end (the scenario's own rings once they settle, and
-- idle rings) has to match the server in full; a ring that is still fighting has to match in what the server told it.

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local Workspace = game:GetService("Workspace")

local okArgs, args = pcall(function()
	return StudioTestService:GetTestArgs()
end)
if not okArgs or type(args) ~= "table" then
	return
end
local scenario = args.scenario
if scenario ~= "pvp" and scenario ~= "match" and scenario ~= "bot" and scenario ~= "pits" then
	return
end

local duration: number = if type(args.duration) == "number" then args.duration else 20
local level: number = if type(args.level) == "number" then args.level else 2
local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FightSim = require(ReplicatedStorage.Shared.FightSim)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)
local State = FightSim.State
local Phase = MatchFlow.Phase

local report = Instance.new("RemoteEvent")
report.Name = "ChecksReport"
report.Parent = ReplicatedStorage
ReplicatedStorage:SetAttribute("ChecksScenario", scenario)
ReplicatedStorage:SetAttribute("ChecksLevel", level)

type RingDump = {
	full: string,
	commands: string,
}

type ClientReport = {
	slot: number,
	userId: number,
	steps: number,
	resimSteps: number,
	rollbacks: number,
	pingMs: number,
	errors: number,
	engineErrors: number,
	errorSamples: { string },
	-- The ring the client was in at the end, and what it saw of every ring then, by name.
	ring: number,
	dumps: { [string]: RingDump },
}

local reports: { [number]: ClientReport } = {}
report.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) == "table" then
		reports[player.UserId] = payload :: ClientReport
	end
end)

local failures: { string } = {}
local function check(name: string, condition: boolean, detail: any?)
	if not condition then
		table.insert(failures, if detail ~= nil then `{name} ({detail})` else name)
	end
end

-- Counters that change every frame, and a fallen fighter's frame count, are left out: everything else has to match.
local VOLATILE = { Tick = true, PhaseFrame = true, Timer = true }
-- What the server tells a ring rather than what its fight computes (see the client half, which keeps the same list).
local COMMANDS = {
	AiMode = true,
	Loadout = true,
	InMoveX = true,
	InMoveZ = true,
	InJab = true,
	InStraight = true,
	InLeftKick = true,
	InRightKick = true,
	InGuard = true,
	InDash = true,
	Lobby = true,
	TrainingMode = true,
	BotLevel = true,
	DummyMode = true,
	ResetToken = true,
	OwnerUserId = true,
	Look = true,
	Slot = true,
}

local function dump(instance: Instance, only: { [string]: boolean }?): string
	local keys = {}
	local attributes = instance:GetAttributes()
	local down = attributes.State == State.KO
	for key in attributes do
		local wanted = if only ~= nil then only[key] == true else not VOLATILE[key]
		if wanted and not (down and key == "StateFrame") then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local value = attributes[key]
		table.insert(
			parts,
			key .. "=" .. (if type(value) == "number" then string.format("%.4f", value) else tostring(value))
		)
	end
	return table.concat(parts, " ")
end

local function waitUntil(predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.1)
	end
	return predicate()
end

local function finish(result: { [string]: any })
	StudioTestService:EndTest(result)
end

-- The rings as the server built them, numbered like FoundryLayout.Rings.
type Ring = {
	index: number,
	label: string,
	modelOne: Model,
	modelTwo: Model,
	cores: { Part },
	match: Part,
}
local ringsFolder = Workspace:WaitForChild("Rings")
local rings: { Ring } = {}
for index, spec in FoundryLayout.Rings do
	local model = ringsFolder:WaitForChild(spec.name)
	local modelOne = model:WaitForChild("Fighter1") :: Model
	local modelTwo = model:WaitForChild("Fighter2") :: Model
	rings[index] = {
		index = index,
		label = spec.label,
		modelOne = modelOne,
		modelTwo = modelTwo,
		cores = { modelOne:WaitForChild("Core") :: Part, modelTwo:WaitForChild("Core") :: Part },
		match = model:WaitForChild("Match") :: Part,
	}
end

local function ringDump(ring: Ring): RingDump
	return {
		full = `F1 {dump(ring.cores[1])}\nF2 {dump(ring.cores[2])}\nMatch {dump(ring.match)}`,
		commands = `F1 {dump(ring.cores[1], COMMANDS)} {dump(ring.modelOne, COMMANDS)}\n`
			.. `F2 {dump(ring.cores[2], COMMANDS)} {dump(ring.modelTwo, COMMANDS)}\n`
			.. `Match {dump(ring.match, COMMANDS)}`,
	}
end

local function owner(model: Model): number
	local value = model:GetAttribute("OwnerUserId")
	return if type(value) == "number" then value else 0
end

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else -1
end

-- Where each scenario's fights belong: a 1v1 in the main ring, a bot match in the first pit, the pits scenario's training
-- in both pits. The first of them is the one the single-ring checks follow.
local MAIN, PIT_ONE, PIT_TWO = 1, 2, 3
local watched: { number } = if scenario == "bot"
	then { PIT_ONE }
	elseif scenario == "pits" then { PIT_ONE, PIT_TWO }
	else { MAIN }
local primary = rings[watched[1]]
local modelOne, modelTwo, match = primary.modelOne, primary.modelTwo, primary.match
local coreTwo = primary.cores[2]
local mainRing = rings[MAIN]

local function training(ring: Ring): boolean
	return ring.match:GetAttribute("TrainingMode") == true and ring.match:GetAttribute("Lobby") == false
end

local expectedPlayers = if scenario == "bot" then 1 else 2
local ready = waitUntil(function()
	if #Players:GetPlayers() ~= expectedPlayers then
		return false
	end
	-- A bot fight starts in the hall; a 1v1 starts once both players have queued and been seated, and the pits scenario
	-- once both are training, each in a pit.
	if scenario == "bot" then
		return true
	elseif scenario == "pits" then
		local first, second = owner(rings[PIT_ONE].modelOne), owner(rings[PIT_TWO].modelOne)
		return first ~= 0 and second ~= 0 and first ~= second and training(rings[PIT_ONE]) and training(rings[PIT_TWO])
	end
	return owner(modelOne) ~= 0 and owner(modelTwo) ~= 0 and match:GetAttribute("TrainingMode") == false
end, 90)
if not ready then
	finish({ passed = false, failures = { `{expectedPlayers} player(s) did not join and take their seats` } })
	return
end

local ownerOne = if scenario == "bot" then Players:GetPlayers()[1].UserId else owner(modelOne)
local ownerTwo = if scenario == "pits" then owner(rings[PIT_TWO].modelOne) else owner(modelTwo)
check("fighters belong to different players", scenario == "bot" or ownerOne ~= ownerTwo)
if scenario == "bot" then
	check("the player starts in the hall, not in the ring", owner(modelOne) ~= ownerOne)
end
local owners: { number } = if scenario == "bot" then { ownerOne } else { ownerOne, ownerTwo }
-- The ring each player should be in at the end.
local expectedRing: { [number]: number } = {}
if scenario == "pits" then
	expectedRing[ownerOne] = PIT_ONE
	expectedRing[ownerTwo] = PIT_TWO
else
	for _, userId in owners do
		expectedRing[userId] = watched[1]
	end
end

-- Let the join-time reset apply, then start the clients.
task.wait(2)
local seenStates: { [number]: boolean } = {}
local seenMoves: { [number]: boolean } = {}
local seenPhases: { [number]: boolean } = {}
local attacksIn: { [number]: number } = {}
local botAttacks = 0
-- Health by ring and seat, as "ring:seat".
local lowestHp: { [string]: number } = {}
local lastHp: { [string]: number } = {}
local hpDrops = 0
local mostWins = 0
local botWasSeated = false
local playerRing = 0
local mainExhibitionMeanwhile = false
local mainTaken = false
ReplicatedStorage:SetAttribute("ChecksStart", true)

local function sample()
	-- Before the bot scenario's player takes the pit, it stands idle; nothing there counts.
	local playerSeated = scenario ~= "bot" or owner(modelOne) == ownerOne
	for _, index in watched do
		local ring = rings[index]
		for seat, core in ring.cores do
			local state = core:GetAttribute("State")
			if type(state) == "number" and playerSeated then
				seenStates[state] = true
				local moveId = core:GetAttribute("MoveId")
				if state == State.Attack and type(moveId) == "number" then
					seenMoves[moveId] = true
					attacksIn[index] = (attacksIn[index] or 0) + 1
					if seat == 2 and scenario == "bot" then
						botAttacks += 1
					end
				end
			end
			local hp = core:GetAttribute("Hp")
			local key = `{index}:{seat}`
			if type(hp) == "number" then
				lowestHp[key] = math.min(lowestHp[key] or 100, hp)
				if hp < (lastHp[key] or 100) then
					hpDrops += 1
				end
				lastHp[key] = hp
			end
		end
		local phase = ring.match:GetAttribute("Phase")
		if type(phase) == "number" then
			seenPhases[phase] = true
		end
		mostWins = math.max(mostWins, number(ring.match, "WinsA"), number(ring.match, "WinsB"))
	end

	-- In the scenarios that leave the main ring to the bots, nobody is ever seated there, and its exhibition goes on.
	if scenario == "bot" or scenario == "pits" then
		if owner(mainRing.modelOne) ~= 0 or owner(mainRing.modelTwo) ~= 0 then
			mainTaken = true
		end
		local practising = if scenario == "bot"
			then playerSeated and match:GetAttribute("BotLevel") == level and coreTwo:GetAttribute("AiMode") == 3
			else owner(rings[PIT_ONE].modelOne) ~= 0 and owner(rings[PIT_TWO].modelOne) ~= 0
		if
			practising
			and mainRing.match:GetAttribute("Lobby") == false
			and mainRing.cores[1]:GetAttribute("AiMode") == 3
			and mainRing.cores[2]:GetAttribute("AiMode") == 3
		then
			mainExhibitionMeanwhile = true
		end
	end
	if
		scenario == "bot"
		and playerSeated
		and match:GetAttribute("BotLevel") == level
		and coreTwo:GetAttribute("AiMode") == 3
	then
		botWasSeated = true
		local seatedPlayer = Players:GetPlayerByUserId(ownerOne)
		local ringValue = if seatedPlayer ~= nil then seatedPlayer:GetAttribute("Ring") else nil
		if type(ringValue) == "number" then
			playerRing = ringValue
		end
	end
end

local endTime = os.clock() + duration
local rematchChecked = false
local rematchOk = false
-- Who won the match scenario's first match, and who lost it.
local firstWinner = 0
local firstLoser = 0
while os.clock() < endTime do
	sample()
	if scenario == "match" and seenPhases[Phase.MatchEnd] and not rematchChecked then
		-- The client asks for a rematch a few seconds after the result appears; the match must start over clean.
		rematchChecked = true
		local seatOneWon = number(match, "WinsA") > number(match, "WinsB")
		firstWinner = if seatOneWon then owner(modelOne) else owner(modelTwo)
		firstLoser = if seatOneWon then owner(modelTwo) else owner(modelOne)
		rematchOk = waitUntil(function()
			sample()
			local phase = number(match, "Phase")
			return (phase == Phase.Intro or phase == Phase.Fight)
				and number(match, "WinsA") == 0
				and number(match, "WinsB") == 0
		end, 20)
		break
	end
	task.wait(0.05)
end

ReplicatedStorage:SetAttribute("ChecksStop", true)

-- The bot scenario ends with a trip through the menu: the client opens it, then picks training.
local sawLobby = false
local sawTraining = false
if scenario == "bot" then
	sawLobby = waitUntil(function()
		return match:GetAttribute("Lobby") == true
	end, 10)
	sawTraining = waitUntil(function()
		return training(primary) and coreTwo:GetAttribute("AiMode") == 1
	end, 10)
end

-- Wait for a calm moment in every watched ring: the fight is a couple of seconds into a round (or over), or training
-- with nobody acting.
local function ringCalm(ring: Ring): boolean
	local phase = number(ring.match, "Phase")
	local settled = (phase == Phase.Fight and number(ring.match, "PhaseFrame") > 150)
		or phase == Phase.MatchEnd
		or ((scenario == "bot" or scenario == "pits") and phase == Phase.Free)
	if not settled then
		return false
	end
	for _, core in ring.cores do
		local state = number(core, "State")
		if (state ~= State.Idle and state ~= State.KO) or number(core, "Hitstop") ~= 0 then
			return false
		end
	end
	return true
end
local function calm(): boolean
	for _, index in watched do
		if not ringCalm(rings[index]) then
			return false
		end
	end
	return true
end
local settled = waitUntil(calm, 40)
check("the fights settled", settled, number(match, "Phase"))
-- What every ring looks like now, and whether it holds still: the watched rings have settled, and an idle ring stands at
-- its marks.
local serverDumps: { [string]: RingDump } = {}
local still: { [string]: boolean } = {}
for index, ring in rings do
	local name = FoundryLayout.Rings[index].name
	serverDumps[name] = ringDump(ring)
	still[name] = table.find(watched, index) ~= nil or ring.match:GetAttribute("Lobby") == true
end
ReplicatedStorage:SetAttribute("ChecksDump", true)

local gotReports = waitUntil(function()
	for _, userId in owners do
		if reports[userId] == nil then
			return false
		end
	end
	return true
end, 40)
check("every client reported", gotReports)

local errors = 0
for _, entry in LogService:GetLogHistory() do
	if entry.messageType == Enum.MessageType.MessageError then
		errors += 1
	end
end
check("no server errors", errors == 0, errors)
check("attacks were thrown", seenStates[State.Attack] == true)
check("hits were exchanged", hpDrops > 0, hpDrops)
check("a hit or block landed", seenStates[State.Hitstun] == true or seenStates[State.Blockstun] == true)
if scenario ~= "pits" then
	check("the fight phase was reached", seenPhases[Phase.Fight] == true)
end

if scenario == "pvp" then
	check("jab was thrown", seenMoves[FightConfig.JabMoveId] == true)
	check("straight was thrown", seenMoves[FightConfig.StraightMoveId] == true)
	check("snap kick was thrown", seenMoves[FightConfig.SnapKickMoveId] == true)
	check("power kick was thrown", seenMoves[FightConfig.PowerKickMoveId] == true)
	check("guard was used", seenStates[State.Guard] == true)
	check("dash was used", seenStates[State.Dash] == true)
elseif scenario == "match" then
	check("a round ended", seenPhases[Phase.RoundEnd] == true)
	check("a fighter was knocked out", seenStates[State.KO] == true)
	check("the match reached its end", seenPhases[Phase.MatchEnd] == true)
	check("the winner took the target number of rounds", mostWins == FightConfig.Match.roundsToWin, mostWins)
	check("a rematch starts the match over", rematchOk)
	-- The title was vacant, so the winner claimed it, and the result counted once even though the rematch started.
	local foundry = ReplicatedStorage:FindFirstChild("FoundryState")
	local winner = Players:GetPlayerByUserId(firstWinner)
	local loser = Players:GetPlayerByUserId(firstLoser)
	check(
		"the winner claimed the vacant title",
		foundry ~= nil and foundry:GetAttribute("ChampionId") == firstWinner,
		if foundry ~= nil then foundry:GetAttribute("ChampionId") else nil
	)
	check(
		"the win counted once, through the rematch",
		winner ~= nil and winner:GetAttribute("RecordWins") == 1,
		if winner ~= nil then winner:GetAttribute("RecordWins") else nil
	)
	check(
		"and the loss once",
		loser ~= nil and loser:GetAttribute("RecordLosses") == 1,
		if loser ~= nil then loser:GetAttribute("RecordLosses") else nil
	)
elseif scenario == "bot" then
	check("the bot was seated at the chosen level", botWasSeated)
	check("the bot match was fought in the first pit", playerRing == PIT_ONE, playerRing)
	check("the main ring's exhibition went on meanwhile", mainExhibitionMeanwhile)
	check("nobody was seated in the main ring", not mainTaken)
	check("the bot threw attacks", botAttacks > 5, botAttacks)
	check("leaving handed the ring back", sawLobby)
	check("training started with a dummy", sawTraining)
else
	check("the first player trained in the first pit", owner(rings[PIT_ONE].modelOne) == ownerOne)
	check("the second player trained in the second pit", owner(rings[PIT_TWO].modelOne) == ownerTwo)
	check("both pits saw attacks", (attacksIn[PIT_ONE] or 0) > 0 and (attacksIn[PIT_TWO] or 0) > 0)
	check("the main ring's exhibition went on meanwhile", mainExhibitionMeanwhile)
	check("nobody was seated in the main ring", not mainTaken)
end

local summaries: { [string]: any } = {}
local stateList: { number } = {}
for state in seenStates do
	table.insert(stateList, state)
end
table.sort(stateList)
local moveList: { number } = {}
for moveId in seenMoves do
	table.insert(moveList, moveId)
end
table.sort(moveList)
local phaseList: { number } = {}
for phase in seenPhases do
	table.insert(phaseList, phase)
end
table.sort(phaseList)
for clientIndex, userId in owners do
	local entry = reports[userId]
	if entry ~= nil then
		local name = `client {clientIndex}`
		check(`{name} saw no errors`, entry.errors == 0, entry.errors)
		check(`{name} ended in its ring`, entry.ring == expectedRing[userId], entry.ring)
		local mismatched: { string } = {}
		for index, spec in FoundryLayout.Rings do
			local theirs = serverDumps[spec.name]
			local mine = if entry.dumps ~= nil then entry.dumps[spec.name] else nil
			local same = if mine == nil
				then false
				elseif still[spec.name] then mine.full == theirs.full
				else mine.commands == theirs.commands
			check(
				`{name} sees {rings[index].label} as the server does{if still[spec.name] then "" else " (commands)"}`,
				same
			)
			if not same then
				table.insert(mismatched, spec.name)
			end
		end
		local summary: { [string]: any } = {
			slot = entry.slot,
			steps = entry.steps,
			resimSteps = entry.resimSteps,
			rollbacks = entry.rollbacks,
			pingMs = entry.pingMs,
			errors = entry.errors,
			engineErrors = entry.engineErrors,
			matchesServer = #mismatched == 0,
		}
		if entry.errors > 0 then
			summary.errorSamples = entry.errorSamples
		end
		if #mismatched > 0 then
			summary.mismatched = mismatched
			summary.dumps = entry.dumps
		end
		summaries[`client{clientIndex}`] = summary
	end
end

local serverSummary: { [string]: string } = {}
for name, entry in serverDumps do
	serverSummary[name] = if still[name] then entry.full else entry.commands
end
finish({
	passed = #failures == 0,
	failures = failures,
	scenario = scenario,
	duration = duration,
	hpDrops = hpDrops,
	lowestHp = lowestHp,
	statesSeen = stateList,
	movesSeen = moveList,
	phasesSeen = phaseList,
	wins = mostWins,
	botAttacks = botAttacks,
	clients = summaries,
	serverDumps = serverSummary,
})
