--!strict

-- The cosmetic side of the garage: paint, finishes, head crests and premium bodies, how a look travels as one number,
-- which robot frame and add-on kits a loadout and a look put on the robot, and how the two fighters' colors are kept apart
-- on screen. Pure data and arithmetic like Loadout (colors are plain 0-255 numbers, not Color3), so it runs anywhere and
-- can be tested without Roblox. Nothing here changes how a fight plays. Some crests and every premium body are shop items
-- (see Shop); the server only lets a player wear the ones they own (see `strip`).

local Loadout = require(script.Parent.Loadout)

export type Rgb = { number }

-- A swatch without a color stands for the side's own team color.
export type Swatch = { name: string, color: Rgb? }

export type Finish = {
	name: string,
	-- An Enum.Material name for the armor and trim.
	material: string,
	reflectance: number,
}

-- A body a chassis can be drawn as. The first is every chassis' own frame; the others are premium bodies, each for one
-- chassis, drawn as another frame on the same skeleton and unlocked by a shop item.
export type Body = {
	name: string,
	chassis: number?,
	frame: string?,
	item: string?,
}

-- Every choice is a position in one of the lists below, counted from 1. Position 1 is the default.
export type Look = {
	armor: number,
	accent: number,
	finish: number,
	crest: number,
	body: number,
}

export type Resolved = {
	armor: Rgb,
	accent: Rgb,
	finish: Finish,
	crest: number,
}

local Looks = {}

-- What each side wears when its look says "team": the local fighter in light steel and blue, the opponent in gunmetal and
-- red, so the two always read apart at a glance.
Looks.Team = {
	me = { armor = { 0.52 * 255, 0.56 * 255, 0.66 * 255 }, accent = { 70, 140, 255 } },
	foe = { armor = { 0.2 * 255, 0.21 * 255, 0.26 * 255 }, accent = { 255, 84, 70 } },
}

Looks.Armor = {
	{ name = "TEAM" },
	{ name = "STEEL", color = { 133, 143, 168 } },
	{ name = "GUNMETAL", color = { 51, 54, 66 } },
	{ name = "SNOW", color = { 222, 228, 236 } },
	{ name = "OBSIDIAN", color = { 24, 26, 32 } },
	{ name = "BONE", color = { 206, 196, 170 } },
	{ name = "SAND", color = { 176, 150, 100 } },
	{ name = "COPPER", color = { 168, 92, 52 } },
	{ name = "BRASS", color = { 150, 120, 52 } },
	{ name = "CRIMSON", color = { 150, 38, 44 } },
	{ name = "ROSE", color = { 176, 86, 124 } },
	{ name = "VIOLET", color = { 92, 62, 138 } },
	{ name = "COBALT", color = { 50, 76, 160 } },
	{ name = "OCEAN", color = { 36, 92, 132 } },
	{ name = "MOSS", color = { 84, 104, 62 } },
	{ name = "FOREST", color = { 34, 74, 56 } },
} :: { Swatch }

-- The trim, the glowing eyes and core, and the sparks and trails all follow this color.
Looks.Accents = {
	{ name = "TEAM" },
	{ name = "ICE", color = { 80, 200, 255 } },
	{ name = "COBALT", color = { 70, 140, 255 } },
	{ name = "TEAL", color = { 40, 220, 210 } },
	{ name = "MINT", color = { 90, 255, 190 } },
	{ name = "LIME", color = { 150, 255, 70 } },
	{ name = "SUN", color = { 255, 220, 70 } },
	{ name = "AMBER", color = { 255, 170, 50 } },
	{ name = "FLAME", color = { 255, 110, 50 } },
	{ name = "SCARLET", color = { 255, 84, 70 } },
	{ name = "PINK", color = { 255, 100, 170 } },
	{ name = "MAGENTA", color = { 230, 70, 255 } },
	{ name = "VIOLET", color = { 150, 100, 255 } },
	{ name = "WHITE", color = { 240, 244, 255 } },
	{ name = "GOLD", color = { 230, 190, 90 } },
	{ name = "SILVER", color = { 190, 200, 215 } },
} :: { Swatch }

