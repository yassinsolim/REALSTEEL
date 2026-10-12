-- Balance tournament for the garage: plays loadouts against each other with the bot on both sides and prints win rates. Run it
-- with scripts/balance.ps1, which bundles the pure shared modules with this file and runs them in the standalone Luau
-- interpreter. `load`, `MODE`, `ROUNDS`, `LEVEL` and `SEEDBASE` come from that bundle.
--
-- Modes: chassis (the five stock chassis against each other), modules (each module on each chassis against the same
-- stock chassis), presets (each ready-made build against the five stock chassis) and all (every one of the 135 loadouts
-- against the five stock chassis, with the best, the worst and the main effect of every part).
--
-- This only tells how the bots fare, and a bot reads and reacts like no person: use it to find a build that wins or loses
-- far too often after a change to Loadout, not to settle what is fair.
local FightSim = load("FightSim")
local BotBrain = load("BotBrain")
local Loadout = load("Loadout")
local State = FightSim.State
local N = ROUNDS or 40
local LV = LEVEL or 2
local SEED = SEEDBASE or 0

local function code(c, a, k, l)
	return Loadout.encode({ chassis = c, arms = a or 1, core = k or 1, legs = l or 1 })
end

local function name(c, a, k, l)
	local text = Loadout.Chassis[c].name
	if (a or 1) > 1 or (k or 1) > 1 or (l or 1) > 1 then
		text ..= " " .. Loadout.Modules.ARMS[a or 1].name:sub(1, 3) .. "/" .. Loadout.Modules.CORE[k or 1].name:sub(1, 3) .. "/" .. Loadout.Modules.LEGS[l or 1].name:sub(1, 3)
	end
	return text
end

-- One round to the finish. Returns the winner (1, 2, or 0 for a draw), how many frames it took, and whether it ended in a KO.
local function playRound(codeA, codeB, seed)
	local a, b = FightSim.newFighter(0, 0), FightSim.newFighter(0, 0)
	a.stats = Loadout.stats(codeA)
	b.stats = Loadout.stats(codeB)
	FightSim.reset(a, b)
	local ia, ib = FightSim.newInput(), FightSim.newInput()
	local options = { training = false, rounds = true, combat = true }
	local tick = (seed + SEED) * 7919 + 13
	local frames = 0
	for frame = 1, 3600 do
		tick += 1
		BotBrain.input(tick, a, b, ia, LV, 1)
		BotBrain.input(tick, b, a, ib, LV, 2)
		FightSim.step(a, b, ia, ib, options)
		frames = frame
		if a.state == State.KO or b.state == State.KO then
			break
		end
	end
	local ko = a.state == State.KO or b.state == State.KO
	local winner = 0
	if a.state == State.KO and b.state == State.KO then
		winner = 0
	elseif a.state == State.KO then
		winner = 2
	elseif b.state == State.KO then
		winner = 1
	else
		-- The clock ran out: the fuller health bar wins.
		local ha, hb = a.hp * b.stats.maxHp, b.hp * a.stats.maxHp
		if ha > hb then
			winner = 1
		elseif hb > ha then
			winner = 2
		end
	end
	return winner, frames, ko
end

-- Win percentage of X against Y (a draw counts half), with the sides alternating, and the average round length in seconds.
local function versus(codeX, codeY, rounds)
	local score, frames = 0, 0
	for i = 1, rounds do
		local w, f
		if i % 2 == 0 then
			w, f = playRound(codeY, codeX, i)
			w = if w == 1 then 2 elseif w == 2 then 1 else 0
		else
			w, f = playRound(codeX, codeY, i)
		end
		score += if w == 1 then 1 elseif w == 0 then 0.5 else 0
		frames += f
	end
	return score / rounds * 100, frames / rounds / 60
end

local function pad(text, width)
	return string.format("%-" .. width .. "s", text)
end

if MODE == "chassis" then
	local list = {}
	for c = 1, #Loadout.Chassis do
		table.insert(list, { name = Loadout.Chassis[c].name, code = code(c) })
	end
	print("Win % of ROW against COLUMN, stock chassis, level " .. LV .. ", " .. N .. " rounds per cell")
	local head = pad("", 9)
	for _, y in list do
		head ..= string.format("%8s", y.name)
	end
	print(head .. "     avg   secs")
	for _, x in list do
		local line, sum, count, secs = pad(x.name, 9), 0, 0, 0
		for _, y in list do
			local win, s = versus(x.code, y.code, N)
			line ..= string.format("%8.0f", win)
			if x ~= y then
				sum += win
				count += 1
				secs += s
			end
		end
		print(line .. string.format("  %6.1f  %5.1f", sum / count, secs / count))
	end
