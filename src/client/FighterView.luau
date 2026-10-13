--!strict

-- Client-only presentation: draws a fighter's robot from simulation state. Nothing here feeds back into the simulation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local FightSim = require(Shared:WaitForChild("FightSim"))
local RobotAnimator = require(Shared:WaitForChild("RobotAnimator"))
local RobotFrames = require(script.Parent:WaitForChild("RobotFrames"))
local RobotRig = require(script.Parent:WaitForChild("RobotRig"))

-- Every frame the fighters can be drawn as, and the animation set they share (see RobotFrames).
export type Robot = RobotFrames.Library

export type View = {
	model: Model,
	core: Part,
	hitViz: Part,
	robot: RobotRig.RobotRig,
	-- The frames the robot can be drawn as.
	library: Robot,
	animator: RobotAnimator.Animator,
	-- The middle of the fighter's ring in the hall. Simulation positions are relative to it.
	origin: Vector3,
	-- Where the fighter is drawn in its ring: simulation position plus a decaying offset that hides rollback corrections.
	drawX: number,
	drawZ: number,
	offsetX: number,
	offsetZ: number,
	lastX: number,
	lastZ: number,
	lastHp: number,
	lastTime: number,
	ready: boolean,
	-- Whether the robot is drawn as a southpaw, which swaps which limb performs each move.
	mirror: boolean,
	-- The robot's head armor once it has been looked up (see headPoint).
	head: BasePart?,
}

local FighterView = {}

-- Normal movement never exceeds this speed, so a bigger jump in simulation position is a rollback correction.
local SMOOTH_SPEED = 20
local SMOOTH_TIME = 0.09
local DEFAULT_ACCENT = Color3.fromRGB(70, 140, 255)
local HIT_FLASH = Color3.new(1, 1, 1)
local BLOCK_FLASH = Color3.fromRGB(150, 205, 255)
local BREAK_FLASH = Color3.fromRGB(255, 110, 90)
local FLASH_FRAMES = 6

-- `origin` is the middle of the fighter's ring in the hall (the main ring's is the hall's origin).
function FighterView.new(model: Model, robot: Robot, origin: Vector3?): View
	local accent = model:GetAttribute("Accent")
	local frame = RobotFrames.get(robot, nil)
	return {
		model = model,
		core = model:WaitForChild("Core") :: Part,
		hitViz = model:WaitForChild("HitViz") :: Part,
		robot = RobotRig.new(
			model,
			frame.rig,
			if typeof(accent) == "Color3" then accent else DEFAULT_ACCENT,
			frame.template,
			frame.wear
		),
		library = robot,
		animator = RobotAnimator.new(robot.rig, robot.clips),
		origin = origin or Vector3.zero,
		drawX = 0,
		drawZ = 0,
		offsetX = 0,
		offsetZ = 0,
		lastX = 0,
		lastZ = 0,
		lastHp = 0,
		lastTime = 0,
		ready = false,
		mirror = false,
		head = nil,
	}
end

-- Returns the time since the last render frame.
local function updateDrawPosition(view: View, fighter: FightSim.Fighter, now: number): number
	local renderDelta = if view.ready then math.clamp(now - view.lastTime, 1 / 240, 0.1) else 1 / 60
	view.lastTime = now

	if view.ready then
		if view.lastHp <= 0 and fighter.hp > 0 then
			-- A new round teleports fighters to their marks; do not glide.
			view.offsetX = 0
			view.offsetZ = 0
		else
			local jumpX = fighter.x - view.lastX
			local jumpZ = fighter.z - view.lastZ
			local jump = math.sqrt(jumpX * jumpX + jumpZ * jumpZ)
			local bound = SMOOTH_SPEED * renderDelta + 0.05
			if jump > bound then
				local excess = (jump - bound) / jump
				view.offsetX -= jumpX * excess
				view.offsetZ -= jumpZ * excess
			end
		end
	end

	local decay = math.exp(-renderDelta / SMOOTH_TIME)
	view.offsetX *= decay
	view.offsetZ *= decay
	view.lastX = fighter.x
	view.lastZ = fighter.z
	view.lastHp = fighter.hp
	view.ready = true
	view.drawX = fighter.x + view.offsetX
	view.drawZ = fighter.z + view.offsetZ
	return renderDelta
end

local function robotPart(view: View, name: string): BasePart?
	local part = view.robot.folder:FindFirstChild(name)
	if part ~= nil and part:IsA("BasePart") then
		return part
	end
	return nil
end

-- The limb that really performs a move. FightConfig names the limb in the clip (HandL for the jab), but a southpaw
-- robot is drawn with left and right swapped, so there the same motion is done by the other limb.
function FighterView.limb(view: View, striker: string): string
	if not view.mirror then
		return striker
	end
	local base = string.sub(striker, 1, -2)
	local side = string.sub(striker, -1)
	if side == "L" then
		return base .. "R"
	elseif side == "R" then
		return base .. "L"
	end
	return striker
end

