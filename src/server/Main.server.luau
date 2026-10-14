--!strict

-- Server: builds THE FOUNDRY, runs the fight simulation for every ring, and wires every player to their garage, their bay
-- in the hall, the pads in front of the main ring and the line for the rings (see Rings and Pads).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HallWalk = require(ReplicatedStorage.Shared.HallWalk)
local InputSetup = require(ReplicatedStorage.Shared.InputSetup)
local Simulation = require(ReplicatedStorage.Shared.Simulation)
local Garage = require(script.Parent.Garage)
local Pads = require(script.Parent.Pads)
local Records = require(script.Parent.Records)
local RobotLibrary = require(script.Parent.RobotLibrary)
local Rings = require(script.Parent.Rings)
local Wallet = require(script.Parent.Wallet)
local WorldBuilder = require(script.Parent.WorldBuilder)

local MENU_COOLDOWN = 0.2
local NAME_LENGTH = 16

-- The hall comes first, before anything that can wait. A live server is still starting up when its first player joins,
-- and that player's character spawns as soon as they do: it must find the catwalk under it, not the void.
local world = WorldBuilder.build()
for _, ring in world.rings do
	-- The clients number the rings the same way, from their Index attribute.
	local index = Simulation.addRing(ring.cores, ring.match)
	assert(index == ring.index, "rings must be added in order")
end
Simulation.start()
-- Characters walk where the server hears their players' controls (see HallWalk). Nothing below depends on it.
local walking, walkingError = pcall(HallWalk.start)
if not walking then
	warn("[REALSTEEL] Walking in the hall could not start: " .. tostring(walkingError))
end
-- The robot models download in the background. The clients wait for them (see RobotFrames) before they draw any robot.
task.spawn(RobotLibrary.preload)

-- The hall's state for the clients (see Rings).
local state = Instance.new("Folder")
state.Name = "FoundryState"
state.Parent = ReplicatedStorage

-- The menu is the one thing that is not a fight input: a client asks for a ring here and the server decides.
local menu = Instance.new("RemoteEvent")
menu.Name = "Menu"
menu.Parent = ReplicatedStorage

-- A garage change reaches the fighters when the player's next session in a ring starts, so there is nothing to do here.
local garage = Garage.new(function() end)
-- Coins and shop items (see Wallet). What a player owns decides what their garage may put on their robot, and a
-- purchase shows on it at once.
local wallet = Wallet.new(function(player: Player)
	garage.refresh(player)
end)
garage.setOwnership(wallet.owns)
MarketplaceService.ProcessReceipt = wallet.processReceipt
-- Every finished bot match and 1v1 goes on its players' records, and 1v1s decide the champion (see Records); it pays
-- them coins too.
local records = Records.new(state)
local rings = Rings.new(world, garage, state, function(mode: string, level: number, owners, winner: number)
	records.matchEnded({ mode = mode, level = level, owners = owners, winner = winner })
	wallet.matchEnded(mode, level, owners, winner)
end)
-- The pads in front of the main ring start a fight for whoever stands on them (see Pads).
Pads.new(state, { seated = rings.seated, request = rings.request, pair = rings.pair })
game:BindToClose(function()
	-- Matches already won are reported and nothing after, so the players the shutdown removes forfeit nothing; only then
	-- is everything written, records and wallets side by side.
	rings.close()
	local walletsSaved = false
	task.spawn(function()
		wallet.saveAll()
		walletsSaved = true
	end)
	records.saveAll()
	while not walletsSaved do
		task.wait(0.2)
	end
end)

-- Every player gets a bay for their robot. With more players than bays, the latecomers simply have none.
local bayOwners: { [number]: Player? } = {}

local function claimBay(player: Player)
	for _, bay in world.hall.bays do
		if bayOwners[bay.index] == nil then
			bayOwners[bay.index] = player
			bay.nameplate.Text = string.upper(string.sub(player.DisplayName, 1, NAME_LENGTH))
			bay.nameplate.TextColor3 = Color3.new(1, 1, 1)
			player:SetAttribute("Bay", bay.index)
			return
		end
	end
	player:SetAttribute("Bay", 0)
end

local function freeBay(player: Player)
	for _, bay in world.hall.bays do
		if bayOwners[bay.index] == player then
			bayOwners[bay.index] = nil
			bay.nameplate.Text = "OPEN BAY"
			bay.nameplate.TextColor3 = Color3.fromRGB(140, 154, 184)
		end
	end
end

local lastRequest: { [Player]: number } = {}

local function added(player: Player)
	wallet.add(player)
	garage.add(player)
	records.add(player)
	InputSetup.build(player)
	claimBay(player)
	player.CharacterAdded:Connect(function()
		rings.characterAdded(player)
	end)
end

Players.PlayerAdded:Connect(added)
Players.PlayerRemoving:Connect(function(player: Player)
	lastRequest[player] = nil
	-- Out of the line and the rings first: saving waits on the DataStore, and nobody should be held in a booth, or handed
	-- a ring, meanwhile.
	rings.remove(player)
	freeBay(player)
	records.remove(player)
	wallet.remove(player)
	garage.remove(player)
end)
for _, player in Players:GetPlayers() do
	added(player)
end

menu.OnServerEvent:Connect(function(player: Player, action: unknown, level: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < MENU_COOLDOWN then
		return
	end
	lastRequest[player] = now
	rings.request(player, action, if typeof(level) == "number" then level else nil)
end)

-- AiMode 2 stands in for a remote human in a ring's second seat: inputs arrive as replicated state the predicting
-- client cannot know ahead.
local rng = Random.new(1234)
local nextDecision: { [Part]: number } = {}

local function pulse(core: Part, name: string)
	core:SetAttribute(name, true)
	task.delay(0.12, function()
		core:SetAttribute(name, false)
	end)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, ring in world.rings do
		local core = ring.cores[2]
		if core:GetAttribute("AiMode") == 2 and now >= (nextDecision[core] or 0) then
			nextDecision[core] = now + rng:NextNumber(0.25, 0.6)
			core:SetAttribute("InMoveZ", rng:NextInteger(-1, 1))
			core:SetAttribute("InMoveX", rng:NextInteger(-1, 1))
			local roll = rng:NextNumber()
			core:SetAttribute("InGuard", roll > 0.8)
			if roll < 0.3 then
				pulse(core, "InJab")
			elseif roll < 0.45 then
				pulse(core, "InStraight")
			elseif roll < 0.55 then
				pulse(core, "InDash")
			elseif roll < 0.65 then
				pulse(core, "InLeftKick")
			elseif roll < 0.72 then
				pulse(core, "InRightKick")
			end
		end
	end
end)
