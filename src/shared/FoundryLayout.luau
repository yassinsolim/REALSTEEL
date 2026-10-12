--!strict

-- Where everything in THE FOUNDRY is, shared by the server that builds the hall (Foundry) and the clients that draw on it.
-- Studs. The ring's center is the origin, +X is east and +Z is south, toward the spawn catwalk; the hall floor is at 0.

local FoundryLayout = {}

-- Spectators stay outside this circle around the ring, which keeps the fight camera (FightConfig.CameraMaxRadius) clear.
FoundryLayout.RailRadius = 26.5

-- The inside faces of the walls, and the roof. The east side of the hall holds the practice pits.
FoundryLayout.West = -70
FoundryLayout.East = 96
FoundryLayout.North = -52
FoundryLayout.South = 70
FoundryLayout.Height = 32

-- The columns along the east and north walls (the west side's are the bay dividers): where each stands on the floor, and
-- how wide it is.
FoundryLayout.ColumnWidth = 1.8
function FoundryLayout.columns(): { Vector3 }
	local list: { Vector3 } = {}
	for z = FoundryLayout.North + 12, FoundryLayout.South - 8, 22 do
		table.insert(list, Vector3.new(FoundryLayout.East - 1.2, 0, z))
	end
	for _, x in { -44, -28, 28, 52, 76 } do
		table.insert(list, Vector3.new(x, 0, FoundryLayout.North + 1.2))
	end
	return list
end

-- A loop of molten channel around the ring island: its east and west sides, and its north and south ends.
FoundryLayout.ChannelX = 36
FoundryLayout.ChannelNorth = -36
FoundryLayout.ChannelSouth = 38

-- Where a seated player's character stands while their robot fights, facing the ring: west for slot 1, east for slot 2.
FoundryLayout.BoothFloor = 1.2
FoundryLayout.Booths = {
	CFrame.lookAt(Vector3.new(-31.4, 1.2, 0), Vector3.new(0, 1.2, 0)),
	CFrame.lookAt(Vector3.new(31.4, 1.2, 0), Vector3.new(0, 1.2, 0)),
}

-- The practice pits: the same canvas as the main ring in a smaller enclosure. Spectators stand at a rail just outside
-- the ropes, inside the fight camera's reach (FightConfig.CameraMaxRadius), so the camera fades whoever it comes close
-- to; walls and columns stay out of that reach.
FoundryLayout.PitRailRadius = 19.5
FoundryLayout.PitBoothRadius = 22.5

local function pitBooths(center: Vector3): { CFrame }
	local floor = Vector3.new(0, FoundryLayout.BoothFloor, 0)
	local aim = center + floor
	return {
		CFrame.lookAt(aim - Vector3.xAxis * FoundryLayout.PitBoothRadius, aim),
		CFrame.lookAt(aim + Vector3.xAxis * FoundryLayout.PitBoothRadius, aim),
	}
end

-- The four-sided screen hung over the main ring, and the smaller ones over the pits (their middle's height above the
-- ring, and their size).
FoundryLayout.Jumbotron = { center = Vector3.new(0, 19.5, 0), width = 12, height = 6 }
FoundryLayout.PitScreen = { y = 19.5, width = 7.2, height = 3.6 }

-- The rings, numbered the same way by the server and every client. The main ring is the centerpiece, where 1v1s are
-- fought and the bots put on exhibitions; the pits take bot matches and training, so practice never waits on a fight in
-- the main ring. Every ring's fight area is the same (FightConfig.RingRadius), so a fight plays the same wherever it is.
export type RingSpec = {
	-- Its model under Workspace.Rings, and for a pit, its model in the hall.
	name: string,
	-- What the hall calls it.
	label: string,
	-- The middle of its canvas on the hall floor. The simulation's coordinates are relative to it.
	center: Vector3,
	pit: boolean,
	-- Where each seat's player stands while their robot fights.
	booths: { CFrame },
	-- What it hosts (see RingQueue): 1v1s, bot matches and training, and its rank among the rings that host practice.
	versus: boolean,
	solo: boolean,
	rank: number,
	-- Whether the bots fight in it while nobody wants it.
	exhibitions: boolean,
	-- The height of the winches under the ring's screen, which lower the robots onto their marks when a match starts.
	hookY: number,
}

local PIT_ONE = Vector3.new(68, 0, -22)
local PIT_TWO = Vector3.new(68, 0, 30)
local MAIN_HOOK_Y = FoundryLayout.Jumbotron.center.Y - FoundryLayout.Jumbotron.height / 2
local PIT_HOOK_Y = FoundryLayout.PitScreen.y - FoundryLayout.PitScreen.height / 2
FoundryLayout.Rings = {
	{
		name = "Main",
		label = "MAIN RING",
		center = Vector3.zero,
		pit = false,
		booths = FoundryLayout.Booths,
		versus = true,
		solo = true,
		rank = 2,
		exhibitions = true,
		hookY = MAIN_HOOK_Y,
	},
	{
		name = "Pit1",
		label = "PIT 1",
		center = PIT_ONE,
		pit = true,
		booths = pitBooths(PIT_ONE),
		versus = false,
		solo = true,
		rank = 1,
		exhibitions = false,
		hookY = PIT_HOOK_Y,
	},
	{
		name = "Pit2",
		label = "PIT 2",
		center = PIT_TWO,
		pit = true,
		booths = pitBooths(PIT_TWO),
		versus = false,
		solo = true,
		rank = 1,
		exhibitions = false,
		hookY = PIT_HOOK_Y,
	},
} :: { RingSpec }

-- The champion's statue: where the robot stands on its pedestal north of the main ring, facing the hall, and the
-- pedestal's size.
FoundryLayout.Statue = CFrame.lookAt(Vector3.new(0, 1.6, -44), Vector3.new(0, 1.6, 0))
FoundryLayout.StatuePedestal = { radius = 4.2, height = 1.6 }

-- The leaderboards on the north wall, either side of the hall's name, facing the hall. The clients draw them.
export type Board = { name: string, title: string, center: Vector3 }
FoundryLayout.BoardSize = Vector2.new(13, 10)
FoundryLayout.Boards = {
	{ name = "BoardVersus", title = "1V1 WINS", center = Vector3.new(-36, 12.5, -51.65) },
	{ name = "BoardBots", title = "HARD BOT WINS", center = Vector3.new(40, 12.5, -51.65) },
} :: { Board }

-- The pads in front of the ring. Each opens the PLAY card at its own section.
export type Pad = { name: string, label: string, position: Vector3 }
FoundryLayout.Pads = {
	{ name = "Bot", label = "FIGHT A BOT", position = Vector3.new(-11, 0, 32) },
	{ name = "Versus", label = "1V1", position = Vector3.new(0, 0, 32) },
	{ name = "Training", label = "TRAINING", position = Vector3.new(11, 0, 32) },
} :: { Pad }

-- The garage bays along the west wall. Every player in the server gets one, and their robot stands on its lift facing
-- east, into the hall.
FoundryLayout.BayCount = 8
FoundryLayout.BayX = -62
FoundryLayout.BayFirstZ = -38.5
FoundryLayout.BaySpacing = 11
FoundryLayout.LiftTop = 0.8

-- Where bay `index`'s robot stands and which way it faces.
function FoundryLayout.bay(index: number): CFrame
	local z = FoundryLayout.BayFirstZ + (index - 1) * FoundryLayout.BaySpacing
	local position = Vector3.new(FoundryLayout.BayX, FoundryLayout.LiftTop, z)
	return CFrame.lookAt(position, position + Vector3.xAxis)
end

-- The catwalk along the south wall that players spawn on, looking over the hall.
FoundryLayout.DeckTop = 10
FoundryLayout.DeckNorth = 58
FoundryLayout.Spawn = CFrame.lookAt(Vector3.new(0, 10, 63), Vector3.new(0, 10, 0))

return FoundryLayout