-- Where the limb that performs a move is drawn right now, for effects. The striker is a joint name such as HandL.
function FighterView.strikePoint(view: View, striker: string): Vector3?
	local part = robotPart(view, FighterView.limb(view, striker) .. "_Armor")
	return if part ~= nil then part.Position else nil
end

-- Where the fighter's feet are drawn, in the hall.
function FighterView.groundPoint(view: View): Vector3
	return view.origin + Vector3.new(view.drawX, FightConfig.GroundY, view.drawZ)
end

function FighterView.chestPoint(view: View): Vector3
	local part = robotPart(view, "Chest_Armor")
	return if part ~= nil then part.Position else view.origin + Vector3.new(view.drawX, 4.2, view.drawZ)
end

-- Where the robot's head is drawn, or nil before it is built.
function FighterView.headPoint(view: View): Vector3?
	local head = view.head
	if head == nil or head.Parent == nil then
		head = robotPart(view, "Head_Armor")
		view.head = head
	end
	return if head ~= nil then head.Position else nil
end

function FighterView.setPalette(view: View, accent: Color3, armor: Color3?)
	RobotRig.setPalette(view.robot, accent, armor)
end

-- Fades the robot out on this screen alone, from 0 (drawn) to 1 (gone).
function FighterView.setGhost(view: View, amount: number)
	RobotRig.setGhost(view.robot, amount)
end

-- Dresses the robot for the garage's choices: the frame it is drawn as, how big it is, the kits it wears, its paint and
-- the finish of its armor (`finishName` picks the frame's worn-metal textures). Returns whether the robot was rebuilt as
-- another frame, which takes the strike trails with the old parts (see Effects.attachSlot).
function FighterView.dress(
	view: View,
	frameName: string,
	scale: number,
	kits: { string },
	accent: Color3,
	armor: Color3,
	finish: Enum.Material?,
	reflectance: number,
	finishName: string
): boolean
	local frame = RobotFrames.get(view.library, frameName)
	local rebuilt = RobotRig.setFrame(view.robot, frame.rig, frame.template, frame.wear)
	view.head = nil
	RobotRig.setScale(view.robot, scale)
	RobotRig.setKits(view.robot, kits)
	RobotRig.setPalette(view.robot, accent, armor)
	RobotRig.setFinish(view.robot, finish, reflectance, finishName)
	return rebuilt
end

-- mirror draws the robot as a southpaw. The camera sits on the local fighter's right, so mirroring the opponent turns
-- both chests toward it. showHitbox draws the active attack's hit sphere (training). emote names a standing clip to
-- play (Intro, Victory or Slump), or nil. lift draws the robot that far above its mark, hanging from its winch (see
-- Hoist).
function FighterView.update(
	view: View,
	fighter: FightSim.Fighter,
	foe: FightSim.Fighter,
	now: number,
	mirror: boolean,
	showHitbox: boolean,
	emote: string?,
	lift: number?
)
	local dt = updateDrawPosition(view, fighter, now)
	view.mirror = mirror

	local dx = foe.x - fighter.x
	local dz = foe.z - fighter.z
	local dist = math.sqrt(dx * dx + dz * dz)
	local dirX = 1
	local dirZ = 0
	if dist > 1e-4 then
		dirX = dx / dist
		dirZ = dz / dist
	end

	-- Hitstop freezes the fight for a few frames; a small tremor sells the impact.
	local tremor = Vector3.zero
	if fighter.hitstop > 0 then
		tremor = Vector3.new(math.sin(now * 130) * 0.05, 0, math.cos(now * 110) * 0.05)
	end
	local position = FighterView.groundPoint(view)
	local pose, aimYaw = RobotAnimator.update(view.animator, fighter, dirX, dirZ, dt, emote)
	local raised = position + tremor + Vector3.new(0, lift or 0, 0)
	local rootCFrame = CFrame.lookAt(raised, raised + Vector3.new(dirX, 0, dirZ)) * CFrame.Angles(0, aimYaw, 0)
	RobotRig.place(view.robot, pose, rootCFrame, mirror)

	local state = fighter.state
	local flash: Color3? = nil
	if state == FightSim.State.Hitstun and fighter.stateFrame < FLASH_FRAMES then
		flash = HIT_FLASH
	elseif state == FightSim.State.Blockstun and fighter.stateFrame < FLASH_FRAMES then
		flash = BLOCK_FLASH
	elseif state == FightSim.State.GuardBreak and fighter.stateFrame < FLASH_FRAMES * 2 then
		flash = BREAK_FLASH
	end
	RobotRig.setFlash(view.robot, flash)

	if showHitbox and FightSim.attackPhase(fighter) == "active" then
		local move = fighter.stats.moves[fighter.moveId]
		local center = position + Vector3.new(fighter.aimX, 0, fighter.aimZ) * move.reach + Vector3.new(0, 3.2, 0)
		view.hitViz.Size = Vector3.new(0.2, move.hitRadius * 2, move.hitRadius * 2)
		view.hitViz.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		view.hitViz.Transparency = 0.45
	else
		view.hitViz.Transparency = 1
	end
end

return FighterView
