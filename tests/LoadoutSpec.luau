--!strict

-- Headless checks for the garage's gameplay side: the loadout catalog, its codes and derived stats, and that the
-- simulation, the round flow, the frame data and the bot all play each build by its own numbers. Run from Studio's
-- command bar or the Studio MCP:
--   local passed, failures = require(game.ReplicatedStorage.Tests.LoadoutSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local Cases = require(ReplicatedStorage.Shared.Cases)
local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FightSim = require(ReplicatedStorage.Shared.FightSim)
local FrameData = require(ReplicatedStorage.Shared.FrameData)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Looks = require(ReplicatedStorage.Shared.Looks)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)
local Shop = require(ReplicatedStorage.Shared.Shop)

local State = FightSim.State

local ANVIL, BULWARK, LANCE, RAZOR, MAUL = 1, 2, 3, 4, 5
local PISTON, SERVO = 2, 3
local PLATING, DAMPERS = 2, 3

local function code(chassis: number, arms: number?, core: number?, legs: number?): number
	return Loadout.encode({ chassis = chassis, arms = arms or 1, core = core or 1, legs = legs or 1 })
end

-- The default look with some choices changed.
local function lookWith(fields: { [string]: number }): Looks.Look
	local look = Looks.default()
	for key, value in fields do
		(look :: any)[key] = value
	end
	return look
end

local function fighterWith(loadout: number, x: number): FightSim.Fighter
	local fighter = FightSim.newFighter(x, 0)
	fighter.stats = Loadout.stats(loadout)
	fighter.hp = fighter.stats.maxHp
	return fighter
end

local function press(jab: boolean?, guard: boolean?): FightSim.Input
	local input = FightSim.newInput()
	input.jab = jab or false
	input.guard = guard or false
	return input
end

local neutral = FightSim.newInput()

local function sameStats(a: FightConfig.Stats, b: FightConfig.Stats): boolean
	if
		a.maxHp ~= b.maxHp
		or a.walkForward ~= b.walkForward
		or a.walkBack ~= b.walkBack
		or a.strafe ~= b.strafe
		or a.chipTaken ~= b.chipTaken
		or a.guardTaken ~= b.guardTaken
		or a.blockstunTaken ~= b.blockstunTaken
		or a.hitstunTaken ~= b.hitstunTaken
		or a.knockbackTaken ~= b.knockbackTaken
		or a.dash.startup ~= b.dash.startup
		or a.dash.travel ~= b.dash.travel
		or a.dash.recovery ~= b.dash.recovery
		or a.dash.speed ~= b.dash.speed
		or #a.moves ~= #b.moves
	then
		return false
	end
	for index, move in a.moves do
		local other = b.moves[index]
		for key, value in move :: any do
			if (other :: any)[key] ~= value then
				return false
			end
		end
	end
	return true
end

