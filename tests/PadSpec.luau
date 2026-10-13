--!strict

-- Headless checks for the pads in front of the main ring (PadRules): who holds a pad, when its countdown runs out, and
-- what it asks for then. Run from Studio's command bar, or without Studio through scripts/run-specs.ps1:
--   local passed, failures = require(game.ReplicatedStorage.Tests.PadSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PadRules = require(ReplicatedStorage.Shared.PadRules)

local A, B, C = 101, 202, 303
local SOLO, PAIR = 2, 3
local PADS: { PadRules.PadSpec } = {
	{ name = "BotHard", kind = "bot", level = 3, seat = 0, x = -14, z = 33 },
	{ name = "Training", kind = "training", level = 0, seat = 0, x = 14, z = 33 },
	{ name = "VersusBlue", kind = "versus", level = 0, seat = 1, x = -4, z = 33 },
	{ name = "VersusRed", kind = "versus", level = 0, seat = 2, x = 4, z = 33 },
}
local BOT = { x = -14, z = 33 }
local TRAINING = { x = 14, z = 33 }
local BLUE = { x = -4, z = 33 }
local RED = { x = 4, z = 33 }
local AWAY = { x = 0, z = 50 }

local function at(id: number, spot: { x: number, z: number }, free: boolean?): PadRules.Presence
	return { id = id, x = spot.x, z = spot.z, free = free ~= false }
end

local function holder(board: PadRules.Board, name: string): number
	return board.state[name].holder
end

local function describe(triggers: { PadRules.Trigger }): string
	local parts = {}
	for _, trigger in triggers do
		table.insert(parts, `{trigger.kind}{trigger.level}:{table.concat(trigger.ids, ",")}`)
	end
	return if #parts == 0 then "none" else table.concat(parts, " ")
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

	-- A bot pad: stepping on takes it and starts its countdown, stepping off cancels, and standing long enough asks for a
	-- bot match at the pad's level, once.
	do
		local board = PadRules.new(PADS, 2.45, SOLO, PAIR)
		PadRules.update(board, { at(A, AWAY) }, 0)
		check("nobody holds an empty pad", holder(board, "BotHard") == 0)
		check("an empty pad counts nothing down", PadRules.countdown(board, "BotHard", 0) == nil)
		PadRules.update(board, { at(A, { x = -14 + 2.3, z = 33 }) }, 1)
		check("stepping on a pad's edge takes it", holder(board, "BotHard") == A)
		check("and starts its countdown", PadRules.countdown(board, "BotHard", 1) == SOLO)
		check("which runs down", PadRules.countdown(board, "BotHard", 2) == SOLO - 1)
		check("stepping off cancels it", describe(PadRules.update(board, { at(A, AWAY) }, 2.5)) == "none")
		check("and frees the pad", holder(board, "BotHard") == 0)
		PadRules.update(board, { at(A, BOT) }, 3)
		check("not yet", describe(PadRules.update(board, { at(A, BOT) }, 3 + SOLO - 0.1)) == "none")
		local fired = PadRules.update(board, { at(A, BOT) }, 3 + SOLO)
		check("standing long enough asks for a bot at the pad's level", describe(fired) == "bot3:101", describe(fired))
		check("once", describe(PadRules.update(board, { at(A, BOT) }, 3 + SOLO + 5)) == "none")
		check("and the pad is free for the next player", holder(board, "BotHard") == 0)
		PadRules.update(board, { at(A, BOT), at(B, BOT) }, 20)
		check("who can take it with the first still standing there", holder(board, "BotHard") == B)
		PadRules.update(board, { at(A, AWAY), at(B, AWAY) }, 21)
		PadRules.update(board, { at(A, BOT) }, 22)
		check("stepping off and on again counts again", holder(board, "BotHard") == A)
	end

	-- The first one on keeps a pad, players in a ring hold none, and players who leave are forgotten.
	do
		local board = PadRules.new(PADS, 2.45, SOLO, PAIR)
		PadRules.update(board, { at(A, TRAINING) }, 0)
		PadRules.update(board, { at(A, TRAINING), at(B, TRAINING) }, 1)
		check("the first one on keeps the pad", holder(board, "Training") == A)
		local fired = PadRules.update(board, { at(A, TRAINING), at(B, TRAINING) }, SOLO)
		check("a training pad asks for training", describe(fired) == "training0:101", describe(fired))
		PadRules.update(board, { at(C, TRAINING, false) }, 10)
		check("a player in a ring holds no pad", holder(board, "Training") == 0)
		PadRules.update(board, {}, 11)
		check("players who leave are forgotten", next(board.standing) == nil and next(board.spent) == nil)
	end

	-- The 1V1 pads count down once a different player stands on each, and ask for a 1v1 with the blue pad's player first.
	do
		local board = PadRules.new(PADS, 2.45, SOLO, PAIR)
		PadRules.update(board, { at(A, BLUE) }, 0)
		check("one 1V1 pad alone counts nothing down", PadRules.countdown(board, "VersusBlue", 0) == nil)
		check("and asks for nothing", describe(PadRules.update(board, { at(A, BLUE) }, 30)) == "none")
		check("however long it waits", holder(board, "VersusBlue") == A)
		PadRules.update(board, { at(A, BLUE), at(B, RED) }, 31)
		check(
			"both held count down together",
			PadRules.countdown(board, "VersusBlue", 31) == PAIR
				and PadRules.countdown(board, "VersusRed", 32) == PAIR - 1
		)
		PadRules.update(board, { at(A, BLUE), at(B, AWAY) }, 32)
		check("either stepping off cancels", PadRules.countdown(board, "VersusBlue", 32) == nil)
		PadRules.update(board, { at(A, BLUE), at(C, RED) }, 33)
		check("a new challenger starts it over", PadRules.countdown(board, "VersusRed", 34) == PAIR - 1)
		local fired = PadRules.update(board, { at(A, BLUE), at(C, RED) }, 33 + PAIR)
		check("the countdown asks for a 1v1, blue first", describe(fired) == "versus0:101,303", describe(fired))
		check("and frees both pads", holder(board, "VersusBlue") == 0 and holder(board, "VersusRed") == 0)
		check("once", describe(PadRules.update(board, { at(A, BLUE), at(C, RED) }, 40)) == "none")
		PadRules.update(board, { at(C, BLUE), at(A, RED) }, 50)
		check("swapping pads is a new pair", PadRules.countdown(board, "VersusBlue", 50) == PAIR)
		local swapped = PadRules.update(board, { at(C, BLUE), at(A, RED) }, 50 + PAIR)
		check("with the seats swapped", describe(swapped) == "versus0:303,101", describe(swapped))
	end

	return passed, failures
end
