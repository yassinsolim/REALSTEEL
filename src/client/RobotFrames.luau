--!strict

-- Client: every robot frame the game can draw (see RobotRigs), ready to build. Each frame is a rig on the shared skeleton,
-- the uploaded meshes the server loaded for it (ReplicatedStorage.Robots, see RobotLibrary) and its worn-metal textures
-- (ReplicatedStorage.Shared.RobotWear, one SurfaceAppearance per paint finish). Frames without meshes are drawn as
-- blockouts, and frames without textures in plain colors. All frames share one animation set, compiled on ANVIL's rig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RobotClips = require(Shared:WaitForChild("RobotClips"))
local RobotRigs = require(Shared:WaitForChild("RobotRigs"))
local RobotSkeleton = require(Shared:WaitForChild("RobotSkeleton"))

export type Frame = {
	name: string,
	rig: RobotSkeleton.Rig,
	template: Instance?,
	wear: { [string]: SurfaceAppearance }?,
}

export type Library = {
	-- The skeleton's rig and the clips every frame plays.
	rig: RobotSkeleton.Rig,
	clips: { [string]: RobotSkeleton.Clip },
	frames: { [string]: Frame },
}

local RobotFrames = {}

-- The frame drawn when one is missing or unknown.
RobotFrames.Default = "Anvil"

local function wearOf(folder: Instance?, name: string): { [string]: SurfaceAppearance }?
	local frame = if folder ~= nil then folder:FindFirstChild(name) else nil
	if frame == nil then
		return nil
	end
	local byFinish: { [string]: SurfaceAppearance } = {}
	local found = false
	for _, child in frame:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			byFinish[child.Name] = child
			found = true
		end
	end
	return if found then byFinish else nil
end

-- Yields until the server has shared the meshes (or given up on them).
function RobotFrames.load(): Library
	local robots = ReplicatedStorage:WaitForChild("Robots", 30)
	local wear = Shared:FindFirstChild("RobotWear")
	local frames: { [string]: Frame } = {}
	for name, def in RobotRigs :: { [string]: RobotSkeleton.RigDef } do
		frames[name] = {
			name = name,
			rig = RobotSkeleton.newRig(def),
			template = if robots ~= nil then robots:FindFirstChild(name) else nil,
			wear = wearOf(wear, name),
		}
	end
	local rig = frames[RobotFrames.Default].rig
	return {
		rig = rig,
		clips = RobotSkeleton.compileClips(rig, RobotClips :: any),
		frames = frames,
	}
end

-- A frame by name, or the default frame for a name that is not one.
function RobotFrames.get(library: Library, name: string?): Frame
	return (if name ~= nil then library.frames[name] else nil) or library.frames[RobotFrames.Default]
end

return RobotFrames
