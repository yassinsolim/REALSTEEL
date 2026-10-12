--!strict

-- Studio-only checks of the server's records (src/server/Records.luau): results counted and written as additions, the
-- champion's title changing hands and falling vacant, and the leaderboards read from the all-time stores or, when those
-- cannot be reached, ranked from the server's own players. It runs against stand-in stores and stand-in players, so it
-- needs no game. From the command bar in Edit mode:
--   require(game.ReplicatedStorage.Tests.RecordsSpec:Clone())()

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local function newPlayer(userId: number, name: string): any
	local attributes: { [string]: any } = {}
	local player: any = { UserId = userId, DisplayName = name, attributes = attributes }
	function player:SetAttribute(key: string, value: any)
		attributes[key] = value
	end
	function player:GetAttribute(key: string): any
		return attributes[key]
	end
	return player
end

-- A record store: GetAsync and UpdateAsync. `delay` makes a read slow; `failReads` makes reads throw; `failWrites` makes a
-- write throw before it lands; `loseReplies` lets a write land and then throws, like a reply lost on the way back.
local function newStore(): any
	local store: any =
		{ data = {}, reads = 0, writes = 0, delay = 0, failReads = false, failWrites = false, loseReplies = 0 }
	function store:GetAsync(key: string): any
		store.reads += 1
		if store.delay > 0 then
			task.wait(store.delay)
		end
		if store.failReads then
			error("the store is down")
		end
		return store.data[key]
	end
	function store:UpdateAsync(key: string, transform: (any) -> any): any
		if store.failWrites then
			error("the store is down")
		end
		local result = transform(store.data[key])
		if result ~= nil then
			store.writes += 1
			store.data[key] = result
		end
		if store.loseReplies > 0 then
			store.loseReplies -= 1
			error("the reply was lost")
		end
		return result
	end
	return store
end

-- A board store: UpdateAsync and GetSortedAsync (best first). `failReads` makes a read throw, `failWrites` a write;
-- `delay` makes a read slow.
local function newBoard(): any
	local board: any = { data = {}, writes = 0, failReads = false, failWrites = false, delay = 0 }
	function board:UpdateAsync(key: string, transform: (any) -> any): any
		if board.failWrites then
			error("the board is down")
		end
		local result = transform(board.data[key])
		if result ~= nil then
			board.writes += 1
			board.data[key] = result
		end
		return result
	end
	function board:GetSortedAsync(_ascending: boolean, size: number): any
		if board.delay > 0 then
			task.wait(board.delay)
		end
		if board.failReads then
			error("the board is down")
		end
		local items = {}
		for key, value in board.data do
			table.insert(items, { key = key, value = value })
		end
		table.sort(items, function(a, b)
			return a.value > b.value
		end)
		local page = {}
		for index = 1, math.min(size, #items) do
			page[index] = items[index]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
		}
	end
	return board
