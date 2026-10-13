--!strict

-- Server: the pads in front of the main ring (FoundryLayout.Pads). Several times a second it reads where every player's
-- character stands, keeps the pads' board (see PadRules), and hands whatever a finished countdown asks for to the rings:
-- a bot match or training for one player, a 1v1 for the two on the 1V1 pads. Each pad's state is published for the
-- clients on a folder named after it under `state`.Pads: Holder (the UserId standing on it, or 0) and Ends (when its
-- countdown runs out, in the server's clock, or 0).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FoundryLayout = require(ReplicatedStorage.Shared.FoundryLayout)
local PadRules = require(ReplicatedStorage.Shared.PadRules)

export type Hooks = {
	-- Whether a player is in a ring now, where they hold no pad.
	seated: (player: Player) -> boolean,
	-- A bot or training pad's countdown ran out: "bot" with its level, or "training".
	request: (player: Player, action: string, level: number?) -> (),
	-- The 1V1 pads' countdown ran out; `first` stood on the first seat's pad.
	pair: (first: Player, second: Player) -> (),
}

local Pads = {}

local TICK = 0.1
-- Seconds a player stands on a bot or training pad before it starts, and the two 1V1 players before their fight does.
Pads.SoloDelay = 2
Pads.PairDelay = 3
-- Only where a character stands across the floor decides which pad it is on: nothing it can stand on is above the pads,
-- and a jump on a pad (the root rises about 10 studs) must not count as stepping off. Anything higher than this is not
-- in the hall at all.
local MAX_ROOT_HEIGHT = 30

local function setIfChanged(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

function Pads.new(state: Instance, hooks: Hooks)
	local specs: { PadRules.PadSpec } = {}
	for _, pad in FoundryLayout.Pads do
		table.insert(specs, {
			name = pad.name,
			kind = pad.kind,
			level = pad.level,
			seat = pad.seat,
			x = pad.position.X,
			z = pad.position.Z,
		})
	end
	local board = PadRules.new(specs, FoundryLayout.PadRadius, Pads.SoloDelay, Pads.PairDelay)

	local folder = Instance.new("Folder")
	folder.Name = "Pads"
	local padFolders: { [string]: Folder } = {}
	for _, spec in specs do
		local padFolder = Instance.new("Folder")
		padFolder.Name = spec.name
		padFolder:SetAttribute("Holder", 0)
		padFolder:SetAttribute("Ends", 0)
		padFolder.Parent = folder
		padFolders[spec.name] = padFolder
	end
	folder.Parent = state

	local function tick()
		local now = os.clock()
		local presences: { PadRules.Presence } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
			if root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0 then
				local at = root.Position
				if at.Y < MAX_ROOT_HEIGHT then
					table.insert(presences, { id = player.UserId, x = at.X, z = at.Z, free = not hooks.seated(player) })
				end
			end
		end

		for _, trigger in PadRules.update(board, presences, now) do
			if trigger.kind == "versus" then
				local first = Players:GetPlayerByUserId(trigger.ids[1])
				local second = Players:GetPlayerByUserId(trigger.ids[2])
				if first ~= nil and second ~= nil then
					hooks.pair(first, second)
				end
			else
				local player = Players:GetPlayerByUserId(trigger.ids[1])
				if player ~= nil then
					hooks.request(player, trigger.kind, if trigger.kind == "bot" then trigger.level else nil)
				end
			end
		end

		local serverNow = Workspace:GetServerTimeNow()
		for _, spec in specs do
			local padFolder = padFolders[spec.name]
			local left = PadRules.countdown(board, spec.name, now)
			setIfChanged(padFolder, "Holder", board.state[spec.name].holder)
			-- Rounded, so it only changes when a countdown starts or stops.
			setIfChanged(padFolder, "Ends", if left ~= nil then math.floor((serverNow + left) * 10 + 0.5) / 10 else 0)
		end
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= TICK then
			elapsed = 0
			tick()
		end
	end)
end

return Pads
