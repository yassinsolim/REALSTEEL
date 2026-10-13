--!strict

-- Who gets which ring next. THE FOUNDRY has several rings: the main ring in the middle of the hall and the practice pits
-- beside it. Players queue for a fight, not for a ring, and the line hands every free ring to whoever should have it. Pure
-- and deterministic like the fight rules: ids are numbers (the players' UserIds) and times are seconds, so the server can
-- keep one of these and the rules can be tested without Roblox.
--
-- The rules:
--   * A 1v1 needs two players: the two earliest waiting 1v1 players pair up and take a free ring that hosts 1v1s. A lone
--     1v1 waiter holds up nobody. Two players who ask for a 1v1 together (on the 1V1 pads) are a pair already: they
--     fight each other, and take their place in line where the later of the two stands.
--   * A bot match or a training session starts as soon as a ring that hosts it is free, in line order. Free rings are
--     handed out by rank, so practice fills the pits before it takes the main ring.
--   * Pairs are placed before practice, because practice can go to several rings and a 1v1 only to the ones that host it.
--   * Whoever is in a ring may ask for a rematch only while nobody waiting would get that ring.
--   * Training has no end of its own. Once someone waiting could take its ring it gets a deadline; when several sessions
--     could make room, the one that has run longest does.

local RingQueue = {}

export type Mode = "bot" | "training" | "versus"

-- What a ring hosts.
export type Rule = {
	versus: boolean,
	-- Bot matches and training.
	solo: boolean,
	-- Of the free rings that host practice, the lowest rank is handed out first (and the lowest index of equal ranks).
	rank: number,
}

export type Entry = {
	id: number,
	mode: Mode,
	-- The bot's level for a bot match, 0 otherwise.
	level: number,
	-- When the player joined the line; changing the mode keeps the place.
	since: number,
	-- For a 1v1 asked for together with someone (see joinPair): who that is. Nil for everyone else.
	partner: number?,
}

export type Session = {
	-- The ring it is in.
	ring: number,
	mode: Mode,
	-- The players in the ring, in seat order.
	ids: { number },
	level: number,
	startedAt: number,
	-- When the ring has to be handed over, or nil while nobody is waiting for it.
	deadline: number?,
}

export type Queue = {
	rules: { Rule },
	entries: { Entry },
	-- The session in each ring, by ring index.
	sessions: { [number]: Session },
}

-- A ring handed out: who gets it, and their 1v1 partner.
type Placement = {
	ring: number,
	first: Entry,
	partner: Entry?,
}

function RingQueue.new(rules: { Rule }): Queue
	return { rules = rules, entries = {}, sessions = {} }
end

local function indexOf(queue: Queue, id: number): number?
	for index, entry in queue.entries do
		if entry.id == id then
			return index
		end
	end
	return nil
end

-- The session a player is in, or nil.
function RingQueue.sessionOf(queue: Queue, id: number): Session?
	for _, session in queue.sessions do
		if table.find(session.ids, id) ~= nil then
			return session
		end
	end
	return nil
end

-- Whether a player is in a ring now.
function RingQueue.inSession(queue: Queue, id: number): boolean
	return RingQueue.sessionOf(queue, id) ~= nil
end

-- The player's place in line: their entry and how many players ahead of them want the same kind of fight (a 1v1, or
-- practice), or nil when they are not in line.
function RingQueue.find(queue: Queue, id: number): (Entry?, number)
	local index = indexOf(queue, id)
	if index == nil then
		return nil, 0
	end
	local entry = queue.entries[index]
	local ahead = 0
	for other = 1, index - 1 do
		if (queue.entries[other].mode == "versus") == (entry.mode == "versus") then
			ahead += 1
		end
	end
	return entry, ahead
end

-- Takes a player's partner, if they have one, off them: the partner keeps waiting for a 1v1 with anyone.
local function unpair(queue: Queue, entry: Entry)
	local partner = entry.partner
	entry.partner = nil
	if partner == nil then
		return
	end
	local other = indexOf(queue, partner)
	if other ~= nil and queue.entries[other].partner == entry.id then
		queue.entries[other].partner = nil
	end
end

