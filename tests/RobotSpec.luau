--!strict

-- Headless checks for the robot rig, pose sampling and animator. Run from Studio's command bar or the Studio MCP:
--   local passed, failures = require(game.ReplicatedStorage.Tests.RobotSpec)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FightConfig = require(ReplicatedStorage.Shared.FightConfig)
local FightSim = require(ReplicatedStorage.Shared.FightSim)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Looks = require(ReplicatedStorage.Shared.Looks)
local RobotAnimator = require(ReplicatedStorage.Shared.RobotAnimator)
local RobotAssets = require(ReplicatedStorage.Shared.RobotAssets)
local RobotClips = require(ReplicatedStorage.Shared.RobotClips)
local RobotKits = require(ReplicatedStorage.Shared.RobotKits)
local RobotRigs = require(ReplicatedStorage.Shared.RobotRigs)
local RobotSkeleton = require(ReplicatedStorage.Shared.RobotSkeleton)

local State = FightSim.State
local jab = FightConfig.Moves[FightConfig.JabMoveId]
local straight = FightConfig.Moves[FightConfig.StraightMoveId]

-- The defender's body is a circle of BodyRadius, but the robot is only about this deep from its center to its front.
local DEFENDER_FRONT_DEPTH = 0.65
local EPSILON = 1e-4

local rig = RobotSkeleton.newRig(RobotRigs.Anvil)
local clips = RobotSkeleton.compileClips(rig, RobotClips :: any)

