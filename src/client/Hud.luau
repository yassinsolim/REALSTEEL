--!strict

-- The fight HUD: two health bars (each with a trailing damage bar and round pips) around a plate that shows the clock,
-- floating damage numbers, the ROUND / FIGHT! / K.O. banners, soft shading top and bottom, a red flush when the local
-- fighter is nearly down, and a card of controls that fades away after a while. It only reads the state it is given.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local FightSim = require(Shared:WaitForChild("FightSim"))
local MatchFlow = require(Shared:WaitForChild("MatchFlow"))
local MatchView = require(script.Parent:WaitForChild("MatchView"))

-- The local fighter is always drawn on the left, so the left bar is the local player's and the right bar is the opponent's.
export type Args = {
	left: FightSim.Fighter,
	right: FightSim.Fighter,
	winsLeft: number,
	winsRight: number,
	nameLeft: string,
	nameRight: string,
	-- Who took the last round: 1 the left fighter, 2 the right, 0 a draw or none yet.
	roundWinner: number,
	-- Whether the local player has a seat. A spectator sees names where a player sees ROUND WON and ROUND LOST.
	seated: boolean,
	view: MatchView.View,
}

export type Hud = {
	gui: ScreenGui,
	update: (args: Args) -> (),
	setCompact: (compact: boolean) -> (),
	-- Shows or hides the controls card. It also shows itself for the first moments of a session.
	setHelp: (visible: boolean) -> (),
	-- The whole fight HUD, hidden while the menu is up.
	setShown: (shown: boolean) -> (),
	-- A small readout in the top right corner, for example "42 ms  60 fps", tinted by how healthy the connection is.
	setStats: (text: string, color: Color3) -> (),
}

type Bar = {
	root: Frame,
	back: Frame,
	fill: Frame,
	lag: Frame,
	name: TextLabel,
	hp: TextLabel,
	pips: { Frame },
	alignRight: boolean,
	-- Fraction of full health the trailing bar is showing, and how long it waits before it catches up.
	lagValue: number,
	lagHold: number,
	lastHp: number,
	-- The maximum health the bar was last drawn for, so a build with a different maximum does not read as damage.
	lastMax: number,
}

local Hud = {}

local Phase = MatchFlow.Phase
local Reason = MatchFlow.Reason

local HELP_ROWS = {
	{ "A  D", "move" },
	{ "W  S", "sidestep" },
	{ "LMB  RMB", "punches" },
	{ "Q  E", "kicks" },
	{ "SHIFT", "guard" },
	{ "SPACE", "dash" },
	{ "M", "menu" },
}

local EMBLEM_WIDTH = 72
local GAP = 10
local TOP = 8
local HELP_SECONDS = 14
local LAG_HOLD = 0.45
local LAG_SPEED = 0.7
-- The ROUND banner shows for this many frames of the intro, then FIGHT!.
local ROUND_BANNER_FRAMES = 62
-- A KO banner shows alone for this long before the sub line appears.
local SUB_DELAY_FRAMES = 55
local DANGER_FRACTION = 0.3

-- Bar and name heights for the full layout and the slimmer touch layout, which has less screen to spare.
local FULL = { bar = 20, name = 16, nameSize = 12, hpSize = 10, vsSize = 16 }
local COMPACT = { bar = 14, name = 12, nameSize = 10, hpSize = 9, vsSize = 13 }

local TEAM_BLUE = Color3.fromRGB(70, 140, 255)
local TEAM_RED = Color3.fromRGB(255, 84, 70)
local LAG_COLOR = Color3.fromRGB(255, 236, 170)
local AMBER = Color3.fromRGB(255, 200, 90)
local TEAL = Color3.fromRGB(64, 214, 232)
local PANEL = Color3.fromRGB(8, 10, 18)
local WARN = Color3.fromRGB(255, 96, 84)

