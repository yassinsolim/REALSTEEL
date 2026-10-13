--!strict

-- Builds the hall (see Foundry, which puts the main ring's island in its middle and the pits beside it) and every ring's
-- simulation cores: two fighters and a match core each, under Workspace.Rings in the order of FoundryLayout.Rings.
-- Everything is created from code so a clean build needs no Studio-authored content. The clients draw the robots from the
-- rig data and pose them from simulation state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FightSim = require(ReplicatedStorage.Shared.FightSim)
local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Foundry = require(script.Parent.Foundry)

-- One ring's fight. `cores` and `models` are in seat order.
export type RingWorld = {
	index: number,
	spec: FoundryLayout.RingSpec,
	model: Model,
	cores: { Part },
	models: { Model },
	match: Part,
}

export type World = {
	rings: { RingWorld },
	hall: Foundry.Hall,
}

local WorldBuilder = {}

local FIGHTER_COLORS = {
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(255, 84, 70),
}

local function newPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildFighter(slot: number, center: Vector3, parent: Instance): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "Fighter" .. slot
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerUserId", 0)

	local core = newPart(
		"Core",
		Vector3.new(1, 1, 1),
		CFrame.new(center + Vector3.new(0, 8, 0)),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		model
	)
	core.Transparency = 1

	-- The client builds the robot itself from the rig data; the server only owns the simulation core and the hitbox
	-- overlay, and tells clients which team color to use.
	local accent = FIGHTER_COLORS[slot]
	model:SetAttribute("Accent", accent)

	-- Debug overlay of the attack hitbox, shown by the client during active frames in training.
	local hitViz = newPart(
		"HitViz",
		Vector3.new(0.2, 1, 1),
		CFrame.new(center + Vector3.new(0, 12, 0)),
		Color3.fromRGB(255, 40, 40),
		Enum.Material.Neon,
		model
	)
	hitViz.Shape = Enum.PartType.Cylinder
	hitViz.Transparency = 1

	model.PrimaryPart = core
	model.Parent = parent
	return model, core
end

local function buildRing(index: number, spec: FoundryLayout.RingSpec, parent: Instance): RingWorld
	-- A persistent model, so a ring's cores are on every client however far across the hall the player stands.
	local model = Instance.new("Model")
	model.Name = spec.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Index", index)
	model:SetAttribute("Center", spec.center)

	local models: { Model } = {}
	local cores: { Part } = {}
	local fighterA = FightSim.newFighter(0, 0)
	local fighterB = FightSim.newFighter(0, 0)
	FightSim.reset(fighterA, fighterB)
	for slot = 1, 2 do
		local fighter, core = buildFighter(slot, spec.center, model)
		core:SetAttribute("AiMode", 1)
		core:SetAttribute("InMoveX", 0)
		core:SetAttribute("InMoveZ", 0)
		core:SetAttribute("InJab", false)
		core:SetAttribute("InStraight", false)
		core:SetAttribute("InLeftKick", false)
		core:SetAttribute("InRightKick", false)
		core:SetAttribute("InGuard", false)
		core:SetAttribute("InDash", false)
		core:SetAttribute("InGrab", false)
		Simulation.writeState(core, if slot == 1 then fighterA else fighterB)
		models[slot] = fighter
		cores[slot] = core
	end

	-- Carries the ring's match-wide commands. Predicted like the fighters so every peer applies them on the same frame.
	local match = newPart(
		"Match",
		Vector3.new(1, 1, 1),
		CFrame.new(spec.center + Vector3.new(0, 9, 0)),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		model
	)
	match.Transparency = 1
	-- Commands from the server: the menu is up, training rules, the bot's level (0 for none), the dummy's behavior.
	match:SetAttribute("Lobby", true)
	match:SetAttribute("TrainingMode", true)
	match:SetAttribute("BotLevel", 0)
	match:SetAttribute("DummyMode", 0)
	match:SetAttribute("ResetToken", 0)
	match:SetAttribute("AppliedReset", 0)
	-- Round and match state, written by the simulation (see MatchFlow).
	Simulation.writeMatch(match, MatchFlow.new())
	model.PrimaryPart = match
	model.Parent = parent

	return { index = index, spec = spec, model = model, cores = cores, models = models, match = match }
end

function WorldBuilder.build(): World
	local hall = Foundry.build()

	local folder = Instance.new("Folder")
	folder.Name = "Rings"
	local rings: { RingWorld } = {}
	for index, spec in FoundryLayout.Rings do
		rings[index] = buildRing(index, spec, folder)
	end
	folder.Parent = Workspace

	return { rings = rings, hall = hall }
end

return WorldBuilder
