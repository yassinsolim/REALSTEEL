--!strict

-- Server: every player's wallet, the coins they have earned and the shop items they own (see Shop).
--
-- Like a record (see Records), a wallet is saved as additions inside one UpdateAsync: the coins earned and spent and the
-- items bought with coins since the last save make a batch, numbered by this server, and the stored wallet remembers
-- each server's latest batch (Standings.hasBatch), so a retry whose earlier attempt landed after all is not added twice.
-- Owned items only ever join the stored set, so nothing a purchase granted can be written away.
--
-- Robux purchases arrive through MarketplaceService.ProcessReceipt (`processReceipt`). A receipt is granted inside one
-- UpdateAsync that also records its PurchaseId, and Roblox hears the purchase went through only once that write has
-- landed: a receipt tried again (after a lost reply, or on another server) finds its PurchaseId and is not granted twice,
-- and one whose write failed is tried again later by Roblox. The buyer has the item for the session from the first try
-- either way, since they paid. Where DataStores cannot be reached (Studio before the place is published) coins and
-- purchases last for the session.
--
-- Until the stored wallet has been read, what a player owns is not known: the read is tried again in the background until
-- it works, and the shop does not sell to them meanwhile, so nobody pays twice for something they already own.
--
-- What the clients show is published on each Player: Coins (a number), Owned (the items they own, packed by
-- Shop.formatOwned to fit an attribute) and WalletReady (whether those are known yet).
--
-- A wallet also counts the player's unopened cases (by case id, added up like coins) and keeps a few small records for the
-- rewards (see Rewards): the daily reward's streak, the day's contracts and each case's pity counter. Those records are not
-- additions: the latest one written wins, which is right for a player who plays on one server at a time. Cases bought with
-- Robux arrive through a receipt like any purchase; a receipt that has landed counts toward the session at once, and
-- stops counting separately as soon as the stored wallet this server holds includes it (see `grantedCases`). Cases,
-- counters and records this version does not know (a newer server's) are kept as they are, like items.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cases = require(ReplicatedStorage.Shared.Cases)
local DailyRewards = require(ReplicatedStorage.Shared.DailyRewards)
local Shop = require(ReplicatedStorage.Shared.Shop)
local Standings = require(ReplicatedStorage.Shared.Standings)

local STORE_NAME = "RealSteelWallet1"
local SAVE_VERSION = 1
-- Coins are written at most this often while a player stays, a coin purchase at once, and everything when they leave.
local SAVE_DELAY = 15
local LOAD_ATTEMPTS = 3
-- A wallet that could not be read is tried again this long after the last attempt.
local RELOAD_DELAY = 15
-- How many purchases a wallet remembers, so a receipt tried again is recognized. Far more than can be pending at once.
local RECEIPT_MEMORY = 100
-- How long a player who left is kept at least (a result that comes in just after they left still pays), how many failed
-- writes they are given before what is unsaved is dropped, and how long the server waits for the last saves on shutdown.
local KEEP_AFTER_LEAVING = 15
local DEPARTED_TRIES = 12
local SHUTDOWN_WAIT = 20
-- A player may ask to buy something this often.
local REQUEST_COOLDOWN = 0.5
-- The longest item id a stored wallet may hold.
local MAX_ID_LENGTH = 64
-- The most unopened cases of one kind a wallet holds.
local MAX_CASES = 100000
-- The records a wallet keeps for the rewards, and the most contracts one day's record holds.
local STATE_KEYS = { "daily", "contracts", "pity" }
local MAX_CONTRACTS = 6

-- What a wallet holds: coins, the set of owned item ids, unopened cases by case id, and the rewards' records by name.
-- `receipts` is only ever read from the store: the purchases the stored wallet has granted.
type Holdings = {
	coins: number,
	owned: { [string]: boolean },
	cases: { [string]: number },
	state: { [string]: any },
	receipts: { [string]: boolean },
}

-- A change to a wallet (see `apply`): coins and cases to add (negative to spend), items to own, records to replace.
export type Change = {
	coins: number?,
	owned: { string }?,
	cases: { [string]: number }?,
	state: { [string]: any }?,
}

-- What a wallet holds now, for the rewards to read. The records are copies.
export type View = {
	coins: number,
	owned: { [string]: boolean },
	cases: { [string]: number },
	state: { [string]: any },
}

type Batch = {
	delta: Holdings,
	sequence: number,
}

type Profile = {
	userId: number,
	player: Player?,
	leftAt: number,
	-- The wallet as last read or written, the batch being written, and what changed since. `granted` holds items Robux
	-- purchases granted, which are saved by the receipt (or will be when Roblox tries it again); `grantedCases` the cases
	-- receipts granted, by PurchaseId, which count until `base` includes the receipt.
	base: Holdings,
	batch: Batch?,
	pending: Holdings,
	granted: { [string]: boolean },
	grantedCases: { [string]: { case: string, count: number } },
	-- Whether `base` is the stored wallet: read, or returned by a write (which is newer than any read still on its way).
	-- Until then what the player owns is not known.
	loaded: boolean,
	loading: boolean,
	-- When a wallet that could not be read is tried again.
	nextLoad: number,
	saving: boolean,
	lastSave: number,
	failures: number,
}

export type Wallet = {
	add: (player: Player) -> (),
	-- Never yields: what the player has not saved is written in the background.
	remove: (player: Player) -> (),
	owns: (player: Player, item: string) -> boolean,
	coins: (player: Player) -> number,
	-- Pays the players in a finished match (see Shop.reward). Never yields.
	matchEnded: (mode: string, level: number, owners: { [number]: Player? }, winner: number) -> (),
	-- Buys an item with coins. Returns whether it was bought.
	buy: (player: Player, item: string) -> boolean,
	-- Whether the player's stored wallet has been read, so what they own and the rewards' records are known.
	ready: (player: Player) -> boolean,
	-- What the player's wallet holds now, or nil for a player without one.
	view: (player: Player) -> View?,
	-- Applies a change at once (it is saved with the next batch, or right away when `urgent`). Only for a ready wallet;
	-- the caller checks that what it spends is there. Returns whether it was applied.
	apply: (player: Player, change: Change, urgent: boolean?) -> boolean,
	-- Calls `listener` with the player whenever what their wallet holds may have changed.
	watch: (listener: (player: Player) -> ()) -> (),
	-- What the Shop remote does with a request. The remote calls it; checks can too.
	handle: (player: Player, action: unknown, item: unknown) -> (),
	-- MarketplaceService.ProcessReceipt.
	processReceipt: (receipt: { [string]: any }) -> Enum.ProductPurchaseDecision,
	-- One pass of the background work: wallets that could not be read are read again, and what is due is saved. The
	-- background loop calls it every few seconds; checks can call it themselves.
	tick: () -> (),
	-- Writes everything unsaved and waits (up to SHUTDOWN_WAIT) for it to land; the server calls it as it shuts down.
	saveAll: () -> (),
	-- Stops the background work. The server never needs it; checks do.
	destroy: () -> (),
}

-- For checks: a stand-in for the DataStore (GetAsync, UpdateAsync), a remote that is not in the game, whether the
-- background loop runs, how long a failed read waits before it is tried again (and a wallet that could not be read before
-- it is read again), whether a store that cannot be read is given up for the session (as in Studio), and the name of this
-- server in its batches. With them the module touches nothing outside itself (and without a store it keeps everything for
-- the session).
export type Options = {
	store: any?,
	remote: RemoteEvent?,
	background: boolean?,
	retryDelay: number?,
	reloadDelay: number?,
	giveUpUnread: boolean?,
	session: string?,
}

local Wallet = {}

local warned = false
local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[REALSTEEL] Wallets are not saved: " .. message)
	end
end

local function newHoldings(): Holdings
	return { coins = 0, owned = {}, cases = {}, state = {}, receipts = {} }
end

local function isEmpty(holdings: Holdings): boolean
	if holdings.coins ~= 0 or next(holdings.owned) ~= nil or next(holdings.state) ~= nil then
		return false
	end
	for _, count in holdings.cases do
		if count ~= 0 then
			return false
		end
	end
	return true
end

local function clampCoins(value: number): number
	return math.clamp(value, 0, Shop.MaxCoins)
end

local function wholeNumber(value: unknown, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.floor(value), low, high)
end

-- The day's contracts as a save file has them, kept to their shape (Contracts.forDay checks them against the pool).
local function sanitizeContracts(raw: unknown): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end
	local source = raw :: { [string]: unknown }
	local day = wholeNumber(source.day, 0, math.huge)
	if day == nil or type(source.ids) ~= "table" or type(source.progress) ~= "table" then
		return nil
	end
	local ids: { string } = {}
	local progress: { number } = {}
	for index, id in source.ids :: { unknown } do
		if type(id) == "string" and #id <= MAX_ID_LENGTH and #ids < MAX_CONTRACTS then
			table.insert(ids, id)
			table.insert(progress, wholeNumber((source.progress :: { unknown })[index], 0, 1000) or 0)
		end
	end
	return { day = day, ids = ids, progress = progress, bonus = source.bonus == true }
end

-- The rewards' records from whatever a DataStore or a change hands over, the known ones each in its own shape. A record
-- this version does not know (a newer server's) is kept as it is when it comes from the store (`fromStore`), so a server
-- that has not been updated yet never writes it away; a change may only set the known ones.
local function sanitizeState(raw: unknown, fromStore: boolean): { [string]: any }
	local state: { [string]: any } = {}
	if type(raw) ~= "table" then
		return state
	end
	local source = raw :: { [string]: unknown }
	if source.daily ~= nil then
		state.daily = DailyRewards.sanitize(source.daily)
	end
	if source.contracts ~= nil then
		state.contracts = sanitizeContracts(source.contracts)
	end
	if source.pity ~= nil then
		state.pity = Cases.sanitizeCounts(source.pity, Cases.PityLimit)
	end
	if fromStore then
		for name, record in source do
			if type(name) == "string" and #name <= MAX_ID_LENGTH and table.find(STATE_KEYS, name) == nil then
				state[name] = record
			end
		end
	end
	return state
end

-- A wallet from whatever a DataStore handed back: coins as a whole number, and every item id it holds. Ids the shop does
-- not sell (any more) are kept, so taking an item off sale never takes it from those who bought it.
local function sanitize(data: unknown): Holdings
	local holdings = newHoldings()
	if type(data) ~= "table" then
		return holdings
	end
	local source = data :: { [string]: unknown }
	local coins = source.coins
	if type(coins) == "number" and coins == coins then
		holdings.coins = clampCoins(math.floor(coins))
	end
	local owned = source.owned
	if type(owned) == "table" then
		for _, id in owned :: { unknown } do
			if type(id) == "string" and #id > 0 and #id <= MAX_ID_LENGTH then
				holdings.owned[id] = true
			end
		end
	end
	holdings.cases = Cases.sanitizeCounts(source.cases, MAX_CASES)
	holdings.state = sanitizeState(source.state, true)
	local receipts = source.receipts
	if type(receipts) == "table" then
		for _, id in receipts :: { unknown } do
			if type(id) == "string" then
				holdings.receipts[id] = true
			end
		end
	end
	return holdings
end

local function receiptsOf(data: unknown): { string }
	local receipts: { string } = {}
	if type(data) == "table" then
		local list = (data :: { [string]: unknown }).receipts
		if type(list) == "table" then
			for _, id in list :: { unknown } do
				if type(id) == "string" then
					table.insert(receipts, id)
				end
			end
		end
	end
	return receipts
end

local function sortedIds(owned: { [string]: boolean }): { string }
	local ids: { string } = {}
	for id in owned do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- What is stored: the wallet, with the purchases and batches the stored copy `old` remembered.
local function toSaved(old: unknown, holdings: Holdings): { [string]: any }
	local cases: { [string]: number } = {}
	for id, count in holdings.cases do
		if count > 0 then
			cases[id] = count
		end
	end
	return {
		v = SAVE_VERSION,
		coins = holdings.coins,
		owned = sortedIds(holdings.owned),
		cases = cases,
		state = holdings.state,
		receipts = receiptsOf(old),
		batches = if type(old) == "table" then (old :: any).batches else nil,
	}
end

-- Adds `extra` onto `into`: coins and cases add up (a wallet never holds less than none), items join the set, and
-- records replace the ones they name.
local function merge(into: Holdings, extra: Holdings)
	into.coins = clampCoins(into.coins + extra.coins)
	for id in extra.owned do
		into.owned[id] = true
	end
	for id, count in extra.cases do
		into.cases[id] = math.clamp((into.cases[id] or 0) + count, 0, MAX_CASES)
	end
	for name, record in extra.state do
		into.state[name] = record
	end
end

function Wallet.new(onOwned: (player: Player) -> (), options: Options?): Wallet
	local testing = options ~= nil
	local background = if options ~= nil and options.background ~= nil then options.background else true
	local retryDelay = if options ~= nil and options.retryDelay ~= nil then options.retryDelay else 2
	local reloadDelay = if options ~= nil and options.reloadDelay ~= nil then options.reloadDelay else RELOAD_DELAY
	-- In Studio a store that cannot be read is nearly always one Studio may not use (its access to API services is off).
	local giveUpUnread = if options ~= nil and options.giveUpUnread ~= nil
		then options.giveUpUnread
		else not testing and RunService:IsStudio()
	local session = if options ~= nil and options.session ~= nil
		then options.session
		else HttpService:GenerateGUID(false)
	local remote: RemoteEvent
	if options ~= nil and options.remote ~= nil then
		remote = options.remote
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = "Shop"
		remote.Parent = ReplicatedStorage
	end

	local store: any = nil
	if options ~= nil and options.store ~= nil then
		store = options.store
	elseif not testing then
		local opened, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if opened then
			store = result
		else
			warnOnce(tostring(result))
		end
	end

	-- By UserId, so a player who just left keeps theirs until it is saved.
	local profiles: { [number]: Profile } = {}
	local lastRequest: { [Player]: number } = {}
	local sequence = 0
	local running = true

	local function total(profile: Profile): Holdings
		local holdings = newHoldings()
		merge(holdings, profile.base)
		-- The cases receipts granted are in the store already, like `base`, so they count before any change made since: a
		-- case opened from a pack is taken off the pack's count, not off a stored count that had none to give (where the
		-- floor at zero would lose the opening and leave the case to be opened again).
		for purchase, grant in profile.grantedCases do
			if not profile.base.receipts[purchase] then
				holdings.cases[grant.case] = math.clamp((holdings.cases[grant.case] or 0) + grant.count, 0, MAX_CASES)
			end
		end
		local batch = profile.batch
		if batch ~= nil then
			merge(holdings, batch.delta)
		end
		merge(holdings, profile.pending)
		for id in profile.granted do
			holdings.owned[id] = true
		end
		return holdings
	end

	local listeners: { (player: Player) -> () } = {}

	local function publish(profile: Profile)
		local player = profile.player
		if player == nil then
			return
		end
		local holdings = total(profile)
		player:SetAttribute("Coins", holdings.coins)
		player:SetAttribute("Owned", Shop.formatOwned(holdings.owned))
		player:SetAttribute("WalletReady", profile.loaded)
		for _, listener in listeners do
			task.spawn(listener, player)
		end
	end

	-- Tells the garage what the player owns may have changed, so it dresses them again.
	local function notify(profile: Profile)
		local player = profile.player
		if player ~= nil and profiles[profile.userId] == profile then
			onOwned(player)
		end
	end

	local function ownedKey(profile: Profile): string
		return table.concat(sortedIds(total(profile).owned), ",")
	end

	local function key(userId: number): string
		return "u" .. userId
	end

	-- Adds a profile's unsaved changes to its stored wallet. A batch that fails keeps its number and is tried again as it
	-- is; changes made meanwhile wait for the next batch. True when nothing is left to write.
	local function write(profile: Profile): boolean
		local batch = profile.batch
		if batch == nil then
			if isEmpty(profile.pending) then
				return true
			end
			sequence += 1
			batch = { delta = profile.pending, sequence = sequence }
			profile.pending = newHoldings()
			profile.batch = batch
		end
		local current = batch :: Batch
		local wasLoaded = profile.loaded
		local before = ownedKey(profile)
		local written: Holdings? = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key(profile.userId), function(old: any): any
				local holdings = sanitize(old)
				written = holdings
				if Standings.hasBatch(old, session, current.sequence) then
					-- This batch landed on an earlier try whose reply was lost.
					return nil
				end
				merge(holdings, current.delta)
				local saved = toSaved(old, holdings)
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
		-- What a write returns is the stored wallet, newer than any read still on its way.
		profile.base = result
		profile.loaded = true
		for purchase in profile.grantedCases do
			if result.receipts[purchase] then
				profile.grantedCases[purchase] = nil
			end
		end
		publish(profile)
		if not wasLoaded or ownedKey(profile) ~= before then
			-- The stored wallet held something this server did not know about (it had not been read yet).
			notify(profile)
		end
		return true
	end

	local function save(profile: Profile)
		if profile.saving or store == nil then
			return
		end
		profile.saving = true
		local ok = write(profile)
		if ok and next(profile.pending.owned) ~= nil then
			-- A purchase made while that write was on its way goes straight after it, not with the next batch of coins.
			ok = write(profile)
		end
		if ok then
			profile.failures = 0
		else
			profile.failures += 1
		end
		profile.saving = false
		profile.lastSave = os.clock()
	end

	local function unsaved(profile: Profile): boolean
		return profile.batch ~= nil or not isEmpty(profile.pending)
	end

	-- Carries on without the store, as if there were none: everything lasts for the session. Only for a store that cannot
	-- be read in Studio (see giveUpUnread), so the shop can still be tried there; test purchases in Studio are free. A live
	-- server keeps trying instead.
	local function sessionOnly()
		if store == nil then
			return
		end
		store = nil
		warn("[REALSTEEL] Wallets last for the session: their store cannot be read here")
		for _, other in profiles do
			if not other.loaded then
				other.loaded = true
				publish(other)
				notify(other)
			end
		end
	end

	-- Reads the stored wallet so the player's coins and items can be shown and used. Saving does not depend on it. A
	-- wallet that cannot be read is tried again later (see tick).
	local function load(profile: Profile)
		local current = store
		if current == nil or profile.loaded or profile.loading then
			return
		end
		profile.loading = true
		for attempt = 1, LOAD_ATTEMPTS do
			local ok, data = pcall(function()
				return current:GetAsync(key(profile.userId))
			end)
			if ok then
				if not profile.loaded then
					profile.base = sanitize(data)
					profile.loaded = true
					for purchase in profile.grantedCases do
						if profile.base.receipts[purchase] then
							profile.grantedCases[purchase] = nil
						end
					end
				end
				break
			end
			warnOnce(tostring(data))
			if attempt < LOAD_ATTEMPTS then
				task.wait(retryDelay * attempt)
			end
		end
		profile.loading = false
		profile.nextLoad = os.clock() + reloadDelay
		if not profile.loaded and giveUpUnread then
			-- Marks every unread wallet as read, this one too, and tells the garage.
			sessionOnly()
		elseif profile.loaded then
			publish(profile)
			notify(profile)
		end
	end

	local function profileOf(player: Player?): Profile?
		if player == nil then
			return nil
		end
		local profile = profiles[player.UserId]
		return if profile ~= nil and profile.player == player then profile else nil
	end

	local function owns(player: Player, item: string): boolean
		local profile = profileOf(player)
		if profile == nil then
			return false
		end
		if profile.base.owned[item] or profile.pending.owned[item] or profile.granted[item] then
			return true
		end
		local batch = profile.batch
		return batch ~= nil and batch.delta.owned[item] == true
	end

	local function buy(player: Player, id: string): boolean
		local profile = profileOf(player)
		local item = Shop.item(id)
		if profile == nil or item == nil or item.coins == nil or not profile.loaded or owns(player, id) then
			-- Nor while the stored wallet is unread: they might own it already.
			return false
		end
		if total(profile).coins < item.coins then
			return false
		end
		profile.pending.coins -= item.coins
		profile.pending.owned[id] = true
		publish(profile)
		onOwned(player)
		-- A purchase is written at once rather than with the next batch of coins.
		task.spawn(save, profile)
		return true
	end

	local function handle(player: Player, action: unknown, item: unknown)
		if action ~= "buy" or type(item) ~= "string" or profileOf(player) == nil then
			return
		end
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now
		buy(player, item)
	end
	local connection = remote.OnServerEvent:Connect(handle)

	local function ready(player: Player): boolean
		local profile = profileOf(player)
		return profile ~= nil and profile.loaded
	end

	local function view(player: Player): View?
		local profile = profileOf(player)
		if profile == nil then
			return nil
		end
		local holdings = total(profile)
		local state: { [string]: any } = {}
		for _, name in STATE_KEYS do
			local record = holdings.state[name]
			state[name] = if type(record) == "table" then table.clone(record) else record
		end
		return { coins = holdings.coins, owned = holdings.owned, cases = holdings.cases, state = state }
	end

	local function apply(player: Player, change: Change, urgent: boolean?): boolean
		local profile = profileOf(player)
		if profile == nil or not profile.loaded then
			return false
		end
		local pending = profile.pending
		-- `pending` is a change, not a balance: what is spent stays negative until it is written.
		if change.coins ~= nil then
			pending.coins = math.clamp(pending.coins + math.floor(change.coins), -Shop.MaxCoins, Shop.MaxCoins)
		end
		local gotItem = false
		if change.owned ~= nil then
			for _, id in change.owned do
				if type(id) == "string" and #id > 0 and #id <= MAX_ID_LENGTH then
					pending.owned[id] = true
					gotItem = true
				end
			end
		end
		if change.cases ~= nil then
			for id, count in change.cases do
				if Cases.get(id) ~= nil then
					pending.cases[id] = math.clamp((pending.cases[id] or 0) + math.floor(count), -MAX_CASES, MAX_CASES)
				end
			end
		end
		if change.state ~= nil then
			for name, record in sanitizeState(change.state, false) do
				pending.state[name] = record
			end
		end
		publish(profile)
		if gotItem then
			notify(profile)
		end
		if urgent then
			task.spawn(save, profile)
		end
		return true
	end

	-- A pack of cases bought with Robux. Granted inside one UpdateAsync that records the PurchaseId, like an item; the cases
	-- count for the session once that write has landed (see `grantedCases`). A write that fails grants nothing yet:
	-- Roblox tries the receipt again, and a count, unlike an item, must not be granted twice.
	local function processCaseReceipt(
		receipt: { [string]: any },
		case: Cases.Case,
		pack: Cases.Pack
	): Enum.ProductPurchaseDecision
		local userId = receipt.PlayerId
		local purchase = tostring(receipt.PurchaseId)
		if type(userId) ~= "number" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if store == nil then
			local profile = profiles[userId]
			if profile == nil then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			profile.grantedCases[purchase] = { case = case.id, count = pack.count }
			publish(profile)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local landed = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(old: any): any
				landed = true
				local receipts = receiptsOf(old)
				if table.find(receipts, purchase) ~= nil then
					-- Granted on an earlier try whose reply was lost.
					return nil
				end
				local holdings = sanitize(old)
				holdings.cases[case.id] = math.clamp((holdings.cases[case.id] or 0) + pack.count, 0, MAX_CASES)
				table.insert(receipts, purchase)
				while #receipts > RECEIPT_MEMORY do
					table.remove(receipts, 1)
				end
				local saved = toSaved(old, holdings)
				saved.receipts = receipts
				return saved
			end)
		end)
		if not ok or not landed then
			if not ok then
				warnOnce(tostring(err))
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local profile = profiles[userId]
		if profile ~= nil then
			profile.grantedCases[purchase] = { case = case.id, count = pack.count }
			publish(profile)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
		local packCase, pack = Cases.packByProduct(receipt.ProductId)
		if packCase ~= nil and pack ~= nil then
			return processCaseReceipt(receipt, packCase, pack)
		end
		local item = Shop.byProduct(receipt.ProductId)
		local userId = receipt.PlayerId
		local purchase = tostring(receipt.PurchaseId)
		if item == nil or type(userId) ~= "number" then
			-- Not something this server sells (an older or newer server's product): leave it for Roblox to try again.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local profile = profiles[userId]
		if store == nil then
			-- Nowhere to save it: the purchase lasts for the session, and only while the buyer is here to have it.
			if profile == nil then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			profile.granted[item.id] = true
		else
			local landed = false
			local ok, err = pcall(function()
				store:UpdateAsync(key(userId), function(old: any): any
					landed = true
					local receipts = receiptsOf(old)
					if table.find(receipts, purchase) ~= nil then
						-- Granted on an earlier try whose reply was lost.
						return nil
					end
					local holdings = sanitize(old)
					holdings.owned[item.id] = true
					table.insert(receipts, purchase)
					while #receipts > RECEIPT_MEMORY do
						table.remove(receipts, 1)
					end
					local saved = toSaved(old, holdings)
					saved.receipts = receipts
					return saved
				end)
			end)
			if not ok or not landed then
				if not ok then
					warnOnce(tostring(err))
				end
				-- They paid, so they have it for the session now; Roblox tries the receipt again until it is saved, and
				-- its PurchaseId keeps that from granting it twice.
				local present = profiles[userId]
				if present ~= nil then
					present.granted[item.id] = true
					publish(present)
					notify(present)
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			profile = profiles[userId]
			if profile ~= nil then
				profile.granted[item.id] = true
			end
		end
		if profile ~= nil then
			publish(profile)
			notify(profile)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local function matchEnded(mode: string, level: number, owners: { [number]: Player? }, winner: number)
		for seat = 1, 2 do
			local player = owners[seat]
			local profile = if player ~= nil then profiles[player.UserId] else nil
			if profile ~= nil then
				local amount = Shop.reward(mode, level, seat == winner)
				if amount > 0 then
					-- `pending` is a change, not a balance: a coin purchase not yet written makes it negative, and that has
					-- to stay so.
					profile.pending.coins = math.clamp(profile.pending.coins + amount, -Shop.MaxCoins, Shop.MaxCoins)
					publish(profile)
				end
			end
		end
	end

	-- Wallets that could not be read are read again; what is due is saved; players who left are forgotten once nothing of
	-- theirs is left unsaved (or the store has refused it for about a minute).
	local function tick()
		local now = os.clock()
		for userId, profile in profiles do
			local departed = profile.player == nil
			if
				not departed
				and store ~= nil
				and not profile.loaded
				and not profile.loading
				and now >= profile.nextLoad
			then
				task.spawn(load, profile)
			end
			if unsaved(profile) and (departed or now - profile.lastSave >= SAVE_DELAY) then
				task.spawn(save, profile)
			end
			if
				departed
				and now - profile.leftAt >= KEEP_AFTER_LEAVING
				and (not unsaved(profile) or store == nil or profile.failures >= DEPARTED_TRIES)
				and not profile.saving
			then
				profiles[userId] = nil
			end
		end
	end

	if background then
		task.spawn(function()
			while running do
				task.wait(5)
				tick()
			end
		end)
	end

	local self: Wallet = {
		add = function(player: Player)
			local existing = profiles[player.UserId]
			if existing ~= nil then
				-- Back before their last session was forgotten: carry on with it (and read the stored wallet if that never
				-- worked).
				existing.player = player
				publish(existing)
				onOwned(player)
				task.spawn(load, existing)
				return
			end
			local profile: Profile = {
				userId = player.UserId,
				player = player,
				leftAt = 0,
				base = newHoldings(),
				batch = nil,
				pending = newHoldings(),
				granted = {},
				grantedCases = {},
				-- A session wallet has nothing to read.
				loaded = store == nil,
				loading = false,
				nextLoad = 0,
				saving = false,
				lastSave = os.clock(),
				failures = 0,
			}
			profiles[player.UserId] = profile
			publish(profile)
			task.spawn(load, profile)
		end,
		remove = function(player: Player)
			lastRequest[player] = nil
			local profile = profileOf(player)
			if profile == nil then
				return
			end
			profile.player = nil
			profile.leftAt = os.clock()
			if unsaved(profile) then
				task.spawn(save, profile)
			end
		end,
		owns = owns,
		coins = function(player: Player): number
			local profile = profileOf(player)
			return if profile ~= nil then total(profile).coins else 0
		end,
		matchEnded = matchEnded,
		buy = buy,
		ready = ready,
		view = view,
		apply = apply,
		watch = function(listener: (player: Player) -> ())
			table.insert(listeners, listener)
		end,
		handle = handle,
		processReceipt = processReceipt,
		tick = tick,
		saveAll = function()
			if store == nil then
				return
			end
			local started = os.clock()
			repeat
				local waiting = false
				for _, profile in profiles do
					if unsaved(profile) then
						waiting = true
						if not profile.saving then
							task.spawn(save, profile)
						end
					end
				end
				if waiting then
					task.wait(0.5)
				end
			until not waiting or os.clock() - started > SHUTDOWN_WAIT
		end,
		destroy = function()
			running = false
			connection:Disconnect()
		end,
	}
	return self
end

return Wallet
