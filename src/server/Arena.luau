--!strict

-- The rings. The main ring's island in the middle of the hall (see Foundry): a raised canvas with its posts and ropes,
-- the floor around it out to the spectators' rail with its markings, a low barricade, and a ring of girders overhead
-- with eight spot fixtures. And the practice pits beside it: the same canvas in a smaller enclosure (buildPit). The
-- ring's size and ground height come from FightConfig; the rest is dressing. The lights on the fighters in the main ring
-- belong to the client (StageLights).
--
-- What Future lighting taught here:
--   * Near-black surfaces never show, so whatever must be seen is a mid-dark navy or a dark Neon color.
--   * Large bright Neon surfaces wash out the fighters. The backdrop stays dim and only thin lines are bright.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local Build = require(script.Parent.Build)

local Arena = {}

-- The fighters own blue and red. The venue stays teal and amber on navy so the robots stand out from it.
local TEAM_BLUE = Color3.fromRGB(70, 140, 255)
local TEAM_RED = Color3.fromRGB(255, 84, 70)
local TEAL = Color3.fromRGB(64, 214, 232)
local AMBER = Color3.fromRGB(255, 178, 66)
local ICE = Color3.fromRGB(225, 236, 255)
local STEEL = Color3.fromRGB(46, 51, 66)
local DARK = Color3.fromRGB(14, 16, 22)

-- The island's floor sits just above the hall's, so the two never fight over the same surface.
local ISLAND_TOP = 0.03
local BARRICADE_RADIUS = 23
local TRUSS_RADIUS = 21
local TRUSS_HEIGHT = 21
-- A pit's screen hangs over its canvas (FoundryLayout.PitScreen) with the work light under it, both high enough to stay
-- out of the fight camera's view.
local PIT_SCREEN = FoundryLayout.PitScreen
local PIT_LAMP_Y = PIT_SCREEN.y - PIT_SCREEN.height / 2 - 0.3

local ROPE_HEIGHTS = { 1.5, 2.7, 3.9 }
local ROPE_SEGMENTS = 36
local POST_COUNT = 8

-- The floor around the main ring out to the spectators' rail, with a teal line and amber runway lights.
local function buildIslandFloor(model: Model)
	local floorColor = Color3.fromRGB(28, 32, 48)
	Build.disc(model, "Floor", FoundryLayout.RailRadius, ISLAND_TOP, 0.3, floorColor, Enum.Material.SmoothPlastic)
	Build.ringLine(model, "FloorRing", 19.2, 0.3, ISLAND_TOP, TEAL, floorColor, Enum.Material.SmoothPlastic)
	-- Amber dashes laid around the ring like runway lights.
	for index = 1, 40 do
		local angle = index / 40 * math.pi * 2
		Build.decor(
			model,
			"FloorLight" .. index,
			Vector3.new(1.4, 0.06, 0.26),
			CFrame.new(Build.polar(20.9, angle, ISLAND_TOP + 0.03)) * CFrame.Angles(0, -angle, 0),
			AMBER,
			Enum.Material.Neon
		)
	end
end