local function label(parent: Instance, name: string, font: Enum.Font, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = font
	text.TextSize = size
	text.Parent = parent
	return text
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.Transparency = transparency
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = parent
	return line
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function newBar(parent: Instance, name: string, alignRight: boolean, color: Color3): Bar
	local root = Instance.new("Frame")
	root.Name = name
	root.AnchorPoint = Vector2.new(if alignRight then 0 else 1, 0)
	root.Position = UDim2.new(0.5, (if alignRight then 1 else -1) * (EMBLEM_WIDTH / 2 + GAP), 0, TOP)
	root.Size = UDim2.fromOffset(300, FULL.bar + FULL.name + 4)
	root.BackgroundTransparency = 1
	root.Parent = parent

	local nameLabel = label(root, "Name", Enum.Font.Michroma, 12)
	nameLabel.Size = UDim2.new(1, -70, 0, FULL.name)
	nameLabel.Position = UDim2.fromOffset(if alignRight then 70 else 0, FULL.bar + 4)
	nameLabel.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	nameLabel.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 0, FULL.bar)
	back.BackgroundColor3 = PANEL
	back.BackgroundTransparency = 0.1
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Parent = root
	round(back, 4)
	stroke(back, color:Lerp(Color3.new(1, 1, 1), 0.45), 1.5, 0.35)

	local function strip(stripName: string, stripColor: Color3, order: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = stripName
		frame.Size = UDim2.fromScale(1, 1)
		frame.AnchorPoint = Vector2.new(if alignRight then 1 else 0, 0)
		frame.Position = UDim2.fromScale(if alignRight then 1 else 0, 0)
		frame.BackgroundColor3 = stripColor
		frame.BorderSizePixel = 0
		frame.ZIndex = order
		frame.Parent = back
		return frame
	end
	local lag = strip("Lag", LAG_COLOR, 1)
	local fill = strip("Fill", Color3.new(1, 1, 1), 2)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.new(0, 0, 0), 0.3))
	gradient.Parent = fill

	-- A soft highlight along the top and a tick every tenth, so the bar reads as a gauge.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.fromScale(1, 0.45)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.86
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 3
	gloss.Parent = back
	for tenth = 1, 9 do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. tenth
		tick.Size = UDim2.new(0, 1, 1, 0)
		tick.Position = UDim2.fromScale(tenth / 10, 0)
		tick.BackgroundColor3 = Color3.new(0, 0, 0)
		tick.BackgroundTransparency = 0.55
		tick.BorderSizePixel = 0
		tick.ZIndex = 4
		tick.Parent = back
	end

	local hpLabel = label(back, "Hp", Enum.Font.Michroma, 10)
	hpLabel.Size = UDim2.new(1, -12, 1, 0)
	hpLabel.Position = UDim2.fromOffset(6, 0)
	hpLabel.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	hpLabel.TextStrokeTransparency = 0.5
	hpLabel.ZIndex = 5

	-- Round pips at the inner end, under the bar: one per round needed to win the match.
	local pipRow = Instance.new("Frame")
	pipRow.Name = "Pips"
	pipRow.AnchorPoint = Vector2.new(if alignRight then 0 else 1, 0)
	pipRow.Position = UDim2.new(if alignRight then 0 else 1, 0, 0, FULL.bar + 6)
	pipRow.Size = UDim2.fromOffset(60, 12)
	pipRow.BackgroundTransparency = 1
	pipRow.Parent = root
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = if alignRight then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
	pipLayout.Padding = UDim.new(0, 5)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pipRow
	local pips: { Frame } = {}
	for index = 1, FightConfig.Match.roundsToWin do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. index
		pip.LayoutOrder = if alignRight then index else FightConfig.Match.roundsToWin - index + 1
		pip.Size = UDim2.fromOffset(11, 11)
		pip.BackgroundColor3 = Color3.fromRGB(26, 30, 46)
		pip.BorderSizePixel = 0
		pip.Parent = pipRow
		round(pip, 6)
		stroke(pip, AMBER, 1.5, 0.45)
		pips[index] = pip
	end

	return {
		root = root,
		back = back,
		fill = fill,
		lag = lag,
		name = nameLabel,
		hp = hpLabel,
		pips = pips,
		alignRight = alignRight,
		lagValue = 1,
		lagHold = 0,
		lastHp = FightConfig.MaxHp,
		lastMax = FightConfig.MaxHp,
	}
end

