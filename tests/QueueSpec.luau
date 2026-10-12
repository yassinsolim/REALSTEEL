--!strict

-- Headless checks for the line for the rings: who gets which ring next, how a 1v1 pairs up, when a rematch is allowed and
-- when training has to make room. Run from Studio's command bar, or without Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.QueueSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RingQueue = require(ReplicatedStorage.Shared.RingQueue)

local A, B, C, D, E = 101, 202, 303, 404, 505

-- One ring that hosts everything.
local ONE: { RingQueue.Rule } = { { versus = true, solo = true, rank = 1 } }
-- The hall: the main ring hosts everything but goes to practice last, and two pits host practice.
local MAIN, PIT1, PIT2 = 1, 2, 3
local HALL: { RingQueue.Rule } = {
	{ versus = true, solo = true, rank = 2 },
	{ versus = false, solo = true, rank = 1 },
	{ versus = false, solo = true, rank = 1 },
}

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

	local function ids(session: RingQueue.Session?): string
		if session == nil then
			return "none"
		end
		local parts = {}
		for _, id in session.ids do
			table.insert(parts, tostring(id))
		end
		return `{session.mode}:{table.concat(parts, ",")}`
	end

	-- What started, as "ring=mode:ids" in the order the rings were handed out.
	local function started(sessions: { RingQueue.Session }): string
		local parts = {}
		for _, session in sessions do
			table.insert(parts, `{session.ring}={ids(session)}`)
		end
		return if #parts == 0 then "none" else table.concat(parts, " ")
	end

	local function deadline(queue: RingQueue.Queue, ring: number): number?
		local session = queue.sessions[ring]
		return if session ~= nil then session.deadline else nil
	end

	local function ahead(queue: RingQueue.Queue, id: number): number
		local _, count = RingQueue.find(queue, id)
		return count
	end

	-- An empty line starts nothing.
	do
		local queue = RingQueue.new(ONE)
		check("a new line is empty", #queue.entries == 0 and queue.sessions[1] == nil)
		check("nothing starts from an empty line", #RingQueue.start(queue, 0) == 0)
		check("nobody is waiting", not RingQueue.waitingFor(queue, 1))
		check("no rematch without a session", not RingQueue.canRematch(queue, 1))
	end

	-- A bot match starts at once and takes its player out of line.
	do
		local queue = RingQueue.new(ONE)
		check("joining works", RingQueue.join(queue, A, "bot", 3, 1))
		local session = RingQueue.start(queue, 2)[1]
		check("a bot match starts at once", ids(session) == "bot:101", ids(session))
		check("it keeps the level", session ~= nil and session.level == 3)
		check("it knows its ring", session ~= nil and session.ring == 1)
		check("the player left the line", #queue.entries == 0)
		check("the player is in the ring", RingQueue.inSession(queue, A))
		check("the ring cannot be handed out twice", #RingQueue.start(queue, 3) == 0)
		check("someone in the ring cannot queue", not RingQueue.join(queue, A, "training", 0, 4))
		check("a rematch is open while nobody waits", RingQueue.canRematch(queue, 1))
		local ended = RingQueue.finish(queue, 1)
		check("finishing returns the session", ids(ended) == "bot:101")
		check("and frees the ring", queue.sessions[1] == nil and not RingQueue.inSession(queue, A))
	end

	-- A 1v1 needs two players, and a lone 1v1 waiter does not hold up the line.
	do
		local queue = RingQueue.new(ONE)
		RingQueue.join(queue, A, "versus", 0, 1)
		check("a lone 1v1 waiter cannot start", #RingQueue.start(queue, 2) == 0)
		check("a lone 1v1 waiter is not waiting for the ring", not RingQueue.waitingFor(queue, 1))
		RingQueue.join(queue, B, "training", 0, 3)
		local first = RingQueue.start(queue, 4)[1]
		check("the player behind a lone 1v1 waiter goes first", ids(first) == "training:202", ids(first))
		local entry, count = RingQueue.find(queue, A)
		check("the 1v1 waiter keeps waiting at the front", entry ~= nil and entry.mode == "versus" and count == 0)
		RingQueue.finish(queue, 1)
		RingQueue.join(queue, C, "bot", 1, 5)
		RingQueue.join(queue, D, "versus", 0, 6)
		local pair = RingQueue.start(queue, 7)[1]
		check("the two earliest 1v1 players pair up, in order", ids(pair) == "versus:101,404", ids(pair))
		check("the bot player behind them is still in line", (RingQueue.find(queue, C)) ~= nil and ahead(queue, C) == 0)
		check("with someone able to start, no rematch", not RingQueue.canRematch(queue, 1))
		RingQueue.leave(queue, C)
		check("with nobody waiting, a rematch is open", RingQueue.canRematch(queue, 1))
		RingQueue.join(queue, B, "versus", 0, 8)
		check("a lone 1v1 waiter does not close the rematch", RingQueue.canRematch(queue, 1))
	end

	-- Changing what you wait for keeps your place; leaving and rejoining does not.
	do
		local queue = RingQueue.new(ONE)
		RingQueue.join(queue, A, "bot", 1, 1)
		RingQueue.join(queue, B, "bot", 2, 2)
		check("joining the same way twice changes nothing", not RingQueue.join(queue, B, "bot", 2, 3))
		check("changing the level counts as a change", RingQueue.join(queue, B, "bot", 3, 3))
		check("changing mode is allowed", RingQueue.join(queue, A, "training", 0, 4))
		local entry, count = RingQueue.find(queue, A)
		check("changing mode keeps the place", entry ~= nil and entry.mode == "training" and count == 0)
		check("a training entry has no level", entry ~= nil and entry.level == 0)
		check("leaving works once", RingQueue.leave(queue, A) and not RingQueue.leave(queue, A))
		RingQueue.join(queue, A, "bot", 1, 5)
		check("rejoining goes to the back", ahead(queue, A) == 1)
		check("a player not in line is found nowhere", (RingQueue.find(queue, C)) == nil)
	end

	-- A player who leaves the game ends their session and leaves the line.
	do
		local queue = RingQueue.new(ONE)
		RingQueue.join(queue, A, "versus", 0, 1)
		RingQueue.join(queue, B, "versus", 0, 2)
		RingQueue.start(queue, 3)
		RingQueue.join(queue, C, "bot", 2, 4)
		local ended = RingQueue.remove(queue, B)
		check("leaving the game ends your session", ids(ended) == "versus:101,202", ids(ended))
		check("the ring is free again", queue.sessions[1] == nil)
		check("someone not in the ring leaving ends nothing", RingQueue.remove(queue, C) == nil)
		check("and takes them out of line", #queue.entries == 0)
	end

	-- Training hands the ring over once someone is waiting.
	do
		local queue = RingQueue.new(ONE)
		RingQueue.join(queue, A, "training", 0, 1)
		RingQueue.start(queue, 1)
		check("training never offers a rematch", not RingQueue.canRematch(queue, 1))
		RingQueue.updateDeadlines(queue, 10, 45)
		check("nobody waiting, no deadline", deadline(queue, 1) == nil)
		RingQueue.join(queue, B, "versus", 0, 11)
		RingQueue.updateDeadlines(queue, 12, 45)
		check("a lone 1v1 waiter sets no deadline", deadline(queue, 1) == nil)
		RingQueue.join(queue, C, "bot", 1, 13)
		RingQueue.updateDeadlines(queue, 14, 45)
		check("someone able to start sets one", deadline(queue, 1) == 59, deadline(queue, 1))
		RingQueue.updateDeadlines(queue, 20, 45)
		check("the deadline does not move", deadline(queue, 1) == 59, deadline(queue, 1))
		RingQueue.leave(queue, C)
		RingQueue.updateDeadlines(queue, 21, 45)
		check("and goes away when they stop waiting", deadline(queue, 1) == nil)
		RingQueue.finish(queue, 1)
		RingQueue.join(queue, D, "bot", 2, 22)
		RingQueue.start(queue, 23)
		RingQueue.updateDeadlines(queue, 24, 45)
		check("a bot match gets no deadline", deadline(queue, 1) == nil)
	end

	-- In the hall, practice fills the pits before the main ring, in line order.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "bot", 2, 1)
		RingQueue.join(queue, B, "training", 0, 2)
		RingQueue.join(queue, C, "bot", 1, 3)
		RingQueue.join(queue, D, "bot", 3, 4)
		local first = RingQueue.start(queue, 5)
		check(
			"practice goes to the pits first, then the main ring",
			started(first) == "2=bot:101 3=training:202 1=bot:303",
			started(first)
		)
		check("whoever does not fit keeps waiting", #queue.entries == 1 and (RingQueue.find(queue, D)) ~= nil)
		local session = RingQueue.sessionOf(queue, B)
		check("a player's session says which ring it is in", session ~= nil and session.ring == PIT2)
		check(
			"the waiting player would get whichever ring frees",
			RingQueue.waitingFor(queue, MAIN)
				and RingQueue.waitingFor(queue, PIT1)
				and RingQueue.waitingFor(queue, PIT2)
		)
		check(
			"so no ring offers a rematch",
			not RingQueue.canRematch(queue, MAIN) and not RingQueue.canRematch(queue, PIT1)
		)
		RingQueue.finish(queue, PIT1)
		local second = RingQueue.start(queue, 6)
		check("a freed pit goes to the next in line", started(second) == "2=bot:404", started(second))
		check(
			"with the line empty, the rematches open again",
			RingQueue.canRematch(queue, MAIN) and RingQueue.canRematch(queue, PIT1)
		)
	end

	-- A 1v1 takes the main ring before practice that joined earlier, and never a pit.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "bot", 2, 1)
		RingQueue.join(queue, B, "bot", 2, 2)
		RingQueue.start(queue, 3)
		RingQueue.join(queue, C, "training", 0, 4)
		RingQueue.join(queue, D, "versus", 0, 5)
		RingQueue.join(queue, E, "versus", 0, 6)
		local pair = RingQueue.start(queue, 7)
		check("a pair takes the main ring before earlier practice", started(pair) == "1=versus:404,505", started(pair))
		check("the practice player waits for a pit", not RingQueue.inSession(queue, C) and ahead(queue, C) == 0)
		check("practice waiting would take the main ring, so no rematch there", not RingQueue.canRematch(queue, MAIN))
		RingQueue.finish(queue, PIT1)
		local freed = RingQueue.start(queue, 8)
		check("a freed pit goes to the practice player", started(freed) == "2=training:303", started(freed))
		check("and the pair may have its rematch", RingQueue.canRematch(queue, MAIN))
	end

	-- A pair waits for the main ring even with a pit free, and does not hold up the pits.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "versus", 0, 1)
		RingQueue.join(queue, B, "versus", 0, 2)
		RingQueue.start(queue, 3)
		RingQueue.join(queue, C, "versus", 0, 4)
		RingQueue.join(queue, D, "versus", 0, 5)
		check("a waiting pair takes no pit", #RingQueue.start(queue, 6) == 0)
		local first, partner = RingQueue.nextFor(queue, MAIN)
		check(
			"the pair is next for the main ring",
			first ~= nil and first.id == C and partner ~= nil and partner.id == D
		)
		check("so the main ring offers no rematch", not RingQueue.canRematch(queue, MAIN))
		check("nobody is waiting for a pit", not RingQueue.waitingFor(queue, PIT1))
		RingQueue.join(queue, E, "bot", 1, 7)
		local practice = RingQueue.start(queue, 8)
		check("practice behind the pair goes straight to a pit", started(practice) == "2=bot:505", started(practice))
		check("and its bot match may have a rematch", RingQueue.canRematch(queue, PIT1))
		RingQueue.finish(queue, MAIN)
		local main = RingQueue.start(queue, 9)
		check("the main ring goes to the pair", started(main) == "1=versus:303,404", started(main))
	end

	-- A place in line counts the players ahead who want the same kind of fight.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "versus", 0, 1)
		RingQueue.join(queue, B, "bot", 1, 2)
		RingQueue.join(queue, C, "versus", 0, 3)
		RingQueue.join(queue, D, "training", 0, 4)
		check("a 1v1 counts the 1v1 players ahead", ahead(queue, C) == 1)
		check("practice counts the practice ahead", ahead(queue, D) == 1)
		check("the first of each kind is at the front", ahead(queue, A) == 0 and ahead(queue, B) == 0)
	end

	-- Leaving the game ends the session in your ring and no other.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "bot", 1, 1)
		RingQueue.join(queue, B, "training", 0, 2)
		RingQueue.start(queue, 3)
		local ended = RingQueue.remove(queue, B)
		check("leaving ends the session in your ring", ended ~= nil and ended.ring == PIT2, ids(ended))
		check("and only that one", queue.sessions[PIT1] ~= nil and queue.sessions[PIT2] == nil)
	end

	-- With several training sessions, the ones that have run longest make room, one per player waiting.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "training", 0, 1)
		RingQueue.join(queue, B, "training", 0, 1)
		RingQueue.start(queue, 1)
		-- The first pit's player leaves and someone else trains there, so the second pit's session is the older one.
		RingQueue.finish(queue, PIT1)
		RingQueue.join(queue, C, "training", 0, 5)
		RingQueue.start(queue, 5)
		RingQueue.join(queue, A, "bot", 2, 6)
		RingQueue.start(queue, 6)
		RingQueue.updateDeadlines(queue, 7, 45)
		check(
			"with nobody waiting, no training has a deadline",
			deadline(queue, PIT1) == nil and deadline(queue, PIT2) == nil
		)
		RingQueue.join(queue, D, "bot", 1, 8)
		RingQueue.updateDeadlines(queue, 9, 45)
		check(
			"one player waiting cuts short only the longest training",
			deadline(queue, PIT2) == 54 and deadline(queue, PIT1) == nil,
			`{deadline(queue, PIT1)} {deadline(queue, PIT2)}`
		)
		check("a bot match is never cut short", deadline(queue, MAIN) == nil)
		RingQueue.join(queue, E, "training", 0, 10)
		RingQueue.updateDeadlines(queue, 11, 45)
		check(
			"a second player waiting cuts short the next",
			deadline(queue, PIT2) == 54 and deadline(queue, PIT1) == 56,
			`{deadline(queue, PIT1)} {deadline(queue, PIT2)}`
		)
		RingQueue.leave(queue, E)
		RingQueue.updateDeadlines(queue, 12, 45)
		check(
			"and that deadline goes when they stop waiting",
			deadline(queue, PIT2) == 54 and deadline(queue, PIT1) == nil,
			`{deadline(queue, PIT1)} {deadline(queue, PIT2)}`
		)
	end

	-- A pair can only fight in the main ring, so training there makes room for it, even when the pits' is older.
	do
		local queue = RingQueue.new(HALL)
		RingQueue.join(queue, A, "training", 0, 1)
		RingQueue.join(queue, B, "training", 0, 1)
		RingQueue.start(queue, 1)
		RingQueue.join(queue, C, "training", 0, 2)
		RingQueue.start(queue, 2)
		RingQueue.join(queue, D, "versus", 0, 3)
		RingQueue.join(queue, E, "versus", 0, 4)
		RingQueue.updateDeadlines(queue, 5, 45)
		check("a waiting pair cuts short training in the main ring", deadline(queue, MAIN) == 50, deadline(queue, MAIN))
		check(
			"and not in the pits, where it cannot fight",
			deadline(queue, PIT1) == nil and deadline(queue, PIT2) == nil
		)
	end

	return passed, failures
end
