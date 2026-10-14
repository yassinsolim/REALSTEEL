--!strict

-- The server half of the place owner's connection probe (see NetProbe on the client): how steadily the server keeps its
-- frames, and where the server has the owner's character, ten times a second. Nobody else's character is published.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROOT_EVERY = 0.1

local state = ReplicatedStorage:WaitForChild("FoundryState")

local function watched(player: Player): boolean
	return RunService:IsStudio() or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

local frames = 0
local worst = 0
local elapsed = 0
local sinceRoot = 0

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
end)
