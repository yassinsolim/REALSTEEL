--!strict

-- Pure rules for what fighters have to show for their fights: each one's record (1v1 wins and losses, and wins and losses
-- against each bot level), the champion's title, which only changes hands in a 1v1, and the order of a leaderboard. No
-- Roblox APIs, so the server keeps these and the rules can be tested without a place.
--
-- The title:
--   * While it is vacant, the winner of any 1v1 claims it.
--   * The champion who wins a 1v1 defends it; the one who loses hands it to the winner.
--   * A 1v1 between two other players leaves it where it is.
--   * It falls vacant when the champion leaves.

local Standings = {}

-- Bot levels, EASY to HARD (see BotBrain).
local BOT_LEVELS = 3
-- Saved counts are clamped to this, so a damaged save cannot put absurd numbers on a board.
local MAX_COUNT = 10_000_000
local SAVE_VERSION = 1
-- How many servers' batches of results a saved record keeps track of (see hasBatch).
Standings.SessionMemory = 64

-- The latest batch of results one server added to a saved record.
export type Mark = {
	-- The server, and the number of its batch.
	s: string,
	n: number,
}

export type Record = {
	versusWins: number,
	versusLosses: number,
	-- By bot level.
	botWins: { number },
	botLosses: { number },
}

export type Title = {
	-- The champion's UserId, or 0 while the title is vacant.
	holder: number,
	-- 1v1s the champion has won since taking the title.
	defenses: number,
}

-- What a finished 1v1 did to the title.
export type TitleChange = "claimed" | "taken" | "defended" | "none"

-- A line on a leaderboard.
export type Entry = {
	id: number,
	name: string,
	score: number,
}

function Standings.newRecord(): Record
	local botWins: { number } = {}
	local botLosses: { number } = {}
	for level = 1, BOT_LEVELS do
		botWins[level] = 0
		botLosses[level] = 0
	end
	return { versusWins = 0, versusLosses = 0, botWins = botWins, botLosses = botLosses }
end

local function count(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_COUNT)
end

-- A record from whatever a DataStore handed back; anything missing or broken reads as zero.
function Standings.sanitize(data: unknown): Record
	local record = Standings.newRecord()
	if type(data) ~= "table" then
		return record
	end
	local source = data :: { [string]: unknown }
	record.versusWins = count(source.vw)
	record.versusLosses = count(source.vl)
	for level = 1, BOT_LEVELS do
		record.botWins[level] = count(source["bw" .. level])
		record.botLosses[level] = count(source["bl" .. level])
	end
	return record
end

function Standings.toSaved(record: Record): { [string]: number }
	local saved: { [string]: number } = { v = SAVE_VERSION, vw = record.versusWins, vl = record.versusLosses }
	for level = 1, BOT_LEVELS do
		saved["bw" .. level] = record.botWins[level]
		saved["bl" .. level] = record.botLosses[level]
	end
	return saved
end

