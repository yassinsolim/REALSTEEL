--!strict

-- Client: the winches' cables and hooks. The server builds the winches themselves under each ring's screen (see Foundry);
-- where each robot and hook hangs comes from Hoist, and this draws a cable from the winch down to the hook, which holds
-- the robot by the top of its head. A hook that has not moved since the last frame is left as it is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local Hoist = require(Shared:WaitForChild("Hoist"))

-- One winch's cable and hook.
type Line = {
	cable: Part,
	hook: Part,
	-- How far the hook hangs off to the side of its winch: under it, unless it holds a robot that has moved.
	drift: Vector3,
	shown: boolean,
	-- Where the hook was last drawn, while it shows.
	drawn: Vector3?,
}

export type Cranes = {
	folder: Folder,
	lines: { [string]: Line },
}

local Cranes = {}

-- A hook wound up closer than this to its winch is tucked away under it.
local TUCKED = 0.3
-- How quickly a hook swings over to a robot it is coming down for, or back under its winch once it has let go.
local SWING = 6
-- A hook that moved less than this since it was last drawn is not drawn again.
local STILL = 1e-3
local CABLE = Color3.fromRGB(30, 33, 42)
local HOOK = Color3.fromRGB(255, 178, 66)

function Cranes.new(): Cranes
	local folder = Instance.new("Folder")
	folder.Name = "Cranes"
	folder.Parent = Workspace
	return { folder = folder, lines = {} }
end

-- Where the underside of the winch over a seat's mark is, in a ring at `origin` whose winches hang at `hookY`.
function Cranes.winchAt(origin: Vector3, hookY: number, seat: number): Vector3
	local side = if seat == 1 then -1 else 1
	return origin + Vector3.new(side * FightConfig.StartHalfDistance, hookY - Hoist.WinchDrop, 0)
end

local function newPart(self: Cranes, key: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = 1
	part.Parent = self.folder
	return part
end

local function lineFor(self: Cranes, key: string): Line
	local line = self.lines[key]
	if line == nil then
		local cable = newPart(self, key, Vector3.new(1, 0.14, 0.14), CABLE, Enum.Material.Metal)
		-- A cylinder's length runs along its X axis.
		cable.Shape = Enum.PartType.Cylinder
		local made: Line = {
			cable = cable,
			hook = newPart(self, key, Vector3.new(0.7, 0.5, 0.7), HOOK, Enum.Material.Neon),
			drift = Vector3.zero,
			shown = false,
			drawn = nil,
		}
		self.lines[key] = made
		return made
	end
	return line
end

-- Draws one winch's cable and hook, `key` naming it (a ring and a seat): `at` is the winch's underside and `winch` how
-- far its robot and hook hang (see Hoist). `head` is where the robot's head is drawn, which the hook holds it by, and
-- `reaching` says the hook is coming down for it; the head is only needed while the hook holds the robot or reaches for
-- it.
function Cranes.draw(
	self: Cranes,
	key: string,
	at: Vector3,
	winch: Hoist.Winch,
	head: Vector3?,
	reaching: boolean,
	dt: number
)
	local line = lineFor(self, key)
	local overHead = if head ~= nil then Vector3.new(head.X - at.X, 0, head.Z - at.Z) else line.drift
	if winch.lift > 0 then
		line.drift = overHead
	else
		local goal = if reaching then overHead else Vector3.zero
		line.drift = goal + (line.drift - goal) * math.exp(-SWING * dt)
	end

	local shown = winch.reach >= TUCKED
	if shown ~= line.shown then
		line.shown = shown
		line.drawn = nil
		local transparency = if shown then 0 else 1
		line.cable.Transparency = transparency
		line.hook.Transparency = transparency
	end
	if not shown then
		return
	end
	local bottom = at + line.drift - Vector3.new(0, winch.reach, 0)
	local drawn = line.drawn
	if drawn ~= nil and (bottom - drawn).Magnitude < STILL then
		return
	end
	line.drawn = bottom
	line.cable.Size = Vector3.new((bottom - at).Magnitude, 0.14, 0.14)
	-- Turned so its length runs from the winch down to the hook.
	line.cable.CFrame = CFrame.lookAt((at + bottom) / 2, bottom, Vector3.xAxis) * CFrame.Angles(0, math.rad(90), 0)
	line.hook.CFrame = CFrame.new(bottom)
end

return Cranes
