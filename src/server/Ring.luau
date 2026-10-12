--!strict

-- Server: one ring and the fight in it. The line for the rings (see Rings) decides who fights where; a Ring sets its fight
-- up for them (who holds each seat, their inputs, the robots' builds and the match's commands), stands their characters
-- in its booths, and reads the training keys of the player in its first seat. While nobody wants it, it stands idle or,
-- in the main ring, the bots put on an exhibition (Rings starts those).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local InputSetup = require(ReplicatedStorage.Shared.InputSetup)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Looks = require(ReplicatedStorage.Shared.Looks)
local MatchFlow = require(ReplicatedStorage.Shared.MatchFlow)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Garage = require(script.Parent.Garage)
local WorldBuilder = require(script.Parent.WorldBuilder)

export type Mode = "idle" | "bot" | "training" | "versus" | "exhibition"

export type Ring = {
	index: number,
	spec: FoundryLayout.RingSpec,
	world: WorldBuilder.RingWorld,
	garage: Garage.Garage,
	mode: Mode,
	level: number,
	-- The players in the seats. An empty seat is a bot in a bot match or an exhibition, and the dummy otherwise.
	owners: { [number]: Player? },
	-- Counts the matches started, so the bots' builds change from one to the next.
	matchCount: number,
	-- When the ring last went idle, and when its match reached its end (nil while it is going on).
	idleSince: number,
	overSince: number?,
	-- The match whose result has been reported (its reset token, see Rings), so no result counts twice.
	reported: number,
	-- The first seat's training keys on the last read.
	keys: { next: boolean, reset: boolean, toggle: boolean },
}

local Ring = {}

local DUMMY_MODE_COUNT = 7

-- Stands a character in a booth (`stand`, facing the ring) and keeps it there, or lets it go again (nil).
function Ring.hold(player: Player?, stand: CFrame?)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	if stand == nil then
		root.Anchored = false
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local lift = 3
	if humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15 then
		lift = humanoid.HipHeight + root.Size.Y / 2
	end
	character:PivotTo(stand * CFrame.new(0, lift, 0))
	root.Anchored = true
end

local function requestReset(self: Ring)
	local match = self.world.match
	local token = match:GetAttribute("ResetToken")
	match:SetAttribute("ResetToken", (if type(token) == "number" then token else 0) + 1)
end

-- Puts each seat's robot on its fighter: the player's garage choices, or a bot's pick (the stock ANVIL for the dummy).
-- It happens just before the match resets, so every peer starts it with the same builds.
local function dressFighters(self: Ring, botLevel: number)
	self.matchCount += 1
	-- Each ring draws its bots' builds from a different point in the sequence.
	local pick = self.matchCount + self.index * 7
	for seat = 1, 2 do
		local owner = self.owners[seat]
		local loadout: number
		local look: number
		if owner ~= nil then
			loadout, look = self.garage.codes(owner)
		else
			loadout = Loadout.encode(Loadout.botChoice(botLevel, pick + seat))
			look = Looks.encode(if botLevel > 0 then Looks.botLook(pick + seat) else Looks.default())
		end
		self.world.cores[seat]:SetAttribute("Loadout", loadout)
		self.world.models[seat]:SetAttribute("Look", look)
	end
end

-- Sets the ring up for a mode with `owners` in the seats. Whatever match was on before is never reported after this:
-- its result belongs to whoever played it, and Rings settles it first. A ring that goes idle keeps the robots it had, for
-- the winches to hoist away (the clients draw that, see Hoist); the first time it stands idle it gets stock ones.
function Ring.apply(self: Ring, mode: Mode, level: number, owners: { [number]: Player? })
	self.reported = Ring.generation(self)
	self.mode = mode
	self.level = level
	self.owners = owners
	local world = self.world
	local lobby = mode == "idle"
	local botLevel = if mode == "bot" or mode == "exhibition" then level else 0
	world.match:SetAttribute("Lobby", lobby)
	world.match:SetAttribute("TrainingMode", lobby or mode == "training")
	world.match:SetAttribute("BotLevel", botLevel)
	world.match:SetAttribute("DummyMode", 0)
	for seat = 1, 2 do
		local owner = owners[seat]
		world.models[seat]:SetAttribute("OwnerUserId", if owner ~= nil then owner.UserId else 0)
		world.cores[seat]:SetAttribute("AiMode", if owner ~= nil then 0 elseif botLevel > 0 then 3 else 1)
		Simulation.setInputs(self.index, seat, if owner ~= nil then InputSetup.find(owner) else nil)
	end
	if not lobby or self.matchCount == 0 then
		dressFighters(self, botLevel)
	end
	requestReset(self)
	self.overSince = nil