local function solved(pose: RobotSkeleton.Pose, mirror: boolean?): ({ CFrame }, { CFrame })
	local joints = table.create(rig.jointCount, CFrame.identity)
	local parts = table.create(#rig.def.parts, CFrame.identity)
	RobotSkeleton.solve(rig, pose, CFrame.identity, mirror == true, joints, parts)
	return joints, parts
end

local function sampled(clipName: string, u: number): RobotSkeleton.Pose
	local pose = RobotSkeleton.newPose(rig)
	RobotSkeleton.sample(clips[clipName], u, pose)
	return pose
end

local function samePose(a: RobotSkeleton.Pose, b: RobotSkeleton.Pose, tolerance: number): boolean
	if (a.pos - b.pos).Magnitude > tolerance then
		return false
	end
	for index, rotation in a.rot do
		if (rotation - b.rot[index]).Magnitude > tolerance then
			return false
		end
	end
	return true
end

-- Furthest forward (along -Z) a limb's boxes reach for a clip position, with the root at the origin facing -Z.
local function strikerFront(clipName: string, u: number, joint: string): number
	local _, parts = solved(sampled(clipName, u))
	return RobotSkeleton.frontExtent(rig, parts, joint)
end

-- The other side's limb: HandL and HandR, FootL and FootR.
local function twinOf(joint: string): string
	local side = string.sub(joint, -1)
	return string.sub(joint, 1, -2) .. (if side == "L" then "R" else "L")
end

-- Distance at which an attack's hit sphere can still touch a defender, measured to the front of the defender's body.
local function neededReach(move: FightConfig.MoveData): number
	return move.reach + move.hitRadius + FightConfig.BodyRadius - DEFENDER_FRONT_DEPTH
end

local function fighterIn(state: number, extra: { [string]: number }?): FightSim.Fighter
	local fighter = FightSim.newFighter(0, 0)
	fighter.state = state
	local values: { [string]: number } = extra or {}
	for key, value in values do
		(fighter :: any)[key] = value
	end
	return fighter
end

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

	-- Rig data: every generated Blender frame is consistent and symmetric, and on the shared skeleton.
	for frameName, def in RobotRigs :: { [string]: RobotSkeleton.RigDef } do
		local frameRig = RobotSkeleton.newRig(def)
		local roleless = 0
		for _, part in frameRig.def.parts do
			if frameRig.def.roles[part.role] == nil then
				roleless += 1
			end
		end
		check(`{frameName}: every part has a known role`, roleless == 0, roleless)

		local sameSkeleton = frameRig.jointCount == rig.jointCount
		for index, joint in frameRig.def.joints do
			local stock = rig.def.joints[index]
			if stock == nil or stock.name ~= joint.name or (stock.pivot - joint.pivot).Magnitude > EPSILON then
				sameSkeleton = false
			end
		end
		check(`{frameName}: built on the shared skeleton`, sameSkeleton)

		local restJoints = table.create(frameRig.jointCount, CFrame.identity)
		local restParts = table.create(#frameRig.def.parts, CFrame.identity)
		RobotSkeleton.solve(frameRig, RobotSkeleton.newPose(frameRig), CFrame.identity, false, restJoints, restParts)
		local worst = 0
		for index, part in frameRig.def.parts do
			worst = math.max(worst, (restParts[index].Position - part.center).Magnitude)
		end
		check(`{frameName}: rest pose reproduces the authored part centers`, worst < EPSILON, worst)

		local asymmetric = 0
		for index, joint in frameRig.def.joints do
			local other = frameRig.mirror[index]
			local pivot = frameRig.pivot[other]
			if (Vector3.new(-pivot.X, pivot.Y, pivot.Z) - joint.pivot).Magnitude > EPSILON then
				asymmetric += 1
			end
		end
		check(`{frameName}: joint pivots mirror left to right`, asymmetric == 0, asymmetric)

		local lookup: { [string]: RobotSkeleton.PartDef } = {}
		for _, part in frameRig.def.parts do
			lookup[part.name] = part
		end
		local unmatched = 0
		for _, part in frameRig.def.parts do
			local joint = part.joint
			if string.sub(joint, -1) == "L" then
				local twin = lookup[string.sub(part.name, 1, #joint - 1) .. "R" .. string.sub(part.name, #joint + 1)]
				if
					twin == nil
					or twin.role ~= part.role
					or (twin.size - part.size).Magnitude > 2e-3
					or (twin.center - Vector3.new(-part.center.X, part.center.Y, part.center.Z)).Magnitude > 2e-3
				then
					unmatched += 1
				end
			end
		end
		check(`{frameName}: left parts have mirrored right twins`, unmatched == 0, unmatched)
		-- The game looks up these parts for effects and the winches' hooks.
		local named = lookup.Head_Armor ~= nil and lookup.Chest_Armor ~= nil
		for _, limb in { "HandL", "HandR", "FootL", "FootR" } do
			named = named and lookup[limb .. "_Armor"] ~= nil
		end
		check(`{frameName}: has the head, chest, hand and foot armor the effects aim at`, named)
	end
	local frameCount = 0
	for _ in RobotRigs :: { [string]: any } do
		frameCount += 1
	end
	check("there is a frame for every chassis", frameCount >= #Looks.Frames, frameCount)
	for _, frameName in Looks.Frames do
		check(`the {frameName} frame exists`, (RobotRigs :: any)[frameName] ~= nil)
	end
	for _, body in Looks.Bodies do
		if body.frame ~= nil then
			check(`the {body.name} body's frame exists`, (RobotRigs :: any)[body.frame] ~= nil)
		end
	end
	-- Every frame is uploaded and has its worn-metal textures for every paint finish: a frame without a model is drawn as a
	-- blockout, and one without textures in plain colors.
	do
		local wear = ReplicatedStorage.Shared:FindFirstChild("RobotWear")
		local notUploaded: { string } = {}
		local unworn: { string } = {}
		for frameName in RobotRigs :: { [string]: any } do
			local asset = RobotAssets[frameName]
			if asset == nil or asset.Id <= 0 then
				table.insert(notUploaded, frameName)
			end
			local folder = if wear ~= nil then wear:FindFirstChild(frameName) else nil
			for _, finish in Looks.Finishes do
				local appearance = if folder ~= nil then folder:FindFirstChild(finish.name) else nil
				if appearance == nil or not appearance:IsA("SurfaceAppearance") then
					table.insert(unworn, `{frameName} {finish.name}`)
				end
			end
		end
		check("every frame is uploaded", #notUploaded == 0, table.concat(notUploaded, ", "))
		check("every frame has worn textures for every finish", #unworn == 0, table.concat(unworn, ", "))
		local strays: { string } = {}
		for name in RobotAssets do
			if (RobotRigs :: any)[name] == nil then
				table.insert(strays, name)
			end
		end
		check("every uploaded model is a frame", #strays == 0, table.concat(strays, ", "))
	end

	-- Clips: sampling hits its keys, loops are continuous, and nothing sinks into the floor.
	do
		local clipCount = 0
		local missingKeys = 0
		for _, clip in clips do
			clipCount += 1
			if #clip.keys == 0 then
				missingKeys += 1
			end
		end
		check("every clip has keys", clipCount > 0 and missingKeys == 0, missingKeys)

		local looseLoops = 0
		for name, clip in clips do
			if clip.kind == "loop" then
				local start = sampled(name, 0)
				local wrapped = sampled(name, 1)
				if not samePose(start, wrapped, 1e-3) then
					looseLoops += 1
				end
			end
		end
		check("loops end where they begin", looseLoops == 0, looseLoops)

		local offKey = 0
		for name, clip in clips do
			for index, key in clip.keys do
				local next = clip.keys[index + 1]
				if next ~= nil and next.u > key.u and clip.kind ~= "loop" then
					if not samePose(sampled(name, key.u), key.pose, 1e-3) then
						offKey += 1
					end
				end
			end
		end
		check("sampling a key position returns its pose", offKey == 0, offKey)

		local buried = 0
		for _, clip in clips do
			for _, key in clip.keys do
				local _, parts = solved(key.pose)
				for _, frame in parts do
					if frame.Position.Y < 0 then
						buried += 1
					end
				end
			end
		end
		check("no part center is below the floor in any key pose", buried == 0, buried)

		local mid = sampled("Jab", 0.5)
		local before = sampled("Jab", 0)
		local after = sampled("Jab", 1)
		check(
			"jab startup moves between its end poses",
			not samePose(mid, before, 1e-3) and not samePose(mid, after, 1e-3)
		)
	end

	-- The animation must visibly connect wherever the hit detection says an attack can, with the limb the move names.
	do
		for _, move in FightConfig.Moves do
			local clipName = move.clip
			local clip = clips[clipName]
			check(`{move.name} has a phase clip`, clip ~= nil and clip.kind == "phase")
			if clip ~= nil then
				local striker = move.striker
				local needed = neededReach(move)
				local atContact = strikerFront(clipName, 1.5, striker)
				check(`{move.name} reaches the hit range during active frames`, atContact >= needed, atContact)
				check(
					`{move.name} holds its extension through the active phase`,
					strikerFront(clipName, 1, striker) >= needed and strikerFront(clipName, 2, striker) >= needed
				)
				local travel = strikerFront(clipName, 1, striker) - strikerFront(clipName, 0, striker)
				check(`{move.name} travels at least a stud from the stance to the strike`, travel >= 1, travel)
				check(`{move.name} recovers to the stance`, samePose(sampled(clipName, 3), sampled("Idle", 0), EPSILON))

				-- A southpaw robot (the opponent, drawn mirrored) does the same move with the other limb. Effects and
				-- trails have to follow that limb, or they sit on an idle hand while the real one connects.
				local twin = twinOf(striker)
				local _, southpaw = solved(sampled(clipName, 1.5), true)
				local twinFront = RobotSkeleton.frontExtent(rig, southpaw, twin)
				local namedFront = RobotSkeleton.frontExtent(rig, southpaw, striker)
				check(`{move.name} is thrown by the {twin} when drawn as a southpaw`, twinFront >= needed, twinFront)
				check(
					`{move.name} leaves the {striker} back when drawn as a southpaw`,
					namedFront < needed - 1,
					namedFront
				)
			end
		end
	end

	-- Animator: each simulation state picks the right clip, and attacks follow their locked aim.
	do
		local function play(
			fighter: FightSim.Fighter,
			facingX: number?,
			facingZ: number?
		): (RobotAnimator.Animator, number)
			local animator = RobotAnimator.new(rig, clips)
			local _, yaw = RobotAnimator.update(animator, fighter, facingX or 1, facingZ or 0, 1 / 60)
			return animator, yaw
		end
		local function clipFor(fighter: FightSim.Fighter): string
			return (play(fighter)).clipKey
		end

		check("idle plays the idle loop", clipFor(fighterIn(State.Idle)) == "Idle")
		check("walking plays the walk cycle", clipFor(fighterIn(State.Idle, { vx = 5 })) == "Walk")
		check("guard plays the guard pose", clipFor(fighterIn(State.Guard)) == "Guard")
		check("jab plays the jab", clipFor(fighterIn(State.Attack, { moveId = FightConfig.JabMoveId })) == "Jab")
		check(
			"straight plays the straight",
			clipFor(fighterIn(State.Attack, { moveId = FightConfig.StraightMoveId })) == "Straight"
		)
		check(
			"snap kick plays the snap kick",
			clipFor(fighterIn(State.Attack, { moveId = FightConfig.SnapKickMoveId })) == "SnapKick"
		)
		check(
			"power kick plays the power kick",
			clipFor(fighterIn(State.Attack, { moveId = FightConfig.PowerKickMoveId })) == "PowerKick"
		)
		check("a short stun is a light hit", clipFor(fighterIn(State.Hitstun, { stun = jab.hitstun })) == "HitLight")
		check(
			"a long stun is a heavy hit",
			clipFor(fighterIn(State.Hitstun, { stun = straight.hitstun })) == "HitHeavy"
		)
		check("blockstun plays the block reaction", clipFor(fighterIn(State.Blockstun, { stun = 14 })) == "Block")
		check("dash plays the dash", clipFor(fighterIn(State.Dash, { dashFwd = 1 })) == "Dash")
		check("knockout plays the fall", clipFor(fighterIn(State.KO)) == "Ko")

		-- Facing +X, the fighter's right is +Z. An attack aimed 30 degrees to the right turns the robot right.
		local function strikeYaw(aimX: number, aimZ: number): number
			local fighter = fighterIn(
				State.Attack,
				{ moveId = FightConfig.JabMoveId, stateFrame = jab.startup + 1, aimX = aimX, aimZ = aimZ }
			)
			local _, yaw = play(fighter)
			return yaw
		end
		local thirty = math.rad(30)
		check(
			"a locked aim to the right turns the robot right",
			math.abs(strikeYaw(math.cos(thirty), math.sin(thirty)) + thirty) < 1e-3
		)
		check(
			"a locked aim to the left turns the robot left",
			math.abs(strikeYaw(math.cos(thirty), -math.sin(thirty)) - thirty) < 1e-3
		)
		check("an aim straight ahead does not turn the robot", math.abs(strikeYaw(1, 0)) < 1e-6)

		-- The jab's contact pose lands on the first active frame the sim reports.
		local animator = RobotAnimator.new(rig, clips)
		local fighter = fighterIn(State.Attack, { moveId = FightConfig.JabMoveId, stateFrame = jab.startup })
		RobotAnimator.update(animator, fighter, 1, 0, 1)
		check("the jab is fully extended when startup ends", samePose(animator.pose, sampled("Jab", 1), EPSILON))

		-- A fallen robot lies on its back, feet toward the opponent, and stays down.
		local down = fighterIn(State.KO, { stateFrame = 120 })
		local downAnimator = RobotAnimator.new(rig, clips)
		RobotAnimator.update(downAnimator, down, 1, 0, 1)
		local joints = solved(downAnimator.pose)
		local pelvis = rig.jointIndex.Pelvis
		check("a knocked out robot lies on its back", math.abs(downAnimator.pose.rot[pelvis].X - math.rad(88)) < 0.05)
		check(
			"a fallen robot's head is behind its feet",
			joints[rig.jointIndex.Head].Position.Z > joints[rig.jointIndex.FootR].Position.Z + 3
		)
	end

	-- Mirroring swaps left and right for the southpaw view without changing the pose.
	do
		local pose = sampled("Jab", 1.5)
		local plain = solved(pose)
		local mirrored = solved(pose, true)
		local handL = plain[rig.jointIndex.HandL].Position
		local handR = mirrored[rig.jointIndex.HandR].Position
		check(
			"a mirrored pose swaps hands",
			(handR - Vector3.new(-handL.X, handL.Y, handL.Z)).Magnitude < EPSILON,
			handR
		)
		local headPlain = plain[rig.jointIndex.Head].Position
		local headMirrored = mirrored[rig.jointIndex.Head].Position
		check(
			"a mirrored head stays on the center line side-swapped",
			(headMirrored - Vector3.new(-headPlain.X, headPlain.Y, headPlain.Z)).Magnitude < EPSILON
		)
	end

	-- Chassis and kits: a bigger or smaller robot still connects, and every add-on piece sits on a real joint.
	do
		local pose = sampled("Jab", 1.5)
		local scaledJoints = table.create(rig.jointCount, CFrame.identity)
		local scaledParts = table.create(#rig.def.parts, CFrame.identity)
		RobotSkeleton.solve(rig, pose, CFrame.identity, false, scaledJoints, scaledParts, 1.1)
		local _, plainParts = solved(pose)
		local worstOffset, worstTurn = 0, 0
		for index, frame in scaledParts do
			worstOffset = math.max(worstOffset, (frame.Position - plainParts[index].Position * 1.1).Magnitude)
			worstTurn = math.max(
				worstTurn,
				(frame.XVector - plainParts[index].XVector).Magnitude,
				(frame.YVector - plainParts[index].YVector).Magnitude
			)
		end
		check(
			"a scaled robot is the same pose, farther from its feet",
			worstOffset < EPSILON and worstTurn < EPSILON,
			`{worstOffset}, {worstTurn}`
		)

		-- Each chassis' strikes still reach: the limb of the chassis' own frame, and of each premium body for it, drawn at the
		-- chassis' size, gets to the hit range the build has. A smaller robot may stop a little short at the very edge of the
		-- range, which is invisible.
		local drawnAs: { { name: string, frame: string, chassis: number } } = {}
		for index, chassis in Loadout.Chassis do
			table.insert(drawnAs, { name = chassis.name, frame = Looks.Frames[index], chassis = index })
		end
		for _, body in Looks.Bodies do
			if body.frame ~= nil and body.chassis ~= nil then
				table.insert(drawnAs, { name = body.name, frame = body.frame, chassis = body.chassis })
			end
		end
		for _, entry in drawnAs do
			local def = (RobotRigs :: any)[entry.frame]
			if def == nil then
				check(`{entry.name} has a frame`, false)
				continue
			end
			local chassis = Loadout.Chassis[entry.chassis]
			local frameRig = RobotSkeleton.newRig(def)
			local stats = Loadout.stats(Loadout.encode({ chassis = entry.chassis, arms = 1, core = 1, legs = 1 }))
			local shortest = math.huge
			local joints = table.create(frameRig.jointCount, CFrame.identity)
			local parts = table.create(#frameRig.def.parts, CFrame.identity)
			for _, move in stats.moves do
				RobotSkeleton.solve(frameRig, sampled(move.clip, 1.5), CFrame.identity, false, joints, parts)
				local reach = RobotSkeleton.frontExtent(frameRig, parts, move.striker) * chassis.scale
				shortest = math.min(shortest, reach - neededReach(move))
			end
			check(`{entry.name} reaches what its moves can hit`, shortest >= -0.2, shortest)
		end

		-- Kits: the garage names real kits, every kit is used, and every piece is valid.
		local used: { [string]: boolean } = {}
		for _, name in Looks.CrestKits do
			if name ~= "" then
				used[name] = true
			end
		end
		local missing, unused = 0, 0
		for name in used do
			if RobotKits[name] == nil then
				missing += 1
			end
		end
		for name in RobotKits do
			if not used[name] then
				unused += 1
			end
		end
		check("every kit the garage names exists", missing == 0, missing)
		check("every kit is worn by something", unused == 0, unused)

		local shapes = { box = true, cyl = true, ball = true }
		local badPieces, misplaced, asymmetric, biggest = 0, 0, 0, 0
		local restJoints = table.create(rig.jointCount, CFrame.identity)
		local restParts = table.create(#rig.def.parts, CFrame.identity)
		RobotSkeleton.solve(rig, RobotSkeleton.newPose(rig), CFrame.identity, false, restJoints, restParts)
		for _, pieces in RobotKits do
			biggest = math.max(biggest, #pieces)
			for _, piece in pieces do
				local size, center = piece.size, piece.center
				if
					not shapes[piece.shape]
					or rig.def.roles[piece.role] == nil
					or rig.jointIndex[piece.joint] == nil
					or size.X <= 0
					or size.Y <= 0
					or size.Z <= 0
					or math.abs(center.X) > 4
					or center.Y < -0.5
					or center.Y > 9
					or math.abs(center.Z) > 3
				then
					badPieces += 1
				else
					local jointIndex, offset = RobotSkeleton.pieceLocal(rig, piece)
					if ((restJoints[jointIndex] * CFrame.new(offset)).Position - center).Magnitude > EPSILON then
						misplaced += 1
					end
					-- The robot is symmetric, so a piece on one side has a twin on the other.
					local twinJoint = rig.def.joints[rig.mirror[jointIndex]].name
					local found = false
					for _, other in pieces do
						if
							other.joint == twinJoint
							and other.role == piece.role
							and other.shape == piece.shape
							and (other.size - size).Magnitude < 1e-3
							and (other.center - Vector3.new(-center.X, center.Y, center.Z)).Magnitude < 1e-3
							and (other.rot - Vector3.new(piece.rot.X, -piece.rot.Y, -piece.rot.Z)).Magnitude < 1e-2
						then
							found = true
							break
						end
					end
					if not found then
						asymmetric += 1
					end
				end
			end
		end
		check("every kit piece is a valid piece on a real joint", badPieces == 0, badPieces)
		check("kit pieces sit at their authored centers at rest", misplaced == 0, misplaced)
		check("every kit piece has a mirror twin", asymmetric == 0, asymmetric)
		check("no kit is heavier than 40 pieces", biggest <= 40, biggest)
	end

	-- Cost: posing and solving a robot every render frame must stay cheap.
	do
		local animator = RobotAnimator.new(rig, clips)
		local fighter = fighterIn(State.Attack, { moveId = FightConfig.StraightMoveId })
		local joints = table.create(rig.jointCount, CFrame.identity)
		local parts = table.create(#rig.def.parts, CFrame.identity)
		local iterations = 500
		local started = os.clock()
		for frame = 1, iterations do
			fighter.stateFrame = frame % 37
			local pose = RobotAnimator.update(animator, fighter, 1, 0, 1 / 60)
			RobotSkeleton.solve(rig, pose, CFrame.identity, false, joints, parts)
		end
		local perFrameMs = (os.clock() - started) / iterations * 1000
		check("animating and solving a robot costs well under a millisecond", perFrameMs < 0.5, perFrameMs)
	end

	return passed, failures
end
