--!strict

-- Small helpers for building the venue out of anchored parts: plain decoration (no collision, no queries, no shadow),
-- solid structure people walk on and bump into, discs, bars between two points, and text on a surface. Everything the
-- server builds goes through here, so the venue's parts all behave the same way.

local Build = {}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape ~= nil then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

-- Decoration: nothing collides with it, raycasts pass through it, and it casts no shadow.
function Build.decor(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = newPart(parent, name, size, cframe, color, material, shape)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Structure: floors, walls, steps and rails that characters stand on and the camera stops at.
function Build.solid(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = newPart(parent, name, size, cframe, color, material, shape)
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	return part
end

-- An invisible wall that only stops characters.
function Build.blocker(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local part = newPart(parent, name, size, cframe, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	part.Transparency = 1
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A flat disc centered on (x, z). Cylinder parts run along X, so they are turned onto Y to lie flat.
function Build.disc(
	parent: Instance,
	name: string,
	radius: number,
	topY: number,
	thickness: number,
	color: Color3,
	material: Enum.Material,
	x: number?,
	z: number?
): Part
	return Build.decor(
		parent,
		name,
		Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(x or 0, topY - thickness / 2, z or 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A thin glowing circle painted on a flat surface: a glowing disc with the surface color laid over its middle. The glow
-- stays opaque: the engine draws see-through Neon a little toward the camera, so a see-through glow this close under the
-- cover shows through it and floods the whole circle.
function Build.ringLine(
	parent: Instance,
	name: string,
	radius: number,
	width: number,
	topY: number,
	color: Color3,
	surfaceColor: Color3,
	surfaceMaterial: Enum.Material
)
	Build.disc(parent, name, radius + width / 2, topY + 0.02, 0.04, color, Enum.Material.Neon)
	Build.disc(parent, name .. "Cover", radius - width / 2, topY + 0.04, 0.04, surfaceColor, surfaceMaterial)
end

-- A cylinder between two points.
function Build.bar(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material
): Part
	local length = (to - from).Magnitude
	return Build.decor(
		parent,
		name,
		Vector3.new(length + thickness * 0.5, thickness, thickness),
		CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

-- A vertical cylinder standing on a point.
function Build.vbar(
	parent: Instance,
	name: string,
	base: Vector3,
	height: number,
	thickness: number,
	color: Color3,
	material: Enum.Material
): Part
	return Build.decor(
		parent,
		name,
		Vector3.new(height, thickness, thickness),
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

function Build.polar(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

-- A block standing on the circle at `radius`, turned to face the ring's center.
function Build.facingCenter(radius: number, angle: number, centerY: number): CFrame
	local position = Build.polar(radius, angle, centerY)
	return CFrame.lookAt(position, Vector3.new(0, centerY, 0))
end

-- Text on the front face of a part, lit from within so it reads in the dark. Returns the label so it can be changed.
function Build.label(
	part: BasePart,
	text: string,
	font: Enum.Font,
	color: Color3,
	pixelsPerStud: number?,
	face: Enum.NormalId?
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = part
	local item = Instance.new("TextLabel")
	item.Name = "Text"
	item.BackgroundTransparency = 1
	item.Size = UDim2.fromScale(1, 1)
	item.Font = font
	item.Text = text
	item.TextColor3 = color
	item.TextScaled = true
	item.Parent = gui
	return item
end

return Build