end

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

	-- A fresh copy of the module and of what it needs, so nothing cached from an earlier run is used.
	local temp = Instance.new("Folder")
	temp.Name = "__RecordsSpecTemp"
	ReplicatedStorage:WaitForChild("Shared"):Clone().Parent = temp
	local copy = ServerScriptService:WaitForChild("Records"):Clone() :: any
	copy.Source = string.gsub(copy.Source, "ReplicatedStorage%.Shared", "script.Parent.Shared")
	copy.Parent = temp
	temp.Parent = ServerStorage
	local load: (module: any) -> any = require :: any
	local Records: any = load(copy)
	local made: { any } = {}

	-- A server's records against the stand-in stores; `session` tags its batches (two servers need two).
	local function newRecords(store: any, versus: any, bots: any, session: string?): (any, Folder)
		local state = Instance.new("Folder")
		local records = Records.new(state, {
			store = store,
			versusBoard = versus,
			botsBoard = bots,
			nameOf = function(id: number): string
				return "PLAYER" .. id
			end,
			background = false,
			retryDelay = 0.01,
			session = session or "TEST",
		})
		table.insert(made, records)
		return records, state
	end

	local function board(state: Folder, name: string): { any }
		local raw = state:GetAttribute(name)
		if type(raw) ~= "string" then
			return {}
		end
		return HttpService:JSONDecode(raw)
	end

	local function versus(records: any, winner: any, loser: any)
		records.matchEnded({ mode = "versus", level = 0, owners = { winner, loser }, winner = 1 })
	end

	local ok, err = pcall(function()
		-- A new player starts empty; their saved record arrives under what they won meanwhile.
		do
			local store = newStore()
			store.data["u1"] = { v = 1, vw = 4, vl = 2, bw3 = 3 }
			store.delay = 0.3
			local records, state = newRecords(store, newBoard(), newBoard())
			local first, second = newPlayer(1, "Ada"), newPlayer(2, "Bo")
			records.add(first)
			records.add(second)
			check("a new player's record is published empty", first:GetAttribute("RecordWins") == 0)
			versus(records, first, second)
			check("a win shows at once", first:GetAttribute("RecordWins") == 1)
			task.wait(0.6)
			local record = records.recordOf(first)
			check(
				"the saved record arrives with the session's win on top",
				record ~= nil and record.versusWins == 5 and record.versusLosses == 2 and record.botWins[3] == 3,
				if record ~= nil then `{record.versusWins}-{record.versusLosses}` else "none"
			)
			check(
				"and is published",
				first:GetAttribute("RecordWins") == 5 and first:GetAttribute("RecordHardWins") == 3
			)
			check("the loser's loss counts", second:GetAttribute("RecordLosses") == 1)
			check("the first 1v1 winner is champion", state:GetAttribute("ChampionId") == 1)
			check("by name", state:GetAttribute("ChampionName") == "ADA")
		end

		-- The title changes hands only in 1v1s, and falls vacant when the champion leaves.
		do
			local records, state = newRecords(newStore(), newBoard(), newBoard())
			local a, b, c = newPlayer(11, "Ana"), newPlayer(12, "Ben"), newPlayer(13, "Cy")
			for _, player in { a, b, c } do
				records.add(player)
			end
			check("the title starts vacant", state:GetAttribute("ChampionId") == 0)
			versus(records, b, a)
			check("the winner claims it", state:GetAttribute("ChampionId") == 12)
			versus(records, b, c)
			check("winning again defends it", state:GetAttribute("ChampionDefenses") == 1)
			records.matchEnded({ mode = "bot", level = 3, owners = { a, nil }, winner = 1 })
			check("a bot match leaves it", state:GetAttribute("ChampionId") == 12)
			versus(records, c, b)
			check("beating the champion takes it", state:GetAttribute("ChampionId") == 13)
			check("with no defenses yet", state:GetAttribute("ChampionDefenses") == 0)
			records.remove(c)
			check("the champion leaving vacates it", state:GetAttribute("ChampionId") == 0)
			check("and clears the name", state:GetAttribute("ChampionName") == "")
		end

		-- Bot matches count by level, from whichever seat the player sat in.
		do
			local records = newRecords(newStore(), newBoard(), newBoard())
			local player = newPlayer(21, "Dee")
			records.add(player)
			records.matchEnded({ mode = "bot", level = 3, owners = { player, nil }, winner = 1 })
			records.matchEnded({ mode = "bot", level = 3, owners = { nil, player }, winner = 2 })
			records.matchEnded({ mode = "bot", level = 1, owners = { player, nil }, winner = 2 })
			records.matchEnded({ mode = "training", level = 0, owners = { player, nil }, winner = 1 })
			records.matchEnded({ mode = "exhibition", level = 3, owners = {}, winner = 1 })
			local record = records.recordOf(player)
			check("HARD wins count from either seat", record ~= nil and record.botWins[3] == 2)
			check("a loss counts at its level", record ~= nil and record.botLosses[1] == 1 and record.botWins[1] == 0)
			check("training and exhibitions count nothing", record ~= nil and record.versusWins == 0)
			check("HARD wins are published", player:GetAttribute("RecordHardWins") == 2)
		end

		-- Results are added to the stored record, never written over it.
		do
			local store = newStore()
			store.data["u31"] = { v = 1, vw = 10, vl = 1 }
			local versusBoard, botsBoard = newBoard(), newBoard()
			local records = newRecords(store, versusBoard, botsBoard)
			local a, b = newPlayer(31, "Eve"), newPlayer(32, "Fay")
			records.add(a)
			records.add(b)
			versus(records, a, b)
			-- Another server adds a win of its own before this one writes.
			store.data["u31"] = { v = 1, vw = 20, vl = 1 }
			records.saveAll()
			check("a save adds to what is stored", store.data["u31"].vw == 21, store.data["u31"].vw)
			check("and keeps what it did not touch", store.data["u31"].vl == 1)
			check("the 1v1 board gets the new total", versusBoard.data["31"] == 21)
			check("a board with an unchanged score is not written", botsBoard.writes == 0, botsBoard.writes)
			local writes = store.writes
			records.saveAll()
			check("with nothing new, nothing is written", store.writes == writes)

			store.failWrites = true
			versus(records, a, b)
			records.saveAll()
			check("a failed write adds nothing", store.data["u31"].vw == 21)
			store.failWrites = false
			records.saveAll()
			check("the batch lands once on the next try", store.data["u31"].vw == 22, store.data["u31"].vw)

			store.loseReplies = 1
			versus(records, a, b)
			records.saveAll()
			check("a write whose reply was lost is not added twice", store.data["u31"].vw == 23, store.data["u31"].vw)

			versusBoard.data["31"] = 99
			versus(records, a, b)
			records.saveAll()
			check("a board never goes down", versusBoard.data["31"] == 99)
		end

		-- A write whose reply was lost, tried again after another server has written many times: it is still added once.
		do
			local store = newStore()
			local first = newRecords(store, newBoard(), newBoard(), "A")
			local second = newRecords(store, newBoard(), newBoard(), "B")
			local here, rival = newPlayer(81, "Lu"), newPlayer(82, "Max")
			first.add(here)
			first.add(rival)
			versus(first, here, rival)
			store.loseReplies = 1
			first.remove(here)
			task.wait(0.05)
			check("the write whose reply was lost landed", store.data["u81"] ~= nil and store.data["u81"].vw == 1)
			-- They join another server and win there, again and again, before the first one tries again.
			local again, other = newPlayer(81, "Lu"), newPlayer(83, "Ned")
			second.add(again)
			second.add(other)
			for _ = 1, 20 do
				versus(second, again, other)
				second.saveAll()
			end
			check("the other server adds its wins", store.data["u81"].vw == 21, store.data["u81"].vw)
			first.saveAll()
			check("the batch whose reply was lost is not added again", store.data["u81"].vw == 21, store.data["u81"].vw)
			check("the rival's loss is written too", store.data["u82"] ~= nil and store.data["u82"].vl == 1)
		end

		-- A result that comes in just after a player left still counts, but the title only goes to a winner who is here.
		do
			local store = newStore()
			local records, state = newRecords(store, newBoard(), newBoard())
			local stays, leaves = newPlayer(101, "Sam"), newPlayer(102, "Tia")
			records.add(stays)
			records.add(leaves)
			records.remove(leaves)
			versus(records, stays, leaves)
			records.saveAll()
			check("the winner's win counts", store.data["u101"] ~= nil and store.data["u101"].vw == 1)
			check("and so does the loss of the one who left", store.data["u102"] ~= nil and store.data["u102"].vl == 1)
			check("the winner takes the title", state:GetAttribute("ChampionId") == 101)

			-- The champion leaves, so the title is there for the taking.
			records.remove(stays)
			local gone, here = newPlayer(103, "Uma"), newPlayer(104, "Vic")
			records.add(gone)
			records.add(here)
			records.remove(gone)
			versus(records, gone, here)
			check("a winner who has left takes no title", state:GetAttribute("ChampionId") == 0)
			records.saveAll()
			check("but keeps the win", store.data["u103"] ~= nil and store.data["u103"].vw == 1)
		end

		-- A board write that fails is tried again; a joining player's stored scores are put on the boards, in case a
		-- server stopped between writing their record and their boards.
		do
			local store = newStore()
			local versusBoard = newBoard()
			local records = newRecords(store, versusBoard, newBoard())
			local a, b = newPlayer(91, "Ola"), newPlayer(92, "Pia")
			records.add(a)
			records.add(b)
			versus(records, a, b)
			versusBoard.failWrites = true
			records.saveAll()
			check("a record lands while its board is down", store.data["u91"] ~= nil and store.data["u91"].vw == 1)
			check("and the board misses it", versusBoard.data["91"] == nil)
			versusBoard.failWrites = false
			local writes = store.writes
			records.saveAll()
			check("the board gets it on the next save", versusBoard.data["91"] == 1, versusBoard.data["91"])
			check("without the record being written again", store.writes == writes)

			local stored = newStore()
			stored.data["u95"] = { v = 1, vw = 5, bw3 = 2 }
			local versusAgain, botsAgain = newBoard(), newBoard()
			local later = newRecords(stored, versusAgain, botsAgain)
			later.add(newPlayer(95, "Rio"))
			later.saveAll()
			check(
				"a joining player's stored scores are put on the boards",
				versusAgain.data["95"] == 5 and botsAgain.data["95"] == 2
			)
			check("without writing their record", stored.writes == 0, stored.writes)
			local boardWrites = versusAgain.writes + botsAgain.writes
			later.saveAll()
			check("and only once", versusAgain.writes + botsAgain.writes == boardWrites)
		end

		-- A player who leaves is written in the background; one who comes back first keeps their unsaved results.
		do
			local store = newStore()
			local records = newRecords(store, newBoard(), newBoard())
			local a, b, c = newPlayer(41, "Gus"), newPlayer(42, "Hal"), newPlayer(43, "Ike")
			records.add(a)
			records.add(b)
			records.add(c)
			versus(records, a, b)
			local before = os.clock()
			records.remove(b)
			check("leaving does not wait for the store", os.clock() - before < 0.05)
			task.wait(0.1)
			check("the leaver's results are written", type(store.data["u42"]) == "table" and store.data["u42"].vl == 1)

			store.failWrites = true
			versus(records, a, c)
			records.remove(a)
			task.wait(0.1)
			local back = newPlayer(41, "Gus")
			records.add(back)
			local record = records.recordOf(back)
			check(
				"coming back keeps the unsaved wins",
				record ~= nil and record.versusWins == 2,
				if record ~= nil then record.versusWins else nil
			)
			store.failWrites = false
			records.saveAll()
			check("and they are written later", store.data["u41"] ~= nil and store.data["u41"].vw == 2)
		end

		-- A record that cannot be read still has its results added to it.
		do
			local store = newStore()
			store.data["u51"] = { v = 1, vw = 80 }
			store.failReads = true
			local records = newRecords(store, newBoard(), newBoard())
			local a, b = newPlayer(51, "Ike"), newPlayer(52, "Jem")
			records.add(a)
			records.add(b)
			versus(records, a, b)
			task.wait(0.2)
			check("a record that cannot be read gives up reading", store.reads == 6, store.reads)
			check("and still shows this session", a:GetAttribute("RecordWins") == 1)
			records.saveAll()
			check("its results are added to the stored record", store.data["u51"].vw == 81, store.data["u51"].vw)
		end

		-- The boards: all-time from the stores, or the server's players while the stores cannot be read.
		do
			local versusBoard, botsBoard = newBoard(), newBoard()
			versusBoard.data["901"] = 40
			versusBoard.data["902"] = 12
			botsBoard.data["901"] = 3
			local records, state = newRecords(newStore(), versusBoard, botsBoard)
			local player = newPlayer(61, "Ivy")
			records.add(player)
			records.refresh()
			check("reachable stores make all-time boards", state:GetAttribute("BoardScope") == "ALL TIME")
			local list = board(state, "BoardVersus")
			check(
				"the 1v1 board is best first, by name and id",
				#list == 2 and list[1].name == "PLAYER901" and list[1].id == 901 and list[1].score == 40
			)
			check("the HARD board lists its own", #board(state, "BoardBots") == 1)

			versusBoard.failReads = true
			records.matchEnded({ mode = "bot", level = 3, owners = { player, nil }, winner = 1 })
			records.refresh()
			check(
				"a store that cannot be read falls back to this server",
				state:GetAttribute("BoardScope") == "THIS SERVER"
			)
			local here = board(state, "BoardBots")
			check(
				"the server's board ranks the players here",
				#here == 1 and here[1].name == "IVY" and here[1].id == 61 and here[1].score == 1
			)
			check("with nobody's 1v1 wins, that board is empty", #board(state, "BoardVersus") == 0)

			-- A slow store never holds up a result: the server's boards are redone without reading it.
			versusBoard.delay = 0.2
			local before = os.clock()
			records.matchEnded({ mode = "bot", level = 3, owners = { player, nil }, winner = 1 })
			check("reporting a result never waits on the boards", os.clock() - before < 0.05, os.clock() - before)
			local after = board(state, "BoardBots")
			check("and the server's board shows it at once", #after == 1 and after[1].score == 2)
		end

		-- With no stores at all the server's boards stay current after every match.
		do
			local records, state = newRecords(nil, nil, nil)
			local a, b = newPlayer(71, "Jo"), newPlayer(72, "Kim")
			records.add(a)
			records.add(b)
			records.refresh()
			versus(records, a, b)
			local list = board(state, "BoardVersus")
			check("no stores means the server's boards", state:GetAttribute("BoardScope") == "THIS SERVER")
			check("and a win shows at once", #list == 1 and list[1].name == "JO")
			records.saveAll()
			check("saving with no store returns at once", true)
		end
	end)
	if not ok then
		table.insert(failures, "error: " .. tostring(err))
	end

	for _, records in made do
		records.destroy()
	end
	temp:Destroy()
	return passed, failures
end
