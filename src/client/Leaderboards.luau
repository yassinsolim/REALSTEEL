--!strict

-- Client: the two leaderboards on the north wall (see Foundry's buildBoards). The server publishes each as a JSON list in a
-- StringValue under FoundryState (BoardVersus, BoardBots) of { id, name, score }, best first, with the attribute
-- BoardScope saying whether they are all-time or this server's (see Records). Drawn locally on SurfaceGuis; the local
-- player's own line is picked out by their UserId, since display names are not unique.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FoundryLayout = require(Shared:WaitForChild("FoundryLayout"))

export type Leaderboards = {
	-- Call every frame; it redraws only when a board changed.
	step: (now: number) -> (),
}

type Row = {
	frame: Frame,
	rank: TextLabel,
	name: TextLabel,
	score: TextLabel,
}

type Panel = {
	-- The StringValue under FoundryState that holds this board's list.
	source: string,
	scope: TextLabel,
	empty: TextLabel,
	rows: { Row },
	shown: string,
}

local Leaderboards = {}

local ROWS = 10
local AMBER = Color3.fromRGB(255, 200, 90)
local TEAL = Color3.fromRGB(64, 214, 232)
local MUTED = Color3.fromRGB(140, 154, 184)
local HIGHLIGHT = Color3.fromRGB(30, 40, 66)
local REFRESH = 1

local function text(parent: Instance, font: Enum.Font, color: Color3, position: UDim2, size: UDim2): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.TextColor3 = color
	item.TextScaled = true
	item.Position = position
	item.Size = size
	item.Text = ""
	item.Parent = parent
	return item
end

local function newPanel(part: BasePart, board: FoundryLayout.Board, gui: Instance): Panel
	local surface = Instance.new("SurfaceGui")
	surface.Name = board.name
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.Adornee = part
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Brightness = 1.2
	surface.ResetOnSpawn = false
	surface.Parent = gui

	local title = text(surface, Enum.Font.Michroma, AMBER, UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.1))
	title.Text = board.title
	local scope = text(surface, Enum.Font.GothamBold, TEAL, UDim2.fromScale(0.25, 0.135), UDim2.fromScale(0.5, 0.045))
	local empty = text(surface, Enum.Font.GothamMedium, MUTED, UDim2.fromScale(0.1, 0.45), UDim2.fromScale(0.8, 0.06))
	empty.Text = "NO WINS YET  ·  BE THE FIRST"

	local rows: { Row } = {}
	for index = 1, ROWS do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = HIGHLIGHT
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromScale(0.05, 0.2 + (index - 1) * 0.078)
		frame.Size = UDim2.fromScale(0.9, 0.07)
		frame.Parent = surface
		local rank = text(frame, Enum.Font.GothamBold, MUTED, UDim2.fromScale(0, 0.1), UDim2.fromScale(0.1, 0.8))
		rank.Text = tostring(index)
		local name = text(
			frame,
			Enum.Font.GothamBold,
			Color3.new(1, 1, 1),
			UDim2.fromScale(0.13, 0.1),
			UDim2.fromScale(0.62, 0.8)
		)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local score = text(frame, Enum.Font.GothamBlack, AMBER, UDim2.fromScale(0.77, 0.1), UDim2.fromScale(0.23, 0.8))
		score.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { frame = frame, rank = rank, name = name, score = score }
	end
	return { source = board.name, scope = scope, empty = empty, rows = rows, shown = "" }
end

function Leaderboards.new(state: Instance): Leaderboards
	local localPlayer = Players.LocalPlayer
	local gui = localPlayer:WaitForChild("PlayerGui")
	local panels: { Panel } = {}
	local lastRefresh = -math.huge

	-- The hall streams in, so the panels are picked up when they arrive.
	task.spawn(function()
		local hall = Workspace:WaitForChild("Foundry")
		for _, board in FoundryLayout.Boards do
			local part = hall:WaitForChild(board.name)
			if part:IsA("BasePart") then
				table.insert(panels, newPanel(part, board, gui))
			end
		end
	end)

	local function draw(panel: Panel)
		local holder = state:FindFirstChild(panel.source)
		local raw = if holder ~= nil and holder:IsA("StringValue") then holder.Value else nil
		local scope = state:GetAttribute("BoardScope")
		local key = `{raw}|{scope}`
		if key == panel.shown then
			return
		end
		panel.shown = key
		panel.scope.Text = if type(scope) == "string" then scope else ""
		local entries: { any } = {}
		if type(raw) == "string" then
			local ok, decoded = pcall(function(): any
				return HttpService:JSONDecode(raw)
			end)
			if ok and type(decoded) == "table" then
				entries = decoded
			end
		end
		panel.empty.Visible = #entries == 0
		for index, row in panel.rows do
			local entry = entries[index]
			local name = if type(entry) == "table" and type(entry.name) == "string" then entry.name else nil
			local score = if type(entry) == "table" and type(entry.score) == "number" then entry.score else nil
			local id = if type(entry) == "table" and type(entry.id) == "number" then entry.id else 0
			row.frame.Visible = name ~= nil and score ~= nil
			if name ~= nil and score ~= nil then
				row.name.Text = name
				row.score.Text = tostring(math.floor(score))
				row.frame.BackgroundTransparency = if id == localPlayer.UserId then 0.2 else 1
				row.rank.TextColor3 = if index == 1 then AMBER else MUTED
			end
		end
	end

	return {
		step = function(now: number)
			if now - lastRefresh < REFRESH then
				return
			end
			lastRefresh = now
			for _, panel in panels do
				draw(panel)
			end
		end,
	}
end

return Leaderboards