-- Puts a player in line, or changes what they are waiting for without losing their place. Someone already in a ring
-- cannot queue. Asking for anything but a 1v1 leaves a pair (see joinPair). Returns whether anything changed.
function RingQueue.join(queue: Queue, id: number, mode: Mode, level: number, now: number): boolean
	if RingQueue.inSession(queue, id) then
		return false
	end
	local index = indexOf(queue, id)
	local wanted = if mode == "bot" then level else 0
	if index ~= nil then
		local entry = queue.entries[index]
		if entry.mode == mode and entry.level == wanted then
			return false
		end
		unpair(queue, entry)
		entry.mode = mode
		entry.level = wanted
		return true
	end
	table.insert(queue.entries, { id = id, mode = mode, level = wanted, since = now, partner = nil })
	return true
end

-- Puts two players in line together for a 1v1 against each other: `first` takes the first seat. They leave whatever place
-- they had, and go to the back together; two who are already a pair keep their place, in the seats asked for now.
-- Nobody in a ring can pair up. Returns whether anything changed.
function RingQueue.joinPair(queue: Queue, first: number, second: number, now: number): boolean
	if first == second or RingQueue.inSession(queue, first) or RingQueue.inSession(queue, second) then
		return false
	end
	local firstIndex = indexOf(queue, first)
	local secondIndex = indexOf(queue, second)
	if
		firstIndex ~= nil
		and secondIndex ~= nil
		and queue.entries[firstIndex].partner == second
		and queue.entries[secondIndex].partner == first
	then
		if firstIndex < secondIndex then
			return false
		end
		-- The seats swap; the pair's place in line stays the later member's.
		local entries = queue.entries
		entries[firstIndex], entries[secondIndex] = entries[secondIndex], entries[firstIndex]
		return true
	end
	RingQueue.leave(queue, first)
	RingQueue.leave(queue, second)
	table.insert(queue.entries, { id = first, mode = "versus", level = 0, since = now, partner = second })
	table.insert(queue.entries, { id = second, mode = "versus", level = 0, since = now, partner = first })
	return true
end

-- Takes a player out of line; a partner they had waits on for anyone. Returns whether they were in it.
function RingQueue.leave(queue: Queue, id: number): boolean
	local index = indexOf(queue, id)
	if index == nil then
		return false
	end
	unpair(queue, queue.entries[index])
	table.remove(queue.entries, indexOf(queue, id) :: number)
	return true
end

local function freeRings(queue: Queue): { [number]: boolean }
	local free: { [number]: boolean } = {}
	for index in queue.rules do
		free[index] = queue.sessions[index] == nil
	end
	return free
end

-- The 1v1s the line would start, in the order they became possible: each pair that asked together, once the later of
-- the two is in line, and the waiting singles two by two, earliest first.
local function versusUnits(queue: Queue): { { Entry } }
	local units: { { Entry } } = {}
	local waiting: Entry? = nil
	for index, entry in queue.entries do
		if entry.mode == "versus" then
			local other = if entry.partner ~= nil then indexOf(queue, entry.partner) else nil
			if other ~= nil and queue.entries[other].partner == entry.id then
				if other < index then
					table.insert(units, { queue.entries[other], entry })
				end
			elseif waiting == nil then
				waiting = entry
			else
				table.insert(units, { waiting, entry })
				waiting = nil
			end
		end
	end
	return units
end

-- Who would get which of the `free` rings. `order` ranks the free rings that host practice, lowest first; without it
-- each ring's own rank does.
local function plan(queue: Queue, free: { [number]: boolean }, order: ((ring: number) -> number)?): { Placement }
	local placements: { Placement } = {}
	local open = table.clone(free)

	-- 1v1s, in the order they became possible, to the free rings that host them in ring order.
	for _, unit in versusUnits(queue) do
		local ring: number? = nil
		for index, rule in queue.rules do
			if open[index] and rule.versus then
				ring = index
				break
			end
		end
		if ring == nil then
			break
		end
		open[ring] = false
		table.insert(placements, { ring = ring, first = unit[1], partner = unit[2] })
	end

	-- Practice in line order, each to the best free ring that hosts it.
	for _, entry in queue.entries do
		if entry.mode ~= "versus" then
			local best: number? = nil
			local bestRank = math.huge
			for index, rule in queue.rules do
				if open[index] and rule.solo then
					local rank = if order ~= nil then order(index) else rule.rank
					if rank < bestRank then
						best = index
						bestRank = rank
					end
				end
			end
			if best == nil then
				break
			end
			open[best] = false
			table.insert(placements, { ring = best, first = entry, partner = nil })
		end
	end
	return placements
