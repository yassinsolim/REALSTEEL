--!strict

-- The daily reward: once a day (by the server's clock, in UTC days) a player can claim the next day of a seven-day cycle,
-- coins that grow through the week and a case on the seventh day. Claiming on consecutive days carries the streak on;
-- missing a whole day starts it again from the first day. Nothing is lost by claiming late in the day, and nothing
-- counts down on screen: the reward simply waits until the player claims it. Pure data and arithmetic, so it can be tested
-- without Roblox; the server keeps each player's state in their wallet (see Rewards on the server).

export type Reward = {
	coins: number,
	-- Cases of this id, if any (see Cases).
	cases: number?,
	case: string?,
}

export type State = {
	-- The UTC day (whole days since 1970) of the last claim, 0 for never.
	day: number,
	-- How many days in a row the player has claimed, up to and including that day.
	streak: number,
}

export type Status = {
	-- Whether a reward can be claimed now.
	ready: boolean,
	-- The streak the next claim makes, and the day of the cycle (1 to #Cycle) it pays.
	streak: number,
	cycleDay: number,
	-- Whether the next claim starts the streak again because a day was missed.
	broken: boolean,
}

local DailyRewards = {}

DailyRewards.Cycle = {
	{ coins = 75 },
	{ coins = 100 },
	{ coins = 150 },
	{ coins = 200 },
	{ coins = 250 },
	{ coins = 300 },
	{ coins = 100, cases = 1, case = "case.foundry" },
} :: { Reward }

local DAY = 86400

-- The UTC day a moment (seconds since 1970) falls on.
function DailyRewards.dayOf(seconds: number): number
	return math.floor(seconds / DAY)
end

function DailyRewards.new(): State
	return { day = 0, streak = 0 }
end

-- Whatever a save file says, as a valid state.
function DailyRewards.sanitize(raw: unknown): State
	if type(raw) ~= "table" then
		return DailyRewards.new()
	end
	local source = raw :: { [string]: unknown }
	local day = source.day
	local streak = source.streak
	if type(day) ~= "number" or day ~= day or type(streak) ~= "number" or streak ~= streak then
		return DailyRewards.new()
	end
	return { day = math.max(0, math.floor(day)), streak = math.max(0, math.floor(streak)) }
end

function DailyRewards.status(state: State, today: number): Status
	if state.day >= today and state.day > 0 then
		local cycleDay = (math.max(state.streak, 1) - 1) % #DailyRewards.Cycle + 1
		return { ready = false, streak = state.streak, cycleDay = cycleDay, broken = false }
	end
	local continues = state.day > 0 and state.day == today - 1
	local streak = if continues then state.streak + 1 else 1
	return {
		ready = true,
		streak = streak,
		cycleDay = (streak - 1) % #DailyRewards.Cycle + 1,
		broken = state.day > 0 and not continues,
	}
end

-- Claims today's reward: what it pays and the state after, or nil and the state unchanged when it was claimed already.
function DailyRewards.claim(state: State, today: number): (Reward?, State)
	local status = DailyRewards.status(state, today)
	if not status.ready then
		return nil, state
	end
	return DailyRewards.Cycle[status.cycleDay], { day = today, streak = status.streak }
end

return DailyRewards
