--!strict

-- Client half of the multiplayer checks (see StudioChecks.server.luau). Waits for the server to say go, plays what the
-- scenario calls for through the Input Action System and the menu remote, then reports what this client saw.

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
-- Rings are queued for in the hall, so a 1v1 scenario joins the line before the server starts the clock, and so does the
-- pits scenario, where both players train at once.
local queuedFor = ReplicatedStorage:GetAttribute("ChecksScenario")
if queuedFor == "pvp" or queuedFor == "match" or queuedFor == "pits" then
	local remote = ReplicatedStorage:WaitForChild("Menu") :: RemoteEvent
	task.wait(1)
	remote:FireServer(if queuedFor == "pits" then "training" else "versus")
end
if ReplicatedStorage:GetAttribute("ChecksStart") ~= true then
	ReplicatedStorage:GetAttributeChangedSignal("ChecksStart"):Wait()
end

local player = Players.LocalPlayer
local FoundryLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FoundryLayout"))
local InputSetup = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InputSetup"))
local Loadout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loadout"))
local report = ReplicatedStorage:WaitForChild("ChecksReport") :: RemoteEvent
local menu = ReplicatedStorage:WaitForChild("Menu") :: RemoteEvent
local scenario = ReplicatedStorage:GetAttribute("ChecksScenario")
local level = ReplicatedStorage:GetAttribute("ChecksLevel")

-- The ring the player's fight is in: the one the server seated them in, or until then the one the scenario's fight
-- belongs in (a 1v1 in the main ring, practice in the first pit).
type Ring = {
	modelOne: Instance,
	modelTwo: Instance,
	coreOne: Instance,
	coreTwo: Instance,
	match: Instance,
}
local ringsFolder = Workspace:WaitForChild("Rings")
local function ringIndex(): number
	local value = player:GetAttribute("Ring")
	if type(value) == "number" and value > 0 then
		return value
	end
	return if scenario == "bot" then 2 else 1
end
local function bind(index: number): Ring
	local model = ringsFolder:WaitForChild(FoundryLayout.Rings[index].name)
	local modelOne = model:WaitForChild("Fighter1")
	local modelTwo = model:WaitForChild("Fighter2")
	return {
		modelOne = modelOne,
		modelTwo = modelTwo,
		coreOne = modelOne:WaitForChild("Core"),
		coreTwo = modelTwo:WaitForChild("Core"),
		match = model:WaitForChild("Match"),
	}
end
local ring = bind(ringIndex())
local slot = if ring.modelOne:GetAttribute("OwnerUserId") == player.UserId then 1 else 2

-- Scriptable bindings drive the same actions as hardware input.
local scripted = InputSetup.findScripted(player)
while scripted == nil do
	task.wait(0.1)
	scripted = InputSetup.findScripted(player)
end
local controls = scripted :: InputSetup.Scripted

-- Counters that change every frame, and a fallen fighter's frame count, are left out of the comparison.
local VOLATILE = { Tick = true, PhaseFrame = true, Timer = true }
local KO = 3
-- What the server tells a ring rather than what its fight computes: who sits where, the builds and looks, the bot's
-- level, the dummy, the resets and the stand-in inputs. A ring that is mid-fight is compared on these alone.
local COMMANDS = {
	AiMode = true,
	Loadout = true,
	InMoveX = true,
	InMoveZ = true,
	InJab = true,
	InStraight = true,
	InLeftKick = true,
	InRightKick = true,
	InGuard = true,
	InDash = true,
	Lobby = true,
	TrainingMode = true,
	BotLevel = true,
	DummyMode = true,
	ResetToken = true,
	OwnerUserId = true,
	Look = true,
	Slot = true,
}

local function dump(instance: Instance, only: { [string]: boolean }?): string
	local keys = {}
	local attributes = instance:GetAttributes()
	local down = attributes.State == KO
	for key in attributes do
		local wanted = if only ~= nil then only[key] == true else not VOLATILE[key]
		if wanted and not (down and key == "StateFrame") then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		local value = attributes[key]
		table.insert(
			parts,
			key .. "=" .. (if type(value) == "number" then string.format("%.4f", value) else tostring(value))
		)
	end
	return table.concat(parts, " ")
end

