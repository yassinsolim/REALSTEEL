--!strict

-- Headless checks for the cases (Cases): the odds every case shows add up to exactly 100 and are what the draw does, the
-- pity guarantee, and that every item in a case is a cosmetic a look can wear. Run from Studio's command bar, or without
-- Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.CasesSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Looks = require(ReplicatedStorage.Shared.Looks)

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

	-- The rarities.
	do
		local total = 0
		local rising = true
		for index, rarity in Cases.Rarities do
			total += rarity.chance
			local previous = Cases.Rarities[index - 1]
			if previous ~= nil and (rarity.chance >= previous.chance or rarity.refund <= previous.refund) then
				rising = false
			end
		end
		check("five rarities", #Cases.Rarities == 5)
		check("the rarities' chances add up to exactly 100", total == 100, total)
		check("each rarity is rarer and worth more than the one before", rising)
		check("the pity guarantees LEGENDARY or better", Cases.Rarities[Cases.PityRarity].name == "LEGENDARY")
	end

	for _, case in Cases.List do
		local name = case.name

		-- What a case holds.
		local seen: { [string]: boolean } = {}
		local wearable = true
		local unique = true
		local everyRarity = #case.items == #Cases.Rarities
		for rarity, items in case.items do
			if #items == 0 then
				everyRarity = false
			end
			for _, item in items do
				if seen[item] then
					unique = false
				end
				seen[item] = true
				local key, index = Looks.slotOf(item)
				if key == nil or index == nil or Looks.itemAt(key, index) ~= item or Looks.describe(item) == nil then
					wearable = false
				end
				if Cases.rarityOf(item) ~= rarity then
					unique = false
				end
			end
		end
		check(`{name} has items of every rarity`, everyRarity)
		check(`{name} holds each item once`, unique)
		check(`every item in {name} is a cosmetic a look can wear`, wearable)
		check(`{name} costs coins`, case.coins > 0)
		local packsOk = #case.packs > 0
		for _, pack in case.packs do
			if pack.count < 1 or pack.robux < 1 then
				packsOk = false
			end
		end
		check(`{name} sells packs of cases for Robux`, packsOk)

		-- The odds, as shown: every outcome's chance, adding up to exactly 100, normally and when the pity is due.
		for _, pity in { 0, Cases.PityLimit - 1 } do
			local total = 0
			local exact = true
			for _, outcome in Cases.outcomes(case, pity) do
				total += outcome.chance
				-- Every chance is a short exact decimal, so what the screen shows is the chance itself.
				local shown = tonumber((string.gsub(Cases.formatChance(outcome.chance), "%%", "")))
				if shown ~= outcome.chance then
					exact = false
				end
			end
			check(`{name}'s odds add up to exactly 100 (pity {pity})`, total == 100, total)
			check(`{name}'s odds are shown exactly (pity {pity})`, exact)
		end
		local due = Cases.rarityOdds(Cases.PityLimit - 1)
		check(
			"when the pity is due only LEGENDARY and MYTHIC can come, in proportion",
			due[1] == 0 and due[2] == 0 and due[3] == 0 and due[4] == 80 and due[5] == 20,
			table.concat(due, ",")
		)
		local early = Cases.rarityOdds(Cases.PityLimit - 2)
		check("before that the usual odds apply", early[1] == 60 and early[5] == 1)

		-- The draw does what the odds say: rolls spread evenly over [0, 1) land on each rarity in proportion.
		local steps = 20000
		local tally = { 0, 0, 0, 0, 0 }
		local itemTally: { [string]: number } = {}
		for step = 0, steps - 1 do
			local roll = (step + 0.5) / steps
			local draw = Cases.draw(case, 0, roll, (step * 7919 % steps + 0.5) / steps)
			tally[draw.rarity] += 1
			itemTally[draw.item] = (itemTally[draw.item] or 0) + 1
		end
		local matches = true
		for rarity, count in tally do
			if math.abs(count / steps * 100 - Cases.Rarities[rarity].chance) > 0.01 then
				matches = false
			end
		end
		check("the draw lands on each rarity as often as its odds say", matches, table.concat(tally, ","))
		local everyItem = true
		for _, items in case.items do
			for _, item in items do
				if (itemTally[item] or 0) == 0 then
					everyItem = false
				end
			end
		end
		check("every item can come out", everyItem)
		check("the lowest roll draws a COMMON", Cases.draw(case, 0, 0, 0).rarity == 1)
		check("the highest roll draws a MYTHIC", Cases.draw(case, 0, 0.99999, 0.99999).rarity == 5)
		check(
			"an item roll of almost 1 stays in range",
			Cases.draw(case, 0, 0, 0.9999999).item == case.items[1][#case.items[1]]
		)

		-- The pity counter.
		local common = Cases.draw(case, 5, 0, 0)
		check("a draw below LEGENDARY counts toward the pity", common.pityAfter == 6 and not common.pity)
		local legendary = Cases.draw(case, 5, 0.97, 0)
		check("a LEGENDARY resets it", legendary.rarity == 4 and legendary.pityAfter == 0)
		local forced = Cases.draw(case, Cases.PityLimit - 1, 0, 0)
		check(
			"the last open of the pity is LEGENDARY or better, whatever the roll",
			forced.rarity >= Cases.PityRarity and forced.pity and forced.pityAfter == 0
		)
		local guaranteed = 0
		local pity = 0
		for step = 1, 3 * Cases.PityLimit do
			-- The worst luck there is: every roll is the lowest.
			local draw = Cases.draw(case, pity, 0, 0)
			pity = draw.pityAfter
			if draw.rarity >= Cases.PityRarity then
				guaranteed += 1
			end
			if step % Cases.PityLimit == 0 and guaranteed ~= step / Cases.PityLimit then
				guaranteed = -100
			end
		end
		check("even with the worst luck, every PityLimit-th open is guaranteed", guaranteed == 3, guaranteed)
	end

	-- Finding cases and packs.
	do
		local case = Cases.List[1]
		check(
			"a case is found by id",
			Cases.get(case.id) == case and Cases.get("case.nothing") == nil and Cases.get(4) == nil
		)
		local foundCase, foundPack = Cases.packByProduct(-1)
		check("nothing sells under no product", foundCase == nil and foundPack == nil)
		local productsKnown = true
		local seen: { [number]: boolean } = {}
		for _, each in Cases.List do
			for _, pack in each.packs do
				local byCase, byPack = Cases.packByProduct(pack.product)
				if not Cases.forSale(pack) or seen[pack.product] or byCase ~= each or byPack ~= pack then
					productsKnown = false
				end
				seen[pack.product] = true
			end
		end
		check("every pack has a product of its own, and is found by it", productsKnown)
		check("chances read cleanly", Cases.formatChance(7.5) == "7.5%" and Cases.formatChance(0.5) == "0.5%")
		check(
			"and whole ones without a point",
			Cases.formatChance(20) == "20%" and Cases.formatChance(100) == "100%" and Cases.formatChance(0) == "0%"
		)
		local longId = string.rep("c", 80)
		local counts = Cases.sanitizeCounts(
			{ ["case.foundry"] = 3.7, ["case.newer"] = 2, ["case.x"] = "y", ["case.none"] = 0, [longId] = 4 },
			999
		)
		local kept = 0
		for _ in counts do
			kept += 1
		end
		check(
			"stored counts are whole numbers by id, and keep a case this version does not know (a newer server's)",
			counts["case.foundry"] == 3 and counts["case.newer"] == 2 and kept == 2,
			kept
		)
		check("and nothing else", next(Cases.sanitizeCounts("junk", 999)) == nil)
	end

	return passed, failures
end
