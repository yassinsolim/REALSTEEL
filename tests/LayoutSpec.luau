--!strict

-- Checks for where things stand in THE FOUNDRY (FoundryLayout): every ring's fight camera has room, the rings and their
-- booths do not run into each other or into the hall, and the order the server and the clients number the rings by
-- keeps the main ring first. Pure numbers; runs in Studio's command bar, or without Studio through scripts/run-specs.ps1
-- (which stands in a small Vector3 and CFrame for it):
--   local passed, failures = require(game.ReplicatedStorage.Tests.LayoutSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)

-- Half the size of a booth's platform across and toward its ring (see Foundry's buildBooth).
local BOOTH_HALF_WIDE = 3.3
local BOOTH_HALF_DEEP = 2.3
-- Room the camera keeps from anything solid, and the least walkway between two rings' rails.
local CAMERA_ROOM = 0.5
local WALKWAY = 4
-- The molten channel's strip and curbs reach this far either side of its middle line.
local CHANNEL_HALF = 1.4

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

	local function flat(vector: Vector3): Vector3
		return Vector3.new(vector.X, 0, vector.Z)
	end

	local function railOf(spec: FoundryLayout.RingSpec): number
		return if spec.pit then FoundryLayout.PitRailRadius else FoundryLayout.RailRadius
	end

	local function round(value: number): number
		return math.floor(value * 100 + 0.5) / 100
	end

	local rings = FoundryLayout.Rings
	local reach = FightConfig.CameraMaxRadius + CAMERA_ROOM

	-- The numbering: the clients take the first ring for the main one and every other for a pit.
	check("there are rings", #rings >= 1, #rings)
	check("the main ring comes first", rings[1] ~= nil and not rings[1].pit)
	local names: { [string]: boolean } = {}
	local unique = true
	for index, spec in rings do
		if index > 1 then
			check(`{spec.name} is a pit`, spec.pit)
			check(`{spec.name} hosts no 1v1s`, not spec.versus)
		end
		if names[spec.name] then
			unique = false
		end
		names[spec.name] = true
		check(`{spec.name} has a label`, spec.label ~= "")
		check(`{spec.name} hosts something`, spec.versus or spec.solo)
		check(`{spec.name} has two booths`, #spec.booths == 2, #spec.booths)
	end
	check("ring names are unique", unique)
	check("the main ring hosts 1v1s and the exhibitions", rings[1].versus and rings[1].exhibitions)

	for _, spec in rings do
		local center = flat(spec.center)
		check(`{spec.name} stands on the hall floor`, spec.center.Y == 0, spec.center.Y)

		-- The fight camera may go anywhere within its reach of the ring's middle, so walls and columns stay out of it.
		check(
			`{spec.name}'s camera stays inside the walls`,
			center.X - reach > FoundryLayout.West
				and center.X + reach < FoundryLayout.East
				and center.Z - reach > FoundryLayout.North
				and center.Z + reach < FoundryLayout.South
		)
		local nearest = math.huge
		for _, column in FoundryLayout.columns() do
			nearest = math.min(nearest, (flat(column) - center).Magnitude - FoundryLayout.ColumnWidth * 0.71)
		end
		check(`{spec.name}'s camera misses the columns`, nearest > reach, round(nearest))

		-- Booths stand outside the ring's rail, inside the hall, facing the ring.
		for slot, stand in spec.booths do
			local at = flat(stand.Position)
			local away = (at - center).Magnitude
			check(
				`{spec.name} booth {slot} is outside the rail`,
				away - BOOTH_HALF_DEEP >= railOf(spec),
				round(away - BOOTH_HALF_DEEP)
			)
			-- CFrames keep their position in single precision, so the height is only near the layout's number.
			check(
				`{spec.name} booth {slot} stands at booth height`,
				math.abs(stand.Position.Y - FoundryLayout.BoothFloor) < 1e-4,
				stand.Position.Y
			)
			local toward = (center - at).Unit
			check(
				`{spec.name} booth {slot} faces the ring`,
				flat(stand.LookVector).Unit:Dot(toward) > 0.999,
				round(flat(stand.LookVector).Unit:Dot(toward))
			)
			-- The platform's reach along X and Z, from which way it faces.
			local look = flat(stand.LookVector).Unit
			local reachX = math.abs(look.X) * BOOTH_HALF_DEEP + math.abs(look.Z) * BOOTH_HALF_WIDE
			local reachZ = math.abs(look.Z) * BOOTH_HALF_DEEP + math.abs(look.X) * BOOTH_HALF_WIDE
			check(
				`{spec.name} booth {slot} is inside the hall`,
				at.X - reachX > FoundryLayout.West
					and at.X + reachX < FoundryLayout.East
					and at.Z - reachZ > FoundryLayout.North
					and at.Z + reachZ < FoundryLayout.South
			)
			local half = FoundryLayout.ColumnWidth / 2
			local clear = true
			for _, column in FoundryLayout.columns() do
				if math.abs(column.X - at.X) < reachX + half and math.abs(column.Z - at.Z) < reachZ + half then
					clear = false
				end
			end
			check(`{spec.name} booth {slot} clears the columns`, clear)
		end

		-- A pit stands clear of the channel around the main ring's island, booths and all.
		if spec.pit then
			local inner = math.min(center.X - railOf(spec), center.X - FoundryLayout.PitBoothRadius - BOOTH_HALF_DEEP)
			check(`{spec.name} is clear of the channel`, inner > FoundryLayout.ChannelX + CHANNEL_HALF, round(inner))
		end

		-- The pads and the bays are out of the camera's way, and the spawn far from the fight.
		for _, pad in FoundryLayout.Pads do
			local away = (flat(pad.position) - center).Magnitude
			check(`{spec.name} leaves the {pad.name} pad outside its rail`, away > railOf(spec), round(away))
		end
		for index = 1, FoundryLayout.BayCount do
			local away = (flat(FoundryLayout.bay(index).Position) - center).Magnitude
			if away <= reach then
				check(`{spec.name}'s camera misses bay {index}`, false, round(away))
			end
		end
		check(`{spec.name}'s camera misses the spawn`, (flat(FoundryLayout.Spawn.Position) - center).Magnitude > reach)
	end

	-- Rings keep a walkway between their rails, and none stands in another's booths.
	for first = 1, #rings do
		for second = first + 1, #rings do
			local a, b = rings[first], rings[second]
			local between = (flat(a.center) - flat(b.center)).Magnitude - railOf(a) - railOf(b)
			check(`{a.name} and {b.name} leave a walkway between them`, between >= WALKWAY, round(between))
			for _, spec in { a, b } do
				local other = if spec == a then b else a
				for slot, stand in spec.booths do
					local away = (flat(stand.Position) - flat(other.center)).Magnitude
					check(
						`{spec.name} booth {slot} is outside {other.name}'s rail`,
						away - BOOTH_HALF_WIDE - BOOTH_HALF_DEEP > railOf(other),
						round(away)
					)
				end
			end
		end
	end

	-- The champion's statue: out of every fight camera's way, clear of the channel and inside the hall.
	local statue = flat(FoundryLayout.Statue.Position)
	local pedestal = FoundryLayout.StatuePedestal.radius
	for _, spec in rings do
		local away = (statue - flat(spec.center)).Magnitude - pedestal
		check(`the statue is out of {spec.name}'s camera`, away > reach, round(away))
	end
	check(
		"the statue is clear of the channel",
		statue.Z + pedestal < FoundryLayout.ChannelNorth - CHANNEL_HALF
			or statue.Z - pedestal > FoundryLayout.ChannelSouth + CHANNEL_HALF
	)
	check("the statue is inside the hall", statue.Z - pedestal > FoundryLayout.North)
	check("the statue faces the main ring", flat(FoundryLayout.Statue.LookVector).Unit:Dot(-statue.Unit) > 0.999)

	-- The leaderboards hang on the north wall between its columns, beside the hall's name (42 studs wide, centered).
	for _, board in FoundryLayout.Boards do
		local half = FoundryLayout.BoardSize.X / 2 + 0.4
		check(`{board.name} hangs on the north wall`, math.abs(board.center.Z - FoundryLayout.North) < 1)
		local clear = true
		for _, column in FoundryLayout.columns() do
			if math.abs(column.Z - FoundryLayout.North) < 3 then
				if math.abs(column.X - board.center.X) < half + FoundryLayout.ColumnWidth / 2 then
					clear = false
				end
			end
		end
		check(`{board.name} sits between the columns`, clear)
		check(`{board.name} clears the hall's name`, math.abs(board.center.X) - half > 21)
	end

	-- Every ring's winches leave room to hang the tallest build (scale 1.1, about 8.8 studs) above its mark.
	for _, spec in rings do
		local room = spec.hookY - 0.7 - 1 - FightConfig.GroundY - 8 * 1.1
		check(`{spec.name}'s winches leave room for a drop`, room > 2, round(room))
	end

	return passed, failures
end
