--!strict

-- Client: the scoreboard on the four faces of a screen hung over a ring: the big one over the main ring (Face1 to Face4 in
-- the hall) and the small ones over the pits (Face1 to Face4 in each pit's model). It shows who is fighting with their
-- health bars, the clock and the round, and who is next; with nothing on in the ring it shows the ring's name. Drawn
-- locally on SurfaceGuis and refreshed a few times a second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local FightSim = require(Shared:WaitForChild("FightSim"))
local MatchFlow = require(Shared:WaitForChild("MatchFlow"))
local MatchView = require(script.Parent:WaitForChild("MatchView"))

export type Info = {
	view: MatchView.View,
	-- The fighters in slot order: slot 1 shows on the left of every face, slot 2 on the right.
	left: FightSim.Fighter,
	right: FightSim.Fighter,
	nameLeft: string,
	nameRight: string,
	nextUp: string,
}

export type Jumbotron = {
	update: (info: Info) -> (),
}

export type Options = {
	-- Finds the screen's faces, waiting for them to stream in. Called once, on a thread of its own.
	faces: () -> { BasePart },
	-- What the screen says with nothing on in its ring.
	title: string,
	subtitle: string,
}

type Face = {
	idle: Frame,
	live: Frame,
	names: { TextLabel },
	fills: { Frame },
	clock: TextLabel,
	round: TextLabel,
	nextUp: TextLabel,
}

local Jumbotron = {}

local TEAL = Color3.fromRGB(64, 214, 232)
local AMBER = Color3.fromRGB(255, 200, 90)
local BLUE = Color3.fromRGB(70, 140, 255)
local RED = Color3.fromRGB(255, 84, 70)
local TRACK = Color3.fromRGB(26, 32, 50)
local WARN = Color3.fromRGB(255, 96, 84)
local REFRESH = 1 / 12

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

local function newFace(part: BasePart, gui: Instance, options: Options): Face
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Jumbotron"
	surface.Adornee = part
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.LightInfluence = 0
	surface.Brightness = 1.4
	surface.ResetOnSpawn = false
	surface.Parent = gui

	local idle = Instance.new("Frame")
	idle.BackgroundTransparency = 1
	idle.Size = UDim2.fromScale(1, 1)
	idle.Parent = surface
	local title = text(idle, Enum.Font.Michroma, AMBER, UDim2.fromScale(0.06, 0.24), UDim2.fromScale(0.88, 0.3))
	title.Text = options.title
	local sub = text(idle, Enum.Font.GothamBold, TEAL, UDim2.fromScale(0.2, 0.58), UDim2.fromScale(0.6, 0.12))
	sub.Text = options.subtitle

	local live = Instance.new("Frame")
	live.BackgroundTransparency = 1
	live.Size = UDim2.fromScale(1, 1)
	live.Visible = false
	live.Parent = surface
	local names: { TextLabel } = {}
	local fills: { Frame } = {}
	for side = 1, 2 do
		local x = if side == 1 then 0.04 else 0.56
		local name =
			text(live, Enum.Font.GothamBold, Color3.new(1, 1, 1), UDim2.fromScale(x, 0.07), UDim2.fromScale(0.4, 0.13))
		name.TextXAlignment = if side == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		names[side] = name
		local track = Instance.new("Frame")
		track.BackgroundColor3 = TRACK
		track.BorderSizePixel = 0
		track.Position = UDim2.fromScale(x, 0.24)
		track.Size = UDim2.fromScale(0.4, 0.1)
		track.Parent = live
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = if side == 1 then BLUE else RED
		fill.BorderSizePixel = 0
		fill.AnchorPoint = Vector2.new(if side == 1 then 0 else 1, 0)
		fill.Position = UDim2.fromScale(if side == 1 then 0 else 1, 0)
		fill.Size = UDim2.fromScale(1, 1)
		fill.Parent = track
		fills[side] = fill
	end
	local clock = text(live, Enum.Font.GothamBlack, AMBER, UDim2.fromScale(0.34, 0.4), UDim2.fromScale(0.32, 0.3))
	local round =
		text(live, Enum.Font.GothamBold, Color3.new(1, 1, 1), UDim2.fromScale(0.3, 0.7), UDim2.fromScale(0.4, 0.1))
	local nextUp = text(live, Enum.Font.GothamBold, TEAL, UDim2.fromScale(0.06, 0.84), UDim2.fromScale(0.88, 0.1))
	return { idle = idle, live = live, names = names, fills = fills, clock = clock, round = round, nextUp = nextUp }
end

function Jumbotron.new(options: Options): Jumbotron
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local faces: { Face } = {}
	local lastRefresh = -math.huge

	-- The hall streams in, so the faces are picked up when they arrive.
	task.spawn(function()
		for _, part in options.faces() do
			table.insert(faces, newFace(part, gui, options))
		end
	end)

	return {
		update = function(info: Info)
			local now = os.clock()
			if now - lastRefresh < REFRESH then
				return
			end
			lastRefresh = now
			local view = info.view
			local live = not view.lobby
			local rounds = live and not view.training
			local seconds = math.ceil(view.timer / FightConfig.SimHz)
			local clockText = if rounds then tostring(seconds) else "TRAINING"
			local roundText = if not rounds
				then ""
				elseif view.phase == MatchFlow.Phase.MatchEnd then "FINAL"
				else `ROUND {view.round}  ·  {view.winsA} - {view.winsB}`
			local nextText = if info.nextUp ~= "" then `NEXT UP  {info.nextUp}` else ""
			for _, face in faces do
				face.idle.Visible = not live
				face.live.Visible = live
				if live then
					face.names[1].Text = info.nameLeft
					face.names[2].Text = info.nameRight
					face.fills[1].Size = UDim2.fromScale(math.clamp(info.left.hp / info.left.stats.maxHp, 0, 1), 1)
					face.fills[2].Size = UDim2.fromScale(math.clamp(info.right.hp / info.right.stats.maxHp, 0, 1), 1)
					face.clock.Text = clockText
					face.clock.TextColor3 = if rounds
							and seconds <= 10
							and view.phase == MatchFlow.Phase.Fight
						then WARN
						else AMBER
					face.round.Text = roundText
					face.nextUp.Text = nextText
				end
			end
		end,
	}
end

return Jumbotron
