--!strict

-- Forward kinematics and pose sampling for the fighters' articulated robots. Pure math over the generated rig and clip
-- data (RobotRigs, RobotClips), so it behaves the same on the client, in the unit checks, and anywhere else.
--
-- Rotations are stored in radians and applied as CFrame.fromEulerAnglesYXZ(rx, ry, rz) about each joint pivot, in the
-- parent joint's frame. The robot faces -Z with its right side on +X.

export type JointDef = { name: string, parent: string, pivot: Vector3 }
export type PartDef = { name: string, joint: string, role: string, center: Vector3, size: Vector3 }
export type RoleDef = { color: Color3, material: Enum.Material, tint: boolean }
export type RigDef = { roles: { [string]: RoleDef }, joints: { JointDef }, parts: { PartDef } }

export type Rig = {
	def: RigDef,
	jointCount: number,
	jointIndex: { [string]: number },
	-- Index of each joint's parent; 0 for the root joint.
	parent: { number },
	pivot: { Vector3 },
	-- Rest-pose pivot relative to the parent's pivot.
	offset: { Vector3 },
	-- Index of the joint on the other side of the body (itself for center joints), used to mirror a pose.
	mirror: { number },
	partJoint: { number },
	-- Rest-pose part center relative to its joint's pivot.
	partOffset: { Vector3 },
}

export type Pose = { pos: Vector3, rot: { Vector3 } }

export type PoseData = { pos: Vector3, rot: { [string]: Vector3 } }
export type KeyData = { u: number, pose: string, ease: string }
export type ClipData = { kind: string, period: number?, keys: { KeyData } }
export type ClipsData = { poses: { [string]: PoseData }, clips: { [string]: ClipData } }

export type Key = { u: number, pose: Pose, ease: string }
-- kind is "loop" (u wraps 0-1), "phase" (u runs 0-3 across startup, active, recovery), "norm" (0-1), "seconds" or "hold".
export type Clip = { kind: string, period: number, keys: { Key } }

local RobotSkeleton = {}

local function mirrorName(name: string): string
	local base = string.sub(name, 1, -2)
	local side = string.sub(name, -1)
	if side == "L" then
		return base .. "R"
	elseif side == "R" then
		return base .. "L"
	end
	return name
end

function RobotSkeleton.newRig(def: RigDef): Rig
	local rig: Rig = {
		def = def,
		jointCount = #def.joints,
		jointIndex = {},
		parent = {},
		pivot = {},
		offset = {},
		mirror = {},
		partJoint = {},
		partOffset = {},
	}
	for index, joint in def.joints do
		rig.jointIndex[joint.name] = index
	end
	for index, joint in def.joints do
		local parentIndex = if joint.parent == "" then 0 else rig.jointIndex[joint.parent]
		assert(parentIndex ~= nil and parentIndex < index, "joint " .. joint.name .. " must come after its parent")
		rig.parent[index] = parentIndex
		rig.pivot[index] = joint.pivot
		rig.offset[index] = if parentIndex == 0 then Vector3.zero else joint.pivot - def.joints[parentIndex].pivot
		rig.mirror[index] = rig.jointIndex[mirrorName(joint.name)] or index
	end
	for index, part in def.parts do
		local jointIndex = rig.jointIndex[part.joint]
		assert(jointIndex ~= nil, "part " .. part.name .. " names an unknown joint")
		rig.partJoint[index] = jointIndex
		rig.partOffset[index] = part.center - rig.pivot[jointIndex]
	end
	return rig
end

function RobotSkeleton.newPose(rig: Rig): Pose
	return { pos = Vector3.zero, rot = table.create(rig.jointCount, Vector3.zero) }
end

function RobotSkeleton.copy(from: Pose, into: Pose)
	into.pos = from.pos
	for index, rotation in from.rot do
		into.rot[index] = rotation
	end
end

function RobotSkeleton.lerp(a: Pose, b: Pose, t: number, into: Pose)
	into.pos = a.pos:Lerp(b.pos, t)
	for index, rotation in a.rot do
		into.rot[index] = rotation:Lerp(b.rot[index], t)
	end
end

function RobotSkeleton.clear(into: Pose)
	into.pos = Vector3.zero
	for index in into.rot do
		into.rot[index] = Vector3.zero
	end
end

-- into += pose * weight, for blending several clips by direction.
function RobotSkeleton.accumulate(into: Pose, pose: Pose, weight: number)
	into.pos += pose.pos * weight
	for index, rotation in pose.rot do
		into.rot[index] += rotation * weight
	end
end

