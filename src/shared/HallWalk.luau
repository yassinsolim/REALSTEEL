--!strict

-- Walks the characters in the hall. The server simulates every character (Workspace.AuthorityMode), so a character
-- only gets anywhere when the server hears its player's input. Roblox's newer player scripts send that through input
-- actions of their own (Player.InputContexts); a live server that runs the classic player scripts instead moves each
-- character on its own client only, while the server holds it at the spawn and keeps correcting the client back. For
-- those players HallWalk carries Roblox's controls through their HallInputs (see InputSetup): each client fires them
-- every frame from what its controls want, and inside the simulation the server (for every player) and the client (for
-- its own) turn them into the same Humanoid:Move and jump, the way Roblox's own scripts do, so the prediction holds.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputSetup = require(script.Parent.InputSetup)

-- What the simulation needs of one player, looked up outside it (see refresh).
type Walker = {
	humanoid: Humanoid?,
	actions: InputSetup.HallActions?,
	-- Roblox's own player scripts carry this player's walking, so HallWalk leaves it alone.
	engine: boolean,
}

local REFRESH_EVERY = 0.5

local HallWalk = {}

local walkers: { [Player]: Walker } = {}

-- Whether Roblox's own player scripts carry this player's walking to the server, so HallWalk must stay out of it.
function HallWalk.engineDrives(player: Player): boolean
	local contexts = player:FindFirstChild("InputContexts")
	return contexts ~= nil and contexts:FindFirstChild("CharacterContext") ~= nil
end

local function finite(value: number): number
	return if value == value and math.abs(value) ~= math.huge then value else 0
end

-- A camera-relative move vector (as Roblox's controllers give it, forward along -Z) turned into a world direction on
-- the ground, the way Roblox's ControlModule turns it.
local function cameraToWorld(relative: Vector3): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Vector2.zero
	end
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		local up = camera.CFrame.UpVector
		forward = Vector3.new(up.X, 0, up.Z)
		if forward.Magnitude < 1e-3 then
			return Vector2.zero
		end
	end
	forward = forward.Unit
	local right = forward:Cross(Vector3.yAxis)
	local world = right * relative.X - forward * relative.Z
	return Vector2.new(world.X, world.Z)
end

local function drive(walker: Walker)
	local humanoid = walker.humanoid
	local actions = walker.actions
	if walker.engine or humanoid == nil or actions == nil then
		return
	end
	-- Whatever a client sends, it walks at most at the humanoid's own speed.
	local walk = actions.walk:GetState() :: Vector2
	local x, z = finite(walk.X), finite(walk.Y)
	local length = math.sqrt(x * x + z * z)
	if length > 1 then
		x, z = x / length, z / length
	end
	humanoid:Move(Vector3.new(x, 0, z))
	humanoid.Jump = actions.jump:GetState() == true
end

-- Looks a player's humanoid and actions up again. Outside the simulation, which may only touch "Simulation Access" APIs.
local function refresh(player: Player, walker: Walker)
	walker.engine = HallWalk.engineDrives(player)
	walker.actions = InputSetup.findHall(player)
	local character = player.Character
	walker.humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
end

local function track(player: Player)
	local walker: Walker = { humanoid = nil, actions = nil, engine = false }
	walkers[player] = walker
	refresh(player, walker)
	player.CharacterAdded:Connect(function(character: Model)
		walker.humanoid = nil
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid ~= nil and humanoid:IsA("Humanoid") and player.Character == character then
			walker.humanoid = humanoid
		end
	end)
	player.CharacterRemoving:Connect(function()
		walker.humanoid = nil
	end)
end

-- Binds the walking to the simulation: on the server for every player, on a client for its own.
function HallWalk.start(): RBXScriptConnection
	if RunService:IsServer() then
		Players.PlayerAdded:Connect(track)
		Players.PlayerRemoving:Connect(function(player: Player)
			walkers[player] = nil
		end)
		for _, player in Players:GetPlayers() do
			track(player)
		end
	else
		track(Players.LocalPlayer)
	end
	-- The actions arrive with the player and Roblox's own contexts can arrive later, so both are looked up again now and
	-- then, besides the character on every spawn.
	local sinceRefresh = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		sinceRefresh += deltaTime
		if sinceRefresh >= REFRESH_EVERY then
			sinceRefresh = 0
			for player, walker in walkers do
				refresh(player, walker)
			end
		end
	end)
	return RunService:BindToSimulation(function()
		for _, walker in walkers do
			drive(walker)
		end
	end, Enum.StepFrequency.Hz60)
end

-- Client: what Roblox's controls want this frame, sent through the local player's HallInputs. The controls are the
-- classic player scripts' ControlModule, which works out a world direction (from the keys, thumbstick, touch or click to
-- move, and the camera) and whether to jump. While the game rests them (a card is up, the garage is open or the player
-- is in a ring) their controller is off and this sends standing still.
export type Feed = {
	setControls: (controls: any) -> (),
}

function HallWalk.feed(): Feed
	local player = Players.LocalPlayer
	local controls: any = nil
	local bindings: InputSetup.HallScripted? = nil
	local sentWalk = Vector2.zero
	local sentJump = false

	-- Right after Roblox's ControlModule, which updates at the Input priority, and before the simulation steps.
	RunService:BindToRenderStep("HallWalkInput", Enum.RenderPriority.Input.Value + 1, function()
		if HallWalk.engineDrives(player) then
			return
		end
		if bindings == nil then
			bindings = InputSetup.findHallScripted(player)
		end
		local scripted = bindings
		if scripted == nil then
			return
		end
		local walk = Vector2.zero
		local jump = false
		if controls ~= nil then
			pcall(function()
				local active = controls.activeController
				local touchJump = controls.touchJumpController
				if active ~= nil and active.enabled then
					local vector = controls.inputMoveVector
					if typeof(vector) == "Vector3" then
						walk = Vector2.new(vector.X, vector.Z)
					else
						walk = cameraToWorld(controls:GetMoveVector())
					end
					jump = active:GetIsJumping() == true
				end
				if touchJump ~= nil and touchJump:GetIsJumping() == true then
					jump = true
				end
			end)
		end
		if walk ~= sentWalk then
			sentWalk = walk
			scripted.walk:Fire(walk)
		end
		if jump ~= sentJump then
			sentJump = jump
			scripted.jump:Fire(jump)
		end
	end)

	return {
		setControls = function(value: any)
			controls = value
		end,
	}
end

return HallWalk
