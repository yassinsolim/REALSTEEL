--!strict

-- The camera while the game drives it. Walking around the hall the player has Roblox's own camera (`release`); the rig
-- takes over for:
--   fight   broadside to the pair, the local fighter on the left, as close as the window and the ring allow, with a low
--           sweep that settles in as the bell rings and a push in on whoever goes down
--   garage  a close-up of the player's robot in its bay that sways a little around its front, the lens shifted so the
--           robot stands in the part of the view the garage panel leaves free
-- Taking over starts from wherever the camera is, so it swoops into place. The fight camera follows the *drawn*
-- positions, so rollback corrections never jolt the view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local MatchFlow = require(Shared:WaitForChild("MatchFlow"))

export type Args = {
	dt: number,
	now: number,
	-- Where the local fighter and the opponent are drawn (x and z), in their ring.
	meX: number,
	meZ: number,
	foeX: number,
	foeZ: number,
	-- The middle of their ring in the hall (the main ring's, the hall's origin, when nil).
	origin: Vector3?,
	touch: boolean,
	phase: number,
	phaseFrame: number,
	-- How the last round ended, and which fighter fell: 0 none, 1 the local fighter, 2 the opponent.
	reason: number,
	fallen: number,
	-- Camera shake in studs.
	shake: number,
	-- Extra push-in from impacts, 0 to 1.
	punch: number,
}

export type GarageArgs = {
	dt: number,
	now: number,
	-- Where the robot stands (its feet) and the horizontal direction it faces.
	at: Vector3,
	facing: Vector3,
	-- How much of the view the garage panel covers, as fractions of half the view's width and of half its height. The
	-- robot is placed in the middle of what is left.
	shiftX: number,
	shiftY: number,
}

export type CameraRig = {
	camera: Camera,
	position: Vector3,
	target: Vector3,
	fov: number,
	-- False while Roblox's camera is in charge; the next update starts from wherever that camera is.
	ready: boolean,
	-- 0 to 1: how far the KO close-up has been pulled in.
	closeUp: number,
	-- 0 to 1: how far the view has slid aside for the result card.
	slide: number,
}

local CameraRig = {}

local FOLLOW_RATE = 8
-- The field of view Roblox's own camera gets back.
local FREE_FOV = 70
-- How the KO close-up plays over the round-end phase, in simulation frames: in, hold, then out.
local CLOSE_IN = 14
local CLOSE_HOLD = 74
local CLOSE_OUT = 150
-- Studs above and below the aim point that always stay in view: a robot with its arms raised, whatever pulled the camera
-- in (the KO push-in, or the barricade stopping it backing off).
local FRAME_HALF_HEIGHT = 5.6
-- Once a round is over the winner stands tall with both arms up (about 9.5 studs), so the aim rises and the frame grows.
-- On touch the bars across the top cover the top fifth of the view and the buttons fill the lower corners, so the aim
-- sits higher still and the lens opens wider, which keeps both the raised fists and the feet in view.
local OVER_AIM = 4.9
local OVER_AIM_TOUCH = 6.2
local OVER_HALF_HEIGHT = 6.8
local OVER_HALF_HEIGHT_TOUCH = 8.8
local MAX_FOV = 72
-- The pair slides left, by this much of the half-width of the view, once the result card is about to show.
local RESULT_SHIFT = 0.4
local RESULT_SLIDE_FRAME = 30
-- The garage close-up: how far off the camera stands, how high above the robot's feet it is and what it looks at, and how
-- it sways around the front of the robot (an angle from straight ahead, in radians). The sway stays small so the bay's
-- side columns never come between the camera and the robot.
local GARAGE_DISTANCE = 13.5
local GARAGE_FAR = 22
local GARAGE_HEIGHT = 4.0
local GARAGE_AIM = 3.6
local GARAGE_FOV = 42
local GARAGE_MAX_FOV = 60
local GARAGE_ANGLE = 0.35
local GARAGE_SWAY = 0.2
local GARAGE_SWAY_SPEED = 0.35
-- The room a robot needs: half its width with its arms out, and its height with its fists up and some air above them.
-- The camera backs off, and widens its lens, when the part of the view the panel leaves free is too small for that.
local GARAGE_HALF_WIDTH = 3.6
local GARAGE_TALL = 10

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function CameraRig.new(camera: Camera): CameraRig
	return {
		camera = camera,
		position = Vector3.zero,
		target = Vector3.zero,
		fov = 48,
		ready = false,
		closeUp = 0,
		slide = 0,
	}
end

