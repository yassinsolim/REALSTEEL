--!strict

-- Server: every player's record, the champion's title and the leaderboards made from them (see Standings for the rules).
--
-- Records are saved as additions, not as totals: each save takes what a player has won since the last one and adds it to
-- the stored record inside one UpdateAsync, so two servers (or two saves) can never write an older total over a newer
-- one, and results count even when the stored record could not be read first. Each server numbers its batches, a batch
-- keeps its number until it lands, and the stored record keeps the latest number each server added (see
-- Standings.hasBatch), so a retry whose earlier attempt landed after all is not added twice, whatever other servers wrote
-- meanwhile. The all-time boards are ordered DataStores that only ever go up; a player's scores are put on them after
-- every write of their record, again until they land, and once more when the player joins, in case a server stopped
-- between the two. Where DataStores cannot be reached (Studio before the place is published) the boards rank the players
-- in the server instead.
--
-- What the clients show is published on `state` (FoundryState), as attributes:
--   ChampionId, ChampionName, ChampionDefenses   the title (0, "" and 0 while it is vacant)
--   BoardScope                                    "ALL TIME", or "THIS SERVER" while the all-time boards are out of reach
-- and as StringValues, since a replicated attribute holds at most 50 characters in a place with server authority:
--   BoardVersus, BoardBots                        JSON lists of { id, name, score }, best first: 1v1 wins, HARD bot wins
-- and on each Player: RecordWins and RecordLosses (1v1s) and RecordHardWins.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Standings = require(ReplicatedStorage.Shared.Standings)

local STORE_NAME = "RealSteelRecords1"
local VERSUS_BOARD = "RealSteelVersusWins1"
local BOTS_BOARD = "RealSteelHardBotWins1"
local HARD = 3
-- A player's results are written at most this often while they stay, and at once when they leave.
local SAVE_DELAY = 15
local BOARD_REFRESH = 60
local BOARD_SIZE = 10
local LOAD_ATTEMPTS = 3
local NAME_LENGTH = 16
-- How long the server waits for the last saves when it shuts down (it has 30 seconds in all), and how often it tries each
-- one; and how many failed writes a player who left is given before their unsaved results are dropped.
local SHUTDOWN_WAIT = 20
local SHUTDOWN_TRIES = 3
local DEPARTED_TRIES = 12
-- How long a player who left is kept at least, so a result that comes in just after they left still counts (see Rings,
-- which waits a few seconds before a 1v1 left by dropping out of the game counts).
local KEEP_AFTER_LEAVING = 15

-- Results on their way to the store: what is added, and the number that recognizes it once it has landed.
type Batch = {
	delta: Standings.Record,
	sequence: number,
}

type Profile = {
	userId: number,
	name: string,
	-- The player while they are in the server; nil once they left and only their last results are still being written.
	player: Player?,
	-- When they left.
	leftAt: number,
	-- The record as last read or written, the batch being written, and what was won since.
	base: Standings.Record,
	batch: Batch?,
	pending: Standings.Record,
	-- Whether `base` came from a write, which is newer than any read still on its way.
	committed: boolean,
	saving: boolean,
	lastSave: number,
	-- Writes that failed in a row.
	failures: number,
	-- The scores last put on each board (0 until they have been), so an unchanged one is not written again.
	boardVersus: number,
	boardBots: number,
}

export type MatchResult = {
	-- "bot" or "versus". Training and exhibitions are nobody's to show for.
	mode: string,
	-- The bot's level in a bot match.
	level: number,
	-- The players in the seats; an empty seat is the bot.
	owners: { [number]: Player? },
	-- The seat that won.
	winner: number,
}

export type Records = {
	add: (player: Player) -> (),
	-- Never yields: the player's last results are written in the background.
	remove: (player: Player) -> (),
	-- Call once for each match in a ring that reaches its end (or is forfeited), also when a player in it has just left.
	-- Never yields.
	matchEnded: (result: MatchResult) -> (),
	-- Reads the boards and publishes them. It also runs every minute by itself.
	refresh: () -> (),
	-- Writes every unsaved result and waits (up to SHUTDOWN_WAIT) until they have landed; the server calls it as it shuts
	-- down.
	saveAll: () -> (),
	-- For checks: a player's record as shown.
	recordOf: (player: Player) -> Standings.Record?,
	-- Stops the background work. The server never needs it; checks do.
	destroy: () -> (),
}

-- For checks: stand-ins for the record store (GetAsync, UpdateAsync) and the two board stores (UpdateAsync,
-- GetSortedAsync), a name lookup for players who are not in the server, whether the background loops run, how long a
-- failed read waits before it is tried again, and the name of this server in its batches. With them the module touches
-- nothing outside itself.
export type Options = {
	store: any?,
	versusBoard: any?,
	botsBoard: any?,
	nameOf: ((id: number) -> string)?,
	background: boolean?,
	retryDelay: number?,
	session: string?,
}

