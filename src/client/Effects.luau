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
local Looks = require(Shared:WaitForChild("Looks"))
local FighterView = require(script.Parent:WaitForChild("FighterView"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Snapshot = {
	hitstop: number,
	state: number,
	hp: number,
}

export type Effects = {
	folder: Folder,
	sfx: Sfx.Sfx,
	previous: { [number]: Snapshot },
	lastImpact: { [number]: number },
	lastSwing: { [number]: number },
	-- When each fighter last had a guard break, a catch, a slam or a broken throw, so a rollback replaying one does not
	-- set it off twice.
	lastSpecial: { [number]: number },
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
	-- Each fighter's strike trail and impact effect (see Looks.Trails and Looks.Impacts), and its accent color.
	styles: { [number]: Style },
}

type Style = {
	trail: Looks.Trail,
	impact: Looks.Impact,
	accent: Color3,
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
local BREAK_COLOR = Color3.fromRGB(170, 235, 255)
local THROW_COLOR = Color3.fromRGB(255, 150, 230)
local SPECIAL_COOLDOWN = 0.3

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
		lastSpecial = {},
		trails = {},
		shake = 0,
		flash = 0,
		punch = 0,
		excitement = 0,
		cheers = true,
		styles = {},
	}
end

local function rgb(color: Looks.Rgb): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- A trail's colors from its hot core to its tail: the accent's, a trail item's, or this moment's hue for "spectrum".
local function trailColors(style: Style?, accent: Color3, now: number): ColorSequence
	local trail = if style ~= nil then style.trail else nil
	if trail ~= nil and trail.animation == "spectrum" then
		local hue = (now * 0.35) % 1
		return ColorSequence.new(Color3.fromHSV(hue, 0.35, 1), Color3.fromHSV((hue + 0.18) % 1, 0.9, 1))
	end
	if trail ~= nil and trail.from ~= nil and trail.to ~= nil then
		return ColorSequence.new(rgb(trail.from), rgb(trail.to))
	end
	return ColorSequence.new(Color3.new(1, 1, 1), accent)
end

local function buildTrail(part: BasePart, colors: ColorSequence): Trail
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
	trail.Color = colors
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Enabled = false
	trail.Parent = part
	return trail
end

-- Builds the strike trails on one robot, replacing any it had. Call again whenever the robot's parts are rebuilt (a frame
-- swap), since the trails are fastened to them.
function Effects.attachSlot(self: Effects, slot: number, view: FighterView.View, accent: Color3)
	local set: { [string]: Trail } = {}
	local colors = trailColors(self.styles[slot], accent, os.clock())
	for _, striker in STRIKERS do
		local part = view.robot.folder:FindFirstChild(striker .. "_Armor")
		if part ~= nil and part:IsA("BasePart") then
			set[striker] = buildTrail(part, colors)
		end
	end
	local old = self.trails[slot]
	if old ~= nil then
		for _, trail in old do
			local top, bottom = trail.Attachment0, trail.Attachment1
			trail:Destroy()
			if top ~= nil then
				top:Destroy()
			end
			if bottom ~= nil then
				bottom:Destroy()
			end
		end
	end
	self.trails[slot] = set
end

-- Builds the strike trails on both robots. Call once the robots exist; `accents` follow the team colors.
function Effects.attach(self: Effects, views: { FighterView.View }, accents: { Color3 })
	for slot, view in views do
		Effects.attachSlot(self, slot, view, accents[slot])
	end
end

function Effects.setAccent(self: Effects, slot: number, accent: Color3)
	local style = self.styles[slot]
	if style ~= nil then
		style.accent = accent
	end
	local set = self.trails[slot]
	if set == nil then
		return
	end
	local colors = trailColors(style, accent, os.clock())
	for _, trail in set do
		trail.Color = colors
	end
end

-- Puts a fighter's strike trail and impact effect on (see Looks.Trails and Looks.Impacts).
function Effects.setStyle(self: Effects, slot: number, trail: Looks.Trail, impact: Looks.Impact, accent: Color3)
	self.styles[slot] = { trail = trail, impact = impact, accent = accent }
	Effects.setAccent(self, slot, accent)
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

-- What a case item's impact adds on top of the sparks (see Looks.Impacts): a burst of smoke, a second slower ring, or a
-- shower of gold that falls away.
local function flair(self: Effects, kind: string?, position: Vector3, color: Color3, scale: number)
	if kind == nil then
		return
	end
	local part = anchorPart(self, facing(position, Vector3.yAxis))
	if kind == "smoke" then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = SMOKE_TEXTURE
		smoke.Color = ColorSequence.new(color, Color3.fromRGB(60, 44, 40))
		smoke.LightEmission = 0.4
		smoke.LightInfluence = 0.3
		smoke.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * scale),
			NumberSequenceKeypoint.new(1, 3.4 * scale),
		})
		smoke.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(0.5, 0.8)
		smoke.Speed = NumberRange.new(3, 8)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Drag = 4
		smoke.Rate = 0
		smoke.Parent = part
		smoke:Emit(math.floor(8 * scale) + 4)
	elseif kind == "ring" then
		local ring = Instance.new("BillboardGui")
		ring.Adornee = part
		ring.AlwaysOnTop = true
		ring.LightInfluence = 0
		ring.Size = UDim2.fromScale(scale * 2, scale * 2)
		ring.Parent = part
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
		stroke.Color = color
		stroke.Thickness = 10
		stroke.Parent = circle
		local grow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tweenAndClean(ring, grow, { Size = UDim2.fromScale(9 * scale, 9 * scale) })
		tweenAndClean(stroke, grow, { Thickness = 1, Transparency = 1 })
	elseif kind == "coins" then
		local shower = sparkEmitter(part, color, NumberRange.new(8, 18), 80, 0.9 * scale)
		shower.Acceleration = Vector3.new(0, -60, 0)
		shower.Lifetime = NumberRange.new(0.5, 0.9)
		shower:Emit(math.floor(16 * scale) + 6)
	end
	Debris:AddItem(part, 1.2)
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