end

-- The same mode again: a rematch, or training reset to the marks. Like apply, it closes the books on the match before.
function Ring.restart(self: Ring)
	if self.mode == "idle" then
		return
	end
	self.reported = Ring.generation(self)
	dressFighters(self, if self.mode == "bot" or self.mode == "exhibition" then self.level else 0)
	requestReset(self)
	self.overSince = nil
end

-- Seats `owners` for a session and stands them in the booths.
function Ring.seat(self: Ring, mode: Mode, level: number, owners: { [number]: Player? })
	Ring.apply(self, mode, level, owners)
	for seat, owner in owners do
		Ring.hold(owner, self.spec.booths[seat])
	end
end

-- Lets the players go and leaves the ring standing idle.
function Ring.clear(self: Ring, now: number)
	for _, owner in self.owners do
		Ring.hold(owner, nil)
	end
	self.idleSince = now
	Ring.apply(self, "idle", 0, {})
end

-- Which seat a player holds, or nil.
function Ring.seatOf(self: Ring, player: Player): number?
	for seat, owner in self.owners do
		if owner == player then
			return seat
		end
	end
	return nil
end

-- Notes when the match reached its end. Call every tick.
function Ring.update(self: Ring, now: number)
	local over = self.world.match:GetAttribute("Phase") == MatchFlow.Phase.MatchEnd
	if not over then
		self.overSince = nil
	elseif self.overSince == nil then
		self.overSince = now
	end
end

-- Which match the ring is showing: the reset token the simulation last applied. Every match starts with a reset, so it
-- changes with each new match and rematch, and not between rounds.
function Ring.generation(self: Ring): number
	local value = self.world.match:GetAttribute("AppliedReset")
	return if type(value) == "number" then value else 0
end

-- The next scripted dummy, in training.
function Ring.cycleDummy(self: Ring)
	local match = self.world.match
	local dummy = match:GetAttribute("DummyMode")
	match:SetAttribute("DummyMode", ((if type(dummy) == "number" then dummy else 0) + 1) % DUMMY_MODE_COUNT)
end

-- Which training keys the player in the first seat has pressed since the last read: T (the next dummy), R (reset, or a
-- rematch once a match is over) and M (leave). They come through the Input Action System like every other input, so the
-- server only trusts that player and reads their replicated action states.
function Ring.pressedKeys(self: Ring): (boolean, boolean, boolean)
	local owner = self.owners[1]
	local actions = if owner ~= nil then InputSetup.findTraining(owner) else nil
	local keys = self.keys
	if actions == nil then
		keys.next, keys.reset, keys.toggle = false, false, false
		return false, false, false
	end
	local nextDown = actions.next:GetState() :: boolean
	local resetDown = actions.reset:GetState() :: boolean
	local toggleDown = actions.toggle:GetState() :: boolean
	local pressedNext = nextDown and not keys.next
	local pressedReset = resetDown and not keys.reset
	local pressedToggle = toggleDown and not keys.toggle
	keys.next, keys.reset, keys.toggle = nextDown, resetDown, toggleDown
	return pressedNext, pressedReset, pressedToggle
end

function Ring.new(world: WorldBuilder.RingWorld, garage: Garage.Garage, now: number): Ring
	local self: Ring = {
		index = world.index,
		spec = world.spec,
		world = world,
		garage = garage,
		mode = "idle",
		level = 0,
		owners = {},
		matchCount = 0,
		idleSince = now,
		overSince = nil,
		reported = -1,
		keys = { next = false, reset = false, toggle = false },
	}
	Ring.apply(self, "idle", 0, {})
	return self
end

return Ring