local Records = {}

local warned = false
local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[REALSTEEL] Records are not saved: " .. message)
	end
end

local function open(name: string, ordered: boolean): any
	local ok, result = pcall(function(): any
		if ordered then
			return DataStoreService:GetOrderedDataStore(name)
		end
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		return result
	end
	warnOnce(tostring(result))
	return nil
end

local function shortName(name: string): string
	return string.upper(string.sub(name, 1, NAME_LENGTH))
end

function Records.new(state: Instance, options: Options?): Records
	local store: any = if options ~= nil then options.store else open(STORE_NAME, false)
	local versusBoard: any = if options ~= nil then options.versusBoard else open(VERSUS_BOARD, true)
	local botsBoard: any = if options ~= nil then options.botsBoard else open(BOTS_BOARD, true)
	local background = options == nil or options.background ~= false
	local retryDelay = if options ~= nil and options.retryDelay ~= nil then options.retryDelay else 2
	local session = if options ~= nil and options.session ~= nil
		then options.session
		else HttpService:GenerateGUID(false)
	local profiles: { [number]: Profile } = {}
	local title = Standings.newTitle()
	local names: { [number]: string } = {}
	local sequence = 0
	local running = true

	-- What a profile shows: the base with everything not yet written on top.
	local function totalOf(profile: Profile): Standings.Record
		local total = Standings.copy(profile.base)
		local batch = profile.batch
		if batch ~= nil then
			Standings.merge(total, batch.delta)
		end
		Standings.merge(total, profile.pending)
		return total
	end

	local function nameOf(id: number): string
		local profile = profiles[id]
		if profile ~= nil then
			return profile.name
		end
		local cached = names[id]
		if cached ~= nil then
			return cached
		end
		local name = "PLAYER"
		local lookup = if options ~= nil then options.nameOf else nil
		if lookup ~= nil then
			name = lookup(id)
		else
			local ok, result = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			if ok and type(result) == "string" then
				name = result
			end
		end
		names[id] = shortName(name)
		return names[id]
	end

	local function publishRecord(profile: Profile)
		local player = profile.player
		if player == nil then
			return
		end
		local total = totalOf(profile)
		player:SetAttribute("RecordWins", total.versusWins)
		player:SetAttribute("RecordLosses", total.versusLosses)
		player:SetAttribute("RecordHardWins", total.botWins[HARD])
	end

	-- The name and defenses go first, so a client never sees a new champion's id with the old champion's name.
	local function publishTitle()
		state:SetAttribute("ChampionName", if title.holder ~= 0 then nameOf(title.holder) else "")
		state:SetAttribute("ChampionDefenses", title.defenses)
		state:SetAttribute("ChampionId", title.holder)
	end

	local function encode(entries: { Standings.Entry }): string
		local list = {}
		for _, entry in entries do
			table.insert(list, { id = entry.id, name = entry.name, score = entry.score })
		end
		return HttpService:JSONEncode(list)
	end

	-- One all-time board, best first, or nil when the store cannot be read.
	local function readBoard(board: any): { Standings.Entry }?
		if board == nil then
			return nil
		end
		local ok, result = pcall(function(): any
			return board:GetSortedAsync(false, BOARD_SIZE):GetCurrentPage()
		end)
		if not ok or type(result) ~= "table" then
			if not ok then
				warnOnce(tostring(result))
			end
			return nil
		end
		local entries: { Standings.Entry } = {}
		for _, item in result do
			local id = tonumber(item.key)
			local score = item.value
			if id ~= nil and type(score) == "number" then
				table.insert(entries, { id = id, name = nameOf(id), score = score })
			end
		end
		return Standings.rank(entries, BOARD_SIZE)
	end

	-- The same boards from the records of the players in the server.
	local function serverBoards(): ({ Standings.Entry }, { Standings.Entry })
		local versus: { Standings.Entry } = {}
		local bots: { Standings.Entry } = {}
		for id, profile in profiles do
			if profile.player ~= nil then
				local total = totalOf(profile)
				table.insert(versus, { id = id, name = profile.name, score = total.versusWins })
				table.insert(bots, { id = id, name = profile.name, score = total.botWins[HARD] })
			end
		end
		return Standings.rank(versus, BOARD_SIZE), Standings.rank(bots, BOARD_SIZE)
	end

	-- A board's list, as the value of a StringValue under `state` (made the first time).
	local function boardValue(name: string): StringValue
		local existing = state:FindFirstChild(name)
		if existing ~= nil and existing:IsA("StringValue") then
			return existing
		end
		local value = Instance.new("StringValue")
		value.Name = name
		value.Parent = state
		return value
	end

	local function publishBoards(versus: { Standings.Entry }, bots: { Standings.Entry }, scope: string)
		boardValue("BoardVersus").Value = encode(versus)
		boardValue("BoardBots").Value = encode(bots)
		state:SetAttribute("BoardScope", scope)
	end

	local function refresh()
		local versus = readBoard(versusBoard)
		local bots = readBoard(botsBoard)
		if versus == nil or bots == nil then
			local hereVersus, hereBots = serverBoards()
			publishBoards(hereVersus, hereBots, "THIS SERVER")
		else
			publishBoards(versus, bots, "ALL TIME")
		end
	end

	-- Puts a score on a board, never lowering what is there (another server may have put a newer total).
	local function writeBoard(board: any, id: number, score: number): boolean
		if board == nil then
			return true
		end
		local ok, err = pcall(function()
			board:UpdateAsync(tostring(id), function(old: any): any
				local current = if type(old) == "number" then old else 0
				return if score > current then score else nil
			end)
		end)
		if not ok then
			warnOnce(tostring(err))
		end
		return ok
	end

	-- Adds a profile's unsaved results to its stored record. A batch that fails keeps its tag and is tried again as it is;
	-- results won meanwhile wait for the next batch. True when nothing is left to write.
	local function writeRecord(profile: Profile): boolean
		local batch = profile.batch
		if batch == nil then
			if Standings.isEmpty(profile.pending) then
				return true
			end
			sequence += 1
			batch = { delta = profile.pending, sequence = sequence }
			profile.pending = Standings.newRecord()
			profile.batch = batch
		end
		local current = batch :: Batch
		local written: Standings.Record? = nil
		local ok, err = pcall(function()
			store:UpdateAsync("u" .. profile.userId, function(old: any): any
				local record = Standings.sanitize(old)
				written = record
				if Standings.hasBatch(old, session, current.sequence) then
					-- This batch landed on an earlier try whose reply was lost.
					return nil
				end
				Standings.merge(record, current.delta)
				local saved: { [string]: any } = Standings.toSaved(record)
				saved.batches = Standings.withBatch(old, session, current.sequence)
				return saved
			end)
		end)
		local result = written
		if not ok or result == nil then
			if not ok then
				warnOnce(tostring(err))
			end
			return false
		end
		profile.batch = nil
		profile.base = result
		profile.committed = true
		publishRecord(profile)
		return true
	end

	-- Whether the boards may be missing a player's stored scores: a board write that failed, or a record read when they
	-- joined, whose last scores a server that stopped may never have put up.
	local function boardsBehind(profile: Profile): boolean
		return profile.boardVersus ~= profile.base.versusWins or profile.boardBots ~= profile.base.botWins[HARD]
	end

	-- Puts a player's stored scores on the boards. True when both are up.
	local function syncBoards(profile: Profile): boolean
		local versusWins = profile.base.versusWins
		local hardWins = profile.base.botWins[HARD]
		local synced = true
		if versusWins ~= profile.boardVersus then
			if writeBoard(versusBoard, profile.userId, versusWins) then
				profile.boardVersus = versusWins
			else
				synced = false
			end
		end
		if hardWins ~= profile.boardBots then
			if writeBoard(botsBoard, profile.userId, hardWins) then
				profile.boardBots = hardWins
			else
				synced = false
			end
		end
		return synced
	end

	-- Writes a profile's unsaved results and then its scores on the boards, one save at a time per profile.
	local function save(profile: Profile)
		if profile.saving or store == nil then
			return
		end
		profile.saving = true
		if writeRecord(profile) and syncBoards(profile) then
			profile.failures = 0
		else
			profile.failures += 1
		end
		profile.saving = false
		profile.lastSave = os.clock()
	end

	-- Whether a profile has anything to write: results, or scores the boards are missing.
	local function unsaved(profile: Profile): boolean
		return profile.batch ~= nil or not Standings.isEmpty(profile.pending) or boardsBehind(profile)
	end

	-- Reads the stored record so the player's totals can be shown. Saving does not depend on it.
	local function load(profile: Profile)
		local current = store
		if current == nil then
			return
		end
		for attempt = 1, LOAD_ATTEMPTS do
			local ok, data = pcall(function()
				return current:GetAsync("u" .. profile.userId)
			end)
			if ok then
				if not profile.committed then
					profile.base = Standings.sanitize(data)
					publishRecord(profile)
				end
				return
			end
			warnOnce(tostring(data))
			if attempt < LOAD_ATTEMPTS then
				task.wait(retryDelay * attempt)
			end
		end
	end

	-- A seat's profile for a result: the player's, also when they have just left (see KEEP_AFTER_LEAVING).
	local function profileFor(player: Player?): Profile?
		return if player ~= nil then profiles[player.UserId] else nil
	end

	local function profileOf(player: Player?): Profile?
		local profile = profileFor(player)
		return if profile ~= nil and profile.player == player then profile else nil
	end

	local function matchEnded(result: MatchResult)
		local winnerSeat = result.winner
		if result.mode == "versus" then
			local winner = result.owners[winnerSeat]
			local loser = result.owners[3 - winnerSeat]
			local winnerProfile = profileFor(winner)
			local loserProfile = profileFor(loser)
			if winner == nil or loser == nil or winnerProfile == nil or loserProfile == nil then
				return
			end
			Standings.recordVersus(winnerProfile.pending, loserProfile.pending)
			publishRecord(winnerProfile)
			publishRecord(loserProfile)
			-- The title only goes to a winner who is still here; one who has left could never be dethroned.
			local present = winnerProfile.player ~= nil
			if present and Standings.settleTitle(title, winner.UserId, loser.UserId) ~= "none" then
				publishTitle()
			end
		elseif result.mode == "bot" then
			for seat = 1, 2 do
				local profile = profileFor(result.owners[seat])
				if profile ~= nil then
					Standings.recordBot(profile.pending, result.level, winnerSeat == seat)
					publishRecord(profile)
				end
			end
		else
			return
		end
		-- The all-time boards catch up on their own schedule. The server's own are cheap to redo at once, and are redone
		-- without a read, so reporting a result never waits on the store.
		if state:GetAttribute("BoardScope") ~= "ALL TIME" then
			local versus, bots = serverBoards()
			publishBoards(versus, bots, "THIS SERVER")
		end
	end

	if background then
		-- Written in the background so a busy store never holds up a match. Players who left are written at once, and
		-- forgotten a little later once nothing of theirs is left unsaved (or the store has refused them for about a
		-- minute).
		task.spawn(function()
			while running do
				task.wait(5)
				local now = os.clock()
				for id, profile in profiles do
					local gone = profile.player == nil
						and not profile.saving
						and now - profile.leftAt >= KEEP_AFTER_LEAVING
					if gone and (not unsaved(profile) or profile.failures >= DEPARTED_TRIES) then
						profiles[id] = nil
					elseif unsaved(profile) and (profile.player == nil or now - profile.lastSave >= SAVE_DELAY) then
						task.spawn(save, profile)
					end
				end
			end
		end)
		task.spawn(function()
			while running do
				refresh()
				task.wait(BOARD_REFRESH)
			end
		end)
	end
	publishTitle()

	return {
		add = function(player: Player)
			local profile = profiles[player.UserId]
			if profile == nil then
				local made: Profile = {
					userId = player.UserId,
					name = shortName(player.DisplayName),
					player = player,
					leftAt = 0,
					base = Standings.newRecord(),
					batch = nil,
					pending = Standings.newRecord(),
					committed = false,
					saving = false,
					lastSave = 0,
					failures = 0,
					boardVersus = 0,
					boardBots = 0,
				}
				profiles[player.UserId] = made
				publishRecord(made)
				task.spawn(load, made)
			else
				-- Back before their last results were written: those carry on with this visit.
				profile.player = player
				profile.name = shortName(player.DisplayName)
				publishRecord(profile)
			end
		end,
		remove = function(player: Player)
			if Standings.vacate(title, player.UserId) then
				publishTitle()
			end
			local profile = profiles[player.UserId]
			if profile ~= nil and profile.player == player then
				profile.player = nil
				profile.leftAt = os.clock()
				task.spawn(save, profile)
			end
		end,
		matchEnded = matchEnded,
		refresh = refresh,
		saveAll = function()
			if store == nil then
				return
			end
			local deadline = os.clock() + SHUTDOWN_WAIT
			local tries: { [Profile]: number } = {}
			while os.clock() < deadline do
				local waiting = false
				for _, profile in profiles do
					if profile.saving then
						waiting = true
					elseif unsaved(profile) and (tries[profile] or 0) < SHUTDOWN_TRIES then
						waiting = true
						tries[profile] = (tries[profile] or 0) + 1
						task.spawn(save, profile)
					end
				end
				if not waiting then
					return
				end
				task.wait(0.1)
			end
		end,
		recordOf = function(player: Player): Standings.Record?
			local profile = profileOf(player)
			return if profile ~= nil then totalOf(profile) else nil
		end,
		destroy = function()
			running = false
		end,
	}
end

return Records