end

-- Who would get `ring` if it were handed over now: the first player and their 1v1 partner, or nil.
function RingQueue.nextFor(queue: Queue, ring: number): (Entry?, Entry?)
	local free = freeRings(queue)
	free[ring] = true
	for _, placement in plan(queue, free, nil) do
		if placement.ring == ring then
			return placement.first, placement.partner
		end
	end
	return nil, nil
end

-- Whether someone in line would get `ring` if it were handed over now.
function RingQueue.waitingFor(queue: Queue, ring: number): boolean
	return (RingQueue.nextFor(queue, ring)) ~= nil
end

-- Whether a player waiting for a 1v1 has nobody to fight yet: no partner, and no other single waiting with them.
function RingQueue.alone(queue: Queue, id: number): boolean
	local index = indexOf(queue, id)
	if index == nil or queue.entries[index].mode ~= "versus" then
		return false
	end
	for _, unit in versusUnits(queue) do
		if unit[1].id == id or unit[2].id == id then
			return false
		end
	end
	return true
end

-- Hands every free ring to whoever should have it. Returns the sessions that started, in the order they were placed.
function RingQueue.start(queue: Queue, now: number): { Session }
	local started: { Session } = {}
	for _, placement in plan(queue, freeRings(queue), nil) do
		local ids = { placement.first.id }
		local partner = placement.partner
		if partner ~= nil then
			table.insert(ids, partner.id)
		end
		for _, id in ids do
			RingQueue.leave(queue, id)
		end
		local session: Session = {
			ring = placement.ring,
			mode = placement.first.mode,
			ids = ids,
			level = placement.first.level,
			startedAt = now,
			deadline = nil,
		}
		queue.sessions[placement.ring] = session
		table.insert(started, session)
	end
	return started
end

-- Ends the session in a ring and returns it.
function RingQueue.finish(queue: Queue, ring: number): Session?
	local session = queue.sessions[ring]
	queue.sessions[ring] = nil
	return session
end

-- A player left the game: they leave the line, and if they were in a ring its session ends. Returns the ended session.
function RingQueue.remove(queue: Queue, id: number): Session?
	RingQueue.leave(queue, id)
	local session = RingQueue.sessionOf(queue, id)
	if session ~= nil then
		return RingQueue.finish(queue, session.ring)
	end
	return nil
end

-- A rematch keeps the ring, so it is only offered while nobody waiting would get it. Training restarts on its own.
function RingQueue.canRematch(queue: Queue, ring: number): boolean
	local session = queue.sessions[ring]
	return session ~= nil and session.mode ~= "training" and not RingQueue.waitingFor(queue, ring)
end

-- Gives a training session a deadline `grace` seconds from now once someone waiting could take its ring, and takes it
-- away again when nobody could. When there are fewer players waiting than training sessions they could replace, the
-- sessions that have run longest make room.
function RingQueue.updateDeadlines(queue: Queue, now: number, grace: number)
	local free = freeRings(queue)
	local training: { [number]: boolean } = {}
	for ring, session in queue.sessions do
		if session.mode == "training" then
			free[ring] = true
			training[ring] = true
		end
	end
	-- A ring that is free already is handed out before any training is cut short, and older sessions before newer ones.
	local placements = plan(queue, free, function(ring: number): number
		local session = queue.sessions[ring]
		return if session == nil then -math.huge else session.startedAt
	end)
	local yielding: { [number]: boolean } = {}
	for _, placement in placements do
		if training[placement.ring] then
			yielding[placement.ring] = true
		end
	end
	for ring, session in queue.sessions do
		if not yielding[ring] then
			session.deadline = nil
		elseif session.deadline == nil then
			session.deadline = now + grace
		end
	end
end

return RingQueue
