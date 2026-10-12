--!strict

-- Client-only life for the venue: a chase of light along the LED ribbon and twinkling lights in the crowd. Arena tags
-- the parts; this only changes their colors, a few dozen property writes a few times a second. Both speed up with the
-- crowd's excitement, so a big hit visibly sets the whole building off.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FightConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FightConfig"))

export type ArenaFx = {
	-- 0 to 1: how worked up the crowd is.
	setExcitement: (value: number) -> (),
}

local ArenaFx = {}

local RIBBON_BASE = Color3.fromRGB(22, 70, 120)
local RIBBON_HIGHLIGHT = Color3.fromRGB(255, 170, 70)
local RIBBON_STEP = 1 / 15
local RIBBON_SPEED = 0.45
local CROWD_STEP = 1 / 8

type RibbonCell = { part: BasePart, angle: number }
type Twinkle = { part: BasePart, speed: number, offset: number }

function ArenaFx.start(): ArenaFx
	local random = Random.new(7)
	local ribbon: { RibbonCell } = {}
	local twinkles: { Twinkle } = {}
	local excitement = 0

	local function addRibbon(instance: Instance)
		if instance:IsA("BasePart") then
			table.insert(ribbon, { part = instance, angle = math.atan2(instance.Position.Z, instance.Position.X) })
		end
	end
	local function addTwinkle(instance: Instance)
		if instance:IsA("BasePart") then
			table.insert(twinkles, {
				part = instance,
				speed = random:NextNumber(0.6, 2.2),
				offset = random:NextNumber(0, math.pi * 2),
			})
		end
	end
	for _, instance in CollectionService:GetTagged(FightConfig.RibbonTag) do
		addRibbon(instance)
	end
	for _, instance in CollectionService:GetTagged(FightConfig.CrowdLightTag) do
		addTwinkle(instance)
	end
	CollectionService:GetInstanceAddedSignal(FightConfig.RibbonTag):Connect(addRibbon)
	CollectionService:GetInstanceAddedSignal(FightConfig.CrowdLightTag):Connect(addTwinkle)

	-- The clocks advance by the time that passed times the current speed, so changing the speed never makes them jump.
	local ribbonClock = 0
	local crowdClock = 0
	local last = os.clock()
	local nextRibbon = 0
	local nextCrowd = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		ribbonClock += dt * RIBBON_SPEED * (1 + 2.2 * excitement)
		crowdClock += dt * (1 + 2.5 * excitement)
		if now >= nextRibbon then
			nextRibbon = now + RIBBON_STEP
			-- Two highlights travel around the ring.
			for _, cell in ribbon do
				local pulse = math.max(0, math.cos((cell.angle - ribbonClock) * 2)) ^ 6
				cell.part.Color = RIBBON_BASE:Lerp(RIBBON_HIGHLIGHT, pulse)
			end
		end
		if now >= nextCrowd then
			nextCrowd = now + CROWD_STEP
			-- Mostly lit, with each light dipping now and then.
			for _, twinkle in twinkles do
				local wave = 0.5 + 0.5 * math.sin(crowdClock * twinkle.speed + twinkle.offset)
				twinkle.part.Transparency = 0.05 + 0.6 * (1 - wave) ^ 3
			end
		end
	end)

	return {
		setExcitement = function(value: number)
			excitement = math.clamp(value, 0, 1)
		end,
	}
end

return ArenaFx
