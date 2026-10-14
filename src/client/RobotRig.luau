--!strict

-- Client-only: builds a robot's anchored parts (the uploaded meshes when available, plain blocks otherwise) and moves
-- them from solved poses. On top of the robot's own parts it can draw a chassis' size, a paint finish with worn-metal
-- textures, and add-on kits (the crests), which are plain Parts. A robot can be swapped for another frame in place.
-- Nothing here feeds back into the simulation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RobotKits = require(Shared:WaitForChild("RobotKits"))
local RobotSkeleton = require(Shared:WaitForChild("RobotSkeleton"))

-- One piece of an add-on kit, with where it sits at rest relative to its joint.
type KitPart = {
	part: Part,
	role: string,
	joint: number,
	-- From the joint's pivot to the piece's center, and the piece's own turn, at scale 1.
	offset: Vector3,
	turn: CFrame,
	size: Vector3,
	-- The piece's CFrame relative to its joint at the current scale.
	placed: CFrame,
}

export type RobotRig = {
	rig: RobotSkeleton.Rig,
	folder: Folder,
	parts: { BasePart },
	-- Difference between an imported mesh part's placement and the rig's authoring axes. Identity for blocks.
	correction: { CFrame },
	roles: { string },
	accent: Color3,
	-- Replaces the rig's armor color, so the two fighters can read apart as light steel and dark gunmetal.
	armor: Color3?,
	flash: Color3?,
	joints: { CFrame },
	-- Where every part goes this frame: the robot's own parts first, then the kit pieces.
	frames: { CFrame },
	usesMeshes: boolean,
	-- How big the robot is drawn, and the sizes and corrections that go with it.
	scale: number,
	baseSizes: { Vector3 },
	scaledCorrection: { CFrame },
	kitParts: { KitPart },
	-- The kits currently drawn, as one comma-separated key, so asking for the same set again does nothing.
	kitKey: string,
	allParts: { BasePart },
	-- The material and reflectance armor and trim are drawn with, or nil for the rig's own.
	finishMaterial: Enum.Material?,
	finishReflectance: number,
	-- How much of the robot is hidden on this screen alone, from 0 (drawn) to 1 (gone).
	ghost: number,
	-- The frame's worn-metal SurfaceAppearances by finish name (see RobotWear), or nil for plain colored parts; the name of
	-- the finish worn, and each textured part's appearance (nil for parts drawn plain, like glows).
	wear: { [string]: SurfaceAppearance }?,
	finishName: string,
	appearances: { [BasePart]: SurfaceAppearance? },
	-- The core glow's own color (a case item, see Looks.Glows) in place of the accent's, and how it moves: nil, "pulse"
	-- or "spectrum".
	glowColor: Color3?,
	glowAnimation: string?,
}

local RobotRig = {}

local FLASH_STRENGTH = 0.7
local CYLINDER_TURN = CFrame.Angles(0, 0, math.rad(90))
-- The roles drawn with the worn-metal textures; Armor and Trim are tinted with the paint, the others are not.
local TEXTURED = { Armor = true, Trim = true, Dark = true, Steel = true }
local UNTINTED = Color3.new(1, 1, 1)

local function roleColor(def: RobotSkeleton.RoleDef, role: string, accent: Color3, armor: Color3?): Color3
	if role == "Armor" and armor ~= nil then
		return armor
	end
	if not def.tint then
		return def.color
	end
	if role == "Glow" then
		return accent:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	return accent
end

local function paint(self: RobotRig, part: BasePart, role: string)
	local def = self.rig.def.roles[role]
	local color = roleColor(def, role, self.accent, self.armor)
	if role == "Glow" and self.glowColor ~= nil then
		color = RobotRig.glowAt(self, os.clock())
	end
	if self.flash ~= nil and (role == "Armor" or role == "Trim") then
		color = color:Lerp(self.flash, FLASH_STRENGTH)
	end
	local appearance = self.appearances[part]
	if appearance ~= nil then
		-- The textures carry the material; the paint tints where the map's alpha says paint is (see RobotWear).
		appearance.Color = if role == "Armor" or role == "Trim" then color else UNTINTED
		part.Color = color
		part.Material = Enum.Material.Metal
		part.Reflectance = 0
		return
	end
	part.Color = color
	if self.finishMaterial ~= nil and (role == "Armor" or role == "Trim") then
		part.Material = self.finishMaterial
		part.Reflectance = self.finishReflectance
	else
		part.Material = def.material
		part.Reflectance = 0
	end
