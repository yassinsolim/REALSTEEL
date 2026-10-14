--!strict

-- Server: the reasons to come back. The daily reward (DailyRewards), the day's contracts (Contracts) and the cases
-- (Cases), all kept in the player's wallet (see Wallet) so they are saved with their coins. Players ask through the
-- Rewards remote:
--   "sync"                     the state is sent again
--   "daily"                    claims today's reward
--   "open", caseId, payWith    opens a case, paid with "coins" or with one of the player's unopened "cases"
--   "buy", caseId, pack        asks Roblox to sell a pack of cases for Robux
-- and hear back through the same remote:
--   "state", State             everything the reward screens show (see `stateFor`)
--   "opened", Opened           what a case gave
--   "notice", text             a short line for the hall: a contract done, a daily reward claimed
--
-- Roblox's paid random items policy: cases bought with Robux are paid random items, so their odds are shown before any
-- purchase (see the case screen), and a player for whom PolicyService says paid random items are restricted is never
-- offered them, and their purchase is never prompted. Until PolicyService answers, and when it fails, nobody is. Cases
-- opened with coins stay open to everyone: coins are only ever earned by playing, never sold.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cases = require(ReplicatedStorage.Shared.Cases)
local Contracts = require(ReplicatedStorage.Shared.Contracts)
local DailyRewards = require(ReplicatedStorage.Shared.DailyRewards)
local Looks = require(ReplicatedStorage.Shared.Looks)
local Wallet = require(script.Parent.Wallet)

export type Rewards = {
	add: (player: Player) -> (),
	remove: (player: Player) -> (),
	-- Counts a finished bot match or 1v1 toward its players' contracts (the same report that pays their coins).
	matchEnded: (mode: string, level: number, owners: { [number]: Player? }, winner: number) -> (),
}

local Rewards = {}