-- A damage number that pops in under the end of the bar, drifts down and fades.
local function popup(bar: Bar, amount: number)
	local text = label(bar.root, "Damage", Enum.Font.Michroma, 20)
	text.Size = UDim2.fromOffset(90, 24)
	text.AnchorPoint = Vector2.new(if bar.alignRight then 1 else 0, 0)
	text.Position = UDim2.new(if bar.alignRight then 1 else 0, 0, 0, bar.root.AbsoluteSize.Y + 4)
	text.Text = "-" .. math.floor(amount + 0.5)
	text.TextColor3 = AMBER
	text.TextXAlignment = if bar.alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	text.TextStrokeTransparency = 0.3
	local scale = Instance.new("UIScale")
	scale.Scale = 1.5
	scale.Parent = text
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(
		text,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = text.Position + UDim2.fromOffset(0, 18), TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(0.9, function()
		text:Destroy()
	end)
end

local function updateBar(bar: Bar, fighter: FightSim.Fighter, dt: number, name: string, wins: number, showPips: boolean)
	local maxHp = fighter.stats.maxHp
	local fraction = math.clamp(fighter.hp / maxHp, 0, 1)
	bar.fill.Size = UDim2.fromScale(fraction, 1)

	if maxHp ~= bar.lastMax then
		bar.lastMax = maxHp
		bar.lastHp = fighter.hp
		bar.lagValue = fraction
	end
	if fighter.hp < bar.lastHp - 0.5 then
		bar.lagHold = LAG_HOLD
		popup(bar, bar.lastHp - fighter.hp)
	end
	if fighter.hp > bar.lastHp + 0.5 then
		-- A new round fills the bar back up.
		bar.lagValue = fraction
	end
	bar.lastHp = fighter.hp

	if bar.lagHold > 0 then
		bar.lagHold -= dt
	elseif bar.lagValue > fraction then
		bar.lagValue = math.max(fraction, bar.lagValue - LAG_SPEED * dt)
	else
		bar.lagValue = fraction
	end
	bar.lag.Size = UDim2.fromScale(math.max(bar.lagValue, fraction), 1)

	bar.name.Text = name
	bar.hp.Text = tostring(math.floor(fighter.hp))
	for index, pip in bar.pips do
		pip.Visible = showPips
		pip.BackgroundColor3 = if index <= wins then AMBER else Color3.fromRGB(26, 30, 46)
	end
end

-- The middle of the top edge: a small plate that shows the clock, or VS outside a round match.
local function newEmblem(parent: Instance): (Frame, TextLabel)
	local plate = Instance.new("Frame")
	plate.Name = "Emblem"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, TOP)
	plate.Size = UDim2.fromOffset(EMBLEM_WIDTH, FULL.bar + FULL.name + 4)
	plate.BackgroundColor3 = PANEL
	plate.BackgroundTransparency = 0.1
	plate.BorderSizePixel = 0
	plate.Parent = parent
	round(plate, 6)
	stroke(plate, TEAL, 1.5, 0.45)

	local text = label(plate, "Clock", Enum.Font.Michroma, 16)
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "VS"
	text.TextColor3 = AMBER
	text.TextStrokeTransparency = 0.5
	return plate, text
end