end

-- Puts the worn-metal textures of the current finish on every textured part, or takes them off when the frame has none.
local function applyWear(self: RobotRig)
	local wear = self.wear
	local source = if wear ~= nil then wear[self.finishName] or wear.BRUSHED else nil
	for index, part in self.parts do
		local old = self.appearances[part]
		local wanted = source ~= nil and self.usesMeshes and TEXTURED[self.roles[index]] == true
		if old ~= nil and (not wanted or old.Name ~= (source :: SurfaceAppearance).Name) then
			old:Destroy()
			self.appearances[part] = nil
		end
		if wanted and self.appearances[part] == nil then
			local appearance = (source :: SurfaceAppearance):Clone()
			appearance.Parent = part
			self.appearances[part] = appearance
		end
	end
end

local function applyColors(self: RobotRig)
	for index, part in self.parts do
		paint(self, part, self.roles[index])
	end
	for _, kit in self.kitParts do
		paint(self, kit.part, kit.role)
	end
end

-- The corrections and kit placements for the current scale.
local function applyScale(self: RobotRig)
	local scale = self.scale
	for index, part in self.parts do
		local base = self.baseSizes[index]
		part.Size = base * scale
	end
	for index, correction in self.correction do
		self.scaledCorrection[index] = CFrame.new(correction.Position * scale) * (correction - correction.Position)
	end
	for _, kit in self.kitParts do
		local size = kit.size * scale
		-- A cylinder's length runs along X in Roblox, along Y in the kit data.
		kit.part.Size = if kit.part.Shape == Enum.PartType.Cylinder then Vector3.new(size.Y, size.X, size.Z) else size
		kit.placed = CFrame.new(kit.offset * scale) * kit.turn
	end
end

