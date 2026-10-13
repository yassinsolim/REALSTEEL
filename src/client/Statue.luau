--!strict

-- Client: the champion's statue on its pedestal north of the main ring (see Foundry's buildStatue). The server says who
-- holds the title (ChampionId, ChampionName and ChampionDefenses on FoundryState, see Records); the statue is their robot,
-- built the way their garage has it, cast in gold and frozen in its victory pose. While the title is vacant the pedestal
-- holds a stock ANVIL in dull steel. The plaque under it says whose it is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoundryLayout = require(Shared:WaitForChild("FoundryLayout"))
local Loadout = require(Shared:WaitForChild("Loadout"))
local Looks = require(Shared:WaitForChild("Looks"))
local RobotSkeleton = require(Shared:WaitForChild("RobotSkeleton"))
local FighterView = require(script.Parent:WaitForChild("FighterView"))
local RobotFrames = require(script.Parent:WaitForChild("RobotFrames"))
local RobotRig = require(script.Parent:WaitForChild("RobotRig"))

export type Statue = {
	-- Call every frame; it only does work when the title or the champion's garage changed.
	step: (now: number) -> (),
}

local Statue = {}

local GOLD = Color3.fromRGB(255, 196, 92)
local GOLD_DEEP = Color3.fromRGB(205, 146, 58)
local STEEL = Color3.fromRGB(92, 98, 114)
local STEEL_DEEP = Color3.fromRGB(58, 62, 74)
local MUTED = Color3.fromRGB(140, 154, 184)
local SYNC_SECONDS = 0.5
-- Where in the victory loop the statue is frozen: both fists up.
local POSE_AT = 0

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function text(instance: Instance, name: string): string
	local value = instance:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

local function line(parent: Instance, font: Enum.Font, color: Color3, y: number, height: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.TextColor3 = color
	item.TextScaled = true
	item.Position = UDim2.fromScale(0.04, y)
	item.Size = UDim2.fromScale(0.92, height)
	item.Text = ""
	item.Parent = parent
	return item
end

function Statue.new(robot: FighterView.Robot, state: Instance): Statue
	local folder = Instance.new("Folder")
	folder.Name = "Statue"
	folder.Parent = Workspace
	-- A statue is cast metal, so it is drawn without the worn paint.
	local stock = RobotFrames.get(robot, nil)
	local rig = RobotRig.new(folder, stock.rig, GOLD, stock.template)
	local pose = RobotSkeleton.newPose(robot.rig)
	local victory = robot.clips.Victory or robot.clips.Idle
	RobotSkeleton.sample(victory, POSE_AT, pose)

	local heading: TextLabel? = nil
	local detail: TextLabel? = nil
	-- The plaque streams in with the hall.
	task.spawn(function()
		local plaque = Workspace:WaitForChild("Foundry"):WaitForChild("StatuePlaque")
		if not plaque:IsA("BasePart") then
			return
		end
		local surface = Instance.new("SurfaceGui")
		surface.Name = "StatuePlaque"
		surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		surface.Adornee = plaque
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 60
		surface.LightInfluence = 0
		surface.Brightness = 1.3
		surface.ResetOnSpawn = false
		surface.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		heading = line(surface, Enum.Font.Michroma, GOLD, 0.06, 0.46)
		detail = line(surface, Enum.Font.GothamBold, MUTED, 0.58, 0.34)
	end)

	local shownRig = ""
	local shownPlaque = ""
	local lastSync = -math.huge

	local function refresh()
		local holderId = number(state, "ChampionId")
		local holder = if holderId ~= 0 then Players:GetPlayerByUserId(holderId) else nil
		local champion = holderId ~= 0
		local loadout = if holder ~= nil then number(holder, "GarageLoadout") else Loadout.DefaultCode
		local look = if holder ~= nil then number(holder, "GarageLook") else Looks.encode(Looks.default())
		local defenses = number(state, "ChampionDefenses")
		local name = text(state, "ChampionName")

		-- The robot and the plaque are each redone only when what they show changed. Whether the champion's Player has
		-- reached this client yet counts too: until it has, their build is not known.
		local rigKey = `{champion}:{holder ~= nil}:{loadout}:{look}`
		if rigKey ~= shownRig then
			shownRig = rigKey
			local choice = Loadout.decode(loadout)
			local chosen = Looks.decode(look)
			local frame = RobotFrames.get(robot, Looks.frameFor(choice, chosen))
			RobotRig.setFrame(rig, frame.rig, frame.template)
			RobotRig.setScale(rig, Loadout.scale(loadout))
			RobotRig.setKits(rig, Looks.kitsFor(choice, chosen))
			if champion then
				RobotRig.setPalette(rig, GOLD, GOLD_DEEP)
				RobotRig.setFinish(rig, Enum.Material.Metal, 0.35)
			else
				RobotRig.setPalette(rig, STEEL, STEEL_DEEP)
				RobotRig.setFinish(rig, Enum.Material.Metal, 0.05)
			end
			RobotRig.place(rig, pose, FoundryLayout.Statue, false)
		end

		local top = heading
		local bottom = detail
		local plaqueKey = `{champion}:{name}:{defenses}`
		if top ~= nil and bottom ~= nil and plaqueKey ~= shownPlaque then
			shownPlaque = plaqueKey
			if champion then
				top.Text = name
				top.TextColor3 = GOLD
				bottom.Text = if defenses == 1 then "CHAMPION  ·  1 DEFENSE" else `CHAMPION  ·  {defenses} DEFENSES`
			else
				top.Text = "TITLE VACANT"
				top.TextColor3 = MUTED
				bottom.Text = "WIN A 1V1 TO CLAIM IT"
			end
		end
	end

	return {
		step = function(now: number)
			if now - lastSync >= SYNC_SECONDS then
				lastSync = now
				refresh()
			end
		end,
	}
end

return Statue
