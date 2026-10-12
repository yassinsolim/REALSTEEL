--!strict

-- Server: the line for the rings and what the hall is told about them. Players queue for a fight through the Menu remote
-- (see RingQueue for who gets which ring); when their turn comes their ring (see Ring) seats them, and when the match is
-- over the ring is handed on. While nobody wants the main ring, two bots put on an exhibition in it, so there is always a
-- fight to watch.
--
-- What the clients need to know is published as attributes, none of them on a predicted core, where every change would
-- roll the clients back: per ring on a folder named after it in `state` (Session, NextUp, RematchOpen, HandoverAt), the
-- number waiting on `state` itself, and each player's place on the Player (QueueMode, QueueLevel, QueueAhead, QueueAlone,
-- InRing, and Ring, the number of the ring they are in or 0).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)
local RingQueue = require(ReplicatedStorage.Shared.RingQueue)
local Garage = require(script.Parent.Garage)
local Ring = require(script.Parent.Ring)
local WorldBuilder = require(script.Parent.WorldBuilder)

export type Rings = {
	-- A request from the Menu remote: "bot" (with a level), "training", "versus", "leave", "rematch" or "menu" (leave).
	request: (player: Player, action: string, level: number?) -> (),
	-- Call when a player leaves the game.
	remove: (player: Player) -> (),
	-- Call when a player's character spawns, so a player in a ring is put back in their booth.
	characterAdded: (player: Player) -> (),
	-- Call as the server shuts down: every match already won is reported, and from then on nothing is, so the players
	-- the shutdown removes forfeit nothing (whether they are removed before this is called or after).
	close: () -> (),
}

-- Told when a bot match or a 1v1 in a ring reaches its end: the mode, the bot's level, who sat in each seat (an empty seat
-- was the bot) and the seat that won. It runs in a thread of its own, so the rings never wait on it.
export type MatchEnded = (mode: string, level: number, owners: { [number]: Player? }, winner: number) -> ()

local Rings = {}

-- How long a finished match stays up before its ring is handed on: briefly when someone is waiting for the ring, longer
-- otherwise, so there is time to ask for a rematch.
local HANDOVER_WAITING = 7
local HANDOVER_IDLE = 25
-- How long a training session may go on once someone is waiting for its ring.
local TRAINING_GRACE = 45
-- How long a ring with exhibitions stands empty before the bots fight, and how long an exhibition's result stays up.
local EXHIBITION_DELAY = 4
local EXHIBITION_RESULT = 6
-- How long a 1v1 left undecided by a player dropping out of the game waits before it counts as lost by them. It counts
-- only if the other player is still here by then and the server is not shutting down: a shutdown or an update removes
-- everyone, in no set order with the server's close, and nobody forfeits that way.
local DROPOUT_GRACE = 5
local TICK = 0.2
local NAME_LENGTH = 14

