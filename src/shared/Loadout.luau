--!strict

-- The gameplay side of the garage: five chassis, three module slots, and the arithmetic that turns a choice into the
-- Stats the simulation plays. Pure and deterministic like FightSim: the server and every predicting client derive the
-- same numbers from the same small integer code, so a loadout travels as one number on the fighter's core.
--
-- Every choice is a sidegrade. Each chassis and module gives something and takes something away, so no loadout is
-- simply better than another, and everyone can use all of them. What a player earns or buys on top of that is how the
-- robot looks (see Looks).

local FightConfig = require(script.Parent.FightConfig)

export type MoveMod = {
	-- Frames added to the move's timing.
	startup: number?,
	active: number?,
	recovery: number?,
	hitstun: number?,
	blockstun: number?,
	hitstop: number?,
	-- Multipliers.
	damage: number?,
	reach: number?,
	hitRadius: number?,
	knockback: number?,
}

-- A change to the base stats. Multipliers multiply, frame counts add; several mods stack in the order they are applied.
export type Mod = {
	-- Multiplier on maximum health.
	hp: number?,
	-- Multipliers on walking speed: all directions, then backing away and sidestepping on top of that.
	walk: number?,
	walkBack: number?,
	strafe: number?,
	-- Dash speed (multiplier) and frames added to the dash's startup and recovery.
	dashSpeed: number?,
	dashStartup: number?,
	dashRecovery: number?,
	-- What the fighter suffers; see FightConfig.Stats.
	chipTaken: number?,
	blockstunTaken: number?,
	hitstunTaken: number?,
	knockbackTaken: number?,
	-- Changes to moves, by selector: all, punch, kick, jab, straight, snap or power.
	moves: { [string]: MoveMod }?,
}

export type Chassis = {
	name: string,
	role: string,
	blurb: string,
	-- How much larger or smaller the robot is drawn. Looks only; the hit circle does not change.
	scale: number,
	mods: Mod,
}

export type Module = {
	name: string,
	blurb: string,
	mods: Mod,
}

export type Preset = {
	name: string,
	blurb: string,
	chassis: number,
	arms: number,
	core: number,
	legs: number,
}

export type Choice = {
	chassis: number,
	arms: number,
	core: number,
	legs: number,
}

export type Line = { text: string, good: boolean }

local Loadout = {}

-- The three slots, in the order mods are applied. Option 1 of every slot is the stock part.
Loadout.Slots = { "ARMS", "CORE", "LEGS" }
Loadout.OptionsPerSlot = 3
Loadout.DefaultCode = 1

local MIN_STARTUP = 5
local MIN_RECOVERY = 8
local MIN_ACTIVE = 2

Loadout.Chassis = {
	{
		name = "ANVIL",
		role = "ALL-ROUNDER",
		blurb = "Honest steel. No weakness, no trick.",
		scale = 1,
		mods = {},
	},
	{
		name = "BULWARK",
		role = "TANK",
		blurb = "Big, slow and hard to hurt. Guarding costs it nothing.",
		scale = 1.08,
		mods = {
			hp = 1.1,
			walk = 0.86,
			dashRecovery = 2,
			chipTaken = 0,
			moves = { all = { damage = 0.9 } },
		},
	},
	{
		name = "LANCE",
		role = "POKER",
		blurb = "Long arms win the distance game, but every punch starts a beat late.",
		scale = 1.1,
		mods = {
			hp = 0.94,
			walk = 0.97,
			moves = {
				punch = { reach = 1.1, startup = 1, damage = 0.96 },
				kick = { damage = 0.9 },
			},
		},
	},
	{
		name = "RAZOR",
		role = "RUSHDOWN",
		blurb = "Quick hands and quicker feet on a light frame.",
		scale = 0.94,
		mods = {
			hp = 0.92,
			walk = 1.1,
			dashSpeed = 1.1,
			dashRecovery = -2,
			moves = { jab = { startup = -1 } },
		},
	},
	{
		name = "MAUL",
		role = "HEAVY HITTER",
		blurb = "Every hit counts and every miss is paid for.",
		scale = 1.06,
		mods = {
			hp = 1.08,
			walk = 0.94,
			moves = { all = { damage = 1.18, startup = 1, recovery = 1, knockback = 1.2 } },
		},
	},
} :: { Chassis }