-- Every ring as this client sees it, by name: in full, and the commands alone.
local function ringDumps(): { [string]: { full: string, commands: string } }
	local result: { [string]: { full: string, commands: string } } = {}
	for index, spec in FoundryLayout.Rings do
		local seen = bind(index)
		result[spec.name] = {
			full = `F1 {dump(seen.coreOne)}\nF2 {dump(seen.coreTwo)}\nMatch {dump(seen.match)}`,
			commands = `F1 {dump(seen.coreOne, COMMANDS)} {dump(seen.modelOne, COMMANDS)}\n`
				.. `F2 {dump(seen.coreTwo, COMMANDS)} {dump(seen.modelTwo, COMMANDS)}\n`
				.. `Match {dump(seen.match, COMMANDS)}`,
		}
	end
	return result
end

local function press(binding: InputBinding, hold: number)
	binding:Fire(true)
	task.wait(hold)
	binding:Fire(false)
end

local function walk(x: number, y: number, seconds: number)
	controls.move:Fire(Vector2.new(x, y))
	task.wait(seconds)
	controls.move:Fire(Vector2.zero)
end

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function stopped(): boolean
	return ReplicatedStorage:GetAttribute("ChecksStop") == true
end

local function releaseAll()
	controls.move:Fire(Vector2.zero)
	controls.jab:Fire(false)
	controls.straight:Fire(false)
	controls.leftKick:Fire(false)
	controls.rightKick:Fire(false)
	controls.guard:Fire(false)
	controls.dash:Fire(false)
end

-- A seeded mix of every action. Slot 1 plays forward, slot 2 plays defensively, so every state gets exercised on both
-- sides. The stick reads like the screen, so pushing it right walks toward the opponent.
local rng = Random.new(100 + slot)
local function randomMix()
	local approach = if slot == 1 then 0.2 else 0.15
	local jab = approach + (if slot == 1 then 0.2 else 0.15)
	local straight = jab + (if slot == 1 then 0.12 else 0.08)
	local kick = straight + (if slot == 1 then 0.12 else 0.08)
	local guard = kick + (if slot == 1 then 0.08 else 0.2)
	local dash = guard + (if slot == 1 then 0.08 else 0.12)

	-- Every attack button once while the fighters are still far apart, so the check covers all four bindings no matter
	-- how the random mix falls. The pause outlasts the longest recovery.
	for _, binding in { controls.jab, controls.straight, controls.leftKick, controls.rightKick } do
		press(binding, 0.12)
		task.wait(0.95)
	end

	while not stopped() do
		local roll = rng:NextNumber()
		if roll < approach then
			walk(1, 0, rng:NextNumber(0.2, 0.5))
		elseif roll < jab then
			press(controls.jab, 0.12)
			task.wait(rng:NextNumber(0.1, 0.3))
		elseif roll < straight then
			press(controls.straight, 0.12)
			task.wait(rng:NextNumber(0.2, 0.5))
		elseif roll < kick then
			press(if rng:NextNumber() < 0.5 then controls.leftKick else controls.rightKick, 0.12)
			task.wait(rng:NextNumber(0.2, 0.6))
		elseif roll < guard then
			controls.guard:Fire(true)
			task.wait(rng:NextNumber(0.3, 0.8))
			controls.guard:Fire(false)
		elseif roll < dash then
			controls.move:Fire(Vector2.new(rng:NextInteger(-1, 1), rng:NextInteger(-1, 1)))
			press(controls.dash, 0.1)
			controls.move:Fire(Vector2.zero)
			task.wait(rng:NextNumber(0.3, 0.6))
		else
			walk(rng:NextInteger(-1, 1), rng:NextInteger(-1, 1), rng:NextNumber(0.2, 0.4))
		end
	end
end

-- Walks up to the opponent and throws the heavy attacks until they are down, round after round.
local function aggressor()
	while not stopped() do
		local me = if slot == 1 then ring.coreOne else ring.coreTwo
		local foe = if slot == 1 then ring.coreTwo else ring.coreOne
		local dx = number(foe, "PosX") - number(me, "PosX")
		local dz = number(foe, "PosZ") - number(me, "PosZ")
		local distance = math.sqrt(dx * dx + dz * dz)
		local fighting = number(ring.match, "Phase") == 3
		if not fighting then
			task.wait(0.1)
		elseif distance > 3.7 then
			walk(1, 0, 0.12)
		else
			press(if rng:NextNumber() < 0.5 then controls.straight else controls.rightKick, 0.08)
			task.wait(0.45)
		end
	end