local function setIfChanged(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function nameOf(id: number): string
	local player = Players:GetPlayerByUserId(id)
	local name = if player ~= nil then player.DisplayName else "PLAYER"
	return string.upper(string.sub(name, 1, NAME_LENGTH))
end

function Rings.new(world: WorldBuilder.World, garage: Garage.Garage, state: Instance, onMatchEnded: MatchEnded?): Rings
	local now = os.clock()
	local rules: { RingQueue.Rule } = {}
	local rings: { Ring.Ring } = {}
	local boards: { Instance } = {}
	for index, ringWorld in world.rings do
		local spec = ringWorld.spec
		rules[index] = { versus = spec.versus, solo = spec.solo, rank = spec.rank }
		rings[index] = Ring.new(ringWorld, garage, now)
		local board = Instance.new("Folder")
		board.Name = spec.name
		board:SetAttribute("Index", index)
		board.Parent = state
		boards[index] = board
	end
	local queue = RingQueue.new(rules)
	local random = Random.new()
	-- Set once the server shuts down (see close).
	local closed = false

	local function lingerFor(index: number): number
		return if RingQueue.waitingFor(queue, index) then HANDOVER_WAITING else HANDOVER_IDLE
	end

	local function startSession(session: RingQueue.Session)
		local owners: { [number]: Player? } = {}
		for seat, id in session.ids do
			local player = Players:GetPlayerByUserId(id)
			if player ~= nil then
				owners[seat] = player
			end
		end
		Ring.seat(rings[session.ring], session.mode, session.level, owners)
	end

	-- Reports the ring's match once: when it has reached its end, when it is torn down (`final`: someone walks out or
	-- drops out of the game, or the server shuts down) with its last round already won, or, when `quitter` walks out of
	-- a 1v1 that is still undecided, as lost by them; one who `droppedOut` of the game loses it only after DROPOUT_GRACE.
	-- A bot match or training left before it is won counts for nothing. Never yields, so whoever called it carries on
	-- with the ring as it was.
	local function settle(ring: Ring.Ring, quitter: Player?, final: boolean?, droppedOut: boolean?)
		if closed or (ring.mode ~= "bot" and ring.mode ~= "versus") then
			return
		end
		local generation = Ring.generation(ring)
		if generation == ring.reported then
			return
		end
		local match = ring.world.match
		local winsA = match:GetAttribute("WinsA")
		local winsB = match:GetAttribute("WinsB")
		local phase = match:GetAttribute("Phase")
		local winner = MatchFlow.winner(
			if type(phase) == "number" then phase else MatchFlow.Phase.Lobby,
			if type(winsA) == "number" then winsA else 0,
			if type(winsB) == "number" then winsB else 0,
			final == true or quitter ~= nil
		)
		local forfeit = false
		if winner == nil and quitter ~= nil and ring.mode == "versus" then
			local seat = Ring.seatOf(ring, quitter)
			if seat ~= nil then
				winner = 3 - seat
				forfeit = true
			end
		end
		if winner == nil then
			return
		end
		ring.reported = generation
		local report = onMatchEnded
		if report == nil then
			return
		end
		local mode, level, owners, won = ring.mode, ring.level, table.clone(ring.owners), winner
		if forfeit and droppedOut then
			task.delay(DROPOUT_GRACE, function()
				local stayed = owners[won]
				if not closed and stayed ~= nil and stayed.Parent == Players then
					report(mode, level, owners, won)
				end
			end)
		else
			task.spawn(report, mode, level, owners, won)
		end
	end

	local function endSession(index: number, quitter: Player?)
		settle(rings[index], quitter, true)
		RingQueue.finish(queue, index)
		Ring.clear(rings[index], os.clock())
	end

	local function describe(first: RingQueue.Entry?, partner: RingQueue.Entry?): string
		if first == nil then
			return ""
		elseif partner ~= nil then
			return `{nameOf(first.id)}  vs  {nameOf(partner.id)}`
		elseif first.mode == "bot" then
			return `{nameOf(first.id)}  ·  BOT {BotBrain.Levels[math.clamp(first.level, 1, BotBrain.LevelCount)].name}`
		end
		return `{nameOf(first.id)}  ·  TRAINING`
	end

	-- What the clients show: per ring who is next, whether a rematch is open and when it is handed on, and where each
	-- player stands in line.
	local function publish(at: number)
		local serverNow = Workspace:GetServerTimeNow()
		for index, ring in rings do
			local board = boards[index]
			setIfChanged(board, "Session", if ring.mode == "idle" then "" else ring.mode)
			setIfChanged(board, "NextUp", describe(RingQueue.nextFor(queue, index)))
			setIfChanged(board, "RematchOpen", ring.overSince ~= nil and RingQueue.canRematch(queue, index))
			local session = queue.sessions[index]
			local remaining: number? = nil
			if session ~= nil then
				local over = ring.overSince
				if session.deadline ~= nil then
					remaining = session.deadline - at
				elseif over ~= nil and session.mode ~= "training" then
					remaining = lingerFor(index) - (at - over)
				end
			end
			-- In the server's clock, rounded so it does not change on every tick.
			setIfChanged(
				board,
				"HandoverAt",
				if remaining ~= nil then math.floor((serverNow + remaining) * 2 + 0.5) / 2 else 0
			)
		end
		setIfChanged(state, "Waiting", #queue.entries)

		local versusWaiting = 0
		for _, entry in queue.entries do
			if entry.mode == "versus" then
				versusWaiting += 1
			end
		end
		for _, player in Players:GetPlayers() do
			local entry, ahead = RingQueue.find(queue, player.UserId)
			local session = RingQueue.sessionOf(queue, player.UserId)
			setIfChanged(player, "QueueMode", if entry ~= nil then entry.mode else "")
			setIfChanged(player, "QueueLevel", if entry ~= nil then entry.level else 0)
			setIfChanged(player, "QueueAhead", ahead)
			-- A 1v1 waits for a second player, however far ahead it is.
			setIfChanged(player, "QueueAlone", entry ~= nil and entry.mode == "versus" and versusWaiting < 2)
			setIfChanged(player, "InRing", session ~= nil)
			setIfChanged(player, "Ring", if session ~= nil then session.ring else 0)
		end
	end

	local function step()
		local at = os.clock()
		for _, ring in rings do
			Ring.update(ring, at)
			settle(ring, nil)
		end

		RingQueue.updateDeadlines(queue, at, TRAINING_GRACE)
		for index, ring in rings do
			local session = queue.sessions[index]
			if session ~= nil then
				local over = ring.overSince
				local deadline = session.deadline
				local finished = session.mode ~= "training" and over ~= nil and at - over >= lingerFor(index)
				if finished or (deadline ~= nil and at >= deadline) then
					endSession(index)
				end
			end
		end

		for _, session in RingQueue.start(queue, at) do
			startSession(session)
		end
		for index, ring in rings do
			if queue.sessions[index] == nil and ring.spec.exhibitions then
				local over = ring.overSince
				if ring.mode == "exhibition" and over ~= nil and at - over >= EXHIBITION_RESULT then
					-- The winches hoist the pair away before the next one is dropped in.
					Ring.clear(ring, at)
				elseif ring.mode == "idle" and at - ring.idleSince >= EXHIBITION_DELAY then
					Ring.apply(ring, "exhibition", random:NextInteger(2, 3), {})
				end
			end
		end
		publish(at)
	end

	local function request(player: Player, action: string, value: number?)
		local id = player.UserId
		local at = os.clock()
		local session = RingQueue.sessionOf(queue, id)
		if action == "bot" then
			local wanted = if value ~= nil and value == value then math.floor(value) else 2
			RingQueue.join(queue, id, "bot", math.clamp(wanted, 1, BotBrain.LevelCount), at)
		elseif action == "training" then
			RingQueue.join(queue, id, "training", 0, at)
		elseif action == "versus" then
			RingQueue.join(queue, id, "versus", 0, at)
		elseif action == "leave" or action == "menu" then
			if session ~= nil then
				-- Walking out of a 1v1 that is still on loses it (see settle).
				endSession(session.ring, player)
			else
				RingQueue.leave(queue, id)
			end
		elseif action == "rematch" then
			if session ~= nil then
				local ring = rings[session.ring]
				if ring.overSince ~= nil and RingQueue.canRematch(queue, session.ring) then
					-- The finished match is settled first, so the rematch can never count it again.
					settle(ring, nil)
					Ring.restart(ring)
				end
			end
		end
		step()
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= TICK then
			elapsed = 0
			step()
		end

		-- The training keys of each ring's first seat. M leaves a bot match or training, never a 1v1.
		for _, ring in rings do
			local owner = ring.owners[1]
			local pressedNext, pressedReset, pressedToggle = Ring.pressedKeys(ring)
			if owner ~= nil then
				if pressedNext and ring.mode == "training" then
					Ring.cycleDummy(ring)
				end
				if pressedReset then
					if ring.mode == "training" then
						Ring.restart(ring)
					elseif ring.overSince ~= nil then
						request(owner, "rematch", nil)
					end
				end
				if pressedToggle and (ring.mode == "training" or ring.mode == "bot") then
					request(owner, "leave", nil)
				end
			end
		end
	end)

	step()
	return {
		request = request,
		remove = function(player: Player)
			-- Dropping out of a 1v1 that is still on loses it, like walking out does, once it is clear the server is not
			-- shutting down (see DROPOUT_GRACE).
			local session = RingQueue.sessionOf(queue, player.UserId)
			if session ~= nil then
				settle(rings[session.ring], player, true, true)
			end
			local ended = RingQueue.remove(queue, player.UserId)
			if ended ~= nil then
				Ring.clear(rings[ended.ring], os.clock())
			end
			step()
		end,
		characterAdded = function(player: Player)
			for _, ring in rings do
				local seat = Ring.seatOf(ring, player)
				if seat ~= nil then
					-- After the spawn has placed the character.
					task.delay(0.25, function()
						if ring.owners[seat] == player then
							Ring.hold(player, ring.spec.booths[seat])
						end
					end)
				end
			end
		end,
		close = function()
			for _, ring in rings do
				settle(ring, nil, true)
			end
			closed = true
		end,
	}
end

return Rings
