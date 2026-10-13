--!strict

-- Studio-only checks of the server's wallets (src/server/Wallet.luau): coins paid for matches, items bought with coins,
-- Robux purchases granted once and only once, and saves that add up whatever else writes to the store. It runs against a
-- stand-in DataStore and stand-in players, so it needs no game. From the command bar in Edit mode:
--   require(game.ReplicatedStorage.Tests.WalletSpec:Clone())()
-- (clone it so an edit is not hidden by a cached result).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- A coin purchase is accepted at most this often per player (REQUEST_COOLDOWN in the module).
local COOLDOWN = 0.55

local function newPlayer(userId: number): any
	local attributes: { [string]: any } = {}
	local player: any = { UserId = userId, attributes = attributes }
	function player:SetAttribute(name: string, value: any)
		attributes[name] = value
	end
	function player:GetAttribute(name: string): any
		return attributes[name]
	end
	return player
end

local function copyOf(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = copyOf(item)
	end
	return copy
end

-- Anything with GetAsync and UpdateAsync, holding copies like a real store. `failReads` makes that many reads throw;
-- `failNext` makes that many writes throw before anything is written; `loseNextReply` lets the next write land and then
-- throws, like a reply that never arrived.
local function newStore(): any
	local store: any = { data = {}, reads = 0, writes = 0, failReads = 0, failNext = 0, loseNextReply = false }
	function store:GetAsync(key: string): any
		store.reads += 1
		if store.failReads > 0 then
			store.failReads -= 1
			error("the store cannot be read")
		end
		return copyOf(store.data[key])
	end
	function store:UpdateAsync(key: string, transform: (old: any) -> any): any
		if store.failNext > 0 then
			store.failNext -= 1
			error("the store is down")
		end
		local result = transform(copyOf(store.data[key]))
		if result ~= nil then
			store.writes += 1
			store.data[key] = copyOf(result)
		end
		if store.loseNextReply then
			store.loseNextReply = false
			error("the reply was lost")
		end
		return copyOf(if result ~= nil then result else store.data[key])
	end
	return store
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
	temp.Name = "__WalletSpecTemp"
	ReplicatedStorage:WaitForChild("Shared"):Clone().Parent = temp
	local copy = ServerScriptService:WaitForChild("Wallet"):Clone() :: any
	copy.Source = string.gsub(copy.Source, "ReplicatedStorage%.Shared", "script.Parent.Shared")
	copy.Parent = temp
	temp.Parent = ServerStorage
	local wallets: { any } = {}
	local remotes: { RemoteEvent } = {}

	local load: (module: any) -> any = require :: any
	local Shop: any = load((temp :: any).Shared.Shop)
	local Wallet: any = load(copy)

	local monarch = Shop.item("body.monarch")
	local crown = Shop.item("crest.crown")
	-- MONARCH's product, for these checks.
	monarch.product = 4242

	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet

	local function newWallet(store: any?): (any, { any })
		local reported: { any } = {}
		local remote = Instance.new("RemoteEvent")
		table.insert(remotes, remote)
		local wallet = Wallet.new(function(player: any)
			table.insert(reported, player)
		end, {
			store = store,
			remote = remote,
			background = false,
			retryDelay = 0,
			reloadDelay = 0,
			session = "spec",
		})
		table.insert(wallets, wallet)
		return wallet, reported
	end

	local function receipt(userId: number, purchase: string, product: number?): { [string]: any }
		return { PlayerId = userId, PurchaseId = purchase, ProductId = product or monarch.product, CurrencySpent = 499 }
	end

	local ok, err = pcall(function()
		-- Loading: what is stored is published, cleaned of what the shop does not sell.
		do
			local store = newStore()
			store.data.u1 = { v = 1, coins = 300, owned = { "crest.crown", "hat.party", 7 } }
			local wallet, reported = newWallet(store)
			local player = newPlayer(1)
			wallet.add(player)
			task.wait(0.05)
			check(
				"a stored wallet is read and published",
				player:GetAttribute("Coins") == 300 and player:GetAttribute("Owned") == "crest.crown,hat.party",
				`{player:GetAttribute("Coins")} {player:GetAttribute("Owned")}`
			)
			check(
				"an item the shop no longer sells is kept, and junk is dropped",
				wallet.owns(player, "hat.party") and not wallet.owns(player, "7")
			)
			check("and the read is reported, so the garage can follow", #reported == 1 and reported[1] == player)
			check(
				"what is owned is known",
				player:GetAttribute("WalletReady") == true
					and wallet.owns(player, "crest.crown")
					and not wallet.owns(player, "body.monarch")
			)

			local odd = newStore()
			odd.data.u2 = { coins = -50, owned = "crest.crown" }
			local other = newWallet(odd)
			local p2 = newPlayer(2)
			other.add(p2)
			task.wait(0.05)
			check(
				"a damaged wallet reads as an empty one",
				p2:GetAttribute("Coins") == 0 and p2:GetAttribute("Owned") == ""
			)
		end

		-- Matches pay coins, saved as additions.
		do
			local store = newStore()
			store.data.u5 = { v = 1, coins = 100, owned = {} }
			local wallet = newWallet(store)
			local winner, loser = newPlayer(5), newPlayer(6)
			wallet.add(winner)
			wallet.add(loser)
			task.wait(0.05)
			wallet.matchEnded("versus", 0, { winner, loser }, 1)
			check(
				"a 1v1 pays the winner more than the loser",
				wallet.coins(winner) == 100 + Shop.Rewards.versusWin and wallet.coins(loser) == Shop.Rewards.versusLoss
			)
			check("and the coins are published at once", winner:GetAttribute("Coins") == 100 + Shop.Rewards.versusWin)
			wallet.matchEnded("bot", 3, { winner }, 1)
			wallet.matchEnded("bot", 1, { nil, winner }, 1)
			check(
				"a bot match pays by level, and something for a loss",
				wallet.coins(winner) == 100 + Shop.Rewards.versusWin + Shop.Rewards.botWin[3] + Shop.Rewards.botLoss
			)
			local before = wallet.coins(winner)
			wallet.matchEnded("training", 1, { winner }, 1)
			check("practice pays nothing", wallet.coins(winner) == before)
			check("nothing is written for every match", store.writes == 0, store.writes)

			-- Another server writes to the same wallet meanwhile: both count.
			store.data.u5.coins += 1000
			wallet.saveAll()
			check(
				"a save adds to the stored coins rather than overwriting them",
				store.data.u5.coins == 1000 + before,
				store.data.u5.coins
			)
			check("and the wallet shows the stored total", wallet.coins(winner) == 1000 + before)
			local writes = store.writes
			wallet.saveAll()
			check("an unchanged wallet is not written again", store.writes == writes)

			-- A save whose reply was lost is tried again and not added twice.
			wallet.matchEnded("bot", 2, { winner }, 1)
			local expected = store.data.u5.coins + Shop.Rewards.botWin[2]
			store.loseNextReply = true
			wallet.saveAll()
			check(
				"a save that landed but whose reply was lost is not added twice",
				store.data.u5.coins == expected,
				`{store.data.u5.coins} vs {expected}`
			)
			check("and the wallet agrees", wallet.coins(winner) == expected)

			-- A store that is down keeps the coins for the next try.
			wallet.matchEnded("bot", 1, { winner }, 1)
			store.failNext = 1
			local landed = store.data.u5.coins
			wallet.saveAll()
			check(
				"a failed save loses nothing",
				store.data.u5.coins == landed + Shop.Rewards.botWin[1]
					and wallet.coins(winner) == landed + Shop.Rewards.botWin[1]
			)

			-- A player who leaves is paid for a match that ends just after, and saved.
			wallet.remove(loser)
			wallet.matchEnded("versus", 0, { winner, loser }, 2)
			wallet.saveAll()
			check(
				"a result just after leaving still pays and is saved",
				store.data.u6 ~= nil and store.data.u6.coins == Shop.Rewards.versusLoss + Shop.Rewards.versusWin,
				if store.data.u6 ~= nil then store.data.u6.coins else "nothing saved"
			)
		end

		-- Buying with coins.
		do
			local store = newStore()
			store.data.u8 = { v = 1, coins = 700, owned = {} }
			local wallet, reported = newWallet(store)
			local player = newPlayer(8)
			wallet.add(player)
			task.wait(0.05)
			local seen = #reported
			check("a Robux item cannot be bought with coins", not wallet.buy(player, "body.monarch"))
			check("nor something the shop does not sell", not wallet.buy(player, "hat.party"))
			check("a crest is bought with coins", wallet.buy(player, "crest.crown"))
			check(
				"its price is taken, it is owned, and that is published and reported",
				wallet.coins(player) == 700 - crown.coins
					and wallet.owns(player, "crest.crown")
					and player:GetAttribute("Owned") == "crest.crown"
					and #reported == seen + 1
			)
			task.wait(0.05)
			check(
				"a purchase is written at once",
				store.data.u8.coins == 700 - crown.coins and table.find(store.data.u8.owned, "crest.crown") ~= nil
			)
			check("an owned item is not bought twice", not wallet.buy(player, "crest.crown"))
			check(
				"too few coins buy nothing",
				not wallet.buy(player, "crest.mohawk") and wallet.coins(player) == 700 - crown.coins
			)
			for _ = 1, 8 do
				wallet.matchEnded("bot", 3, { player }, 1)
			end
			check("with enough, it is bought", wallet.buy(player, "crest.mohawk"))
			check("coins never go below zero", wallet.coins(player) >= 0)

			-- The remote: only "buy", only strings, and one request in a while.
			local third = newPlayer(9)
			wallet.add(third)
			task.wait(0.05)
			for _ = 1, 30 do
				wallet.matchEnded("bot", 3, { third }, 1)
			end
			wallet.handle(third, "take", "crest.crown")
			wallet.handle(third, "buy", 5)
			check("other actions and items that are not names do nothing", not wallet.owns(third, "crest.crown"))
			wallet.handle(third, "buy", "crest.crown")
			wallet.handle(third, "buy", "crest.mohawk")
			check(
				"a second request straight after is ignored",
				wallet.owns(third, "crest.crown") and not wallet.owns(third, "crest.mohawk")
			)
			task.wait(COOLDOWN)
			wallet.handle(third, "buy", "crest.mohawk")
			check("a request after the wait is taken", wallet.owns(third, "crest.mohawk"))
			local stranger = newPlayer(77)
			wallet.handle(stranger, "buy", "crest.crown")
			check(
				"a player nobody added cannot buy",
				not wallet.owns(stranger, "crest.crown") and wallet.coins(stranger) == 0
			)
		end

		-- Robux purchases.
		do
			local store = newStore()
			local wallet, reported = newWallet(store)
			local player = newPlayer(11)
			wallet.add(player)
			task.wait(0.05)
			check(
				"a product the shop does not sell is left for later",
				wallet.processReceipt(receipt(11, "p1", 999)) == NotYet
			)
			local seen = #reported
			check("a purchase is granted", wallet.processReceipt(receipt(11, "p1")) == Granted)
			check(
				"it is saved with its purchase, owned, published and reported",
				store.data.u11 ~= nil
					and table.find(store.data.u11.owned, "body.monarch") ~= nil
					and table.find(store.data.u11.receipts, "p1") ~= nil
					and wallet.owns(player, "body.monarch")
					and player:GetAttribute("Owned") == "body.monarch"
					and #reported == seen + 1
			)
			local writes = store.writes
			check("the same purchase again is granted", wallet.processReceipt(receipt(11, "p1")) == Granted)
			check(
				"without writing it twice",
				store.writes == writes and #store.data.u11.receipts == 1,
				`{store.writes - writes} {#store.data.u11.receipts}`
			)
			store.failNext = 1
			check("a purchase the store cannot take is tried later", wallet.processReceipt(receipt(11, "p2")) == NotYet)
			check("and only recorded once it lands", table.find(store.data.u11.receipts, "p2") == nil)
			store.loseNextReply = true
			check(
				"a purchase whose reply was lost is not granted yet",
				wallet.processReceipt(receipt(11, "p3")) == NotYet
			)
			check("but Roblox's retry is granted once", wallet.processReceipt(receipt(11, "p3")) == Granted)
			local count = 0
			for _, id in store.data.u11.receipts do
				if id == "p3" then
					count += 1
				end
			end
			check("and recorded once", count == 1, count)

			-- Coins saved after a purchase keep the purchase.
			wallet.matchEnded("versus", 0, { player }, 1)
			wallet.saveAll()
			check(
				"a later save of coins keeps the purchase and its receipts",
				table.find(store.data.u11.owned, "body.monarch") ~= nil
					and table.find(store.data.u11.receipts, "p1") ~= nil
					and store.data.u11.coins == Shop.Rewards.versusWin
			)

			-- A buyer who left before the receipt came in still gets it.
			check("a purchase for a player not here is granted", wallet.processReceipt(receipt(12, "q1")) == Granted)
			check(
				"and kept for them",
				store.data.u12 ~= nil and table.find(store.data.u12.owned, "body.monarch") ~= nil
			)
			local back = newPlayer(12)
			wallet.add(back)
			task.wait(0.05)
			check("they have it when they come back", wallet.owns(back, "body.monarch"))
		end

		-- A buyer whose receipt cannot be saved yet has the item for the session; Roblox's retry saves it, once.
		do
			local store = newStore()
			local wallet = newWallet(store)
			local buyer = newPlayer(13)
			wallet.add(buyer)
			task.wait(0.05)
			store.failNext = 1
			check("a receipt the store cannot take is tried later", wallet.processReceipt(receipt(13, "r1")) == NotYet)
			check(
				"but the buyer has the item for the session, so it is not offered again",
				wallet.owns(buyer, "body.monarch") and buyer:GetAttribute("Owned") == "body.monarch"
			)
			check(
				"and Roblox's retry saves it",
				wallet.processReceipt(receipt(13, "r1")) == Granted
					and store.data.u13 ~= nil
					and table.find(store.data.u13.owned, "body.monarch") ~= nil
			)
		end

		-- A wallet that cannot be read is not ready, sells nothing, and is read again later.
		do
			local store = newStore()
			store.data.u40 = { v = 1, coins = 500, owned = { "body.monarch" } }
			store.failReads = 3
			local wallet, reported = newWallet(store)
			local player = newPlayer(40)
			wallet.add(player)
			task.wait(0.3)
			check(
				"an unread wallet is not ready, and owns nothing yet",
				player:GetAttribute("WalletReady") == false and not wallet.owns(player, "body.monarch")
			)
			for _ = 1, 12 do
				wallet.matchEnded("bot", 3, { player }, 1)
			end
			check("nothing is sold while it is unread", not wallet.buy(player, "crest.mohawk"))
			check("and nothing is reported yet", #reported == 0, #reported)
			wallet.tick()
			task.wait(0.05)
			check(
				"it is read again, then ready with what is stored and what was earned meanwhile",
				player:GetAttribute("WalletReady") == true
					and wallet.owns(player, "body.monarch")
					and wallet.coins(player) == 500 + 12 * Shop.Rewards.botWin[3],
				wallet.coins(player)
			)
			check("and the garage hears of it", #reported == 1, #reported)
		end

		-- In Studio a store that cannot be read is given up: the wallet lasts for the session, so the shop can be tried.
		do
			local store = newStore()
			store.failReads = 3
			local remote = Instance.new("RemoteEvent")
			table.insert(remotes, remote)
			local reported: { any } = {}
			local wallet = Wallet.new(function(player: any)
				table.insert(reported, player)
			end, {
				store = store,
				remote = remote,
				background = false,
				retryDelay = 0,
				reloadDelay = 0,
				giveUpUnread = true,
				session = "spec",
			})
			table.insert(wallets, wallet)
			local player = newPlayer(60)
			wallet.add(player)
			task.wait(0.3)
			check(
				"a store Studio cannot read is given up for the session",
				player:GetAttribute("WalletReady") == true and #reported == 1,
				#reported
			)
			for _ = 1, 20 do
				wallet.matchEnded("bot", 3, { player }, 1)
			end
			check(
				"and the shop works for the session",
				wallet.buy(player, "crest.crown") and wallet.owns(player, "crest.crown")
			)
			task.wait(0.05)
			check("without writing to the store", store.writes == 0, store.writes)
		end

		-- A match that ends while a coin purchase waits to be written does not cancel its price.
		do
			local store = newStore()
			store.data.u50 = { v = 1, coins = 1000, owned = {} }
			local wallet = newWallet(store)
			local player = newPlayer(50)
			wallet.add(player)
			task.wait(0.05)
			wallet.matchEnded("bot", 3, { player }, 1)
			store.failNext = 1
			check("a crest is bought while the store is down", wallet.buy(player, "crest.mohawk"))
			store.failNext = 1
			check("and another while the first is still unsaved", wallet.buy(player, "crest.crown"))
			wallet.matchEnded("bot", 1, { player }, 2)
			local expected = 1000 + Shop.Rewards.botWin[3] - 350 - 600 + Shop.Rewards.botLoss
			check("both prices are taken, and the payout added", wallet.coins(player) == expected, wallet.coins(player))
			wallet.saveAll()
			check(
				"and so they are saved",
				store.data.u50.coins == expected
					and table.find(store.data.u50.owned, "crest.crown") ~= nil
					and table.find(store.data.u50.owned, "crest.mohawk") ~= nil,
				store.data.u50.coins
			)
		end

		-- Without a store (Studio before the place is published) everything lasts for the session.
		do
			local wallet = newWallet(nil)
			local player = newPlayer(20)
			wallet.add(player)
			task.wait(0.05)
			check(
				"a session wallet starts empty, and ready",
				wallet.coins(player) == 0
					and player:GetAttribute("Owned") == ""
					and player:GetAttribute("WalletReady") == true
			)
			wallet.matchEnded("bot", 3, { player }, 1)
			check("it is paid", wallet.coins(player) == Shop.Rewards.botWin[3])
			check("a purchase is granted for the session", wallet.processReceipt(receipt(20, "s1")) == Granted)
			check("and owned", wallet.owns(player, "body.monarch"))
			check("but not for a player who is not here to have it", wallet.processReceipt(receipt(21, "s2")) == NotYet)
			wallet.saveAll()
			check("saving does nothing and nothing throws", wallet.owns(player, "body.monarch"))
		end
	end)
	if not ok then
		table.insert(failures, "the spec itself failed: " .. tostring(err))
	end

	for _, wallet in wallets do
		wallet.destroy()
	end
	for _, remote in remotes do
		remote:Destroy()
	end
	temp:Destroy()
	return passed, failures
end
