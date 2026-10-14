--!strict

-- THE FOUNDRY: the hall players walk around in. A dark steel hall with a roof of girders and hanging lamps, a loop of
-- molten channel under grates around the main ring's island, a catwalk along the south wall that players spawn on, a rail
-- that keeps spectators out of the fight camera's way, the operators' booths beside every ring, a four-sided screen over
-- the main ring, the practice pits along the east side (see Arena), and the stations (see FoundryStations). Built from
-- code like everything else; FoundryLayout has the numbers the clients need too.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local Arena = require(script.Parent.Arena)
local Build = require(script.Parent.Build)
local FoundryStations = require(script.Parent.FoundryStations)

export type Hall = {
	model: Model,
	bays: { FoundryStations.Bay },
	pads: { [string]: Part },
	spawn: SpawnLocation,
}

local Foundry = {}

local TEAL = Color3.fromRGB(64, 214, 232)
-- Teal for lines that should read without glowing at the player: painted markings and the thin wall line.
local TEAL_SOFT = Color3.fromRGB(70, 150, 162)
local AMBER = Color3.fromRGB(255, 178, 66)
local TEAM_BLUE = Color3.fromRGB(70, 140, 255)
local TEAM_RED = Color3.fromRGB(255, 84, 70)
-- Deep enough that the channels smoulder under their grates rather than flood the floor with orange.
local MOLTEN = Color3.fromRGB(196, 62, 18)
local LAVA = Color3.fromRGB(255, 120, 40)
-- The hall's surfaces are mid grays rather than near black, so the lamps have something to light: the eye adjusts to a
-- lit room, not to a black one with glowing lines in it.
local FLOOR = Color3.fromRGB(74, 76, 82)
local WALL = Color3.fromRGB(56, 60, 68)
local ROOF = Color3.fromRGB(34, 36, 42)
local GIRDER = Color3.fromRGB(64, 68, 78)
local STEEL = Color3.fromRGB(86, 92, 106)
local GRATE = Color3.fromRGB(52, 54, 60)
local HANDRAIL = Color3.fromRGB(110, 116, 130)
local DARK = Color3.fromRGB(14, 16, 22)
local LAMP = Color3.fromRGB(255, 222, 186)
-- The walls' wash: cool, against the lamps' warm pools on the floor.
local WASH = Color3.fromRGB(170, 196, 232)

local LAYOUT = FoundryLayout
local MID_X = (LAYOUT.West + LAYOUT.East) / 2
local MID_Z = (LAYOUT.North + LAYOUT.South) / 2
local SPAN_X = LAYOUT.East - LAYOUT.West
local SPAN_Z = LAYOUT.South - LAYOUT.North

local function light(parent: BasePart, kind: string, range: number, brightness: number, color: Color3)
	local item = Instance.new(kind) :: any
	item.Range = range
	item.Brightness = brightness
	item.Color = color
	item.Shadows = false
	item.Parent = parent
end

-- An invisible anchor for a light.
local function lightPoint(model: Model, position: Vector3): Part
	local part = Build.decor(model, "Light", Vector3.one * 0.3, CFrame.new(position), DARK, Enum.Material.SmoothPlastic)
	part.Transparency = 1
	return part
end

-- A soft cool light low down, aimed up the wall it stands in front of (`towardWall` points at the wall).
local function wallWash(model: Model, at: Vector3, towardWall: Vector3)
	local anchor = lightPoint(model, at)
	anchor.CFrame = CFrame.lookAt(at, at + towardWall * 1.2 + Vector3.yAxis * 3)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 22
	spot.Brightness = 1.3
	spot.Color = WASH
	spot.Shadows = false
	spot.Parent = anchor
end