-- Reads one fighter's view of a frame. `defender` is the fighter whose hitstop just rose, `attacker` the other, and
-- `style` the attacker's look, whose impact effect colors the hits it lands.
local function onImpact(
	self: Effects,
	defender: FightSim.Fighter,
	attacker: FightSim.Fighter,
	defenderView: FighterView.View,
	attackerView: FighterView.View,
	style: Style?
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
	local itemImpact = if style ~= nil then style.impact else nil
	local itemColor = if itemImpact ~= nil and itemImpact.color ~= nil then rgb(itemImpact.color) else nil
	local itemFlair = if itemImpact ~= nil then itemImpact.flair else nil
	if defender.state == FightSim.State.KO then
		impact(self, point, toward, itemColor or KO_COLOR, 2.2, 48)
		flair(self, itemFlair, point, itemColor or KO_COLOR, 2.2)
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
		local scale = if heavy then 1.5 else 1
		impact(self, point, toward, itemColor or HIT_COLOR, scale, if heavy then 30 else 18)
		flair(self, itemFlair, point, itemColor or HIT_COLOR, scale)
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

-- The moments a guard or a throw makes: a guard shattering, a grab catching, a thrown robot hitting the canvas, and two
-- robots shoving out of a throw.
local function onSpecial(
	self: Effects,
	kind: string,
	fighter: FightSim.Fighter,
	other: FightSim.Fighter,
	view: FighterView.View,
	otherView: FighterView.View
)
	local offset = Vector3.new(fighter.x - other.x, 0, fighter.z - other.z)
	local away = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.xAxis
	local now = os.clock()
	if kind == "break" then
		-- The guard shatters: a burst of pale sparks off the chest, a hard flash and a clang that rings out.
		impact(self, FighterView.chestPoint(view), -away, BREAK_COLOR, 1.9, 40)
		self.shake = math.max(self.shake, 0.4)
		self.flash = math.max(self.flash, 0.45)
		self.punch = math.max(self.punch, 0.8)
		self.excitement = math.min(self.excitement + 0.45, 1)
		Sfx.play(self.sfx, "clank", 1.2, 0.62)
		Sfx.play(self.sfx, "boom", 0.55, 1.5)
		if self.cheers then
			Sfx.surge(self.sfx, now, 0.8)
		end
	elseif kind == "catch" then
		local middle = (FighterView.chestPoint(view) + FighterView.chestPoint(otherView)) / 2
		impact(self, middle, -away, THROW_COLOR, 0.8, 10)
		self.shake = math.max(self.shake, 0.08)
		self.punch = math.max(self.punch, 0.3)
		Sfx.play(self.sfx, "clank", 0.9, 1.35)
	elseif kind == "slam" then
		local ground = FighterView.groundPoint(view)
		impact(self, ground + Vector3.new(0, 0.6, 0), Vector3.yAxis, THROW_COLOR, 2, 36)
		dust(self, ground)
		dust(self, ground + away * 1.5)
		self.shake = math.max(self.shake, 0.5)
		self.flash = math.max(self.flash, 0.25)
		self.punch = math.max(self.punch, 0.8)
		self.excitement = math.min(self.excitement + 0.5, 1)
		Sfx.play(self.sfx, "heavy", 1.1, 0.75)
		Sfx.play(self.sfx, "boom", 0.8, 1.1)
		if self.cheers then
			Sfx.surge(self.sfx, now, 0.9)
		end
	elseif kind == "escape" then
		local middle = (FighterView.chestPoint(view) + FighterView.chestPoint(otherView)) / 2
		impact(self, middle, Vector3.yAxis, Color3.new(1, 1, 1), 1.1, 16)
		self.shake = math.max(self.shake, 0.12)
		self.punch = math.max(self.punch, 0.25)
		Sfx.play(self.sfx, "clank", 1, 1.5)
		Sfx.play(self.sfx, "whoosh", 0.5, 1.2)
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
				onImpact(self, fighter, fighters[other], views[slot], views[other], self.styles[other])
			end
			if fighter.state == FightSim.State.Dash and previous.state ~= FightSim.State.Dash then
				dust(self, FighterView.groundPoint(views[slot]))
				Sfx.play(self.sfx, "whoosh", 0.6, 0.8)
			end
			-- A broken guard, a catch, a slam and an escape. Two robots shoving out of a throw make one effect.
			local special: string? = nil
			if fighter.state == FightSim.State.GuardBreak and previous.state ~= FightSim.State.GuardBreak then
				special = "break"
			elseif fighter.state == FightSim.State.Thrown and previous.state ~= FightSim.State.Thrown then
				special = "catch"
			elseif fighter.state == FightSim.State.Thrown and fighter.hp < previous.hp then
				special = "slam"
			elseif
				slot == 1
				and fighter.state == FightSim.State.ThrowBreak
				and previous.state ~= FightSim.State.ThrowBreak
			then
				special = "escape"
			end
			if special ~= nil and now - (self.lastSpecial[slot] or -1) > SPECIAL_COOLDOWN then
				self.lastSpecial[slot] = now
				onSpecial(self, special, fighter, fighters[other], views[slot], views[other])
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
		self.previous[slot] = { hitstop = fighter.hitstop, state = fighter.state, hp = fighter.hp }

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
			local style = self.styles[slot]
			local spectrum = style ~= nil and style.trail.animation == "spectrum"
			local colors = if spectrum and style ~= nil then trailColors(style, style.accent, now) else nil
			for striker, trail in set do
				trail.Enabled = striker == wanted
				if colors ~= nil then
					trail.Color = colors
				end
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