-- The latest batch each server added to a saved record, the server that wrote last at the end.
local function batchMarks(data: unknown): { Mark }
	local marks: { Mark } = {}
	if type(data) ~= "table" then
		return marks
	end
	local list = (data :: { [string]: unknown }).batches
	if type(list) ~= "table" then
		return marks
	end
	local items = list :: { unknown }
	for index = 1, math.min(#items, Standings.SessionMemory) do
		local item = items[index]
		if type(item) == "table" then
			local mark = item :: { [string]: unknown }
			local session, sequence = mark.s, mark.n
			if type(session) == "string" and type(sequence) == "number" then
				table.insert(marks, { s = session, n = sequence })
			end
		end
	end
	return marks
end

-- Whether batch number `sequence` of server `session` has already been added to the saved record `data`. A save whose
-- reply was lost may have landed after all; tried again, it is recognized here, however many batches other servers have
-- added since. Each server numbers its batches in order and writes one player's one at a time, so the record only needs
-- each server's latest number, and it keeps the last SessionMemory servers: far more than one player can write from
-- while a save is being tried again.
function Standings.hasBatch(data: unknown, session: string, sequence: number): boolean
	for _, mark in batchMarks(data) do
		if mark.s == session then
			return mark.n >= sequence
		end
	end
	return false
end

-- What a saved record keeps track of once batch `sequence` of server `session` is added to `data`.
function Standings.withBatch(data: unknown, session: string, sequence: number): { Mark }
	local marks = batchMarks(data)
	local latest = sequence
	for index, mark in marks do
		if mark.s == session then
			latest = math.max(latest, mark.n)
			table.remove(marks, index)
			break
		end
	end
	table.insert(marks, { s = session, n = latest })
	while #marks > Standings.SessionMemory do
		table.remove(marks, 1)
	end
	return marks
end

-- Adds `extra` onto `into`: one batch of results onto a stored record, or what has not been written yet onto what has.
function Standings.merge(into: Record, extra: Record)
	into.versusWins = math.min(into.versusWins + extra.versusWins, MAX_COUNT)
	into.versusLosses = math.min(into.versusLosses + extra.versusLosses, MAX_COUNT)
	for level = 1, BOT_LEVELS do
		into.botWins[level] = math.min(into.botWins[level] + extra.botWins[level], MAX_COUNT)
		into.botLosses[level] = math.min(into.botLosses[level] + extra.botLosses[level], MAX_COUNT)
	end
end

function Standings.copy(record: Record): Record
	local copy = Standings.newRecord()
	Standings.merge(copy, record)
	return copy
end

-- Whether a record counts nothing at all.
function Standings.isEmpty(record: Record): boolean
	if record.versusWins ~= 0 or record.versusLosses ~= 0 then
		return false
	end
	for level = 1, BOT_LEVELS do
		if record.botWins[level] ~= 0 or record.botLosses[level] ~= 0 then
			return false
		end
	end
	return true
end

function Standings.recordVersus(winner: Record, loser: Record)
	winner.versusWins = math.min(winner.versusWins + 1, MAX_COUNT)
	loser.versusLosses = math.min(loser.versusLosses + 1, MAX_COUNT)
end

-- A bot match at `level` (1 to 3) ended. Other levels are ignored.
function Standings.recordBot(record: Record, level: number, won: boolean)
	if level < 1 or level > BOT_LEVELS or level ~= math.floor(level) then
		return
	end
	if won then
		record.botWins[level] = math.min(record.botWins[level] + 1, MAX_COUNT)
	else
		record.botLosses[level] = math.min(record.botLosses[level] + 1, MAX_COUNT)
	end
end

function Standings.newTitle(): Title
	return { holder = 0, defenses = 0 }
end

-- A 1v1 between `winner` and `loser` (UserIds) ended. Returns what it did to the title.
function Standings.settleTitle(title: Title, winner: number, loser: number): TitleChange
	if winner == loser or winner == 0 then
		return "none"
	end
	if title.holder == 0 then
		title.holder = winner
		title.defenses = 0
		return "claimed"
	elseif title.holder == winner then
		title.defenses += 1
		return "defended"
	elseif title.holder == loser then
		title.holder = winner
		title.defenses = 0
		return "taken"
	end
	return "none"
end

-- The player `id` left. Returns whether the title fell vacant.
function Standings.vacate(title: Title, id: number): boolean
	if id ~= 0 and title.holder == id then
		title.holder = 0
		title.defenses = 0
		return true
	end
	return false
end

-- The best `size` entries with a score above zero: highest score first, then by name, then by id, so the order never
-- depends on the order the entries came in.
function Standings.rank(entries: { Entry }, size: number): { Entry }
	local kept: { Entry } = {}
	for _, entry in entries do
		if entry.score > 0 then
			table.insert(kept, entry)
		end
	end
	table.sort(kept, function(a: Entry, b: Entry): boolean
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	local top: { Entry } = {}
	for index = 1, math.min(size, #kept) do
		top[index] = kept[index]
	end
	return top
end

return Standings
