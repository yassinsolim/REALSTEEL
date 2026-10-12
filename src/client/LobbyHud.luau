--!strict

-- Client: what the player sees while walking around the hall. A PLAY button (M or Select also open the PLAY card), a chip
-- that says where they stand in line for a fight with a LEAVE button, and short notices such as "PIT 1 IS YOURS". It
-- only reads what it is given; the server keeps the line (see Rings).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BotBrain = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BotBrain"))

export type Info = {
	-- Hidden while the player is in a ring, or while the PLAY card or the garage is up.
	hidden: boolean,
	-- What the player is in line for ("" when they are not), at which level for a bot, how many ahead of them want the
	-- same kind of fight, and for a 1v1 whether anyone else is waiting for one.
	queueMode: string,
	queueLevel: number,
	queueAhead: number,
	alone: boolean,
}

export type LobbyHud = {
	update: (info: Info) -> (),
	setCompact: (compact: boolean) -> (),
	notify: (text: string) -> (),
}

local LobbyHud = {}

local PANEL = Color3.fromRGB(8, 10, 18)
local AMBER = Color3.fromRGB(255, 200, 90)
local TEAL = Color3.fromRGB(64, 214, 232)
local MUTED = Color3.fromRGB(140, 154, 184)
local DARK = Color3.fromRGB(10, 14, 24)
local NOTICE_SECONDS = 2.6

local function round(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- The chip's line for a place in the queue.
function LobbyHud.describe(info: Info): string
	if info.queueMode == "" then
		return ""
	end
	local what = if info.queueMode == "bot"
		then `BOT {BotBrain.Levels[math.clamp(info.queueLevel, 1, BotBrain.LevelCount)].name}`
		elseif info.queueMode == "training" then "TRAINING"
		else "1V1"
	if info.queueMode == "versus" and info.alone then
		return "1V1  ·  WAITING FOR AN OPPONENT"
	end
	local place = if info.queueAhead == 0 then "YOU'RE NEXT" else `{info.queueAhead} AHEAD`
	return `IN LINE  ·  {what}  ·  {place}`
end

function LobbyHud.new(gui: ScreenGui, onPlay: () -> (), onLeave: () -> ()): LobbyHud
	local root = Instance.new("Frame")
	root.Name = "Lobby"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 15
	root.Parent = gui

	local play = Instance.new("TextButton")
	play.Name = "Play"
	play.AnchorPoint = Vector2.new(0.5, 1)
	play.BackgroundColor3 = AMBER
	play.BorderSizePixel = 0
	play.AutoButtonColor = true
	play.Text = "PLAY"
	play.Font = Enum.Font.GothamBlack
	play.TextColor3 = DARK
	play.Parent = root
	round(play, 10)
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(1, -12, 0.5, 0)
	hint.Size = UDim2.fromOffset(24, 20)
	hint.Text = "M"
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 13
	hint.TextColor3 = DARK
	hint.TextTransparency = 0.35
	hint.Parent = play
	play.Activated:Connect(onPlay)

	local chip = Instance.new("Frame")
	chip.Name = "Queue"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.BackgroundColor3 = PANEL
	chip.BackgroundTransparency = 0.12
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.Parent = root
	round(chip, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEAL
	stroke.Transparency = 0.45
	stroke.Thickness = 1.5
	stroke.Parent = chip
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = chip
	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.BackgroundColor3 = Color3.fromRGB(30, 40, 66)
	leave.BorderSizePixel = 0
	leave.Text = "LEAVE"
	leave.Font = Enum.Font.GothamBold
	leave.TextColor3 = MUTED
	leave.Parent = chip
	round(leave, 7)
	leave.Activated:Connect(onLeave)

	local notice = Instance.new("TextLabel")
	notice.Name = "Notice"
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.BackgroundTransparency = 1
	notice.Font = Enum.Font.GothamBlack
	notice.TextColor3 = AMBER
	notice.TextStrokeTransparency = 0.3
	notice.TextTransparency = 1
	notice.TextStrokeColor3 = Color3.new(0, 0, 0)
	notice.Parent = root
	local noticeToken = 0

	local compact = false
	local function layout()
		play.Size = if compact then UDim2.fromOffset(150, 44) else UDim2.fromOffset(200, 54)
		play.TextSize = if compact then 20 else 24
		play.Position = UDim2.new(0.5, 0, 1, if compact then -14 else -26)
		hint.Visible = not compact
		chip.Size = if compact then UDim2.fromOffset(330, 34) else UDim2.fromOffset(440, 42)
		chip.Position = UDim2.new(0.5, 0, 0, if compact then 46 else 62)
		status.Position = UDim2.fromOffset(14, 0)
		status.Size = UDim2.new(1, -(14 + 86), 1, 0)
		status.TextSize = if compact then 11 else 13
		leave.Position = UDim2.new(1, -6, 0.5, 0)
		leave.Size = if compact then UDim2.fromOffset(64, 24) else UDim2.fromOffset(74, 30)
		leave.TextSize = if compact then 11 else 12
		notice.Position = UDim2.new(0.5, 0, 0, if compact then 88 else 116)
		notice.Size = UDim2.fromOffset(640, if compact then 30 else 40)
		notice.TextSize = if compact then 22 else 30
	end
	layout()

	return {
		update = function(info: Info)
			play.Visible = not info.hidden
			local line = LobbyHud.describe(info)
			chip.Visible = not info.hidden and line ~= ""
			if status.Text ~= line then
				status.Text = line
			end
		end,
		setCompact = function(value: boolean)
			if value ~= compact then
				compact = value
				layout()
			end
		end,
		notify = function(content: string)
			noticeToken += 1
			local token = noticeToken
			notice.Text = content
			TweenService:Create(notice, TweenInfo.new(0.2), { TextTransparency = 0, TextStrokeTransparency = 0.3 })
				:Play()
			task.delay(NOTICE_SECONDS, function()
				if noticeToken == token then
					TweenService
						:Create(notice, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
						:Play()
				end
			end)
		end,
	}
end

return LobbyHud