-- Modules by slot: stock first, then two ways to trade something for something.
Loadout.Modules = {
	ARMS = {
		{ name = "STOCK", blurb = "No changes.", mods = {} },
		{
			name = "PISTON FISTS",
			blurb = "Harder punches, and a slower straight.",
			mods = { moves = { punch = { damage = 1.18 }, straight = { startup = 1 } } },
		},
		{
			name = "SERVO WRISTS",
			blurb = "Faster punches that hit lighter and take longer to recover.",
			mods = { moves = { punch = { damage = 0.9, startup = -1, recovery = 2 } } },
		},
	},
	CORE = {
		{ name = "STOCK", blurb = "No changes.", mods = {} },
		{
			name = "PLATING",
			blurb = "More armor, more weight.",
			mods = { hp = 1.05, walk = 0.9 },
		},
		{
			name = "SHOCK DAMPERS",
			blurb = "Shorter stuns, on a slightly thinner frame.",
			mods = { hp = 0.98, blockstunTaken = -2, hitstunTaken = -2 },
		},
	},
	LEGS = {
		{ name = "STOCK", blurb = "No changes.", mods = {} },
		{
			name = "HYDRAULIC BOOTS",
			blurb = "Kicks that hit harder and recover slower.",
			mods = { moves = { kick = { damage = 1.15, recovery = 2 } } },
		},
		{
			name = "SPRING GREAVES",
			blurb = "Quicker on the feet, lighter kicks.",
			mods = { walk = 1.08, dashRecovery = -1, moves = { kick = { damage = 0.9 } } },
		},
	},
} :: { [string]: { Module } }

-- Ready-made builds, two for every chassis. Choosing one fills every slot; the player can change any of them afterwards.
Loadout.Presets = {
	{ name = "STEEL WALL", blurb = "Soak it up and counter.", chassis = 1, arms = 1, core = 2, legs = 1 },
	{ name = "CLEAN HANDS", blurb = "Quick fists, quick feet.", chassis = 1, arms = 3, core = 1, legs = 3 },
	{ name = "BREAKWATER", blurb = "A tank that hits back.", chassis = 2, arms = 2, core = 1, legs = 2 },
	{
		name = "IRON CURTAIN",
		blurb = "Nothing gets through, nothing gets chipped.",
		chassis = 2,
		arms = 2,
		core = 3,
		legs = 1,
	},
	{ name = "SKIRMISHER", blurb = "Fast pokes behind shock dampers.", chassis = 3, arms = 3, core = 3, legs = 1 },
	{ name = "SNIPER", blurb = "Long arms, solid plating, quick feet.", chassis = 3, arms = 1, core = 2, legs = 3 },
	{ name = "SHREDDER", blurb = "Light on its feet, heavy on its fists.", chassis = 4, arms = 2, core = 1, legs = 3 },
	{ name = "GHOST", blurb = "Hard to pin down, hard to keep down.", chassis = 4, arms = 3, core = 3, legs = 3 },
	{ name = "WRECKER", blurb = "Everything is a haymaker.", chassis = 5, arms = 2, core = 1, legs = 2 },
	{ name = "BRAWLER", blurb = "Quick hands that shake off hits.", chassis = 5, arms = 3, core = 3, legs = 1 },
} :: { Preset }

local MOVE_SELECTORS = { "all", "punch", "kick", "jab", "straight", "snap", "power" }
local SELECTED: { [string]: { number } } = {
	all = { 1, 2, 3, 4 },
	punch = { 1, 2 },
	kick = { 3, 4 },
	jab = { 1 },
	straight = { 2 },
	snap = { 3 },
	power = { 4 },
}

-- The running totals while mods are applied: multipliers start at 1 and frame counts at 0.
type MoveTotals = {
	startup: number,
	active: number,
	recovery: number,
	hitstun: number,
	blockstun: number,
	hitstop: number,
	damage: number,
	reach: number,
	hitRadius: number,
	knockback: number,
}

local function newMoveTotals(): MoveTotals
	return {
		startup = 0,
		active = 0,
		recovery = 0,
		hitstun = 0,
		blockstun = 0,
		hitstop = 0,
		damage = 1,
		reach = 1,
		hitRadius = 1,
		knockback = 1,
	}
end

local function round(value: number): number
	return math.floor(value + 0.5)
end

-- Rounds to a number of decimal places (0 to 2) with plain multiplication, so every machine agrees on the result.
local SCALES = { [0] = 1, [1] = 10, [2] = 100 }
local function roundTo(value: number, places: number): number
	local scale = SCALES[places]
	return math.floor(value * scale + 0.5) / scale
end

local function applyMoveMod(totals: MoveTotals, mod: MoveMod)
	totals.startup += mod.startup or 0
	totals.active += mod.active or 0
	totals.recovery += mod.recovery or 0
	totals.hitstun += mod.hitstun or 0
	totals.blockstun += mod.blockstun or 0
	totals.hitstop += mod.hitstop or 0
	totals.damage *= mod.damage or 1
	totals.reach *= mod.reach or 1
	totals.hitRadius *= mod.hitRadius or 1
	totals.knockback *= mod.knockback or 1
