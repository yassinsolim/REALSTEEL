--!strict

-- Who stands on which pad in front of the main ring, and when a pad's countdown runs out (see FoundryLayout.Pads). Pure
-- like RingQueue: ids are UserIds, times seconds and positions plain numbers on the hall floor, so the server keeps one
-- board and the rules can be tested without Roblox.
--
-- The rules:
--   * A pad belongs to one player at a time: of those standing on it, the one who stepped on first. A player in a ring
--     holds no pad.
--   * A bot or training pad counts down from the moment its player steps on; stepping off before it runs out cancels.
--   * The two 1V1 pads count down together once a different player stands on each; either one stepping off cancels.
--   * Once a pad's countdown has run out it has done its job for whoever was on it: they hold it no longer, so the next
--     player can use it, until they step off and on again.

local PadRules = {}

export type Kind = "versus" | "bot" | "training"

export type PadSpec = {
	name: string,
	kind: Kind,
	-- The bot's level on a bot pad.
	level: number,
	-- The seat a 1V1 pad's player takes (1 or 2).
	seat: number,
	x: number,
	z: number,
}

-- A player in the hall: where their character stands, and whether they may take a pad (not in a ring).
export type Presence = {
	id: number,
	x: number,
	z: number,
	free: boolean,
}

export type PadState = {
	-- The player on it, or 0.
	holder: number,
	-- When they stepped on.
	since: number,
}

export type Board = {
	pads: { PadSpec },
	radius: number,
	soloDelay: number,
	pairDelay: number,
	state: { [string]: PadState },
	-- The pad each player stands on and since when, and the pad whose countdown has already run out for them.
	standing: { [number]: { pad: string, since: number } },
	spent: { [number]: string },
	-- The two players the 1V1 pads are counting down for ("first:second"), and since when.
	pairKey: string?,
	pairSince: number,
}

-- A countdown that ran out: what it asks for, and for whom (a 1v1's two players in seat order).
export type Trigger = {
	kind: Kind,
	level: number,
	ids: { number },
}

function PadRules.new(pads: { PadSpec }, radius: number, soloDelay: number, pairDelay: number): Board
	local state: { [string]: PadState } = {}
	for _, pad in pads do
		state[pad.name] = { holder = 0, since = 0 }
	end
	return {
		pads = pads,
		radius = radius,
		soloDelay = soloDelay,
		pairDelay = pairDelay,
		state = state,
		standing = {},
		spent = {},
		pairKey = nil,
		pairSince = 0,
	}
end

local function padAt(board: Board, x: number, z: number): PadSpec?
	for _, pad in board.pads do
		local dx, dz = x - pad.x, z - pad.z
		if dx * dx + dz * dz <= board.radius * board.radius then
			return pad
		end
	end
	return nil
end

-- The two 1V1 pads, by seat.
local function versusPads(board: Board): (PadSpec?, PadSpec?)
	local first, second = nil, nil
	for _, pad in board.pads do
		if pad.kind == "versus" then
			if pad.seat == 1 then
				first = pad
			elseif pad.seat == 2 then
				second = pad
			end
		end
	end
	return first, second
end

-- Reads where everyone stands now, and returns the countdowns that ran out.
function PadRules.update(board: Board, presences: { Presence }, now: number): { Trigger }
	-- Where each free player stands. Stepping off a pad, or onto another, starts over.
	local present: { [number]: boolean } = {}
	for _, presence in presences do
		local pad = if presence.free then padAt(board, presence.x, presence.z) else nil
		local id = presence.id
		present[id] = true
		local standing = board.standing[id]
		if pad == nil then
			board.standing[id] = nil
		elseif standing == nil or standing.pad ~= pad.name then
			board.standing[id] = { pad = pad.name, since = now }
		end
		local current = board.standing[id]
		if board.spent[id] ~= nil and (current == nil or current.pad ~= board.spent[id]) then
			board.spent[id] = nil
		end
	end
	for id in board.standing do
		if not present[id] then
			board.standing[id] = nil
		end
	end
	for id in board.spent do
		if not present[id] then
			board.spent[id] = nil
		end
	end

	-- Each pad's holder: whoever has stood on it longest, its countdown not yet spent on them.
	for _, pad in board.pads do
		local holder, since = 0, math.huge
		for id, standing in board.standing do
			if standing.pad == pad.name and board.spent[id] ~= pad.name then
				if standing.since < since or (standing.since == since and id < holder) then
					holder, since = id, standing.since
				end
			end
		end
		local padState = board.state[pad.name]
		padState.holder = holder
		padState.since = if holder ~= 0 then since else 0
	end

	local triggers: { Trigger } = {}
	for _, pad in board.pads do
		local padState = board.state[pad.name]
		if pad.kind ~= "versus" and padState.holder ~= 0 and now - padState.since >= board.soloDelay then
			table.insert(triggers, { kind = pad.kind, level = pad.level, ids = { padState.holder } })
			board.spent[padState.holder] = pad.name
			padState.holder, padState.since = 0, 0
		end
	end

	local first, second = versusPads(board)
	local firstHolder = if first ~= nil then board.state[first.name].holder else 0
	local secondHolder = if second ~= nil then board.state[second.name].holder else 0
	if first ~= nil and second ~= nil and firstHolder ~= 0 and secondHolder ~= 0 and firstHolder ~= secondHolder then
		local key = `{firstHolder}:{secondHolder}`
		if board.pairKey ~= key then
			board.pairKey = key
			board.pairSince = now
		elseif now - board.pairSince >= board.pairDelay then
			table.insert(triggers, { kind = "versus", level = 0, ids = { firstHolder, secondHolder } })
			board.spent[firstHolder] = first.name
			board.spent[secondHolder] = second.name
			board.state[first.name].holder, board.state[first.name].since = 0, 0
			board.state[second.name].holder, board.state[second.name].since = 0, 0
			board.pairKey = nil
		end
	else
		board.pairKey = nil
	end
	return triggers
end

-- Seconds left on a pad's countdown, or nil when it is not counting down: a bot or training pad while someone holds
-- it, and the 1V1 pads while both are held.
function PadRules.countdown(board: Board, name: string, now: number): number?
	local padState = board.state[name]
	if padState == nil or padState.holder == 0 then
		return nil
	end
	for _, pad in board.pads do
		if pad.name == name then
			if pad.kind ~= "versus" then
				return math.max(board.soloDelay - (now - padState.since), 0)
			elseif board.pairKey ~= nil then
				return math.max(board.pairDelay - (now - board.pairSince), 0)
			end
			return nil
		end
	end
	return nil
end

return PadRules
