--!strict

-- The stations of THE FOUNDRY that players use: the garage bays along the west wall, where every player's robot stands
-- on a lift under their name, and the three pads in front of the ring that open the PLAY card. The server builds them;
-- the clients draw the robots and handle the prompts (see Bays and Main on the client).

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

-- The three pads in front of the ring, each with a sign facing the spawn and a prompt the clients answer. Returns the
-- prompt parts by pad name.
function FoundryStations.buildPads(model: Model): { [string]: Part }
	local prompts: { [string]: Part } = {}
	for _, pad in FoundryLayout.Pads do
		local position = pad.position
		local color = if pad.name == "Versus" then TEAL else AMBER
		-- Opaque, like every glow under a cover (see Build.ringLine).
		Build.disc(model, "PadGlow", 2.8, 0.06, 0.04, color, Enum.Material.Neon, position.X, position.Z)
		Build.disc(
			model,
			"Pad",
			2.45,
			0.08,
			0.06,
			Color3.fromRGB(40, 44, 56),
			Enum.Material.Metal,
			position.X,
			position.Z
		)

		local signAt = position + Vector3.new(0, 0, -3.4)
		Build.vbar(model, "SignPost", signAt, 5, 0.3, STEEL, Enum.Material.Metal)
		local sign = Build.decor(
			model,
			"Sign",
			Vector3.new(5.6, 1.5, 0.3),
			facing(signAt + Vector3.new(0, 5.5, 0), Vector3.zAxis),
			DARK,
			Enum.Material.SmoothPlastic
		)
		Build.label(sign, pad.label, Enum.Font.GothamBlack, color, 40)

		local holder = Build.decor(
			model,
			"Pad" .. pad.name,
			Vector3.one,
			CFrame.new(position + Vector3.new(0, 2.5, 0)),
			color,
			Enum.Material.SmoothPlastic
		)
		holder.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Open"
		prompt.ActionText = "OPEN"
		prompt.ObjectText = pad.label
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = holder
		prompts[pad.name] = holder
	end
	return prompts
end

return FoundryStations
