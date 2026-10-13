--!strict

-- Client: the pads in front of the main ring as the server reports them (see Pads on the server). A pad someone stands
-- on glows brighter with their name over it, and pulses while it counts down; over the 1V1 pads both names show, and
-- what the pair is waiting for. It also tells the hall's chip what the local player's own pad is doing (see LobbyHud).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local FoundryLayout = require(Shared:WaitForChild("FoundryLayout"))

export type PadView = {
	-- Call every frame. Returns the chip's line for the local player's pad, or "" when they stand on none.
	step: () -> string,
}

type Sign = {
	main: TextLabel,
	sub: TextLabel,
}

type Entry = {
	pad: FoundryLayout.Pad,
	sign: Sign?,
	glow: BasePart?,
	base: Color3,
}

local PadView = {}

local NAME_LENGTH = 14
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 182, 206)
local AMBER = Color3.fromRGB(255, 200, 90)

local function nameOf(id: number): string
	if id == Players.LocalPlayer.UserId then
		return "YOU"
	end
	local player = Players:GetPlayerByUserId(id)
	return string.upper(string.sub(if player ~= nil then player.DisplayName else "PLAYER", 1, NAME_LENGTH))
end

-- A label floating over a spot on the floor, `width` by `height` studs: a big line and a small one under it.
local function newSign(folder: Instance, at: Vector3, width: number, height: number): Sign
	local anchor = Instance.new("Part")
	anchor.Name = "PadSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = at
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromScale(width, height)
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Adornee = anchor
	gui.Parent = anchor
	local function line(name: string, top: number, size: number, font: Enum.Font): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0, top)
		text.Size = UDim2.fromScale(1, size)
		text.Font = font
		text.TextScaled = true
		text.TextColor3 = WHITE
		text.TextStrokeTransparency = 0.35
		text.Text = ""
		text.Parent = gui
		return text
	end
	return {
		main = line("Main", 0, 0.62, Enum.Font.GothamBlack),
		sub = line("Sub", 0.64, 0.36, Enum.Font.GothamBold),
	}
end

function PadView.new(state: Instance): PadView
	local localId = Players.LocalPlayer.UserId
	local folder = Instance.new("Folder")
	folder.Name = "PadSigns"
	folder.Parent = Workspace

	local entries: { Entry } = {}
	local versusMiddle = Vector3.zero
	local versusCount = 0
	for _, pad in FoundryLayout.Pads do
		local entry: Entry = { pad = pad, sign = nil, glow = nil, base = WHITE }
		if pad.kind ~= "versus" then
			entry.sign = newSign(folder, pad.position + Vector3.new(0, 3.6, 0), 5, 1.5)
		else
			versusMiddle += pad.position
			versusCount += 1
		end
		table.insert(entries, entry)
	end
	local versusSign = if versusCount > 0
		then newSign(folder, versusMiddle / versusCount + Vector3.new(0, 3.8, 0), 9, 2)
		else nil

	local padsFolder: Instance? = nil
	local hall: Instance? = nil
	local function boardOf(name: string): Instance?
		if padsFolder == nil then
			padsFolder = state:FindFirstChild("Pads")
		end
		return if padsFolder ~= nil then padsFolder:FindFirstChild(name) else nil
	end
	local function number(board: Instance?, name: string): number
		local value = if board ~= nil then board:GetAttribute(name) else nil
		return if type(value) == "number" then value else 0
	end

	return {
		step = function(): string
			local serverNow = Workspace:GetServerTimeNow()
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
			if hall == nil then
				hall = Workspace:FindFirstChild("Foundry")
			end
			local mine = ""
			local versusHolders: { [number]: number } = {}
			local versusLeft: number? = nil
			for _, entry in entries do
				local pad = entry.pad
				local board = boardOf(pad.name)
				local holder = number(board, "Holder")
				local ends = number(board, "Ends")
				local left = if ends > 0 then math.max(ends - serverNow, 0) else nil

				-- The glow brightens under a player, and pulses while the pad counts down.
				local glow = entry.glow
				if glow == nil and hall ~= nil then
					local found = (hall :: Instance):FindFirstChild("PadGlow" .. pad.name)
					if found ~= nil and found:IsA("BasePart") then
						glow = found
						entry.glow = found
						entry.base = found.Color
					end
				end
				if glow ~= nil then
					local lift = if holder == 0 then 0 elseif left ~= nil then 0.25 + 0.35 * pulse else 0.3
					glow.Color = entry.base:Lerp(WHITE, lift)
				end

				local what = if pad.kind == "bot"
					then `BOT {BotBrain.Levels[math.clamp(pad.level, 1, BotBrain.LevelCount)].name}`
					else "TRAINING"
				if pad.kind == "versus" then
					versusHolders[pad.seat] = holder
					if left ~= nil then
						versusLeft = left
					end
				else
					local sign = entry.sign
					if sign ~= nil then
						sign.main.Text = if holder ~= 0 then nameOf(holder) else ""
						sign.sub.Text = if left ~= nil then `{what} IN {math.ceil(left)}` else ""
						sign.sub.TextColor3 = AMBER
					end
					if holder == localId then
						mine = if left ~= nil then `{what} IN {math.ceil(left)} · STEP OFF TO CANCEL` else what
					end
				end
			end

			-- The 1V1 pads: who stands on each, and what the pair is waiting for.
			local blue, red = versusHolders[1] or 0, versusHolders[2] or 0
			if versusSign ~= nil then
				if blue == 0 and red == 0 then
					versusSign.main.Text = ""
					versusSign.sub.Text = "STAND ON A PAD TO FIGHT"
					versusSign.sub.TextColor3 = MUTED
				else
					local left = if blue ~= 0 then nameOf(blue) else "?"
					local right = if red ~= 0 then nameOf(red) else "?"
					versusSign.main.Text = `{left}  vs  {right}`
					versusSign.sub.Text = if versusLeft ~= nil
						then `FIGHT IN {math.ceil(versusLeft)}`
						else "WAITING FOR A CHALLENGER"
					versusSign.sub.TextColor3 = if versusLeft ~= nil then AMBER else MUTED
				end
			end
			if blue == localId or red == localId then
				local rival = if blue == localId then red else blue
				mine = if versusLeft ~= nil
					then `1V1 vs {nameOf(rival)}  ·  FIGHT IN {math.ceil(versusLeft)}`
					else "WAITING FOR A CHALLENGER · STEP OFF TO CANCEL"
			end
			return mine
		end,
	}
end

return PadView