-- A player may open a case this often (the case screen's reveal takes longer), and ask for anything else this often.
local OPEN_COOLDOWN = 1.5
local REQUEST_COOLDOWN = 0.3
-- How often the server checks whether a new day has started for anyone, so their daily reward shows up.
local DAY_CHECK = 30
local POLICY_ATTEMPTS = 3

local function today(): number
	return DailyRewards.dayOf(os.time())
end

function Rewards.new(wallet: Wallet.Wallet): Rewards
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Rewards"
	remote.Parent = ReplicatedStorage

	local random = Random.new()
	-- Whether Roblox lets each player buy paid random items; nil until PolicyService has answered.
	local packsAllowed: { [Player]: boolean } = {}
	local lastRequest: { [Player]: number } = {}
	local lastOpen: { [Player]: number } = {}
	local lastDay: { [Player]: number } = {}
	local pushQueued: { [Player]: boolean } = {}

	local function contractsFor(player: Player, view: Wallet.View, day: number): Contracts.State
		return Contracts.forDay(view.state.contracts, player.UserId, day)
	end

	-- Everything the reward screens show, for one player.
	local function stateFor(player: Player): { [string]: any }
		local day = today()
		local view = wallet.view(player)
		local ready = wallet.ready(player)
		if view == nil then
			return { ready = false, packs = false, today = day }
		end
		local cases = {}
		local pity = view.state.pity or {}
		for _, case in Cases.List do
			table.insert(cases, { id = case.id, count = view.cases[case.id] or 0, pity = pity[case.id] or 0 })
		end
		local daily = DailyRewards.status(DailyRewards.sanitize(view.state.daily), day)
		local contracts = contractsFor(player, view, day)
		local list = {}
		for index, id in contracts.ids do
			local contract = Contracts.get(id)
			if contract ~= nil then
				table.insert(list, {
					id = id,
					text = contract.text,
					goal = contract.goal,
					progress = contracts.progress[index] or 0,
					coins = contract.coins,
				})
			end
		end
		return {
			ready = ready,
			packs = packsAllowed[player] == true,
			today = day,
			coins = view.coins,
			cases = cases,
			daily = {
				ready = ready and daily.ready,
				streak = daily.streak,
				cycleDay = daily.cycleDay,
				broken = daily.broken,
			},
			contracts = { list = list, bonus = contracts.bonus, bonusCoins = Contracts.Bonus },
		}
	end

	-- Sends the state once for any number of changes in the same moment.
	local function push(player: Player)
		if pushQueued[player] then
			return
		end
		pushQueued[player] = true
		task.defer(function()
			pushQueued[player] = nil
			if player.Parent == Players then
				lastDay[player] = today()
				remote:FireClient(player, "state", stateFor(player))
			end
		end)
	end
	wallet.watch(push)

	local function notice(player: Player, text: string)
		remote:FireClient(player, "notice", text)
	end

	local function claimDaily(player: Player)
		local view = wallet.view(player)
		if view == nil or not wallet.ready(player) then
			return
		end
		local reward, after = DailyRewards.claim(DailyRewards.sanitize(view.state.daily), today())
		if reward == nil then
			return
		end
		local change: Wallet.Change = { coins = reward.coins, state = { daily = after } }
		local case = if reward.case ~= nil then Cases.get(reward.case) else nil
		if case ~= nil and reward.cases ~= nil then
			change.cases = { [case.id] = reward.cases }
		end
		if wallet.apply(player, change, true) then
			local text = `DAY {(after.streak - 1) % #DailyRewards.Cycle + 1} REWARD  ·  +{reward.coins} COINS`
			if case ~= nil and reward.cases ~= nil then
				text ..= `  ·  +{reward.cases} {case.name}`
			end
			notice(player, text)
		end
	end

	local function open(player: Player, caseId: unknown, payWith: unknown)
		local case = Cases.get(caseId)
		local view = wallet.view(player)
		if case == nil or view == nil or not wallet.ready(player) then
			return
		end
		if payWith == "case" then
			if (view.cases[case.id] or 0) < 1 then
				return
			end
		elseif payWith == "coins" then
			if view.coins < case.coins then
				return
			end
		else
			return
		end
		local pityTable: { [string]: number } = table.clone(view.state.pity or {})
		local pity = pityTable[case.id] or 0
		local draw = Cases.draw(case, pity, random:NextNumber(), random:NextNumber())
		local duplicate = view.owned[draw.item] == true
		local refund = if duplicate then Cases.Rarities[draw.rarity].refund else 0
		pityTable[case.id] = draw.pityAfter
		local change: Wallet.Change = {
			coins = refund - (if payWith == "coins" then case.coins else 0),
			cases = if payWith == "case" then { [case.id] = -1 } else nil,
			owned = if duplicate then nil else { draw.item },
			state = { pity = pityTable },
		}
		if not wallet.apply(player, change, true) then
			return
		end
		local description = Looks.describe(draw.item)
		remote:FireClient(player, "opened", {
			case = case.id,
			item = draw.item,
			rarity = draw.rarity,
			name = if description ~= nil then description.name else draw.item,
			kind = if description ~= nil then description.kind else "",
			duplicate = duplicate,
			refund = refund,
			pity = draw.pity,
		})
		if draw.rarity >= Cases.PityRarity then
			-- A LEGENDARY or MYTHIC is news for the whole hall.
			for _, other in Players:GetPlayers() do
				if other ~= player then
					notice(
						other,
						`{string.upper(player.DisplayName)} OPENED {Cases.Rarities[draw.rarity].name} {description and description.name or ""}`
					)
				end
			end
		end
	end

	local function buy(player: Player, caseId: unknown, packIndex: unknown)
		local case = Cases.get(caseId)
		local pack = if case ~= nil and type(packIndex) == "number" then case.packs[packIndex] else nil
		if pack == nil or not Cases.forSale(pack) or packsAllowed[player] ~= true then
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, pack.product)
		end)
	end

	remote.OnServerEvent:Connect(function(player: Player, action: unknown, first: unknown, second: unknown)
		local now = os.clock()
		if action == "open" then
			if now - (lastOpen[player] or -math.huge) < OPEN_COOLDOWN then
				return
			end
			lastOpen[player] = now
			open(player, first, second)
			return
		end
		if now - (lastRequest[player] or -math.huge) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now
		if action == "sync" then
			push(player)
		elseif action == "daily" then
			claimDaily(player)
		elseif action == "buy" then
			buy(player, first, second)
		end
	end)

	-- A new day for a player still in the game: their daily reward and contracts change.
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK)
			local day = today()
			for _, player in Players:GetPlayers() do
				if lastDay[player] ~= nil and lastDay[player] ~= day then
					push(player)
				end
			end
		end
	end)

	local function checkPolicy(player: Player)
		for attempt = 1, POLICY_ATTEMPTS do
			local ok, result = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			if ok and type(result) == "table" then
				packsAllowed[player] = result.ArePaidRandomItemsRestricted ~= true
				push(player)
				return
			end
			if player.Parent ~= Players then
				return
			end
			task.wait(2 * attempt)
		end
		-- Unknown: offer no Robux cases rather than risk offering them where they are not allowed.
		packsAllowed[player] = false
		push(player)
	end

	return {
		add = function(player: Player)
			task.spawn(checkPolicy, player)
			push(player)
		end,
		remove = function(player: Player)
			packsAllowed[player] = nil
			lastRequest[player] = nil
			lastOpen[player] = nil
			lastDay[player] = nil
			pushQueued[player] = nil
		end,
		matchEnded = function(mode: string, level: number, owners: { [number]: Player? }, winner: number)
			local day = today()
			for seat = 1, 2 do
				local player = owners[seat]
				local view = if player ~= nil then wallet.view(player) else nil
				if player ~= nil and view ~= nil and wallet.ready(player) then
					local before = contractsFor(player, view, day)
					local result = Contracts.record(before, { mode = mode, level = level, won = seat == winner })
					local changed = result.coins > 0 or result.state.bonus ~= before.bonus
					for index, count in result.state.progress do
						if count ~= before.progress[index] then
							changed = true
						end
					end
					if changed then
						wallet.apply(player, { coins = result.coins, state = { contracts = result.state } })
						for _, contract in result.completed do
							notice(
								player,
								`CONTRACT DONE  ·  {string.upper(contract.text)}  ·  +{contract.coins} COINS`
							)
						end
						if result.bonus then
							notice(player, `ALL CONTRACTS DONE  ·  +{Contracts.Bonus} COINS`)
						end
					end
				end
			end
		end,
	}
end

return Rewards