end

if scenario == "bot" then
	-- Fight with a build of its own, set the way the garage sets it. The ring takes the garage's build when a session
	-- starts, so the build is confirmed first, then the bot is picked from the menu as a player would, and the fighter has
	-- to come out wearing the build; one that never arrives is logged as an error, which fails the check.
	local garage = ReplicatedStorage:WaitForChild("Garage") :: RemoteEvent
	local code = Loadout.encode({ chassis = 5, arms = 3, core = 2, legs = 3 })
	garage:FireServer(
		"set",
		{ chassis = 5, arms = 3, core = 2, legs = 3, armor = 6, accent = 9, finish = 3, crest = 4 }
	)
	local deadline = os.clock() + 5
	while player:GetAttribute("GarageLoadout") ~= code and os.clock() < deadline do
		task.wait(0.1)
	end
	menu:FireServer("bot", level)
	deadline = os.clock() + 10
	while (player:GetAttribute("Ring") or 0) == 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	ring = bind(ringIndex())
	slot = if ring.modelOne:GetAttribute("OwnerUserId") == player.UserId then 1 else 2
	local mine = if slot == 1 then ring.coreOne else ring.coreTwo
	if number(mine, "Loadout") ~= code then
		task.spawn(error, `the garage's build never reached the fighter: {number(mine, "Loadout")}, not {code}`)
	end
	while number(ring.match, "Phase") ~= 3 and not stopped() do
		task.wait(0.1)
	end
	randomMix()
elseif scenario == "match" then
	if slot == 1 then
		-- After the match is decided and the result has been up for a few seconds, ask for a rematch.
		task.spawn(function()
			while number(ring.match, "Phase") ~= 5 and not stopped() do
				task.wait(0.2)
			end
			task.wait(3)
			menu:FireServer("rematch")
		end)
		aggressor()
	else
		while not stopped() do
			task.wait(0.2)
		end
	end
else
	randomMix()
end

releaseAll()

if scenario == "bot" then
	-- Out of the ring through the menu, then back in for training.
	menu:FireServer("menu")
	task.wait(1.5)
	menu:FireServer("training")
end

-- Wait for the server to say the fights have settled, then record what this client sees of every ring at that moment.
if ReplicatedStorage:GetAttribute("ChecksDump") ~= true then
	ReplicatedStorage:GetAttributeChangedSignal("ChecksDump"):Wait()
end
task.wait(0.3)

-- Roblox's own scripts (the player list, the start-up script, the default chat script) sometimes log errors in
-- unpublished test places, for example "Invalid value for enum CreatorType" or a chat setting that the core scripts had
-- not registered yet. They are the engine's rather than the game's, and are counted apart.
local ENGINE_ERROR_MARKERS = {
	"[Roblox][",
	"PlayerScripts.ChatScript",
	"PlayerScripts.BubbleChat",
	"PlayerScripts.RbxCharacterSounds",
}
local function isEngineError(message: string): boolean
	for _, marker in ENGINE_ERROR_MARKERS do
		if string.find(message, marker, 1, true) ~= nil then
			return true
		end
	end
	return false
end
local errors = 0
local engineErrors = 0
local errorSamples: { string } = {}
for _, entry in LogService:GetLogHistory() do
	if entry.messageType == Enum.MessageType.MessageError then
		if isEngineError(entry.message) then
			engineErrors += 1
		else
			errors += 1
			if #errorSamples < 5 then
				table.insert(errorSamples, string.sub(entry.message, 1, 300))
			end
		end
	end
end

report:FireServer({
	slot = slot,
	userId = player.UserId,
	steps = player:GetAttribute("RS_Steps") or 0,
	resimSteps = player:GetAttribute("RS_ResimSteps") or 0,
	rollbacks = player:GetAttribute("RS_Rollbacks") or 0,
	pingMs = player:GetAttribute("RS_PingMs") or 0,
	errors = errors,
	engineErrors = engineErrors,
	errorSamples = errorSamples,
	ring = ringIndex(),
	dumps = ringDumps(),
})
