--!strict

-- The place owner's connection probe. Every character is simulated by the server (Workspace.AuthorityMode) and each
-- client predicts its own; when the two disagree the client is corrected, which shows as the character jumping back.
-- A live server can do that where Studio never does, so this measures it there: frame hitches, the engine's rollbacks,
-- every jump of the local character, how far it got while trying to walk, and how far the server's copy of it got (see
-- NetProbe on the server). It prints a summary to the client log every two seconds while anything happens, a line for
-- every jump, and keeps a readout in the bottom left corner. Only the owner runs it (and anyone in Studio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if
	not RunService:IsStudio() and not (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProbeText = require(Shared:WaitForChild("ProbeText"))
local Simulation = require(Shared:WaitForChild("Simulation"))
local state = ReplicatedStorage:WaitForChild("FoundryState")

local SUMMARY_EVERY = 2
-- A quiet stretch still gets a line this often, so the log shows the probe is alive.
local QUIET_EVERY = 30
-- The server's view of the owner (see NetProbe on the server) goes in the log this long after joining, and whenever the
-- player has been walking in the last couple of seconds.
local SERVER_VIEW_AT_START = 20
local HITCH = 0.05
local JUMP_LINES = 6
local FLAT = Vector3.new(1, 0, 1)

type Window = {
	time: number,
	frames: number,
	worst: number,
	hitches: number,
	jumps: number,
	jumpsBack: number,
	worstJump: number,
	jumpLines: number,
	-- Seconds spent trying to walk, the studs a walk at WalkSpeed would have covered meanwhile, and the studs actually
	-- covered in the direction the player was trying to go.
	walking: number,
	expected: number,
	along: number,
	falling: number,
	gapWorst: number,
	clientStart: Vector3?,
	clientEnd: Vector3?,
	serverStart: Vector3?,
	serverEnd: Vector3?,
	-- This client's view of its character and inputs, taken the first time in the window the player tried to walk.
	clientView: string?,
}

local function newWindow(): Window
	return {
		time = 0,
		frames = 0,
		worst = 0,
		hitches = 0,
		jumps = 0,
		jumpsBack = 0,
		worstJump = 0,
		jumpLines = 0,
		walking = 0,
		expected = 0,
		along = 0,
		falling = 0,
		gapWorst = 0,
		clientStart = nil,
		clientEnd = nil,
		serverStart = nil,
		serverEnd = nil,
		clientView = nil,
	}
end

local function point(at: Vector3?): string
	return if at ~= nil then string.format("%.1f,%.1f,%.1f", at.X, at.Y, at.Z) else "-"
end

local function moved(from: Vector3?, to: Vector3?): number
	return if from ~= nil and to ~= nil then ((to - from) * FLAT).Magnitude else 0
end

local function pingMs(): number
	return math.floor(player:GetNetworkPing() * 1000 + 0.5)
end

local gui = Instance.new("ScreenGui")
gui.Name = "NetProbe"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")
local readout = Instance.new("TextLabel")
readout.Name = "Readout"
readout.AnchorPoint = Vector2.new(0, 1)
readout.Position = UDim2.new(0, 10, 1, -6)
readout.Size = UDim2.fromOffset(760, 16)
readout.BackgroundTransparency = 1
readout.Font = Enum.Font.GothamMedium
readout.TextSize = 12
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextColor3 = Color3.fromRGB(200, 210, 230)
readout.TextStrokeTransparency = 0.5
readout.Text = ""
readout.Parent = gui

local qualityOk, quality = pcall(function()
	return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name
end)
local authorityOk, authority = pcall(function()
	return (Workspace :: any).AuthorityMode.Name
end)
print(
	string.format(
		"[REALSTEEL][probe] start  version %d  authority %s  streaming %s  quality %s  memory %d MB",
		game.PlaceVersion,
		if authorityOk then tostring(authority) else "?",
		tostring(Workspace.StreamingEnabled),
		if qualityOk then tostring(quality) else "?",
		math.floor(Stats:GetTotalMemoryUsageMb())
	)
)

local window = newWindow()
local sinceLine = 0
local lastPosition: Vector3? = nil
local lastCharacter: Model? = nil
local metrics = Simulation.getMetrics()
local rollbacksBefore = metrics.rollbacks
local resimBefore = metrics.resimSteps
local started = os.clock()
local walkedLately = false

task.spawn(function()
	local serverView = ReplicatedStorage:WaitForChild("ProbeServer", 60)
	if serverView == nil or not serverView:IsA("RemoteEvent") then
		return
	end
	serverView.OnClientEvent:Connect(function(text: unknown)
		if type(text) == "string" and (walkedLately or os.clock() - started < SERVER_VIEW_AT_START) then
			print("[REALSTEEL][probe][server] " .. text)
		end
	end)
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	window.time += deltaTime
	window.frames += 1
	window.worst = math.max(window.worst, deltaTime)
	if deltaTime > HITCH then
		window.hitches += 1
	end

	local serverRoot = player:GetAttribute("ProbeServerRoot")
	local serverPosition: Vector3? = if typeof(serverRoot) == "Vector3" then serverRoot else nil
	if serverPosition ~= nil then
		window.serverStart = window.serverStart or serverPosition
		window.serverEnd = serverPosition
	end

	local character = player.Character
	if character ~= lastCharacter then
		lastCharacter = character
		lastPosition = nil
	end
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if root ~= nil and root:IsA("BasePart") and humanoid ~= nil then
		local position = root.Position
		window.clientStart = window.clientStart or position
		window.clientEnd = position
		if serverPosition ~= nil then
			window.gapWorst = math.max(window.gapWorst, ((position - serverPosition) * FLAT).Magnitude)
		end
		local humanoidState = humanoid:GetState()
		if humanoidState == Enum.HumanoidStateType.Freefall then
			window.falling += deltaTime
		end

		local intent = humanoid.MoveDirection * FLAT
		local trying = intent.Magnitude > 0.1
		if trying then
			walkedLately = true
			if window.clientView == nil then
				window.clientView = ProbeText.character(character) .. "  | " .. ProbeText.inputs(player)
			end
		end
		local previous = lastPosition
		if previous ~= nil then
			local step = (position - previous) * FLAT
			if trying then
				window.walking += deltaTime
				window.expected += humanoid.WalkSpeed * deltaTime
				window.along += step:Dot(intent.Unit)
			end
			-- Farther in one frame than walking could carry it: a correction (respawns and teleports are farther still). The
			-- simulation steps at 60 Hz, so a fast frame can still hold two of its steps.
			local size = step.Magnitude
			if size > humanoid.WalkSpeed * math.max(deltaTime, 1 / 30) * 1.6 + 0.35 and size < 60 then
				local back = trying and step:Dot(intent.Unit) < 0
				window.jumps += 1
				window.worstJump = math.max(window.worstJump, size)
				if back then
					window.jumpsBack += 1
				end
				if window.jumpLines < JUMP_LINES then
					window.jumpLines += 1
					print(
						string.format(
							"[REALSTEEL][probe] jump %.2f studs%s  frame %.0f ms  from %s to %s  server %s  ping %d ms  %s",
							size,
							if back then " BACK" else "",
							deltaTime * 1000,
							point(previous),
							point(position),
							point(serverPosition),
							pingMs(),
							humanoidState.Name
						)
					)
				end
			end
		end
		lastPosition = position
	end

	if window.time < SUMMARY_EVERY then
		return
	end
	sinceLine += window.time
	local rollbacks = metrics.rollbacks - rollbacksBefore
	local resim = metrics.resimSteps - resimBefore
	rollbacksBefore = metrics.rollbacks
	resimBefore = metrics.resimSteps
	local fps = window.frames / window.time
	local progress = if window.expected > 1
		then string.format("%d%%", math.floor(window.along / window.expected * 100 + 0.5))
		else "-"
	local serverFps = state:GetAttribute("ServerFps")
	local serverWorst = state:GetAttribute("ServerWorstMs")
	local serverPhysics = state:GetAttribute("ServerPhysicsFps")
	readout.Text = string.format(
		"v%d  ·  %d ms  ·  %.0f fps (worst %.0f ms)  ·  server %s fps  ·  rollbacks %d  ·  jumps %d  ·  walk %s",
		game.PlaceVersion,
		pingMs(),
		fps,
		window.worst * 1000,
		tostring(serverFps),
		rollbacks,
		window.jumps,
		progress
	)
	local eventful = window.walking > 0 or window.jumps > 0 or window.hitches > 0
	if eventful or sinceLine >= QUIET_EVERY then
		sinceLine = 0
		print(
			string.format(
				"[REALSTEEL][probe] v%d  ping %d ms  fps %.0f  worst %.0f ms  hitches %d  rollbacks %d  resim %d  jumps %d (%d back, worst %.1f)  walking %.1f s  progress %s  client moved %.1f  server moved %.1f  gap %.1f  falling %.1f s  server %s fps (physics %s, worst %s ms)  memory %d MB  at %s",
				game.PlaceVersion,
				pingMs(),
				fps,
				window.worst * 1000,
				window.hitches,
				rollbacks,
				resim,
				window.jumps,
				window.jumpsBack,
				window.worstJump,
				window.walking,
				progress,
				moved(window.clientStart, window.clientEnd),
				moved(window.serverStart, window.serverEnd),
				window.gapWorst,
				window.falling,
				tostring(serverFps),
				tostring(serverPhysics),
				tostring(serverWorst),
				math.floor(Stats:GetTotalMemoryUsageMb()),
				point(window.clientEnd)
			)
		)
	end
	if window.clientView ~= nil then
		print("[REALSTEEL][probe][client] " .. window.clientView)
	end
	walkedLately = window.walking > 0
	window = newWindow()
end)
