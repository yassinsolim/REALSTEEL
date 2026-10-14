--!strict

-- Client: the robots in the garage bays. Every player in the server has a bay (the server says which, as the attribute
-- Bay on the Player). Their robot stands on its lift with their parts and their paint, idling, so everyone can see what
-- everyone else is fighting with. The local player's robot wears what the garage screen shows at once, and their bay has
-- the prompt that opens the garage.

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

export type Bays = {
	-- Call every frame with the camera's position, and the codes the garage screen shows when it has any.
	step: (now: number, camera: Vector3, previewLoadout: number?, previewLook: number?) -> (),
	-- Where the local player's robot stands, facing out of its bay, or nil while they have no bay.
	mine: () -> CFrame?,
}

type Entry = {
	index: number,
	robot: RobotRig.RobotRig,
	-- The codes it was last dressed with.
	loadout: number,
	look: number,
	-- Where in the idle loop this robot is, so the robots do not all breathe in step.
	offset: number,
}

local Bays = {}

-- Robots farther than this from the camera stand still. The local player's robot always moves; the others take turns,
-- a couple a frame.
local ANIMATE_RADIUS = 90
local OTHERS_PER_FRAME = 2
local SYNC_SECONDS = 0.5

local function rgb(color: Looks.Rgb): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function materialOf(name: string): Enum.Material
	local item = Enum.Material:FromName(name)
	return if item ~= nil then item :: any else Enum.Material.Metal
end

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function Bays.new(robot: FighterView.Robot, onGarage: () -> ()): Bays
	local localPlayer = Players.LocalPlayer
	local folder = Instance.new("Folder")
	folder.Name = "BayRobots"
	folder.Parent = Workspace

	local entries: { [Player]: Entry } = {}
	local pose = RobotSkeleton.newPose(robot.rig)
	local idle = robot.clips.Idle
	local prompt: ProximityPrompt? = nil
	local promptBay = 0
	local lastSync = -math.huge
	local turn = 0

	-- Returns whether it dressed the robot anew (maybe rebuilt as another frame, whose parts need placing again).
	local function dress(entry: Entry, loadout: number, look: number): boolean
		if entry.loadout == loadout and entry.look == look then
			return false
		end
		entry.loadout = loadout
		entry.look = look
		local chosen = Looks.decode(look)
		local choice = Loadout.decode(loadout)
		-- A bay has no opponent, so "team" paint is the owner's own blue and steel.
		local colors = Looks.resolve(chosen, Looks.default())
		local frame = RobotFrames.get(robot, Looks.frameFor(choice, chosen))
		RobotRig.setFrame(entry.robot, frame.rig, frame.template, frame.wear)
		RobotRig.setScale(entry.robot, Loadout.scale(loadout))
		RobotRig.setKits(entry.robot, Looks.kitsFor(choice, chosen))
		RobotRig.setPalette(entry.robot, rgb(colors.accent), rgb(colors.armor))
		RobotRig.setFinish(
			entry.robot,
			materialOf(colors.finish.material),
			colors.finish.reflectance,
			colors.finish.name
		)
		local glow = colors.glow
		RobotRig.setGlow(
			entry.robot,
			if glow.color ~= nil or glow.animation ~= nil then rgb(glow.color or colors.accent) else nil,
			glow.animation
		)
		return true
	end

	local function place(entry: Entry, now: number)
		RobotSkeleton.sample(idle, now / idle.period + entry.offset, pose)
		RobotRig.place(entry.robot, pose, FoundryLayout.bay(entry.index), false)
	end

	local function remove(owner: Player)
		local entry = entries[owner]
		if entry ~= nil then
			entry.robot.folder:Destroy()
			entries[owner] = nil
		end
	end

	-- The prompt on the local player's lift. The hall streams in, so this keeps trying until the lift is there.
	local function updatePrompt(index: number)
		if index == promptBay and (index == 0 or prompt ~= nil) then
			return
		end
		local current = prompt
		if current ~= nil then
			current:Destroy()
			prompt = nil
		end
		promptBay = index
		if index == 0 then
			return
		end
		local hall = Workspace:FindFirstChild("Foundry")
		local bay = if hall ~= nil then hall:FindFirstChild("Bay" .. index) else nil
		local lift = if bay ~= nil then bay:FindFirstChild("Lift") else nil
		if lift == nil then
			return
		end
		local item = Instance.new("ProximityPrompt")
		item.Name = "Garage"
		item.ActionText = "GARAGE"
		item.ObjectText = "YOUR ROBOT"
		item.HoldDuration = 0
		item.MaxActivationDistance = 12
		item.RequiresLineOfSight = false
		item.Triggered:Connect(onGarage)
		item.Parent = lift
		prompt = item
	end

	local function sync(now: number)
		lastSync = now
		local present: { [Player]: boolean } = {}
		for _, owner in Players:GetPlayers() do
			local index = number(owner, "Bay")
			local entry: Entry? = entries[owner]
			if index < 1 or index > FoundryLayout.BayCount then
				remove(owner)
			else
				present[owner] = true
				if entry ~= nil and entry.index ~= index then
					remove(owner)
					entry = nil
				end
				if entry == nil then
					local frame = RobotFrames.get(robot, nil)
					local made: Entry = {
						index = index,
						robot = RobotRig.new(folder, frame.rig, rgb(Looks.Team.me.accent), frame.template, frame.wear),
						loadout = -1,
						look = -1,
						offset = (index * 0.37) % 1,
					}
					entries[owner] = made
					place(made, now)
				end
			end
		end
		for owner in entries do
			if not present[owner] then
				remove(owner)
			end
		end
		updatePrompt(number(localPlayer, "Bay"))
	end

	return {
		step = function(now: number, camera: Vector3, previewLoadout: number?, previewLook: number?)
			if now - lastSync >= SYNC_SECONDS then
				sync(now)
			end
			local others: { Entry } = {}
			for owner, entry in entries do
				local loadout = number(owner, "GarageLoadout")
				local look = number(owner, "GarageLook")
				if owner == localPlayer then
					loadout = previewLoadout or loadout
					look = previewLook or look
				end
				-- A robot dressed anew is put back in its bay at once, however far away it is: a new frame's parts start out
				-- at the template's pose.
				if dress(entry, loadout, look) or owner == localPlayer then
					place(entry, now)
				elseif (FoundryLayout.bay(entry.index).Position - camera).Magnitude < ANIMATE_RADIUS then
					table.insert(others, entry)
				end
			end
			for _ = 1, math.min(OTHERS_PER_FRAME, #others) do
				turn += 1
				place(others[(turn - 1) % #others + 1], now)
			end
		end,
		mine = function(): CFrame?
			local index = number(localPlayer, "Bay")
			if index < 1 or index > FoundryLayout.BayCount then
				return nil
			end
			return FoundryLayout.bay(index)
		end,
	}
end

return Bays
