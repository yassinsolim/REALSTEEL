--!strict

-- The cosmetic side of the garage: paint, finishes, head crests, premium bodies, core glows, strike trails, impact effects
-- and titles, how a look travels as one number, which robot frame and add-on kits a loadout and a look put on the robot,
-- and how the two fighters' colors are kept apart on screen. Pure data and arithmetic like Loadout (colors are plain 0-255
-- numbers, not Color3), so it runs anywhere and can be tested without Roblox. Nothing here changes how a fight plays. Some
-- crests and every premium body are shop items (see Shop), the glows, trails, impacts, titles and a few paints come from
-- cases (see Cases); the server only lets a player wear the ones they own (see `strip`).

local Loadout = require(script.Parent.Loadout)

export type Rgb = { number }

-- A swatch without a color stands for the side's own team color. A swatch with an item is a case item (see Cases): only
-- its owners may wear it.
export type Swatch = { name: string, color: Rgb?, item: string? }

-- The robot's core glow (its eyes and lights). The first follows the accent color; the others are case items. An
-- animated glow changes over time (see RobotRig): "pulse" breathes in and out, "spectrum" runs through every hue.
export type Glow = { name: string, color: Rgb?, animation: string?, item: string? }

-- The trails behind a striking fist or foot: from a hot core (`from`) to a color (`to`), or through every hue. The first
-- runs from white to the accent color.
export type Trail = { name: string, from: Rgb?, to: Rgb?, animation: string?, item: string? }

-- How the player's hits burst: the standard sparks in the hit color, or a case item's color with a flair on top ("smoke",
-- "ring" or "coins", see Effects).
export type Impact = { name: string, color: Rgb?, flair: string?, item: string? }

-- A title shown under the player's name, on their bay and in the ring. The first is none.
export type Title = { name: string, item: string? }

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
	glow: number,
	trail: number,
	impact: number,
	title: number,
}

export type Resolved = {
	armor: Rgb,
	accent: Rgb,
	finish: Finish,
	crest: number,
	glow: Glow,
	trail: Trail,
	impact: Impact,
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
	-- Case items from here on.
	{ name = "PEARL", color = { 232, 226, 214 }, item = "armor.pearl" },
	{ name = "ROSE GOLD", color = { 198, 136, 116 }, item = "armor.rosegold" },
} :: { Swatch }

-- The trim, the glowing eyes and core, and the sparks and trails all follow this color, unless the look picks a core glow,
-- a strike trail or an impact of its own.
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
	-- Case items from here on.
	{ name = "ACID", color = { 196, 255, 48 }, item = "accent.acid" },
} :: { Swatch }

Looks.Glows = {
	{ name = "ACCENT" },
	{ name = "ARC WHITE", color = { 236, 244, 255 }, item = "glow.arcwhite" },
	{ name = "TOXIC", color = { 120, 255, 80 }, item = "glow.toxic" },
	{ name = "PLASMA", color = { 186, 104, 255 }, item = "glow.plasma" },
	{ name = "SOLAR", color = { 255, 206, 72 }, item = "glow.solar" },
	{ name = "BLOOD MOON", color = { 255, 44, 58 }, item = "glow.bloodmoon" },
	{ name = "DEEP SEA", color = { 36, 140, 255 }, item = "glow.deepsea" },
	{ name = "PULSE", color = { 255, 120, 56 }, animation = "pulse", item = "glow.pulse" },
	{ name = "SPECTRUM", animation = "spectrum", item = "glow.spectrum" },
} :: { Glow }

Looks.Trails = {
	{ name = "ACCENT" },
	{ name = "FROST", from = { 255, 255, 255 }, to = { 96, 206, 255 }, item = "trail.frost" },
	{ name = "EMBER", from = { 255, 232, 150 }, to = { 255, 84, 28 }, item = "trail.ember" },
	{ name = "VENOM", from = { 226, 255, 150 }, to = { 64, 210, 70 }, item = "trail.venom" },
	{ name = "SHADOW", from = { 196, 150, 255 }, to = { 40, 12, 70 }, item = "trail.shadow" },
	{ name = "PRISM", animation = "spectrum", item = "trail.prism" },
} :: { Trail }