-- (Re)builds the robot's own parts for a frame: the imported meshes where the template has them, blocks otherwise. Kit
-- pieces are left alone; they ride on the shared skeleton's joints, which every frame has.
local function buildParts(self: RobotRig, rig: RobotSkeleton.Rig, template: Instance?)
	local meshes: { [string]: MeshPart? } = {}
	if template ~= nil then
		for _, descendant in template:GetDescendants() do
			if descendant:IsA("MeshPart") then
				meshes[descendant.Name] = descendant
			end
		end
	end

	-- The importer may place the whole model anywhere; the first part tells how it relates to the authoring axes.
	local defs = rig.def.parts
	local mapping = CFrame.identity
	local referenceMesh = meshes[defs[1].name]
	if referenceMesh ~= nil then
		mapping = referenceMesh.CFrame * CFrame.new(defs[1].center):Inverse()
	end
	local unmap = mapping:Inverse()

	local parts: { BasePart } = {}
	local correction: { CFrame } = {}
	local roles: { string } = {}
	local baseSizes: { Vector3 } = {}
	local usesMeshes = false
	for index, def in defs do
		local part: BasePart
		local mesh = meshes[def.name]
		if mesh ~= nil then
			part = mesh:Clone()
			correction[index] = CFrame.new(def.center):Inverse() * unmap * mesh.CFrame
			usesMeshes = true
		else
			local block = Instance.new("Part")
			block.Size = def.size
			part = block
			correction[index] = CFrame.identity
		end
		part.Name = def.name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = rig.def.roles[def.role].material
		part.LocalTransparencyModifier = self.ghost
		part.Parent = self.folder
		parts[index] = part
		roles[index] = def.role
		baseSizes[index] = part.Size
	end

	self.rig = rig
	self.parts = parts
	self.correction = correction
	self.roles = roles
	self.baseSizes = baseSizes
	self.scaledCorrection = table.clone(correction)
	self.usesMeshes = usesMeshes
	table.clear(self.appearances)
	local all = table.clone(parts)
	for _, kit in self.kitParts do
		table.insert(all, kit.part)
	end
	self.allParts = all
	self.frames = table.create(#all, CFrame.identity)
	applyWear(self)
end

-- Builds the parts under `parent`. `template` holds the imported MeshParts by name, or is nil for a blockout robot.
-- `wear` holds the frame's worn-metal SurfaceAppearances by finish name, if it has them.
function RobotRig.new(
	parent: Instance,
	rig: RobotSkeleton.Rig,
	accent: Color3,
	template: Instance?,
	wear: { [string]: SurfaceAppearance }?
): RobotRig
	local folder = Instance.new("Folder")
	folder.Name = "Robot"
	local self: RobotRig = {
		rig = rig,
		folder = folder,
		parts = {},
		correction = {},
		roles = {},
		accent = accent,
		armor = nil,
		flash = nil,
		joints = table.create(rig.jointCount, CFrame.identity),
		frames = {},
		usesMeshes = false,
		scale = 1,
		baseSizes = {},
		scaledCorrection = {},
		kitParts = {},
		kitKey = "",
		allParts = {},
		finishMaterial = nil,
		finishReflectance = 0,
		ghost = 0,
		wear = wear,
		finishName = "",
		appearances = {},
		glowColor = nil,
		glowAnimation = nil,
	}
	buildParts(self, rig, template)
	folder.Parent = parent
	applyColors(self)
	return self
end

-- Swaps the robot for another frame on the same skeleton (another chassis' robot), keeping its size, kits, paint, finish
-- and fade. Asking for the frame it already is does nothing. Returns whether it rebuilt the robot's parts: anything
-- fastened to the old parts (strike trails) is gone, and the new parts stand at the template's pose until the next place.
function RobotRig.setFrame(
	self: RobotRig,
	rig: RobotSkeleton.Rig,
	template: Instance?,
	wear: { [string]: SurfaceAppearance }?
): boolean
	if rig == self.rig then
		return false
	end
	for _, part in self.parts do
		part:Destroy()
	end
	self.wear = wear
	buildParts(self, rig, template)
	applyScale(self)
	applyColors(self)
	return true
end

-- Changes the team color and the armor color (nil keeps the rig's own).
function RobotRig.setPalette(self: RobotRig, accent: Color3, armor: Color3?)
	if accent ~= self.accent or armor ~= self.armor then
		self.accent = accent
		self.armor = armor
		applyColors(self)
	end
end

-- The material and reflectance of the armor and trim (a paint finish), or nil for the rig's own. `name` is the finish's
-- name in Looks.Finishes, which picks the worn-metal textures for a frame that has them.
function RobotRig.setFinish(self: RobotRig, material: Enum.Material?, reflectance: number, name: string?)
	local finishName = name or ""
	if material ~= self.finishMaterial or reflectance ~= self.finishReflectance or finishName ~= self.finishName then
		self.finishMaterial = material
		self.finishReflectance = reflectance
		self.finishName = finishName
		applyWear(self)
		applyColors(self)
	end
end

-- Tints the armor and trim toward a color (a hit or a block flash), or back to normal with nil.
function RobotRig.setFlash(self: RobotRig, color: Color3?)
	if color ~= self.flash then
		self.flash = color
		applyColors(self)
	end
end

-- The core glow's color at a moment: its own color, breathing for "pulse", or running through every hue for "spectrum".
function RobotRig.glowAt(self: RobotRig, now: number): Color3
	local color = self.glowColor or self.accent
	if self.glowAnimation == "pulse" then
		local breath = 0.5 + 0.5 * math.sin(now * 2.6)
		return Color3.new(0, 0, 0):Lerp(color, 0.45 + 0.55 * breath)
	elseif self.glowAnimation == "spectrum" then
		return Color3.fromHSV((now * 0.12) % 1, 0.8, 1)
	end
	return color
end

-- Gives the core glow a color of its own and a way of moving (see Looks.Glows), or follows the accent again with nil.
function RobotRig.setGlow(self: RobotRig, color: Color3?, animation: string?)
	if color ~= self.glowColor or animation ~= self.glowAnimation then
		self.glowColor = color
		self.glowAnimation = animation
		applyColors(self)
	end
end

-- Moves an animated core glow on; place does it every frame, so only a robot that is not placed needs it.
function RobotRig.stepGlow(self: RobotRig, now: number)
	if self.glowAnimation == nil or self.glowColor == nil then
		return
	end
	local color = RobotRig.glowAt(self, now)
	for index, part in self.parts do
		if self.roles[index] == "Glow" then
			part.Color = color
		end
	end
	for _, kit in self.kitParts do
		if kit.role == "Glow" then
			kit.part.Color = color
		end
	end
end

-- Draws the robot this many times as big about its feet. The hit circle in the simulation does not change.
function RobotRig.setScale(self: RobotRig, scale: number)
	if scale ~= self.scale then
		self.scale = scale
		applyScale(self)
	end
end

-- Fades the robot out on this screen alone (0 draws it, 1 hides it); the garage clears the opponent out of its close-up.
function RobotRig.setGhost(self: RobotRig, amount: number)
	if amount ~= self.ghost then
		self.ghost = amount
		for _, part in self.allParts do
			part.LocalTransparencyModifier = amount
		end
	end
end

local function newKitPart(self: RobotRig, piece: RobotKits.Piece): KitPart
	local part = Instance.new("Part")
	part.Name = "Kit"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.LocalTransparencyModifier = self.ghost
	if piece.shape == "cyl" then
		part.Shape = Enum.PartType.Cylinder
	elseif piece.shape == "ball" then
		part.Shape = Enum.PartType.Ball
	end
	part.Parent = self.folder
	local jointIndex, offset, turn = RobotSkeleton.pieceLocal(self.rig, piece)
	return {
		part = part,
		role = piece.role,
		joint = jointIndex,
		offset = offset,
		turn = if piece.shape == "cyl" then turn * CYLINDER_TURN else turn,
		size = piece.size,
		placed = CFrame.identity,
	}
end

-- Draws exactly these add-on kits (names from RobotKits) and none other. An empty list takes them all off.
function RobotRig.setKits(self: RobotRig, names: { string })
	local sorted = table.clone(names)
	table.sort(sorted)
	local key = table.concat(sorted, ",")
	if key == self.kitKey then
		return
	end
	self.kitKey = key

	for _, kit in self.kitParts do
		kit.part:Destroy()
	end
	table.clear(self.kitParts)
	for _, name in sorted do
		local pieces = RobotKits[name]
		if pieces ~= nil then
			for _, piece in pieces do
				table.insert(self.kitParts, newKitPart(self, piece))
			end
		end
	end

	local all = table.clone(self.parts)
	for _, kit in self.kitParts do
		table.insert(all, kit.part)
	end
	self.allParts = all
	self.frames = table.create(#all, CFrame.identity)
	applyScale(self)
	applyColors(self)
end

function RobotRig.place(self: RobotRig, pose: RobotSkeleton.Pose, root: CFrame, mirror: boolean)
	RobotSkeleton.solve(self.rig, pose, root, mirror, self.joints, self.frames, self.scale)
	local base = #self.parts
	for index = 1, base do
		self.frames[index] = self.frames[index] * self.scaledCorrection[index]
	end
	for index, kit in self.kitParts do
		self.frames[base + index] = self.joints[kit.joint] * kit.placed
	end
	Workspace:BulkMoveTo(self.allParts, self.frames, Enum.BulkMoveMode.FireCFrameChanged)
	RobotRig.stepGlow(self, os.clock())
end

return RobotRig