end

-- Builds the stats for a list of mods applied in order on top of the base stats.
local function build(mods: { Mod }): FightConfig.Stats
	local base = FightConfig.BaseStats
	local hp, walk, walkBack, strafe, dashSpeed = 1, 1, 1, 1, 1
	local dashStartup, dashRecovery = 0, 0
	local chipTaken, blockstunTaken, hitstunTaken, knockbackTaken = 1, 0, 0, 1
	local totals: { MoveTotals } = {}
	for index in base.moves do
		totals[index] = newMoveTotals()
	end

	for _, mod in mods do
		hp *= mod.hp or 1
		walk *= mod.walk or 1
		walkBack *= mod.walkBack or 1
		strafe *= mod.strafe or 1
		dashSpeed *= mod.dashSpeed or 1
		dashStartup += mod.dashStartup or 0
		dashRecovery += mod.dashRecovery or 0
		chipTaken *= mod.chipTaken or 1
		blockstunTaken += mod.blockstunTaken or 0
		hitstunTaken += mod.hitstunTaken or 0
		knockbackTaken *= mod.knockbackTaken or 1
		local byMove = mod.moves
		if byMove ~= nil then
			-- A fixed order, so the same mods always multiply the same way.
			for _, selector in MOVE_SELECTORS do
				local change = byMove[selector]
				if change ~= nil then
					for _, moveId in SELECTED[selector] do
						applyMoveMod(totals[moveId], change)
					end
				end
			end
		end
	end

	local moves: { FightConfig.MoveData } = {}
	for index, move in base.moves do
		local change = totals[index]
		moves[index] = {
			name = move.name,
			clip = move.clip,
			striker = move.striker,
			startup = math.max(move.startup + change.startup, MIN_STARTUP),
			active = math.max(move.active + change.active, MIN_ACTIVE),
			recovery = math.max(move.recovery + change.recovery, MIN_RECOVERY),
			damage = math.max(round(move.damage * change.damage), 1),
			chip = move.chip,
			reach = roundTo(move.reach * change.reach, 2),
			hitRadius = roundTo(move.hitRadius * change.hitRadius, 2),
			hitstun = move.hitstun + change.hitstun,
			blockstun = move.blockstun + change.blockstun,
			knockback = roundTo(move.knockback * change.knockback, 1),
			blockPush = move.blockPush,
			hitstop = math.max(move.hitstop + change.hitstop, 1),
		}
	end

	return {
		maxHp = math.max(round(base.maxHp * hp), 1),
		walkForward = roundTo(base.walkForward * walk, 2),
		walkBack = roundTo(base.walkBack * walk * walkBack, 2),
		strafe = roundTo(base.strafe * walk * strafe, 2),
		dash = {
			startup = math.max(base.dash.startup + dashStartup, 1),
			travel = base.dash.travel,
			recovery = math.max(base.dash.recovery + dashRecovery, 3),
			speed = roundTo(base.dash.speed * dashSpeed, 2),
		},
		moves = moves,
		chipTaken = math.max(chipTaken, 0),
		blockstunTaken = blockstunTaken,
		hitstunTaken = hitstunTaken,
		knockbackTaken = roundTo(knockbackTaken, 2),
	}
end

-- A choice is four numbers: the chassis and an option for each slot, all counted from 1.
local function clampIndex(value: unknown, count: number): number
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(math.floor(value), 1, count)
end