-- Hands the camera back to Roblox, following `subject` (the local character's Humanoid).
function CameraRig.release(self: CameraRig, subject: Humanoid?)
	local camera = self.camera
	if camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = FREE_FOV
	end
	if subject ~= nil and camera.CameraSubject ~= subject then
		camera.CameraSubject = subject
	end
	self.ready = false
	self.closeUp = 0
	self.slide = 0
end

-- Eases toward where the camera should be, starting from where it is when the rig takes over, and applies the shake.
local function apply(
	self: CameraRig,
	dt: number,
	now: number,
	position: Vector3,
	target: Vector3,
	fov: number,
	shake: number,
	punch: number
)
	local camera = self.camera
	if not self.ready then
		local current = camera.CFrame
		self.position = current.Position
		self.target = current.Position + current.LookVector * (target - position).Magnitude
		self.fov = camera.FieldOfView
		self.ready = true
	end
	local alpha = 1 - math.exp(-dt * FOLLOW_RATE)
	self.position = self.position:Lerp(position, alpha)
	self.target = self.target:Lerp(target, alpha)
	self.fov += (fov - self.fov) * alpha

	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- Hits shake the view and pull the lens in a little.
	local jitter = Vector3.zero
	if shake > 0 then
		jitter = Vector3.new(math.noise(now * 38, 0.3), math.noise(0.7, now * 41), math.noise(now * 35, 9.1)) * shake
	end
	camera.FieldOfView = self.fov - shake * 6 - punch * 2.5
	camera.CFrame = CFrame.lookAt(self.position + jitter, self.target)
end

-- The most the camera may back off along its viewing line so it stays inside the barricade.
local function reachAlong(midX: number, midZ: number, lookX: number, lookZ: number): number
	local along = midX * lookX + midZ * lookZ
	local inside = along * along
		- (midX * midX + midZ * midZ)
		+ FightConfig.CameraMaxRadius * FightConfig.CameraMaxRadius
	return along + math.sqrt(math.max(inside, 0))
end

function CameraRig.update(self: CameraRig, args: Args)
	local camera = self.camera
	local midX = (args.meX + args.foeX) / 2
	local midZ = (args.meZ + args.foeZ) / 2
	local dx = args.foeX - args.meX
	local dz = args.foeZ - args.meZ
	local dist = math.sqrt(dx * dx + dz * dz)
	local dirX = 1
	local dirZ = 0
	if dist > 1e-4 then
		dirX = dx / dist
		dirZ = dz / dist
	end
	-- Broadside: the viewing direction is perpendicular to the line between the fighters.
	local lookX = dirZ
	local lookZ = -dirX

	-- Touch layouts have the Roblox top bar and the health bars across the top, and the controls sit in the bottom
	-- corners, so the pair is aimed higher to sit low and central, clear of both.
	local aim = if args.touch then 5 else 3.5
	local baseFov = if args.touch then 54 else 48
	local viewport = camera.ViewportSize
	-- Close enough for the robots to fill the frame, backed off when the window is too narrow to fit both across,
	-- and never past the barricade.
	local halfWidth = math.tan(math.rad(baseFov / 2)) * viewport.X / math.max(viewport.Y, 1)
	local distance = math.max(math.clamp(dist * 1.2 + 8, 12, 22), (dist + 10) / (2 * halfWidth))
	distance = math.max(math.min(distance, reachAlong(midX, midZ, lookX, lookZ)), 9)
	local height = 2.3
	local sweep = 0

	if args.phase == MatchFlow.Phase.Intro then
		-- Start wide, high and off to one side; settle in front of the fighters by the time FIGHT! shows.
		local progress = easeOut(math.clamp(args.phaseFrame / (FightConfig.Match.introFrames * 0.8), 0, 1))
		distance *= 1 + 0.42 * (1 - progress)
		height += 3.2 * (1 - progress)
		sweep = math.rad(34) * (1 - progress)
		baseFov += 10 * (1 - progress)
	end

	-- The KO close-up: in over the freeze, held while the robot falls, out as the winner celebrates.
	local closeTarget = 0
	if args.phase == MatchFlow.Phase.RoundEnd and args.reason == MatchFlow.Reason.KO then
		local f = args.phaseFrame
		if f < CLOSE_IN then
			closeTarget = smooth(f / CLOSE_IN)
		elseif f < CLOSE_HOLD then
			closeTarget = 1
		else
			closeTarget = 1 - smooth((f - CLOSE_HOLD) / (CLOSE_OUT - CLOSE_HOLD))
		end
	end
	self.closeUp += (closeTarget - self.closeUp) * (1 - math.exp(-args.dt * 12))

	local focusX = midX
	local focusZ = midZ
	local focusY = aim
	if args.fallen ~= 0 and self.closeUp > 0.001 then
		local fx = if args.fallen == 1 then args.meX else args.foeX
		local fz = if args.fallen == 1 then args.meZ else args.foeZ
		focusX += (fx - focusX) * 0.45 * self.closeUp
		focusZ += (fz - focusZ) * 0.45 * self.closeUp
		focusY = aim + 0.6 * self.closeUp
		distance *= 1 - 0.1 * self.closeUp
		baseFov -= 3 * self.closeUp
	end
	-- The round is over: the winner stands tall, so aim higher and frame more.
	local over = args.phase == MatchFlow.Phase.RoundEnd or args.phase == MatchFlow.Phase.MatchEnd
	if over then
		focusY = math.max(focusY, if args.touch then OVER_AIM_TOUCH else OVER_AIM)
	end
	distance *= 1 - 0.07 * args.punch
	-- Keep both robots whole in the frame: widen the lens when the camera cannot back off any further.
	local halfHeight = FRAME_HALF_HEIGHT
	if over then
		halfHeight = if args.touch then OVER_HALF_HEIGHT_TOUCH else OVER_HALF_HEIGHT
	end
	local fitFov = math.deg(2 * math.atan(halfHeight / distance))
	baseFov = math.max(baseFov, math.min(fitFov, MAX_FOV))

	-- A wide view shows the result card on the right, so the pair slides over to the left of the frame.
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local wantSlide = if args.phase == MatchFlow.Phase.MatchEnd
			and args.phaseFrame >= RESULT_SLIDE_FRAME
			and viewport.X >= FightConfig.ResultMinWidth
			and aspect >= FightConfig.ResultMinAspect
		then 1
		else 0
	self.slide += (wantSlide - self.slide) * (1 - math.exp(-args.dt * 4))
	if self.slide > 0.001 then
		local reach = distance * math.tan(math.rad(baseFov / 2)) * aspect
		-- The view's right-hand direction. There is no intro sweep at the end of a match, so it is the look direction.
		focusX -= lookZ * reach * RESULT_SHIFT * self.slide
		focusZ += lookX * reach * RESULT_SHIFT * self.slide
	end

	-- Rotate the viewing direction around the focus for the intro sweep.
	local cosS = math.cos(sweep)
	local sinS = math.sin(sweep)
	local viewX = lookX * cosS - lookZ * sinS
	local viewZ = lookX * sinS + lookZ * cosS
	-- Everything above is in the ring's own coordinates; the ring may stand anywhere in the hall.
	local origin = args.origin or Vector3.zero
	local target = origin + Vector3.new(focusX, focusY, focusZ)
	local position = origin + Vector3.new(focusX - viewX * distance, height, focusZ - viewZ * distance)
	apply(self, args.dt, args.now, position, target, baseFov, args.shake, args.punch)
end

-- The garage's close-up of a robot standing at `args.at`.
function CameraRig.garage(self: CameraRig, args: GarageArgs)
	local viewport = self.camera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local tanBase = math.tan(math.rad(GARAGE_FOV / 2))
	local tanMax = math.tan(math.rad(GARAGE_MAX_FOV / 2))
	local freeX = math.max(1 - args.shiftX, 0.2)
	local freeY = math.max(1 - args.shiftY, 0.25)
	local distance = math.clamp(GARAGE_HALF_WIDTH / (tanBase * aspect * freeX), GARAGE_DISTANCE, GARAGE_FAR)
	-- The lens opens up before the camera backs off any further.
	local tanFit = GARAGE_TALL / (2 * distance * freeY)
	if tanFit > tanMax then
		distance = math.min(GARAGE_TALL / (2 * tanMax * freeY), GARAGE_FAR)
		tanFit = math.min(GARAGE_TALL / (2 * distance * freeY), tanMax)
	end
	local tanHalf = math.max(tanBase, tanFit)
	local halfHeight = distance * tanHalf
	local halfWidth = halfHeight * aspect

	-- The camera stands in front of the robot, a little off to its right-hand side, which turns the robot's chest toward
	-- the left of the screen and the panel.
	local facing = Vector3.new(args.facing.X, 0, args.facing.Z)
	facing = if facing.Magnitude > 1e-4 then facing.Unit else Vector3.xAxis
	local angle = GARAGE_ANGLE + GARAGE_SWAY * math.sin(args.now * GARAGE_SWAY_SPEED)
	local cosA = math.cos(angle)
	local sinA = math.sin(angle)
	local offsetX = cosA * facing.X + sinA * facing.Z
	local offsetZ = cosA * facing.Z - sinA * facing.X
	-- Moving the camera and its target together, to the left and down, puts the robot to the right and up on screen
	-- without turning the view.
	local slideX = -halfWidth * args.shiftX
	local slideY = -halfHeight * args.shiftY
	local at = args.at
	local target = Vector3.new(at.X + offsetZ * slideX, at.Y + GARAGE_AIM + slideY, at.Z - offsetX * slideX)
	local position = Vector3.new(
		at.X + offsetX * distance + offsetZ * slideX,
		at.Y + GARAGE_HEIGHT + slideY,
		at.Z + offsetZ * distance - offsetX * slideX
	)
	apply(self, args.dt, args.now, position, target, math.deg(2 * math.atan(tanHalf)), 0, 0)
end

return CameraRig