local function buildShell(model: Model)
	local height = LAYOUT.Height
	Build.solid(
		model,
		"Floor",
		Vector3.new(SPAN_X + 4, 1, SPAN_Z + 4),
		CFrame.new(MID_X, -0.5, MID_Z),
		FLOOR,
		Enum.Material.Concrete
	)
	local walls = {
		{ Vector3.new(2, height, SPAN_Z + 4), Vector3.new(LAYOUT.West - 1, height / 2, MID_Z) },
		{ Vector3.new(2, height, SPAN_Z + 4), Vector3.new(LAYOUT.East + 1, height / 2, MID_Z) },
		{ Vector3.new(SPAN_X + 4, height, 2), Vector3.new(MID_X, height / 2, LAYOUT.North - 1) },
		{ Vector3.new(SPAN_X + 4, height, 2), Vector3.new(MID_X, height / 2, LAYOUT.South + 1) },
	}
	-- Concrete, not Metal: in Future lighting a metal surface shows only reflections, and with nothing bright to reflect the
	-- walls of a closed hall read as black however they are lit.
	for _, wall in walls do
		Build.solid(model, "Wall", wall[1], CFrame.new(wall[2]), WALL, Enum.Material.Concrete)
	end
	Build.solid(
		model,
		"Roof",
		Vector3.new(SPAN_X + 4, 1, SPAN_Z + 4),
		CFrame.new(MID_X, height + 0.5, MID_Z),
		ROOF,
		Enum.Material.Metal
	)
	-- A thin teal line along the walls a little above head height: a guide for the eye, not a light.
	local stripe = 9
	for _, line in
		{
			{ Vector3.new(0.2, 0.16, SPAN_Z), Vector3.new(LAYOUT.West + 0.15, stripe, MID_Z) },
			{ Vector3.new(0.2, 0.16, SPAN_Z), Vector3.new(LAYOUT.East - 0.15, stripe, MID_Z) },
			{ Vector3.new(SPAN_X, 0.16, 0.2), Vector3.new(MID_X, stripe, LAYOUT.North + 0.15) },
		}
	do
		local part = Build.decor(model, "Stripe", line[1], CFrame.new(line[2]), TEAL_SOFT, Enum.Material.Neon)
		part.Transparency = 0.45
	end

	-- Columns along the east and north walls (the west side's are the bay dividers), painted steel with caution-painted
	-- feet. A soft cool light at the foot of each washes up the wall behind it, so the walls read as walls instead of black.
	local width = LAYOUT.ColumnWidth
	for _, at in LAYOUT.columns() do
		Build.solid(
			model,
			"Column",
			Vector3.new(width, height, width),
			CFrame.new(at.X, height / 2, at.Z),
			Color3.fromRGB(70, 74, 86),
			Enum.Material.SmoothPlastic
		)
		Build.decor(
			model,
			"ColumnBase",
			Vector3.new(width + 0.3, 1.2, width + 0.3),
			CFrame.new(at.X, 0.6, at.Z),
			AMBER,
			Enum.Material.SmoothPlastic
		)
		local towardWall = if at.Z <= LAYOUT.North + 2 then -Vector3.zAxis else Vector3.xAxis
		wallWash(model, Vector3.new(at.X, 1.4, at.Z) - towardWall * 1.6, towardWall)
	end

	-- Girders across the roof: a top and a bottom chord with posts between them.
	for z = LAYOUT.North + 12, LAYOUT.South - 4, 22 do
		Build.bar(
			model,
			"Girder",
			Vector3.new(LAYOUT.West, height - 1.5, z),
			Vector3.new(LAYOUT.East, height - 1.5, z),
			1.1,
			GIRDER,
			Enum.Material.Metal
		)
		Build.bar(
			model,
			"Chord",
			Vector3.new(LAYOUT.West, height - 4.5, z),
			Vector3.new(LAYOUT.East, height - 4.5, z),
			0.6,
			GIRDER,
			Enum.Material.Metal
		)
		for x = LAYOUT.West + 6, LAYOUT.East - 6, 12 do
			Build.bar(
				model,
				"Brace",
				Vector3.new(x, height - 4.5, z),
				Vector3.new(x + 6, height - 1.5, z),
				0.3,
				GIRDER,
				Enum.Material.Metal
			)
		end
	end

	-- Warm industrial lamps hanging over the walkways, away from the rings' own lights. Each throws a wide pool of light
	-- down onto the floor (lamps this high with only a bulb's glow light the roof and leave the floor black), and the
	-- bulb's own soft glow lights the shade and the girders around it.
	for _, at in
		{
			Vector2.new(-46, -30),
			Vector2.new(-46, 0),
			Vector2.new(-46, 30),
			Vector2.new(-18, -44),
			Vector2.new(18, -44),
			Vector2.new(41, -26),
			Vector2.new(41, 18),
			Vector2.new(68, 4),
			Vector2.new(-18, 48),
			Vector2.new(18, 48),
		}
	do
		local x, z = at.X, at.Y
		Build.bar(model, "LampCable", Vector3.new(x, height, z), Vector3.new(x, 21, z), 0.12, DARK, Enum.Material.Metal)
		Build.decor(
			model,
			"LampShade",
			Vector3.new(1.4, 4.2, 4.2),
			CFrame.new(x, 20.6, z) * CFrame.Angles(0, 0, math.rad(90)),
			GIRDER,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		local bulb = Build.decor(
			model,
			"LampBulb",
			Vector3.new(0.12, 3.4, 3.4),
			CFrame.new(x, 19.86, z) * CFrame.Angles(0, 0, math.rad(90)),
			LAMP,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		bulb.Transparency = 0.15
		-- The bulb is a cylinder turned onto its side, so its Left face (-X) is the one pointing down.
		local pool = Instance.new("SpotLight")
		pool.Face = Enum.NormalId.Left
		pool.Angle = 120
		pool.Range = 34
		pool.Brightness = 2.4
		pool.Color = LAMP
		pool.Shadows = false
		pool.Parent = bulb
		light(bulb, "PointLight", 9, 0.6, LAMP)
	end
end

-- A strip of molten metal along one side of the loop, under a close grate, between two curbs: a bed of cracked lava with a
-- narrow glowing core, so only embers show between the bars and the loop smoulders around the island instead of reading
-- as a band of light.
local function buildChannel(model: Model, from: Vector2, to: Vector2)
	local alongX = from.Y == to.Y
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	local turn = if alongX then CFrame.identity else CFrame.Angles(0, math.rad(90), 0)
	local base = CFrame.new(middle.X, 0, middle.Y) * turn
	Build.decor(
		model,
		"Molten",
		Vector3.new(length + 1.6, 0.06, 1.6),
		base * CFrame.new(0, 0.03, 0),
		LAVA,
		Enum.Material.CrackedLava
	)
	Build.decor(
		model,
		"MoltenCore",
		Vector3.new(length + 1.6, 0.06, 0.5),
		base * CFrame.new(0, 0.05, 0),
		MOLTEN,
		Enum.Material.Neon
	)
	for _, side in { -1, 1 } do
		Build.decor(
			model,
			"Curb",
			Vector3.new(length + 2, 0.18, 0.4),
			base * CFrame.new(0, 0.09, side),
			GRATE,
			Enum.Material.Metal
		)
	end
	local count = math.floor(length / 0.95)
	for index = 0, count do
		Build.decor(
			model,
			"Grate",
			Vector3.new(0.5, 0.14, 1.9),
			base * CFrame.new(-length / 2 + index * length / count, 0.1, 0),
			GRATE,
			Enum.Material.DiamondPlate
		)
	end
	-- The glow spills onto the floor around it.
	local lights = math.max(1, math.floor(length / 20))
	for index = 1, lights do
		local t = (index - 0.5) / lights
		local point = from:Lerp(to, t)
		light(lightPoint(model, Vector3.new(point.X, 0.8, point.Y)), "PointLight", 12, 1.1, MOLTEN)
	end
end

local function buildChannels(model: Model)
	local x, north, south = LAYOUT.ChannelX, LAYOUT.ChannelNorth, LAYOUT.ChannelSouth
	buildChannel(model, Vector2.new(-x, north), Vector2.new(x, north))
	buildChannel(model, Vector2.new(-x, south), Vector2.new(x, south))
	buildChannel(model, Vector2.new(-x, north), Vector2.new(-x, south))
	buildChannel(model, Vector2.new(x, north), Vector2.new(x, south))
end

-- The catwalk players spawn on, with a rail along its front and a stair at each end down to the floor.
local function buildDeck(model: Model): SpawnLocation
	local top = LAYOUT.DeckTop
	local northEdge = LAYOUT.DeckNorth
	local depth = LAYOUT.South - northEdge
	Build.solid(
		model,
		"Deck",
		Vector3.new(72, 0.8, depth),
		CFrame.new(0, top - 0.4, northEdge + depth / 2),
		Color3.fromRGB(58, 62, 74),
		Enum.Material.DiamondPlate
	)
	for x = -30, 30, 3 do
		Build.vbar(model, "RailPost", Vector3.new(x, top, northEdge + 0.3), 3, 0.18, STEEL, Enum.Material.Metal)
	end
	-- The handrail is plain steel: it runs across the view of everyone on the catwalk at eye height. The amber line is on
	-- the catwalk's front face instead, where it is seen from the floor and the ring and stays under the spawn's view.
	Build.bar(
		model,
		"RailTop",
		Vector3.new(-30, top + 3, northEdge + 0.3),
		Vector3.new(30, top + 3, northEdge + 0.3),
		0.22,
		HANDRAIL,
		Enum.Material.Metal
	)
	Build.decor(
		model,
		"DeckEdge",
		Vector3.new(60, 0.2, 0.12),
		CFrame.new(0, top - 0.25, northEdge - 0.06),
		AMBER,
		Enum.Material.Neon
	)
	Build.bar(
		model,
		"RailMid",
		Vector3.new(-30, top + 1.6, northEdge + 0.3),
		Vector3.new(30, top + 1.6, northEdge + 0.3),
		0.14,
		STEEL,
		Enum.Material.Metal
	)
	Build.blocker(model, "RailBlock", Vector3.new(60, 4, 0.5), CFrame.new(0, top + 2, northEdge + 0.3))
	for _, x in { -24, -8, 8, 24 } do
		Build.vbar(model, "Support", Vector3.new(x, 0, northEdge + 1.2), top - 0.8, 0.8, GIRDER, Enum.Material.Metal)
	end

	-- A stair at each end runs down toward the ring. A wedge is full height at its back (+Z) and zero at its front.
	local run = 14
	for _, side in { -1, 1 } do
		local stair = Instance.new("WedgePart")
		stair.Name = "Stair"
		stair.Anchored = true
		stair.Size = Vector3.new(6, top, run)
		stair.CFrame = CFrame.new(side * 33, top / 2, northEdge - run / 2)
		stair.Color = Color3.fromRGB(58, 62, 74)
		stair.Material = Enum.Material.DiamondPlate
		stair.Parent = model
		for step = 1, run - 1 do
			Build.decor(
				model,
				"Tread",
				Vector3.new(6, 0.05, 0.12),
				CFrame.new(side * 33, top * step / run + 0.03, northEdge - run + step),
				AMBER,
				Enum.Material.SmoothPlastic
			)
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 0.2, 4)
	spawn.CFrame = LAYOUT.Spawn + Vector3.new(0, 0.1, 0)
	spawn.Parent = model
	light(lightPoint(model, Vector3.new(0, top + 9, 64)), "PointLight", 26, 1.1, LAMP)
	return spawn
end

-- The rail around the ring island. Its LED line is the ribbon the client animates with the crowd's excitement, and an
-- invisible wall behind it keeps characters out of the fight camera's way.
local function buildRail(model: Model)
	local radius = LAYOUT.RailRadius
	local segments = 48
	for index = 1, segments do
		local a0 = (index - 1) / segments * math.pi * 2
		local a1 = index / segments * math.pi * 2
		Build.vbar(model, "RailPost", Build.polar(radius, a0, 0), 3.2, 0.2, STEEL, Enum.Material.Metal)
		Build.bar(
			model,
			"RailTop",
			Build.polar(radius, a0, 3.2),
			Build.polar(radius, a1, 3.2),
			0.24,
			STEEL,
			Enum.Material.Metal
		)
		local led = Build.bar(
			model,
			"RailLed",
			Build.polar(radius - 0.05, a0, 3.42),
			Build.polar(radius - 0.05, a1, 3.42),
			0.16,
			Color3.fromRGB(22, 70, 120),
			Enum.Material.Neon
		)
		CollectionService:AddTag(led, FightConfig.RibbonTag)
		Build.bar(
			model,
			"RailMid",
			Build.polar(radius, a0, 1.7),
			Build.polar(radius, a1, 1.7),
			0.12,
			STEEL,
			Enum.Material.Metal
		)
	end
	local blocks = 24
	local arc = 2 * math.pi * (radius + 0.3) / blocks
	for index = 1, blocks do
		local angle = (index - 0.5) / blocks * math.pi * 2
		Build.blocker(model, "RailBlock", Vector3.new(arc * 1.08, 10, 0.6), Build.facingCenter(radius + 0.3, angle, 5))
	end
end

-- Where the players stand while their robots fight: a platform beside each seat of every ring, with a console in the
-- team color between the player and the ring. `stand` faces the ring. A pit's booths stand inside its fight camera's
-- reach, so like the ropes they fade when the camera comes close (`fades`).
local function buildBooth(model: Model, name: string, stand: CFrame, color: Color3, fades: boolean)
	local floor = LAYOUT.BoothFloor
	local look = Vector3.new(stand.LookVector.X, 0, stand.LookVector.Z)
	local at = Vector3.new(stand.X, 0, stand.Z)
	local base = CFrame.lookAt(at, at + look)
	local parts: { BasePart } = {}
	table.insert(
		parts,
		Build.solid(
			model,
			name,
			Vector3.new(6.6, floor, 4.6),
			base * CFrame.new(0, floor / 2, 0),
			Color3.fromRGB(52, 56, 68),
			Enum.Material.DiamondPlate
		)
	)
	table.insert(
		parts,
		Build.decor(
			model,
			"Console",
			Vector3.new(2.6, 1.1, 1),
			base * CFrame.new(0, floor + 0.55, -1.7),
			DARK,
			Enum.Material.Metal
		)
	)
	-- Leaning back toward the player.
	table.insert(
		parts,
		Build.decor(
			model,
			"Screen",
			Vector3.new(2.3, 0.8, 0.08),
			base * CFrame.new(0, floor + 1.4, -2.25) * CFrame.Angles(math.rad(15), 0, 0),
			color,
			Enum.Material.Neon
		)
	)
	for _, side in { -3.2, 3.2 } do
		table.insert(
			parts,
			Build.bar(
				model,
				"BoothRail",
				(base * CFrame.new(side, floor + 1.2, -2.3)).Position,
				(base * CFrame.new(side, floor + 1.2, 2.3)).Position,
				0.12,
				color,
				Enum.Material.Neon
			)
		)
	end
	if fades then
		for _, part in parts do
			CollectionService:AddTag(part, FightConfig.RingFadeTag)
		end
	end
end

local function buildBooths(model: Model)
	for _, spec in LAYOUT.Rings do
		for slot, stand in spec.booths do
			buildBooth(model, `{spec.name}Booth{slot}`, stand, if slot == 1 then TEAM_BLUE else TEAM_RED, spec.pit)
		end
	end
end

-- A four-sided screen hung over the ring. The clients draw the scoreboard on its faces (Face1 to Face4).
local function buildJumbotron(model: Model)
	local spec = LAYOUT.Jumbotron
	local center, width, height = spec.center, spec.width, spec.height
	Build.decor(model, "Jumbotron", Vector3.new(width, height, width), CFrame.new(center), DARK, Enum.Material.Metal)
	for index, direction in { -Vector3.zAxis, Vector3.xAxis, Vector3.zAxis, -Vector3.xAxis } do
		local at = center + direction * (width / 2 + 0.06)
		local face = Build.decor(
			model,
			"Face" .. index,
			Vector3.new(width - 0.6, height - 0.6, 0.1),
			CFrame.lookAt(at, at + direction),
			Color3.fromRGB(8, 10, 16),
			Enum.Material.SmoothPlastic
		)
		face:SetAttribute("JumbotronFace", index)
	end
	for _, y in { center.Y - height / 2, center.Y + height / 2 } do
		-- A thin frame along the edges, not a slab: from below a solid plate of light is all the screen would be.
		local edge = width + 0.2
		for _, bar in
			{
				{ Vector3.new(edge, 0.18, 0.18), Vector3.new(0, 0, edge / 2) },
				{ Vector3.new(edge, 0.18, 0.18), Vector3.new(0, 0, -edge / 2) },
				{ Vector3.new(0.18, 0.18, edge), Vector3.new(edge / 2, 0, 0) },
				{ Vector3.new(0.18, 0.18, edge), Vector3.new(-edge / 2, 0, 0) },
			}
		do
			local rim = Build.decor(
				model,
				"JumbotronRim",
				bar[1],
				CFrame.new(Vector3.new(center.X, y, center.Z) + bar[2]),
				TEAL,
				Enum.Material.Neon
			)
			rim.Transparency = 0.2
		end
	end
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) } do
		local x, z = center.X + corner.X * (width / 2 - 1), center.Z + corner.Y * (width / 2 - 1)
		Build.bar(
			model,
			"JumbotronCable",
			Vector3.new(x, center.Y + height / 2, z),
			Vector3.new(x, LAYOUT.Height, z),
			0.12,
			DARK,
			Enum.Material.Metal
		)
	end
end

-- The hall's name on the north wall. From the spawn catwalk the screen over the ring hides the wall above about 18 studs
-- and the champion's statue hides its middle below about 12, so the name sits between, with the small line above it.
local function buildSign(model: Model)
	local z = LAYOUT.North + 0.4
	local title = Build.decor(
		model,
		"Title",
		Vector3.new(42, 6.5, 0.4),
		CFrame.lookAt(Vector3.new(0, 15, z), Vector3.new(0, 15, z + 1)),
		DARK,
		Enum.Material.SmoothPlastic
	)
	Build.label(title, "THE FOUNDRY", Enum.Font.Michroma, AMBER, 24)
	local subtitle = Build.decor(
		model,
		"Subtitle",
		Vector3.new(22, 1.6, 0.4),
		CFrame.lookAt(Vector3.new(0, 19.4, z), Vector3.new(0, 19.4, z + 1)),
		DARK,
		Enum.Material.SmoothPlastic
	)
	Build.label(subtitle, "ROBOT FIGHT CLUB", Enum.Font.GothamBold, TEAL, 30)
end

-- Under each ring's screen, a winch over each fighter's mark. The clients hang the robots from them while the ring stands
-- idle and drop them onto the canvas when a match starts (see Hoist, and Cranes on the client).
local function buildWinches(model: Model)
	for _, spec in LAYOUT.Rings do
		for _, side in { -1, 1 } do
			local at = spec.center + Vector3.new(side * FightConfig.StartHalfDistance, spec.hookY - 0.35, 0)
			Build.decor(model, "Winch", Vector3.new(1.3, 0.7, 1.3), CFrame.new(at), GIRDER, Enum.Material.Metal)
			Build.decor(
				model,
				"WinchLamp",
				Vector3.new(0.5, 0.08, 0.5),
				CFrame.new(at - Vector3.new(0, 0.38, 0)),
				AMBER,
				Enum.Material.Neon
			)
		end
	end
end

-- The champion's pedestal north of the main ring, with the plaque the clients write the title on and a warm light from
-- above. The clients stand the champion's robot on it, cast in gold (see Statue on the client).
local function buildStatue(model: Model)
	local stand = LAYOUT.Statue
	local pedestal = LAYOUT.StatuePedestal
	local x, z = stand.X, stand.Z
	Build.solid(
		model,
		"StatuePedestal",
		Vector3.new(pedestal.height, pedestal.radius * 2, pedestal.radius * 2),
		CFrame.new(x, pedestal.height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(44, 46, 56),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	local gold = Color3.fromRGB(255, 196, 92)
	Build.disc(
		model,
		"StatueTrim",
		pedestal.radius + 0.12,
		pedestal.height - 0.25,
		0.22,
		gold,
		Enum.Material.Neon,
		x,
		z
	)
	local front = stand.LookVector
	local plaque = Build.decor(
		model,
		"StatuePlaque",
		Vector3.new(5.2, 1.0, 0.12),
		CFrame.lookAt(
			Vector3.new(x, 0.62, z) + front * (pedestal.radius + 0.12),
			Vector3.new(x, 0.62, z) + front * (pedestal.radius + 1)
		),
		DARK,
		Enum.Material.SmoothPlastic
	)
	plaque.Transparency = 0.05
	local lamp = lightPoint(model, Vector3.new(x, 22, z + 6))
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 32
	spot.Range = 30
	spot.Brightness = 3.2
	spot.Color = gold
	spot.Shadows = false
	spot.Parent = lamp
	lamp.CFrame = CFrame.lookAt(lamp.Position, Vector3.new(x, 5, z))
end

-- The two leaderboards on the north wall: a dark panel the clients draw the board on (named after the board), framed in
-- teal, with a lamp over it.
local function buildBoards(model: Model)
	local size = LAYOUT.BoardSize
	for _, board in LAYOUT.Boards do
		local at = board.center
		local facing = CFrame.lookAt(at, at + Vector3.zAxis)
		Build.decor(
			model,
			"BoardBack",
			Vector3.new(size.X + 0.8, size.Y + 0.8, 0.3),
			facing * CFrame.new(0, 0, 0.12),
			Color3.fromRGB(24, 27, 36),
			Enum.Material.Metal
		)
		Build.decor(
			model,
			board.name,
			Vector3.new(size.X, size.Y, 0.1),
			facing,
			Color3.fromRGB(8, 10, 16),
			Enum.Material.SmoothPlastic
		)
		for _, edge in { size.Y / 2 + 0.3, -size.Y / 2 - 0.3 } do
			local rim = Build.decor(
				model,
				"BoardRim",
				Vector3.new(size.X + 0.8, 0.12, 0.12),
				facing * CFrame.new(0, edge, -0.05),
				TEAL,
				Enum.Material.Neon
			)
			rim.Transparency = 0.2
		end
		light(lightPoint(model, at + Vector3.new(0, size.Y / 2 + 2, 2.5)), "PointLight", 12, 0.8, LAMP)
	end
end

-- Painted dashes on the floor from the bottom of each stair to the pads, to the garage bays and between the pits. Paint,
-- not light: a trail of glowing dashes across the floor pulls the eye at every step.
local function buildWalkways(model: Model)
	local routes = {
		{ Vector2.new(-33, 42), Vector2.new(-46, 32), Vector2.new(-54, 18) },
		{ Vector2.new(-33, 42), Vector2.new(-14, 34.5) },
		{ Vector2.new(33, 42), Vector2.new(14, 34.5) },
		{ Vector2.new(33, 42), Vector2.new(41, 36), Vector2.new(41, 4), Vector2.new(58, 4) },
	}
	for _, route in routes do
		for index = 1, #route - 1 do
			local from, to = route[index], route[index + 1]
			local length = (to - from).Magnitude
			local count = math.floor(length / 2.6)
			for dash = 1, count do
				local at = from:Lerp(to, (dash - 0.5) / count)
				local part = Build.decor(
					model,
					"Walkway",
					Vector3.new(1.5, 0.04, 0.32),
					CFrame.lookAt(Vector3.new(at.X, 0.03, at.Y), Vector3.new(to.X, 0.03, to.Y))
						* CFrame.Angles(0, math.rad(90), 0),
					TEAL_SOFT,
					Enum.Material.SmoothPlastic
				)
				part.Transparency = 0.1
			end
		end
	end
end

-- Builds the hall, the ring island in its middle, the pits beside it and the stations, under Workspace.
function Foundry.build(): Hall
	local model = Instance.new("Model")
	model.Name = "Foundry"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildShell(model)
	buildChannels(model)
	local spawn = buildDeck(model)
	buildRail(model)
	buildBooths(model)
	buildJumbotron(model)
	buildSign(model)
	buildWalkways(model)
	buildWinches(model)
	buildStatue(model)
	buildBoards(model)
	local bays = FoundryStations.buildBays(model)
	local pads = FoundryStations.buildPads(model)
	Arena.build(model)
	for _, spec in LAYOUT.Rings do
		if spec.pit then
			Arena.buildPit(model, spec)
		end
	end
	model.Parent = Workspace
	return { model = model, bays = bays, pads = pads, spawn = spawn }
end

return Foundry
