--!strict

-- The stations of THE FOUNDRY that players use: the garage bays along the west wall, where every player's robot stands
-- on a lift under their name, and the pads in front of the ring that start a fight for whoever stands on them. The
-- server builds them; the clients draw the robots and the pads' state (see Bays and PadView on the client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local Build = require(script.Parent.Build)

export type Bay = {
	index: number,
	-- What the robot stands on, and the plate that carries its owner's name.
	lift: Part,
	nameplate: TextLabel,
}

local FoundryStations = {}

local TEAL = Color3.fromRGB(64, 214, 232)
local AMBER = Color3.fromRGB(255, 178, 66)
local MUTED = Color3.fromRGB(140, 154, 184)
local STEEL = Color3.fromRGB(46, 51, 66)
local PANEL = Color3.fromRGB(30, 33, 42)
local DARK = Color3.fromRGB(14, 16, 22)
local LAMP = Color3.fromRGB(255, 226, 190)
local TEAM_BLUE = Color3.fromRGB(70, 140, 255)
local TEAM_RED = Color3.fromRGB(255, 84, 70)
local FLOOR_PAINT = Color3.fromRGB(36, 38, 44)

-- The bay dividers are the hall's columns on that side.
local DIVIDER_X = -57

local function facing(position: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(position, position + direction)
end

local function buildBay(model: Model, index: number): Bay
	local stand = FoundryLayout.bay(index)
	local x, z = stand.Position.X, stand.Position.Z
	local wall = FoundryLayout.West
	local folder = Instance.new("Model")
	folder.Name = "Bay" .. index
	folder:SetAttribute("BayIndex", index)
	folder.Parent = model

	Build.solid(folder, "Back", Vector3.new(1, 17, 10.4), CFrame.new(wall + 0.5, 8.5, z), PANEL, Enum.Material.Metal)
	Build.decor(folder, "Accent", Vector3.new(0.2, 0.3, 9), CFrame.new(wall + 1.1, 15.5, z), TEAL, Enum.Material.Neon)
	local numberPlate = Build.decor(
		folder,
		"Number",
		Vector3.new(4, 2.6, 0.2),
		facing(Vector3.new(wall + 1.15, 11, z), Vector3.xAxis),
		PANEL,
		Enum.Material.SmoothPlastic
	)
	numberPlate.Transparency = 1
	Build.label(numberPlate, string.format("%02d", index), Enum.Font.Michroma, MUTED, 30)

	local lift = Build.solid(
		folder,
		"Lift",
		Vector3.new(FoundryLayout.LiftTop, 6.4, 6.4),
		CFrame.new(x, FoundryLayout.LiftTop / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(56, 62, 76),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	Build.decor(
		folder,
		"LiftRim",
		Vector3.new(0.3, 6.75, 6.75),
		CFrame.new(x, 0.15, z) * CFrame.Angles(0, 0, math.rad(90)),
		AMBER,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)

	local gantryX = x - 4.5
	for _, side in { -4.6, 4.6 } do
		Build.vbar(folder, "Post", Vector3.new(gantryX, 0, z + side), 15.5, 0.6, STEEL, Enum.Material.Metal)
	end
	Build.bar(
		folder,
		"Beam",
		Vector3.new(gantryX, 15.5, z - 4.6),
		Vector3.new(gantryX, 15.5, z + 4.6),
		0.7,
		STEEL,
		Enum.Material.Metal
	)
	Build.bar(folder, "Arm", Vector3.new(gantryX, 15.5, z), Vector3.new(x, 15.5, z), 0.5, STEEL, Enum.Material.Metal)
	for _, side in { -1.4, 1.4 } do
		Build.bar(
			folder,
			"Chain",
			Vector3.new(x, 15.4, z + side),
			Vector3.new(x, 9.6, z + side),
			0.12,
			DARK,
			Enum.Material.Metal
		)
	end

	local plate = Build.decor(
		folder,
		"Nameplate",
		Vector3.new(8.6, 1.4, 0.25),
		facing(Vector3.new(gantryX + 0.45, 16.9, z), Vector3.xAxis),
		DARK,
		Enum.Material.SmoothPlastic
	)
	local nameplate = Build.label(plate, "OPEN BAY", Enum.Font.GothamBold, MUTED, 30)

	local threshold = Build.decor(
		folder,
		"Threshold",
		Vector3.new(0.3, 0.04, 9.4),
		CFrame.new(DIVIDER_X + 0.2, 0.03, z),
		TEAL,
		Enum.Material.Neon
	)
	threshold.Transparency = 0.3

	local lamp = Build.decor(
		folder,
		"Lamp",
		Vector3.one * 0.4,
		CFrame.lookAt(Vector3.new(-52, 17, z), Vector3.new(x, 4.5, z)),
		DARK,
		Enum.Material.SmoothPlastic
	)
	lamp.Transparency = 1
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = 26
	spot.Brightness = 3
	spot.Color = LAMP
	spot.Shadows = false
	spot.Parent = lamp

	return { index = index, lift = lift, nameplate = nameplate }
end

-- The bays and the columns between them. Returns the bays in order, north to south.
function FoundryStations.buildBays(model: Model): { Bay }
	local bays: { Bay } = {}
	for index = 1, FoundryLayout.BayCount do
		bays[index] = buildBay(model, index)
	end
	for index = 0, FoundryLayout.BayCount do
		local z = FoundryLayout.BayFirstZ - FoundryLayout.BaySpacing / 2 + index * FoundryLayout.BaySpacing
		Build.solid(
			model,
			"Divider",
			Vector3.new(1.6, FoundryLayout.Height, 1.6),
			CFrame.new(DIVIDER_X, FoundryLayout.Height / 2, z),
			Color3.fromRGB(40, 44, 56),
			Enum.Material.Metal
		)
		Build.decor(
			model,
			"DividerBase",
			Vector3.new(1.9, 1.2, 1.9),
			CFrame.new(DIVIDER_X, 0.6, z),
			AMBER,
			Enum.Material.SmoothPlastic
		)
	end
	return bays
end

-- The pads in front of the ring: a glowing disc each, in its seat's team color for the two 1V1 pads, amber for the bot
-- pads and teal for training, a sign facing the spawn, and VS painted on the floor between the 1V1 pads. The server
-- reads who stands on them (see Pads) and the clients draw their state. Returns each pad's top by name.
function FoundryStations.buildPads(model: Model): { [string]: Part }
	local tops: { [string]: Part } = {}
	local versus: { Vector3 } = {}
	for _, pad in FoundryLayout.Pads do
		local position = pad.position
		local color = if pad.kind == "versus"
			then (if pad.seat == 1 then TEAM_BLUE else TEAM_RED)
			elseif pad.kind == "bot" then AMBER
			else TEAL
		local radius = FoundryLayout.PadRadius
		-- Opaque, like every glow under a cover (see Build.ringLine).
		Build.disc(
			model,
			"PadGlow" .. pad.name,
			radius + 0.35,
			0.06,
			0.04,
			color,
			Enum.Material.Neon,
			position.X,
			position.Z
		)
		local top = Build.disc(
			model,
			"PadTop" .. pad.name,
			radius,
			0.08,
			0.06,
			Color3.fromRGB(40, 44, 56),
			Enum.Material.Metal,
			position.X,
			position.Z
		)
		tops[pad.name] = top

		if pad.kind == "versus" then
			table.insert(versus, position)
		else
			local signAt = position + Vector3.new(0, 0, -3.4)
			Build.vbar(model, "SignPost", signAt, 5, 0.3, STEEL, Enum.Material.Metal)
			local sign = Build.decor(
				model,
				"Sign" .. pad.name,
				Vector3.new(5.6, 1.5, 0.3),
				facing(signAt + Vector3.new(0, 5.5, 0), Vector3.zAxis),
				DARK,
				Enum.Material.SmoothPlastic
			)
			Build.label(
				sign,
				if pad.kind == "bot" then `BOT · {pad.label}` else pad.label,
				Enum.Font.GothamBlack,
				color,
				40
			)
		end
	end

	-- The 1V1 pads share one sign between them, and VS on the floor.
	if #versus == 2 then
		local middle = (versus[1] + versus[2]) / 2
		local signAt = middle + Vector3.new(0, 0, -3.4)
		for _, side in { -2.6, 2.6 } do
			Build.vbar(model, "SignPost", signAt + Vector3.new(side, 0, 0), 5.2, 0.3, STEEL, Enum.Material.Metal)
		end
		local sign = Build.decor(
			model,
			"SignVersus",
			Vector3.new(6.8, 1.8, 0.3),
			facing(signAt + Vector3.new(0, 5.8, 0), Vector3.zAxis),
			DARK,
			Enum.Material.SmoothPlastic
		)
		Build.label(sign, "1V1", Enum.Font.GothamBlack, Color3.new(1, 1, 1), 40)
		local mark = Build.decor(
			model,
			"VersusMark",
			Vector3.new(2.6, 0.02, 1.6),
			CFrame.new(middle.X, 0.02, middle.Z),
			FLOOR_PAINT,
			Enum.Material.SmoothPlastic
		)
		mark.Transparency = 1
		Build.label(mark, "VS", Enum.Font.GothamBlack, AMBER, 40, Enum.NormalId.Top)
	end
	return tops
end

return FoundryStations