-- The ring itself, around the origin: the raised canvas with its start marks, posts and ropes. Every ring in the hall is
-- the same, because the simulation's ring is.
local function buildRing(model: Model)
	local ground = FightConfig.GroundY
	local radius = FightConfig.RingRadius
	-- Skirt around the platform, then the canvas on top. The sim's ground height is the canvas surface.
	Build.disc(
		model,
		"Apron",
		radius + 1.6,
		ground - 0.1,
		ground + 0.4,
		Color3.fromRGB(34, 38, 50),
		Enum.Material.Metal
	)
	-- Opaque, like every glow under a cover (see Build.ringLine).
	Build.disc(model, "ApronTrim", radius + 1.65, ground - 0.35, 0.18, AMBER, Enum.Material.Neon)
	local canvasColor = Color3.fromRGB(50, 57, 84)
	Build.disc(model, "Canvas", radius + 0.9, ground, 0.6, canvasColor, Enum.Material.SmoothPlastic)
	Build.ringLine(model, "CanvasEdge", radius - 0.6, 0.18, ground, TEAL, canvasColor, Enum.Material.SmoothPlastic)
	Build.ringLine(model, "CanvasCenter", 3.4, 0.14, ground, ICE, canvasColor, Enum.Material.SmoothPlastic)

	-- Start marks, one per fighter, in their team colors.
	for index, color in { TEAM_BLUE, TEAM_RED } do
		local x = if index == 1 then -FightConfig.StartHalfDistance else FightConfig.StartHalfDistance
		local mark = Build.decor(
			model,
			"StartMark" .. index,
			Vector3.new(0.05, 2.4, 2.4),
			CFrame.new(x, ground + 0.03, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		mark.Transparency = 0.45
	end

	-- Posts with team-colored caps, and three thin energy ropes (blue, white, red) strung between them. The ropes stay
	-- thin and a little dim: wide bright Neon lines smear into the bloom and fill the screen.
	local ropeRadius = radius + 0.4
	for index = 1, POST_COUNT do
		local angle = (index - 0.5) / POST_COUNT * math.pi * 2
		local base = Build.polar(ropeRadius, angle, ground)
		local top = Build.polar(ropeRadius, angle, ground + 4.6)
		local post = Build.vbar(model, "Post" .. index, base, 4.6, 0.7, STEEL, Enum.Material.Metal)
		CollectionService:AddTag(post, FightConfig.RingFadeTag)
		local cap = Build.decor(
			model,
			"PostCap" .. index,
			Vector3.new(0.95, 0.95, 0.95),
			CFrame.new(top),
			if index % 2 == 0 then TEAM_RED else TEAM_BLUE,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		CollectionService:AddTag(cap, FightConfig.RingFadeTag)
	end
	local ropeColors = { Color3.fromRGB(40, 90, 190), Color3.fromRGB(150, 160, 175), Color3.fromRGB(190, 55, 50) }
	for level, height in ROPE_HEIGHTS do
		for index = 1, ROPE_SEGMENTS do
			local from = Build.polar(ropeRadius, (index - 1) / ROPE_SEGMENTS * math.pi * 2, ground + height)
			local to = Build.polar(ropeRadius, index / ROPE_SEGMENTS * math.pi * 2, ground + height)
			local rope = Build.bar(model, `Rope{level}_{index}`, from, to, 0.15, ropeColors[level], Enum.Material.Neon)
			CollectionService:AddTag(rope, FightConfig.RingFadeTag)
		end
	end
end

-- A low wall around the ring, inside the spectators' rail.
local function buildBarricade(model: Model)
	local blocks = 40
	local arc = 2 * math.pi * BARRICADE_RADIUS / blocks
	for index = 1, blocks do
		local angle = index / blocks * math.pi * 2
		Build.decor(
			model,
			"Barricade" .. index,
			Vector3.new(arc * 1.05, 1.7, 0.7),
			Build.facingCenter(BARRICADE_RADIUS, angle, 0.85),
			STEEL,
			Enum.Material.Metal
		)
	end
end

-- A faint shaft of light from a fixture down toward the canvas that fades out before it gets there. The wide edge is
-- soft because the shaft is nearly transparent; it stands in for light in haze, which the engine does not draw.
local function addBeam(source: Part, target: Part, color: Color3)
	local from = Instance.new("Attachment")
	from.Parent = source
	local to = Instance.new("Attachment")
	to.Parent = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 1
	beam.Width1 = 3.6
	beam.Transparency = NumberSequence.new(0.95, 1)
	beam.Parent = source
end

-- A ring of girders high over the ring with eight spot fixtures hanging from it. They are dressing, with a beam each;
-- the light that falls on the fighters comes from StageLights.
local function buildTruss(model: Model)
	local girderColor = Color3.fromRGB(40, 44, 58)
	local segments = 24
	for index = 1, segments do
		Build.bar(
			model,
			"Girder" .. index,
			Build.polar(TRUSS_RADIUS, (index - 1) / segments * math.pi * 2, TRUSS_HEIGHT),
			Build.polar(TRUSS_RADIUS, index / segments * math.pi * 2, TRUSS_HEIGHT),
			0.7,
			girderColor,
			Enum.Material.Metal
		)
	end

	local ground = FightConfig.GroundY
	local random = Random.new(3)
	local fixtureColors = { ICE, TEAL }
	for index = 1, 8 do
		local angle = (index - 0.5) / 8 * math.pi * 2
		local color = fixtureColors[(index - 1) % #fixtureColors + 1]
		local spot = Build.polar(random:NextNumber(0.5, 3.5), random:NextNumber(0, math.pi * 2), ground + 0.1)
		local at = Build.polar(TRUSS_RADIUS, angle, TRUSS_HEIGHT - 1.1)
		local frame = CFrame.lookAt(at, spot)
		Build.decor(model, "Fixture" .. index, Vector3.new(1.5, 1.5, 2), frame, girderColor, Enum.Material.Metal)
		-- A cylinder runs along X, so the lens is turned to face along the fixture.
		local lens = Build.decor(
			model,
			"FixtureLens" .. index,
			Vector3.new(0.12, 1.05, 1.05),
			frame * CFrame.new(0, 0, -1.02) * CFrame.Angles(0, math.rad(90), 0),
			color,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		local target = Build.decor(
			model,
			"BeamTarget" .. index,
			Vector3.one * 0.2,
			CFrame.new(spot),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic
		)
		target.Transparency = 1
		addBeam(lens, target, color)
	end
end

-- Builds the ring island under `parent`.
function Arena.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Arena"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildIslandFloor(model)
	buildRing(model)
	buildBarricade(model)
	buildTruss(model)
	model.Parent = parent
	return model
end

-- A practice pit: the same ring on a plain floor, a rail just outside the ropes with an invisible wall behind it, a
-- light overhead and a screen of its own (faces Face1 to Face4 in the pit's model, see Jumbotron on the client). Built
-- around the origin, then moved to the pit's center. The rail sits inside the fight camera's reach, so it fades near
-- the camera like the ropes.
function Arena.buildPit(parent: Instance, spec: FoundryLayout.RingSpec): Model
	local model = Instance.new("Model")
	model.Name = spec.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local radius = FoundryLayout.PitRailRadius

	local floorColor = Color3.fromRGB(30, 33, 44)
	Build.disc(model, "Floor", radius + 1.5, ISLAND_TOP, 0.3, floorColor, Enum.Material.DiamondPlate)
	Build.ringLine(model, "FloorRing", radius + 0.9, 0.24, ISLAND_TOP, AMBER, floorColor, Enum.Material.DiamondPlate)
	for index = 1, 24 do
		local angle = index / 24 * math.pi * 2
		Build.decor(
			model,
			"FloorLight" .. index,
			Vector3.new(1.1, 0.06, 0.24),
			CFrame.new(Build.polar(radius - 1.2, angle, ISLAND_TOP + 0.03)) * CFrame.Angles(0, -angle, 0),
			TEAL,
			Enum.Material.Neon
		)
	end
	buildRing(model)

	local segments = 32
	for index = 1, segments do
		local a0 = (index - 1) / segments * math.pi * 2
		local a1 = index / segments * math.pi * 2
		local post = Build.vbar(model, "RailPost", Build.polar(radius, a0, 0), 3, 0.2, STEEL, Enum.Material.Metal)
		local top = Build.bar(
			model,
			"RailTop",
			Build.polar(radius, a0, 3),
			Build.polar(radius, a1, 3),
			0.22,
			STEEL,
			Enum.Material.Metal
		)
		local led = Build.bar(
			model,
			"RailLed",
			Build.polar(radius - 0.05, a0, 3.2),
			Build.polar(radius - 0.05, a1, 3.2),
			0.14,
			Color3.fromRGB(150, 96, 30),
			Enum.Material.Neon
		)
		for _, part in { post, top, led } do
			CollectionService:AddTag(part, FightConfig.RingFadeTag)
		end
	end
	local blocks = 20
	local arc = 2 * math.pi * (radius + 0.3) / blocks
	for index = 1, blocks do
		local angle = (index - 0.5) / blocks * math.pi * 2
		Build.blocker(model, "RailBlock", Vector3.new(arc * 1.08, 10, 0.6), Build.facingCenter(radius + 0.3, angle, 5))
	end

	-- A work light under the screen, over the canvas.
	local lamp = Build.decor(
		model,
		"Lamp",
		Vector3.new(2.4, 0.6, 2.4),
		CFrame.new(0, PIT_LAMP_Y, 0),
		Color3.fromRGB(40, 44, 58),
		Enum.Material.Metal
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 110
	spot.Range = PIT_LAMP_Y + 10
	spot.Brightness = 2.2
	spot.Color = ICE
	spot.Shadows = false
	spot.Parent = lamp
	local glow = Build.decor(
		model,
		"LampGlow",
		Vector3.new(2, 0.08, 2),
		CFrame.new(0, PIT_LAMP_Y - 0.32, 0),
		ICE,
		Enum.Material.Neon
	)
	glow.Transparency = 0.2

	-- The screen, hung from the roof, with the scoreboard on its four faces.
	local width, height = PIT_SCREEN.width, PIT_SCREEN.height
	local center = Vector3.new(0, PIT_SCREEN.y, 0)
	Build.decor(model, "Screen", Vector3.new(width, height, width), CFrame.new(center), DARK, Enum.Material.Metal)
	for index, direction in { -Vector3.zAxis, Vector3.xAxis, Vector3.zAxis, -Vector3.xAxis } do
		local at = center + direction * (width / 2 + 0.06)
		Build.decor(
			model,
			"Face" .. index,
			Vector3.new(width - 0.4, height - 0.4, 0.1),
			CFrame.lookAt(at, at + direction),
			Color3.fromRGB(8, 10, 16),
			Enum.Material.SmoothPlastic
		)
	end
	local rim = Build.decor(
		model,
		"ScreenRim",
		Vector3.new(width + 0.16, 0.14, width + 0.16),
		CFrame.new(0, center.Y - height / 2, 0),
		AMBER,
		Enum.Material.Neon
	)
	rim.Transparency = 0.2
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, 1) } do
		local x, z = corner.X * (width / 2 - 0.6), corner.Y * (width / 2 - 0.6)
		Build.bar(
			model,
			"ScreenCable",
			Vector3.new(x, center.Y + height / 2, z),
			Vector3.new(x, FoundryLayout.Height, z),
			0.1,
			DARK,
			Enum.Material.Metal
		)
	end

	model.WorldPivot = CFrame.identity
	model:PivotTo(CFrame.new(spec.center))
	model.Parent = parent
	return model
end

return Arena
