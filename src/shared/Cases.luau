--!strict

-- The cases: each holds cosmetic items (see Looks: core glows, strike trails, impact effects, titles and paint) in five
-- rarities. Opening one draws a rarity by its odds and then one of that rarity's items, each equally likely. The case
-- screen shows these odds, item by item, before the player opens or buys a case, and the same numbers decide the draw, so
-- what is shown is what happens (Roblox's paid random items policy: every outcome's chance as a percentage, adding up to
-- exactly 100). The item counts are chosen so every chance is an exact decimal.
--
-- A pity counter guarantees a LEGENDARY or better: the PityLimit-th open in a row without one draws only from LEGENDARY
-- and MYTHIC, in proportion to their usual odds. That changes the odds, so the case screen shows the counter and, when it
-- is due, the odds that apply. An item the player already owns turns into coins (its rarity's refund), which the case
-- screen says too. Pure data and arithmetic like Looks and Shop, so it runs anywhere and can be tested without Roblox.
--
-- A case's id is what a wallet counts unopened cases by (see Wallet on the server), so an id never changes once shipped.
-- Robux packs are developer products like the shop's (see Shop): scripts/products.ps1 creates them and writes their IDs
-- here; 0 means not created yet, and the pack is not for sale.

local Looks = require(script.Parent.Looks)

export type Rarity = {
	name: string,
	color: Looks.Rgb,
	-- Percent of opens that draw this rarity. The rarities' chances add up to exactly 100.
	chance: number,
	-- Coins an item of this rarity turns into for a player who already owns it.
	refund: number,
}

export type Pack = {
	product: number,
	count: number,
	robux: number,
}

export type Case = {
	id: string,
	name: string,
	blurb: string,
	-- The price of opening one with coins.
	coins: number,
	packs: { Pack },
	-- The item ids by rarity (positions in Cases.Rarities).
	items: { { string } },
}

-- One possible result of an open and its chance, in percent.
export type Outcome = {
	item: string,
	rarity: number,
	chance: number,
}

export type Draw = {
	item: string,
	rarity: number,
	-- The opens in a row without a LEGENDARY or better after this one.
	pityAfter: number,
	-- Whether the pity decided this draw.
	pity: boolean,
}

local Cases = {}

Cases.Rarities = {
	{ name = "COMMON", color = { 176, 184, 198 }, chance = 60, refund = 50 },
	{ name = "RARE", color = { 72, 146, 255 }, chance = 25, refund = 120 },
	{ name = "EPIC", color = { 178, 98, 255 }, chance = 10, refund = 300 },
	{ name = "LEGENDARY", color = { 255, 186, 56 }, chance = 4, refund = 900 },
	{ name = "MYTHIC", color = { 255, 72, 112 }, chance = 1, refund = 2500 },
} :: { Rarity }

-- The pity: at most this many opens in a row without one of the guaranteed rarities, the lowest of which is this one.
Cases.PityLimit = 30
Cases.PityRarity = 4

Cases.List = {
	{
		id = "case.foundry",
		name = "FOUNDRY CASE",
		blurb = "Core glows, strike trails, impact effects, titles and paint.",
		coins = 500,
		packs = {
			{ product = 3718525122, count = 1, robux = 99 },
			{ product = 3718525123, count = 5, robux = 399 },
		},
		items = {
			{
				"glow.arcwhite",
				"glow.toxic",
				"trail.frost",
				"title.scrapper",
				"title.gearhead",
				"title.brawler",
				"armor.pearl",
				"accent.acid",
			},
			{
				"glow.plasma",
				"glow.solar",
				"trail.ember",
				"trail.venom",
				"impact.arc",
				"title.ironfist",
				"title.heavyweight",
				"armor.rosegold",
			},
			{ "glow.bloodmoon", "glow.deepsea", "trail.shadow", "impact.inferno", "title.themachine" },
			{ "glow.pulse", "trail.prism", "impact.void", "title.unbreakable" },
			{ "glow.spectrum", "impact.goldrush" },
		},
	},
} :: { Case }

function Cases.get(id: unknown): Case?
	if type(id) ~= "string" then
		return nil
	end
	for _, case in Cases.List do
		if case.id == id then
			return case
		end
	end
	return nil
end

-- The case and the pack a developer product sells, if any.
function Cases.packByProduct(productId: unknown): (Case?, Pack?)
	if type(productId) ~= "number" or productId <= 0 then
		return nil, nil
	end
	for _, case in Cases.List do
		for _, pack in case.packs do
			if pack.product == productId then
				return case, pack
			end
		end
	end
	return nil, nil
end

-- Whether a pack can be bought right now: it has a product.
function Cases.forSale(pack: Pack): boolean
	return pack.product > 0
end

-- The rarity of an item in any case, or nil for one no case holds.
function Cases.rarityOf(item: string): number?
	for _, case in Cases.List do
		for rarity, items in case.items do
			if table.find(items, item) ~= nil then
				return rarity
			end
		end
	end
	return nil
end

-- Whether the next open is the one the pity decides, after `pity` opens in a row without a guaranteed rarity.
function Cases.pityDue(pity: number): boolean
	return pity >= Cases.PityLimit - 1
end

-- Each rarity's chance in percent for the next open after `pity` opens in a row without a guaranteed rarity.
function Cases.rarityOdds(pity: number): { number }
	local odds: { number } = {}
	if not Cases.pityDue(pity) then
		for index, rarity in Cases.Rarities do
			odds[index] = rarity.chance
		end
		return odds
	end
	local guaranteed = 0
	for index, rarity in Cases.Rarities do
		if index >= Cases.PityRarity then
			guaranteed += rarity.chance
		end
	end
	for index, rarity in Cases.Rarities do
		odds[index] = if index >= Cases.PityRarity then rarity.chance / guaranteed * 100 else 0
	end
	return odds
end

-- Every item the next open can give, with its chance in percent; together they add up to 100.
function Cases.outcomes(case: Case, pity: number): { Outcome }
	local odds = Cases.rarityOdds(pity)
	local list: { Outcome } = {}
	for rarity, items in case.items do
		for _, item in items do
			table.insert(list, { item = item, rarity = rarity, chance = odds[rarity] / #items })
		end
	end
	return list
end

-- One open: `rarityRoll` and `itemRoll` are uniform numbers in [0, 1) (the server's own random numbers). Draws the rarity
-- by the odds that apply, then one of its items.
function Cases.draw(case: Case, pity: number, rarityRoll: number, itemRoll: number): Draw
	local odds = Cases.rarityOdds(pity)
	local rarity = #odds
	local reach = 0
	for index, chance in odds do
		reach += chance
		if chance > 0 and rarityRoll * 100 < reach then
			rarity = index
			break
		end
	end
	local items = case.items[rarity]
	local index = math.clamp(math.floor(itemRoll * #items) + 1, 1, #items)
	local guaranteed = rarity >= Cases.PityRarity
	return {
		item = items[index],
		rarity = rarity,
		pityAfter = if guaranteed then 0 else pity + 1,
		pity = Cases.pityDue(pity),
	}
end

-- A chance as the case screen shows it: "7.5%", "3.125%", "0.5%", "0%".
function Cases.formatChance(percent: number): string
	local text = string.format("%.4f", percent)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text .. "%"
end

-- Unopened cases or pity counters as a wallet stores them: whole numbers from 0 by case id. An id this version does not
-- know is kept, so a server that has not been updated yet never writes away a newer case; only the known ones can be
-- opened or added to (see Wallet and Rewards on the server).
local MAX_TALLIES = 64
local MAX_TALLY_ID = 64
function Cases.sanitizeCounts(raw: unknown, limit: number): { [string]: number }
	local counts: { [string]: number } = {}
	if type(raw) ~= "table" then
		return counts
	end
	local kept = 0
	for id, value in raw :: { [unknown]: unknown } do
		if type(id) == "string" and #id > 0 and #id <= MAX_TALLY_ID and type(value) == "number" and value == value then
			local count = math.clamp(math.floor(value), 0, limit)
			if count > 0 and kept < MAX_TALLIES then
				kept += 1
				counts[id] = count
			end
		end
	end
	return counts
end

return Cases
