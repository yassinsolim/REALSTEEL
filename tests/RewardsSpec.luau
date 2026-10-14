--!strict

-- Headless checks for the daily reward (DailyRewards) and the daily contracts (Contracts): the streak and when it starts
-- again, what each day pays, and which matches count toward which contract. Run from Studio's command bar, or without
-- Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.RewardsSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Contracts = require(ReplicatedStorage.Shared.Contracts)
local DailyRewards = require(ReplicatedStorage.Shared.DailyRewards)

local TODAY = 20374

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

	-- The daily reward.
	do
		check("a day is a whole UTC day", DailyRewards.dayOf(TODAY * 86400 + 86399) == TODAY)
		check("and the next starts at midnight", DailyRewards.dayOf((TODAY + 1) * 86400) == TODAY + 1)
		local cycle = DailyRewards.Cycle
		local growing = true
		for index = 2, #cycle - 1 do
			if cycle[index].coins <= cycle[index - 1].coins then
				growing = false
			end
		end
		check("a seven-day cycle whose coins grow through the week", #cycle == 7 and growing)
		local last = cycle[#cycle]
		check("and whose last day gives a case", last.cases == 1 and last.case ~= nil and Cases.get(last.case) ~= nil)

		local fresh = DailyRewards.new()
		local status = DailyRewards.status(fresh, TODAY)
		check(
			"a new player can claim day 1",
			status.ready and status.cycleDay == 1 and status.streak == 1 and not status.broken
		)
		local reward, state = DailyRewards.claim(fresh, TODAY)
		check("which pays day 1", reward == cycle[1] and state.day == TODAY and state.streak == 1)
		local again, same = DailyRewards.claim(state, TODAY)
		check("once a day", again == nil and same.day == TODAY and same.streak == 1)
		check("and says so", not DailyRewards.status(state, TODAY).ready)

		-- A week in a row, then the cycle starts over and the streak carries on.
		local paid: { number } = {}
		local run = DailyRewards.new()
		for day = TODAY, TODAY + 8 do
			local got
			got, run = DailyRewards.claim(run, day)
			table.insert(paid, if got ~= nil then got.coins else -1)
		end
		check(
			"consecutive days walk through the cycle and start it again",
			paid[1] == cycle[1].coins
				and paid[7] == cycle[7].coins
				and paid[8] == cycle[1].coins
				and paid[9] == cycle[2].coins,
			table.concat(paid, ",")
		)
		check("the streak keeps counting", run.streak == 9)

		local missed = DailyRewards.status({ day = TODAY - 2, streak = 5 }, TODAY)
		check(
			"a missed day starts the streak again",
			missed.ready and missed.streak == 1 and missed.cycleDay == 1 and missed.broken
		)
		local kept = DailyRewards.status({ day = TODAY - 1, streak = 5 }, TODAY)
		check(
			"claiming the next day keeps it",
			kept.ready and kept.streak == 6 and kept.cycleDay == 6 and not kept.broken
		)
		local odd = DailyRewards.sanitize({ day = "x", streak = 3 })
		check("a broken save is a new player", odd.day == 0 and odd.streak == 0)
		local fine = DailyRewards.sanitize({ day = TODAY + 0.5, streak = 2.9 })
		check("a fine save is kept, in whole numbers", fine.day == TODAY and fine.streak == 2)
	end

	-- The contracts.
	do
		local ids: { [string]: boolean } = {}
		local wellFormed = true
		local solo = true
		for _, contract in Contracts.Pool do
			if ids[contract.id] or contract.goal < 1 or contract.coins < 1 then
				wellFormed = false
			end
			ids[contract.id] = true
			if contract.mode == "versus" then
				solo = false
			end
		end
		check("every contract has its own id, a goal and coins", wellFormed)
		check("every contract can be done alone, against the bots, so a day's set can always be finished", solo)

		local sameAll = true
		local spread: { [string]: boolean } = {}
		for user = 1, 60 do
			for day = TODAY, TODAY + 6 do
				local picks = Contracts.picks(user * 12345, day)
				local again = Contracts.picks(user * 12345, day)
				local groups: { [string]: boolean } = {}
				if #picks ~= Contracts.PerDay then
					sameAll = false
				end
				for index, contract in picks do
					if again[index].id ~= contract.id or groups[contract.group] then
						sameAll = false
					end
					groups[contract.group] = true
					spread[contract.id] = true
				end
			end
		end
		check("a player gets the same contracts all day, one of each group", sameAll)
		local everyContract = true
		for _, contract in Contracts.Pool do
			if not spread[contract.id] then
				everyContract = false
			end
		end
		check("every contract comes up for someone", everyContract)

		local userId = 777
		local state = Contracts.forDay(nil, userId, TODAY)
		check("a new day brings a fresh set", state.day == TODAY and #state.ids == Contracts.PerDay and not state.bonus)
		local kept = Contracts.forDay(state, userId, TODAY)
		check("which stays for the day", kept.ids[1] == state.ids[1] and kept.ids[3] == state.ids[3])
		local tomorrow = Contracts.forDay(state, userId, TODAY + 1)
		check("and is replaced the next day", tomorrow.day == TODAY + 1 and tomorrow.progress[1] == 0)

		-- Which matches count: a fixed set to check against.
		local fixed: Contracts.State =
			{ day = TODAY, ids = { "botwin2", "hard", "play5" }, progress = { 0, 0, 0 }, bonus = false }
		local lost = Contracts.record(fixed, { mode = "bot", level = 3, won = false })
		check(
			"a lost bot match counts only as a match played",
			lost.coins == 0
				and lost.state.progress[1] == 0
				and lost.state.progress[2] == 0
				and lost.state.progress[3] == 1
		)
		local easy = Contracts.record(fixed, { mode = "bot", level = 1, won = true })
		check(
			"beating an EASY bot counts toward beating bots, not toward HARD",
			easy.state.progress[1] == 1 and easy.state.progress[2] == 0 and easy.coins == 0
		)
		check("and leaves the stored state alone", fixed.progress[1] == 0)
		local hard = Contracts.record(easy.state, { mode = "bot", level = 3, won = true })
		check(
			"beating a HARD bot finishes both bot contracts and pays them",
			hard.state.progress[1] == 2
				and hard.state.progress[2] == 1
				and #hard.completed == 2
				and hard.coins
					== (Contracts.get("botwin2") :: Contracts.Contract).coins + (
						Contracts.get("hard") :: Contracts.Contract
					).coins
		)
		local more = Contracts.record(hard.state, { mode = "bot", level = 3, won = true })
		check("a finished contract pays once", more.coins == 0 and #more.completed == 0 and more.state.progress[3] == 3)
		local training = Contracts.record(more.state, { mode = "training", level = 0, won = true })
		check("training counts for nothing", training.coins == 0 and training.state.progress[3] == 3)
		local fourth = Contracts.record(more.state, { mode = "versus", level = 0, won = false })
		check("a 1v1 counts as a match played", fourth.coins == 0 and fourth.state.progress[3] == 4)
		local fifth = Contracts.record(fourth.state, { mode = "bot", level = 1, won = false })
		check(
			"the fifth match finishes the last one, and all three pay the bonus",
			fifth.bonus
				and fifth.state.bonus
				and fifth.coins == (Contracts.get("play5") :: Contracts.Contract).coins + Contracts.Bonus
				and Contracts.allDone(fifth.state)
		)
		local after = Contracts.record(fifth.state, { mode = "versus", level = 0, won = true })
		check("the bonus pays once", not after.bonus and after.coins == 0)
		local junk = Contracts.forDay({ day = TODAY, ids = { "nope", "play3" }, progress = { 4, 99 } }, userId, TODAY)
		check(
			"a stored set keeps only real contracts, capped at their goals",
			#junk.ids == 1 and junk.ids[1] == "play3" and junk.progress[1] == 3
		)
	end

	return passed, failures
end
