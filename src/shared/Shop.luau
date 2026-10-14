--!strict

-- What the shop sells, and the coins matches pay. Everything for sale is cosmetic: a premium body draws a chassis as
-- another robot with the same size, reach and stats, and a crest only sits on the head. Pure data and arithmetic like
-- Looks, so it runs anywhere and can be tested without Roblox.
--
-- An item's id is what a player's wallet keeps (see Wallet on the server), so an id never changes once it has shipped.
-- Robux items are sold as developer products: `product` is the product's ID (scripts/products.ps1 creates the product and
-- writes it here; 0 means not created yet, and the item is not for sale), and `robux` is the price the shop shows, the
-- same as the product's. Coin items cost `coins`, the free currency every match pays out.
--
-- What a player owns reaches the clients as the Owned attribute (see Wallet): one bit for each item in Looks.items(), six
-- to a character (`formatOwned`, `parseOwned`). A replicated attribute may hold at most 50 characters in a place with
-- server authority, which a list of ids would pass with a handful of items; this fits 300.

local Looks = require(script.Parent.Looks)

export type Item = {
	id: string,
	name: string,
	-- "body" (see Looks.Bodies) or "crest" (see Looks.CrestItems).
	kind: string,
	-- What the shop card says under the name.
	blurb: string,
	product: number?,
	robux: number?,
	coins: number?,
}

local Shop = {}

Shop.Items = {
	{
		id = "body.haymaker",
		name = "HAYMAKER",
		kind = "body",
		blurb = "Prizefighter armor for ANVIL, with a headguard.",
		product = 3718288893,
		robux = 499,
	},
	{
		id = "body.bastion",
		name = "BASTION",
		kind = "body",
		blurb = "Fortress armor for BULWARK, with turret shoulders.",
		product = 3718288897,
		robux = 499,
	},
	{
		id = "body.spectre",
		name = "SPECTRE",
		kind = "body",
		blurb = "Stealth armor for LANCE, with one glowing eye.",
		product = 3718288898,
		robux = 499,
	},
	{
		id = "body.ronin",
		name = "RONIN",
		kind = "body",
		blurb = "Samurai armor for RAZOR, with a horned helmet.",
		product = 3718288900,
		robux = 499,
	},
	{
		id = "body.monarch",
		name = "MONARCH",
		kind = "body",
		blurb = "Champion's armor for MAUL, with a gold title belt.",
		product = 3718281987,
		robux = 499,
	},
	{
		id = "crest.crown",
		name = "CROWN",
		kind = "crest",
		blurb = "Five gold points with a gem on each.",
		coins = 600,
	},
	{
		id = "crest.mohawk",
		name = "MOHAWK",
		kind = "crest",
		blurb = "Four swept blades with a glowing edge.",
		coins = 350,
	},
} :: { Item }

-- Coins a match pays each player in it: more for a win, more for a harder bot, something for a loss so every match counts.
-- Training and exhibitions pay nothing.
Shop.Rewards = {
	versusWin = 40,
	versusLoss = 15,
	botWin = { 10, 20, 35 },
	botLoss = 5,
}

-- A wallet holds at most this many coins.
Shop.MaxCoins = 10000000

function Shop.item(id: unknown): Item?
	if type(id) ~= "string" then
		return nil
	end
	for _, item in Shop.Items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- The item a developer product sells, if any.
function Shop.byProduct(productId: unknown): Item?
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end
	for _, item in Shop.Items do
		if item.product == productId then
			return item
		end
	end
	return nil
end

-- Whether an item can be bought with Robux right now: it has a product.
function Shop.forRobux(item: Item): boolean
	return item.product ~= nil and item.product > 0 and item.robux ~= nil
end

-- What a player in a finished match earns: mode is "versus" or "bot", level the bot's level (1 to 3).
function Shop.reward(mode: string, level: number, won: boolean): number
	if mode == "versus" then
		return if won then Shop.Rewards.versusWin else Shop.Rewards.versusLoss
	elseif mode == "bot" then
		if not won then
			return Shop.Rewards.botLoss
		end
		return Shop.Rewards.botWin[level] or 0
	end
	return 0
end

-- A coin count as the shop shows it: 1,250.
function Shop.formatCoins(coins: number): string
	local text = tostring(math.max(0, math.floor(coins)))
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

-- The longest string a replicated attribute may hold in a place with server authority.
Shop.AttributeLimit = 50

local OWNED_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- Every item a player can own, in the Owned attribute's order (the lists in Looks do not change while a server runs).
local catalog: { string }? = nil
local function ownable(): { string }
	local items = catalog
	if items ~= nil then
		return items
	end
	local fresh = Looks.items()
	catalog = fresh
	return fresh
end

-- The Owned attribute for a set of item ids. Ids no catalog item has (an item taken out of the game) are left out.
function Shop.formatOwned(owned: { [string]: boolean }): string
	local items = ownable()
	local digits: { string } = {}
	local last = 0
	for start = 1, #items, 6 do
		local value = 0
		for bit = 0, 5 do
			local item = items[start + bit]
			if item ~= nil and owned[item] then
				value += 2 ^ bit
			end
		end
		table.insert(digits, string.sub(OWNED_DIGITS, value + 1, value + 1))
		if value > 0 then
			last = #digits
		end
	end
	return table.concat(digits, "", 1, last)
end

-- The ids in a published Owned attribute.
function Shop.parseOwned(text: unknown): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if type(text) ~= "string" then
		return owned
	end
	local items = ownable()
	for position = 1, #text do
		local digit = string.find(OWNED_DIGITS, string.sub(text, position, position), 1, true)
		local value = if digit ~= nil then digit - 1 else 0
		for bit = 0, 5 do
			if value % 2 == 1 then
				local item = items[(position - 1) * 6 + bit + 1]
				if item ~= nil then
					owned[item] = true
				end
			end
			value = math.floor(value / 2)
		end
	end
	return owned
end

return Shop
