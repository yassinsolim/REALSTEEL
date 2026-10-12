--!strict

-- Headless checks for records, the champion's title and leaderboard order (Standings). Run from Studio's command bar, or
-- without Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.StandingsSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Standings = require(ReplicatedStorage.Shared.Standings)

local A, B, C = 101, 202, 303

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

	-- Records count up, per kind of fight.
	do
		local mine = Standings.newRecord()
		local theirs = Standings.newRecord()
		check("a new record is empty", mine.versusWins == 0 and mine.versusLosses == 0 and mine.botWins[3] == 0)
		Standings.recordVersus(mine, theirs)
		check("a 1v1 win counts for the winner", mine.versusWins == 1 and mine.versusLosses == 0)
		check("and a loss for the loser", theirs.versusLosses == 1 and theirs.versusWins == 0)
		Standings.recordBot(mine, 3, true)
		Standings.recordBot(mine, 3, true)
		Standings.recordBot(mine, 1, false)
		check("bot wins count by level", mine.botWins[3] == 2 and mine.botWins[1] == 0 and mine.botWins[2] == 0)
		check("bot losses count by level", mine.botLosses[1] == 1 and mine.botLosses[3] == 0)
		Standings.recordBot(mine, 0, true)
		Standings.recordBot(mine, 4, true)
		Standings.recordBot(mine, 2.5, true)
		check(
			"levels that do not exist count nowhere",
			mine.botWins[1] == 0 and mine.botWins[2] == 0 and mine.botWins[3] == 2
		)
	end

	-- Saving and loading.
	do
		local record = Standings.newRecord()
		record.versusWins = 7
		record.versusLosses = 3
		record.botWins[2] = 5
		record.botLosses[3] = 9
		local back = Standings.sanitize(Standings.toSaved(record))
		check(
			"a record survives a round trip",
			back.versusWins == 7 and back.versusLosses == 3 and back.botWins[2] == 5 and back.botLosses[3] == 9
		)
		check("nothing reads as an empty record", Standings.sanitize(nil).versusWins == 0)
		local broken = Standings.sanitize({ vw = -4, vl = 0 / 0, bw1 = "lots", bw2 = 2.9, bw3 = math.huge })
		check("negative counts read as zero", broken.versusWins == 0)
		check("NaN reads as zero", broken.versusLosses == 0)
		check("words read as zero", broken.botWins[1] == 0)
		check("fractions are cut to whole fights", broken.botWins[2] == 2)
		check("absurd numbers are capped", broken.botWins[3] == 10_000_000)
		check("a save says its version", Standings.toSaved(record).v == 1)
	end

	-- What a save keeps track of, so a batch whose reply was lost is never added twice.
	do
		check("nothing has no batches", not Standings.hasBatch(nil, "A", 1))
		local saved: { [string]: any } = { vw = 3, batches = Standings.withBatch(nil, "A", 1) }
		check("a landed batch is recognized", Standings.hasBatch(saved, "A", 1))
		check("the server's next one is not", not Standings.hasBatch(saved, "A", 2))
		check("nor another server's", not Standings.hasBatch(saved, "B", 1))
		for sequence = 1, 40 do
			saved.batches = Standings.withBatch(saved, "B", sequence)
		end
		check(
			"however many batches another server adds, it is still recognized",
			Standings.hasBatch(saved, "A", 1) and Standings.hasBatch(saved, "B", 40)
		)
		saved.batches = Standings.withBatch(saved, "A", 7)
		check("a server's latest batch covers its earlier ones", Standings.hasBatch(saved, "A", 3))
		check("each server is kept once", #saved.batches == 2, #saved.batches)
		check("the one that wrote last at the end", saved.batches[2].s == "A" and saved.batches[2].n == 7)
		saved.batches = Standings.withBatch(saved, "A", 5)
		check("a server's number never goes back", Standings.hasBatch(saved, "A", 7))
		for server = 1, Standings.SessionMemory do
			saved.batches = Standings.withBatch(saved, `S{server}`, 1)
		end
		check("a save keeps a limited number of servers", #saved.batches == Standings.SessionMemory, #saved.batches)
		check(
			"forgetting the one that wrote longest ago",
			not Standings.hasBatch(saved, "B", 1)
				and not Standings.hasBatch(saved, "A", 1)
				and Standings.hasBatch(saved, "S1", 1)
		)
		local damaged: { any } = { 4, { s = "A", n = 2 }, { s = 5, n = 1 }, { s = "C" }, false }
		check(
			"a damaged list keeps only what it can read",
			#Standings.withBatch({ batches = damaged }, "D", 1) == 2
				and not Standings.hasBatch({ batches = "A" }, "A", 1)
		)
	end

	-- What a player won while their saved record was loading is added to it.
	do
		local saved = Standings.sanitize({ vw = 10, vl = 4, bw3 = 6 })
		local meanwhile = Standings.newRecord()
		Standings.recordVersus(meanwhile, Standings.newRecord())
		Standings.recordBot(meanwhile, 3, true)
		Standings.merge(saved, meanwhile)
		check("merging adds the session to the save", saved.versusWins == 11 and saved.botWins[3] == 7)
		check("and keeps what the session did not touch", saved.versusLosses == 4)
		local copy = Standings.copy(saved)
		copy.versusWins = 0
		copy.botWins[3] = 0
		check("a copy is its own record", saved.versusWins == 11 and saved.botWins[3] == 7)
		check("a new record is empty", Standings.isEmpty(Standings.newRecord()))
		check("one loss is not empty", not Standings.isEmpty(Standings.sanitize({ bl2 = 1 })))
		check("a copy of nothing is empty", Standings.isEmpty(Standings.copy(Standings.newRecord())))
	end

	-- The title.
	do
		local title = Standings.newTitle()
		check("the title starts vacant", title.holder == 0 and title.defenses == 0)
		check("the first 1v1 winner claims it", Standings.settleTitle(title, A, B) == "claimed" and title.holder == A)
		check("winning again defends it", Standings.settleTitle(title, A, C) == "defended" and title.defenses == 1)
		check("and again", Standings.settleTitle(title, A, B) == "defended" and title.defenses == 2)
		check("a 1v1 between others leaves it", Standings.settleTitle(title, B, C) == "none" and title.holder == A)
		check("beating the champion takes it", Standings.settleTitle(title, C, A) == "taken" and title.holder == C)
		check("a new champion starts with no defenses", title.defenses == 0)
		check("someone else leaving changes nothing", not Standings.vacate(title, A) and title.holder == C)
		check("the champion leaving vacates it", Standings.vacate(title, C) and title.holder == 0)
		check("a vacant title cannot be vacated", not Standings.vacate(title, 0))
		check(
			"a fight against yourself is no fight",
			Standings.settleTitle(title, A, A) == "none" and title.holder == 0
		)
	end

	-- Leaderboards.
	do
		local entries: { Standings.Entry } = {
			{ id = 1, name = "MORGAN", score = 5 },
			{ id = 2, name = "ALEX", score = 9 },
			{ id = 3, name = "ZED", score = 5 },
			{ id = 4, name = "NOBODY", score = 0 },
			{ id = 5, name = "ALEX", score = 5 },
			{ id = 6, name = "QUINN", score = 2 },
		}
		local top = Standings.rank(entries, 4)
		local order = {}
		for _, entry in top do
			table.insert(order, entry.id)
		end
		local line = table.concat(order, ",")
		check("the board is best first, ties by name, then by id", line == "2,5,1,3", line)
		check("a board keeps its size", #top == 4)
		check("nobody with no score is listed", #Standings.rank(entries, 10) == 5)
		check("an empty board is empty", #Standings.rank({}, 10) == 0)
	end

	return passed, failures
end