-- Whatever a client or a save file says, as a valid choice. Unknown or odd values fall back to the stock part.
function Loadout.sanitize(raw: unknown): Choice
	local source: { [string]: unknown } = if type(raw) == "table" then raw :: any else {}
	return {
		chassis = clampIndex(source.chassis, #Loadout.Chassis),
		arms = clampIndex(source.arms, #Loadout.Modules.ARMS),
		core = clampIndex(source.core, #Loadout.Modules.CORE),
		legs = clampIndex(source.legs, #Loadout.Modules.LEGS),
	}
end

-- The one number a choice travels as. 0 is never used, so a core that has not been given a loadout reads as invalid.
function Loadout.encode(choice: Choice): number
	local options = Loadout.OptionsPerSlot
	local index = ((choice.chassis - 1) * options + (choice.arms - 1)) * options + (choice.core - 1)
	return 1 + index * options + (choice.legs - 1)
end

function Loadout.codeCount(): number
	local options = Loadout.OptionsPerSlot
	return #Loadout.Chassis * options * options * options
end

-- The choice a code stands for, or the stock ANVIL when the code means nothing.
function Loadout.decode(code: unknown): Choice
	if type(code) ~= "number" or code ~= code or code < 1 or code > Loadout.codeCount() or code % 1 ~= 0 then
		return { chassis = 1, arms = 1, core = 1, legs = 1 }
	end
	local options = Loadout.OptionsPerSlot
	local rest = code - 1
	local legs = rest % options
	rest = (rest - legs) / options
	local core = rest % options
	rest = (rest - core) / options
	local arms = rest % options
	local chassis = (rest - arms) / options
	return { chassis = chassis + 1, arms = arms + 1, core = core + 1, legs = legs + 1 }
end

function Loadout.isValidCode(code: unknown): boolean
	return type(code) == "number" and code >= 1 and code <= Loadout.codeCount() and code % 1 == 0
end

-- The stats a choice plays with.
function Loadout.derive(choice: Choice): FightConfig.Stats
	local safe = Loadout.sanitize(choice)
	return build({
		Loadout.Chassis[safe.chassis].mods,
		Loadout.Modules.ARMS[safe.arms].mods,
		Loadout.Modules.CORE[safe.core].mods,
		Loadout.Modules.LEGS[safe.legs].mods,
	})
end

local cache: { [number]: FightConfig.Stats } = {}

-- The stats for a code, built once and shared. Callers must not modify them.
function Loadout.stats(code: unknown): FightConfig.Stats
	local key = if Loadout.isValidCode(code) then code :: number else Loadout.DefaultCode
	local found = cache[key]
	if found == nil then
		found = Loadout.derive(Loadout.decode(key))
		cache[key] = found
	end
	return found
end

-- The robot the bot fights with: the stock ANVIL on EASY, a stock chassis picked from the seed on MEDIUM, and one of the
-- ready-made builds on HARD. The seed changes from match to match, so a rematch can bring something different.
function Loadout.botChoice(level: number, seed: number): Choice
	local pick = math.abs(math.floor(seed))
	if level <= 1 then
		return { chassis = 1, arms = 1, core = 1, legs = 1 }
	elseif level == 2 then
		return { chassis = pick % #Loadout.Chassis + 1, arms = 1, core = 1, legs = 1 }
	end
	local preset = Loadout.Presets[pick % #Loadout.Presets + 1]
	return { chassis = preset.chassis, arms = preset.arms, core = preset.core, legs = preset.legs }
end

-- How large the robot is drawn.
function Loadout.scale(code: unknown): number
	return Loadout.Chassis[Loadout.decode(code).chassis].scale
end

-- The ready-made build a choice matches exactly, or nil.
function Loadout.presetIndex(choice: Choice): number?
	local safe = Loadout.sanitize(choice)
	for index, preset in Loadout.Presets do
		if
			preset.chassis == safe.chassis
			and preset.arms == safe.arms
			and preset.core == safe.core
			and preset.legs == safe.legs
		then
			return index
		end
	end
	return nil
end

-- What the garage calls a build: its preset's name, the chassis' own name when every module is stock, or CUSTOM and the
-- chassis' name.
function Loadout.buildName(choice: Choice): string
	local safe = Loadout.sanitize(choice)
	local preset = Loadout.presetIndex(safe)
	if preset ~= nil then
		return Loadout.Presets[preset].name
	end
	local chassis = Loadout.Chassis[safe.chassis].name
	if safe.arms == 1 and safe.core == 1 and safe.legs == 1 then
		return chassis
	end
	return "CUSTOM " .. chassis
end

-- The parts of a build in one line: the chassis, then every module that is not stock.
function Loadout.summary(choice: Choice): string
	local safe = Loadout.sanitize(choice)
	local parts = { Loadout.Chassis[safe.chassis].name }
	local picks = { ARMS = safe.arms, CORE = safe.core, LEGS = safe.legs }
	for _, slot in Loadout.Slots do
		if picks[slot] > 1 then
			table.insert(parts, Loadout.Modules[slot][picks[slot]].name)
		end
	end
	return table.concat(parts, " · ")
end

-- What each move field is called, and whether a bigger number is better for the robot that has it.
local DESCRIBED_FIELDS: { [string]: { label: string, higherIsBetter: boolean } } = {
	damage = { label = "damage", higherIsBetter = true },
	reach = { label = "reach", higherIsBetter = true },
	knockback = { label = "knockback", higherIsBetter = true },
	startup = { label = "startup", higherIsBetter = false },
	recovery = { label = "recovery", higherIsBetter = false },
}

local SELECTOR_WORDS: { [string]: string } = {
	all = "all attacks",
	punch = "punches",
	kick = "kicks",
	jab = "the jab",
	straight = "the straight",
	snap = "the snap kick",
	power = "the power kick",
}

local function percent(multiplier: number): string
	local value = round((multiplier - 1) * 100)
	return (if value > 0 then "+" else "") .. value .. "%"
end

local function frames(count: number): string
	return (if count > 0 then "+" else "") .. count .. (if math.abs(count) == 1 then " frame" else " frames")
end

-- Plain-language lines for a mod, for the garage to show. `good` says which side of the trade each line is on.
function Loadout.describe(mod: Mod): { Line }
	local lines: { Line } = {}
	local function add(text: string, good: boolean)
		table.insert(lines, { text = text, good = good })
	end
	if mod.hp ~= nil then
		add(`{percent(mod.hp)} health`, mod.hp > 1)
	end
	if mod.walk ~= nil then
		add(`{percent(mod.walk)} walking speed`, mod.walk > 1)
	end
	if mod.walkBack ~= nil then
		add(`{percent(mod.walkBack)} backing-away speed`, mod.walkBack > 1)
	end
	if mod.strafe ~= nil then
		add(`{percent(mod.strafe)} sidestep speed`, mod.strafe > 1)
	end
	if mod.dashSpeed ~= nil then
		add(`{percent(mod.dashSpeed)} dash speed`, mod.dashSpeed > 1)
	end
	if mod.dashStartup ~= nil then
		add(`{frames(mod.dashStartup)} dash startup`, mod.dashStartup < 0)
	end
	if mod.dashRecovery ~= nil then
		add(`{frames(mod.dashRecovery)} dash recovery`, mod.dashRecovery < 0)
	end
	if mod.chipTaken ~= nil then
		add(
			if mod.chipTaken == 0 then "No chip damage" else `{percent(mod.chipTaken)} chip damage taken`,
			mod.chipTaken < 1
		)
	end
	if mod.blockstunTaken ~= nil then
		add(`{frames(mod.blockstunTaken)} blockstun`, mod.blockstunTaken < 0)
	end
	if mod.hitstunTaken ~= nil then
		add(`{frames(mod.hitstunTaken)} hitstun`, mod.hitstunTaken < 0)
	end
	if mod.knockbackTaken ~= nil then
		add(`{percent(mod.knockbackTaken)} knockback taken`, mod.knockbackTaken < 1)
	end
	local byMove = mod.moves
	if byMove ~= nil then
		for _, selector in MOVE_SELECTORS do
			local change = byMove[selector]
			if change ~= nil then
				local words = SELECTOR_WORDS[selector]
				for _, field in { "damage", "reach", "knockback" } do
					local value = (change :: any)[field]
					if value ~= nil then
						local label = DESCRIBED_FIELDS[field]
						add(`{percent(value)} {label.label} on {words}`, (value > 1) == label.higherIsBetter)
					end
				end
				for _, field in { "startup", "recovery" } do
					local value = (change :: any)[field]
					if value ~= nil then
						local label = DESCRIBED_FIELDS[field]
						add(`{frames(value)} {label.label} on {words}`, (value > 0) == label.higherIsBetter)
					end
				end
			end
		end
	end
	return lines
end

-- Five ratings from 1 to 10 for the garage's bars, with 5 for the stock robot: health, mobility, damage, speed of the
-- attacks, and reach. They are read off the derived stats, so they cannot drift from what the simulation does.
function Loadout.ratings(
	stats: FightConfig.Stats
): { health: number, mobility: number, damage: number, speed: number, reach: number }
	local base = FightConfig.BaseStats
	local function rating(ratio: number): number
		return math.clamp(roundTo(5 * ratio, 1), 1, 10)
	end
	local function average(read: (move: FightConfig.MoveData) -> number): number
		local total = 0
		for _, move in stats.moves do
			total += read(move)
		end
		local reference = 0
		for _, move in base.moves do
			reference += read(move)
		end
		return total / reference
	end
	local walk = stats.walkForward / base.walkForward
	local dash = (stats.dash.speed / base.dash.speed) * (base.dash.recovery / stats.dash.recovery)
	return {
		health = rating(stats.maxHp / base.maxHp),
		mobility = rating(0.6 * walk + 0.4 * dash),
		damage = rating(average(function(move)
			return move.damage
		end)),
		speed = rating(1 / average(function(move)
			return move.startup + move.recovery * 0.5
		end)),
		reach = rating(average(function(move)
			return move.reach + move.hitRadius
		end)),
	}
end

return Loadout