Looks.Impacts = {
	{ name = "STANDARD" },
	{ name = "ARC", color = { 120, 204, 255 }, item = "impact.arc" },
	{ name = "INFERNO", color = { 255, 104, 30 }, flair = "smoke", item = "impact.inferno" },
	{ name = "VOID", color = { 168, 78, 255 }, flair = "ring", item = "impact.void" },
	{ name = "GOLD RUSH", color = { 255, 198, 64 }, flair = "coins", item = "impact.goldrush" },
} :: { Impact }

Looks.Titles = {
	{ name = "NONE" },
	{ name = "SCRAPPER", item = "title.scrapper" },
	{ name = "GEARHEAD", item = "title.gearhead" },
	{ name = "BRAWLER", item = "title.brawler" },
	{ name = "IRON FIST", item = "title.ironfist" },
	{ name = "HEAVYWEIGHT", item = "title.heavyweight" },
	{ name = "THE MACHINE", item = "title.themachine" },
	{ name = "UNBREAKABLE", item = "title.unbreakable" },
} :: { Title }

-- What each kind of case item is called, by the prefix of its id.
Looks.KindNames = {
	armor = "ARMOR PAINT",
	accent = "ACCENT PAINT",
	glow = "CORE GLOW",
	trail = "STRIKE TRAIL",
	impact = "IMPACT FX",
	title = "TITLE",
}

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
	{ name = "HAYMAKER", chassis = 1, frame = "Haymaker", item = "body.haymaker" },
	{ name = "BASTION", chassis = 2, frame = "Bastion", item = "body.bastion" },
	{ name = "SPECTRE", chassis = 3, frame = "Spectre", item = "body.spectre" },
	{ name = "RONIN", chassis = 4, frame = "Ronin", item = "body.ronin" },
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
	return { armor = 1, accent = 1, finish = 1, crest = 1, body = 1, glow = 1, trail = 1, impact = 1, title = 1 }
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
		glow = clampIndex(source.glow, #Looks.Glows),
		trail = clampIndex(source.trail, #Looks.Trails),
		impact = clampIndex(source.impact, #Looks.Impacts),
		title = clampIndex(source.title, #Looks.Titles),
	}
end

-- The choices in the order a code packs them, most significant first, with the length of each one's list.
local function dimensions(): { { key: string, count: number } }
	return {
		{ key = "title", count = #Looks.Titles },
		{ key = "impact", count = #Looks.Impacts },
		{ key = "trail", count = #Looks.Trails },
		{ key = "glow", count = #Looks.Glows },
		{ key = "body", count = #Looks.Bodies },
		{ key = "armor", count = #Looks.Armor },
		{ key = "accent", count = #Looks.Accents },
		{ key = "finish", count = #Looks.Finishes },
		{ key = "crest", count = #Looks.Crests },
	}
end

function Looks.codeCount(): number
	local count = 1
	for _, dimension in dimensions() do
		count *= dimension.count
	end
	return count
end

-- A look travels as one number from 1, the same way a loadout does. (Saves keep each choice on its own, so the codes may
-- change as the lists grow.)
function Looks.encode(look: Look): number
	local values = look :: any
	local index = 0
	for _, dimension in dimensions() do
		index = index * dimension.count + (values[dimension.key] - 1)
	end
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
	local look = Looks.default()
	local values = look :: any
	local order = dimensions()
	for position = #order, 1, -1 do
		local dimension = order[position]
		local value = rest % dimension.count
		rest = (rest - value) / dimension.count
		values[dimension.key] = value + 1
	end
	return look
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

-- The lists of the choices case items unlock, by the look's field (which is also the prefix of their items' ids).
local function itemLists(): { [string]: { { name: string, item: string? } } }
	return {
		armor = Looks.Armor :: any,
		accent = Looks.Accents :: any,
		glow = Looks.Glows :: any,
		trail = Looks.Trails :: any,
		impact = Looks.Impacts :: any,
		title = Looks.Titles :: any,
	}
end

-- The item a choice needs (`key` is a look's field, `index` a position in its list), or nil for one everyone has.
function Looks.itemAt(key: string, index: number): string?
	if key == "crest" then
		return Looks.crestItem(index)
	elseif key == "body" then
		return Looks.bodyItem(index)
	end
	local list = itemLists()[key]
	local entry = if list ~= nil then list[index] else nil
	return if entry ~= nil then entry.item else nil
end

-- The look's field and position an item unlocks, or nil for an id that is not a cosmetic.
function Looks.slotOf(item: string): (string?, number?)
	for key, list in itemLists() do
		for index, entry in list do
			if entry.item == item then
				return key, index
			end
		end
	end
	local body = Looks.bodyFor(item)
	if body ~= nil then
		return "body", body
	end
	local crest = Looks.crestFor(item)
	if crest ~= nil then
		return "crest", crest
	end
	return nil, nil
end

-- What an item is called and what kind of thing it is ("CORE GLOW"), for the case screen; nil for an unknown id.
function Looks.describe(item: string): { name: string, kind: string }?
	local key, index = Looks.slotOf(item)
	if key == nil or index == nil then
		return nil
	end
	if key == "crest" then
		return { name = Looks.Crests[index], kind = "CREST" }
	elseif key == "body" then
		return { name = Looks.Bodies[index].name, kind = "BODY" }
	end
	local entry = itemLists()[key][index]
	return { name = entry.name, kind = (Looks.KindNames :: any)[key] or string.upper(key) }
end

-- The title under a look's name, or "" for none.
function Looks.titleOf(look: Look): string
	return if look.title > 1 and Looks.Titles[look.title] ~= nil then Looks.Titles[look.title].name else ""
end

-- Every item a player can own, each once, in a fixed order: the premium bodies, the shop's crests, then the case items by
-- the look's fields. (Only a server and its clients, which run the same code, need to agree on the order: saves keep ids.)
function Looks.items(): { string }
	local items: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(item: string?)
		if item ~= nil and item ~= "" and not seen[item] then
			seen[item] = true
			table.insert(items, item)
		end
	end
	for _, body in Looks.Bodies do
		add(body.item)
	end
	for _, crest in Looks.CrestItems do
		add(crest)
	end
	local lists = itemLists()
	for _, key in { "armor", "accent", "glow", "trail", "impact", "title" } do
		for _, entry in lists[key] do
			add(entry.item)
		end
	end
	return items
end

-- The look with anything its wearer does not own taken off: shop crests and bodies, and every case item.
function Looks.strip(look: Look, owns: (item: string) -> boolean): Look
	local stripped = table.clone(look)
	local values = stripped :: any
	for _, key in { "armor", "accent", "crest", "body", "glow", "trail", "impact", "title" } do
		local item = Looks.itemAt(key, values[key])
		if item ~= nil and not owns(item) then
			values[key] = 1
		end
	end
	return stripped
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
		glow = Looks.Glows[mine.glow] or Looks.Glows[1],
		trail = Looks.Trails[mine.trail] or Looks.Trails[1],
		impact = Looks.Impacts[mine.impact] or Looks.Impacts[1],
	}, {
		armor = foeArmor,
		accent = foeAccent,
		finish = Looks.Finishes[theirs.finish],
		crest = theirs.crest,
		glow = Looks.Glows[theirs.glow] or Looks.Glows[1],
		trail = Looks.Trails[theirs.trail] or Looks.Trails[1],
		impact = Looks.Impacts[theirs.impact] or Looks.Impacts[1],
	}
end

return Looks