Looks.Finishes = {
	{ name = "BRUSHED", material = "Metal", reflectance = 0 },
	{ name = "MATTE", material = "SmoothPlastic", reflectance = 0 },
	{ name = "CHROME", material = "Metal", reflectance = 0.3 },
	{ name = "GLOSS", material = "Plastic", reflectance = 0.15 },
} :: { Finish }

-- The head crests: the first is none, and each of the others is a kit in RobotKits. A crest with an item in CrestItems is
-- bought in the shop; the rest are everyone's.
Looks.Crests = { "NONE", "FIN", "ANTENNA", "HORNS", "HALO", "CROWN", "MOHAWK" }
Looks.CrestKits = { "", "CrestFin", "CrestAntenna", "CrestHorns", "CrestHalo", "CrestCrown", "CrestMohawk" }
Looks.CrestItems = { "", "", "", "", "", "crest.crown", "crest.mohawk" }

-- The robot each chassis is drawn as, by frame name in RobotRigs. Every frame is built on the same skeleton, so they all
-- play the same animations.
Looks.Frames = { "Anvil", "Bulwark", "Lance", "Razor", "Maul" }

Looks.Bodies = {
	{ name = "STOCK" },
	{ name = "MONARCH", chassis = 5, frame = "Monarch", item = "body.monarch" },
} :: { Body }

-- The distance in RGB below which two colors are too alike to tell fighters apart.
local ARMOR_CLASH = 70
local ACCENT_CLASH = 90

local function clampIndex(value: unknown, count: number): number
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(math.floor(value), 1, count)
end

function Looks.default(): Look
	return { armor = 1, accent = 1, finish = 1, crest = 1, body = 1 }
end

