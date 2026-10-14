--!strict

-- Daily contracts: three small goals a day, picked for each player from the pool below (the same three all day, a new set
-- the next UTC day), each paying coins the moment it is done, and a bonus for finishing all three. They count finished
-- bot matches and 1v1s, the same matches that pay coins (see Shop.Rewards). Every contract can be done against the bots,
-- so a day's set can always be finished alone, however empty the server. Pure data and arithmetic, so it can be tested
-- without Roblox; the server keeps each player's state in their wallet (see Rewards on the server).

export type Contract = {
	id: string,
	text: string,
	goal: number,
	coins: number,
	-- What counts: a match of this mode ("bot" or "versus", nil for either), against a bot of at least this level, won.
	mode: string?,
	minLevel: number?,
	win: boolean?,
	-- Two contracts of a group are never offered on the same day.
	group: string,
}

-- A finished match, from one player's side.
export type Event = {
	mode: string,
	level: number,
	won: boolean,
}

export type State = {
	-- The UTC day the contracts are for, 0 for none yet.
	day: number,
	ids: { string },
	progress: { number },
	-- Whether the bonus for finishing all of them has been paid.
	bonus: boolean,
}

-- What a match did to a player's contracts.
export type Result = {
	state: State,
	completed: { Contract },
	-- Coins earned: the contracts completed, and the bonus if this finished the last one.
	coins: number,
	bonus: boolean,
}

local Contracts = {}

Contracts.PerDay = 3
Contracts.Bonus = 100

Contracts.Pool = {
	{ id = "play3", text = "Play 3 matches", goal = 3, coins = 80, group = "play" },
	{ id = "play5", text = "Play 5 matches", goal = 5, coins = 140, group = "play" },
	{ id = "botwin2", text = "Beat 2 bots", goal = 2, coins = 100, mode = "bot", win = true, group = "botwins" },
	{ id = "botwin4", text = "Beat 4 bots", goal = 4, coins = 170, mode = "bot", win = true, group = "botwins" },
	{
		id = "medium",
		text = "Beat a MEDIUM or HARD bot",
		goal = 1,
		coins = 120,
		mode = "bot",
		minLevel = 2,
		win = true,
		group = "level",
	},
	{
		id = "hard",
		text = "Beat a HARD bot",
		goal = 1,
		coins = 200,
		mode = "bot",
		minLevel = 3,
		win = true,
		group = "level",
	},
} :: { Contract }

function Contracts.get(id: unknown): Contract?
	for _, contract in Contracts.Pool do
		if contract.id == id then
			return contract
		end
	end
	return nil
end

-- A small seeded generator, so a player's contracts for a day are the same on every server.
local MODULUS = 2147483647
local function generator(userId: number, day: number): () -> number
	local seed = (math.abs(math.floor(userId)) % MODULUS * 7919 + math.floor(day) * 104729) % MODULUS
	if seed == 0 then
		seed = 1
	end
	return function(): number
		seed = (seed * 48271) % MODULUS
		return seed / MODULUS
	end
end

-- The contracts a player gets on a day: PerDay of the pool in a shuffled order, one per group.
function Contracts.picks(userId: number, day: number): { Contract }
	local nextNumber = generator(userId, day)
	local order: { Contract } = table.clone(Contracts.Pool)
	for index = #order, 2, -1 do
		local other = math.floor(nextNumber() * index) + 1
		order[index], order[other] = order[other], order[index]
	end
	local picked: { Contract } = {}
	local groups: { [string]: boolean } = {}
	for _, contract in order do
		if not groups[contract.group] then
			groups[contract.group] = true
			table.insert(picked, contract)
			if #picked == Contracts.PerDay then
				break
			end
		end
	end
	return picked
end

-- A player's contracts for `day`: the stored ones if they are for that day, a fresh set otherwise.
function Contracts.forDay(raw: unknown, userId: number, day: number): State
	if type(raw) == "table" then
		local source = raw :: { [string]: unknown }
		local ids = source.ids
		local progress = source.progress
		if source.day == day and type(ids) == "table" and type(progress) == "table" then
			local state: State = { day = day, ids = {}, progress = {}, bonus = source.bonus == true }
			for index, id in ids :: { unknown } do
				local contract = Contracts.get(id)
				local count = (progress :: { unknown })[index]
				if contract ~= nil then
					table.insert(state.ids, contract.id)
					table.insert(
						state.progress,
						if type(count) == "number" and count == count
							then math.clamp(math.floor(count), 0, contract.goal)
							else 0
					)
				end
			end
			if #state.ids > 0 then
				return state
			end
		end
	end
	local state: State = { day = day, ids = {}, progress = {}, bonus = false }
	for _, contract in Contracts.picks(userId, day) do
		table.insert(state.ids, contract.id)
		table.insert(state.progress, 0)
	end
	return state
end

local function counts(contract: Contract, event: Event): boolean
	if contract.mode ~= nil and contract.mode ~= event.mode then
		return false
	end
	if event.mode ~= "bot" and event.mode ~= "versus" then
		return false
	end
	if contract.minLevel ~= nil and (event.mode ~= "bot" or event.level < contract.minLevel) then
		return false
	end
	if contract.win == true and not event.won then
		return false
	end
	return true
end

-- Counts a finished match toward the contracts in `state` (already for the right day).
function Contracts.record(state: State, event: Event): Result
	local after: State =
		{ day = state.day, ids = table.clone(state.ids), progress = table.clone(state.progress), bonus = state.bonus }
	local completed: { Contract } = {}
	local coins = 0
	for index, id in after.ids do
		local contract = Contracts.get(id)
		local count = after.progress[index] or 0
		if contract ~= nil and count < contract.goal and counts(contract, event) then
			count += 1
			after.progress[index] = count
			if count >= contract.goal then
				table.insert(completed, contract)
				coins += contract.coins
			end
		end
	end
	local bonus = false
	if not after.bonus and Contracts.allDone(after) then
		after.bonus = true
		bonus = true
		coins += Contracts.Bonus
	end
	return { state = after, completed = completed, coins = coins, bonus = bonus }
end

function Contracts.allDone(state: State): boolean
	if #state.ids == 0 then
		return false
	end
	for index, id in state.ids do
		local contract = Contracts.get(id)
		if contract ~= nil and (state.progress[index] or 0) < contract.goal then
			return false
		end
	end
	return true
end

return Contracts