local function compilePose(rig: Rig, data: PoseData): Pose
	local pose = RobotSkeleton.newPose(rig)
	pose.pos = data.pos
	for name, degrees in data.rot do
		local index = rig.jointIndex[name]
		assert(index ~= nil, "pose names an unknown joint " .. name)
		pose.rot[index] = Vector3.new(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
	end
	return pose
end

function RobotSkeleton.compileClips(rig: Rig, data: ClipsData): { [string]: Clip }
	local poses: { [string]: Pose } = {}
	for name, poseData in data.poses do
		poses[name] = compilePose(rig, poseData)
	end
	local clips: { [string]: Clip } = {}
	for name, clipData in data.clips do
		local keys: { Key } = {}
		local previous = -math.huge
		for _, keyData in clipData.keys do
			local pose = poses[keyData.pose]
			assert(pose ~= nil, "clip " .. name .. " names an unknown pose " .. keyData.pose)
			assert(keyData.u >= previous, "clip " .. name .. " keys must be in order")
			previous = keyData.u
			table.insert(keys, { u = keyData.u, pose = pose, ease = keyData.ease })
		end
		clips[name] = { kind = clipData.kind, period = clipData.period or 1, keys = keys }
	end
	return clips
end

local function ease(t: number, mode: string): number
	if mode == "in" then
		return t * t
	elseif mode == "out" then
		return 1 - (1 - t) * (1 - t)
	elseif mode == "smooth" then
		return t * t * (3 - 2 * t)
	end
	return t
end

-- Writes the clip's pose at position u into `into`. Outside a non-looping clip's keys the nearest key holds.
function RobotSkeleton.sample(clip: Clip, u: number, into: Pose)
	local keys = clip.keys
	local count = #keys
	local first = keys[1]
	local last = keys[count]
	if count == 1 then
		RobotSkeleton.copy(first.pose, into)
		return
	end

	if clip.kind == "loop" then
		u = (u - first.u) % 1 + first.u
		if u >= last.u then
			local t = (u - last.u) / (1 + first.u - last.u)
			RobotSkeleton.lerp(last.pose, first.pose, ease(t, last.ease), into)
			return
		end
	elseif u <= first.u then
		RobotSkeleton.copy(first.pose, into)
		return
	elseif u >= last.u then
		RobotSkeleton.copy(last.pose, into)
		return
	end

	for index = 1, count - 1 do
		local a = keys[index]
		local b = keys[index + 1]
		if u >= a.u and u < b.u then
			RobotSkeleton.lerp(a.pose, b.pose, ease((u - a.u) / (b.u - a.u), a.ease), into)
			return
		end
	end
	RobotSkeleton.copy(last.pose, into)
end

local function jointRotation(rig: Rig, pose: Pose, index: number, mirror: boolean): CFrame
	if mirror then
		local rotation = pose.rot[rig.mirror[index]]
		return CFrame.fromEulerAnglesYXZ(rotation.X, -rotation.Y, -rotation.Z)
	end
	local rotation = pose.rot[index]
	return CFrame.fromEulerAnglesYXZ(rotation.X, rotation.Y, rotation.Z)
end

-- Fills `joints` with every joint's world CFrame and `parts` with every part's, for the robot standing at `root`
-- (ground contact point between the feet, facing -Z). A mirrored solve swaps left and right, so the same clips drive
-- a southpaw. `scale` draws the whole robot that many times as big about the root, feet staying on the ground.
function RobotSkeleton.solve(
	rig: Rig,
	pose: Pose,
	root: CFrame,
	mirror: boolean,
	joints: { CFrame },
	parts: { CFrame },
	scale: number?
)
	local size = scale or 1
	local shift = pose.pos * size
	if mirror then
		shift = Vector3.new(-shift.X, shift.Y, shift.Z)
	end
	for index = 1, rig.jointCount do
		local rotation = jointRotation(rig, pose, index, mirror)
		local parentIndex = rig.parent[index]
		if parentIndex == 0 then
			joints[index] = root * CFrame.new(rig.pivot[index] * size + shift) * rotation
		else
			joints[index] = joints[parentIndex] * CFrame.new(rig.offset[index] * size) * rotation
		end
	end
	for index, jointIndex in rig.partJoint do
		parts[index] = joints[jointIndex] * CFrame.new(rig.partOffset[index] * size)
	end
end

-- Where an add-on piece (see RobotKits) sits at rest: the index of the joint it rides on, the offset from that joint's
-- pivot to the piece's center, and the piece's own turn (degrees applied as CFrame.fromEulerAnglesYXZ). The piece's
-- CFrame is then the joint's CFrame times CFrame.new(offset) times the turn.
function RobotSkeleton.pieceLocal(
	rig: Rig,
	piece: { joint: string, center: Vector3, rot: Vector3 }
): (number, Vector3, CFrame)
	local jointIndex = rig.jointIndex[piece.joint]
	assert(jointIndex ~= nil, "kit piece names an unknown joint " .. piece.joint)
	local turn = CFrame.fromEulerAnglesYXZ(math.rad(piece.rot.X), math.rad(piece.rot.Y), math.rad(piece.rot.Z))
	return jointIndex, piece.center - rig.pivot[jointIndex], turn
end

-- How far in front of the root (along -Z) a joint's parts reach, from their oriented bounding boxes.
function RobotSkeleton.frontExtent(rig: Rig, parts: { CFrame }, jointName: string): number
	local jointIndex = rig.jointIndex[jointName]
	local best = -math.huge
	for index, part in rig.def.parts do
		if rig.partJoint[index] == jointIndex then
			local half = part.size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner =
							parts[index]:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						best = math.max(best, -corner.Z)
					end
				end
			end
		end
	end
	return best
end

return RobotSkeleton