elseif MODE == "modules" then
	print("Win % of the module build against the same stock chassis, level " .. LV .. ", " .. N .. " rounds")
	local entries = {}
	for slot, slotName in { "ARMS", "CORE", "LEGS" } do
		for option = 2, 3 do
			table.insert(entries, { slot = slot, option = option, label = slotName:sub(1, 1) .. option .. " " .. Loadout.Modules[slotName][option].name:sub(1, 10) })
		end
	end
	local head = pad("", 9)
	for _, e in entries do
		head ..= string.format(" %-14s", e.label)
	end
	print(head)
	for c = 1, #Loadout.Chassis do
		local line = pad(Loadout.Chassis[c].name, 9)
		for _, e in entries do
			local arms, core, legs = 1, 1, 1
			if e.slot == 1 then
				arms = e.option
			elseif e.slot == 2 then
				core = e.option
			else
				legs = e.option
			end
			line ..= string.format(" %-14.0f", (versus(code(c, arms, core, legs), code(c), N)))
		end
		print(line)
	end
elseif MODE == "presets" then
	local refs = {}
	for c = 1, #Loadout.Chassis do
		table.insert(refs, { name = Loadout.Chassis[c].name, code = code(c) })
	end
	print("Preset win % against each stock chassis, level " .. LV .. ", " .. N .. " rounds")
	local head = pad("", 14)
	for _, r in refs do
		head ..= string.format("%8s", r.name)
	end
	print(head .. "     avg")
	for _, p in Loadout.Presets do
		local mine = code(p.chassis, p.arms, p.core, p.legs)
		local line, sum, count = pad(p.name, 14), 0, 0
		for _, r in refs do
			local win = versus(mine, r.code, N)
			line ..= string.format("%8.0f", win)
			sum += win
			count += 1
		end
		print(line .. string.format("  %6.1f", sum / count))
	end
elseif MODE == "all" then
	local refs = {}
	for c = 1, #Loadout.Chassis do
		table.insert(refs, code(c))
	end
	local rows = {}
	for c = 1, #Loadout.Chassis do
		for a = 1, 3 do
			for k = 1, 3 do
				for l = 1, 3 do
					local total, count = 0, 0
					for _, ref in refs do
						if ref ~= code(c, a, k, l) then
							total += versus(code(c, a, k, l), ref, N)
							count += 1
						end
					end
					table.insert(rows, { name = name(c, a, k, l), avg = total / count, chassis = c, pick = { a, k, l } })
				end
			end
		end
	end
	table.sort(rows, function(p, q)
		return p.avg > q.avg
	end)
	print("Average win % against the five stock chassis (" .. N .. " rounds each), level " .. LV)
	for i = 1, 12 do
		print(string.format("%3d  %-26s %5.1f", i, rows[i].name, rows[i].avg))
	end
	print("  ...")
	for i = #rows - 11, #rows do
		print(string.format("%3d  %-26s %5.1f", i, rows[i].name, rows[i].avg))
	end
	local perChassis = {}
	for _, r in rows do
		local entry = perChassis[r.chassis] or { sum = 0, n = 0, lo = 1e9, hi = -1e9 }
		entry.sum += r.avg
		entry.n += 1
		entry.lo = math.min(entry.lo, r.avg)
		entry.hi = math.max(entry.hi, r.avg)
		perChassis[r.chassis] = entry
	end
	for c = 1, #Loadout.Chassis do
		local e = perChassis[c]
		print(string.format("%-9s mean %5.1f  range %5.1f - %5.1f", Loadout.Chassis[c].name, e.sum / e.n, e.lo, e.hi))
	end
	-- The main effect of each option: the mean win % of every loadout that uses it, overall and on each chassis.
	local slotNames = { "ARMS", "CORE", "LEGS" }
	print("-- main effect of each option (mean win % of every loadout that uses it)")
	local head = string.format("%-18s %6s", "", "all")
	for c = 1, #Loadout.Chassis do
		head ..= string.format(" %7s", Loadout.Chassis[c].name)
	end
	print(head)
	for slot = 1, 3 do
		for option = 1, 3 do
			local sum, n = 0, 0
			local per = {}
			for _, r in rows do
				if r.pick[slot] == option then
					sum += r.avg
					n += 1
					local cell = per[r.chassis] or { sum = 0, n = 0 }
					cell.sum += r.avg
					cell.n += 1
					per[r.chassis] = cell
				end
			end
			local line = string.format("%-18s %6.1f", slotNames[slot]:sub(1, 1) .. option .. " " .. Loadout.Modules[slotNames[slot]][option].name, sum / n)
			for c = 1, #Loadout.Chassis do
				line ..= string.format(" %7.1f", per[c].sum / per[c].n)
			end
			print(line)
		end
	end
else
	error("MODE must be chassis, modules, presets or all")
end