-- A card of keys at the bottom left. A CanvasGroup lets the whole card fade as one.
local function newHelpCard(parent: Instance): CanvasGroup
	local card = Instance.new("CanvasGroup")
	card.Name = "Help"
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, 16, 1, -16)
	card.Size = UDim2.fromOffset(196, 14 + #HELP_ROWS * 21)
	card.BackgroundColor3 = PANEL
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.Parent = parent
	round(card, 8)
	stroke(card, TEAL, 1, 0.6)

	for index, row in HELP_ROWS do
		local y = 8 + (index - 1) * 21
		local keys = label(card, "Keys", Enum.Font.Michroma, 10)
		keys.Position = UDim2.fromOffset(12, y)
		keys.Size = UDim2.fromOffset(84, 18)
		keys.TextXAlignment = Enum.TextXAlignment.Left
		keys.TextColor3 = TEAL
		keys.Text = row[1]

		local action = label(card, "Action", Enum.Font.GothamMedium, 12)
		action.Position = UDim2.fromOffset(100, y)
		action.Size = UDim2.fromOffset(88, 18)
		action.TextXAlignment = Enum.TextXAlignment.Left
		action.TextColor3 = Color3.fromRGB(205, 214, 230)
		action.Text = row[2]
	end
	return card
end

-- Dark gradients along the top and bottom edges: they keep the bars readable and give the picture a frame.
local function newShading(parent: Instance)
	for _, top in { true, false } do
		local frame = Instance.new("Frame")
		frame.Name = if top then "ShadeTop" else "ShadeBottom"
		frame.AnchorPoint = Vector2.new(0, if top then 0 else 1)
		frame.Position = UDim2.fromScale(0, if top then 0 else 1)
		frame.Size = UDim2.new(1, 0, 0, if top then 110 else 140)
		frame.BackgroundColor3 = Color3.fromRGB(2, 4, 12)
		frame.BorderSizePixel = 0
		frame.ZIndex = 0
		frame.Parent = parent
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = if top then 90 else -90
		gradient.Transparency = NumberSequence.new(if top then 0.4 else 0.5, 1)
		gradient.Parent = frame
	end
end

-- Red edges that pulse while the local fighter is nearly out.
local function newDanger(parent: Instance): { Frame }
	local edges: { Frame } = {}
	for _, left in { true, false } do
		local frame = Instance.new("Frame")
		frame.Name = if left then "DangerLeft" else "DangerRight"
		frame.AnchorPoint = Vector2.new(if left then 0 else 1, 0)
		frame.Position = UDim2.fromScale(if left then 0 else 1, 0)
		frame.Size = UDim2.new(0, 220, 1, 0)
		frame.BackgroundColor3 = WARN
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.ZIndex = 0
		frame.Parent = parent
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = if left then 0 else 180
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame
		table.insert(edges, frame)
	end
	return edges
end

function Hud.new(): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "FightHud"
	gui.ResetOnSpawn = false
	-- The game's screens draw each object's children over it and order siblings by ZIndex. A ScreenGui made by script sorts
	-- all its descendants by ZIndex unless told to, which drew the garage panel (ZIndex 30) over its own buttons.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Keep the default safe area so the bars clear the Roblox top bar and device notches.
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	newShading(root)
	local danger = newDanger(root)
	local barA = newBar(root, "P1", false, TEAM_BLUE)
	local barB = newBar(root, "P2", true, TEAM_RED)
	local plate, clock = newEmblem(root)

	local banner = label(root, "Banner", Enum.Font.GothamBlack, 84)
	banner.Size = UDim2.fromOffset(640, 110)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.TextColor3 = AMBER
	banner.TextStrokeTransparency = 0.1
	banner.Visible = false
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	local sub = label(root, "BannerSub", Enum.Font.Michroma, 20)
	sub.Size = UDim2.fromOffset(640, 30)
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.new(0.5, 0, 0.32, 70)
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.3
	sub.Visible = false

	local stats = label(root, "Stats", Enum.Font.GothamMedium, 11)
	stats.AnchorPoint = Vector2.new(1, 0)
	stats.Position = UDim2.new(1, -10, 0, 4)
	stats.Size = UDim2.fromOffset(160, 14)
	stats.TextXAlignment = Enum.TextXAlignment.Right
	stats.TextTransparency = 0.25
	stats.TextStrokeTransparency = 0.6

	local help = newHelpCard(root)
	local helpPinned = false
	local helpShown = true
	local compactLayout = false
	-- A CanvasGroup faded to nothing still draws a faint ghost of itself, so the card is also hidden outright once it has
	-- faded. The touch layout never shows it.
	local function setHelp(visible: boolean)
		helpShown = visible
		if visible then
			help.Visible = not compactLayout
		end
		TweenService:Create(help, TweenInfo.new(0.35), { GroupTransparency = if visible then 0 else 1 }):Play()
		if not visible then
			task.delay(0.4, function()
				if not helpShown then
					help.Visible = false
				end
			end)
		end
	end
	task.delay(HELP_SECONDS, function()
		if not helpPinned then
			setHelp(false)
		end
	end)

	local function layout()
		local metrics = if compactLayout then COMPACT else FULL
		local screen = gui.AbsoluteSize.X
		local width = math.clamp(math.floor(screen * (if compactLayout then 0.3 else 0.34)), 190, 460)
			- EMBLEM_WIDTH / 2
			- GAP
		local height = metrics.bar + metrics.name + 4
		for _, bar in { barA, barB } do
			bar.root.Size = UDim2.fromOffset(width, height)
			bar.back.Size = UDim2.new(1, 0, 0, metrics.bar)
			bar.name.Size = UDim2.new(1, -70, 0, metrics.name)
			bar.name.Position = UDim2.fromOffset(if bar.alignRight then 70 else 0, metrics.bar + 4)
			bar.name.TextSize = metrics.nameSize
			bar.hp.TextSize = metrics.hpSize
		end
		plate.Size = UDim2.fromOffset(EMBLEM_WIDTH, height)
		clock.TextSize = metrics.vsSize
	end
	layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local lastTime = os.clock()
	local bannerKey = ""
	local clockSeconds = -1

	local function setBanner(text: string, subText: string, color: Color3, subColor: Color3?)
		if text == "" then
			if banner.Visible then
				TweenService:Create(banner, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 })
					:Play()
				TweenService:Create(sub, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 })
					:Play()
				local snapshot = bannerKey
				task.delay(0.22, function()
					if bannerKey == snapshot then
						banner.Visible = false
						sub.Visible = false
					end
				end)
			end
			return
		end
		banner.Text = text
		banner.TextColor3 = color
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0.1
		banner.Visible = true
		bannerScale.Scale = 1.7
		TweenService
			:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		sub.Text = subText
		sub.TextColor3 = subColor or Color3.new(1, 1, 1)
		sub.TextTransparency = 0
		sub.TextStrokeTransparency = 0.3
		sub.Visible = subText ~= ""
	end

	-- Chooses what the banner says from where the round flow is. Only a change of what it says restarts the animation.
	local function banners(args: Args)
		local view = args.view
		local key = ""
		local text = ""
		local subText = ""
		local color = AMBER
		local subColor: Color3? = nil
		if view.phase == Phase.Intro then
			if view.phaseFrame < ROUND_BANNER_FRAMES then
				local last = FightConfig.Match.roundsToWin - 1
				local final = args.winsLeft >= last and args.winsRight >= last
				text = if final then "FINAL ROUND" else `ROUND {view.round}`
				subText = `{args.nameLeft}   VS   {args.nameRight}`
				key = "round" .. view.round
			else
				text = "FIGHT!"
				key = "fight" .. view.round
			end
		elseif view.phase == Phase.RoundEnd then
			text = if view.reason == Reason.Time then "TIME" else "K.O."
			color = if view.reason == Reason.Time then AMBER else Color3.fromRGB(255, 120, 70)
			key = "end" .. view.round .. view.result
			if view.phaseFrame >= SUB_DELAY_FRAMES then
				local winner = if args.roundWinner == 1
					then args.left
					elseif args.roundWinner == 2 then args.right
					else nil
				if winner == nil then
					subText = "DRAW"
				elseif winner.hp >= winner.stats.maxHp then
					subText = "PERFECT"
					subColor = AMBER
				elseif args.seated then
					subText = if args.roundWinner == 1 then "ROUND WON" else "ROUND LOST"
				else
					subText = `{if args.roundWinner == 1 then args.nameLeft else args.nameRight} WINS`
				end
				key ..= "sub"
			end
		end
		if key ~= bannerKey then
			bannerKey = key
			setBanner(text, subText, color, subColor)
		end
	end

	return {
		gui = gui,
		update = function(args: Args)
			local now = os.clock()
			local dt = math.min(now - lastTime, 0.1)
			lastTime = now
			local view = args.view
			local rounds = view.phase >= Phase.Intro

			updateBar(barA, args.left, dt, args.nameLeft, args.winsLeft, rounds)
			updateBar(barB, args.right, dt, args.nameRight, args.winsRight, rounds)

			-- The plate shows the clock during a round match.
			local seconds = math.ceil(view.timer / FightConfig.SimHz)
			if rounds then
				if seconds ~= clockSeconds then
					clockSeconds = seconds
					clock.Text = tostring(seconds)
				end
				clock.TextColor3 = if seconds <= 10 and view.phase == Phase.Fight then WARN else Color3.new(1, 1, 1)
			elseif clockSeconds ~= -1 then
				clockSeconds = -1
				clock.Text = "VS"
				clock.TextColor3 = AMBER
			end

			banners(args)

			local low = rounds and view.phase == Phase.Fight and args.left.hp / args.left.stats.maxHp < DANGER_FRACTION
			local pulse = 0.82 - 0.14 * (0.5 + 0.5 * math.sin(now * 6))
			for _, edge in danger do
				edge.BackgroundTransparency = if low then pulse else 1
			end
		end,
		-- Compact layout for touch: narrower bars leave room for the training buttons, and the keyboard help goes away.
		setCompact = function(compact: boolean)
			compactLayout = compact
			layout()
			help.Visible = helpShown and not compact
		end,
		setHelp = function(visible: boolean)
			helpPinned = visible
			if visible ~= helpShown then
				setHelp(visible)
			end
		end,
		setShown = function(shown: boolean)
			root.Visible = shown
		end,
		setStats = function(text: string, color: Color3)
			stats.Text = text
			stats.TextColor3 = color
		end,
	}
end

return Hud
