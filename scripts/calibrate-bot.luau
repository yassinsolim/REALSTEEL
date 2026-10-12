-- Bot calibration: plays the three bot levels against each other, against three stand-in humans, and against the scripted
-- dummy, and prints win rates. Run it with scripts/calibrate-bot.ps1, which bundles the pure shared modules with this file
-- and runs them in the standalone Luau interpreter. `load` and `ROUNDS` come from that bundle. The stand-ins are only
-- here for calibration; they are not part of the game.
local FightConfig = load("FightConfig")
local FightSim = load("FightSim")
local BotBrain = load("BotBrain")
local State = FightSim.State

-- Human stand-ins, only for calibration (never shipped). They only read and punish; the neutral-game fields stay at zero.
local ROOKIE = { name = "ROOKIE", reaction = 30, think = 45, aggression = 0.35, guardSeen = 0.1, dodgeSeen = 0, counter = 0, preGuard = 0.1, punish = 0.05, mistake = 0.35, dash = 0.02, strafe = 0.1, lead = 0, snipe = 0, wary = 0, guardOut = 0, stick = 0, follow = 0, mix = { 5, 3, 2, 2 } }
local AVERAGE = { name = "AVERAGE", reaction = 17, think = 22, aggression = 0.5, guardSeen = 0.4, dodgeSeen = 0.05, counter = 0, preGuard = 0.12, punish = 0.3, mistake = 0.15, dash = 0.08, strafe = 0.2, lead = 0, snipe = 0, wary = 0, guardOut = 0, stick = 0, follow = 0, mix = { 4, 3, 2, 2 } }
local GOOD = { name = "GOOD", reaction = 12, think = 18, aggression = 0.55, guardSeen = 0.6, dodgeSeen = 0.15, counter = 0.1, preGuard = 0.18, punish = 0.55, mistake = 0.08, dash = 0.12, strafe = 0.25, lead = 0, snipe = 0, wary = 0, guardOut = 0, stick = 0, follow = 0, mix = { 4, 3, 2, 2 } }
table.insert(BotBrain.Levels, ROOKIE)
table.insert(BotBrain.Levels, AVERAGE)
table.insert(BotBrain.Levels, GOOD)
BotBrain.LevelCount = #BotBrain.Levels
local IDX = { EASY = 1, MEDIUM = 2, HARD = 3, ROOKIE = 4, AVERAGE = 5, GOOD = 6 }

local function botController(level, salt)
	return function(tick, me, foe, into) BotBrain.input(tick, me, foe, into, level, salt) end
end
local function dummyController(mode)
	return function(tick, me, foe, into) FightSim.dummyInput(tick, me, foe, into, mode) end
end

local function playRound(ctrlA, ctrlB, seed)
	local a, b = FightSim.newFighter(0, 0), FightSim.newFighter(0, 0)
	FightSim.reset(a, b)
	local ia, ib = FightSim.newInput(), FightSim.newInput()
	local options = { training = false, rounds = true, combat = true }
	local tick = seed * 7919 + 13
	for frame = 1, 3600 do
		tick += 1
		ctrlA(tick, a, b, ia)
		ctrlB(tick, b, a, ib)
		FightSim.step(a, b, ia, ib, options)
		if a.state == State.KO or b.state == State.KO then break end
	end
	if a.state == State.KO and b.state == State.KO then return 0 end
	if a.state == State.KO then return 2 end
	if b.state == State.KO then return 1 end
	if a.hp > b.hp then return 1 elseif b.hp > a.hp then return 2 end
	return 0
end

local function versus(makeX, makeY, rounds)
	local x, y, d = 0, 0, 0
	for i = 1, rounds do
		local w
		if i % 2 == 0 then
			w = playRound(makeY(2), makeX(1), i)
			w = if w == 1 then 2 elseif w == 2 then 1 else 0
		else
			w = playRound(makeX(1), makeY(2), i)
		end
		if w == 1 then x += 1 elseif w == 2 then y += 1 else d += 1 end
	end
	return x, y, d
end

-- Scripted players that walk in and mash one attack, which is the first thing most people try. Each closes to its
-- favorite spacing and presses its button every other frame while the opponent is inside its range.
local function masher(field, spacing, range, strafe, dashIn)
	return function()
		return function(tick, me, foe, into)
			local dx, dz = foe.x - me.x, foe.z - me.z
			local d = math.sqrt(dx * dx + dz * dz)
			into.moveX = if strafe then (if (tick // 24) % 2 == 0 then 1 else -1) else 0
			-- The dash-in player keeps walking in; the others hold their spacing.
			into.moveZ = if dashIn then (if d > spacing then 1 else 0) elseif d > spacing + 0.3 then 1 elseif d < spacing - 0.3 then -1 else 0
			into.jab, into.straight, into.leftKick, into.rightKick, into.guard = false, false, false, false, false
			into.dash = dashIn and d > 5.8 and tick % 2 == 0
			if d <= range then into[field] = tick % 2 == 0 end
		end
	end
end

local function bot(name) return function(salt) return botController(IDX[name], salt) end end
local function dummy(mode) return function() return dummyController(mode) end end

local N = tonumber(ROUNDS) or 100
local function report(label, mx, my)
	local x, y, d = versus(mx, my, N)
	print(string.format("%-22s %3d - %3d (draws %d)  first side %.0f%%", label, x, y, d, x / math.max(x + y, 1) * 100))
end

print("-- levels against each other")
report("MEDIUM vs EASY", bot("MEDIUM"), bot("EASY"))
report("HARD vs MEDIUM", bot("HARD"), bot("MEDIUM"))
report("HARD vs EASY", bot("HARD"), bot("EASY"))
print("-- human stand-ins vs levels (first side = the level)")
for _, h in { "ROOKIE", "AVERAGE", "GOOD" } do
	for _, l in { "EASY", "MEDIUM", "HARD" } do
		report(l .. " vs " .. h, bot(l), bot(h))
	end
end
print("-- levels vs the scripted mixed dummy")
for _, l in { "EASY", "MEDIUM", "HARD" } do
	report(l .. " vs DUMMY4", bot(l), dummy(4))
end

print("-- levels vs scripted mashers")
local MASHERS = {
	{ "JAB", masher("jab", 4.3, 4.7, false, false) },
	{ "STRAIGHT", masher("straight", 5.0, 5.4, false, false) },
	{ "DASH+JAB", masher("jab", 4.5, 4.7, false, true) },
	{ "STRAFE+STRAIGHT", masher("straight", 5.0, 5.4, true, false) },
}
for _, m in MASHERS do
	for _, l in { "EASY", "MEDIUM", "HARD" } do
		report(l .. " vs " .. m[1], bot(l), m[2])
	end
end