-- A fingerprint of everything a fighter carries, for comparing two runs.
local function signature(a: FightSim.Fighter, b: FightSim.Fighter): string
	return string.format(
		"%.4f,%.4f,%d,%d,%d,%d,%d,%d",
		a.x,
		b.x,
		a.hp,
		b.hp,
		a.state,
		b.state,
		a.stateFrame,
		b.stateFrame
	)
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

	-- The catalog.
	do
		check("five chassis", #Loadout.Chassis == 5, #Loadout.Chassis)
		check("three slots", #Loadout.Slots == 3)
		local namesUnique = true
		local seen: { [string]: boolean } = {}
		for _, chassis in Loadout.Chassis do
			if seen[chassis.name] then
				namesUnique = false
			end
			seen[chassis.name] = true
			check(`{chassis.name} has a role and a blurb`, chassis.role ~= "" and chassis.blurb ~= "")
			check(
				`{chassis.name} is drawn at a sane size`,
				chassis.scale >= 0.85 and chassis.scale <= 1.2,
				chassis.scale
			)
		end
		check("chassis names are unique", namesUnique)
		for _, slot in Loadout.Slots do
			local options = Loadout.Modules[slot]
			check(`{slot} has {Loadout.OptionsPerSlot} options`, #options == Loadout.OptionsPerSlot, #options)
			check(`{slot} starts with the stock part`, options[1].name == "STOCK" and next(options[1].mods) == nil)
			for index = 2, #options do
				check(
					`{slot} {options[index].name} says what it does`,
					#Loadout.describe(options[index].mods) >= 2 and options[index].blurb ~= ""
				)
			end
		end
		for _, preset in Loadout.Presets do
			local choice = Loadout.sanitize(preset)
			check(
				`preset {preset.name} is a real loadout`,
				choice.chassis == preset.chassis
					and choice.arms == preset.arms
					and choice.core == preset.core
					and choice.legs == preset.legs
			)
		end
	end

	-- Codes: a loadout travels as one number.
	do
		check("135 codes", Loadout.codeCount() == 135, Loadout.codeCount())
		local roundTrips, seenCodes, duplicates = 0, {}, 0
		for chassis = 1, #Loadout.Chassis do
			for arms = 1, 3 do
				for core = 1, 3 do
					for legs = 1, 3 do
						local value = code(chassis, arms, core, legs)
						local back = Loadout.decode(value)
						if
							back.chassis == chassis
							and back.arms == arms
							and back.core == core
							and back.legs == legs
						then
							roundTrips += 1
						end
						if seenCodes[value] then
							duplicates += 1
						end
						seenCodes[value] = true
					end
				end
			end
		end
		check("every loadout survives the round trip", roundTrips == 135, roundTrips)
		check("every loadout has its own code", duplicates == 0, duplicates)
		check("stock ANVIL is code 1", code(ANVIL) == Loadout.DefaultCode)

		local stock = Loadout.decode(Loadout.DefaultCode)
		local garbage: { any } = { 0, -3, 136, 1e9, 1.5, 0 / 0, math.huge, "7", true, {}, nil }
		local allStock = true
		for index = 1, 11 do
			local back = Loadout.decode(garbage[index])
			if back.chassis ~= stock.chassis or back.arms ~= 1 or back.core ~= 1 or back.legs ~= 1 then
				allStock = false
			end
		end
		check("nonsense codes read as the stock ANVIL", allStock)
		check("a code of 1.5 is not valid", not Loadout.isValidCode(1.5) and not Loadout.isValidCode(0))

		local odd = Loadout.sanitize({ chassis = 99, arms = -4, core = "x", legs = 2.9 })
		check(
			"odd choices are clamped",
			odd.chassis == 5 and odd.arms == 1 and odd.core == 1 and odd.legs == 2,
			`{odd.chassis},{odd.arms},{odd.core},{odd.legs}`
		)
		local empty = Loadout.sanitize(nil)
		check(
			"no choice is the stock ANVIL",
			empty.chassis == 1 and empty.arms == 1 and empty.core == 1 and empty.legs == 1
		)
	end

	-- Derived stats.
	do
		check("a stock ANVIL plays by the base numbers", sameStats(Loadout.stats(code(ANVIL)), FightConfig.BaseStats))
		check("the base stats are the move table", FightConfig.BaseStats.moves == FightConfig.Moves)
		check("a code gives the same stats table every time", Loadout.stats(code(MAUL)) == Loadout.stats(code(MAUL)))
		check(
			"deriving twice gives the same numbers",
			sameStats(
				Loadout.derive(Loadout.decode(code(LANCE, SERVO, DAMPERS, 2))),
				Loadout.derive(Loadout.decode(code(LANCE, SERVO, DAMPERS, 2)))
			)
		)
		check("an invalid code falls back to the stock stats", sameStats(Loadout.stats(-5), FightConfig.BaseStats))
		check(
			"the base stats are not modified by deriving",
			FightConfig.Moves[1].startup == 7 and FightConfig.Moves[1].damage == 8
		)

		local sane = 0
		for value = 1, Loadout.codeCount() do
			local stats = Loadout.stats(value)
			local ok = stats.maxHp >= 70 and stats.maxHp <= 150 and stats.walkForward >= 5.5 and stats.walkForward <= 11
			ok = ok and stats.dash.recovery >= 3 and stats.dash.speed >= 18 and stats.chipTaken >= 0
			for _, move in stats.moves do
				ok = ok
					and move.startup >= 5
					and move.recovery >= 8
					and move.active >= 2
					and move.damage >= 1
					and move.reach >= 1.8
					and move.reach <= 4.2
					and move.hitstun >= 10
					and move.blockstun >= 6
			end
			if ok then
				sane += 1
			end
		end
		check("every loadout has sane stats", sane == Loadout.codeCount(), sane)

		local bulwark = Loadout.stats(code(BULWARK))
		local razor = Loadout.stats(code(RAZOR))
		local maul = Loadout.stats(code(MAUL))
		local lance = Loadout.stats(code(LANCE))
		local anvil = Loadout.stats(code(ANVIL))
		check("BULWARK is tougher and slower", bulwark.maxHp > anvil.maxHp and bulwark.walkForward < anvil.walkForward)
		check("BULWARK takes no chip damage", bulwark.chipTaken == 0)
		check(
			"RAZOR is quicker and more fragile",
			razor.maxHp < anvil.maxHp
				and razor.walkForward > anvil.walkForward
				and razor.dash.recovery < anvil.dash.recovery
				and razor.moves[1].startup < anvil.moves[1].startup
		)
		check(
			"MAUL hits harder and slower",
			maul.moves[2].damage > anvil.moves[2].damage and maul.moves[2].startup > anvil.moves[2].startup
		)
		check(
			"LANCE reaches farther with its punches only",
			lance.moves[1].reach > anvil.moves[1].reach
				and lance.moves[2].reach > anvil.moves[2].reach
				and lance.moves[3].reach == anvil.moves[3].reach
		)

		local piston = Loadout.stats(code(ANVIL, PISTON))
		local servo = Loadout.stats(code(ANVIL, SERVO))
		check(
			"PISTON FISTS trade a slower straight for punch damage",
			piston.moves[1].damage > 8
				and piston.moves[1].startup == 7
				and piston.moves[2].startup == 13
				and piston.moves[3].damage == anvil.moves[3].damage
		)
		check(
			"SERVO WRISTS trade damage and recovery for speed on punches",
			servo.moves[1].damage < 8 and servo.moves[1].startup == 6 and servo.moves[1].recovery == 13
		)
		check("PLATING trades speed for health", Loadout.stats(code(ANVIL, 1, PLATING)).maxHp > 100)
		local stacked = Loadout.stats(code(LANCE, SERVO))
		check(
			"a chassis and a module stack",
			stacked.moves[2].startup == lance.moves[2].startup - 1
				and stacked.moves[1].startup == lance.moves[1].startup - 1
		)

		local ratings = Loadout.ratings(anvil)
		check(
			"the stock ANVIL is a five everywhere",
			ratings.health == 5
				and ratings.mobility == 5
				and ratings.damage == 5
				and ratings.speed == 5
				and ratings.reach == 5
		)
		local inRange = true
		for value = 1, Loadout.codeCount() do
			local r = Loadout.ratings(Loadout.stats(value))
			for _, number in { r.health, r.mobility, r.damage, r.speed, r.reach } do
				if number < 1 or number > 10 then
					inRange = false
				end
			end
		end
		check("every rating is between 1 and 10", inRange)
		check(
			"the ratings tell the chassis apart",
			Loadout.ratings(bulwark).health > 5
				and Loadout.ratings(bulwark).mobility < 5
				and Loadout.ratings(razor).mobility > 5
				and Loadout.ratings(maul).damage > 5
				and Loadout.ratings(lance).reach > 5
		)
	end

	-- What the garage calls a build.
	do
		for index, preset in Loadout.Presets do
			check(`preset {preset.name} is found by its parts`, Loadout.presetIndex(preset) == index)
			check(`preset {preset.name} is named`, Loadout.buildName(preset) == preset.name)
		end
		check(
			"a stock chassis is named after itself",
			Loadout.buildName({ chassis = 4, arms = 1, core = 1, legs = 1 }) == "RAZOR"
		)
		check(
			"an odd mix is custom",
			Loadout.buildName({ chassis = 3, arms = 2, core = 2, legs = 2 }) == "CUSTOM LANCE",
			Loadout.buildName({ chassis = 3, arms = 2, core = 2, legs = 2 })
		)
		check(
			"nothing at all is the stock ANVIL, and it has no preset",
			Loadout.buildName(nil :: any) == "ANVIL"
				and Loadout.presetIndex({ chassis = 1, arms = 1, core = 1, legs = 1 }) == nil
		)
		check(
			"a stock build is summed up by its chassis",
			Loadout.summary({ chassis = 2, arms = 1, core = 1, legs = 1 }) == "BULWARK"
		)
		check(
			"a summary lists the modules that are not stock",
			Loadout.summary({ chassis = 3, arms = 3, core = 3, legs = 1 }) == "LANCE · SERVO WRISTS · SHOCK DAMPERS",
			Loadout.summary({ chassis = 3, arms = 3, core = 3, legs = 1 })
		)
		check(
			"the build names are short enough for a card",
			#Loadout.buildName({ chassis = 5, arms = 2, core = 3, legs = 2 }) <= 20
		)
	end

	-- What a mod says about itself.
	do
		local lines = Loadout.describe(Loadout.Chassis[BULWARK].mods)
		local text = {}
		local good, bad = 0, 0
		for _, line in lines do
			table.insert(text, line.text)
			if line.good then
				good += 1
			else
				bad += 1
			end
		end
		local joined = table.concat(text, "|")
		check("the description has both sides of the trade", good >= 2 and bad >= 2, joined)
		check("the description is in plain words", string.find(joined, "+10% health", 1, true) ~= nil, joined)
		check("no chip damage is said as such", string.find(joined, "No chip damage", 1, true) ~= nil, joined)
		check("a module with no changes has no lines", #Loadout.describe({}) == 0)
	end

	-- The simulation plays each fighter by its own stats.
	do
		check("a new fighter has the base stats", FightSim.newFighter(0, 0).stats == FightConfig.BaseStats)

		local a, b = fighterWith(code(BULWARK), -3), fighterWith(code(RAZOR), 3)
		FightSim.reset(a, b)
		check(
			"a reset fills each fighter to its own maximum",
			a.hp == a.stats.maxHp and b.hp == b.stats.maxHp and a.hp ~= b.hp
		)

		-- Health, walking speed.
		local walkerA, walkerB = fighterWith(code(RAZOR), -10), fighterWith(code(ANVIL), 10)
		local forward = FightSim.newInput()
		forward.moveZ = 1
		for _ = 1, 30 do
			FightSim.step(walkerA, walkerB, forward, forward, { training = true, combat = false })
		end
		local razorWalked = walkerA.x + 10
		local anvilWalked = 10 - walkerB.x
		check("a faster robot walks farther", razorWalked > anvilWalked + 0.3, `{razorWalked} vs {anvilWalked}`)
		check(
			"walking follows the stats",
			math.abs(razorWalked - 30 / 60 * walkerA.stats.walkForward) < 0.01,
			razorWalked
		)

		-- Startup and damage come from the attacker.
		local function jabFrames(loadout: number): (number, number)
			local x, y = fighterWith(loadout, -2), fighterWith(code(ANVIL), 2)
			FightSim.step(x, y, press(true), neutral)
			local firstActive = 0
			for frame = 1, 40 do
				FightSim.step(x, y, neutral, neutral)
				if firstActive == 0 and FightSim.attackPhase(x) == "active" then
					firstActive = frame
				end
			end
			return firstActive, 100 - y.hp
		end
		local razorActive, razorDamage = jabFrames(code(RAZOR))
		local maulActive, maulDamage = jabFrames(code(MAUL))
		local anvilActive, anvilDamage = jabFrames(code(ANVIL))
		check(
			"the jab is active on its first frame after the startup",
			anvilActive == 8 and anvilDamage == 8,
			`{anvilActive},{anvilDamage}`
		)
		check("RAZOR's jab starts a frame early", razorActive == 7, razorActive)
		check(
			"MAUL's jab starts a frame late and hits harder",
			maulActive == 9 and maulDamage > anvilDamage,
			`{maulActive},{maulDamage}`
		)
		check(
			"damage is the attacker's own number",
			maulDamage == Loadout.stats(code(MAUL)).moves[1].damage,
			maulDamage
		)
		check("RAZOR's jab hits as hard as a stock one", razorDamage == anvilDamage, razorDamage)

		-- What the defender suffers.
		local function chipTaken(loadout: number): number
			local x, y = fighterWith(code(ANVIL), -2), fighterWith(loadout, 2)
			local guard = press(false, true)
			for frame = 1, 30 do
				FightSim.step(x, y, if frame == 1 then press(true) else neutral, guard)
			end
			return y.stats.maxHp - y.hp
		end
		check("a guard takes chip damage", chipTaken(code(ANVIL)) == FightConfig.Moves[1].chip, chipTaken(code(ANVIL)))
		check("BULWARK's guard takes none", chipTaken(code(BULWARK)) == 0, chipTaken(code(BULWARK)))

		local function stunAfterJab(loadout: number, blocked: boolean): number
			local x, y = fighterWith(code(ANVIL), -2), fighterWith(loadout, 2)
			local guard = press(false, blocked)
			for frame = 1, 12 do
				FightSim.step(x, y, if frame == 1 then press(true) else neutral, guard)
			end
			return y.stun
		end
		check(
			"hitstun is the base number for a stock robot",
			stunAfterJab(code(ANVIL), false) == FightConfig.Moves[1].hitstun
		)
		check(
			"SHOCK DAMPERS shorten hitstun",
			stunAfterJab(code(ANVIL, 1, DAMPERS), false) == FightConfig.Moves[1].hitstun - 2
		)
		check(
			"SHOCK DAMPERS shorten blockstun",
			stunAfterJab(code(ANVIL, 1, DAMPERS), true) == FightConfig.Moves[1].blockstun - 2
		)

		-- No module takes less knockback today, but the stat is part of the sim, so it is checked with made-up stats.
		local function pushedBy(knockbackTaken: number): number
			local x, y = fighterWith(code(ANVIL), -2), fighterWith(code(ANVIL), 2)
			local stats = table.clone(y.stats)
			stats.knockbackTaken = knockbackTaken
			y.stats = stats
			for frame = 1, 12 do
				FightSim.step(x, y, if frame == 1 then press(true) else neutral, neutral)
			end
			return math.abs(y.vx)
		end
		check(
			"a fighter that takes half the knockback is pushed half as hard",
			math.abs(pushedBy(0.5) * 2 - pushedBy(1)) < 1e-6
		)
	end

	-- A round ends on the fuller health bar, not on the bigger number.
	do
		local function onTime(hpA: number, loadoutA: number, hpB: number, loadoutB: number): number
			local match = MatchFlow.new()
			local a, b = fighterWith(loadoutA, -3), fighterWith(loadoutB, 3)
			a.hp = hpA
			b.hp = hpB
			MatchFlow.start(match, MatchFlow.Mode.Rounds)
			match.phase = MatchFlow.Phase.Fight
			match.timer = 1
			MatchFlow.step(match, a, b)
			return match.result
		end
		local tank, light = code(BULWARK), code(RAZOR)
		local tankMax, lightMax = Loadout.stats(tank).maxHp, Loadout.stats(light).maxHp
		check(
			"equal fractions on time are a draw",
			onTime(tankMax / 2, tank, lightMax / 2, light) == MatchFlow.Result.Draw
		)
		check(
			"a smaller number can be the fuller bar",
			onTime(tankMax * 0.5, tank, lightMax * 0.55, light) == MatchFlow.Result.B,
			"tank 50% against light 55%"
		)
		check(
			"a bigger number can be the emptier bar",
			onTime(tankMax * 0.6, tank, lightMax * 0.55, light) == MatchFlow.Result.A,
			"tank 60% against light 55%"
		)
	end

	-- Frame data describes what the simulation does.
	do
		local function measured(attackerLoadout: number, defenderLoadout: number, blocked: boolean): (number?, number)
			local history = FrameData.newHistory(180)
			local a, b = fighterWith(attackerLoadout, 0), fighterWith(defenderLoadout, 3.6)
			local guard = press(false, blocked)
			local frame = 0
			for step = 1, 120 do
				frame += 1
				FightSim.step(a, b, if step == 1 then press(true) else neutral, guard)
				FrameData.record(history, frame, a, b)
			end
			local exchange = FrameData.lastExchange(history)
			local data = FrameData.forMove(1, a.stats, b.stats)
			return if exchange ~= nil then exchange.advantage else nil, if blocked then data.onBlock else data.onHit
		end
		local pairs: { { number } } = {
			{ code(ANVIL), code(ANVIL) },
			{ code(MAUL), code(BULWARK) },
			{ code(RAZOR, SERVO), code(ANVIL, 1, DAMPERS) },
			{ code(LANCE), code(RAZOR) },
		}
		for _, pair in pairs do
			for _, blocked in { false, true } do
				local advantage, expected = measured(pair[1], pair[2], blocked)
				check(
					`measured advantage matches the table ({pair[1]} on {pair[2]}, {if blocked then "block" else "hit"})`,
					advantage == expected,
					`{advantage} vs {expected}`
				)
			end
		end
		local data = FrameData.forMove(1, Loadout.stats(code(MAUL)), nil)
		check("frame data reads the attacker's moves", data.startup == 8 and data.damage > 8, data.startup)
		local kind = FrameData.cellKind(State.Attack, 1, 8, Loadout.stats(code(MAUL)).moves)
		check("the frame meter reads the fighter's own startup", kind == "startup", kind)
	end

	-- The bot reads and uses each build's own frame data.
	do
		local function play(loadoutA: number, loadoutB: number, seed: number, frames: number): (string, number, number)
			local a, b = fighterWith(loadoutA, -3), fighterWith(loadoutB, 3)
			FightSim.reset(a, b)
			local inputA, inputB = FightSim.newInput(), FightSim.newInput()
			local options: FightSim.Options = { training = false, rounds = true, combat = true }
			local attacksA, attacksB = 0, 0
			local wasA, wasB = false, false
			local tick = seed * 7919 + 13
			for _ = 1, frames do
				tick += 1
				BotBrain.input(tick, a, b, inputA, 3, 1)
				BotBrain.input(tick, b, a, inputB, 3, 2)
				FightSim.step(a, b, inputA, inputB, options)
				if a.state == State.Attack and not wasA then
					attacksA += 1
				end
				if b.state == State.Attack and not wasB then
					attacksB += 1
				end
				wasA = a.state == State.Attack
				wasB = b.state == State.Attack
				if a.state == State.KO or b.state == State.KO then
					break
				end
			end
			return signature(a, b), attacksA, attacksB
		end
		local allAttack = true
		for chassis = 1, 5 do
			local _, attacksA, attacksB = play(code(chassis), code((chassis % 5) + 1), chassis, 900)
			if attacksA < 3 or attacksB < 3 then
				allAttack = false
			end
		end
		check("a bot fights with every chassis", allAttack)

		local first = play(code(LANCE, SERVO, DAMPERS, 3), code(MAUL, PISTON, PLATING, 2), 7, 1500)
		local second = play(code(LANCE, SERVO, DAMPERS, 3), code(MAUL, PISTON, PLATING, 2), 7, 1500)
		check("the same loadouts play the same fight every time", first == second, `{first} vs {second}`)

		-- A tall poker stands off at its own distance instead of the stock one.
		local lanceFighter, foe = fighterWith(code(LANCE), -3), fighterWith(code(ANVIL), 3)
		local into = FightSim.newInput()
		BotBrain.input(10, lanceFighter, foe, into, 3, 1)
		check("the bot accepts any build", into.moveZ >= -1 and into.moveZ <= 1)
	end

	-- Looks: paint, finishes and crests, and how two fighters are kept apart.
	do
		local function freeCount(list: { Looks.Swatch }): number
			local count = 0
			for _, swatch in list do
				if swatch.item == nil then
					count += 1
				end
			end
			return count
		end
		check(
			"sixteen armor and accent swatches for everyone, and case paints after them",
			freeCount(Looks.Armor) == 16 and freeCount(Looks.Accents) == 16 and Looks.Armor[17].item ~= nil,
			`{freeCount(Looks.Armor)},{freeCount(Looks.Accents)}`
		)
		check(
			"four finishes, seven crests, and a kit and a shop item (or none) for each crest",
			#Looks.Finishes == 4 and #Looks.Crests == 7 and #Looks.CrestKits == 7 and #Looks.CrestItems == 7
		)
		check(
			"the first swatch of each list is the team color",
			Looks.Armor[1].color == nil and Looks.Accents[1].color == nil
		)
		local valid = true
		local names: { [string]: boolean } = {}
		local unique = true
		for _, list in { Looks.Armor, Looks.Accents } do
			names = {}
			for index, swatch in list do
				if names[swatch.name] then
					unique = false
				end
				names[swatch.name] = true
				local color = swatch.color
				if color ~= nil then
					for channel = 1, 3 do
						if color[channel] < 0 or color[channel] > 255 then
							valid = false
						end
					end
				elseif index ~= 1 then
					valid = false
				end
			end
		end
		check("every swatch is a real color with its own name", valid and unique)
		check("the defaults are the first of everything", Looks.encode(Looks.default()) == 1)

		-- Too many looks to try them all, so a spread of them across the whole range, and the ends.
		local count = Looks.codeCount()
		local stride = math.max(1, math.floor(count / 150000))
		local tried = 0
		local roundTrips = 0
		for value = 1, count, stride do
			tried += 1
			local back = Looks.decode(value)
			if Looks.encode(back) == value then
				roundTrips += 1
			end
		end
		for _, value in { count, count - 1, 2 } do
			tried += 1
			if Looks.encode(Looks.decode(value)) == value then
				roundTrips += 1
			end
		end
		check("every look survives the round trip", roundTrips == tried, `{roundTrips} of {tried}`)
		local lastOfAll = lookWith({
			armor = #Looks.Armor,
			accent = #Looks.Accents,
			finish = #Looks.Finishes,
			crest = #Looks.Crests,
			body = #Looks.Bodies,
			glow = #Looks.Glows,
			trail = #Looks.Trails,
			impact = #Looks.Impacts,
			title = #Looks.Titles,
		})
		check("the last of everything is the last code", Looks.encode(lastOfAll) == count)
		local mixed = lookWith({
			armor = 4,
			accent = 9,
			finish = 2,
			crest = 6,
			body = 3,
			glow = 8,
			trail = 2,
			impact = 5,
			title = 7,
		})
		local mixedBack = Looks.decode(Looks.encode(mixed))
		check(
			"each choice comes back where it was",
			mixedBack.armor == 4
				and mixedBack.accent == 9
				and mixedBack.finish == 2
				and mixedBack.crest == 6
				and mixedBack.body == 3
				and mixedBack.glow == 8
				and mixedBack.trail == 2
				and mixedBack.impact == 5
				and mixedBack.title == 7
		)
		local garbage: { any } = { 0, -1, Looks.codeCount() + 1, 2.5, 0 / 0, "3", true, {}, nil }
		local allDefault = true
		for index = 1, 9 do
			local back = Looks.decode(garbage[index])
			if back.armor ~= 1 or back.accent ~= 1 or back.finish ~= 1 or back.crest ~= 1 or back.body ~= 1 then
				allDefault = false
			end
			if back.glow ~= 1 or back.trail ~= 1 or back.impact ~= 1 or back.title ~= 1 then
				allDefault = false
			end
		end
		check("nonsense looks fall back to the default", allDefault)
		local odd =
			Looks.sanitize({ armor = 99, accent = -2, finish = "x", crest = 3.9, body = 42, glow = 99, title = -1 })
		check(
			"odd looks are clamped",
			odd.armor == #Looks.Armor
				and odd.accent == 1
				and odd.finish == 1
				and odd.crest == 3
				and odd.body == #Looks.Bodies
				and odd.glow == #Looks.Glows
				and odd.title == 1
				and odd.trail == 1,
			`{odd.armor},{odd.accent},{odd.finish},{odd.crest},{odd.body},{odd.glow},{odd.title}`
		)
		check("a save from before bodies wears the stock body", Looks.sanitize({ armor = 3, crest = 2 }).body == 1)
		check(
			"a save from before case items wears none",
			Looks.sanitize({ armor = 3 }).glow == 1 and Looks.titleOf(Looks.sanitize({ armor = 3 })) == ""
		)

		-- Kits and frames.
		check(
			"a stock ANVIL with no crest wears nothing extra",
			#Looks.kitsFor(Loadout.decode(Loadout.DefaultCode), Looks.default()) == 0
		)
		check("every crest but none has a kit", #Looks.CrestKits == #Looks.Crests and Looks.CrestKits[1] == "")
		local dressed =
			Looks.kitsFor({ chassis = BULWARK, arms = PISTON, core = PLATING, legs = 2 }, lookWith({ crest = 4 }))
		check(
			"only the crest is a kit; the build shows in the frame",
			table.concat(dressed, ",") == "CrestHorns",
			table.concat(dressed, ",")
		)
		check("every chassis has a frame", #Looks.Frames == #Loadout.Chassis)
		local distinct: { [string]: boolean } = {}
		for _, frame in Looks.Frames do
			distinct[frame] = true
		end
		local frameCount = 0
		for _ in distinct do
			frameCount += 1
		end
		check("each chassis is drawn as a robot of its own", frameCount == #Loadout.Chassis, frameCount)
		check(
			"a loadout is drawn as its chassis' frame",
			Looks.frameFor({ chassis = BULWARK, arms = PISTON, core = PLATING, legs = 2 }, Looks.default()) == "Bulwark"
				and Looks.frameFor(Loadout.decode(Loadout.DefaultCode), Looks.default()) == "Anvil"
		)

		-- Premium bodies and shop crests.
		local monarch = Looks.bodyFor("body.monarch") :: number
		check(
			"MONARCH is a body for MAUL, drawn as its own frame",
			monarch ~= nil
				and Looks.Bodies[monarch].chassis == MAUL
				and Looks.Bodies[monarch].frame == "Monarch"
				and Looks.Bodies[1].frame == nil
				and Looks.Bodies[1].item == nil
		)
		local maulBuild = { chassis = MAUL, arms = 1, core = 1, legs = 1 }
		local wearsMonarch = lookWith({ body = monarch })
		check(
			"a premium body draws its own chassis, and only that one",
			Looks.frameFor(maulBuild, wearsMonarch) == "Monarch"
				and Looks.frameFor({ chassis = ANVIL, arms = 1, core = 1, legs = 1 }, wearsMonarch) == "Anvil"
				and Looks.frameFor(maulBuild, Looks.default()) == "Maul"
		)
		local bodiesFor: { [number]: number } = {}
		local bodyFrames: { [string]: boolean } = {}
		local ownFrames, forRobux = true, true
		for index, body in Looks.Bodies do
			if body.chassis == nil then
				continue
			end
			bodiesFor[body.chassis] = (bodiesFor[body.chassis] or 0) + 1
			local frame = body.frame or ""
			if frame == "" or bodyFrames[frame] or table.find(Looks.Frames, frame) ~= nil then
				ownFrames = false
			end
			bodyFrames[frame] = true
			local id = Looks.bodyItem(index)
			local item = if id ~= nil then Shop.item(id) else nil
			if item == nil or item.robux == nil or item.robux <= 0 then
				forRobux = false
			end
		end
		local everyChassis = true
		for index in Loadout.Chassis do
			if (bodiesFor[index] or 0) < 1 then
				everyChassis = false
			end
		end
		check("every chassis has a premium body", everyChassis)
		check("each premium body is a frame of its own, sold for Robux", ownFrames and forRobux)
		local premium = lookWith({
			armor = 2,
			accent = 3,
			finish = 2,
			crest = Looks.crestFor("crest.crown") :: number,
			body = monarch,
		})
		local nothing = Looks.strip(premium, function(_item: string): boolean
			return false
		end)
		local everything = Looks.strip(premium, function(_item: string): boolean
			return true
		end)
		local onlyCrown = Looks.strip(premium, function(item: string): boolean
			return item == "crest.crown"
		end)
		check(
			"a look keeps only the shop items its wearer owns, and all of its paint",
			nothing.body == 1
				and nothing.crest == 1
				and nothing.armor == 2
				and nothing.accent == 3
				and nothing.finish == 2
				and everything.body == monarch
				and everything.crest == premium.crest
				and onlyCrown.body == 1
				and onlyCrown.crest == premium.crest
		)
		local freeStays = Looks.strip(lookWith({ crest = 4 }), function(): boolean
			return false
		end)
		check("everyone's crests need nothing", freeStays.crest == 4)
		local cased = lookWith({ armor = 17, accent = 17, glow = 9, trail = 6, impact = 5, title = 8, finish = 3 })
		local unowned = Looks.strip(cased, function(): boolean
			return false
		end)
		check(
			"case items come off a look whose wearer does not own them, and paint for everyone stays",
			unowned.armor == 1
				and unowned.accent == 1
				and unowned.glow == 1
				and unowned.trail == 1
				and unowned.impact == 1
				and unowned.title == 1
				and unowned.finish == 3
		)
		local owned = Looks.strip(cased, function(item: string): boolean
			return item == "glow.spectrum" or item == "title.unbreakable"
		end)
		check("and the ones they own stay", owned.glow == 9 and owned.title == 8 and owned.trail == 1)
		local slotKey, slotIndex = Looks.slotOf("glow.spectrum")
		check(
			"an item knows what it unlocks",
			slotKey == "glow"
				and slotIndex == 9
				and Looks.itemAt("glow", 9) == "glow.spectrum"
				and Looks.itemAt("glow", 1) == nil
		)
		local crown = Looks.describe("crest.crown")
		local spectrum = Looks.describe("glow.spectrum")
		check(
			"and what it is called",
			crown ~= nil
				and crown.name == "CROWN"
				and spectrum ~= nil
				and spectrum.kind == "CORE GLOW"
				and Looks.describe("hat.nothing") == nil
		)
		check(
			"a title shows only when one is worn",
			Looks.titleOf(Looks.default()) == "" and Looks.titleOf(lookWith({ title = 8 })) == "UNBREAKABLE"
		)
		local caseLists: { { { name: string, item: string? } } } =
			{ Looks.Glows :: any, Looks.Trails :: any, Looks.Impacts :: any, Looks.Titles :: any }
		local firstsFree = true
		local restCased = true
		for _, list in caseLists do
			for index, entry in list do
				if index == 1 and entry.item ~= nil then
					firstsFree = false
				elseif index > 1 and entry.item == nil then
					restCased = false
				end
			end
		end
		check("glows, trails, impacts and titles start with one for everyone", firstsFree)
		check("and every other one is a case item", restCased)
		local botsFree = true
		for seed = 0, 40 do
			if Looks.crestItem(Looks.botLook(seed).crest) ~= nil or Looks.botLook(seed).body ~= 1 then
				botsFree = false
			end
		end
		check("bots wear only what everyone has", botsFree)

		-- The shop.
		local known = true
		for index = 1, #Looks.Crests do
			local id = Looks.crestItem(index)
			local item = if id ~= nil then Shop.item(id) else nil
			if id ~= nil and (item == nil or item.kind ~= "crest") then
				known = false
			end
		end
		for index = 1, #Looks.Bodies do
			local id = Looks.bodyItem(index)
			local item = if id ~= nil then Shop.item(id) else nil
			if id ~= nil and (item == nil or item.kind ~= "body") then
				known = false
			end
		end
		check("every shop crest and body is in the catalog", known)
		local ids: { [string]: boolean } = {}
		local wellFormed = true
		for _, item in Shop.Items do
			local unlocks = if item.kind == "body" then Looks.bodyFor(item.id) else Looks.crestFor(item.id)
			local priced = (item.coins ~= nil and item.coins > 0) ~= (item.robux ~= nil and item.robux > 0)
			if ids[item.id] or unlocks == nil or not priced then
				wellFormed = false
			end
			ids[item.id] = true
		end
		check("every item has its own id, unlocks a look, and one price, in coins or in Robux", wellFormed)
		check(
			"items are found by id and by product",
			Shop.item("crest.mohawk") ~= nil
				and Shop.item("nope") == nil
				and Shop.item(7) == nil
				and Shop.byProduct(0) == nil
				and Shop.byProduct("1") == nil
		)
		check(
			"matches pay more for a win and for a harder bot, something for a loss, and nothing for practice",
			Shop.reward("versus", 0, true) > Shop.reward("versus", 0, false)
				and Shop.reward("versus", 0, false) > 0
				and Shop.reward("bot", 3, true) > Shop.reward("bot", 2, true)
				and Shop.reward("bot", 2, true) > Shop.reward("bot", 1, true)
				and Shop.reward("bot", 1, true) > Shop.reward("bot", 1, false)
				and Shop.reward("bot", 1, false) > 0
				and Shop.reward("training", 1, true) == 0
				and Shop.reward("exhibition", 1, true) == 0
		)
		local parsed = Shop.parseOwned(Shop.formatOwned({ ["body.monarch"] = true, ["crest.crown"] = true }))
		check(
			"coins read with separators and owned items read back",
			Shop.formatCoins(1250) == "1,250"
				and Shop.formatCoins(999) == "999"
				and Shop.formatCoins(1000000) == "1,000,000"
				and parsed["body.monarch"] == true
				and parsed["crest.crown"] == true
				and parsed["crest.mohawk"] == nil
				and next(Shop.parseOwned(nil)) == nil
				and next(Shop.parseOwned("")) == nil
				and Shop.formatOwned({}) == ""
		)

		-- What a player owns fits one replicated attribute, whatever they own, and reads back exactly.
		do
			local ownsAll: { [string]: boolean } = {}
			local items = Looks.items()
			for _, item in items do
				ownsAll[item] = true
			end
			local catalogued = true
			for _, item in Shop.Items do
				catalogued = catalogued and ownsAll[item.id] == true
			end
			for _, case in Cases.List do
				for _, list in case.items do
					for _, item in list do
						catalogued = catalogued and ownsAll[item] == true
					end
				end
			end
			check("every shop item and case item can be owned", catalogued)
			local all = Shop.formatOwned(ownsAll)
			check("owning everything fits an attribute", #all <= Shop.AttributeLimit, #all)
			local back = Shop.parseOwned(all)
			local roundTrip = true
			for _, item in items do
				roundTrip = roundTrip and back[item] == true
				local alone = Shop.parseOwned(Shop.formatOwned({ [item] = true }))
				local found = 0
				for _ in alone do
					found += 1
				end
				roundTrip = roundTrip and alone[item] == true and found == 1
			end
			check("every item reads back, alone and with everything else", roundTrip)
			check(
				"an id no item has is left out",
				Shop.formatOwned({ ["hat.party"] = true }) == "" and next(Shop.parseOwned("?!")) == nil
			)
		end

		-- Colors.
		local me, foe = Looks.resolve(Looks.default(), Looks.default())
		check(
			"two team looks wear the team colors",
			me.armor == Looks.Team.me.armor
				and me.accent == Looks.Team.me.accent
				and foe.armor == Looks.Team.foe.armor
				and foe.accent == Looks.Team.foe.accent
		)
		local crimson = lookWith({ armor = 10, accent = 11, finish = 3, crest = 2 })
		local mine, theirs = Looks.resolve(crimson, crimson)
		check(
			"a look is shown as chosen",
			mine.armor == Looks.Armor[10].color and mine.finish.name == "CHROME" and mine.crest == 2
		)
		check(
			"the same colors on both sides are told apart",
			Looks.distance(mine.armor, theirs.armor) >= 70 and Looks.distance(mine.accent, theirs.accent) >= 90
		)
		check(
			"the opponent falls back to its team colors",
			theirs.armor == Looks.Team.foe.armor and theirs.accent == Looks.Team.foe.accent
		)
		local gunmetal = lookWith({ armor = 3 })
		local _, against = Looks.resolve(gunmetal, Looks.default())
		check(
			"even the team color gives way when it would clash",
			Looks.distance(against.armor, Looks.Armor[3].color :: Looks.Rgb) >= 70
		)
		local apart1, apart2 = Looks.resolve(
			lookWith({ armor = 10, accent = 9 }),
			lookWith({ armor = 12, accent = 3, finish = 2, crest = 5, glow = 4 })
		)
		check(
			"colors that already differ are left alone",
			apart2.armor == Looks.Armor[12].color
				and apart2.accent == Looks.Accents[3].color
				and apart2.finish.name == "MATTE"
				and apart1.crest == 1
		)
		check(
			"each side shows its own glow, trail and impact",
			apart2.glow == Looks.Glows[4] and apart1.glow == Looks.Glows[1] and apart1.trail == Looks.Trails[1]
		)
	end

	return passed, failures
end
