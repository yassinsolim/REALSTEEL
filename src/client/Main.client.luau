--!strict

-- Client: everything the local player sees. Walking around THE FOUNDRY they have Roblox's camera and controls, a PLAY
-- button, the robots in the garage bays, the fights in every ring and the screens over them; once a ring is theirs the
-- fight camera, the fight HUD and the touch controls take over until they leave it again.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local FightSim = require(Shared:WaitForChild("FightSim"))
local FoundryLayout = require(Shared:WaitForChild("FoundryLayout"))
local FrameData = require(Shared:WaitForChild("FrameData"))
local Hoist = require(Shared:WaitForChild("Hoist"))
local InputSetup = require(Shared:WaitForChild("InputSetup"))
local Loadout = require(Shared:WaitForChild("Loadout"))
local Looks = require(Shared:WaitForChild("Looks"))
local MatchFlow = require(Shared:WaitForChild("MatchFlow"))
local Shop = require(Shared:WaitForChild("Shop"))
local Simulation = require(Shared:WaitForChild("Simulation"))
local ArenaFx = require(script.Parent:WaitForChild("ArenaFx"))
local Bays = require(script.Parent:WaitForChild("Bays"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))
local Cranes = require(script.Parent:WaitForChild("Cranes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local FighterView = require(script.Parent:WaitForChild("FighterView"))
local GaragePanel = require(script.Parent:WaitForChild("GaragePanel"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Jumbotron = require(script.Parent:WaitForChild("Jumbotron"))
local Leaderboards = require(script.Parent:WaitForChild("Leaderboards"))
local LobbyHud = require(script.Parent:WaitForChild("LobbyHud"))
local MatchView = require(script.Parent:WaitForChild("MatchView"))
local Menu = require(script.Parent:WaitForChild("Menu"))
local PadView = require(script.Parent:WaitForChild("PadView"))
local RobotFrames = require(script.Parent:WaitForChild("RobotFrames"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local StageLights = require(script.Parent:WaitForChild("StageLights"))
local Statue = require(script.Parent:WaitForChild("Statue"))
local TouchControls = require(script.Parent:WaitForChild("TouchControls"))
local TrainingHud = require(script.Parent:WaitForChild("TrainingHud"))

local Phase = MatchFlow.Phase
local Result = MatchFlow.Result

local player = Players.LocalPlayer

-- Characters closer than this to the player's robot are hidden while the garage's close-up is up.
local GARAGE_CLEAR_RADIUS = 22
-- Characters closer than this to the fight camera are hidden from it. Around a pit the camera reaches over the
-- spectators' rail and past the booths, where the player's own character stands.
local FIGHT_CLEAR_RADIUS = 10
-- Spectators hear a ring at full volume up close and fainter across the hall. The pits carry less far than the main
-- ring, and from a seat in one ring the others are only a murmur.
local HEAR_MAIN = { near = 34, far = 110, quietest = 0.3 }
local HEAR_PIT = { near = 22, far = 80, quietest = 0.08 }
local HEAR_FROM_SEAT = 0.35
local HISTORY_FRAMES = 180

local function rgb(color: Looks.Rgb): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- The local fighter is always drawn on the left, the opponent on the right, whichever slot each one holds. A robot that
-- has not been painted wears its side's team colors, blue and light steel against red and gunmetal, which matches the
-- health bars and the spotlights; the garage's paint replaces them (see Looks.resolve).
local PALETTES = {
	me = { accent = rgb(Looks.Team.me.accent), armor = rgb(Looks.Team.me.armor) },
	foe = { accent = rgb(Looks.Team.foe.accent), armor = rgb(Looks.Team.foe.armor) },
}

-- The player list shows in the hall, where it says who is around, and hides in a ring, where it would sit on top of the
-- opponent's health bar. The core scripts register it a moment after start, so the first calls are repeated.
local playerListShown = true
local function showPlayerList(shown: boolean)
	playerListShown = shown
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, shown)
	end)
end
task.spawn(function()
	for _ = 1, 10 do
		showPlayerList(playerListShown)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		task.wait(0.5)
	end
end)

local function waitForCamera(): Camera
	local current = Workspace.CurrentCamera
	while current == nil do
		task.wait()
		current = Workspace.CurrentCamera
	end
	return current :: Camera
end

local ringsFolder = Workspace:WaitForChild("Rings")

-- The server shares the uploaded robot meshes before it creates the fighters. Without them the robots are blockouts.
local robot: FighterView.Robot = RobotFrames.load()

local camera = waitForCamera()
local sfx = Sfx.new()
-- The hall's state the server publishes (see Rings on the server).
local foundryState = ReplicatedStorage:WaitForChild("FoundryState")

-- One ring as this client sees it.
type RingView = {
	index: number,
	spec: FoundryLayout.RingSpec,
	main: boolean,
	models: { Model },
	views: { FighterView.View },
	match: Part,
	states: { FightSim.Fighter },
	matchView: MatchView.View,
	effects: Effects.Effects,
	-- What the server says about the ring: who is next, whether a rematch is open.
	board: Instance,
	-- Whether its fighters' state has arrived.
	ready: boolean,
	-- What dressAll last ran with: the local slot, both loadouts and both looks; and who held each seat then.
	dressedSlot: number,
	dressedLoadout: { any },
	dressedLook: { any },
	dressedOwner: { number },
	lastPhase: number,
	lastBell: number,
	-- The winch over each seat's mark (see Hoist), where its underside is, the name its cable is drawn under, and how
	-- large each seat's robot is drawn.
	winches: { Hoist.Winch },
	winchAt: { Vector3 },
	craneKeys: { string },
	scales: { number },
}

local rings: { RingView } = {}
for index, spec in FoundryLayout.Rings do
	local model = ringsFolder:WaitForChild(spec.name)
	local models: { Model } = {}
	local views: { FighterView.View } = {}
	local cores: { Part } = {}
	for slot = 1, 2 do
		local fighter = model:WaitForChild("Fighter" .. slot) :: Model
		local view = FighterView.new(fighter, robot, spec.center)
		-- Fighters are not Humanoid characters, so the engine will not predict them unless asked.
		RunService:SetPredictionMode(view.core, Enum.PredictionMode.On)
		models[slot] = fighter
		views[slot] = view
		cores[slot] = view.core
	end
	local match = model:WaitForChild("Match") :: Part
	RunService:SetPredictionMode(match, Enum.PredictionMode.On)
	-- The server adds the rings in the same order, so both number them alike.
	Simulation.addRing(cores, match)
	rings[index] = {
		index = index,
		spec = spec,
		main = not spec.pit,
		models = models,
		views = views,
		match = match,
		states = { FightSim.newFighter(0, 0), FightSim.newFighter(0, 0) },
		matchView = MatchView.new(),
		effects = Effects.new(sfx),
		board = foundryState:WaitForChild(spec.name),
		ready = false,
		dressedSlot = 0,
		dressedLoadout = { false, false },
		dressedLook = { false, false },
		dressedOwner = { -1, -1 },
		lastPhase = -1,
		lastBell = -10,
		winches = { Hoist.new(), Hoist.new() },
		winchAt = { Cranes.winchAt(spec.center, spec.hookY, 1), Cranes.winchAt(spec.center, spec.hookY, 2) },
		craneKeys = { `{index}:1`, `{index}:2` },
		scales = { 1, 1 },
	}
end
-- The main ring comes first in FoundryLayout.Rings.
local mainRing = rings[1]

-- The frame meter's record of the player's own ring, started afresh whenever they take a seat.
local history = FrameData.newHistory(HISTORY_FRAMES)
Simulation.start()

local function ownerId(ring: RingView, slot: number): number
	local value = ring.models[slot]:GetAttribute("OwnerUserId")
	return if type(value) == "number" then value else 0
end

-- The ring the local player holds a seat in and which seat, or nil (and seat 1, the side a spectator sees from).
local function findSeat(): (RingView?, number)
	for _, ring in rings do
		for slot = 1, 2 do
			if ownerId(ring, slot) == player.UserId then
				return ring, slot
			end
		end
	end
	return nil, 1
end

task.spawn(function()
	while true do
		for _, ring in rings do
			for slot = 1, 2 do
				local id = ownerId(ring, slot)
				local owner = if id ~= 0 then Players:GetPlayerByUserId(id) else nil
				Simulation.setInputs(ring.index, slot, if owner ~= nil then InputSetup.find(owner) else nil)
			end
		end
		task.wait(0.25)
	end
end)

local function boardText(ring: RingView, name: string): string
	local value = ring.board:GetAttribute(name)
	return if type(value) == "string" then value else ""
end
local function playerNumber(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end
local function playerText(name: string): string
	local value = player:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local hud = Hud.new()
local menuRemote = ReplicatedStorage:WaitForChild("Menu") :: RemoteEvent
local garageRemote = ReplicatedStorage:WaitForChild("Garage") :: RemoteEvent
local shopRemote = ReplicatedStorage:WaitForChild("Shop") :: RemoteEvent
local garage = GaragePanel.new({
	gui = hud.gui,
	owner = player,
	send = function(choices: { [string]: number })
		garageRemote:FireServer("set", choices)
	end,
	play = function(name: string, gain: number?, pitch: number?)
		Sfx.play(sfx, name, gain, pitch)
	end,
	-- Coins are spent by the server; Robux go through Roblox's purchase prompt, and the server hears of the purchase
	-- itself (see Wallet).
	buy = function(item: Shop.Item)
		if item.coins ~= nil then
			shopRemote:FireServer("buy", item.id)
		elseif Shop.forRobux(item) then
			MarketplaceService:PromptProductPurchase(player, item.product :: number)
		end
	end,
})
-- How a purchase prompt closed, so the shop shows a paid item as on its way rather than for sale. (The purchase itself is
-- granted by the server's ProcessReceipt, never from this.)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
	local item = Shop.byProduct(productId)
	if userId == player.UserId and item ~= nil then
		garage.purchaseFinished(item.id, purchased)
	end
end)
local function send(action: string, level: number?)
	menuRemote:FireServer(action, level)
end

-- Whether the local player holds a seat in a ring; the main loop keeps it current.
local seated = false
local menu: Menu.Menu
local function openGarage()
	if not seated then
		menu.close()
		garage.open()
	end
end
menu = Menu.new(hud.gui, send, openGarage)
local lobbyHud = LobbyHud.new(hud.gui, function()
	if not seated and not garage.isOpen() then
		menu.open(nil)
	end
end, function()
	send("leave", nil)
end)
local bays = Bays.new(robot, openGarage)

-- The screens over the rings: the big one over the main ring, and one over each pit in the pit's model.
local function screenFaces(path: { string }): () -> { BasePart }
	return function(): { BasePart }
		local node: Instance = Workspace:WaitForChild("Foundry")
		for _, name in path do
			node = node:WaitForChild(name)
		end
		local faces: { BasePart } = {}
		for index = 1, 4 do
			local part = node:WaitForChild("Face" .. index)
			if part:IsA("BasePart") then
				table.insert(faces, part)
			end
		end
		return faces
	end
end
local screens: { Jumbotron.Jumbotron } = {}
for index, ring in rings do
	screens[index] = if ring.main
		then Jumbotron.new({ faces = screenFaces({}), title = "THE FOUNDRY", subtitle = "ROBOT FIGHT CLUB" })
		else Jumbotron.new({
			faces = screenFaces({ ring.spec.name }),
			title = ring.spec.label,
			subtitle = "1V1  ·  BOTS  ·  TRAINING",
		})
end
-- The winches' cables and hooks, the champion's statue, and the leaderboards.
local cranes = Cranes.new()
local statue = Statue.new(robot, foundryState)
local leaderboards = Leaderboards.new(foundryState)
-- The champion when the client started, so only a change of title is announced.
local knownChampion = foundryState:GetAttribute("ChampionId")

-- The pads in front of the main ring: who stands on each, and the countdowns (the server starts the fights, see Pads).
local padView = PadView.new(foundryState)

-- P (Select on a gamepad) opens and closes the PLAY card in the hall. It sits well away from the punches on J and K. In a
-- ring the same key reaches the server through the training inputs: held for a moment, it leaves a bot match or
-- training.
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	local key = input.KeyCode
	if processed or seated or garage.isOpen() then
		return
	end
	if key == Enum.KeyCode.P or key == Enum.KeyCode.ButtonSelect then
		if menu.isOpen() then
			menu.close()
		else
			menu.open(nil)
		end
	end
end)

-- The character's own controls rest while a card or the garage is up and while the player is in a ring, so the keys
-- that pick an entry or throw a punch do not also walk the character around.
local controls: any = nil
task.spawn(function()
	local load: (module: any) -> any = require :: any
	local ok, module = pcall(function()
		return load(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 20))
	end)
	if ok and module ~= nil then
		controls = module:GetControls()
	end
end)
local controlsOn = true
local function setControls(on: boolean)
	if on == controlsOn or controls == nil then
		return
	end
	controlsOn = on
	pcall(function()
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

-- H (or a tap on the training status line) shows the controls card and, in training, the frame data and meter.
local showDetail = false
local toggleDetail: () -> () = function() end
local trainingHud = TrainingHud.new(hud.gui, function()
	toggleDetail()
end)
toggleDetail = function()
	showDetail = not showDetail
	hud.setHelp(showDetail)
	trainingHud.setDetail(showDetail)
end
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.H and seated then
		toggleDetail()
	end
end)

-- Touch controls fire the player's Scriptable bindings, which replicate with the rest of the input contexts.
local scripted = InputSetup.findScripted(player)
while scripted == nil do
	task.wait(0.1)
	scripted = InputSetup.findScripted(player)
end
local touchControls = TouchControls.new(hud.gui, scripted :: InputSetup.Scripted)
-- The leave key's state, read here only to draw how far a hold has come (the server decides when it counts).
local trainingActions = InputSetup.findTraining(player)
local leaveHeldSince: number? = nil

-- ForceTouchUI lets the touch layout be checked on a desktop.
local touchUi = false
local touchShown = false
local function refreshTouchUi()
	local wanted = player:GetAttribute("ForceTouchUI") == true
		or UserInputService.PreferredInput == Enum.PreferredInput.Touch
	if wanted ~= touchUi then
		touchUi = wanted
		hud.setCompact(wanted)
		menu.setCompact(wanted)
		garage.setCompact(wanted)
		lobbyHud.setCompact(wanted)
	end
end
refreshTouchUi()
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshTouchUi)
player:GetAttributeChangedSignal("ForceTouchUI"):Connect(refreshTouchUi)

local cameraRig = CameraRig.new(camera)
local lastMetricsPush = 0

-- The ropes and posts of every ring, and the pits' rails, fade out when the fight camera comes close instead of filling
-- the screen.
Workspace:WaitForChild("Foundry"):WaitForChild("Arena")
local arenaFx = ArenaFx.start()
-- The spotlights that follow the fighters hang over the main ring.
local stageLights = StageLights.new({ PALETTES.me.accent, PALETTES.foe.accent })
local lightPositions = { Vector3.zero, Vector3.zero }
local fadeParts: { BasePart } = {}
local fading = false
local function trackFade(instance: Instance)
	if instance:IsA("BasePart") then
		table.insert(fadeParts, instance)
	end
end
for _, instance in CollectionService:GetTagged(FightConfig.RingFadeTag) do
	trackFade(instance)
end
CollectionService:GetInstanceAddedSignal(FightConfig.RingFadeTag):Connect(trackFade)

-- Screen flashes ride on the post effects the place already has.
local grade = Lighting:FindFirstChild("ColorGrade")
local bloom = Lighting:FindFirstChild("Bloom")
local gradeBrightness = if grade ~= nil and grade:IsA("ColorCorrectionEffect") then grade.Brightness else 0
local bloomIntensity = if bloom ~= nil and bloom:IsA("BloomEffect") then bloom.Intensity else 0

local function materialOf(name: string): Enum.Material
	local item = Enum.Material:FromName(name)
	return if item ~= nil then item :: any else Enum.Material.Metal
end

-- What each robot in a ring wears: its chassis' frame and size, its crest, its paint and finish, as the server set them
-- on the fighter. The two looks are resolved together, so the opponent never wears what is too close to the local
-- fighter's colors. The effects follow each robot's accent; the main ring's spotlights keep the team colors, which mark
-- the sides.
local function dressAll(ring: RingView, slot: number)
	local mine, foe = Looks.resolve(
		Looks.decode(ring.models[slot]:GetAttribute("Look")),
		Looks.decode(ring.models[3 - slot]:GetAttribute("Look"))
	)
	for index = 1, 2 do
		local resolved = if index == slot then mine else foe
		local view = ring.views[index]
		local code = view.core:GetAttribute("Loadout")
		local choice = Loadout.decode(code)
		local look = Looks.decode(ring.models[index]:GetAttribute("Look"))
		local accent = rgb(resolved.accent)
		local rebuilt = FighterView.dress(
			view,
			Looks.frameFor(choice, look),
			Loadout.scale(code),
			Looks.kitsFor(choice, look),
			accent,
			rgb(resolved.armor),
			materialOf(resolved.finish.material),
			resolved.finish.reflectance,
			resolved.finish.name
		)
		if rebuilt then
			Effects.attachSlot(ring.effects, index, view, accent)
		else
			Effects.setAccent(ring.effects, index, accent)
		end
		if ring.main then
			StageLights.setAccent(stageLights, index, if index == slot then PALETTES.me.accent else PALETTES.foe.accent)
		end
	end
end

-- Dresses a ring's robots again if anything about them has changed, and says which seats hold a new robot: another
-- player's, another build or another look.
local function refreshDress(ring: RingView, slot: number): (boolean, boolean)
	local loadoutA = ring.views[1].core:GetAttribute("Loadout")
	local loadoutB = ring.views[2].core:GetAttribute("Loadout")
	local lookA = ring.models[1]:GetAttribute("Look")
	local lookB = ring.models[2]:GetAttribute("Look")
	local ownerA = ownerId(ring, 1)
	local ownerB = ownerId(ring, 2)
	local freshA = loadoutA ~= ring.dressedLoadout[1] or lookA ~= ring.dressedLook[1] or ownerA ~= ring.dressedOwner[1]
	local freshB = loadoutB ~= ring.dressedLoadout[2] or lookB ~= ring.dressedLook[2] or ownerB ~= ring.dressedOwner[2]
	if freshA or freshB or slot ~= ring.dressedSlot then
		ring.dressedSlot = slot
		ring.dressedLoadout = { loadoutA, loadoutB }
		ring.dressedLook = { lookA, lookB }
		ring.dressedOwner = { ownerA, ownerB }
		ring.scales = { Loadout.scale(loadoutA), Loadout.scale(loadoutB) }
		dressAll(ring, slot)
	end
	return freshA, freshB
end
for _, ring in rings do
	Effects.attach(ring.effects, ring.views, { PALETTES.me.accent, PALETTES.foe.accent })
	refreshDress(ring, 1)
end

local function displayName(userId: number): string
	local owner = Players:GetPlayerByUserId(userId)
	local name = if owner ~= nil then owner.DisplayName else "PLAYER"
	return string.upper(string.sub(name, 1, 14))
end

local function botLevelName(view: MatchView.View): string
	return BotBrain.Levels[math.clamp(view.botLevel, 1, BotBrain.LevelCount)].name
end

-- What a screen calls a fighter: its player; for a bot facing a player, the bot and its level; for a bot in an
-- exhibition, the build it fights with; and the dummy in training.
local function fighterName(ring: RingView, slot: number): string
	local view = ring.matchView
	local id = ownerId(ring, slot)
	if id ~= 0 then
		return displayName(id)
	end
	if view.botLevel > 0 then
		if ownerId(ring, 3 - slot) ~= 0 then
			return `BOT  ·  {botLevelName(view)}`
		end
		return Loadout.buildName(Loadout.decode(ring.views[slot].core:GetAttribute("Loadout")))
	end
	return if view.training then "DUMMY" else ""
end

-- What a robot does while it stands free: hang powered down from its winch, and stay that way until it is set down;
-- then flex before the bell, and celebrate or slump after it.
local function emoteFor(ring: RingView, slot: number): string?
	local view = ring.matchView
	local phase = view.phase
	if phase == Phase.Lobby or ring.winches[slot].lift > 0 then
		return "Slump"
	elseif phase == Phase.Intro then
		return "Intro"
	elseif phase == Phase.RoundEnd or phase == Phase.MatchEnd then
		if view.result == Result.A or view.result == Result.B then
			local winner = if view.result == Result.A then 1 else 2
			return if slot == winner then "Victory" else "Slump"
		end
	end
	return nil
end

-- Characters near a point are hidden on this screen: near the player's robot while the garage's close-up is up, and near
-- the fight camera, so nobody stands between the camera and the robots.
local ghosted: { [Model]: boolean? } = {}
local function ghost(character: Model, hidden: boolean)
	local amount = if hidden then 1 else 0
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			(item :: any).LocalTransparencyModifier = amount
		end
	end
end
local function clearAround(at: Vector3?, radius: number)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = if character ~= nil then character.PrimaryPart else nil
		if character ~= nil and root ~= nil then
			local wanted = at ~= nil and (root.Position - at).Magnitude < radius
			if wanted ~= (ghosted[character] == true) then
				ghost(character, wanted)
				ghosted[character] = if wanted then true else nil
			end
		end
	end
	for character in ghosted do
		if character.Parent == nil then
			ghosted[character] = nil
		end
	end
end

-- How present a ring is to the player: all of it from its own seat, fading with distance from `listener` for someone in
-- the hall, and only faintly from a seat in another ring.
local function presenceOf(ring: RingView, mine: RingView?, listener: Vector3): number
	if ring == mine then
		return 1
	end
	local hear = if ring.main then HEAR_MAIN else HEAR_PIT
	local away = (listener - (ring.spec.center + Vector3.new(0, 3, 0))).Magnitude
	local presence = math.clamp(1 - (away - hear.near) / (hear.far - hear.near), hear.quietest, 1)
	return if mine ~= nil then presence * HEAR_FROM_SEAT else presence
end

-- How worked up a ring's crowd is. The main ring's rail lights up with it; the crowd's roar follows the player's own
-- fight, or the main ring's.
local function excitementOf(ring: RingView): number
	return math.min(ring.effects.excitement + (if ring.matchView.phase == Phase.Fight then 0.12 else 0), 1)
end

local fpsAverage = 60
local lastStats = 0
-- The build the PLAY card's GARAGE line last named, and the ring the player held a seat in last frame.
local blurbCode = 0
local seatedRing: RingView? = nil

RunService.RenderStepped:Connect(function(deltaTime: number)
	local now = os.clock()
	garage.step(now)
	for _, ring in rings do
		ring.ready = Simulation.readState(ring.views[1].core, ring.states[1])
			and Simulation.readState(ring.views[2].core, ring.states[2])
		if ring.ready then
			MatchView.read(ring.match, ring.matchView)
		end
	end

	local mine, slot = findSeat()
	if mine ~= nil and not mine.ready then
		mine = nil
	end
	local foeSlot = 3 - slot
	seated = mine ~= nil
	-- The ring whose fight the HUD, the menu and the training panel follow: the player's own, or the main ring's.
	local focus = mine or mainRing
	local matchView = focus.matchView
	local versus = mine ~= nil and ownerId(mine, 1) ~= 0 and ownerId(mine, 2) ~= 0
	local lobby = matchView.lobby
	local training = matchView.training and not lobby
	local resultUp = seated and matchView.phase == Phase.MatchEnd and matchView.phaseFrame >= 45

	-- Taking a seat closes whatever was up in the hall; leaving the ring brings the hall back.
	if mine ~= seatedRing then
		local wasSeated = seatedRing ~= nil
		seatedRing = mine
		if mine ~= nil then
			menu.close()
			garage.close()
			lobbyHud.notify(`{mine.spec.label} IS YOURS`)
			history = FrameData.newHistory(HISTORY_FRAMES)
			Simulation.setRecorder(history, mine.index)
		else
			Simulation.setRecorder(nil, 0)
		end
		if wasSeated ~= seated then
			showPlayerList(not seated)
			pcall(function()
				(GuiService :: any).TouchControlsEnabled = not seated
			end)
		end
	end

	-- Every ring's robots. The fight camera sits on the local fighter's right, so the opponent is mirrored to turn both
	-- chests toward it; a spectator sees each ring from its first seat's side. The winches hang them over their marks
	-- while the ring stands idle and drop them in at the start of a match (see Hoist).
	local listener = camera.CFrame.Position
	local shake = 0
	local punch = 0
	for _, ring in rings do
		if ring.ready then
			local ringSlot = if ring == mine then slot else 1
			local freshA, freshB = refreshDress(ring, ringSlot)
			local showHitbox = ring == mine and training
			local a, b = ring.states[1], ring.states[2]
			local hookY = ring.spec.hookY
			local winchA, winchB = ring.winches[1], ring.winches[2]
			local landedA = Hoist.step(winchA, ring.matchView, hookY, ring.scales[1], deltaTime, freshA)
			local landedB = Hoist.step(winchB, ring.matchView, hookY, ring.scales[2], deltaTime, freshB)
			FighterView.update(ring.views[1], a, b, now, ringSlot ~= 1, showHitbox, emoteFor(ring, 1), winchA.lift)
			FighterView.update(ring.views[2], b, a, now, ringSlot ~= 2, showHitbox, emoteFor(ring, 2), winchB.lift)
			local reaching = ring.matchView.phase == Phase.Lobby
			for seat, winch in ring.winches do
				local head = if winch.lift > 0 or reaching then FighterView.headPoint(ring.views[seat]) else nil
				Cranes.draw(cranes, ring.craneKeys[seat], ring.winchAt[seat], winch, head, reaching, deltaTime)
			end
			sfx.volume = presenceOf(ring, mine, listener)
			if landedA and landedB then
				Effects.land(ring.effects, ring.views)
			elseif landedA or landedB then
				Effects.land(ring.effects, { ring.views[if landedA then 1 else 2] })
			end
			ring.effects.cheers = ring == focus
			local ringShake = Effects.update(ring.effects, ring.states, ring.views, now, deltaTime)
			if ring == mine then
				shake = ringShake
				punch = ring.effects.punch
			end
		end
	end
	local previewLoadout, previewLook = garage.preview()
	bays.step(now, listener, previewLoadout, previewLook)
	statue.step(now)
	leaderboards.step(now)
	-- A new champion is news for the whole hall.
	local champion = foundryState:GetAttribute("ChampionId")
	if champion ~= knownChampion then
		knownChampion = champion
		if type(champion) == "number" and champion ~= 0 then
			local name = foundryState:GetAttribute("ChampionName")
			lobbyHud.notify(
				if champion == player.UserId
					then "YOU ARE THE CHAMPION"
					else `NEW CHAMPION  ·  {if type(name) == "string" then name else ""}`
			)
		end
	end

	local meState = focus.states[slot]
	local foeState = focus.states[foeSlot]

	-- In a ring the fight camera; at the bay the garage's close-up; anywhere else Roblox's own camera.
	local garageOpen = garage.isOpen() and not seated
	local bay = bays.mine()
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if mine ~= nil then
		local meView = mine.views[slot]
		local foeView = mine.views[foeSlot]
		local fallen = 0
		if matchView.phase == Phase.RoundEnd and matchView.reason == MatchFlow.Reason.KO then
			fallen = if meState.state == FightSim.State.KO
				then 1
				elseif foeState.state == FightSim.State.KO then 2
				else 0
		end
		CameraRig.update(cameraRig, {
			dt = deltaTime,
			now = now,
			meX = meView.drawX,
			meZ = meView.drawZ,
			foeX = foeView.drawX,
			foeZ = foeView.drawZ,
			origin = mine.spec.center,
			touch = touchUi,
			phase = matchView.phase,
			phaseFrame = matchView.phaseFrame,
			reason = matchView.reason,
			fallen = fallen,
			shake = shake,
			punch = punch,
		})
	elseif garageOpen and bay ~= nil then
		local shiftX, shiftY = garage.room(camera.ViewportSize)
		CameraRig.garage(cameraRig, {
			dt = deltaTime,
			now = now,
			at = bay.Position,
			facing = bay.LookVector,
			shiftX = shiftX,
			shiftY = shiftY,
		})
	else
		CameraRig.release(cameraRig, humanoid)
	end
	local position = camera.CFrame.Position
	if mine ~= nil then
		clearAround(position, FIGHT_CLEAR_RADIUS)
	elseif garageOpen and bay ~= nil then
		clearAround(bay.Position, GARAGE_CLEAR_RADIUS)
	else
		clearAround(nil, 0)
	end
	setControls(not (seated or menu.isOpen() or garageOpen))

	-- Only the fight camera comes close enough to the ropes and rails to need them faded.
	if mine ~= nil then
		for _, part in fadeParts do
			part.LocalTransparencyModifier = math.clamp((17 - (part.Position - position).Magnitude) / 8, 0, 1)
		end
		fading = true
	elseif fading then
		fading = false
		for _, part in fadeParts do
			part.LocalTransparencyModifier = 0
		end
	end
	lightPositions[1] = FighterView.groundPoint(mainRing.views[1])
	lightPositions[2] = FighterView.groundPoint(mainRing.views[2])
	StageLights.update(stageLights, lightPositions, position)

	-- Impacts flash the screen: the player's own fight in full, the others a little, fading with distance.
	local flash = 0
	if mine ~= nil then
		flash = mine.effects.flash
	else
		for _, ring in rings do
			flash = math.max(flash, ring.effects.flash * 0.4 * presenceOf(ring, nil, position))
		end
	end
	if grade ~= nil and grade:IsA("ColorCorrectionEffect") then
		grade.Brightness = gradeBrightness + flash * 0.3
	end
	if bloom ~= nil and bloom:IsA("BloomEffect") then
		bloom.Intensity = bloomIntensity + flash * 0.7
	end
	arenaFx.setExcitement(excitementOf(mainRing))
	sfx.volume = presenceOf(focus, mine, position)
	Sfx.setCrowd(sfx, excitementOf(focus), menu.isOpen() or resultUp)

	-- The bell rings when a round starts and when a clock runs out, in every ring, as loud as the ring is present.
	for _, ring in rings do
		local view = ring.matchView
		if ring.ready and view.phase ~= ring.lastPhase then
			sfx.volume = presenceOf(ring, mine, position)
			if now - ring.lastBell > 1 then
				if view.phase == Phase.Fight and ring.lastPhase == Phase.Intro then
					ring.lastBell = now
					Sfx.play(sfx, "bell", 0.8, 1.15)
				elseif view.phase == Phase.RoundEnd and view.reason == MatchFlow.Reason.Time then
					ring.lastBell = now
					Sfx.play(sfx, "bell", 1, 1)
				end
			end
			if view.phase == Phase.MatchEnd and ring == mine then
				Sfx.surge(sfx, now, 1)
			end
			ring.lastPhase = view.phase
		end
	end
	-- Sounds played between frames (the garage's and the menu's) are the player's own.
	sfx.volume = 1

	-- The fight HUD and the touch controls belong to the players in a ring; the hall has its own.
	hud.setShown(seated and not lobby)
	local wantTouch = touchUi and seated and not resultUp
	if wantTouch ~= touchShown then
		touchShown = wantTouch
		touchControls.setVisible(wantTouch)
	end
	local queueMode = player:GetAttribute("QueueMode")
	local queued = type(queueMode) == "string" and queueMode ~= ""
	menu.update(matchView, {
		slot = slot,
		seated = seated,
		versus = versus,
		rematchOpen = focus.board:GetAttribute("RematchOpen") == true,
		nextUp = boardText(focus, "NextUp"),
		queued = queued,
	})
	local chosenBuild = garage.current()
	if chosenBuild ~= blurbCode then
		blurbCode = chosenBuild
		menu.setGarageBlurb(`{Loadout.buildName(Loadout.decode(chosenBuild))}  ·  parts and paint`)
	end
	-- The pads' signs are drawn whether or not the player is on one, and in a ring too, where they can be in view.
	local padLine = padView.step()
	lobbyHud.update({
		hidden = seated or menu.isOpen() or garageOpen,
		queueMode = if queued then queueMode :: string else "",
		queueLevel = playerNumber("QueueLevel"),
		queueAhead = playerNumber("QueueAhead"),
		alone = player:GetAttribute("QueueAlone") == true,
		rival = playerText("QueueRival"),
		padLine = if seated then "" else padLine,
	})
	touchControls.setTrainingVisible(training and seated)
	touchControls.setModeVisible(seated and not versus)

	-- Holding the leave key in a bot match or training fills the meter until the server lets the player go.
	local leaveDown = trainingActions ~= nil and seated and not versus and trainingActions.toggle:GetState() == true
	if not leaveDown then
		leaveHeldSince = nil
	elseif leaveHeldSince == nil then
		leaveHeldSince = now
	end
	hud.setLeaving(if leaveHeldSince ~= nil then (now - leaveHeldSince) / InputSetup.LeaveHold else 0)

	local winsLeft = if slot == 1 then matchView.winsA else matchView.winsB
	local winsRight = if slot == 1 then matchView.winsB else matchView.winsA
	local roundWinner = 0
	if matchView.result == Result.A then
		roundWinner = if slot == 1 then 1 else 2
	elseif matchView.result == Result.B then
		roundWinner = if slot == 2 then 1 else 2
	end
	local botName = if matchView.botLevel > 0
		then `BOT · {botLevelName(matchView)}`
		else (if training then "DUMMY" else "P2")
	hud.update({
		left = meState,
		right = foeState,
		winsLeft = winsLeft,
		winsRight = winsRight,
		nameLeft = if versus then displayName(ownerId(focus, slot)) elseif seated then "YOU" else "P1",
		nameRight = if versus then displayName(ownerId(focus, foeSlot)) else botName,
		roundWinner = roundWinner,
		seated = seated,
		view = matchView,
	})
	for index, ring in rings do
		screens[index].update({
			view = ring.matchView,
			left = ring.states[1],
			right = ring.states[2],
			nameLeft = fighterName(ring, 1),
			nameRight = fighterName(ring, 2),
			nextUp = boardText(ring, "NextUp"),
		})
	end

	local metrics = Simulation.getMetrics()
	local pingMs = math.floor(player:GetNetworkPing() * 1000 + 0.5)
	local dummyMode = focus.match:GetAttribute("DummyMode")
	trainingHud.update({
		history = history,
		mySlot = slot,
		training = training and seated,
		compact = touchUi,
		dummyMode = if type(dummyMode) == "number" then dummyMode else 0,
		me = meState,
		foe = foeState,
		debugLine = if touchUi
			then string.format("ping %d ms  rollbacks %d", pingMs, metrics.rollbacks)
			else string.format(
				"ping %d ms  steps %d  resim %d  rollbacks %d",
				pingMs,
				metrics.steps,
				metrics.resimSteps,
				metrics.rollbacks
			),
	})

	fpsAverage += (1 / math.max(deltaTime, 1e-3) - fpsAverage) * 0.04
	if now - lastStats > 0.5 then
		lastStats = now
		local color = if pingMs < 70
			then Color3.fromRGB(120, 230, 150)
			elseif pingMs < 130 then Color3.fromRGB(255, 200, 90)
			else Color3.fromRGB(255, 110, 100)
		hud.setStats(string.format("%d ms  %d fps", pingMs, math.floor(fpsAverage + 0.5)), color)
	end

	if now - lastMetricsPush > 0.25 then
		lastMetricsPush = now
		player:SetAttribute("RS_Steps", metrics.steps)
		player:SetAttribute("RS_ResimSteps", metrics.resimSteps)
		player:SetAttribute("RS_Rollbacks", metrics.rollbacks)
		player:SetAttribute("RS_PingMs", pingMs)
	end
end)