-- Whatever a client or a save file says, as a valid look.
function Looks.sanitize(raw: unknown): Look
	local source: { [string]: unknown } = if type(raw) == "table" then raw :: any else {}
	return {
		armor = clampIndex(source.armor, #Looks.Armor),
		accent = clampIndex(source.accent, #Looks.Accents),
		finish = clampIndex(source.finish, #Looks.Finishes),
		crest = clampIndex(source.crest, #Looks.Crests),
		body = clampIndex(source.body, #Looks.Bodies),
	}
end

function Looks.codeCount(): number
	return #Looks.Bodies * #Looks.Armor * #Looks.Accents * #Looks.Finishes * #Looks.Crests
end

-- A look travels as one number from 1, the same way a loadout does. (Saves keep each choice on its own, so the codes may
-- change as the lists grow.)
function Looks.encode(look: Look): number
	local index = (look.body - 1) * #Looks.Armor + (look.armor - 1)
	index = index * #Looks.Accents + (look.accent - 1)
	index = index * #Looks.Finishes + (look.finish - 1)
	index = index * #Looks.Crests + (look.crest - 1)
	return 1 + index
end

function Looks.isValidCode(code: unknown): boolean
	return type(code) == "number" and code >= 1 and code <= Looks.codeCount() and code % 1 == 0
end

function Looks.decode(code: unknown): Look
	if not Looks.isValidCode(code) then
		return Looks.default()
	end
	local rest = (code :: number) - 1
	local crests, finishes, accents, armors = #Looks.Crests, #Looks.Finishes, #Looks.Accents, #Looks.Armor
	local crest = rest % crests
	rest = (rest - crest) / crests
	local finish = rest % finishes
	rest = (rest - finish) / finishes
	local accent = rest % accents
	rest = (rest - accent) / accents
	local armor = rest % armors
	local body = (rest - armor) / armors
	return { armor = armor + 1, accent = accent + 1, finish = finish + 1, crest = crest + 1, body = body + 1 }
end

-- The look a bot wears: its team colors, with one of everyone's crests picked from the seed so the bots are not all the
-- same robot.
function Looks.botLook(seed: number): Look
	local look = Looks.default()
	local free: { number } = {}
	for index, item in Looks.CrestItems do
		if item == "" then
			table.insert(free, index)
		end
	end
	look.crest = free[math.abs(math.floor(seed * 3)) % #free + 1]
	return look
end

-- The shop item a crest or a body needs, or nil for one everyone has.
function Looks.crestItem(crest: number): string?
	local item = Looks.CrestItems[crest]
	return if item ~= nil and item ~= "" then item else nil
end

function Looks.bodyItem(body: number): string?
	local entry = Looks.Bodies[body]
	return if entry ~= nil then entry.item else nil
end

-- The look with any crest or body its wearer does not own taken off.
function Looks.strip(look: Look, owns: (item: string) -> boolean): Look
	local crestItem = Looks.crestItem(look.crest)
	local bodyItem = Looks.bodyItem(look.body)
	return {
		armor = look.armor,
		accent = look.accent,
		finish = look.finish,
		crest = if crestItem ~= nil and not owns(crestItem) then 1 else look.crest,
		body = if bodyItem ~= nil and not owns(bodyItem) then 1 else look.body,
	}
end

-- The body a shop item unlocks, and the crest; nil when it is not one.
function Looks.bodyFor(item: string): number?
	for index, body in Looks.Bodies do
		if body.item == item then
			return index
		end
	end
	return nil
end

function Looks.crestFor(item: string): number?
	for index, crestItem in Looks.CrestItems do
		if crestItem == item then
			return index
		end
	end
	return nil
end

-- The kits to draw for a loadout and a look: the crest. (A chassis is a frame of its own; see frameFor.)
function Looks.kitsFor(_choice: Loadout.Choice, look: Look): { string }
	local crest = Looks.CrestKits[look.crest]
	return if crest ~= nil and crest ~= "" then { crest } else {}
end

-- The frame (a robot in RobotRigs) a loadout is drawn as with a look: the chassis' own, or the premium body the look
-- picks when that body is for this chassis.
function Looks.frameFor(choice: Loadout.Choice, look: Look): string
	local body = Looks.Bodies[look.body]
	if body ~= nil and body.frame ~= nil and body.chassis == choice.chassis then
		return body.frame
	end
	return Looks.Frames[choice.chassis] or Looks.Frames[1]
end

local function distance(a: Rgb, b: Rgb): number
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dr * dr + dg * dg + db * db)
end

Looks.distance = distance

-- A swatch's color for a side: its own, or the side's team color for the first entry.
local function colorOf(swatch: Swatch, team: Rgb): Rgb
	return swatch.color or team
end

-- The first color in the list that stays clear of `against`, or failing that the one farthest from it.
local function clearOf(candidates: { Rgb }, against: Rgb, threshold: number): Rgb
	local best = candidates[1]
	local bestDistance = -1.0
	for _, candidate in candidates do
		local apart = distance(candidate, against)
		if apart >= threshold then
			return candidate
		end
		if apart > bestDistance then
			best = candidate
			bestDistance = apart
		end
	end
	return best
end

-- What each fighter is drawn in. The local fighter keeps its own choices; the opponent keeps its own unless they are too
-- close to the local fighter's, in which case it falls back to its team colors, then to colors that cannot be mistaken.
function Looks.resolve(mine: Look, theirs: Look): (Resolved, Resolved)
	local myArmor = colorOf(Looks.Armor[mine.armor], Looks.Team.me.armor)
	local myAccent = colorOf(Looks.Accents[mine.accent], Looks.Team.me.accent)
	local foeArmor = clearOf({
		colorOf(Looks.Armor[theirs.armor], Looks.Team.foe.armor),
		Looks.Team.foe.armor,
		Looks.Team.me.armor,
		{ 222, 228, 236 },
		{ 24, 26, 32 },
	}, myArmor, ARMOR_CLASH)
	local foeAccent = clearOf({
		colorOf(Looks.Accents[theirs.accent], Looks.Team.foe.accent),
		Looks.Team.foe.accent,
		Looks.Team.me.accent,
		{ 255, 220, 70 },
		{ 230, 70, 255 },
	}, myAccent, ACCENT_CLASH)
	return {
		armor = myArmor,
		accent = myAccent,
		finish = Looks.Finishes[mine.finish],
		crest = mine.crest,
	}, {
		armor = foeArmor,
		accent = foeAccent,
		finish = Looks.Finishes[theirs.finish],
		crest = theirs.crest,
	}
end

return Looks
