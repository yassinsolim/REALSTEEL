--!strict

-- Client-only combat effects: sparks, a flash and a shock ring where a hit or block lands, dust on dashes, and the
-- camera shake that goes with them. They are triggered by watching the rendered simulation state, so nothing here can
-- change the fight.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local FightSim = require(Shared:WaitForChild("FightSim"))
local FighterView = require(script.Parent:WaitForChild("FighterView"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Snapshot = {
	hitstop: number,
	state: number,
}

export type Effects = {
	folder: Folder,
	sfx: Sfx.Sfx,
	previous: { [number]: Snapshot },
	lastImpact: { [number]: number },
	lastSwing: { [number]: number },
	-- One trail per striking limb, per fighter slot.
	trails: { [number]: { [string]: Trail } },
	-- Camera shake in studs, decaying every frame.
	shake: number,
	-- A white flash over the screen, 0 to 1, that dies away in a blink.
	flash: number,
	-- A brief push-in of the camera on every hit, 0 to 1.
	punch: number,
	-- How worked up the crowd is, 0 to 1, fading over a few seconds.
	excitement: number,
	-- Whether big hits here set the crowd roaring. The roar has one cooldown for the whole hall, so only the fight the
	-- player follows may spend it.
	cheers: boolean,
}

local Effects = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
-- A second impact on the same fighter inside this window is a rollback replaying the same hit, not a new one.
local IMPACT_COOLDOWN = 0.12
local SHAKE_DECAY = 0.12
local HEAVY_HITSTOP = 8
local SWING_COOLDOWN = 0.1
local STRIKERS = { "HandL", "HandR", "FootL", "FootR" }
-- Seconds into the whoosh sound where it peaks, so the swell lands as the strike does.
local WHOOSH_PEAK = 0.18
local SWING_PITCH = { 1.3, 1.05, 1.15, 0.85 }

local HIT_COLOR = Color3.fromRGB(255, 190, 80)
local BLOCK_COLOR = Color3.fromRGB(130, 200, 255)
local KO_COLOR = Color3.fromRGB(255, 120, 60)

function Effects.new(sfx: Sfx.Sfx): Effects
	local folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = Workspace
	return {
		folder = folder,
		sfx = sfx,
		previous = {},
		lastImpact = {},
		lastSwing = {},
		trails = {},
		shake = 0,
		flash = 0,
		punch = 0,
		excitement = 0,
		cheers = true,
	}
end

local function buildTrail(part: BasePart, accent: Color3): Trail
	local half = part.Size.Y * 0.45
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, half, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -half, 0)
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.2
	trail.MinLength = 0.04
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Enabled = false
	trail.Parent = part
	return trail
end

-- Builds the strike trails on both robots. Call once the robots exist; `accents` follow the team colors.
function Effects.attach(self: Effects, views: { FighterView.View }, accents: { Color3 })
	for slot, view in views do
		local set: { [string]: Trail } = {}
		for _, striker in STRIKERS do
			local part = view.robot.folder:FindFirstChild(striker .. "_Armor")
			if part ~= nil and part:IsA("BasePart") then
				set[striker] = buildTrail(part, accents[slot])
			end
		end
		self.trails[slot] = set
	end
end

function Effects.setAccent(self: Effects, slot: number, accent: Color3)
	local set = self.trails[slot]
	if set == nil then
		return
	end
	for _, trail in set do
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
	end
end

local function anchorPart(self: Effects, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "Fx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = self.folder
	return part
end

-- Orients a part so its top face points along `direction`, which is where a ParticleEmitter sends its particles.
local function facing(position: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(position, position + direction) * CFrame.Angles(math.rad(-90), 0, 0)
end

local function sparkEmitter(parent: Part, color: Color3, speed: NumberRange, spread: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = Vector3.new(0, -45, 0)
	emitter.Drag = 2.5
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

local function tweenAndClean(instance: Instance, info: TweenInfo, goal: { [string]: any })
	TweenService:Create(instance, info, goal):Play()
	Debris:AddItem(instance, info.Time + 0.1)
end

-- Where a hit lands: a bright flash, an expanding ring, and a spray of sparks back toward the attacker.
local function impact(self: Effects, position: Vector3, toward: Vector3, color: Color3, scale: number, sparks: number)
	local flash = Instance.new("Part")
	flash.Name = "Flash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = color:Lerp(Color3.new(1, 1, 1), 0.55)
	flash.Size = Vector3.one * 0.6 * scale
	flash.Position = position
	flash.Transparency = 0.2
	flash.Parent = self.folder
	tweenAndClean(
		flash,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 3.2 * scale, Transparency = 1 }
	)

	-- The ring is an outline drawn facing the camera. A flat disc facing the attacker is edge-on to the broadside camera
	-- and shows up as a slab cutting through both robots.
	local ringPart = anchorPart(self, CFrame.new(position))
	local ring = Instance.new("BillboardGui")
	ring.Name = "Ring"
	ring.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ring.Adornee = ringPart
	ring.AlwaysOnTop = true
	ring.LightInfluence = 0
	ring.Size = UDim2.fromScale(scale, scale)
	ring.Parent = ringPart
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundTransparency = 1
	circle.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local stroke = Instance.new("UIStroke")
	stroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
	stroke.Thickness = 6
	stroke.Parent = circle
	local grow = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenAndClean(ring, grow, { Size = UDim2.fromScale(5.5 * scale, 5.5 * scale) })
	tweenAndClean(stroke, grow, { Thickness = 1, Transparency = 1 })
	Debris:AddItem(ringPart, 0.5)

	local emitterPart = anchorPart(self, facing(position, -toward))
	local speed = math.sqrt(scale)
	local emitter = sparkEmitter(emitterPart, color, NumberRange.new(14 * speed, 30 * speed), 75, 1.6 * scale)
	emitter:Emit(sparks)
	-- One big star right at the point of contact.
	local flare = sparkEmitter(emitterPart, Color3.new(1, 1, 1), NumberRange.new(0, 0), 0, 7 * scale)
	flare.Lifetime = NumberRange.new(0.12, 0.16)
	flare.Acceleration = Vector3.zero
	flare.RotSpeed = NumberRange.new(0, 0)
	flare:Emit(1)
	Debris:AddItem(emitterPart, 1)
end

local function dust(self: Effects, position: Vector3)
	local part = anchorPart(self, facing(position + Vector3.new(0, 0.2, 0), Vector3.yAxis))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 126, 142))
	emitter.LightEmission = 0.1
	emitter.LightInfluence = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(85, 85)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(7)
	Debris:AddItem(part, 1.5)
end

-- Robots touch down off their winches (see Hoist): both together at the end of the drop that starts a match, or one at
-- a time when training lowers them.
function Effects.land(self: Effects, views: { FighterView.View })
	for _, view in views do
		dust(self, FighterView.groundPoint(view))
	end
	self.shake = math.max(self.shake, 0.22)
	self.excitement = math.min(self.excitement + 0.2, 1)
	Sfx.play(self.sfx, "clank", 1, 0.62)
	Sfx.play(self.sfx, "heavy", 0.7, 0.7)
end

-- Reads one fighter's view of a frame. `defender` is the fighter whose hitstop just rose, `attacker` the other.
local function onImpact(
	self: Effects,
	defender: FightSim.Fighter,
	attacker: FightSim.Fighter,
	defenderView: FighterView.View,
	attackerView: FighterView.View
)
	local chest = FighterView.chestPoint(defenderView)
	local move = attacker.stats.moves[attacker.moveId]
	local point = chest
	local toward = Vector3.new(attacker.aimX, 0, attacker.aimZ)
	if attacker.state == FightSim.State.Attack and move ~= nil then
		point = FighterView.strikePoint(attackerView, move.striker) or chest
	else
		local offset = Vector3.new(attacker.x - defender.x, 0, attacker.z - defender.z)
		toward = if offset.Magnitude > 1e-3 then -offset.Unit else Vector3.xAxis
	end
	if toward.Magnitude < 1e-3 then
		toward = Vector3.xAxis
	end
	toward = toward.Unit

	local now = os.clock()
	if defender.state == FightSim.State.KO then
		impact(self, point, toward, KO_COLOR, 2.2, 48)
		self.shake = math.max(self.shake, 0.6)
		self.flash = 1
		self.punch = 1
		self.excitement = 1
		Sfx.play(self.sfx, "boom", 1, 1)
		Sfx.play(self.sfx, "heavy", 1.1, 0.8)
		if self.cheers then
			Sfx.surge(self.sfx, now, 1)
		end
	elseif defender.state == FightSim.State.Blockstun then
		impact(self, point, toward, BLOCK_COLOR, 0.7, 12)
		self.shake = math.max(self.shake, 0.05)
		self.punch = math.max(self.punch, 0.12)
		self.excitement = math.min(self.excitement + 0.05, 1)
		Sfx.play(self.sfx, "clank", 1, if move ~= nil and move.damage > 15 then 0.95 else 1.2)
	else
		local heavy = defender.hitstop >= HEAVY_HITSTOP
		impact(self, point, toward, HIT_COLOR, if heavy then 1.5 else 1, if heavy then 30 else 18)
		self.shake = math.max(self.shake, if heavy then 0.3 else 0.12)
		self.punch = math.max(self.punch, if heavy then 0.7 else 0.35)
		self.flash = math.max(self.flash, if heavy then 0.22 else 0.06)
		self.excitement = math.min(self.excitement + (if heavy then 0.4 else 0.12), 1)
		Sfx.play(self.sfx, if heavy then "heavy" else "punch", 1, if heavy then 0.95 else 1)
		if heavy and self.cheers then
			Sfx.surge(self.sfx, now, 0.7)
		end
	end
end

-- Call once per render frame, after both fighters' views are updated. Returns the camera shake amplitude in studs.
function Effects.update(
	self: Effects,
	fighters: { FightSim.Fighter },
	views: { FighterView.View },
	now: number,
	dt: number
): number
	for slot = 1, 2 do
		local fighter = fighters[slot]
		local other = 3 - slot
		local previous = self.previous[slot]
		if previous ~= nil then
			local stunned = fighter.state == FightSim.State.Hitstun
				or fighter.state == FightSim.State.Blockstun
				or fighter.state == FightSim.State.KO
			if
				stunned
				and fighter.hitstop > previous.hitstop
				and now - (self.lastImpact[slot] or -1) > IMPACT_COOLDOWN
			then
				self.lastImpact[slot] = now
				onImpact(self, fighter, fighters[other], views[slot], views[other])
			end
			if fighter.state == FightSim.State.Dash and previous.state ~= FightSim.State.Dash then
				dust(self, FighterView.groundPoint(views[slot]))
				Sfx.play(self.sfx, "whoosh", 0.6, 0.8)
			end
			-- A swing starts: the whoosh is timed so its swell peaks as the strike lands.
			local move = fighter.stats.moves[fighter.moveId]
			if
				fighter.state == FightSim.State.Attack
				and previous.state ~= FightSim.State.Attack
				and move ~= nil
				and now - (self.lastSwing[slot] or -1) > SWING_COOLDOWN
			then
				self.lastSwing[slot] = now
				Sfx.play(
					self.sfx,
					"whoosh",
					0.5,
					SWING_PITCH[fighter.moveId] or 1,
					math.max(WHOOSH_PEAK - move.startup / FightConfig.SimHz, 0)
				)
			end
		end
		self.previous[slot] = { hitstop = fighter.hitstop, state = fighter.state }

		-- A trail follows the striking limb from just before the hit to just after it.
		local wanted: string? = nil
		if fighter.state == FightSim.State.Attack then
			local move = fighter.stats.moves[fighter.moveId]
			if
				move ~= nil
				and fighter.stateFrame >= move.startup - 3
				and fighter.stateFrame <= move.startup + move.active + 4
			then
				wanted = FighterView.limb(views[slot], move.striker)
			end
		end
		local set = self.trails[slot]
		if set ~= nil then
			for striker, trail in set do
				trail.Enabled = striker == wanted
			end
		end
	end

	self.shake *= math.exp(-dt / SHAKE_DECAY)
	if self.shake < 0.002 then
		self.shake = 0
	end
	self.flash *= math.exp(-dt / 0.07)
	self.punch *= math.exp(-dt / 0.16)
	self.excitement *= math.exp(-dt / 3.5)
	return self.shake
end

return Effects
