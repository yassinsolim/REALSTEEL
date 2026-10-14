--!strict

-- The server half of the place owner's connection probe (see NetProbe on the client): how steadily the server keeps its
-- frames, where the server has the owner's character ten times a second, and once a second the server's whole view of
-- the owner (their input contexts with every action's state, their character's physics and humanoid), sent to the
-- owner's client to go in its log. Nobody else's character or inputs are sent anywhere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HallWalk = require(ReplicatedStorage.Shared.HallWalk)
local ProbeText = require(ReplicatedStorage.Shared.ProbeText)

local ROOT_EVERY = 0.1
local VIEW_EVERY = 1

local state = ReplicatedStorage:WaitForChild("FoundryState")
local remote = Instance.new("RemoteEvent")
remote.Name = "ProbeServer"
remote.Parent = ReplicatedStorage

local function watched(player: Player): boolean
	return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

-- What only the server knows about a player: its own copy of their character and inputs, and who it thinks
-- simulates the character.
local function view(player: Player): string
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local owner = "?"
	if root ~= nil and root:IsA("BasePart") then
		pcall(function()
			local networkOwner = root:GetNetworkOwner()
			owner = if networkOwner ~= nil then networkOwner.Name else "server"
		end)
	end
	return string.format(
		"v%d  %s  owner %s  walking by %s  | %s",
		game.PlaceVersion,
		ProbeText.character(character),
		owner,
		if HallWalk.engineDrives(player) then "Roblox's player scripts" else "HallWalk",
		ProbeText.inputs(player)
	)
end

local frames = 0
local worst = 0
local elapsed = 0
local sinceRoot = 0
local sinceView = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
	frames += 1
	worst = math.max(worst, deltaTime)
	elapsed += deltaTime
	if elapsed >= 1 then
		state:SetAttribute("ServerFps", math.floor(frames / elapsed + 0.5))
		state:SetAttribute("ServerWorstMs", math.floor(worst * 1000 + 0.5))
		state:SetAttribute("ServerPhysicsFps", math.floor(Workspace:GetRealPhysicsFPS() + 0.5))
		frames = 0
		worst = 0
		elapsed = 0
	end

	sinceRoot += deltaTime
	if sinceRoot >= ROOT_EVERY then
		sinceRoot = 0
		for _, player in Players:GetPlayers() do
			if watched(player) then
				local character = player.Character
				local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
				if root ~= nil and root:IsA("BasePart") then
					player:SetAttribute("ProbeServerRoot", root.Position)
				end
			end
		end
	end

	sinceView += deltaTime
	if sinceView >= VIEW_EVERY then
		sinceView = 0
		for _, player in Players:GetPlayers() do
			if watched(player) then
				local ok, text = pcall(view, player)
				remote:FireClient(player, if ok then text else "view failed: " .. tostring(text))
			end
		end
	end
end)
